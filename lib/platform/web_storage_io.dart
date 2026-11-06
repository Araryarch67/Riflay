/// Native builds keep files instead. See `web_storage.dart`.
abstract final class WebStorage {
  static bool get available => false;
  static String? read(String key) => null;
  static void write(String key, String value) => throw UnsupportedError('No local storage');
  static void remove(String key) {}
}
