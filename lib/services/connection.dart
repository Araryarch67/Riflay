import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../platform/host.dart';

/// Whether the internet can be reached, known fast: the system's own signal at once (Wi-Fi and data gone), and a
/// quick look at YouTube Music when it says connected, since a Wi-Fi can have no internet behind it.
class Connection {
  Connection({this._changes, Future<bool> Function()? reach}) : _reach = reach ?? _reachYoutubeMusic;

  static final instance = Connection();

  final Stream<List<ConnectivityResult>>? _changes;
  final Future<bool> Function() _reach;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  final online = ValueNotifier(true);

  void start() {
    if (_sub != null) return;
    if (_changes == null && (Host.isWeb || Host.environment.containsKey('FLUTTER_TEST'))) return;
    final changes = _changes ?? Connectivity().onConnectivityChanged;
    _sub = changes.listen(_changed, onError: (Object e) => debugPrint('Connection: $e'));
    if (_changes == null) Connectivity().checkConnectivity().then(_changed, onError: (Object _) {});
  }

  Future<void> _changed(List<ConnectivityResult> now) async {
    if (now.isEmpty || now.every((c) => c == ConnectivityResult.none)) {
      online.value = false;
      return;
    }
    await check();
  }

  /// Looks again, as when a streamed song stalls; true when the internet answers.
  Future<bool> check() async => online.value = await _reach();

  static Future<bool> _reachYoutubeMusic() async {
    try {
      await http.head(Uri.https('music.youtube.com', '/')).timeout(const Duration(seconds: 4));
      return true;
    } catch (_) {
      return false;
    }
  }

  void dispose() => _sub?.cancel();
}
