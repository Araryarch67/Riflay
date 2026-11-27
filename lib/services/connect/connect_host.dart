import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;

import '../listen_together/internet.dart';
import '../player_controller.dart';
import 'connect_channel.dart';
import 'connect_protocol.dart';
import 'connect_store.dart';

/// What the desktop reports about its player. Titles and artists are tags and a hash tells rows apart, so no
/// file path, folder or account is in it ([ConnectTrack.of]).
ConnectState connectSnapshot(PlayerController p, {int? nowMs}) {
  final queue = p.queue;
  return ConnectState(
    playing: p.showsPlaying,
    track: p.currentTrack == null ? null : ConnectTrack.of(p.currentTrack!),
    positionMs: p.position.inMilliseconds,
    durationMs: p.duration?.inMilliseconds,
    volume: p.volume.clamp(0.0, 1.0),
    canSetVolume: p.canSetVolume,
    shuffle: p.shuffle,
    repeat: switch (p.loopMode) {
      LoopMode.off => ConnectRepeat.off,
      LoopMode.all => ConnectRepeat.all,
      LoopMode.one => ConnectRepeat.one,
    },
    queue: [for (final t in queue.take(connectQueueLimit)) ConnectTrack.of(t)],
    queueIndex: p.queueIndex,
    atMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
  );
}

/// Applies a controller's command through the one [PlayerController] the rest of the app uses, so casting, the
/// saved volume, Listen together and the queue rules all behave as if someone pressed the button here. Never
/// throws: a bad command is the controller's problem, not a reason for the desktop to stop playing.
Future<void> applyConnectCommand(PlayerController p, ConnectCommand command) async {
  try {
    switch (command) {
      case ConnectSync():
        break;
      case ConnectPlay():
        if (p.hasQueue) await p.play();
      case ConnectPause():
        await p.pause();
      case ConnectNext():
        if (p.hasNext) await p.next();
      case ConnectPrevious():
        if (p.hasQueue) await p.previous();
      case ConnectSeek(:final ms):
        if (p.currentTrack == null) return;
        final end = p.duration;
        await p.seek(Duration(milliseconds: end == null ? ms : min(ms, end.inMilliseconds)));
      case ConnectVolume(:final level):
        if (p.canSetVolume) await p.setVolume(level);
      case ConnectShuffle(:final on):
        if (p.hasQueue && p.shuffle != on) await p.toggleShuffle();
      case ConnectSetRepeat(:final mode):
        // Cycling is the only way the controller changes it; three presses reach any mode.
        for (var i = 0; i < 3 && p.loopMode.name != mode.name; i++) {
          await p.cycleLoopMode();
        }
      case ConnectAdd(:final track):
        await p.addToQueue([track.toTrack()]);
    }
  } catch (e) {
    debugPrint('Riflay Connect: command ${command.runtimeType}: $e');
  }
}

/// A controller asking to be paired, waiting for the desktop's owner to say yes or no.
class ConnectPairRequest {
  const ConnectPairRequest(this.name, this.peerId, this.publicKey);

  /// What the controller calls itself, cleaned up.
  final String name;
  final String peerId;
  final Uint8List publicKey;
}

class _Room {
  _Room(this.peer);

  final ConnectPeer peer;
  ConnectChannel? channel;
  StreamSubscription<Map<String, dynamic>>? sub;

  /// The highest command number applied: a replayed or reordered command with a lower number is ignored.
  int lastN = 0;
  DateTime? lastSeen;
}

class _Broker {
  _Broker(this.index);

  final int index;
  ConnectLink? link;
  StreamSubscription<(String, Uint8List)>? pairSub;
  Timer? retry;
  int attempts = 0;
  bool connecting = false;
}

/// The desktop's side of Riflay Connect: stays reachable on the public broker while "Allow remote control" is on,
/// pairs controllers the owner confirms, and applies their commands. With nobody paired, or nobody sending, it
/// does nothing to playback, and playback never depends on this being connected.
class ConnectHost extends ChangeNotifier {
  ConnectHost(
    this.player, {
    Future<ConnectStore> Function()? openStore,
    ConnectLinkOpener? opener,
    this.deviceName = 'Riflay',
    Random? random,
    int Function()? clock,
    this.stateDelay = const Duration(milliseconds: 300),
    Duration Function(int attempt)? backoff,
  }) : _openStore = openStore ?? ConnectStore.open,
       _open = opener ?? openConnectLink,
       _random = random ?? Random.secure(),
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
       _backoff = backoff ?? connectBackoff;

  static final _instances = Expando<ConnectHost>('ConnectHost');

  static ConnectHost of(PlayerController c) => _instances[c] ??= ConnectHost(c, deviceName: defaultConnectDeviceName());

  /// Makes [host] the one [of] returns for [c] (tests with a made-up broker).
  @visibleForTesting
  static void use(PlayerController c, ConnectHost host) => _instances[c] = host;

  final PlayerController player;
  final Future<ConnectStore> Function() _openStore;
  final ConnectLinkOpener _open;
  final Random _random;
  final int Function() _clock;
  final Duration Function(int) _backoff;
  final Duration stateDelay;

  /// What a pairing controller sees as this computer's name; the OS name, never a user or account name.
  final String deviceName;

  ConnectStore? _store;
  var _enabled = false;
  var _loaded = false;
  var _disposed = false;
  final _rooms = <String, _Room>{};
  final _brokers = <int, _Broker>{};
  Timer? _push;

  String? _pairCode;
  ConnectKeys? _pairKeys;
  int _pairBroker = 0;
  Timer? _pairExpiry;
  ConnectPairRequest? _pending;
  bool _unreachable = false;

  /// Settings are read; [enabled] and [controllers] are meaningful.
  bool get loaded => _loaded;

  /// "Allow remote control" is on.
  bool get enabled => _enabled;

  /// Paired controllers, newest last.
  List<ConnectPeer> get controllers => [for (final r in _rooms.values) r.peer];

  /// Heard from within the last minute.
  bool isActive(String id) {
    final seen = _rooms[id]?.lastSeen;
    return seen != null && DateTime.now().difference(seen) < connectControllerIdle;
  }

  /// The code to show while a pairing is open, formatted; null otherwise.
  String? get pairingCode => _pairCode == null ? null : formatInternetCode(_pairCode!);

  /// The text a QR for the open pairing carries.
  Uri? get pairingLink => _pairCode == null ? null : connectPairingLink(_pairCode!);

  /// Someone entered the code and is waiting for [approve] or [deny].
  ConnectPairRequest? get pending => _pending;

  /// The broker couldn't be reached; the host keeps trying.
  bool get unreachable => _unreachable && _enabled;

  /// Reads the saved settings and, when remote control was left on, starts listening. Call once at start-up.
  Future<void> load() async {
    if (_loaded) return;
    final store = _store = await _openStore();
    if (_disposed) return;
    for (final p in store.controllers) {
      _rooms[p.id] = _Room(p);
    }
    _loaded = true;
    notifyListeners();
    if (store.hostEnabled) await setEnabled(true, remember: false);
  }

  Future<void> setEnabled(bool on, {bool remember = true}) async {
    if (!_loaded) await load();
    if (on == _enabled) return;
    _enabled = on;
    if (remember) await _store!.setHostEnabled(on);
    if (on) {
      player.addListener(_playerChanged);
      for (final r in _rooms.values) {
        _ensureBroker(r.peer.broker);
      }
    } else {
      player.removeListener(_playerChanged);
      _push?.cancel();
      _closePairing();
      for (final b in _brokers.values.toList()) {
        _drop(b);
      }
      _brokers.clear();
      for (final r in _rooms.values) {
        unawaited(r.sub?.cancel());
        unawaited(r.channel?.close());
        r.channel = null;
      }
      _unreachable = false;
    }
    notifyListeners();
  }

  // --- Pairing -----------------------------------------------------------------------------------------------

  /// Opens a pairing: a new code that works once, for [connectPairingWindow]. Turns remote control on.
  Future<void> beginPairing() async {
    if (!_enabled) await setEnabled(true);
    _closePairing();
    _pairBroker = _random.nextInt(internetBrokers.length);
    final code = newInternetCode(_pairBroker, _random);
    _pairCode = code;
    _pairKeys = ConnectKeys.pairing(code);
    _pairExpiry = Timer(connectPairingWindow, cancelPairing);
    final b = _ensureBroker(_pairBroker);
    if (b.link?.isUp ?? false) _listenForPairing(b);
    notifyListeners();
  }

  void cancelPairing() {
    if (_pairCode == null) return;
    _closePairing();
    notifyListeners();
  }

  void _closePairing() {
    _pairExpiry?.cancel();
    _pairExpiry = null;
    _pairCode = null;
    _pairKeys = null;
    _pending = null;
    for (final b in _brokers.values) {
      unawaited(b.pairSub?.cancel());
      b.pairSub = null;
    }
  }

  void _listenForPairing(_Broker b) {
    final keys = _pairKeys, link = b.link;
    if (keys == null || link == null || b.index != _pairBroker) return;
    unawaited(b.pairSub?.cancel());
    link.subscribe(keys.pairingFromControllers);
    b.pairSub = link.messages.listen((e) {
      final peer = keys.pairingPeerOf(e.$1);
      if (peer == null) return;
      final m = ConnectChannel.decode(keys.key, e.$1, e.$2);
      if (m == null || m['t'] != 'hello') return;
      final pub = bytesOfBase64(m['pub']);
      // One request at a time: the code is for one controller.
      if (_pending != null || pub == null || pub.length != 65) return;
      _pending = ConnectPairRequest(cleanConnectName(m['name']), peer, pub);
      notifyListeners();
    });
  }

  /// The owner said yes: this controller gets its own secret, sent under a key only the two of them can make.
  Future<void> approve() async {
    final request = _pending, keys = _pairKeys, code = _pairCode, link = _brokers[_pairBroker]?.link;
    if (request == null || keys == null || code == null || link == null || !link.isUp) return;
    final mine = ConnectPairingKey.generate(_random);
    final shared = mine.agree(request.publicKey, code);
    if (shared == null) return deny();
    final secret = newConnectSecret(_random);
    final topic = keys.pairingTo(request.peerId);
    link.publish(
      topic,
      ConnectChannel.encode(keys.key, topic, {
        't': 'grant',
        'v': connectProtocolVersion,
        'pub': base64Of(mine.publicKey),
        'box': base64Of(InternetCrypto.encrypt(shared, 'grant', base64Of(secret), random: _random)),
        'name': deviceName,
      }),
    );
    final peer = ConnectPeer(
      id: newConnectPeerId(),
      name: request.name,
      secret: secret,
      broker: _pairBroker,
      addedAtMs: _clock(),
    );
    _rooms[peer.id] = _Room(peer);
    await _store!.saveControllers(controllers);
    _closePairing();
    _attach(_brokers[peer.broker]!, _rooms[peer.id]!);
    notifyListeners();
  }

  void deny() {
    final request = _pending, keys = _pairKeys, link = _brokers[_pairBroker]?.link;
    if (request != null && keys != null && link != null) {
      final topic = keys.pairingTo(request.peerId);
      link.publish(topic, ConnectChannel.encode(keys.key, topic, {'t': 'deny'}));
    }
    // A refused code is spent: someone guessing codes gets one try per code.
    _closePairing();
    notifyListeners();
  }

  /// Takes a controller's access away: it is told, its secret is forgotten here, and its room is no longer read.
  Future<void> revoke(String id) async {
    final room = _rooms.remove(id);
    if (room == null) return;
    room.channel?.send({'t': 'revoked'});
    await room.sub?.cancel();
    await room.channel?.close();
    await _store!.saveControllers(controllers);
    notifyListeners();
  }

  // --- Brokers -----------------------------------------------------------------------------------------------

  _Broker _ensureBroker(int index) {
    final b = _brokers.putIfAbsent(index, () => _Broker(index));
    if (b.link == null && !b.connecting && b.retry == null) unawaited(_connect(b));
    return b;
  }

  Future<void> _connect(_Broker b) async {
    b.connecting = true;
    b.retry?.cancel();
    b.retry = null;
    try {
      final link = await _open(internetBrokers[b.index]);
      if (!_enabled || _brokers[b.index] != b) {
        unawaited(link.close());
        return;
      }
      b.link = link;
      b.attempts = 0;
      _unreachable = false;
      for (final r in _rooms.values.where((r) => r.peer.broker == b.index)) {
        _attach(b, r);
      }
      _listenForPairing(b);
      unawaited(link.down.then((_) => _lost(b, link)));
      notifyListeners();
    } catch (e) {
      debugPrint('Riflay Connect: ${internetBrokers[b.index].host}: $e');
      if (_enabled && _brokers[b.index] == b) {
        _unreachable = true;
        _retryLater(b);
        notifyListeners();
      }
    } finally {
      b.connecting = false;
    }
  }

  void _retryLater(_Broker b) {
    b.retry?.cancel();
    b.retry = Timer(_backoff(b.attempts++), () {
      b.retry = null;
      if (_enabled && _brokers[b.index] == b) unawaited(_connect(b));
    });
  }

  void _lost(_Broker b, ConnectLink link) {
    if (b.link != link) return;
    b.link = null;
    unawaited(b.pairSub?.cancel());
    b.pairSub = null;
    for (final r in _rooms.values.where((r) => r.peer.broker == b.index)) {
      unawaited(r.sub?.cancel());
      unawaited(r.channel?.close());
      r.channel = null;
    }
    if (!_enabled || _brokers[b.index] != b) return;
    _unreachable = true;
    _retryLater(b);
    notifyListeners();
  }

  void _drop(_Broker b) {
    b.retry?.cancel();
    unawaited(b.pairSub?.cancel());
    final link = b.link;
    b.link = null;
    if (link != null) unawaited(link.close());
  }

  void _attach(_Broker b, _Room r) {
    final link = b.link;
    if (link == null) return;
    final keys = ConnectKeys.paired(r.peer.secret);
    final channel = r.channel = ConnectChannel(link, keys.key, sendTopic: keys.toController, receiveTopic: keys.toHost);
    r.sub = channel.messages.listen((m) => unawaited(_onMessage(r, m)));
  }

  // --- Commands and state ------------------------------------------------------------------------------------

  Future<void> _onMessage(_Room room, Map<String, dynamic> m) async {
    final n = m['n'], command = ConnectCommand.fromJson(m);
    if (n is! int || command == null || n <= room.lastN) return;
    room.lastN = n;
    room.lastSeen = DateTime.now();
    await applyConnectCommand(player, command);
    // A reply to a sync is what keeps a controller sure we are here; a command's result follows through the
    // player's own notification, but a no-op command (pause while paused) would otherwise get no answer.
    _send(room);
    notifyListeners();
  }

  void _playerChanged() {
    if (_rooms.values.every((r) => r.channel == null)) return;
    _push?.cancel();
    _push = Timer(stateDelay, () {
      for (final r in _rooms.values) {
        if (isActive(r.peer.id)) _send(r);
      }
    });
  }

  void _send(_Room room) => room.channel?.send(connectSnapshot(player, nowMs: _clock()).toJson());

  @override
  void dispose() {
    _disposed = true;
    unawaited(setEnabled(false, remember: false));
    super.dispose();
  }
}
