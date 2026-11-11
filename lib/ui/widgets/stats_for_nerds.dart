import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart';

import '../../models/track.dart';
import '../../services/audio_analysis.dart';
import '../../services/audio_engine.dart';
import '../../services/extensions/extension_finds.dart';
import '../../services/language.dart';
import '../../services/player_controller.dart';
import '../../services/youtube_audio_source.dart';
import '../theme.dart';
import 'controls.dart';
import 'menus.dart';
import 'signal_path.dart';

/// The now-playing cover, with a menu on right-click / long-press for Detail
/// stats and Signal path (as YouTube's video has).
class NowPlayingCover extends StatelessWidget {
  const NowPlayingCover({super.key, required this.child});

  final Widget child;

  /// The menu's entries; [handle] runs the one picked. Also in the ⋯ menu of
  /// the now-playing views, so it isn't only behind a right-click.
  static List<PopupMenuItem<String>> menuItems() => [
    PopupMenuItem(
      value: 'stats',
      child: MenuRow(leading: const Icon(Icons.query_stats_rounded), title: Text(tr.detailStats)),
    ),
    PopupMenuItem(
      value: 'path',
      child: MenuRow(leading: Icon(Icons.graphic_eq_rounded), title: Text(tr.signalPath)),
    ),
  ];

  /// Does what the picked [menuItems] entry says.
  static Future<void> handle(BuildContext context, String? choice) async {
    switch (choice) {
      case 'stats':
        await showDetailStats(context);
      case 'path':
        await showSignalPath(context);
    }
  }

  static Future<void> _menu(BuildContext context, Offset at) async {
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(at & Size.zero, Offset.zero & overlay.size),
      color: AppColors.menu,
      shape: menuShape,
      items: menuItems(),
    );
    if (!context.mounted) return;
    await handle(context, choice);
  }

  @override
  Widget build(BuildContext context) {
    if (!AudioEngine.supported) return child;
    return GestureDetector(
      onSecondaryTapUp: (d) => _menu(context, d.globalPosition),
      onLongPressStart: (d) => _menu(context, d.globalPosition),
      child: child,
    );
  }
}

/// Detail stats, as on YouTube but laid out like Signal path: the song playing, read live once a second, in a
/// sheet of cards (the song, its source, what is done to the sound, where it goes, the connection).
Future<void> showDetailStats(BuildContext context) {
  final c = PlayerScope.read(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.elevated,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => PlayerScope(controller: c, child: const _DetailStatsSheet()),
  );
}

/// One card of the sheet: its icon and title, then label / value rows.
typedef _Section = ({IconData icon, String title, List<(String, String)> rows});

class _DetailStatsSheet extends StatefulWidget {
  const _DetailStatsSheet();

  @override
  State<_DetailStatsSheet> createState() => _DetailStatsSheetState();
}

class _DetailStatsSheetState extends State<_DetailStatsSheet> {
  SignalPath? _path;
  NerdStats _extra = const NerdStats();
  bool _read = false;
  Timer? _timer;
  bool _polling = false;
  Animation<double>? _opening;

  /// The song's file measured (spectrum, dynamic range, loudness): once per song shown here.
  AudioReport? _report;
  String? _reportFor;
  bool _measuring = false;

  void _measure(Track track) {
    if (_reportFor == track.id) return;
    _reportFor = track.id;
    _report = null;
    _measuring = false;
    if (AudioAnalysis.fileOf(track) == null || !AudioAnalysis.supported) return;
    _measuring = true;
    AudioAnalysis.of(track, spectrogram: true)
        .then((r) {
          if (mounted && _reportFor == track.id) setState(() => _report = r);
        }, onError: (Object e) => debugPrint('Measuring ${track.title}: $e'))
        .whenComplete(() {
          if (mounted && _reportFor == track.id) setState(() => _measuring = false);
        });
  }

  static String _khz(double hz) => '${(hz / 1000).toStringAsFixed(1)} kHz';

  /// What the spectrum says, in words: for a lossless file, whether it was made from a lossy one.
  static String _spectrum(AudioReport r, bool lossless) => switch (r.verdict) {
    SourceVerdict.lossyCut when lossless => 'Cut at ${_khz(r.cutoffHz!)}: probably made from an MP3 or AAC',
    SourceVerdict.lossyCut => 'Cut at ${_khz(r.cutoffHz!)}, as lossy files are',
    SourceVerdict.upsampled => 'Nothing above about 22 kHz: upsampled from 44.1 / 48 kHz',
    SourceVerdict.fullBand =>
      r.cutoffHz == null ? 'Full band, up to ${_khz(r.rate / 2)}' : 'Full band, up to ${_khz(r.cutoffHz!)}',
  };

  static String _dr(int dr) =>
      'DR$dr (${dr >= 12
          ? 'dynamic'
          : dr >= 8
          ? 'moderately compressed'
          : 'heavily compressed'})';

  @override
  void initState() {
    super.initState();
    // Let the popup finish opening before starting file analysis and native reads.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final opening = ModalRoute.of(context)?.animation;
      if (opening == null || opening.status == AnimationStatus.completed) {
        _startPolling();
      } else {
        _opening = opening..addStatusListener(_opened);
      }
    });
  }

  void _opened(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _opening?.removeStatusListener(_opened);
    _opening = null;
    _startPolling();
  }

  void _startPolling() {
    if (!mounted || _timer != null) return;
    unawaited(_poll());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_poll()));
  }

  Future<void> _poll() async {
    if (!mounted || _polling) return;
    _polling = true;
    final c = PlayerScope.read(context);
    final trackId = c.currentTrack?.id;
    try {
      if (c.currentTrack case final t?) _measure(t);
      final audio = c.audio;
      final path = await audio.signalPath();
      if (!mounted || c.currentTrack?.id != trackId) return;
      final extra = await audio.nerdStats();
      if (mounted && c.currentTrack?.id == trackId) {
        setState(() {
          _path = path;
          _extra = extra;
          _read = true;
        });
      }
    } catch (e) {
      debugPrint('Reading detail stats: $e');
    } finally {
      _polling = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _opening?.removeStatusListener(_opened);
    super.dispose();
  }

  static String _bytes(int n) => n < 1 << 20 ? '${(n / 1024).round()} KB' : '${(n / (1 << 20)).toStringAsFixed(1)} MB';

  static String _channels(int n) => switch (n) {
    1 => 'Mono',
    2 => 'Stereo',
    final n => '$n channels',
  };

  static String _db(double gain) => '${(20 * math.log(gain) / math.ln10).toStringAsFixed(1)} dB';

  List<_Section> _sections(PlayerController c, Track track, SignalPath p) {
    final streaming = c.player.sequenceState.currentSource is YoutubeAudioSource;
    final yt = track.videoId == null ? null : YoutubeAudioSource.statsOf(track.videoId!);
    final stream = streaming ? yt?.stream : null;
    final audio = c.audio;
    final level = audio.effectiveLeveling;
    final position = c.player.position;
    final duration = c.player.duration;
    final now = ((p.bitrate ?? 0) / 1000).round();
    final avg = stream?.kbps ?? 0;
    final size = stream?.size ?? _extra.fileSize;
    return [
      (
        icon: Icons.music_note_rounded,
        title: 'Song',
        rows: [
          ('Title', track.title),
          if (track.artist.trim().isNotEmpty) ('Artist', track.artist),
          if (track.album case final album? when album.trim().isNotEmpty) ('Album', album),
          ('Position', '${formatDuration(position)} / ${formatDuration(duration)}'),
          (
            'Plays from',
            streaming
                ? 'YouTube Music stream'
                : track.videoId != null
                ? 'Downloaded copy'
                : 'File on this device',
          ),
          // An extension only finds a song; the sound is the same song matched on YouTube Music.
          if (ExtensionFinds.of(track) case final ext?) ('Found with', '$ext extension · matched on YouTube Music'),
          if (track.videoId case final id?)
            streaming ? ('Video ID / itag', '$id / ${stream?.formatId ?? '-'}') : ('Video ID', id)
          else
            ('File', (track.path ?? track.uri.toString()).split(RegExp(r'[/\\]')).last),
        ],
      ),
      (
        icon: Icons.album_rounded,
        title: 'Source',
        rows: [
          ('Codec', _extra.codecName ?? (stream == null ? p.codec : stream.codec)),
          ('Container', stream == null ? p.container.split(',').first : '${stream.ext} (${stream.mimeType})'),
          (
            'Bitrate',
            switch ((now, avg)) {
              (0, 0) => '-',
              (final now, 0) => '$now kbps',
              (0, final avg) => '$avg kbps (avg)',
              (final now, final avg) => '$now kbps (avg $avg)',
            },
          ),
          ('Sample rate', SignalPath.formatRate(p.inRate)),
          if (p.sourceBits case final bits?) ('Bit depth', '$bits-bit'),
          ('Channels', _channels(p.inChannels)),
          ('Lossless', p.lossless ? 'Yes' : 'No'),
          if (size != null) ('File size', _bytes(size)),
        ],
      ),
      if (_report != null || _measuring)
        (
          icon: Icons.analytics_rounded,
          title: 'Analysis',
          rows: switch (_report) {
            null => [('Measuring', 'Reading the whole file…')],
            final r => [
              ('Spectrum', _spectrum(r, p.lossless)),
              if (r.dr case final dr?) ('Dynamic range', _dr(dr)),
              (
                'Loudness',
                '${r.lufs == null ? '-' : '${r.lufs!.toStringAsFixed(1)} LUFS'} · peak ${r.peakDb.toStringAsFixed(1)} dBFS',
              ),
              if (r.gainDb case final g?)
                (
                  'Measured gain',
                  '${g >= 0 ? '+' : ''}${g.toStringAsFixed(1)} dB (leveling uses it without ReplayGain tags)',
                ),
            ],
          },
        ),
      (
        icon: Icons.tune_rounded,
        title: 'Sound',
        rows: [
          (
            'Decoded',
            '${SignalPath.describe(p.inFormat, p.inRate, stored: p.sourceBits)} · ${_channels(p.inChannels)} (${p.inFormat})',
          ),
          ('Effects', p.filters.isEmpty ? 'None' : p.filters.join(', ')),
          (
            'Volume',
            p.isDop
                ? '100% (DoP)'
                : '${(c.volume * 100).round()}% (${p.volume <= 0 ? 'muted' : _db(p.volume / 100)}, ${p.volumePrecision})',
          ),
          (
            'Leveling',
            level == VolumeLeveling.off
                ? 'Off'
                : '${level.label}${_extra.gain == null ? ', no ReplayGain tag' : ' (${_extra.gain})'}',
          ),
          if (stream?.loudness case final lufs?)
            (
              'Loudness',
              switch (stream!.loudnessTarget) {
                null => '${lufs.toStringAsFixed(1)} LUFS',
                // The level YouTube's own player brings it to.
                final target => '${lufs.toStringAsFixed(1)} LUFS (target ${target.toStringAsFixed(0)} LUFS)',
              },
            ),
          if (audio.effectiveTempo != 1 || audio.effectivePitch != 0)
            (
              'Tempo / pitch',
              '${audio.effectiveTempo.toStringAsFixed(2)}× / '
                  '${audio.effectivePitch > 0 ? '+' : ''}${audio.effectivePitch} semitones',
            ),
          ('Crossfade', audio.crossfade ? '${audio.crossfadeSeconds} s' : 'Off'),
          if (p.clipGuard) ('Clip protection', 'On'),
        ],
      ),
      (
        icon: Icons.speaker_rounded,
        title: 'Output',
        rows: [
          ('Format', '${SignalPath.describe(p.outFormat, p.outRate)} · ${_channels(p.outChannels)} (${p.outFormat})'),
          if (p.inRate != p.outRate)
            (
              'Resampled',
              '${SignalPath.formatRate(p.inRate)} → ${SignalPath.formatRate(p.outRate)} · ${AudioEngine.resamplerName}',
            ),
          ('Device', outputName(p)),
          if (p.bluetooth case final bt?)
            (
              'Bluetooth',
              [
                bt.label ?? (bt.needsPermission ? 'codec: allow Nearby devices' : 'codec unknown'),
                ?bt.name,
              ].join(' · '),
            ),
          if (p.dac case final dac?)
            (
              'DAC receives',
              '${dac.bits == null ? dac.format : '${dac.bits}-bit${dac.isFloat ? ' float' : ''}'} / '
                  '${SignalPath.formatRate(dac.rate)} · ${_channels(dac.channels)}${p.dacName == null ? '' : '\n${p.dacName}'}',
            ),
          if (audio.directUsbActive) ('Direct USB', 'On'),
          ('Bit-perfect', p.bitPerfect ? 'Yes' : 'No'),
        ],
      ),
      if (streaming && yt != null)
        (
          icon: Icons.wifi_rounded,
          title: 'Network',
          rows: [
            if (yt.bitsPerSecond case final bps?) ('Connection speed', '${(bps / 1000).round()} Kbps'),
            if (_extra.readSpeed case final speed? when speed > 0) ('Reading now', '${_bytes(speed)}/s'),
            // Can pass the file's size: mpv reads some parts twice (a webm's index sits at the end).
            ('Received', '${_bytes(yt.received)}${stream?.size == null ? '' : ' of ${_bytes(stream!.size!)}'}'),
            if (_extra.buffered case final s?) ('Buffer health', '${s.toStringAsFixed(2)} s'),
            if (stream != null) ('Stream URL from', stream.via),
          ],
        )
      else if (_extra.buffered case final s?)
        (icon: Icons.storage_rounded, title: 'Reading', rows: [('Buffer health', '${s.toStringAsFixed(2)} s')]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.of(context);
    final text = Theme.of(context).textTheme;
    final track = c.currentTrack;
    final p = _path;
    final sections = track == null || p == null ? const <_Section>[] : _sections(c, track, p);
    final status = track == null
        ? tr.statsNothingPlaying
        : c.casting
        ? tr.statsOtherDevice
        : _read
        ? null
        : tr.waitingForAudio;
    void copy() {
      Clipboard.setData(
        ClipboardData(
          text: [
            for (final s in sections) ...[
              '[${s.title}]',
              for (final (k, v) in s.rows) '$k: ${v.replaceAll('\n', ' · ')}',
            ],
          ].join('\n'),
        ),
      );
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(tr.statsCopied), duration: Duration(seconds: 2)));
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(tr.detailStats, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (sections.isNotEmpty)
                  IconButton(tooltip: tr.copyStats, onPressed: copy, icon: const Icon(Icons.copy_rounded)),
              ],
            ),
            const SizedBox(height: 8),
            if (p != null && sections.isNotEmpty) _Badges(path: p),
            if (status != null || sections.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  status ?? tr.waitingForAudio,
                  style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                ),
              ),
            for (final s in sections) ...[const SizedBox(height: 16), _Card(section: s)],
            if (_report case final r? when r.spectrogram != null && r.columns > 0) ...[
              const SizedBox(height: 16),
              RepaintBoundary(child: Spectrogram(report: r)),
            ],
            if (sections.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(tr.statsHint, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
            ],
          ],
        ),
      ),
    );
  }
}

/// The few facts worth a glance, as chips at the top: the codec, lossless or not, the rate and bits, bit-perfect.
class _Badges extends StatelessWidget {
  const _Badges({required this.path});

  final SignalPath path;

  @override
  Widget build(BuildContext context) {
    final p = path;
    final kbps = ((p.bitrate ?? 0) / 1000).round();
    Widget chip(String label, {bool lit = false, IconData? icon}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: lit ? AppColors.accent.withValues(alpha: 0.16) : AppColors.hover,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: lit ? AppColors.accent : AppColors.textSecondary),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w700, color: lit ? AppColors.accent : AppColors.textPrimary),
          ),
        ],
      ),
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip(p.codec.toUpperCase(), icon: Icons.graphic_eq_rounded),
        chip(p.lossless ? 'Lossless' : 'Lossy', lit: p.lossless),
        if (kbps > 0) chip('$kbps kbps'),
        chip(SignalPath.formatRate(p.inRate)),
        if (p.sourceBits case final bits?) chip('$bits-bit'),
        if (p.bitPerfect) chip('Bit-perfect', lit: true, icon: Icons.verified_rounded),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.section});

  final _Section section;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final value = text.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.hover.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(section.icon, size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                Text(section.title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 8),
            for (final (label, v) in section.rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 128,
                      child: Text(label, style: text.bodySmall?.copyWith(color: AppColors.textSecondary)),
                    ),
                    const SizedBox(width: 12),
                    // Plain text: a selectable one costs an editor each, rebuilt every second (Copy has them all).
                    Expanded(child: Text(v, style: value)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A song's spectrogram: time across, frequency up (to the top of the file's band), loudness as colour, with a
/// line where a cut was found.
class Spectrogram extends StatefulWidget {
  const Spectrogram({super.key, required this.report});

  final AudioReport report;

  @override
  State<Spectrogram> createState() => _SpectrogramState();
}

class _SpectrogramState extends State<Spectrogram> {
  ui.Image? _image;
  int _revision = 0;

  /// Dark blue through purple and orange to pale yellow: quiet to loud.
  static const _stops = [
    (0.0, Color(0xFF000004)),
    (0.25, Color(0xFF3B0F70)),
    (0.5, Color(0xFF8C2981)),
    (0.7, Color(0xFFDE4968)),
    (0.85, Color(0xFFFE9F6D)),
    (1.0, Color(0xFFFCFDBF)),
  ];

  static Color _colour(double t) {
    for (var i = 1; i < _stops.length; i++) {
      final (b, cb) = _stops[i];
      final (a, ca) = _stops[i - 1];
      if (t <= b) return Color.lerp(ca, cb, (t - a) / (b - a))!;
    }
    return _stops.last.$2;
  }

  @override
  void initState() {
    super.initState();
    _draw();
  }

  @override
  void didUpdateWidget(Spectrogram old) {
    super.didUpdateWidget(old);
    if (!identical(old.report, widget.report)) _draw();
  }

  static Uint8List _pixels(AudioReport r) {
    final data = r.spectrogram!, w = r.columns, h = AudioAnalyzer.rows;
    final palette = [for (var v = 0; v < 256; v++) _colour(((v / 255) - 0.25).clamp(0.0, 0.75) / 0.75)];
    final pixels = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        // Stored bottom row first; an image's first row is its top.
        final c = palette[data[y * w + x]];
        final o = ((h - 1 - y) * w + x) * 4;
        pixels[o] = (c.r * 255).round();
        pixels[o + 1] = (c.g * 255).round();
        pixels[o + 2] = (c.b * 255).round();
        pixels[o + 3] = 255;
      }
    }
    return pixels;
  }

  Future<void> _draw() async {
    final revision = ++_revision;
    final r = widget.report;
    final pixels = await compute(_pixels, r);
    if (!mounted || revision != _revision) return;
    final w = r.columns, h = AudioAnalyzer.rows;
    ui.decodeImageFromPixels(pixels, w, h, ui.PixelFormat.rgba8888, (image) {
      if (mounted && revision == _revision) {
        setState(() {
          _image?.dispose();
          _image = image;
        });
      } else {
        image.dispose();
      }
    });
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final r = widget.report;
    final top = r.rate / 2;
    final muted = text.labelSmall?.copyWith(color: AppColors.textSecondary);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.hover.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.waves_rounded, size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                Text('Spectrogram', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 160,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 52,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final f in [top, top * 3 / 4, top / 2, top / 4, 0.0])
                          Text('${(f / 1000).round()} kHz', style: muted),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CustomPaint(
                        painter: _SpectrogramPainter(_image, cutoff: r.cutoffHz, top: top),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpectrogramPainter extends CustomPainter {
  _SpectrogramPainter(this.image, {required this.cutoff, required this.top});

  final ui.Image? image;
  final double? cutoff;
  final double top;

  @override
  void paint(Canvas canvas, Size size) {
    final image = this.image;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF000004));
    if (image != null) {
      paintImage(
        canvas: canvas,
        rect: Offset.zero & size,
        image: image,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
      );
    }
    if (cutoff case final hz? when hz < top) {
      final y = size.height * (1 - hz / top);
      final pen = Paint()
        ..color = const Color(0xCCFFFFFF)
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, size.width), y), pen);
      }
    }
  }

  @override
  bool shouldRepaint(_SpectrogramPainter old) => old.image != image || old.cutoff != cutoff || old.top != top;
}
