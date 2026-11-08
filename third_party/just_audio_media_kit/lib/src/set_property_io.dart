library just_audio_media_kit;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:media_kit/media_kit.dart';

Future<void> setProperty(Player player, String key, dynamic value) async {
  if (player.platform is! NativePlayer) return;
  await (player.platform as NativePlayer).setProperty(key, value);
}

/// Riflay: stops mpv reporting `time-pos`, which it does for every audio chunk (16+ times a second), each one
/// waking the app. media_kit registers it with the property name's hash as the reply id. False where there is no
/// native player.
bool stopPositionEvents(Player player) {
  final native = player.platform;
  if (native is! NativePlayer || native.ctx == nullptr) return false;
  return native.mpv.mpv_unobserve_property(native.ctx, 'time-pos'.hashCode) >= 0;
}

/// Riflay: mpv's playback position now, read on the spot; null when there is none (nothing loaded).
Duration? readPosition(Player player) {
  final native = player.platform;
  if (native is! NativePlayer || native.ctx == nullptr) return null;
  final name = 'time-pos'.toNativeUtf8();
  final value = calloc<Double>();
  try {
    final error = native.mpv.mpv_get_property(
      native.ctx,
      name.cast(),
      generated.mpv_format.MPV_FORMAT_DOUBLE,
      value.cast(),
    );
    if (error < 0) return null;
    return Duration(microseconds: (value.value * 1e6).round());
  } finally {
    calloc.free(name);
    calloc.free(value);
  }
}
