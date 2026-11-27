import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../listen_together/internet.dart';
import '../listen_together/protocol.dart' show SharedTrack;
import 'connect_channel.dart';
import 'connect_protocol.dart';
import 'connect_share.dart';
import 'connect_store.dart';

enum ConnectLinkState { disconnected, connecting, connected }

/// Why pairing didn't work, for the screen to say in words.
enum ConnectPairProblem { badCode, unreachable, notFound, denied }

class ConnectPairException implements Exception {
  const ConnectPairException(this.problem);
  final ConnectPairProblem problem;
  @override
  String toString() => 'ConnectPairException($problem)';
}

/// The controller's side of Riflay Connect: pairs with a desktop, then keeps one connection to the room of that
/// pairing, sends commands and shows the state the desktop reports. It never plays anything itself.
///
/// When the connection drops, or the desktop goes quiet, [state] becomes [ConnectLinkState.disconnected] and it
/// tries again after a growing wait ([connectBackoff]) until [disconnect] is called.
class ConnectController extends ChangeNotifier {
  ConnectController({
    Future<ConnectStore> Function()? openStore,
    ConnectLinkOpener? opener,
    this.deviceName = 'Riflay',
    Random? random,
    int Function()? clock,
    this.pairTimeout = connectPairingWindow,
    this.hostSilence = connectHostSilence,
    this.syncEvery = connectSyncEvery,
    Duration Function(int attempt)? backoff,
  }) : _openStore = openStore ?? ConnectStore.open,
       _open = opener ?? openConnectLink,
       _random = random ?? Random.secure(),
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
       _backoff = backoff ?? connectBackoff;

  static final instance = ConnectController(deviceName: defaultConnectDeviceName());

  final Future<ConnectStore> Function() _openStore;
  final ConnectLinkOpener _open;
  final Random _random;
  final int Function() _clock;
  final Duration Function(int) _backoff;
  final Duration pairTimeout;
  final Duration hostSilence;
  final Duration syncEvery;

  /// What this device calls itself when it asks to pair (the OS name and a few characters, never an account).
  final String deviceName;

  /// Sharing collections over the same room; the screen sets it (it needs the player).
  ConnectShare? share;

  ConnectStore? _store;
  var _loaded = false;
  var _hosts = <ConnectPeer>[];
  ConnectPeer? _active;
  var _state = ConnectLinkState.disconnected;
  ConnectState? _remote;
  int _remoteAt = 0;
  int _n = 0;
  int _attempts = 0;
  int _session = 0;
  ConnectLink? _link;
  ConnectChannel? _channel;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _retry, _keepAlive, _silence;

  bool get loaded => _loaded;

  /// Desktops this device is paired with.
  List<ConnectPeer> get hosts => List.unmodifiable(_hosts);

  /// The desktop being controlled (or being reached), if any.
  ConnectPeer? get active => _active;

  ConnectLinkState get state => _state;

  /// The last state the desktop reported; kept while disconnected so the screen doesn't empty.
  ConnectState? get remote => _remote;

  /// How far the current song is now, counted on from the last report.
  Duration get position => _remote?.positionAt(_clock(), _remoteAt) ?? Duration.zero;

  Future<void> load() async {
    if (_loaded) return;
    final store = _store = await _openStore();
    _hosts = store.hosts;
    _loaded = true;
    notifyListeners();
  }

  // --- Pairing -----------------------------------------------------------------------------------------------

  /// Pairs with the desktop showing [input] (a typed code or a scanned link) and starts controlling it. Throws
  /// [ConnectPairException]; waits for the desktop's owner to confirm, up to [pairTimeout].
  Future<void> pair(String input) async {
    if (!_loaded) await load();
    final code = connectCodeFrom(input);
    final broker = code == null ? null : brokerForCode(code);
    if (code == null || broker == null) throw const ConnectPairException(ConnectPairProblem.badCode);
    final keys = ConnectKeys.pairing(code);
    final peerId = newConnectPeerId();
    final mine = ConnectPairingKey.generate(_random);
    final ConnectLink link;
    try {
      link = await _open(broker);
    } catch (e) {
      debugPrint('Riflay Connect: ${broker.host}: $e');
      throw const ConnectPairException(ConnectPairProblem.unreachable);
    }
    final reply = Completer<Map<String, dynamic>>();
    final listening = link.messages.listen((e) {
      if (e.$1 != keys.pairingTo(peerId) || reply.isCompleted) return;
      final m = ConnectChannel.decode(keys.key, e.$1, e.$2);
      if (m != null) reply.complete(m);
    });
    try {
      link.subscribe(keys.pairingTo(peerId));
      final topic = keys.pairingFrom(peerId);
      link.publish(
        topic,
        ConnectChannel.encode(keys.key, topic, {
          't': 'hello',
          'v': connectProtocolVersion,
          'name': deviceName,
          'pub': base64Of(mine.publicKey),
        }),
      );
      final Map<String, dynamic> answer;
      try {
        answer = await Future.any([
          reply.future,
          link.down.then<Map<String, dynamic>>((_) => throw const ConnectPairException(ConnectPairProblem.unreachable)),
        ]).timeout(pairTimeout);
      } on TimeoutException {
        throw const ConnectPairException(ConnectPairProblem.notFound);
      }
      if (answer['t'] == 'deny') throw const ConnectPairException(ConnectPairProblem.denied);
      final secret = _openGrant(answer, mine, code);
      if (secret == null) throw const ConnectPairException(ConnectPairProblem.notFound);
      final name = cleanConnectName(answer['name']);
      final host = ConnectPeer(
        id: newConnectPeerId(),
        name: name,
        secret: secret,
        broker: internetBrokers.indexOf(broker),
        addedAtMs: _clock(),
      );
      _hosts = [..._hosts, host];
      await _store!.saveHosts(_hosts);
      notifyListeners();
      await connect(host);
    } finally {
      await listening.cancel();
      await link.close();
    }
  }

  Uint8List? _openGrant(Map<String, dynamic> m, ConnectPairingKey mine, String code) {
    if (m['t'] != 'grant') return null;
    final theirs = bytesOfBase64(m['pub']), box = bytesOfBase64(m['box']);
    if (theirs == null || box == null) return null;
    final shared = mine.agree(theirs, code);
    if (shared == null) return null;
    final opened = InternetCrypto.decrypt(shared, 'grant', box, nowMs: _clock());
    final secret = bytesOfBase64(opened?.message);
    return secret != null && secret.length == connectSecretLength ? secret : null;
  }

  /// Forgets a desktop on this device. (The desktop still lists the pairing until its owner removes it.)
  Future<void> forget(ConnectPeer host) async {
    if (_active?.id == host.id) disconnect();
    _hosts = [..._hosts.where((h) => h.id != host.id)];
    share?.forget(host.id);
    await _store?.saveHosts(_hosts);
    notifyListeners();
  }

  // --- Connection --------------------------------------------------------------------------------------------

  /// Starts controlling [host] and keeps trying to reach it until [disconnect].
  Future<void> connect(ConnectPeer host) async {
    _stop();
    _active = host;
    _remote = null;
    _attempts = 0;
    final session = ++_session;
    _state = ConnectLinkState.connecting;
    notifyListeners();
    await _reach(host, session);
  }

  /// Stops controlling; the desktop carries on playing.
  void disconnect() {
    _session++;
    _stop();
    _active = null;
    _remote = null;
    _state = ConnectLinkState.disconnected;
    notifyListeners();
  }

  void _stop() {
    if (_active case final host?) share?.detach(host.id);
    _retry?.cancel();
    _keepAlive?.cancel();
    _silence?.cancel();
    unawaited(_sub?.cancel());
    unawaited(_channel?.close());
    final link = _link;
    _link = null;
    _channel = null;
    _sub = null;
    if (link != null) unawaited(link.close());
  }

  Future<void> _reach(ConnectPeer host, int session) async {
    try {
      final link = await _open(internetBrokers[host.broker]);
      if (session != _session) return unawaited(link.close());
      _link = link;
      final keys = ConnectKeys.paired(host.secret);
      final channel = _channel = ConnectChannel(
        link,
        keys.key,
        sendTopic: keys.toHost,
        receiveTopic: keys.toController,
      );
      share?.attach(host.id, host.name, channel.send);
      _sub = channel.messages.listen((m) => _onMessage(m, session));
      unawaited(link.down.then((_) => _dropped(session)));
      // Connected means the desktop answered, not that the broker did: until then we don't know it's there.
      _send(const ConnectSync());
      _keepAlive = Timer.periodic(syncEvery, (_) => _send(const ConnectSync()));
      _armSilence(session);
    } catch (e) {
      debugPrint('Riflay Connect: ${internetBrokers[host.broker].host}: $e');
      if (session == _session) _dropped(session);
    }
  }

  void _armSilence(int session) {
    _silence?.cancel();
    _silence = Timer(hostSilence, () => _dropped(session));
  }

  void _onMessage(Map<String, dynamic> m, int session) {
    if (session != _session) return;
    final host = _active;
    if (host != null && ConnectShare.isShare(m)) return unawaited(share?.handle(host.id, m) ?? Future.value());
    switch (m['t']) {
      case 'state':
        final s = ConnectState.fromJson(m);
        if (s == null) return;
        _remote = s;
        _remoteAt = _clock();
        _attempts = 0;
        _armSilence(session);
        if (_state != ConnectLinkState.connected) _state = ConnectLinkState.connected;
        if (host != null) share?.heard(host.id);
        notifyListeners();
      case 'revoked':
        // The desktop's owner removed this device: the pairing is over, so don't keep knocking.
        if (host != null) unawaited(forget(host));
    }
  }

  void _dropped(int session) {
    if (session != _session || _active == null) return;
    final host = _active!;
    _stop();
    _state = ConnectLinkState.disconnected;
    notifyListeners();
    _retry = Timer(_backoff(_attempts++), () {
      if (session != _session) return;
      _state = ConnectLinkState.connecting;
      notifyListeners();
      unawaited(_reach(host, session));
    });
  }

  // --- Commands ----------------------------------------------------------------------------------------------

  /// False when not connected: a command sent into the void would only look like it worked.
  bool send(ConnectCommand command) {
    if (_state != ConnectLinkState.connected) return false;
    _send(command);
    return true;
  }

  void _send(ConnectCommand command) {
    // Increasing, and in step with the clock, so a recorded command can't be replayed after a newer one.
    _n = max(_n + 1, _clock());
    _channel?.send({...command.toJson(), 'n': _n});
  }

  bool play() => send(const ConnectPlay());
  bool pause() => send(const ConnectPause());
  bool next() => send(const ConnectNext());
  bool previous() => send(const ConnectPrevious());
  bool seek(Duration to) => send(ConnectSeek(to.inMilliseconds));
  bool setVolume(double level) => send(ConnectVolume(level.clamp(0.0, 1.0)));
  bool setShuffle(bool on) => send(ConnectShuffle(on));
  bool setRepeat(ConnectRepeat mode) => send(ConnectSetRepeat(mode));
  bool addToQueue(SharedTrack track) => send(ConnectAdd(track));

  @override
  void dispose() {
    _session++;
    _stop();
    super.dispose();
  }
}
