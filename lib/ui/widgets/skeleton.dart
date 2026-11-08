import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/layout_prefs.dart';
import '../../services/ui_beat.dart';
import '../theme.dart';

/// The one shimmer clock for every skeleton on screen. It is a phase (0 to 1) that moves about ten times a second on
/// the shared [UiBeat], and only while at least one visible skeleton is mounted: no ticker, no animation controller,
/// and nothing at all once the content has arrived. Lightweight and reduced motion never start it: the boxes stay a
/// still grey.
class SkeletonClock {
  SkeletonClock._();

  /// 0 to 1, round and round.
  static final phase = ValueNotifier<double>(0);

  static int _users = 0;
  static UiBeatListener? _beat;

  /// Skeletons that are asking for the clock right now (tests).
  @visibleForTesting
  static int get users => _users;

  /// Whether the skeletons shimmer at all.
  static bool get shimmers => LayoutPrefs.moves;

  static void attach() {
    if (++_users != 1) return;
    _beat = UiBeat.listen(const Duration(milliseconds: 100), (elapsed) {
      // A full sweep in about 1.6 seconds, however many beats were missed.
      phase.value = (phase.value + elapsed.inMicroseconds / 1600000) % 1;
    });
  }

  static void detach() {
    if (_users == 0 || --_users != 0) return;
    _beat?.cancel();
    _beat = null;
  }
}

/// A grey rounded box standing where content will be. Its corners follow Settings › Pages & navigation › Corners.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 6, this.circle = false});

  /// A round one (an avatar, a spinner's place).
  const SkeletonBox.circle({super.key, required double size}) : width = size, height = size, radius = 0, circle = true;

  /// Null fills the room it is given.
  final double? width;
  final double height;

  /// The corner radius at the default Corners setting.
  final double radius;
  final bool circle;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> {
  bool _attached = false;

  /// Shimmers while it is on screen: not under another page, and only when motion is on.
  void _sync(bool want) {
    if (want == _attached) return;
    _attached = want;
    want ? SkeletonClock.attach() : SkeletonClock.detach();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync(SkeletonClock.shimmers && TickerMode.valuesOf(context).enabled);
  }

  @override
  void dispose() {
    _sync(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context).textPrimary;
    final base = c.withValues(alpha: 0.08), glow = c.withValues(alpha: 0.15);
    BoxDecoration decoration(double t) => BoxDecoration(
      color: Color.lerp(base, glow, t),
      shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: widget.circle ? null : LayoutPrefs.corner(widget.radius),
    );
    final box = SizedBox(width: widget.width, height: widget.height);
    if (!_attached) return DecoratedBox(decoration: decoration(0), child: box);
    return ValueListenableBuilder<double>(
      valueListenable: SkeletonClock.phase,
      // A soft pulse between the two greys.
      builder: (context, phase, child) =>
          DecoratedBox(decoration: decoration((math.sin(phase * 2 * math.pi) + 1) / 2), child: child),
      child: box,
    );
  }
}

/// Bars of text: [lines] of them, the last one shorter, as a title or a paragraph would be.
class SkeletonText extends StatelessWidget {
  const SkeletonText({super.key, this.lines = 1, this.height = 12, this.width, this.spacing = 8});

  final int lines;
  final double height;

  /// The width of the first line; the others are a little different. Null fills the room.
  final double? width;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final room = width ?? (box.maxWidth.isFinite ? box.maxWidth : 200);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines; i++) ...[
            if (i > 0) SizedBox(height: spacing),
            SkeletonBox(
              width: room * (i == lines - 1 && lines > 1 ? 0.6 : (const [1.0, 0.86, 0.94][i % 3])),
              height: height,
            ),
          ],
        ],
      );
    },
  );
}

/// One song or one item of a list: a cover and two lines of text, as [SkeletonList] repeats it.
class SkeletonRow extends StatelessWidget {
  const SkeletonRow({super.key, this.size = 48, this.circle = false, this.seed = 0, this.trailing = true});

  /// The cover's side.
  final double size;

  /// An artist: a round cover.
  final bool circle;

  /// Varies the width of the text from row to row.
  final int seed;

  /// A small box at the end, where the ⋯ menu is.
  final bool trailing;

  @override
  Widget build(BuildContext context) {
    final w = const [0.55, 0.7, 0.45, 0.62][seed % 4];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          circle ? SkeletonBox.circle(size: size) : SkeletonBox(width: size, height: size, radius: 4),
          const SizedBox(width: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: box.maxWidth * w, height: 14),
                  const SizedBox(height: 8),
                  SkeletonBox(width: box.maxWidth * w * 0.6, height: 11),
                ],
              ),
            ),
          ),
          if (trailing) ...[const SizedBox(width: 12), const SkeletonBox(width: 20, height: 20, radius: 10)],
        ],
      ),
    );
  }
}

/// A list of [count] rows, for songs, results and playlists on their way. It does not scroll: put it in a page's
/// column or in a sliver adapter.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 8, this.rowSize = 48, this.circle = false, this.padding});

  final int count;
  final double rowSize;
  final bool circle;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    // One layer for the shimmer of all of them.
    child: RepaintBoundary(
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: Column(
          children: [for (var i = 0; i < count; i++) SkeletonRow(size: rowSize, circle: circle, seed: i)],
        ),
      ),
    ),
  );
}

/// A shelf of cards: a square and a caption under each, in a row that is cut off at the edge, like Home's.
class SkeletonCardShelf extends StatelessWidget {
  const SkeletonCardShelf({super.key, this.count = 6, this.cardSize = 140, this.circle = false, this.padding});

  final int count;
  final double cardSize;

  /// Artists: round pictures.
  final bool circle;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: SizedBox(
        height: cardSize + 56,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
          itemCount: count,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, i) => SizedBox(
            width: cardSize,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                circle ? SkeletonBox.circle(size: cardSize) : SkeletonBox(width: cardSize, height: cardSize, radius: 8),
                const SizedBox(height: 10),
                SkeletonBox(width: cardSize * const [0.8, 0.65, 0.9][i % 3], height: 13),
                const SizedBox(height: 6),
                SkeletonBox(width: cardSize * 0.5, height: 11),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// The top of an album, playlist or artist page on its way: a big cover, a title, a row of round buttons around a
/// wide one, then a list of songs.
class SkeletonPage extends StatelessWidget {
  const SkeletonPage({super.key, this.rows = 6});

  final int rows;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            const SizedBox(height: 8),
            const SkeletonBox(width: 200, height: 200, radius: 8),
            const SizedBox(height: 20),
            const SkeletonBox(width: 220, height: 24),
            const SizedBox(height: 10),
            const SkeletonBox(width: 140, height: 13),
            const SizedBox(height: 20),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SkeletonBox.circle(size: 48),
                SizedBox(width: 12),
                SkeletonBox(width: 150, height: 48, radius: 24),
                SizedBox(width: 12),
                SkeletonBox.circle(size: 48),
              ],
            ),
            const SizedBox(height: 20),
            for (var i = 0; i < rows; i++) SkeletonRow(seed: i),
          ],
        ),
      ),
    ),
  );
}

/// Home's shelves on their way: a title bar and a row of cards, [shelves] times.
class SkeletonShelves extends StatelessWidget {
  const SkeletonShelves({super.key, this.shelves = 3});

  final int shelves;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < shelves; i++) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: SkeletonBox(width: 120.0 + 40 * (i % 2), height: 22),
          ),
          SkeletonCardShelf(circle: i == 2),
        ],
      ],
    ),
  );
}
