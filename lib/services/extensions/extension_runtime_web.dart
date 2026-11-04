import 'extension_models.dart';
import 'extension_runner.dart';

/// The web build runs no extension scripts.
const jsRuntimeSupported = false;

ExtensionRunner startJsExtension({
  required String dir,
  required ExtensionManifest manifest,
  required String storagePath,
  Map<String, Object?> config = const {},
}) => throw UnsupportedError('Extensions need the desktop or mobile app');
