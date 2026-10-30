/// Work that should not hold up the UI: another isolate in native builds, the same thread in a browser (which has
/// no isolates; `Isolate.run` throws there).
library;

export 'background_io.dart' if (dart.library.js_interop) 'background_web.dart';
