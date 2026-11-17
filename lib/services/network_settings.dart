import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App HTTP routing. Local playback servers and devices never leave the LAN.
class NetworkSettings extends ChangeNotifier {
  static final instance = NetworkSettings();
  static const _key = 'network.proxy.v1';
  bool enabled = false;
  String address = 'http://127.0.0.1:7890';
  String bypass = '';
  bool _loaded = false;

  static Uri? parseAddress(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'http' ||
        uri.host.isEmpty ||
        !uri.hasPort ||
        uri.port < 1 ||
        uri.port > 65535 ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    return uri;
  }

  static List<String>? parseBypass(String value) {
    final hosts = <String>{};
    for (final entry in value.split(RegExp(r'[,\n]'))) {
      final host = entry.trim().toLowerCase().replaceFirst(RegExp(r'^\*?\.'), '');
      if (host.isEmpty) continue;
      if (!RegExp(r'^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$').hasMatch(host) || host.contains('..')) return null;
      hosts.add(host);
    }
    return hosts.toList();
  }

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final fields = prefs.getStringList(_key);
    if (fields != null && fields.length == 3 && parseAddress(fields[1]) != null && parseBypass(fields[2]) != null) {
      enabled = fields[0] == 'on';
      address = fields[1];
      bypass = fields[2];
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> save({required bool enabled, required String address, required String bypass}) async {
    final parsed = parseAddress(address);
    final rules = parseBypass(bypass);
    if (parsed == null || rules == null) throw const FormatException('Invalid proxy configuration');
    final normalized = parsed.replace(path: '').toString();
    final normalizedRules = rules.join('\n');
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setStringList(_key, [enabled ? 'on' : 'off', normalized, normalizedRules])) {
      throw StateError('Could not save proxy settings');
    }
    this.enabled = enabled;
    this.address = normalized;
    this.bypass = normalizedRules;
    _loaded = true;
    notifyListeners();
  }

  static bool _localHost(String host) {
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host == '::1' ||
        host == '::') {
      return true;
    }
    if (host.contains(':')) return host.startsWith('fe80:') || host.startsWith('fc') || host.startsWith('fd');
    final numbers = host.split('.').map(int.tryParse).toList();
    if (numbers.length != 4 || numbers.any((n) => n == null || n < 0 || n > 255)) return false;
    return numbers[0] == 127 ||
        numbers[0] == 10 ||
        numbers[0] == 0 ||
        (numbers[0] == 192 && numbers[1] == 168) ||
        (numbers[0] == 169 && numbers[1] == 254) ||
        (numbers[0] == 172 && numbers[1]! >= 16 && numbers[1]! <= 31);
  }

  /// Null means direct, including any explicit bypass. No silent direct fallback on proxy failure.
  Uri? proxyFor(Uri destination) {
    if (!enabled || !const {'http', 'https'}.contains(destination.scheme)) return null;
    final host = destination.host.toLowerCase();
    if (_localHost(host)) return null;
    for (final rule in parseBypass(bypass) ?? const <String>[]) {
      if (host == rule || host.endsWith('.$rule')) return null;
    }
    return parseAddress(address);
  }

  String route(Uri destination) {
    final proxy = proxyFor(destination);
    return proxy == null
        ? 'DIRECT'
        : 'PROXY ${proxy.host.contains(':') ? '[${proxy.host}]' : proxy.host}:${proxy.port}';
  }

  List<String> extractorArguments(Uri destination) => ['--proxy', proxyFor(destination)?.toString() ?? ''];
}
