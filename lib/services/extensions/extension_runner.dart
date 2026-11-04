import 'extension_models.dart';
import 'extension_runtime_io.dart' if (dart.library.js_interop) 'extension_runtime_web.dart' as impl;

/// One installed extension, running: its script loaded and `initialize` called, ready to be asked things.
abstract class ExtensionRunner {
  /// Whether this build can run extension scripts (not the web build).
  static bool get supported => impl.jsRuntimeSupported;

  /// Starts [manifest]'s `index.js` from [dir], keeping its `storage` in [storagePath]. Loading happens in the
  /// background; the first call waits for it.
  static ExtensionRunner start({
    required String dir,
    required ExtensionManifest manifest,
    required String storagePath,
    Map<String, Object?> config = const {},
  }) => impl.startJsExtension(dir: dir, manifest: manifest, storagePath: storagePath, config: config);

  /// The songs it finds for [query] (`customSearch`, else `searchTracks`).
  Future<List<ExtensionSearchHit>> search(String query, {int limit = 20});

  /// Calls `cleanup` and stops it.
  Future<void> dispose();
}

/// The extension failed: it threw, timed out or doesn't have what was asked.
class ExtensionError implements Exception {
  const ExtensionError(this.message);
  final String message;

  @override
  String toString() => message;
}
