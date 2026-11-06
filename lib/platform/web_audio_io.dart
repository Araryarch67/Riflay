import 'dart:typed_data';

import 'web_effects.dart';

/// Native builds: mpv does all of this. See `web_audio.dart`.
abstract final class WebAudio {
  static bool get available => false;
  static double get sampleRate => 48000;
  static void install() {}
  static void apply(WebEffects effects) {}
  static bool readBands(List<(double, double)> edges, Float64List levels) => false;
}
