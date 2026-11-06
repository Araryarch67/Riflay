/// Files the web build hands to the browser to save (a download) or asks it for (a file picker), in place of the
/// folders native builds write into and read from. Native builds have none of this.
library;

export 'browser_files_io.dart' if (dart.library.js_interop) 'browser_files_web.dart';
