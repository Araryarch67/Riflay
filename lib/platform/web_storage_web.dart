import 'package:web/web.dart' as web;

/// `window.localStorage`, under `riflay.` keys. See `web_storage.dart`.
abstract final class WebStorage {
  static bool get available => true;

  static String? read(String key) => web.window.localStorage.getItem('riflay.$key');

  /// Throws when the browser's quota (about 5 million characters per site) is full.
  static void write(String key, String value) => web.window.localStorage.setItem('riflay.$key', value);

  static void remove(String key) => web.window.localStorage.removeItem('riflay.$key');
}
