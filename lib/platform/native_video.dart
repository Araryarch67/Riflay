/// Music video outside Flutter's texture pipeline: Windows uses a child window
/// and a video DLL; Linux uses system libmpv and a GTK OpenGL surface. Other
/// platforms use the existing media_kit video backend.
library;

export 'native_video_io.dart' if (dart.library.js_interop) 'native_video_web.dart';
