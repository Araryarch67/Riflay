/// Windows' music video player in a window of its own: a second libmpv (`libmpv-video-2.dll`, built with Direct3D 11
/// output and d3d11va decoding) drawing straight into the window `runner/video_window.cpp` makes, so a video frame
/// never makes Flutter redraw. The web (and every other platform) has none: [NativeVideoPlayer.available] is false.
library;

export 'native_video_io.dart' if (dart.library.js_interop) 'native_video_web.dart';
