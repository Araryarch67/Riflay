import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/track.dart';
import '../../services/audio_lab.dart';
import '../../services/auto_eq.dart';
import '../../services/language.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../../services/visualizer_levels.dart';
import '../pages/audio_lab_page.dart';
import '../pages/lyrics_page.dart';
import '../theme.dart';
import '../widgets/audio_reactive_view.dart';
import '../widgets/controls.dart';
import '../widgets/menus.dart';
import '../widgets/signal_path.dart';
import '../widgets/stats_for_nerds.dart';

/// What the desktop's expanded player shows: the cover (with lyrics or the equalizer beside it), or one of the
/// other modes filling the whole space.
enum ExpandedMode {
  cover(Icons.album_outlined),
  lyrics(Icons.lyrics_outlined),
  vinyl(Icons.album_rounded),
  visualizer(Icons.graphic_eq_rounded),
  ambient(Icons.schedule_rounded),
  hifi(Icons.tune_rounded),
  queue(Icons.queue_music_rounded);

  const ExpandedMode(this.icon);

  final IconData icon;

  String get label => switch (this) {
    cover => tr.modeCover,
    lyrics => tr.lyrics,
    vinyl => tr.modeVinyl,
    visualizer => tr.visualizer,
    ambient => tr.modeAmbient,
    hifi => tr.modeHifi,
    queue => tr.upNext,
  };
}

/// The expanded player's mode, kept between runs.
final expandedMode = _ModeNotifier();

class _ModeNotifier extends ValueNotifier<ExpandedMode> {
  _ModeNotifier() : super(ExpandedMode.cover) {
    unawaited(_load());
  }

  static const _key = 'player.expandedMode';

  Future<void> _load() async {
    try {
      final saved = ExpandedMode.values.asNameMap()[(await SharedPreferences.getInstance()).getString(_key)];
      if (saved != null) value = saved;
    } catch (_) {
      // No saved settings (tests): the cover.
    }
  }

  @override
  set value(ExpandedMode mode) {
    if (mode == super.value) return;
    super.value = mode;
    unawaited(SharedPreferences.getInstance().then((p) => p.setString(_key, mode.name)).catchError((_) => true));
  }
}

/// The mode picker: the mode's icon, a menu of the modes with their keys (1-7).
class ExpandedModeButton extends StatelessWidget {
  const ExpandedModeButton({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ValueListenableBuilder(
      valueListenable: expandedMode,
      builder: (context, mode, _) => MenuAnchor(
        alignmentOffset: const Offset(0, 6),
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.menu),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(menuShape),
          elevation: const WidgetStatePropertyAll(12),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
        ),
        menuChildren: [
          for (final (i, m) in ExpandedMode.values.indexed)
            MenuItemButton(
              onPressed: () => expandedMode.value = m,
              style: MenuItemButton.styleFrom(
                minimumSize: const Size(220, 44),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                foregroundColor: m == mode ? AppColors.accent : AppColors.textPrimary,
              ),
              leadingIcon: Icon(m.icon, size: 20, color: m == mode ? AppColors.accent : AppColors.textSecondary),
              trailingIcon: Text('${i + 1}', style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
              child: Text(
                m.label,
                style: text.bodyMedium?.copyWith(fontWeight: m == mode ? FontWeight.w700 : FontWeight.w500),
              ),
            ),
        ],
        builder: (context, controller, _) => IconButton(
          tooltip: '${tr.expandedMode}: ${mode.label}',
          onPressed: () => controller.isOpen ? controller.close() : controller.open(),
          icon: Icon(mode.icon),
        ),
      ),
    );
  }
}

/// [mode]'s page for [track] (the cover mode is the expanded player's own).
Widget expandedModeView(ExpandedMode mode, Track track, {required Color accent}) => switch (mode) {
  ExpandedMode.cover => const SizedBox.shrink(),
  ExpandedMode.lyrics => _LyricsMode(track: track),
  ExpandedMode.vinyl => _VinylMode(track: track),
  ExpandedMode.visualizer => _VisualizerMode(track: track, accent: accent),
  ExpandedMode.ambient => _AmbientMode(track: track),
  ExpandedMode.hifi => _HifiMode(track: track, accent: accent),
  ExpandedMode.queue => const _QueueMode(),
};

/// The song in one line: its cover, title and artist.
class _SongLine extends StatelessWidget {
  const _SongLine({required this.track, this.size = 56, this.center = false});

  final Track track;
  final double size;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: center ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Artwork(track: track, size: size, radius: size / 6),
        const SizedBox(width: 14),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Lyrics ------------------------------------------------------------------------------------------------------------

/// The lyrics across the whole space, the song in a line above them.
class _LyricsMode extends StatelessWidget {
  const _LyricsMode({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 8, 20, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _SongLine(track: track)),
            LyricsExtrasButtons(key: ValueKey(track.id), track: track),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: LyricsView(track: track),
            ),
          ),
        ),
      ],
    ),
  );
}

// Vinyl -------------------------------------------------------------------------------------------------------------

/// The vinyl mode: the deck, the song under it.
class _VinylMode extends StatelessWidget {
  const _VinylMode({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final side = math.min(box.maxHeight - 110, box.maxWidth * 0.55).clamp(160.0, 760.0);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            VinylDeck(track: track, size: side),
            const SizedBox(height: 28),
            SizedBox(
              width: side * 1.2,
              child: _SongLine(track: track, center: true),
            ),
          ],
        ),
      );
    },
  );
}

/// A record turning at 33⅓ while the song plays, its cover the label, the tone arm down on it; paused, it slows to
/// a stop and the arm lifts off. [size] is the record's; the arm takes a fifth more beside it. The desktop's vinyl
/// mode, and the phone player's Vinyl cover.
class VinylDeck extends StatefulWidget {
  const VinylDeck({super.key, required this.track, required this.size});

  final Track? track;
  final double size;

  /// How much wider than [size] the deck is, with its arm.
  static const armRoom = 1.2;

  @override
  State<VinylDeck> createState() => _VinylDeckState();
}

class _VinylDeckState extends State<VinylDeck> with SingleTickerProviderStateMixin {
  // 33⅓ turns a minute.
  late final _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  void _follow(bool playing) {
    if (!LayoutPrefs.moves) return;
    if (playing && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!playing && _spin.isAnimating) {
      // Slows to a stop over a part of a turn, as a platter does.
      final at = _spin.value;
      _spin.animateTo(
        at + 0.15 > 1 ? 1 : at + 0.15,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) => PlayerSelect<bool>(
    select: (c) => c.showsPlaying,
    builder: (context, playing, _) {
      _follow(playing);
      final side = widget.size;
      return SizedBox(
        width: side * VinylDeck.armRoom,
        height: side,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: side,
              height: side,
              child: RotationTransition(
                turns: _spin,
                child: _Record(track: widget.track),
              ),
            ),
            // The arm, pivoting at its top: on the record while it plays, lifted off beside it paused.
            Positioned(
              left: side * 0.86,
              top: side * 0.02,
              width: side * 0.3,
              height: side * 0.8,
              child: AnimatedRotation(
                turns: playing ? 0.035 : -0.02,
                alignment: const Alignment(0.3, -0.85),
                duration: LayoutPrefs.dur(const Duration(milliseconds: 600)),
                curve: Curves.easeInOutCubic,
                child: const CustomPaint(painter: _ArmPainter()),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _Record extends StatelessWidget {
  const _Record({required this.track});

  final Track? track;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final d = box.maxWidth;
      return Stack(
        alignment: Alignment.center,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 40, offset: Offset(0, 18))],
            ),
            child: SizedBox.square(
              dimension: d,
              child: const CustomPaint(painter: _GroovesPainter()),
            ),
          ),
          ClipOval(
            child: Artwork(track: track, size: d * 0.38, radius: 0),
          ),
          // The spindle.
          Container(
            width: d * 0.025,
            height: d * 0.025,
            decoration: const BoxDecoration(color: Color(0xFF111111), shape: BoxShape.circle),
          ),
        ],
      );
    },
  );
}

/// The record's black face: its grooves, and light caught across it.
class _GroovesPainter extends CustomPainter {
  const _GroovesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF0D0D0F));
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    for (var k = r * 0.2; k < r * 0.97; k += r * 0.012) {
      groove.color = Colors.white.withValues(alpha: 0.025 + 0.02 * ((k / r * 37).floor() % 2));
      canvas.drawCircle(c, k, groove);
    }
    // Two quiet bands between the tracks, and the rim.
    for (final k in [0.55, 0.78]) {
      canvas.drawCircle(
        c,
        r * k,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.012
          ..color = const Color(0xFF070708),
      );
    }
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = SweepGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.07),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.12, 0.25, 0.5, 0.62, 0.75],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  bool shouldRepaint(_GroovesPainter old) => false;
}

/// A tone arm: its pivot at the top, the tube down and in, the head at its tip.
class _ArmPainter extends CustomPainter {
  const _ArmPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final pivot = Offset(w * 0.65, h * 0.08);
    final elbow = Offset(w * 0.62, h * 0.72);
    final tip = Offset(w * 0.2, h * 0.93);
    final tube = Paint()
      ..color = const Color(0xFFC9CCD2)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.06;
    canvas.drawPath(
      Path()
        ..moveTo(pivot.dx, pivot.dy)
        ..lineTo(elbow.dx, elbow.dy)
        ..lineTo(tip.dx, tip.dy),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = w * 0.07
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      Path()
        ..moveTo(pivot.dx, pivot.dy)
        ..lineTo(elbow.dx, elbow.dy)
        ..lineTo(tip.dx, tip.dy),
      tube,
    );
    // The head, and the base it turns on.
    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    canvas.rotate((tip - elbow).direction);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: w * 0.28, height: w * 0.14),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFF2B2D31),
    );
    canvas.restore();
    canvas.drawCircle(pivot, w * 0.16, Paint()..color = const Color(0xFF2B2D31));
    canvas.drawCircle(pivot, w * 0.08, Paint()..color = const Color(0xFFC9CCD2));
  }

  @override
  bool shouldRepaint(_ArmPainter old) => false;
}

// Visualizer --------------------------------------------------------------------------------------------------------

/// The music's spectrum across the space, mirrored up and down from the middle, in the cover's colour; the song
/// in the middle of it.
class _VisualizerMode extends StatelessWidget {
  const _VisualizerMode({required this.track, required this.accent});

  final Track track;
  final Color accent;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: AudioReactiveView(
          own: true,
          builder: (context, levels) => RepaintBoundary(
            child: CustomPaint(painter: _SpectrumPainter(levels, Color.lerp(accent, Colors.white, 0.35)!)),
          ),
        ),
      ),
      Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: _SongLine(track: track, center: true),
        ),
      ),
    ],
  );
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter(this.levels, this.colour) : super(repaint: levels);

  final VisualizerLevels levels;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final bands = levels.value;
    if (bands.isEmpty) return;
    final n = bands.length, gap = 4.0;
    final w = (size.width - 64 - gap * (n - 1)) / n;
    final mid = size.height * 0.45, reach = size.height * 0.4;
    for (var i = 0; i < n; i++) {
      final v = bands[i].clamp(0.0, 1.0);
      final h = math.max(3.0, v * reach);
      final x = 32 + i * (w + gap);
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colour.withValues(alpha: 0.95), colour.withValues(alpha: 0.25)],
        ).createShader(Rect.fromLTWH(x, mid - h, w, h));
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, mid - h, w, h), Radius.circular(math.min(w / 2, 6))),
        paint,
      );
      // Its reflection, fainter, under the middle.
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, mid + gap, w, h * 0.45), Radius.circular(math.min(w / 2, 6))),
        Paint()..color = colour.withValues(alpha: 0.12),
      );
    }
  }

  @override
  bool shouldRepaint(_SpectrumPainter old) => old.colour != colour || old.levels != levels;
}

// Ambient clock -----------------------------------------------------------------------------------------------------

/// A desk clock: the time big, the date over it, the song small at the foot.
class _AmbientMode extends StatelessWidget {
  const _AmbientMode({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Center(
        child: LayoutBuilder(
          builder: (context, box) => DeskClock(size: math.min(box.maxHeight * 0.42, box.maxWidth * 0.22)),
        ),
      ),
      Positioned(left: 32, right: 32, bottom: 24, child: _SongLine(track: track, size: 48)),
    ],
  );
}

/// The time in big round figures, the date over it; woken on the minute, not every second. [size] is the figures'
/// height; they never run wider than the space. The desktop's clock mode, and the phone player's Clock cover.
class DeskClock extends StatefulWidget {
  const DeskClock({super.key, required this.size});

  final double size;

  @override
  State<DeskClock> createState() => _DeskClockState();
}

class _DeskClockState extends State<DeskClock> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    _tick = Timer(Duration(seconds: 60 - DateTime.now().second), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = MaterialLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final h24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final hours = (h24 ? now.hour : (now.hour % 12 == 0 ? 12 : now.hour % 12)).toString().padLeft(2, '0');
    final minutes = now.minute.toString().padLeft(2, '0');
    final size = widget.size;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.formatFullDate(now).toUpperCase(),
            style: text.titleMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 4,
              fontSize: math.max(12, size * 0.09),
            ),
          ),
          SizedBox(height: size * 0.04),
          Text(
            '$hours:$minutes',
            style: TextStyle(
              fontFamily: 'Figtree',
              fontSize: size,
              fontWeight: FontWeight.w700,
              height: 1,
              letterSpacing: -size * 0.03,
              color: AppColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// Hi-Fi -------------------------------------------------------------------------------------------------------------

/// What the sound is and what is done to it: its quality, the live spectrum, the equalizer's curve, and the way to
/// the signal path, the detail stats and the audio lab.
class _HifiMode extends StatelessWidget {
  const _HifiMode({required this.track, required this.accent});

  final Track track;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final audio = PlayerScope.of(context).audio;
    Widget card(String title, IconData icon, Widget child) => Material(
      color: AppColors.textPrimary.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.textSecondary),
                const SizedBox(width: 10),
                Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(child: child),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _SongLine(track: track)),
              const QualityBadge(),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: card(
                    tr.visualizer,
                    Icons.graphic_eq_rounded,
                    AudioReactiveView(
                      own: true,
                      builder: (context, levels) => RepaintBoundary(
                        child: CustomPaint(painter: _SpectrumPainter(levels, Color.lerp(accent, Colors.white, 0.35)!)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: card(
                    tr.equalizer,
                    Icons.equalizer_rounded,
                    ListenableBuilder(
                      listenable: audio,
                      builder: (context, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: CustomPaint(
                              painter: _EqCurvePainter(
                                AudioLab.response(audio.bands),
                                on: audio.eqEnabled,
                                colour: Color.lerp(accent, Colors.white, 0.35)!,
                                grid: AppColors.border,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            audio.eqEnabled ? (audio.eqProfile ?? audio.eqPreset) : tr.off,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => showSignalPath(context),
                icon: const Icon(Icons.route_rounded),
                label: Text(tr.signalPath),
              ),
              FilledButton.tonalIcon(
                onPressed: () => showDetailStats(context),
                icon: const Icon(Icons.analytics_outlined),
                label: Text(tr.detailStats),
              ),
              FilledButton.tonalIcon(
                onPressed: () => openAudioLab(context),
                icon: const Icon(Icons.science_outlined),
                label: Text(tr.audioLab),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// The equalizer's curve, 20 Hz to 20 kHz, ±12 dB.
class _EqCurvePainter extends CustomPainter {
  _EqCurvePainter(this.db, {required this.on, required this.colour, required this.grid});

  final List<double> db;
  final bool on;
  final Color colour, grid;

  @override
  void paint(Canvas canvas, Size size) {
    double y(double v) => size.height / 2 - v.clamp(-12, 12) / 12 * size.height / 2;
    final line = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), line);
    final freqs = AutoEq.fitFrequencies;
    final path = Path();
    for (var i = 0; i < db.length; i++) {
      final p = Offset(size.width * math.log(freqs[i] / 20) / math.log(1000), y(db[i]));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = colour.withValues(alpha: on ? 1 : 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_EqCurvePainter old) => old.db != db || old.on != on || old.colour != colour;
}

// Queue -------------------------------------------------------------------------------------------------------------

/// What plays next, as a wall of covers: a click plays it.
class _QueueMode extends StatelessWidget {
  const _QueueMode();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Rebuilt when what is next changes, not on every tick of the player.
    return PlayerSelect<String>(
      select: (c) => c.upNext.take(60).map((t) => t.id).join('\n'),
      builder: (context, _, _) {
        final upNext = PlayerScope.read(context).upNext.take(60).toList();
        if (upNext.isEmpty) {
          return Center(
            child: Text(tr.queueEmpty, style: text.titleMedium, textAlign: TextAlign.center),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(32, 8, 32, 16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200,
            mainAxisSpacing: 18,
            crossAxisSpacing: 18,
            childAspectRatio: 0.78,
          ),
          itemCount: upNext.length,
          itemBuilder: (context, i) {
            final t = upNext[i];
            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => PlayerScope.read(context).playQueueItem(t),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: LayoutBuilder(
                      builder: (context, box) => Artwork(track: t, size: box.maxWidth, radius: 14),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                  Text(
                    t.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
