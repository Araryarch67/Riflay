import 'dart:convert';
import 'dart:math' as math;

/// A logarithmic filter bank. Analysis channels are discarded after their RMS
/// metadata is measured; the original channels pass through sample for sample.
abstract final class VisualizerSpectrum {
  static const bands = 24;

  static double frequency(int band, int rate) =>
      (35 * math.pow(math.min(16000, rate * 0.45) / 35, band / (bands - 1))).toDouble();

  static String filter({int channels = 2, String layout = 'stereo', int rate = 48000}) {
    if (channels < 1 || channels > 8 || rate < 8000 || !RegExp(r'^[a-zA-Z0-9.+()]+$').hasMatch(layout)) {
      throw ArgumentError('Unsupported spectrum input format');
    }
    final graph = [
      '[in]asplit=2[dry][analysis]',
      '[analysis]aformat=channel_layouts=mono,asplit=$bands${List.generate(bands, (i) => '[b$i]').join()}',
      for (var i = 0; i < bands; i++) '[b$i]bandpass=f=${frequency(i, rate).toStringAsFixed(3)}:t=o:w=0.55[f$i]',
      '[dry]${List.generate(bands, (i) => '[f$i]').join()}'
          'amerge=inputs=${bands + 1},'
          'astats=metadata=1:reset=1:measure_perchannel=RMS_level:measure_overall=none,'
          'pan=$layout${List.generate(channels, (i) => '|c$i=c$i').join()}[out]',
    ].join(';');
    return '@visualizer:lavfi=graph=%${utf8.encode(graph).length}%$graph';
  }
}
