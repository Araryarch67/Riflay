import 'dart:typed_data';

/// Native builds write files themselves. See `browser_files.dart`.
abstract final class BrowserFiles {
  static bool get available => false;
  static void save(Uint8List bytes, String name, {String mime = 'application/octet-stream'}) =>
      throw UnsupportedError('No browser');
  static void saveUrl(Uri url, String name) => throw UnsupportedError('No browser');
}
