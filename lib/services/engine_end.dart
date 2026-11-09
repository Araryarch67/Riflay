import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../platform/host.dart';

/// Android: the process ends with its Flutter engine (`EngineEnd.kt`). audio_service destroys the engine once the
/// app is closed and nothing plays, but Android keeps the process, with every mpv player in it and no Dart left to
/// dispose them: their wakeup callbacks point at code that went with the engine, and mpv's next event crashed in
/// `libmpv.so`. The Android side does it on its own; this only passes the off switch on.
abstract final class EngineEnd {
  /// Off with `RIFLAY_NO_ENGINE_EXIT`: the process stays after its engine, as it did.
  static const exits = !bool.fromEnvironment('RIFLAY_NO_ENGINE_EXIT');

  static Future<void> start({MethodChannel channel = const MethodChannel('riflay/engine_end'), bool? keep}) async {
    if (!Host.isAndroid || !(keep ?? !exits)) return;
    try {
      await channel.invokeMethod<void>('keep');
    } catch (e) {
      debugPrint('Engine end: keeping the process: $e');
    }
  }
}
