// StreamAudioSource is just_audio's documented way to feed custom byte streams.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' show StreamAudioSource;

import '../../models/track.dart';
import 'connect_share.dart' show ShareTrack;
import 'connect_stream.dart';

/// Riflay Connect, stage 3: the direct connection that carries a shared song's audio from its owner.
///
/// Signaling (the offer, the answer and the ICE candidates) goes over the encrypted pair room of stage 1, as
/// `rtc.sig` messages: no new server. The audio then travels over one WebRTC data channel between the two
/// devices. Over it, a tiny request/response protocol:
///  * controller → owner, text: `{t:get, id, ref, s, e}`  "bytes [s, e) of the song `ref`"; `{t:stop, id}`
///  * owner → controller, text: `{t:head, id, len, ct}` the size and type, or `{t:no, id}` "not available";
///    then binary messages (4-byte id, then audio), then text `{t:end, id}`
/// The owner answers `get` only for songs [ConnectOwnership] lets it stream, and `ref` is a hash, never a path.

/// One message on a data channel: text or bytes.
class RtcData {
  const RtcData.text(String this.text) : bytes = null;
  const RtcData.binary(Uint8List this.bytes) : text = null;

  final String? text;
  final Uint8List? bytes;
}

/// An open data channel. [sendBinary] waits while the channel is backed up, so a whole song is never queued in
/// memory.
abstract class RtcLink {
  Stream<RtcData> get messages;
  Future<void> get closed;
  bool get isOpen;
  void sendText(String text);
  Future<void> sendBinary(Uint8List bytes);
  Future<void> close();
}

/// Brings up an [RtcLink] with a peer. [send] carries this side's signals to the other; [incoming] delivers the
/// other side's. Completes when the channel is open, throws if it can't be within [timeout].
typedef RtcOpener = Future<RtcLink> Function({
  required bool offerer,
  required ConnectIceConfig ice,
  required void Function(Map<String, dynamic> signal) send,
  required Stream<Map<String, dynamic>> incoming,
  required Duration timeout,
});

/// A piece of audio is this big, so a message stays well under what every WebRTC stack accepts.
const rtcChunkBytes = 16 * 1024;
const _maxStreamsPerLink = 4;

String rtcMimeOf(String path) => switch (path.split('.').last.toLowerCase()) {
  'flac' => 'audio/flac',
  'ogg' || 'oga' => 'audio/ogg',
  'opus' => 'audio/opus',
  'm4a' || 'aac' || 'mp4' => 'audio/mp4',
  'wav' => 'audio/wav',
  _ => 'audio/mpeg',
};

/// The owner's end of a data channel: answers range requests for the songs it may stream, and for nothing else.
class RtcRangeServer {
  RtcRangeServer(this.link, {required this.ownership, required this.library}) {
    _sub = link.messages.listen(_onMessage);
    unawaited(link.closed.then((_) => _close()));
  }

  final RtcLink link;
  final ConnectOwnership ownership;
  final List<Track> Function() library;
  late final StreamSubscription<RtcData> _sub;
  final _cancelled = <int>{};
  var _active = 0;

  void _close() {
    unawaited(_sub.cancel());
  }

  void _onMessage(RtcData m) {
    final text = m.text;
    if (text == null) return;
    final Object? j;
    try {
      j = jsonDecode(text);
    } catch (_) {
      return;
    }
    if (j is! Map<String, dynamic>) return;
    final id = j['id'];
    if (id is! int) return;
    if (j['t'] == 'stop') {
      _cancelled.add(id);
    } else if (j['t'] == 'get') {
      final ref = j['ref'], s = j['s'], e = j['e'];
      if (ref is! String || s is! int || s < 0 || (e != null && e is! int)) return _no(id);
      unawaited(_serve(id, ref, s, e as int?));
    }
  }

  void _no(int id) => link.sendText(jsonEncode({'t': 'no', 'id': id}));

  Future<void> _serve(int id, String ref, int start, int? end) async {
    // The one gate: a song that isn't marked as the owner's own is answered "no" before any file is opened.
    final track = ownership.streamable(ref, library());
    final path = track?.path;
    if (track == null || path == null || _active >= _maxStreamsPerLink) return _no(id);
    _active++;
    RandomAccessFile? file;
    try {
      file = await File(path).open();
      final total = await file.length();
      final to = (end ?? total).clamp(start, total);
      link.sendText(jsonEncode({'t': 'head', 'id': id, 'len': total, 'ct': rtcMimeOf(path)}));
      var at = start;
      await file.setPosition(start);
      while (at < to && link.isOpen && !_cancelled.contains(id)) {
        final bytes = await file.read(rtcChunkBytes < to - at ? rtcChunkBytes : to - at);
        if (bytes.isEmpty) break;
        final out = Uint8List(4 + bytes.length)
          ..buffer.asByteData().setUint32(0, id)
          ..setRange(4, 4 + bytes.length, bytes);
        await link.sendBinary(out);
        at += bytes.length;
      }
      if (link.isOpen) link.sendText(jsonEncode({'t': 'end', 'id': id}));
    } catch (e) {
      debugPrint('Riflay Connect: serving $ref failed: $e');
      if (link.isOpen) _no(id);
    } finally {
      _active--;
      _cancelled.remove(id);
      await file?.close();
    }
  }
}

/// Thrown when the owner won't stream a song (not marked as theirs, or it's gone) or the connection ended.
class RtcRangeRefused implements Exception {
  const RtcRangeRefused();
  @override
  String toString() => 'The other device did not stream this song.';
}

/// The controller's end: asks for ranges and hands the bytes on as a stream.
class RtcRangeClient {
  RtcRangeClient(this.link) {
    _sub = link.messages.listen(_onMessage);
    unawaited(link.closed.then((_) => _fail()));
  }

  final RtcLink link;
  late final StreamSubscription<RtcData> _sub;
  var _next = 1;
  final _heads = <int, Completer<ConnectRange>>{};
  final _bodies = <int, StreamController<List<int>>>{};

  bool get isOpen => link.isOpen;

  void _fail() {
    for (final c in _heads.values) {
      if (!c.isCompleted) c.completeError(const RtcRangeRefused());
    }
    for (final b in _bodies.values) {
      b.addError(const RtcRangeRefused());
      unawaited(b.close());
    }
    _heads.clear();
    _bodies.clear();
    unawaited(_sub.cancel());
  }

  void _onMessage(RtcData m) {
    final bytes = m.bytes;
    if (bytes != null) {
      if (bytes.length <= 4) return;
      final id = ByteData.sublistView(bytes).getUint32(0);
      _bodies[id]?.add(Uint8List.sublistView(bytes, 4));
      return;
    }
    final Object? j;
    try {
      j = jsonDecode(m.text ?? '');
    } catch (_) {
      return;
    }
    if (j is! Map<String, dynamic> || j['id'] is! int) return;
    final id = j['id'] as int;
    switch (j['t']) {
      case 'head':
        final len = j['len'], ct = j['ct'];
        final head = _heads.remove(id);
        if (head == null || len is! int || ct is! String) return;
        final body = _bodies[id]!;
        head.complete(ConnectRange(sourceLength: len, stream: body.stream, contentType: ct));
      case 'no':
        _heads.remove(id)?.completeError(const RtcRangeRefused());
        unawaited(_bodies.remove(id)?.close());
      case 'end':
        unawaited(_bodies.remove(id)?.close());
    }
  }

  /// Bytes [start, end) of the song `ref`. The stream ends when the range does; dropping it asks the owner to stop.
  Future<ConnectRange> fetch(String ref, int start, int? end) {
    final id = _next++;
    final head = _heads[id] = Completer<ConnectRange>();
    _bodies[id] = StreamController<List<int>>(
      onCancel: () {
        if (_bodies.remove(id) != null && link.isOpen) link.sendText(jsonEncode({'t': 'stop', 'id': id}));
      },
    );
    link.sendText(jsonEncode({'t': 'get', 'id': id, 'ref': ref, 's': start, 'e': end}));
    return head.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        _heads.remove(id);
        unawaited(_bodies.remove(id)?.close());
        throw const RtcRangeRefused();
      },
    );
  }
}

/// The hub for stage 3 on one device: it routes `rtc.sig` messages from the pair rooms, serves ranges when this
/// device is the owner, and keeps one connection per owner when it is the controller. One per app.
class ConnectRtc {
  ConnectRtc({
    required this.opener,
    required this.ownership,
    required this.library,
    this.ice = const ConnectIceConfig(),
    this.timeout = const Duration(seconds: 25),
  });

  static ConnectRtc? instance;

  final RtcOpener opener;
  final ConnectOwnership ownership;
  final List<Track> Function() library;
  ConnectIceConfig ice;
  final Duration timeout;

  final _send = <String, void Function(Map<String, dynamic>)>{};
  final _sessions = <String, StreamController<Map<String, dynamic>>>{};
  final _clients = <String, Future<RtcRangeClient>>{};
  var _n = 0;

  static bool isRtc(Map<String, dynamic> m) => m['t'] == 'rtc.sig';

  void attach(String peerId, void Function(Map<String, dynamic>) send) => _send[peerId] = send;

  void detach(String peerId) {
    _send.remove(peerId);
    _clients.remove(peerId)?.then((c) => c.link.close(), onError: (_) {});
  }

  /// A signal from [peerId]. A first `offer` from a paired device starts an answer: this is the owner's side.
  void handle(String peerId, Map<String, dynamic> m) {
    final sid = m['sid'], d = m['d'];
    final send = _send[peerId];
    if (sid is! String || sid.length > 40 || d is! Map<String, dynamic> || send == null) return;
    final key = '$peerId/$sid';
    var session = _sessions[key];
    if (session == null) {
      if (d['k'] != 'offer' || _sessions.length >= 8) return;
      session = _sessions[key] = StreamController<Map<String, dynamic>>();
      unawaited(_answer(peerId, sid, session, send));
    }
    session.add(d);
  }

  Future<void> _answer(
    String peerId,
    String sid,
    StreamController<Map<String, dynamic>> session,
    void Function(Map<String, dynamic>) send,
  ) async {
    try {
      final link = await opener(
        offerer: false,
        ice: ice,
        send: (d) => send({'t': 'rtc.sig', 'sid': sid, 'd': d}),
        incoming: session.stream,
        timeout: timeout,
      );
      RtcRangeServer(link, ownership: ownership, library: library);
    } catch (e) {
      debugPrint('Riflay Connect: answering $peerId failed: $e');
    }
  }

  /// A connection to the owner [peerId], brought up once and reused. Tries the routes in order (LAN, then
  /// STUN, then the person's own relay, if any) and throws [ConnectRouteException] when none works.
  Future<RtcRangeClient> client(String peerId) {
    final cached = _clients[peerId];
    if (cached != null) {
      return cached.then((c) => c.isOpen ? c : _fresh(peerId), onError: (_) => _fresh(peerId));
    }
    return _fresh(peerId);
  }

  Future<RtcRangeClient> _fresh(String peerId) {
    final f = _clients[peerId] = _connect(peerId);
    f.ignore();
    return f;
  }

  Future<RtcRangeClient> _connect(String peerId) async {
    final send = _send[peerId];
    if (send == null) throw const ConnectRouteException(ConnectRouteFailure.noRoute);
    // There is no LAN link in Riflay Connect yet: the first route tried is STUN, then TURN if one is set up.
    Future<RtcRangeClient?> via(ConnectIceConfig config) async {
      final sid = '${DateTime.now().microsecondsSinceEpoch}-${_n++}';
      final incoming = _sessions['$peerId/$sid'] = StreamController<Map<String, dynamic>>();
      try {
        final link = await opener(
          offerer: true,
          ice: config,
          send: (d) => send({'t': 'rtc.sig', 'sid': sid, 'd': d}),
          incoming: incoming.stream,
          timeout: timeout,
        );
        return RtcRangeClient(link);
      } finally {
        _sessions.remove('$peerId/$sid');
        unawaited(incoming.close());
      }
    }

    final result = await connectViaBestRoute<RtcRangeClient>({
      ConnectRoute.stun: () => via(ConnectIceConfig(stun: ice.stun)),
      if (ice.hasTurn) ConnectRoute.turn: () => via(ice),
    });
    if (result.connection == null) throw ConnectRouteException(result.failure!);
    return result.connection!;
  }

  /// A song of [peerId] as just_audio plays it.
  StreamAudioSource sourceFor(String peerId, String ref, {Object? tag}) => ConnectStreamSource(
    ref,
    tag: tag,
    fetch: (ref, start, end) async => (await client(peerId)).fetch(ref, start, end),
  );
}

/// No route worked: the page says so and suggests the same network.
class ConnectRouteException implements Exception {
  const ConnectRouteException(this.failure);
  final ConnectRouteFailure failure;
  @override
  String toString() => 'Riflay Connect: no route to the other device ($failure)';
}

/// A shared song as a queue entry: the address names the owner and the song, and nothing in it is a path.
const connectTrackScheme = 'riflay-connect';

Track connectTrackOf(String peerId, ShareTrack t) => Track(
  id: 'connect:$peerId:${t.ref}',
  uri: Uri(scheme: connectTrackScheme, host: 'owner', pathSegments: [peerId, t.ref!]),
  title: t.title,
  artist: t.artist,
);

/// The owner and song a [connectTrackOf] entry names, or null for any other track.
({String peerId, String ref})? connectTrackParts(Track t) {
  if (t.uri.scheme != connectTrackScheme || t.uri.pathSegments.length != 2) return null;
  return (peerId: t.uri.pathSegments[0], ref: t.uri.pathSegments[1]);
}
