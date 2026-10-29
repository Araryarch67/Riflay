import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'transport.dart';

/// Listen together over the same Wi-Fi: the host runs a small WebSocket server and announces itself with a
/// UDP multicast beacon; guests find the beacon (or are given the code) and connect to the sender's address.

/// The group and port every beacon goes to.
final lanBeaconGroup = InternetAddress('239.255.77.77');
const lanBeaconPort = 47777;

/// Letters and digits that can't be mistaken for each other (no 0/O, 1/I).
const lanCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

String newLanCode([Random? random]) {
  final r = random ?? Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < 6; i++) lanCodeAlphabet.codeUnitAt(r.nextInt(lanCodeAlphabet.length)),
  ]);
}

/// What someone types is forgiven a little: case and spaces.
String normalizeLanCode(String code) => code.replaceAll(RegExp(r'\s'), '').toUpperCase();

Uri lanJoinLink(String code) => Uri(scheme: 'riflay', host: 'listen', queryParameters: {'code': code});

/// One announcement heard on the network.
class LanBeacon {
  const LanBeacon({required this.name, required this.code, required this.port, required this.address});

  final String name;
  final String code;
  final int port;

  /// Where the beacon came from: the host's address on this network.
  final InternetAddress address;

  Uri get socketUri => Uri(scheme: 'ws', host: address.address, port: port, path: '/listen/$code');

  static String encode({required String name, required String code, required int port}) =>
      jsonEncode({'riflay': 'listen', 'v': 1, 'name': name, 'code': code, 'port': port});

  /// Null for anything that isn't one of ours.
  static LanBeacon? parse(List<int> data, InternetAddress from) {
    if (data.isEmpty || data.length > 1024) return null;
    try {
      final json = jsonDecode(utf8.decode(data));
      if (json is! Map<String, dynamic> || json['riflay'] != 'listen') return null;
      final name = json['name'], code = json['code'], port = json['port'];
      if (name is! String || code is! String || port is! int) return null;
      if (!RegExp('^[$lanCodeAlphabet]{6}\$').hasMatch(code) || port < 1 || port > 65535) return null;
      return LanBeacon(name: name.length > 40 ? name.substring(0, 40) : name, code: code, port: port, address: from);
    } on FormatException {
      return null;
    }
  }
}

/// Android's Wi-Fi drops multicast packets unless an app holds a multicast lock; MainActivity takes and gives it
/// back. Counted, so hosting and searching at once don't release each other's. Elsewhere this does nothing.
abstract final class LanMulticastLock {
  static const _channel = MethodChannel('riflay/multicast');
  static var _holders = 0;

  static Future<void> acquire() async {
    if (_holders++ == 0) await _call('acquire');
  }

  static Future<void> release() async {
    if (_holders > 0 && --_holders == 0) await _call('release');
  }

  static Future<void> _call(String method) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>(method);
    } catch (e) {
      debugPrint('Multicast lock: $e');
    }
  }
}

Future<List<NetworkInterface>> _interfaces() async {
  try {
    return await NetworkInterface.list(type: InternetAddressType.IPv4);
  } catch (e) {
    debugPrint('Listen together: no network list: $e');
    return const [];
  }
}

class _LanPeer implements ListenPeer {
  _LanPeer(this.id, this._socket) {
    _socket.pingInterval = const Duration(seconds: 10);
    incoming = _socket.where((e) => e is String).cast<String>();
  }

  @override
  final String id;
  final WebSocket _socket;

  @override
  late final Stream<String> incoming;

  @override
  void send(String message) {
    if (_socket.readyState == WebSocket.open) _socket.add(message);
  }

  @override
  Future<void> close() => _socket.close();
}

/// The host side on the same Wi-Fi.
class LanHostTransport implements ListenHostTransport {
  LanHostTransport({required this.name, this.maxGuests = 16});

  /// Shown to guests that search nearby.
  final String name;
  final int maxGuests;

  /// Codes of sessions this device is hosting, so its own search doesn't offer them.
  static final Set<String> hostedCodes = {};

  final _peers = StreamController<ListenPeer>.broadcast();
  final _open = <_LanPeer>{};
  final _beaconSockets = <String, RawDatagramSocket>{};
  HttpServer? _server;
  Timer? _beacon;
  String? _code;
  var _nextId = 0;
  var _holdsLock = false;

  @override
  String get code => _code!;

  @override
  Uri get joinLink => lanJoinLink(code);

  /// The port guests connect to. Known after [start].
  int get port => _server!.port;

  @override
  Stream<ListenPeer> get peers => _peers.stream;

  @override
  Future<void> start() async {
    _code = newLanCode();
    hostedCodes.add(_code!);
    await LanMulticastLock.acquire();
    _holdsLock = true;
    try {
      final server = _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      server.listen(_onRequest, onError: (Object e) => debugPrint('Listen together: server: $e'));
      unawaited(_announce());
      _beacon = Timer.periodic(const Duration(milliseconds: 1500), (_) => _announce());
    } catch (e) {
      await stop();
      rethrow;
    }
  }

  Future<void> _onRequest(HttpRequest request) async {
    try {
      if (request.uri.path != '/listen/$_code' || !WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      if (_open.length >= maxGuests) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      final peer = _LanPeer('lan${_nextId++}', socket);
      _open.add(peer);
      socket.done.then((_) => _open.remove(peer), onError: (_) => _open.remove(peer));
      if (!_peers.isClosed) _peers.add(peer);
    } catch (e) {
      debugPrint('Listen together: request: $e');
    }
  }

  Future<void> _announce() async {
    final server = _server;
    if (server == null) return;
    final payload = utf8.encode(LanBeacon.encode(name: name, code: _code!, port: server.port));
    final interfaces = await _interfaces();
    final wanted = {
      for (final i in interfaces)
        for (final a in i.addresses)
          if (!a.isLoopback) a.address: a,
    };
    for (final gone in _beaconSockets.keys.where((k) => !wanted.containsKey(k)).toList()) {
      _beaconSockets.remove(gone)?.close();
    }
    for (final entry in wanted.entries) {
      var socket = _beaconSockets[entry.key];
      if (socket == null) {
        try {
          socket = await RawDatagramSocket.bind(entry.value, 0);
          // Send on this network, not just the one with the default route.
          try {
            socket.setRawOption(
              RawSocketOption(
                RawSocketOption.levelIPv4,
                RawSocketOption.IPv4MulticastInterface,
                entry.value.rawAddress,
              ),
            );
          } catch (_) {}
          if (_server == null) {
            socket.close();
            return;
          }
          _beaconSockets[entry.key] = socket;
        } catch (e) {
          debugPrint('Listen together: can\'t announce on ${entry.key}: $e');
          continue;
        }
      }
      try {
        socket.send(payload, lanBeaconGroup, lanBeaconPort);
      } catch (e) {
        debugPrint('Listen together: announce on ${entry.key}: $e');
        _beaconSockets.remove(entry.key)?.close();
      }
    }
  }

  @override
  Future<void> stop() async {
    _beacon?.cancel();
    _beacon = null;
    if (_code != null) hostedCodes.remove(_code);
    for (final s in _beaconSockets.values) {
      s.close();
    }
    _beaconSockets.clear();
    final server = _server;
    _server = null;
    for (final p in _open.toList()) {
      unawaited(p.close().catchError((Object _) {}));
    }
    _open.clear();
    await server?.close(force: true);
    if (!_peers.isClosed) await _peers.close();
    if (_holdsLock) {
      _holdsLock = false;
      await LanMulticastLock.release();
    }
  }
}

/// Finding hosts on the same Wi-Fi.
abstract final class LanDiscovery {
  /// A session not heard from for this long is gone.
  static const staleAfter = Duration(seconds: 5);

  /// Every beacon heard on any network, as it arrives. Holds the multicast lock while listened to.
  static Stream<LanBeacon> beacons() {
    late final StreamController<LanBeacon> out;
    final sockets = <RawDatagramSocket>[];
    var closed = false, holds = false;

    Future<void> open() async {
      await LanMulticastLock.acquire();
      holds = true;
      if (closed) {
        holds = false;
        await LanMulticastLock.release();
        return;
      }
      RawDatagramSocket socket;
      try {
        try {
          socket = await RawDatagramSocket.bind(
            InternetAddress.anyIPv4,
            lanBeaconPort,
            reuseAddress: true,
            reusePort: true,
          );
        } on SocketException {
          // reusePort is not available everywhere (Windows).
          socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, lanBeaconPort, reuseAddress: true);
        }
      } catch (e) {
        debugPrint('Listen together: can\'t listen for sessions: $e');
        if (!out.isClosed) out.addError(e);
        return;
      }
      if (closed) {
        socket.close();
        return;
      }
      sockets.add(socket);
      var joined = false;
      for (final i in await _interfaces()) {
        try {
          socket.joinMulticast(lanBeaconGroup, i);
          joined = true;
        } catch (e) {
          debugPrint('Listen together: can\'t join on ${i.name}: $e');
        }
      }
      if (!joined) {
        try {
          socket.joinMulticast(lanBeaconGroup);
        } catch (e) {
          debugPrint('Listen together: can\'t join the group: $e');
        }
      }
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final d = socket.receive();
        if (d == null) return;
        final beacon = LanBeacon.parse(d.data, d.address);
        if (beacon != null && !LanHostTransport.hostedCodes.contains(beacon.code) && !out.isClosed) out.add(beacon);
      });
    }

    out = StreamController<LanBeacon>(
      onListen: () => unawaited(open()),
      onCancel: () async {
        closed = true;
        for (final s in sockets) {
          s.close();
        }
        if (holds) {
          holds = false;
          await LanMulticastLock.release();
        }
      },
    );
    return out.stream;
  }

  /// The sessions on this Wi-Fi right now; a new list whenever it changes.
  static Stream<List<FoundSession>> find({Stream<LanBeacon>? source, Duration stale = staleAfter}) {
    late final StreamController<List<FoundSession>> out;
    StreamSubscription<LanBeacon>? sub;
    Timer? sweep;
    final seen = <String, (LanBeacon, DateTime)>{};
    var last = <String>[];

    void emit() {
      final list = [for (final e in seen.values) e.$1]..sort((a, b) => a.name.compareTo(b.name));
      final key = [for (final b in list) '${b.code}|${b.name}'];
      if (listEquals(key, last)) return;
      last = key;
      out.add([for (final b in list) FoundSession(hostName: b.name, code: b.code, joinLink: lanJoinLink(b.code))]);
    }

    out = StreamController<List<FoundSession>>(
      onListen: () {
        sub = (source ?? beacons()).listen((b) {
          seen[b.code] = (b, DateTime.now());
          emit();
        }, onError: (Object e) => debugPrint('Listen together: search: $e'));
        sweep = Timer.periodic(const Duration(seconds: 1), (_) {
          final cutoff = DateTime.now().subtract(stale);
          if (seen.values.any((e) => e.$2.isBefore(cutoff))) {
            seen.removeWhere((_, e) => e.$2.isBefore(cutoff));
            emit();
          }
        });
      },
      onCancel: () async {
        sweep?.cancel();
        await sub?.cancel();
      },
    );
    return out.stream;
  }
}

/// A guest's WebSocket to a LAN host.
class LanGuestConnection implements ListenGuestConnection {
  LanGuestConnection._(this._socket) {
    incoming = _socket.where((e) => e is String).cast<String>();
  }

  final WebSocket _socket;

  @override
  late final Stream<String> incoming;

  /// Waits for the host with [code] to announce itself, then connects. Throws [TimeoutException] when it
  /// isn't heard, or a socket error when the connection is refused.
  static Future<LanGuestConnection> connect(String code, {Duration timeout = const Duration(seconds: 6)}) async {
    final wanted = normalizeLanCode(code);
    final beacon = await LanDiscovery.beacons().firstWhere((b) => b.code == wanted).timeout(timeout);
    return connectTo(beacon.socketUri, timeout: timeout);
  }

  /// Connects to a known address (also what tests use, where multicast may not work).
  static Future<LanGuestConnection> connectTo(Uri uri, {Duration timeout = const Duration(seconds: 6)}) async {
    final socket = await WebSocket.connect('$uri').timeout(timeout);
    socket.pingInterval = const Duration(seconds: 10);
    return LanGuestConnection._(socket);
  }

  @override
  void send(String message) {
    if (_socket.readyState == WebSocket.open) _socket.add(message);
  }

  @override
  Future<void> close() => _socket.close();
}
