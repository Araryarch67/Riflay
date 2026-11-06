/// Web Audio on the web build's `<audio>` elements: the equalizer and the other effects it can do, and the
/// spectrum the visualizer reads. Native builds have mpv's filters for both, so there it is off.
library;

export 'web_audio_io.dart' if (dart.library.js_interop) 'web_audio_web.dart';
