/// The few calls into the operating system's C libraries (`dart:ffi`), which a browser build cannot compile.
///
/// The web side answers "not here" (null, false, an inhibitor that throws), and its callers already treat that as
/// a feature this device lacks.
library;

export 'native_calls_io.dart' if (dart.library.js_interop) 'native_calls_web.dart';
