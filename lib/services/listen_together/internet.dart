import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:pointycastle/export.dart';
import 'package:typed_data/typed_data.dart' show Uint8Buffer;

import 'lan.dart';
import 'transport.dart';

/// Listen together over the internet, with no server of ours: a free public MQTT broker is only the meeting
/// point. Everything on it is end-to-end encrypted with a key made from the session code, so the broker sees
/// random bytes on a random-looking topic.
///
/// The code is 10 characters from [lanCodeAlphabet]. The first one picks the broker (its index in the alphabet
/// is an index into [internetBrokers]), the other nine are random. People see it as `ABCDE-FGHJK`.
///
/// Topics, all under `riflay/l1/<room>/`:
///  * `p`          retained presence, published by the host (an encrypted "open"), so a guest can tell the room
///                 exists. The host's last will, and a clean stop, replace it with an empty retained payload.
///  * `t/<peerId>` host → one guest.
///  * `g/<peerId>` one guest → host (the host subscribes to `g/+`).
///
/// Payload: 12-byte random nonce, then AES-256-GCM(ciphertext + tag) of `{"ts": <ms>, "m": "<message>"}` (and
/// `"id": <peerId>` on the `t/` and `g/` topics). The full topic is the GCM associated data, so a message can't
/// be replayed on another topic. Messages that fail to decrypt, or whose `ts` is more than two minutes off, are
/// dropped.

/// A public broker with TLS.
class InternetBroker {
  const InternetBroker(this.host, this.port);

  final String host;
  final int port;
}

/// The index of a broker is part of every session code, so only ever append to this list. Checked against the
/// real brokers; test.mosquitto.org (8886) reset every connection when this was written, so it isn't here.
const internetBrokers = [InternetBroker('broker.emqx.io', 8883), InternetBroker('broker.hivemq.com', 8883)];

/// Characters in a session code for the internet.
const internetCodeLength = 10;

/// Messages older or newer than this (against our clock) are dropped as replays.
const internetMaxSkew = Duration(minutes: 2);

/// The host re-announces the room this often, so the retained presence never goes stale.
const internetPresenceEvery = Duration(seconds: 60);

/// A guest that has said nothing (the session layer pings every 30 s) for this long is dropped by the host.
const internetGuestIdle = Duration(seconds: 75);

class InternetException implements Exception {
  const InternetException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// No broker could be reached.
class InternetUnreachable extends InternetException {
  const InternetUnreachable()
    : super('Couldn\'t reach the listening servers. Check your internet connection and try again.');
}

/// A broker answered, but nobody is hosting this code.
class InternetRoomNotFound extends InternetException {
  const InternetRoomNotFound() : super('Couldn\'t find that session. Check the code.');
}

// ───────────────────────────── Codes ─────────────────────────────

/// A fresh code for a room on `internetBrokers[brokerIndex]`.
String newInternetCode(int brokerIndex, [Random? random]) {
  assert(brokerIndex >= 0 && brokerIndex < internetBrokers.length);
  final r = random ?? Random.secure();
  return String.fromCharCodes([
    lanCodeAlphabet.codeUnitAt(brokerIndex),
    for (var i = 1; i < internetCodeLength; i++) lanCodeAlphabet.codeUnitAt(r.nextInt(lanCodeAlphabet.length)),
  ]);
}

/// "ABCDE-FGHJK" for a 10-character code; anything else comes back unchanged.
String formatInternetCode(String code) =>
    code.length == internetCodeLength ? '${code.substring(0, 5)}-${code.substring(5)}' : code;

/// The broker a (normalized) internet code points to, or null when the code isn't one of ours.
InternetBroker? brokerForCode(String code) {
  if (code.length != internetCodeLength || code.split('').any((c) => !lanCodeAlphabet.contains(c))) return null;
  final index = lanCodeAlphabet.indexOf(code[0]);
  return index < internetBrokers.length ? internetBrokers[index] : null;
}

/// What someone typed or pasted, as the 6-character Wi-Fi code or the 10-character internet code: upper case,
/// without spaces and hyphens. Null when it is neither.
String? normalizeCode(String input) {
  final code = input.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
  if (code.length == 6 && code.split('').every(lanCodeAlphabet.contains)) return code;
  if (brokerForCode(code) != null) return code;
  return null;
}

Uri internetJoinLink(String code) =>
    Uri(scheme: 'riflay', host: 'listen', queryParameters: {'code': code, 'via': 'internet'});

// ───────────────────────────── Keys and payloads ─────────────────────────────

/// Everything derived from a code: where the room is and the key that opens its messages.
class InternetRoomKeys {
  InternetRoomKeys._(this.room, this.key);

  factory InternetRoomKeys.of(String code) {
    final room = crypto.sha256
        .convert(utf8.encode('riflay-listen-v1/topic/$code'))
        .bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .substring(0, 32);
    final kdf = HKDFKeyDerivator(SHA256Digest())
      ..init(
        HkdfParameters(Uint8List.fromList(utf8.encode(code)), 32, utf8.encode('riflay-listen-v1'), utf8.encode('key')),
      );
    final key = Uint8List(32);
    kdf.deriveKey(null, 0, key, 0);
    return InternetRoomKeys._(room, key);
  }

  /// 32 hex characters, the random-looking part of every topic.
  final String room;

  /// AES-256 key.
  final Uint8List key;

  String get _base => 'riflay/l1/$room';
  String get presenceTopic => '$_base/p';
  String toGuestTopic(String peerId) => '$_base/t/$peerId';
  String fromGuestTopic(String peerId) => '$_base/g/$peerId';
  String get fromGuestsFilter => '$_base/g/+';

  /// The peer id at the end of a `g/` topic, or null for any other topic.
  String? guestOf(String topic) {
    final prefix = '$_base/g/';
    if (!topic.startsWith(prefix)) return null;
    final id = topic.substring(prefix.length);
    return RegExp(r'^[a-z0-9]{12}$').hasMatch(id) ? id : null;
  }
}

/// One decrypted payload.
typedef InternetPayload = ({String message, String? id});

abstract final class InternetCrypto {
  static const nonceLength = 12;

  static Uint8List encrypt(Uint8List key, String topic, String message, {String? id, int? nowMs, Random? random}) {
    final r = random ?? Random.secure();
    final nonce = Uint8List.fromList([for (var i = 0; i < nonceLength; i++) r.nextInt(256)]);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List.fromList(utf8.encode(topic))));
    final plain = utf8.encode(
      jsonEncode({'ts': nowMs ?? DateTime.now().millisecondsSinceEpoch, 'm': message, 'id': ?id}),
    );
    return Uint8List.fromList([...nonce, ...cipher.process(Uint8List.fromList(plain))]);
  }

  /// Null for anything that isn't ours, was altered, is for another topic, or is stale.
  static InternetPayload? decrypt(Uint8List key, String topic, Uint8List data, {int? nowMs}) {
    if (data.length < nonceLength + 16) return null;
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(
            KeyParameter(key),
            128,
            Uint8List.sublistView(data, 0, nonceLength),
            Uint8List.fromList(utf8.encode(topic)),
          ),
        );
      final plain = cipher.process(Uint8List.sublistView(data, nonceLength));
      final json = jsonDecode(utf8.decode(plain));
      if (json is! Map<String, dynamic>) return null;
      final ts = json['ts'], m = json['m'], id = json['id'];
      if (ts is! int || m is! String || (id != null && id is! String)) return null;
      final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
      if ((now - ts).abs() > internetMaxSkew.inMilliseconds) return null;
      return (message: m, id: id as String?);
    } catch (_) {
      // Wrong key, tampered, malformed: all the same to us.
      return null;
    }
  }
}

String _randomId([int length = 12]) {
  final r = Random.secure();
  return [for (var i = 0; i < length; i++) r.nextInt(36).toRadixString(36)].join();
}

// ───────────────────────────── The broker connection ─────────────────────────────

/// One TLS connection to a broker.
class _Link {
  _Link._(this._client);

  final MqttServerClient _client;
  final messages = StreamController<(String, Uint8List)>.broadcast();
  final _down = Completer<void>();
  var _closing = false;

  /// Completes when the connection is gone, however it ended.
  Future<void> get down => _down.future;

  bool get isUp => _client.connectionStatus?.state == MqttConnectionState.connected;

  /// Throws when the broker can't be reached or refuses. [will] (topic) is cleared (empty, retained) if the
  /// connection dies without a goodbye.
  static Future<_Link> open(
    InternetBroker broker, {
    String? will,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final client = MqttServerClient.withPort(broker.host, 'riflay-${_randomId(16)}', broker.port)
      ..secure = true
      ..keepAlivePeriod = 30
      ..autoReconnect = false
      ..logging(on: false)
      ..setProtocolV311();
    var message = MqttConnectMessage().withClientIdentifier(client.clientIdentifier).startClean();
    if (will != null) {
      message = message.withWillTopic(will).withWillMessage('').withWillQos(MqttQos.atLeastOnce).withWillRetain();
    }
    client.connectionMessage = message;
    final link = _Link._(client);
    client.onDisconnected = link._onDown;
    try {
      await client.connect().timeout(timeout);
    } catch (_) {
      client.disconnect();
      rethrow;
    }
    if (!link.isUp) {
      client.disconnect();
      throw const InternetUnreachable();
    }
    client.updates!.listen((batch) {
      for (final m in batch) {
        final payload = m.payload;
        if (payload is! MqttPublishMessage) continue;
        if (!link.messages.isClosed) link.messages.add((m.topic, Uint8List.fromList(payload.payload.message)));
      }
    });
    return link;
  }

  void _onDown() {
    if (!_down.isCompleted) _down.complete();
    if (!messages.isClosed) unawaited(messages.close());
  }

  void subscribe(String topic) => _client.subscribe(topic, MqttQos.atLeastOnce);

  void publish(String topic, Uint8List data, {bool retain = false}) {
    if (!isUp) return;
    try {
      _client.publishMessage(topic, MqttQos.atLeastOnce, Uint8Buffer()..addAll(data), retain: retain);
    } catch (e) {
      debugPrint('Listen together (internet): publish: $e');
    }
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    // Let what was just published leave the socket first.
    if (isUp) await Future<void>.delayed(const Duration(milliseconds: 250));
    _client.disconnect();
    _onDown();
  }
}

// ───────────────────────────── Host ─────────────────────────────

class _InternetPeer implements ListenPeer {
  _InternetPeer(this.id, this._host) {
    _idle = Timer(internetGuestIdle, close);
  }

  @override
  final String id;
  final InternetHostTransport _host;
  final _in = StreamController<String>();
  late Timer _idle;

  @override
  Stream<String> get incoming => _in.stream;

  void heard(String text) {
    if (_in.isClosed) return;
    _idle.cancel();
    _idle = Timer(internetGuestIdle, close);
    _in.add(text);
  }

  @override
  void send(String message) => _host._sendTo(id, message);

  @override
  Future<void> close() async {
    _idle.cancel();
    _host._peerGone(id);
    if (!_in.isClosed) await _in.close();
  }
}

/// The host side over the internet.
class InternetHostTransport implements ListenHostTransport {
  InternetHostTransport({this.maxGuests = 16, Random? random}) : _random = random ?? Random.secure();

  final int maxGuests;
  final Random _random;

  final _peers = StreamController<ListenPeer>.broadcast();
  final _open = <String, _InternetPeer>{};
  _Link? _link;
  InternetRoomKeys? _keys;
  String? _code;
  Timer? _presence;
  StreamSubscription<(String, Uint8List)>? _sub;
  var _stopped = false;

  /// Ten characters, e.g. "K7Q2XM9HTA". Known after [start].
  @override
  String get code => formatInternetCode(_code!);

  /// The code as the broker index is encoded in it, without the hyphen.
  String get rawCode => _code!;

  @override
  Uri get joinLink => internetJoinLink(_code!);

  @override
  Stream<ListenPeer> get peers => _peers.stream;

  @override
  Future<void> start() async {
    final order = List<int>.generate(internetBrokers.length, (i) => i)..shuffle(_random);
    for (final index in order) {
      final code = newInternetCode(index, _random);
      final keys = InternetRoomKeys.of(code);
      try {
        _link = await _Link.open(internetBrokers[index], will: keys.presenceTopic);
        _code = code;
        _keys = keys;
        break;
      } catch (e) {
        debugPrint('Listen together (internet): ${internetBrokers[index].host}: $e');
      }
    }
    final link = _link;
    if (link == null) throw const InternetUnreachable();
    _sub = link.messages.stream.listen(_onMessage);
    unawaited(
      link.down.then((_) {
        if (!_stopped) unawaited(stop());
      }),
    );
    link.subscribe(_keys!.fromGuestsFilter);
    _announce();
    _presence = Timer.periodic(internetPresenceEvery, (_) => _announce());
  }

  void _announce() {
    final keys = _keys!;
    _link?.publish(keys.presenceTopic, InternetCrypto.encrypt(keys.key, keys.presenceTopic, 'open'), retain: true);
  }

  void _onMessage((String, Uint8List) event) {
    final keys = _keys!;
    final id = keys.guestOf(event.$1);
    if (id == null || event.$2.isEmpty) return;
    final payload = InternetCrypto.decrypt(keys.key, event.$1, event.$2);
    if (payload == null || payload.id != id) return;
    var peer = _open[id];
    if (peer == null) {
      if (_open.length >= maxGuests || _peers.isClosed) return;
      peer = _open[id] = _InternetPeer(id, this);
      _peers.add(peer);
    }
    peer.heard(payload.message);
  }

  void _sendTo(String id, String message) {
    final keys = _keys;
    if (keys == null || _stopped) return;
    final topic = keys.toGuestTopic(id);
    _link?.publish(topic, InternetCrypto.encrypt(keys.key, topic, message, id: id));
  }

  void _peerGone(String id) => _open.remove(id);

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _presence?.cancel();
    final keys = _keys, link = _link;
    if (keys != null) link?.publish(keys.presenceTopic, Uint8List(0), retain: true);
    await _sub?.cancel();
    for (final p in _open.values.toList()) {
      unawaited(p.close());
    }
    _open.clear();
    if (!_peers.isClosed) await _peers.close();
    await link?.close();
  }
}

// ───────────────────────────── Guest ─────────────────────────────

class InternetGuestConnection implements ListenGuestConnection {
  InternetGuestConnection._(this._link, this._keys, this._peerId) {
    _sub = _link.messages.stream.listen(_onMessage, onDone: _end);
    _link.down.then((_) => _end());
  }

  final _Link _link;
  final InternetRoomKeys _keys;
  final String _peerId;
  final _in = StreamController<String>();
  StreamSubscription<(String, Uint8List)>? _sub;

  @override
  Stream<String> get incoming => _in.stream;

  /// Joins the room [code] (a normalized 10-character code). Throws [InternetUnreachable] when the broker can't
  /// be reached and [InternetRoomNotFound] when nobody hosts the code (no presence within [timeout]).
  static Future<InternetGuestConnection> connect(String code, {Duration timeout = const Duration(seconds: 12)}) async {
    final broker = brokerForCode(code);
    if (broker == null) throw const InternetRoomNotFound();
    final keys = InternetRoomKeys.of(code);
    final peerId = _randomId();
    final _Link link;
    try {
      link = await _Link.open(broker, timeout: timeout);
    } catch (e) {
      debugPrint('Listen together (internet): ${broker.host}: $e');
      throw const InternetUnreachable();
    }
    final present = Completer<void>();
    final toMe = <String>[];
    final sub = link.messages.stream.listen((event) {
      if (event.$1 == keys.presenceTopic) {
        if (!present.isCompleted && InternetCrypto.decrypt(keys.key, event.$1, event.$2)?.message == 'open') {
          present.complete();
        }
      } else if (event.$1 == keys.toGuestTopic(peerId)) {
        // Can't happen before our Hello, but never lose one.
        final p = InternetCrypto.decrypt(keys.key, event.$1, event.$2);
        if (p != null && p.id == peerId) toMe.add(p.message);
      }
    });
    link.subscribe(keys.toGuestTopic(peerId));
    link.subscribe(keys.presenceTopic);
    try {
      await Future.any([present.future, link.down.then((_) => throw const InternetUnreachable())]).timeout(timeout);
    } on TimeoutException {
      await sub.cancel();
      await link.close();
      throw const InternetRoomNotFound();
    } catch (_) {
      await sub.cancel();
      await link.close();
      rethrow;
    }
    await sub.cancel();
    final conn = InternetGuestConnection._(link, keys, peerId);
    for (final m in toMe) {
      conn._in.add(m);
    }
    return conn;
  }

  void _onMessage((String, Uint8List) event) {
    if (event.$1 == _keys.presenceTopic) {
      // The host's goodbye (or last will): the room is closed.
      if (event.$2.isEmpty) _end();
      return;
    }
    if (event.$1 != _keys.toGuestTopic(_peerId)) return;
    final payload = InternetCrypto.decrypt(_keys.key, event.$1, event.$2);
    if (payload == null || payload.id != _peerId || _in.isClosed) return;
    _in.add(payload.message);
  }

  void _end() {
    if (!_in.isClosed) unawaited(_in.close());
  }

  @override
  void send(String message) {
    final topic = _keys.fromGuestTopic(_peerId);
    _link.publish(topic, InternetCrypto.encrypt(_keys.key, topic, message, id: _peerId));
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    _end();
    await _link.close();
  }
}
