import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'connect_channel.dart';

/// The other end of a pairing, as this device remembers it: on the desktop a controller that may send commands,
/// on a controller a desktop it can control. [secret] opens the pair room (see [ConnectKeys.paired]).
///
/// It lives in the app's preferences. They aren't encrypted at rest: anyone who can read this user's app data
/// could also read the rest of what Riflay keeps there, and removing the entry on the desktop (Settings ›
/// Riflay Connect) ends the access at once.
class ConnectPeer {
  const ConnectPeer({
    required this.id,
    required this.name,
    required this.secret,
    required this.broker,
    required this.addedAtMs,
  });

  /// Local label, to remove or select one entry. Not secret, not sent.
  final String id;

  /// What to call the other device: the one the person chose on it, never an account name.
  final String name;
  final Uint8List secret;

  /// Index into `internetBrokers`, where this pair's room lives.
  final int broker;
  final int addedAtMs;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'secret': base64Of(secret),
    'broker': broker,
    'added': addedAtMs,
  };

  static ConnectPeer? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'], name = json['name'], broker = json['broker'], added = json['added'];
    final secret = bytesOfBase64(json['secret']);
    if (id is! String || name is! String || broker is! int || added is! int) return null;
    if (secret == null || secret.length != connectSecretLength) return null;
    return ConnectPeer(id: id, name: name, secret: secret, broker: broker, addedAtMs: added);
  }
}

/// The two lists Connect keeps: [controllers] on a desktop, [hosts] on a controller, and whether the desktop
/// listens at all.
class ConnectStore {
  ConnectStore(this._prefs);

  static Future<ConnectStore> open() async => ConnectStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _controllersKey = 'connect_controllers';
  static const _hostsKey = 'connect_hosts';
  static const _enabledKey = 'connect_host_enabled';

  bool get hostEnabled => _prefs.getBool(_enabledKey) ?? false;
  Future<void> setHostEnabled(bool on) => _prefs.setBool(_enabledKey, on);

  List<ConnectPeer> get controllers => _read(_controllersKey);
  Future<void> saveControllers(List<ConnectPeer> peers) => _write(_controllersKey, peers);

  List<ConnectPeer> get hosts => _read(_hostsKey);
  Future<void> saveHosts(List<ConnectPeer> peers) => _write(_hostsKey, peers);

  List<ConnectPeer> _read(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      return list is List ? [for (final p in list) ?ConnectPeer.fromJson(p)] : const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _write(String key, List<ConnectPeer> peers) =>
      _prefs.setString(key, jsonEncode([for (final p in peers) p.toJson()]));
}
