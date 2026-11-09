import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/audio_engine.dart';
import '../../services/bluetooth_codec.dart';
import '../../services/null_test.dart';
import '../../services/output_measure.dart';
import '../../services/player_controller.dart';
import '../../services/ui_beat.dart';
import '../debug_switches.dart';
import '../theme.dart';
import '../../services/language.dart';

/// Polls mpv for the live signal path while it's on screen, once a second while a song plays. Paused, nothing in
/// it moves: it is read again only when the song, the player or a sound setting changes (a read and a rebuild
/// every second kept an idle window drawing).
class _SignalPathBuilder extends StatefulWidget {
  const _SignalPathBuilder({required this.builder, this.shows});

  final Widget Function(BuildContext context, SignalPath? path) builder;

  /// What [builder] shows of a path that must show at once: a read that changes only the rest is drawn every
  /// [_refresh] (a whole frame of the window each second, for an Opus song's bitrate going 122, 127, 128 kbps).
  /// Null: every read.
  final Object? Function(SignalPath path)? shows;

  @override
  State<_SignalPathBuilder> createState() => _SignalPathBuilderState();
}

class _SignalPathBuilderState extends State<_SignalPathBuilder> {
  SignalPath? _path;
  DateTime _drawnAt = DateTime.now();
  static const _refresh = Duration(seconds: 10);
  UiBeatListener? _beat;
  late final PlayerController _controller = PlayerScope.read(context);

  /// A read waiting for the one in flight: a burst of changes reads once more, not once each.
  bool _reading = false, _again = false;

  bool get _paused => !_controller.showsPlaying && !DebugSwitches.signalPathWhilePaused;

  /// On a page that isn't shown ([TickerMode] off, e.g. under Now Playing) it isn't read.
  bool _shown = true;

  @override
  void initState() {
    super.initState();
    _poll();
    _controller.addListener(_changed);
    _controller.audio.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shown = TickerMode.valuesOf(context).enabled;
    if (shown && !_shown) _poll();
    _shown = shown;
    _syncBeat();
  }

  /// While playing the beat reads soon enough; paused, a change is read now.
  void _changed() {
    _syncBeat();
    if (_paused) _poll();
  }

  /// On the shared beat while playing: a second is 60 beats, the ones Lightweight's seek bar ticks on, so both draw
  /// in one frame. Paused, off it: a listener left on keeps the beat's 60 Hz timer waking the app.
  void _syncBeat() {
    if (_paused || !_shown) {
      _beat?.cancel();
      _beat = null;
    } else {
      _beat ??= UiBeat.listen(const Duration(seconds: 1), (_) => _poll());
    }
  }

  Future<void> _poll() async {
    if (_reading) {
      _again = true;
      return;
    }
    _reading = true;
    try {
      final path = await _controller.audio.signalPath();
      final shows = widget.shows, old = _path;
      final same =
          shows != null &&
          !DebugSwitches.signalPathEveryRead &&
          path != null &&
          old != null &&
          shows(path) == shows(old) &&
          DateTime.now().difference(_drawnAt) < _refresh;
      if (mounted && !same) {
        _drawnAt = DateTime.now();
        setState(() => _path = path);
      }
    } finally {
      _reading = false;
    }
    if (_again && mounted) {
      _again = false;
      await _poll();
    }
  }

  @override
  void dispose() {
    _beat?.cancel();
    _controller.removeListener(_changed);
    _controller.audio.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _path);
}

String _codecName(SignalPath p) => p.isDop
    ? 'DSD${p.dopBitRate! ~/ 44100}'
    : switch (p.codec) {
        'flac' => 'FLAC',
        'alac' => 'ALAC',
        'opus' => 'Opus',
        'vorbis' => 'Vorbis',
        'aac' => 'AAC',
        'mp3' || 'mp3float' => 'MP3',
        'wavpack' => 'WavPack',
        'ape' => "Monkey's Audio",
        final c when c.startsWith('pcm_') => p.container == 'aiff' ? 'AIFF' : 'WAV',
        final c when c.startsWith('dsd_') => 'DSD${p.inRate * 8 ~/ 44100}',
        'dst' => 'DST (SACD)',
        final c => c.toUpperCase(),
      };

/// What kind of sound a song is, as the badge names it: its word and its icon.
(String, IconData) _tier(SignalPath p) {
  if (p.isDsd || p.isDop) return ('DSD', Icons.blur_on_rounded);
  if (!p.lossless) return (tr.qualityLossy, Icons.graphic_eq_rounded);
  final bits = SignalPath.bitsOf(p.inFormat);
  final hiRes = p.inRate > 48000 || (p.sourceBits ?? (p.inFormat.startsWith('float') ? null : bits) ?? 16) > 16;
  return hiRes ? ('Hi-Res', Icons.diamond_rounded) : (tr.qualityLossless, Icons.diamond_outlined);
}

/// "Opus · Lossy · 160 kbps", "FLAC · Hi-Res · 24-bit / 96 kHz" with the tier's icon, no frame: tap for the full
/// signal path.
class QualityBadge extends StatelessWidget {
  const QualityBadge({super.key, this.onDark = false, this.alignment = Alignment.centerLeft});

  /// On a coloured background (phone now playing): white text instead of grey.
  final bool onDark;

  /// Where it sits in the room it is given.
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    if (!AudioEngine.supported) return const SizedBox.shrink();
    return _SignalPathBuilder(
      // The badge's words but the bitrate: a VBR song's swings each second (Opus: 112-160 kbps) are drawn every
      // [_SignalPathBuilderState._refresh] instead.
      shows: (p) => (
        _codecName(p),
        p.bitPerfect,
        _tier(p),
        p.isDop,
        p.isDsd,
        p.lossless,
        p.inFormat,
        p.inRate,
        p.sourceBits,
        p.bitrate == null || p.bitrate == 0,
      ),
      builder: (context, p) {
        if (p == null) return const SizedBox(height: 24);
        final (tier, icon) = p.bitPerfect ? ('Bit-perfect', Icons.verified_rounded) : _tier(p);
        final detail = p.isDop
            ? 'DoP'
            : p.isDsd
            ? 'PCM ${SignalPath.formatRate(p.inRate)}'
            : p.lossless
            ? SignalPath.describe(p.inFormat, p.inRate, stored: p.sourceBits)
            : p.bitrate == null || p.bitrate == 0
            ? null
            : '${(p.bitrate! / 1000).round()} kbps';
        final color = p.bitPerfect
            ? AppColors.accent
            : onDark
            ? Colors.white
            : AppColors.textSecondary;
        final base = Theme.of(context).textTheme.labelSmall?.copyWith(color: color, letterSpacing: 0.3);
        return Align(
          alignment: alignment,
          child: Tooltip(
            message: tr.signalPath,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => showSignalPath(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: color),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: _codecName(p),
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            TextSpan(
                              text: '  $tier',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            if (detail != null)
                              TextSpan(
                                text: '  ·  $detail',
                                style: TextStyle(fontWeight: FontWeight.w500, color: color.withValues(alpha: 0.7)),
                              ),
                          ],
                        ),
                        style: base,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<void> showSignalPath(BuildContext context) {
  final c = PlayerScope.read(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.elevated,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => PlayerScope(controller: c, child: const _SignalPathSheet()),
  );
}

class _SignalPathSheet extends StatelessWidget {
  const _SignalPathSheet();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _SignalPathBuilder(
      builder: (context, p) {
        if (p == null) {
          return Padding(padding: EdgeInsets.all(32), child: Text(tr.statsNothingPlaying));
        }
        final (verdict, verdictColor, detail) = p.isDop && p.bitPerfect
            ? (tr.nativeDsd2, AppColors.accent, tr.spNativeDsdBody)
            : p.isDop
            ? (tr.spDopChanged, Theme.of(context).colorScheme.error, tr.spDopChangedBody)
            : p.bitPerfect && p.usbDacName != null
            ? ('Bit-perfect', AppColors.accent, tr.spUsbBitPerfect('${p.usbDacName}'))
            : p.usbDacName != null && p.untouched == false && p.inRate != p.outRate
            ? (
                tr.spNotBitPerfect,
                AppColors.textPrimary,
                tr.spUsbDacRateUnsupported(
                  p.usbDacName!,
                  SignalPath.formatRate(p.inRate),
                  SignalPath.formatRate(p.outRate),
                ),
              )
            : p.bitPerfect
            ? ('Bit-perfect', AppColors.accent, tr.spBitPerfectBody)
            : p.untouched && p.mixerResamples
            ? (
                tr.spResampledByMixer,
                AppColors.textPrimary,
                '${tr.spMixerResamples(SignalPath.formatRate(p.dac!.rate), SignalPath.formatRate(p.inRate))} '
                    '${AudioEngine.hasRoutePicker ? tr.spFixedRateOutputs : tr.spTurnOnBitPerfect}',
              )
            : p.untouched && p.viaSystemMixer
            ? (
                tr.spLosslessToMixer,
                AppColors.textPrimary,
                '${tr.spMixerMayResample} '
                    '${AudioEngine.hasRoutePicker
                        ? tr.spIosAlwaysMixes
                        : AudioEngine.hasExclusiveMode
                        ? tr.spForBitPerfectExclusive
                        : tr.spForBitPerfect}',
              )
            : p.isDsd
            ? (
                tr.spDsdConverted,
                AppColors.textPrimary,
                AudioEngine.hasRoutePicker
                    ? tr.spDsdIos
                    : AudioEngine.hasExclusiveMode
                    ? tr.spDsdToPcmExclusive
                    : tr.spDsdToPcmHowTo,
              )
            : (tr.spProcessed, AppColors.textSecondary, tr.spProcessedBody);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr.signalPath, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      p.bitPerfect ? Icons.verified_rounded : Icons.graphic_eq_rounded,
                      color: verdictColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      verdict,
                      style: text.titleMedium?.copyWith(color: verdictColor, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(detail, style: text.bodySmall?.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 20),
                _Stage(
                  title: tr.spSource,
                  value:
                      '${_codecName(p)}${p.lossless ? ' ${tr.spLosslessParen}' : ''}'
                      '${p.sourceBits == null ? '' : ' · ${p.sourceBits}-bit'}'
                      '${p.bitrate == null || p.bitrate == 0 ? '' : ' · ${(p.bitrate! / 1000).round()} kbps'}',
                ),
                _Stage(
                  title: tr.spDecoded,
                  value:
                      '${SignalPath.describe(p.inFormat, p.inRate)} · ${_channels(p.inChannels)}'
                      '${p.sourceBits != null && p.sourceBits != SignalPath.bitsOf(p.inFormat) && !p.inFormat.startsWith('float') ? ' ${tr.spPadded(p.sourceBits!)}' : ''}',
                ),
                for (final f in p.filters) _Stage(title: 'DSP', value: f, changes: true),
                if (p.leveling) _Stage(title: tr.volumeLeveling, value: 'ReplayGain', changes: true),
                _Stage(
                  title: tr.volume,
                  value: (p.volume - 100).abs() < 0.01
                      ? tr.spUntouched
                      : p.volume <= 0
                      ? tr.spMuted
                      : '${(20 * math.log(p.volume / 100) / math.ln10).toStringAsFixed(1)} dB (${p.volumePrecision})',
                  changes: (p.volume - 100).abs() >= 0.01,
                ),
                if (p.clipGuard)
                  _Stage(
                    title: tr.spClipProtection,
                    value: tr.spClipProtectionBody,
                    // Nothing in an untouched song reaches past full scale.
                    changes: !p.untouched,
                  ),
                if (p.inRate != p.outRate)
                  _Stage(
                    title: tr.spResampled,
                    value:
                        '${SignalPath.formatRate(p.inRate)} → ${SignalPath.formatRate(p.outRate)} · ${AudioEngine.resamplerName}',
                    changes: true,
                  ),
                _Stage(
                  title: tr.output,
                  value:
                      '${SignalPath.describe(p.outFormat, p.outRate)} · ${_channels(p.outChannels)}\n'
                      '${outputName(p)}',
                  changes: p.viaSystemMixer,
                  last: p.dac == null,
                ),
                if (p.dac case final dac?)
                  _Stage(
                    title: tr.spDacReceives,
                    value:
                        '${dac.bits == null ? dac.format : '${dac.bits}-bit${dac.isFloat ? ' float' : ''}'} / '
                        '${SignalPath.formatRate(dac.rate)} · ${_channels(dac.channels)} (${dac.format})\n${p.dacName ?? ''}',
                    changes: !p.dacMatches,
                    last: true,
                  ),
                // Bluetooth headphones: their codec takes the Nearby devices permission to read.
                if (p.bluetooth?.needsPermission ?? false)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: BluetoothCodecs.allow,
                      icon: const Icon(Icons.bluetooth_rounded, size: 18),
                      label: Text(tr.showBluetoothCodec),
                    ),
                  ),
                if (OutputMeasure.availableFor(p)) const _MeasureOutput(),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _channels(int n) => switch (n) {
    1 => tr.spMono,
    2 => tr.spStereo,
    final n => tr.spChannels('$n'),
  };
}

/// "Measure output": on a tap, a null test of what Riflay sent PipeWire against the song ([OutputMeasure]), shown
/// the way DeltaWave shows one. The last one is kept for its song, so closing and opening the sheet keeps it.
class _MeasureOutput extends StatefulWidget {
  const _MeasureOutput();

  @override
  State<_MeasureOutput> createState() => _MeasureOutputState();
}

class _MeasureOutputState extends State<_MeasureOutput> {
  static ({String song, OutputMeasurement measurement})? _last;

  late final PlayerController _controller = PlayerScope.read(context);
  bool _running = false;
  MeasureStage _stage = MeasureStage.recording;
  double _progress = 0;
  MeasureProblem? _problem;

  OutputMeasurement? get _shown {
    final last = _last;
    return last != null && last.song == _controller.audio.songKey ? last.measurement : null;
  }

  Future<void> _measure() async {
    setState(() {
      _running = true;
      _problem = null;
      _stage = MeasureStage.recording;
      _progress = 0;
    });
    final song = _controller.audio.songKey;
    try {
      final m = await OutputMeasure.measure(
        _controller.audio,
        onProgress: (stage, progress) {
          // A redraw a tenth of the recording, not one per PipeWire chunk.
          final step = (progress * 10).floor() != (_progress * 10).floor();
          if (mounted && (stage != _stage || step)) {
            setState(() {
              _stage = stage;
              _progress = progress;
            });
          }
        },
      );
      _last = (song: song, measurement: m);
    } on MeasureFailure catch (e) {
      _problem = e.problem;
    } catch (e) {
      debugPrint('Output measurement: $e');
      _problem = MeasureProblem.noMatch;
    }
    if (mounted) setState(() => _running = false);
  }

  static String _db(double v, String unit) => v <= NullTest.floorDb
      ? '−∞ $unit'
      : v >= -NullTest.floorDb
      ? '∞ $unit'
      : '${v.toStringAsFixed(2)} $unit';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final m = _shown;
    final secondary = text.bodySmall?.copyWith(color: AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 24),
          Text(tr.spMeasureOutput, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(tr.spMeasureOutputBody, style: secondary),
          const SizedBox(height: 12),
          if (_running) ...[
            LinearProgressIndicator(value: _stage == MeasureStage.recording ? _progress : null),
            const SizedBox(height: 6),
            Text(switch (_stage) {
              MeasureStage.recording => tr.spMeasureRecording(
                '${(_progress * OutputMeasure.length.inSeconds).floor()}',
                '${OutputMeasure.length.inSeconds}',
              ),
              MeasureStage.decoding => tr.spMeasureDecoding,
              MeasureStage.comparing => tr.spMeasureComparing,
            }, style: secondary),
          ] else ...[
            if (_problem case final problem?) ...[
              Text(switch (problem) {
                MeasureProblem.noRecorder => tr.spMeasureNoRecorder,
                MeasureProblem.noStream => tr.spMeasureNoStream,
                MeasureProblem.twoStreams => tr.spMeasureTwoStreams,
                MeasureProblem.songMoved => tr.spMeasureSongMoved,
                MeasureProblem.noSource => tr.spMeasureNoSource,
                MeasureProblem.noMatch => tr.spMeasureNoMatch,
              }, style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
            ],
            if (m != null) ...[_results(context, m), const SizedBox(height: 8)],
            FilledButton.tonalIcon(
              onPressed: _measure,
              icon: const Icon(Icons.science_outlined, size: 18),
              label: Text(m == null ? tr.spMeasure : tr.spMeasureAgain),
            ),
          ],
        ],
      ),
    );
  }

  Widget _results(BuildContext context, OutputMeasurement m) {
    final text = Theme.of(context).textTheme;
    final r = m.result;
    final share = '${(r.identical * 100).toStringAsFixed(2)}%';
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: text.bodyMedium?.copyWith(color: AppColors.textSecondary)),
          ),
          const SizedBox(width: 12),
          Text(value, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              r.bitPerfect ? Icons.verified_rounded : Icons.graphic_eq_rounded,
              color: r.bitPerfect ? AppColors.accent : AppColors.textPrimary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                r.bitPerfect ? 'Bit Perfect' : tr.spNotBitPerfectShare(share),
                style: text.titleSmall?.copyWith(
                  color: r.bitPerfect ? AppColors.accent : AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        row(tr.spGain, r.gainDb.abs() < 0.005 ? '0 dB' : '${r.gainDb.toStringAsFixed(2)} dB'),
        row(tr.spPhaseOffset, '${r.offsetMs.toStringAsFixed(2)} ms'),
        row(tr.spDifferenceRms, '${_db(r.diffRmsDb, 'dB')} / ${_db(r.diffRmsDba, 'dBA')}'),
        row(tr.spCorrelatedNull, '${_db(r.nullDb, 'dB')} / ${_db(r.nullDba, 'dBA')}'),
        row(tr.spClockDrift, r.driftPpm.abs() < 0.005 ? '0 ppm' : '${r.driftPpm.toStringAsFixed(2)} ppm'),
        row(tr.spFitQuality, switch (r.quality) {
          FitQuality.excellent => tr.spFitExcellent,
          FitQuality.good => tr.spFitGood,
          FitQuality.poor => tr.spFitPoor,
        }),
        const SizedBox(height: 4),
        Text(
          tr.spMeasuredAt(r.seconds.toStringAsFixed(1), SignalPath.formatRate(m.rate)),
          style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// The output API and device, e.g. "WASAPI shared · {0.0.0.00000000}.{…}".
String outputName(SignalPath p) {
  final api = switch (p.output) {
    'pipewire' => tr.spPipewire,
    'pulse' => tr.spPulse,
    'alsa' => p.viaSystemMixer ? 'ALSA' : tr.spAlsaDirect,
    'wasapi' => p.exclusive ? tr.spWasapiExclusive : tr.spWasapiShared,
    'asio' => 'ASIO',
    'coreaudio' => 'Core Audio',
    'opensles' || 'audiotrack' || 'aaudio' =>
      p.usbDacName != null
          ? 'USB DAC${p.usbBitPerfect ? ', bit-perfect (Android 14)' : ' ${tr.spAndroidMixerParen}'} · ${p.usbDacName}'
          : p.bluetooth != null
          ? ['Bluetooth', ?p.bluetooth!.label, ?p.bluetooth!.name].join(' · ')
          : tr.spAndroidMixer,
    'audiounit' => tr.spIosSession,
    final o => o,
  };
  if (p.usbDacName != null) return api;
  return p.device == 'auto' || p.device.isEmpty ? api : '$api · ${p.device.split('/').last}';
}

class _Stage extends StatelessWidget {
  const _Stage({required this.title, required this.value, this.changes = false, this.last = false});

  final String title;
  final String value;

  /// This stage alters the samples.
  final bool changes;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final dot = changes ? AppColors.textSecondary : AppColors.accent;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                const SizedBox(height: 4),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                if (!last) Expanded(child: Container(width: 2, color: AppColors.hover)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.labelMedium?.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 2),
                  Text(value, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
