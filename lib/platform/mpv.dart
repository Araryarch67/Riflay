/// media_kit's libmpv player, which only native builds have.
///
/// On the web `NativePlayer` is an interface nothing implements, so every `player.platform case NativePlayer p`
/// in the audio code is false there and the mpv settings are skipped. Import media_kit with `hide NativePlayer`
/// next to this.
library;

export 'mpv_io.dart' if (dart.library.js_interop) 'mpv_web.dart';
