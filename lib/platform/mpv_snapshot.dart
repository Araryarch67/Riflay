/// Diagnostic property reads run away from the UI thread on native platforms.
library;

export 'mpv_snapshot_io.dart' if (dart.library.js_interop) 'mpv_snapshot_web.dart';
