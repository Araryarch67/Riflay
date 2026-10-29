import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/track.dart';
import '../player_controller.dart';
import 'internet.dart';
import 'lan.dart';
import 'protocol.dart';
import 'transport.dart';

/// What [ListenTogether.host] and [ListenTogether.join] throw; [message] is the calm sentence also in `problem`.
class ListenException implements Exception {
  const ListenException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum ListenRole { none, host, guest }

enum ListenMode { wifi, internet }

/// The decisions a guest makes, as plain functions so they can be tested without a player.
abstract final class ListenSync {
  /// A guest further than this from the host is moved.
  static const driftLimitMs = 750;

  /// How many of the host's next songs are shared.
  static const upNextCount = 5;

  /// Samples of the clock offset kept; the one with the shortest round trip is the most accurate.
  static const clockWindow = 8;

  /// `hostClock - guestClock`, from one Ping/Pong: the host answered halfway through the round trip.
  static int offsetOf({required int pingAtMs, required int hostAtMs, required int pongReceivedAtMs}) {
    final rtt = pongReceivedAtMs - pingAtMs;
    return hostAtMs - (pingAtMs + rtt ~/ 2);
  }

  /// Where the guest should be now.
  static int targetMs(PlaybackState state, {required int guestNowMs, required int offsetMs}) =>
      max(0, state.positionAt(guestNowMs + offsetMs));

  static bool driftTooBig(int currentMs, int targetMs) => (currentMs - targetMs).abs() > driftLimitMs;

  /// The guest has to load a different song.
  static bool songDiffers(String? current, SharedTrack? shared) => shared != null && shared.videoId != current;
}

/// Keeps the clock offset from the lowest-RTT sample among the latest few.
class ClockSync {
  final _samples = <({int rtt, int offset})>[];

  /// `hostClock - guestClock`; 0 until the first answer.
  int get offsetMs => _samples.isEmpty ? 0 : (_samples.reduce((a, b) => b.rtt < a.rtt ? b : a)).offset;

  int? get bestRttMs => _samples.isEmpty ? null : _samples.map((s) => s.rtt).reduce(min);

  void add({required int pingAtMs, required int hostAtMs, required int pongReceivedAtMs}) {
    final rtt = pongReceivedAtMs - pingAtMs;
    if (rtt < 0) return;
    _samples.add((
      rtt: rtt,
      offset: ListenSync.offsetOf(pingAtMs: pingAtMs, hostAtMs: hostAtMs, pongReceivedAtMs: pongReceivedAtMs),
    ));
    if (_samples.length > ListenSync.clockWindow) _samples.removeAt(0);
  }
}

/// One session at a time: this device hosts it, or follows someone's. All state is here; the UI listens.
class ListenTogether extends ChangeNotifier {
  ListenTogether(this.player);

  static final _instances = Expando<ListenTogether>('ListenTogether');

  static ListenTogether of(PlayerController c) => _instances[c] ??= ListenTogether(c);

  final PlayerController player;

  /// Over the internet through public MQTT brokers (no server of ours). Shipped as Beta.
  static bool get internetAvailable => true;

  /// Which kind of session a code someone typed belongs to: 10 characters is the internet, 6 is the same Wi-Fi.
  /// Null when it is neither.
  static ListenMode? modeForCode(String input) => switch (normalizeCode(input)?.length) {
    internetCodeLength => ListenMode.internet,
    6 => ListenMode.wifi,
    _ => null,
  };

  ListenRole _role = ListenRole.none;
  ListenMode? _mode;
  String? _code;
  Uri? _joinLink;
  String? _hostName;
  String? _ownName;
  List<String> _listeners = const [];
  var _suggestionsAllowed = true;
  SharedTrack? _hostTrack;
  List<SharedTrack> _upNext = const [];
  var _hostPlayingUnshareable = false;
  String? _problem;
  final _events = StreamController<String>.broadcast();

  ListenRole get role => _role;
  ListenMode? get mode => _mode;
  String? get code => _code;
  Uri? get joinLink => _joinLink;

  /// Guest: who you follow. Host: your own name.
  String? get hostName => _hostName;
  List<String> get listeners => List.unmodifiable(_listeners);
  bool get suggestionsAllowed => _suggestionsAllowed;
  SharedTrack? get hostTrack => _hostTrack;
  List<SharedTrack> get upNext => List.unmodifiable(_upNext);
  bool get hostPlayingUnshareable => _hostPlayingUnshareable;

  /// One calm sentence, or null.
  String? get problem => _problem;

  /// "Ana joined", "Ana left", "Ana suggested Song", "You left the listening session".
  Stream<String> get events => _events.stream;

  // Shared plumbing.
  final _subs = <StreamSubscription<Object?>>[];
  Timer? _tick;
  var _busy = false;

  // Host side.
  ListenHostTransport? _transport;
  final _peers = <ListenPeer, String?>{}; // name once the Hello arrived
  Timer? _broadcastSoon;

  // Guest side.
  ListenGuestConnection? _conn;
  final _clock = ClockSync();
  Timer? _pingTimer;
  PlaybackState? _pending;
  var _applying = false;
  String? _lastVideoId;
  Timer? _foreignCheck;
  var _nearEnd = false;
  Completer<Welcome>? _welcome;

  static final String _guestId = _randomId();

  static String _randomId() {
    final r = Random.secure();
    return [for (var i = 0; i < 12; i++) r.nextInt(36).toRadixString(36)].join();
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;

  void _setProblem(String? text) {
    _problem = text;
    notifyListeners();
  }

  /// Sets [problem] and throws, so a caller that awaits can react too.
  Never _fail(String text) {
    _setProblem(text);
    throw ListenException(text);
  }

  void _emit(String text) {
    if (!_events.isClosed) _events.add(text);
  }

  // ───────────────────────────── Host ─────────────────────────────

  Future<void> host({required ListenMode mode, required String name}) async {
    if (_role != ListenRole.none || _busy) return;
    _busy = true;
    _problem = null;
    final ListenHostTransport transport = mode == ListenMode.internet
        ? InternetHostTransport()
        : LanHostTransport(name: name);
    try {
      await transport.start();
    } catch (e) {
      debugPrint('Listen together: can\'t host: $e');
      try {
        await transport.stop();
      } catch (_) {}
      _busy = false;
      _fail(
        mode == ListenMode.internet
            ? const InternetUnreachable().message
            : 'Couldn\'t start a session. Check that you\'re connected to Wi-Fi.',
      );
    }
    _busy = false;
    _transport = transport;
    _role = ListenRole.host;
    _mode = mode;
    _code = transport.code;
    _joinLink = transport.joinLink;
    _hostName = name;
    _ownName = name;
    _listeners = const [];
    _suggestionsAllowed = true;
    _subs.add(transport.peers.listen(_onPeer, onDone: _onTransportEnded));
    final p = player.player;
    _subs.add(
      p.sequenceStateStream
          .distinct(
            (a, b) =>
                a.currentSource?.tag == b.currentSource?.tag &&
                listEquals(a.sequence.map((s) => s.tag).toList(), b.sequence.map((s) => s.tag).toList()),
          )
          .listen((_) => _broadcastSoonDebounced()),
    );
    _subs.add(p.playingStream.distinct().listen((_) => _broadcastSoonDebounced()));
    _subs.add(p.positionDiscontinuityStream.listen((_) => _broadcastSoonDebounced()));
    _tick = Timer.periodic(const Duration(seconds: 5), (_) => _broadcastState());
    notifyListeners();
  }

  void _onTransportEnded() {
    if (_role == ListenRole.host) {
      _problem = 'The session stopped. Start it again to keep listening together.';
      unawaited(_teardown());
    }
  }

  void _onPeer(ListenPeer peer) {
    _peers[peer] = null;
    // A connection that never says who it is is dropped.
    Timer(const Duration(seconds: 10), () {
      if (_peers.containsKey(peer) && _peers[peer] == null) _drop(peer);
    });
    peer.incoming.listen(
      (text) => _onGuestMessage(peer, text),
      onDone: () => _dropped(peer),
      onError: (Object e) => debugPrint('Listen together: guest: $e'),
    );
  }

  void _drop(ListenPeer peer) {
    unawaited(peer.close().catchError((Object _) {}));
    _dropped(peer);
  }

  void _dropped(ListenPeer peer) {
    if (!_peers.containsKey(peer)) return;
    final name = _peers.remove(peer);
    if (name == null || _role != ListenRole.host) return;
    _emit('$name left');
    _sendGuests();
  }

  List<String> get _guestNames => [for (final n in _peers.values) ?n];

  void _onGuestMessage(ListenPeer peer, String text) {
    if (_role != ListenRole.host) return;
    final message = ListenMessage.decode(text);
    switch (message) {
      case Hello(:final name):
        if (_peers[peer] != null) return;
        final clean = name.trim().isEmpty ? 'Someone' : name.trim();
        _peers[peer] = clean.length > 30 ? clean.substring(0, 30) : clean;
        peer.send(Welcome(hostName: _ownName!, guests: _guestNames, suggestionsAllowed: _suggestionsAllowed).encode());
        peer.send(_currentState().encode());
        _emit('${_peers[peer]} joined');
        _sendGuests();
      case Ping():
        if (_peers.containsKey(peer)) peer.send(Pong(pingAtMs: message.atMs, hostAtMs: _now()).encode());
      case Suggest(:final track):
        final from = _peers[peer];
        if (from == null || !_suggestionsAllowed) return;
        unawaited(player.playNext([track.toTrack()]));
        _emit('$from suggested ${track.title}');
      case Bye():
        _drop(peer);
      default:
    }
  }

  void _sendGuests() {
    final names = _guestNames;
    _listeners = names;
    notifyListeners();
    final text = Guests(names).encode();
    for (final e in _peers.entries) {
      if (e.value != null) e.key.send(text);
    }
  }

  Future<void> setSuggestionsAllowed(bool v) async {
    if (_role != ListenRole.host || v == _suggestionsAllowed) return;
    _suggestionsAllowed = v;
    notifyListeners();
    for (final e in _peers.entries) {
      if (e.value != null) {
        e.key.send(Welcome(hostName: _ownName!, guests: _guestNames, suggestionsAllowed: v).encode());
      }
    }
  }

  PlaybackState _currentState() {
    final current = player.currentTrack;
    final queue = player.queue;
    var upNext = <SharedTrack>[];
    if (current != null) {
      final at = queue.indexWhere((t) => t.id == current.id);
      if (at >= 0) {
        upNext = [for (final t in queue.skip(at + 1)) ?SharedTrack.of(t)].take(ListenSync.upNextCount).toList();
      }
    }
    return PlaybackState(
      track: current == null ? null : SharedTrack.of(current),
      playing: current != null && player.isPlaying,
      positionMs: player.position.inMilliseconds,
      sentAtMs: _now(),
      upNext: upNext,
    );
  }

  void _broadcastSoonDebounced() {
    _broadcastSoon?.cancel();
    _broadcastSoon = Timer(const Duration(milliseconds: 150), _broadcastState);
  }

  void _broadcastState() {
    if (_role != ListenRole.host || _peers.isEmpty) return;
    final text = _currentState().encode();
    for (final e in _peers.entries) {
      if (e.value != null) e.key.send(text);
    }
  }

  // ───────────────────────────── Guest ─────────────────────────────

  Stream<List<FoundSession>> findNearby() => LanDiscovery.find();

  /// Joins by code. The kind of session comes from the code itself ([modeForCode]); [mode] is ignored.
  Future<void> join({required String code, required String name, ListenMode mode = ListenMode.wifi}) async {
    if (_role != ListenRole.none || _busy) return;
    final normalized = normalizeCode(code);
    final over = normalized != null && normalized.length == internetCodeLength ? ListenMode.internet : ListenMode.wifi;
    _busy = true;
    _problem = null;
    notifyListeners();
    final ListenGuestConnection conn;
    try {
      conn = over == ListenMode.internet
          ? await InternetGuestConnection.connect(normalized!)
          : await LanGuestConnection.connect(code);
    } on InternetException catch (e) {
      debugPrint('Listen together: can\'t join: $e');
      _busy = false;
      _fail(e.message);
    } catch (e) {
      debugPrint('Listen together: can\'t join: $e');
      _busy = false;
      _fail('Couldn\'t find that session. Check the code and that you\'re on the same Wi-Fi.');
    }
    final welcome = _welcome = Completer<Welcome>();
    _conn = conn;
    _ownName = name;
    _code = over == ListenMode.internet ? formatInternetCode(normalized!) : normalizeLanCode(code);
    _mode = over;
    _lastVideoId = player.currentTrack?.videoId;
    _subs.add(
      conn.incoming.listen(
        _onHostMessage,
        onDone: () {
          if (!welcome.isCompleted) welcome.completeError(StateError('closed'));
          _onHostGone();
        },
        onError: (Object e) => debugPrint('Listen together: host: $e'),
      ),
    );
    conn.send(Hello(name: name, guestId: _guestId).encode());
    try {
      final w = await welcome.future.timeout(const Duration(seconds: 8));
      _busy = false;
      if (_conn != conn) return; // closed meanwhile
      _role = ListenRole.guest;
      player.holdAutoplay = true;
      _hostName = w.hostName;
      _listeners = w.guests;
      _suggestionsAllowed = w.suggestionsAllowed;
      _joinLink = over == ListenMode.internet ? internetJoinLink(normalized!) : lanJoinLink(_code!);
      _watchOwnChanges();
      _startPings();
      notifyListeners();
    } catch (e) {
      debugPrint('Listen together: no welcome: $e');
      _busy = false;
      if (_conn == conn) {
        await _teardown();
        _fail('That session isn\'t answering. Try again in a moment.');
      }
    }
  }

  void _startPings() {
    var sent = 0;
    void ping() => _conn?.send(Ping(_now()).encode());
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(milliseconds: 400), (t) {
      ping();
      if (++sent >= 5) {
        t.cancel();
        _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) => ping());
      }
    });
    ping();
  }

  void _onHostMessage(String text) {
    final message = ListenMessage.decode(text);
    switch (message) {
      case Welcome():
        if (_welcome?.isCompleted == false) {
          _welcome!.complete(message);
        } else if (_role == ListenRole.guest) {
          _hostName = message.hostName;
          _listeners = message.guests;
          _suggestionsAllowed = message.suggestionsAllowed;
          notifyListeners();
        }
      case Guests(:final names):
        _listeners = names;
        notifyListeners();
      case Pong():
        _clock.add(pingAtMs: message.pingAtMs, hostAtMs: message.hostAtMs, pongReceivedAtMs: _now());
      case PlaybackState():
        if (_role != ListenRole.guest) return;
        _pending = message;
        if (!_applying) unawaited(_applyPending());
      case Bye():
        final host = _hostName ?? 'The host';
        _emit('$host ended the listening session');
        unawaited(_teardown());
      default:
    }
  }

  void _onHostGone() {
    if (_role == ListenRole.none && _conn == null) return;
    if (_role == ListenRole.guest) {
      final internet = _mode == ListenMode.internet;
      unawaited(_teardown());
      _setProblem(
        internet
            ? 'The session ended or the connection dropped.'
            : 'Lost the connection to the host. Join again to keep listening.',
      );
    }
  }

  Future<void> _applyPending() async {
    _applying = true;
    try {
      while (_pending != null && _role == ListenRole.guest) {
        final state = _pending!;
        _pending = null;
        await _apply(state);
      }
    } catch (e) {
      debugPrint('Listen together: sync: $e');
    } finally {
      _applying = false;
    }
  }

  Future<void> _apply(PlaybackState s) async {
    _hostTrack = s.track;
    _upNext = s.upNext;
    _hostPlayingUnshareable = s.track == null && s.playing;
    notifyListeners();
    final shared = s.track;
    if (shared == null) {
      if (s.playing || player.isPlaying) await player.pause();
      return;
    }
    int target() => ListenSync.targetMs(s, guestNowMs: _now(), offsetMs: _clock.offsetMs);
    if (ListenSync.songDiffers(player.currentTrack?.videoId, shared)) {
      _lastVideoId = shared.videoId;
      await player.playList([shared.toTrack()], 0, from: 'Listening together');
      // The load took a while; the target is computed from the clock now, so it already includes that time.
      if (_pending != null) return; // a newer state arrived while loading
      await player.seek(Duration(milliseconds: s.playing ? target() : s.positionMs));
      if (!s.playing) await player.pause();
      return;
    }
    final here = player.position.inMilliseconds;
    if (s.playing) {
      final to = target();
      if (ListenSync.driftTooBig(here, to)) await player.seek(Duration(milliseconds: to));
      if (!player.isPlaying) unawaited(player.play());
    } else {
      if (player.isPlaying) await player.pause();
      if (ListenSync.driftTooBig(here, s.positionMs)) await player.seek(Duration(milliseconds: s.positionMs));
    }
  }

  /// A guest that starts another song leaves: only the host chooses what plays.
  void _watchOwnChanges() {
    _subs.add(
      player.player.positionStream.listen((pos) {
        final d = player.player.duration;
        _nearEnd = d != null && d - pos < const Duration(seconds: 5);
      }),
    );
    _subs.add(
      player.player.sequenceStateStream.listen((_) {
        if (_role != ListenRole.guest) return;
        final id = player.currentTrack?.videoId;
        if (id == _lastVideoId) return;
        final expected = _hostTrack?.videoId;
        final previous = _lastVideoId;
        _lastVideoId = id;
        if (_applying || id == expected) return;
        // The song ended and the player moved on (autoplay): the host's next state corrects it.
        if (_nearEnd && previous != null) {
          _foreignCheck?.cancel();
          _foreignCheck = Timer(const Duration(seconds: 8), () {
            if (_role == ListenRole.guest && player.currentTrack?.videoId != _hostTrack?.videoId) _leftByChoosing();
          });
          return;
        }
        _leftByChoosing();
      }),
    );
  }

  void _leftByChoosing() {
    _emit('You left the listening session');
    unawaited(leave());
  }

  Future<void> suggest(Track track) async {
    if (_role != ListenRole.guest) return;
    final shared = SharedTrack.of(track);
    if (shared == null) {
      _setProblem('Only songs from YouTube Music can be suggested.');
      return;
    }
    if (!_suggestionsAllowed) {
      _setProblem('The host isn\'t taking suggestions right now.');
      return;
    }
    _problem = null;
    _conn?.send(Suggest(shared, from: _ownName ?? 'Someone').encode());
    notifyListeners();
  }

  // ───────────────────────────── Ending ─────────────────────────────

  /// Host: ends the session for everyone. Guest: stops following.
  Future<void> leave() async {
    if (_role == ListenRole.host) {
      final bye = const Bye().encode();
      for (final p in _peers.keys) {
        p.send(bye);
      }
    } else if (_role == ListenRole.guest) {
      _conn?.send(const Bye().encode());
    }
    await _teardown();
  }

  Future<void> _teardown() async {
    final wasGuest = _role == ListenRole.guest;
    _role = ListenRole.none;
    player.holdAutoplay = false;
    _mode = null;
    _tick?.cancel();
    _pingTimer?.cancel();
    _broadcastSoon?.cancel();
    _foreignCheck?.cancel();
    _tick = _pingTimer = _broadcastSoon = _foreignCheck = null;
    final subs = List.of(_subs);
    _subs.clear();
    for (final s in subs) {
      unawaited(s.cancel());
    }
    final peers = _peers.keys.toList();
    _peers.clear();
    final transport = _transport, conn = _conn;
    _transport = null;
    _conn = null;
    _pending = null;
    _welcome = null;
    _code = null;
    _joinLink = null;
    _hostName = null;
    _ownName = null;
    _listeners = const [];
    _hostTrack = null;
    _upNext = const [];
    _hostPlayingUnshareable = false;
    notifyListeners();
    for (final p in peers) {
      unawaited(p.close().catchError((Object _) {}));
    }
    try {
      await conn?.close();
      await transport?.stop();
    } catch (e) {
      debugPrint('Listen together: closing: $e');
    }
    if (wasGuest) _busy = false;
  }

  @override
  void dispose() {
    _events.close();
    unawaited(_teardown());
    super.dispose();
  }
}
