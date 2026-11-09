import 'dart:convert';
import 'dart:math' as math;

/// A logarithmic filter bank. Analysis channels are discarded after their RMS
/// metadata is measured; the original channels pass through sample for sample.
abstract final class VisualizerSpectrum {
  static const bands = 24;

  /// Balanced on a computer measures half as many bands, each over a 4096-point window ([frugalWindow]): its
  /// visualizer draws 10 times a second, and the filter bank cost the audio thread ~19 ms per second of music at
  /// 24 bands and 1024 points, ~6 ms like this. The bars in between are drawn from their neighbours.
  static const frugalBands = 12;
  static const frugalWindow = 4096;

  /// The centre of [band] of [count], log-spaced from 35 Hz to 16 kHz (or 45% of [rate]).
  static double frequency(int band, int rate, {int count = bands}) =>
      (35 * math.pow(math.min(16000, rate * 0.45) / 35, band / (count - 1))).toDouble();

  /// [spectral]: each channel's power from one 1024-point FFT a window (`aspectralstats`), ~3x cheaper than `astats`,
  /// which works out ~25 statistics on every sample to give the one RMS used here. Off: `astats`, for an mpv whose
  /// FFmpeg is older than 5.1 (no `aspectralstats`), and with `RIFLAY_ASTATS_VISUALIZER`.
  static String filter({
    int channels = 2,
    String layout = 'stereo',
    int rate = 48000,
    bool spectral = true,
    int count = bands,
    int window = 1024,
  }) {
    if (channels < 1 || channels > 8 || rate < 8000 || !RegExp(r'^[a-zA-Z0-9.+()]+$').hasMatch(layout)) {
      throw ArgumentError('Unsupported spectrum input format');
    }
    final graph = [
      '[in]asplit=2[dry][analysis]',
      '[analysis]aformat=channel_layouts=mono,asplit=$count${List.generate(count, (i) => '[b$i]').join()}',
      for (var i = 0; i < count; i++)
        '[b$i]bandpass=f=${frequency(i, rate, count: count).toStringAsFixed(3)}:t=o:w=${(0.55 * (bands - 1) / (count - 1)).toStringAsFixed(3)}[f$i]',
      '[dry]${List.generate(count, (i) => '[f$i]').join()}'
          'amerge=inputs=${count + 1},'
          '${spectral ? 'aspectralstats=win_size=$window:overlap=0:measure=mean+variance' : 'astats=metadata=1:reset=1:measure_perchannel=RMS_level:measure_overall=none'},'
          'pan=$layout${List.generate(channels, (i) => '|c$i=c$i').join()}[out]',
    ].join(';');
    return '@visualizer:lavfi=graph=%${utf8.encode(graph).length}%$graph';
  }
}
