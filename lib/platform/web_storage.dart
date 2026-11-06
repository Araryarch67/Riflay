/// The browser's local storage, where the web build keeps what native builds keep in files of their own (the
/// listening history). Native builds have none.
library;

export 'web_storage_io.dart' if (dart.library.js_interop) 'web_storage_web.dart';
