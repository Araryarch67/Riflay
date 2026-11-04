/// The tray icon and its menu, which only the desktop builds have (tray_manager).
///
/// The web build answers that there is no tray, so nothing there is ever hidden instead of closed.
library;

export 'tray_entry.dart';
export 'tray_io.dart' if (dart.library.js_interop) 'tray_web.dart';
