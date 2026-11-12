import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../models/track.dart';
import '../../services/android_output.dart';
import '../../services/audio_analysis.dart';
import '../../services/audio_engine.dart';
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

/// One group of the sheet: its title, then label / value rows; the values of [lit] rows (by label) are in the
/// accent colour. Built in the reader's language for the screen, and in English for Copy (bug reports).
class _Section {
  const _Section({required this.title, required this.rows, this.lit = const {}});

  final String title;
  final List<(String, String)> rows;
  final Set<String> lit;
}

class _DetailStatsSheet extends StatefulWidget {
  const _DetailStatsSheet();

  @override
  State<_DetailStatsSheet> createState() => _DetailStatsSheetState();
}

class _DetailStatsSheetState extends State<_DetailStatsSheet> {
  SignalPath? _path;
  NerdStats _extra = const NerdStats();
  AndroidOutput? _android;
  bool _read = false;
  Timer? _timer;
  bool _polling = false;
  Animation<double>? _opening;
  late final _scroll = ScrollController(
    onAttach: (position) => position.isScrollingNotifier.addListener(_scrollChanged),
    onDetach: (position) => position.isScrollingNotifier.removeListener(_scrollChanged),
  );
  Timer? _resume;
  bool _dirty = false;

  bool get _scrolling => _scroll.hasClients && _scroll.position.isScrollingNotifier.value;

  void _refresh() {
    if (!mounted) return;
    if (_scrolling) {
      _dirty = true;
    } else {
      _dirty = false;
      setState(() {});
    }
  }

  void _scrollChanged() {
    _resume?.cancel();
    if (_scrolling) return;
    _resume = Timer(const Duration(milliseconds: 180), () {
      if (!mounted || _scrolling) return;
      if (_dirty) _refresh();
      unawaited(_poll());
    });
  }

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
          if (mounted && _reportFor == track.id) {
            _report = r;
            _refresh();
          }
        }, onError: (Object e) => debugPrint('Measuring ${track.title}: $e'))
        .whenComplete(() {
          if (mounted && _reportFor == track.id) {
            _measuring = false;
            _refresh();
          }
        });
  }

  /// The quality tier in words, as the quality badge names it: "Hi-Res Lossless", "Lossless", "Lossy", "DSD".
  static String _quality(SignalPath p) {
    final (tier, _) = qualityTier(p);
    return switch (tier) {
      'Hi-Res' => 'Hi-Res Lossless',
      // TrueHD under the Atmos: it is lossless too.
      'Dolby Atmos' when p.lossless => 'Dolby Atmos · Lossless',
      final tier => tier,
    };
  }

  static final _english = lookupAppLocalizations(const Locale('en'));

  /// The line under the title: "FLAC · 24-bit · 48 kHz".
  static String _summary(SignalPath p, AppLocalizations t) => [
    p.codec.toUpperCase(),
    if (p.isAtmos) 'Dolby Atmos',
    if (p.sourceBits case final bits?) t.dsBits(bits),
    SignalPath.formatRate(p.inRate),
    if (p.bitPerfect) t.dsBitPerfect,
  ].join(' · ');

  static String _khz(double hz) {
    final k = (hz / 1000).toStringAsFixed(1);
    return '${k.endsWith('.0') ? k.substring(0, k.length - 2) : k} kHz';
  }

  /// What the spectrum says, in words: for a lossless file, whether it was made from a lossy one.
  static String _spectrum(AudioReport r, bool lossless, AppLocalizations t) => switch (r.verdict) {
    SourceVerdict.lossyCut when lossless => t.dsCutLossless(_khz(r.cutoffHz!)),
    SourceVerdict.lossyCut => t.dsCutLossy(_khz(r.cutoffHz!)),
    SourceVerdict.upsampled => t.dsUpsampled,
    SourceVerdict.fullBand => t.dsFullBand(_khz(r.cutoffHz ?? r.rate / 2)),
  };

  static String _dr(int dr, AppLocalizations t) =>
      'DR$dr (${dr >= 12
          ? t.dsDrDynamic
          : dr >= 8
          ? t.dsDrModerate
          : t.dsDrHeavy})';

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
    if (!mounted || _polling || _scrolling) return;
    _polling = true;
    final c = PlayerScope.read(context);
    final trackId = c.currentTrack?.id;
    try {
      if (c.currentTrack case final t?) _measure(t);
      final audio = c.audio;
      final path = await audio.signalPath();
      if (!mounted || c.currentTrack?.id != trackId) return;
      final extra = await audio.nerdStats();
      final android = await AndroidOutput.read();
      if (mounted && !_scrolling && c.currentTrack?.id == trackId) {
        setState(() {
          _path = path;
          _extra = extra;
          _android = android;
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
    _resume?.cancel();
    _scroll.dispose();
    _opening?.removeStatusListener(_opened);
    super.dispose();
  }

  static String _bytes(int n) => n < 1 << 20 ? '${(n / 1024).round()} KB' : '${(n / (1 << 20)).toStringAsFixed(1)} MB';

  static String _channels(int n, AppLocalizations t) => switch (n) {
    1 => t.dsMono,
    2 => t.dsStereo,
    final n => t.dsChannelCount(n),
  };

  static String _db(double gain) => '${(20 * math.log(gain) / math.ln10).toStringAsFixed(1)} dB';

  List<_Section> _sections(PlayerController c, Track track, SignalPath p, AppLocalizations t) {
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
    final sections = [
      _Section(
        title: t.dsSong,
        rows: [
          (t.dsTitle, track.title),
          if (track.artist.trim().isNotEmpty) (t.dsArtist, track.artist),
          if (track.album case final album? when album.trim().isNotEmpty) (t.dsAlbum, album),
          (t.dsPosition, '${formatDuration(position)} / ${formatDuration(duration)}'),
          (
            t.dsPlaysFrom,
            streaming
                ? t.dsPlaysStream
                : track.videoId != null
                ? t.dsPlaysDownloaded
                : t.dsPlaysFile,
          ),
          if (track.videoId case final id?)
            streaming ? (t.dsVideoIdItag, '$id / ${stream?.formatId ?? '-'}') : (t.dsVideoId, id)
          else
            (t.dsFile, (track.path ?? track.uri.toString()).split(RegExp(r'[/\\]')).last),
        ],
      ),
      _Section(
        title: t.dsSource,
        lit: {t.dsQuality},
        rows: [
          (t.dsQuality, _quality(p)),
          (t.dsFormat, _extra.codecName ?? (stream == null ? p.codec : stream.codec).toUpperCase()),
          (t.dsSampleRate, SignalPath.formatRate(p.inRate)),
          if (p.sourceBits case final bits?) (t.dsBitDepth, t.dsBits(bits)),
          (
            t.dsBitrate,
            switch ((now, avg)) {
              (0, 0) => '-',
              (final now, 0) => '$now kbps',
              (0, final avg) => t.dsKbpsAvg(avg),
              (final now, final avg) => t.dsKbpsNowAvg(now, avg),
            },
          ),
          (t.dsChannels, _channels(p.inChannels, t)),
          if (p.isAtmos) ('Dolby Atmos', t.dsAtmosBed(p.inChannels)),
          (t.dsContainer, stream == null ? p.container.split(',').first : '${stream.ext} (${stream.mimeType})'),
          if (size != null) (t.dsFileSize, _bytes(size)),
        ],
      ),
      if (p.inRate > 0 && !p.isDsd && !p.isDop)
        _Section(
          title: t.dsSignal,
          rows: [
            (t.dsFrequencyRange, t.dsUpToNyquist(_khz(p.inRate / 2))),
            // What the format can hold (6.02 dB a bit), not what the recording uses: lossy files have no bit depth.
            if (p.lossless && p.sourceBits != null) (t.dsTheoreticalRange, '${(p.sourceBits! * 6.02).round()} dB'),
          ],
        ),
      if (_report != null || _measuring)
        _Section(
          title: t.dsAnalysis,
          rows: switch (_report) {
            null => [(t.dsMeasuring, t.dsReadingFile)],
            final r => [
              (t.dsSpectrum, _spectrum(r, p.lossless, t)),
              if (r.usedBits case final used? when r.storedBits != null)
                (
                  t.dsBitsUsed,
                  r.paddedBits
                      ? t.dsBitsPadded(used, r.storedBits!)
                      : used >= r.storedBits!
                      ? t.dsBitsAll(r.storedBits!)
                      : t.dsBitsOf(used, r.storedBits!),
                ),
              if (r.dr case final dr?) (t.dsDynamicRange, _dr(dr, t)),
              (
                t.dsLoudness,
                '${r.lufs == null ? '-' : '${r.lufs!.toStringAsFixed(1)} LUFS'} · ${t.dsPeak(r.peakDb.toStringAsFixed(1))}',
              ),
              if (r.gainDb case final g?)
                (t.dsMeasuredGain, t.dsMeasuredGainValue('${g >= 0 ? '+' : ''}${g.toStringAsFixed(1)}')),
            ],
          },
        ),
      _Section(
        title: t.dsSound,
        rows: [
          (
            t.dsDecoded,
            '${SignalPath.describe(p.inFormat, p.inRate, stored: p.sourceBits)} · ${_channels(p.inChannels, t)} (${p.inFormat})',
          ),
          if (audio.virtualSpeakersActive && !p.isPassthrough)
            (
              t.dsVirtualRoom,
              switch (audio.virtualRoom) {
                VirtualRoom.stereo => t.dsRoomStereo,
                VirtualRoom.surround => t.dsRoomSurround,
                VirtualRoom.upmix => t.dsRoomUpmix,
              },
            ),
          (t.dsEffects, p.filters.isEmpty ? t.dsNone : p.filters.join(', ')),
          (
            t.dsVolume,
            p.isDop
                ? '100% (DoP)'
                : '${(c.volume * 100).round()}% (${p.volume <= 0 ? t.dsMuted : _db(p.volume / 100)}, ${p.volumePrecision})',
          ),
          (
            t.dsLeveling,
            level == VolumeLeveling.off
                ? t.dsOff
                : '${level.label}${_extra.gain == null ? ', ${t.dsNoReplayGain}' : ' (${_extra.gain})'}',
          ),
          if (stream?.loudness case final lufs?)
            (
              t.dsLoudness,
              switch (stream!.loudnessTarget) {
                null => '${lufs.toStringAsFixed(1)} LUFS',
                // The level YouTube's own player brings it to.
                final target => t.dsLoudnessTarget(lufs.toStringAsFixed(1), target.toStringAsFixed(0)),
              },
            ),
          if (audio.effectiveTempo != 1 || audio.effectivePitch != 0)
            (
              t.dsTempoPitch,
              t.dsTempoPitchValue(
                audio.effectiveTempo.toStringAsFixed(2),
                '${audio.effectivePitch > 0 ? '+' : ''}${audio.effectivePitch}',
              ),
            ),
          (t.dsCrossfade, audio.crossfade ? '${audio.crossfadeSeconds} s' : t.dsOff),
          if (p.clipGuard) (t.dsClipProtection, t.dsOn),
        ],
      ),
      _Section(
        title: t.dsOutput,
        rows: [
          (
            t.dsFormat,
            '${SignalPath.describe(p.outFormat, p.outRate)} · ${_channels(p.outChannels, t)} (${p.outFormat})',
          ),
          if (p.inRate != p.outRate)
            (
              t.dsResampled,
              '${SignalPath.formatRate(p.inRate)} → ${SignalPath.formatRate(p.outRate)} · ${AudioEngine.resamplerName}',
            ),
          if (p.isPassthrough) (t.dsPassthrough, t.dsPassthroughValue(p.codec.toUpperCase())),
          (t.dsDevice, outputName(p)),
          if (_android case final a?) ...[
            if (a.mixerRate case final r?) (t.dsDeviceRate, SignalPath.formatRate(r)),
            if (a.deviceBits case final bits?) (t.dsDeviceFormat, t.dsBits(bits)),
            if (a.bufferMs case final ms?)
              (t.dsMixerBuffer, t.dsMixerBufferValue(ms.toStringAsFixed(1), a.framesPerBuffer!)),
            (t.dsLowLatency, a.lowLatency ? t.dsSupported : t.dsNotSupported),
            (t.dsProAudio, a.pro ? t.dsSupported : t.dsNotSupported),
            (
              t.dsSpatialAudio,
              switch (a.spatial) {
                AndroidSpatial.on => t.dsOn,
                AndroidSpatial.off => t.dsOff,
                AndroidSpatial.unsupported => t.dsNotSupported,
              },
            ),
            if ((a.volume, a.maxVolume) case (final v?, final max?)) (t.dsSystemVolume, '$v / $max'),
          ],
          if (p.bluetooth case final bt?)
            (t.dsBluetooth, [bt.label ?? (bt.needsPermission ? t.dsBtAllow : t.dsBtUnknown), ?bt.name].join(' · ')),
          if (p.dac case final dac?)
            (
              t.dsDacReceives,
              '${dac.bits == null ? dac.format : '${dac.bits}-bit${dac.isFloat ? ' float' : ''}'} / '
                  '${SignalPath.formatRate(dac.rate)} · ${_channels(dac.channels, t)}${p.dacName == null ? '' : '\n${p.dacName}'}',
            ),
          if (audio.directUsbActive) (t.dsDirectUsb, t.dsOn),
          (t.dsBitPerfect, p.bitPerfect ? t.dsYes : t.dsNo),
        ],
      ),
      if (streaming && yt != null)
        _Section(
          title: t.dsNetwork,
          rows: [
            if (yt.bitsPerSecond case final bps?) (t.dsConnectionSpeed, '${(bps / 1000).round()} Kbps'),
            if (_extra.readSpeed case final speed? when speed > 0) (t.dsReadingNow, '${_bytes(speed)}/s'),
            // Can pass the file's size: mpv reads some parts twice (a webm's index sits at the end).
            (
              t.dsReceived,
              stream?.size == null ? _bytes(yt.received) : t.dsReceivedOf(_bytes(yt.received), _bytes(stream!.size!)),
            ),
            if (_extra.buffered case final s?) (t.dsBufferHealth, '${s.toStringAsFixed(2)} s'),
            if (stream != null) (t.dsStreamUrlFrom, stream.via),
          ],
        )
      else if (_extra.buffered case final s?)
        _Section(title: t.dsReading, rows: [(t.dsBufferHealth, '${s.toStringAsFixed(2)} s')]),
    ];
    // The file first, as a glance at the sheet asks "what am I hearing"; the song's names are on screen already.
    final order = [t.dsSource, t.dsSignal, t.dsAnalysis, t.dsSound, t.dsOutput, t.dsSong];
    int rank(_Section s) => switch (order.indexOf(s.title)) {
      -1 => order.length,
      final i => i,
    };
    return sections..sort((a, b) => rank(a).compareTo(rank(b)));
  }

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.identity(context);
    final text = Theme.of(context).textTheme;
    final track = c.currentTrack;
    final p = _path;
    final sections = track == null || p == null ? const <_Section>[] : _sections(c, track, p, tr);
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
            for (final s in _sections(c, track!, p!, _english)) ...[
              '[${s.title}]',
              for (final (k, v) in s.rows) '$k: ${v.replaceAll('\n', ' · ')}',
            ],
          ].join('\n'),
        ),
      );
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(tr.statsCopied), duration: Duration(seconds: 2)));
    }

    // The title and the line under it stay put while the groups scroll under them; Copy floats at the bottom.
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr.detailStats, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          if (p != null && sections.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(_summary(p, tr), style: text.bodyMedium?.copyWith(color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
    final items = <Widget>[
      if (status != null || sections.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(status ?? tr.waitingForAudio, style: text.bodyMedium?.copyWith(color: AppColors.textSecondary)),
        ),
      for (final (i, s) in sections.indexed) ...[
        SizedBox(height: i == 0 ? 8 : 24),
        RepaintBoundary(child: _Card(section: s)),
      ],
      if (_report case final r? when r.spectrogram != null && r.columns > 0) ...[
        const SizedBox(height: 16),
        RepaintBoundary(child: Spectrogram(report: r)),
      ],
      if (sections.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(tr.statsHint, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
      ],
    ];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ListView.builder(
                      controller: _scroll,
                      // Room at the end for the Copy button floating over the last rows.
                      padding: EdgeInsets.fromLTRB(24, 0, 24, sections.isEmpty ? 24 : 96),
                      itemCount: items.length,
                      itemBuilder: (_, i) => items[i],
                    ),
                  ),
                  if (sections.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 16,
                      child: Center(
                        child: FilledButton.tonalIcon(
                          onPressed: copy,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                            shape: const StadiumBorder(),
                            elevation: 2,
                          ),
                          icon: const Icon(Icons.copy_rounded, size: 20),
                          label: Text(tr.copyStats),
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

/// One group: its title in the accent colour, then a tile per row (label at the start, value at the end), the
/// group's ends rounded more than the joins between its tiles.
class _Card extends StatelessWidget {
  const _Card({required this.section});

  final _Section section;

  static const _outer = Radius.circular(20), _inner = Radius.circular(4);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final label = text.bodyLarge?.copyWith(color: AppColors.textPrimary);
    final value = text.bodyMedium?.copyWith(
      color: AppColors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final lit = value?.copyWith(color: AppColors.accent, fontWeight: FontWeight.w700);
    final rows = section.rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Text(
            section.title,
            style: text.titleSmall?.copyWith(color: AppColors.accent, fontWeight: FontWeight.w700),
          ),
        ),
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.hover,
                borderRadius: BorderRadius.vertical(
                  top: i == 0 ? _outer : _inner,
                  bottom: i == rows.length - 1 ? _outer : _inner,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(flex: 3, child: Text(rows[i].$1, style: label)),
                    const SizedBox(width: 16),
                    // Plain text: a selectable one costs an editor each, rebuilt every second (Copy has them all).
                    Expanded(
                      flex: 3,
                      child: Text(
                        rows[i].$2,
                        textAlign: TextAlign.end,
                        style: section.lit.contains(rows[i].$1) ? lit : value,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
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
                Text(tr.dsSpectrogram, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
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
