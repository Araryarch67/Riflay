import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import '../../platform/host.dart';
import '../listen_together/internet.dart';

/// The encrypted channel Riflay Connect runs on. Later stages (sharing a collection, streaming owned files) open
/// more channels the same way: same brokers, same AES-GCM, a secret both sides hold.
///
/// Two kinds of secret:
///  * a **pairing code** (the 10 characters of [newInternetCode]), used once, to meet and to ask the desktop's
///    owner for permission. Everything in the pairing room is encrypted with a key made from the code, and the
///    long-lived secret is never sent under that key alone: it goes under an ECDH key from fresh key pairs, so
///    someone who records the broker traffic and later guesses the code still can't read it.
///  * a **pair secret**, 32 random bytes made by the desktop at confirmation, one per controller. The room and
///    the key come from it, so nobody can guess the topic, and removing it from the desktop closes that room.
///
/// Topics, under `riflay/c1/<room>/`:
///  * pairing room: `g/<peerId>` controller → desktop, `t/<peerId>` desktop → controller.
///  * pair room: `c` controller → desktop, `h` desktop → controller.
///
/// The topic is the GCM associated data ([InternetCrypto]), so a message can't be replayed on another topic, and
/// messages more than two minutes off are dropped.

const connectNamespace = 'riflay-connect-v1';
const connectTopicBase = 'riflay/c1';

/// How long a pairing code works. The desktop's owner has this long to say yes.
const connectPairingWindow = Duration(minutes: 5);

/// A pair secret is 256 random bits.
const connectSecretLength = 32;

/// A controller asks for the state this often; the desktop only pushes to controllers heard from within
/// [connectControllerIdle], and a controller silent for [connectHostSilence] counts the desktop as gone.
const connectSyncEvery = Duration(seconds: 20);
const connectControllerIdle = Duration(seconds: 60);
const connectHostSilence = Duration(seconds: 50);

/// The wait before try number [attempt] (0 for the first retry) to reach a broker again: 2 s, 4 s, 8 s … up to
/// a minute, so a broker that is down isn't hammered by every paired device.
Duration connectBackoff(int attempt) => Duration(seconds: min(60, 2 << min(attempt, 5)));

/// Where a code or secret puts everything on the broker.
class ConnectKeys {
  ConnectKeys._(this._keys);

  /// The pairing room of a code.
  factory ConnectKeys.pairing(String code) => ConnectKeys._(
    InternetRoomKeys.fromSecret(utf8.encode('pair/$code'), label: connectNamespace, base: connectTopicBase),
  );

  /// The room of a paired controller.
  factory ConnectKeys.paired(Uint8List secret) =>
      ConnectKeys._(InternetRoomKeys.fromSecret(secret, label: connectNamespace, base: connectTopicBase));

  final InternetRoomKeys _keys;

  /// AES-256 key of every message in the room.
  Uint8List get key => _keys.key;

  /// The part of the topic that looks random.
  String get room => _keys.room;

  // Pair room.
  String get toHost => _keys.topic('c');
  String get toController => _keys.topic('h');

  // Pairing room.
  String get pairingFromControllers => _keys.topic('g/+');
  String pairingFrom(String peerId) => _keys.topic('g/$peerId');
  String pairingTo(String peerId) => _keys.topic('t/$peerId');

  /// The peer id at the end of a pairing `g/` topic, or null for any other topic.
  String? pairingPeerOf(String topic) {
    final prefix = _keys.topic('g/');
    if (!topic.startsWith(prefix)) return null;
    final id = topic.substring(prefix.length);
    return RegExp(r'^[a-z0-9]{12}$').hasMatch(id) ? id : null;
  }
}

/// A fresh pair secret.
Uint8List newConnectSecret([Random? random]) {
  final r = random ?? Random.secure();
  return Uint8List.fromList([for (var i = 0; i < connectSecretLength; i++) r.nextInt(256)]);
}

/// One side's key pair for the pairing handshake (P-256), thrown away once pairing ends.
class ConnectPairingKey {
  ConnectPairingKey._(this._private, this.publicKey);

  final BigInt _private;

  /// The uncompressed point, 65 bytes.
  final Uint8List publicKey;

  static final _params = ECCurve_secp256r1();

  factory ConnectPairingKey.generate([Random? random]) {
    final r = random ?? Random.secure();
    final rng = FortunaRandom()..seed(KeyParameter(Uint8List.fromList([for (var i = 0; i < 32; i++) r.nextInt(256)])));
    final pair = (ECKeyGenerator()..init(ParametersWithRandom(ECKeyGeneratorParameters(_params), rng)))
        .generateKeyPair();
    final priv = pair.privateKey, pub = pair.publicKey;
    return ConnectPairingKey._(priv.d!, pub.Q!.getEncoded(false));
  }

  /// The AES key both sides get from their own private key and the other's public one, bound to [code] so a
  /// handshake can't be moved to another pairing. Null when [peerPublic] isn't a point on the curve.
  Uint8List? agree(Uint8List peerPublic, String code) {
    final point = _decodeOnCurve(peerPublic);
    if (point == null) return null;
    final shared = ECDHBasicAgreement()..init(ECPrivateKey(_private, _params));
    final x = shared.calculateAgreement(ECPublicKey(point, _params));
    final bytes = _bigToBytes(x, 32);
    final kdf = HKDFKeyDerivator(SHA256Digest())
      ..init(HkdfParameters(bytes, 32, utf8.encode(code), utf8.encode('$connectNamespace/grant')));
    final key = Uint8List(32);
    kdf.deriveKey(null, 0, key, 0);
    return key;
  }

  // NIST P-256: y^2 = x^3 - 3x + b (mod p).
  static final _p = BigInt.parse('ffffffff00000001000000000000000000000000ffffffffffffffffffffffff', radix: 16);
  static final _b = BigInt.parse('5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b', radix: 16);

  static ECPoint? _decodeOnCurve(Uint8List bytes) {
    if (bytes.length != 65 || bytes[0] != 4) return null;
    final x = _bytesToBig(bytes.sublist(1, 33)), y = _bytesToBig(bytes.sublist(33));
    if (x >= _p || y >= _p) return null;
    // A point off the curve would leak bits of our private key (invalid-curve attack).
    if ((y * y) % _p != (x * x * x - BigInt.from(3) * x + _b) % _p) return null;
    return _params.curve.createPoint(x, y);
  }

  static BigInt _bytesToBig(List<int> b) => b.fold(BigInt.zero, (n, byte) => (n << 8) | BigInt.from(byte));

  static Uint8List _bigToBytes(BigInt n, int length) {
    final out = Uint8List(length);
    for (var i = length - 1; i >= 0; i--) {
      out[i] = (n & BigInt.from(0xff)).toInt();
      n >>= 8;
    }
    return out;
  }
}

/// A connection to a broker, as Connect needs it. [InternetLink] is the real one; tests use a made-up broker.
abstract class ConnectLink {
  Stream<(String, Uint8List)> get messages;

  /// Completes when the connection is gone, however it ended.
  Future<void> get down;

  bool get isUp;
  void subscribe(String topic);
  void publish(String topic, Uint8List data);
  Future<void> close();
}

typedef ConnectLinkOpener = Future<ConnectLink> Function(InternetBroker broker);

class _MqttConnectLink implements ConnectLink {
  _MqttConnectLink(this._link);

  final InternetLink _link;

  @override
  Stream<(String, Uint8List)> get messages => _link.messages.stream;
  @override
  Future<void> get down => _link.down;
  @override
  bool get isUp => _link.isUp;
  @override
  void subscribe(String topic) => _link.subscribe(topic);
  @override
  void publish(String topic, Uint8List data) => _link.publish(topic, data);
  @override
  Future<void> close() => _link.close();
}

/// Opens a TLS connection to a public broker, with no will and no retained message: unlike Listen together
/// there is no room for the broker to remember.
Future<ConnectLink> openConnectLink(InternetBroker broker) async => _MqttConnectLink(await InternetLink.open(broker));

/// One direction pair on a [ConnectLink]: JSON in, JSON out, encrypted both ways, and anything that doesn't
/// decrypt with [keys] (a wrong key, a changed byte, another topic, a stale timestamp) dropped without a trace.
class ConnectChannel {
  ConnectChannel(this._link, this._key, {required this.sendTopic, required this.receiveTopic, bool subscribe = true}) {
    if (subscribe) _link.subscribe(receiveTopic);
    _sub = _link.messages.where((e) => e.$1 == receiveTopic).listen((e) {
      final m = decode(_key, receiveTopic, e.$2);
      if (m != null && !_in.isClosed) _in.add(m);
    });
  }

  final ConnectLink _link;
  final Uint8List _key;
  final String sendTopic;
  final String receiveTopic;
  final _in = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription<(String, Uint8List)>? _sub;

  Stream<Map<String, dynamic>> get messages => _in.stream;

  void send(Map<String, dynamic> message) => _link.publish(sendTopic, encode(_key, sendTopic, message));

  Future<void> close() async {
    await _sub?.cancel();
    if (!_in.isClosed) await _in.close();
  }

  static Uint8List encode(Uint8List key, String topic, Map<String, dynamic> message, {int? nowMs, Random? random}) =>
      InternetCrypto.encrypt(key, topic, jsonEncode(message), nowMs: nowMs, random: random);

  /// Null for anything that isn't a JSON object encrypted with [key] for [topic].
  static Map<String, dynamic>? decode(Uint8List key, String topic, Uint8List data, {int? nowMs}) {
    final payload = InternetCrypto.decrypt(key, topic, data, nowMs: nowMs);
    if (payload == null) return null;
    try {
      final json = jsonDecode(payload.message);
      return json is Map<String, dynamic> ? json : null;
    } catch (_) {
      return null;
    }
  }
}

/// A short random id for a pairing peer (the same shape [InternetRoomKeys] expects at the end of a `g/` topic).
String newConnectPeerId() => randomInternetId();

String base64Of(List<int> bytes) => base64Encode(bytes);

Uint8List? bytesOfBase64(Object? text) {
  if (text is! String) return null;
  try {
    return base64Decode(text);
  } catch (_) {
    debugPrint('Riflay Connect: not base64');
    return null;
  }
}

final _unsafeName = RegExp(r'[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]');

/// A name from another device, as plain text to show: no control characters, never long.
String cleanConnectName(Object? raw, {String fallback = 'Riflay', int max = 32}) {
  final text = (raw is String ? raw : '').replaceAll(_unsafeName, '').trim();
  if (text.isEmpty) return fallback;
  return text.length <= max ? text : text.substring(0, max);
}

/// `riflay://connect?code=…`: what the pairing QR carries.
Uri connectPairingLink(String code) => Uri(scheme: 'riflay', host: 'connect', queryParameters: {'code': code});

/// The code in a scanned or pasted pairing link or typed code, or null when it is neither.
String? connectCodeFrom(String text) {
  final uri = Uri.tryParse(text.trim());
  final raw = uri != null && uri.scheme == 'riflay' && uri.host == 'connect' ? uri.queryParameters['code'] ?? '' : text;
  final code = normalizeCode(raw);
  return code != null && code.length == internetCodeLength ? code : null;
}

/// How a pairing names this device to the other: the system ("Windows", "Android") and four characters to tell
/// two of the same kind apart. Never a user, account or computer name.
String defaultConnectDeviceName([Random? random]) {
  final r = random ?? Random.secure();
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final os = Host.isMacOS
      ? 'macOS'
      : Host.isIOS
      ? 'iOS'
      : Host.isWeb
      ? 'Web'
      : _capital(Host.operatingSystem);
  return '$os ${[for (var i = 0; i < 4; i++) chars[r.nextInt(chars.length)]].join()}';
}

String _capital(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
