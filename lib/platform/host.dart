/// What the app runs on, without `dart:io`'s `Platform`, which throws in a browser.
///
/// Native builds read `Platform`; the web build answers "web" and false to every operating system, so code behind
/// `Host.isLinux` and friends simply does not run there.
library;

export 'host_io.dart' if (dart.library.js_interop) 'host_web.dart';
