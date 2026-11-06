import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/track.dart';
import '../../platform/browser_files.dart';
import '../../platform/host.dart';
import '../../services/language.dart';
import '../../services/listening_stats.dart';
import '../../services/listening_streak.dart';
import '../../services/play_history.dart';
import '../../services/player_controller.dart';
import '../../services/wrap.dart';
import '../theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/controls.dart';
import '../widgets/faded_cover.dart';
import '../widgets/streak_badge.dart';

/// Riflay Wrap: a month as a story. Swipe, tap or use the arrow keys to move on.
class WrapPage extends StatelessWidget {
  const WrapPage({super.key, required this.month, this.history, this.data, this.now});

  final WrapMonth month;

  /// Set for the running month: its Wrap "so far", up to this moment.
  final DateTime? now;

  /// The app's history by default.
  final PlayHistory? history;

  /// Ready-made numbers (tests).
  final WrapData? data;

  @override
  Widget build(BuildContext context) {
    final d = data ?? MonthlyWrap.compute(history ?? PlayHistory.instance, month, now: now);
    final c = PlayerScope.read(context);
    final library = {for (final t in c.library) t.id: t};
    if (d == null) {
      return Material(
        color: AppColors.panel,
        child: Center(
          child: Text(
            now != null && MonthlyWrap.isRunning(month, now!)
                ? 'Play a few songs to see your Wrap.'
                : 'There is not enough listening in ${month.label} for a Wrap.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return WrapStory(data: d, trackFor: (s) => library[s.key] ?? s.toTrack());
  }
}

/// The story itself, for numbers already worked out.
class WrapStory extends StatefulWidget {
  const WrapStory({super.key, required this.data, required this.trackFor});

  final WrapData data;
  final Track Function(SongInfo) trackFor;

  @override
  State<WrapStory> createState() => _WrapStoryState();
}

class _WrapStoryState extends State<WrapStory> {
  final _pages = PageController();
  final _focus = FocusNode();
  late final List<GlobalKey> _keys;
  late final List<Widget Function(BuildContext, Color)> _cards;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _cards = _buildCards(widget.data, widget.trackFor);
    _keys = [for (final _ in _cards) GlobalKey()];
  }

  @override
  void dispose() {
    _pages.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _go(int to) {
    if (to < 0 || to >= _cards.length) return;
    _pages.animateToPage(to, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  /// "March 2026"; "November 2026 so far 2026-11-03" for the running month, so a later save does not overwrite it.
  static String _fileTitle(WrapData d) {
    final until = d.until;
    if (until == null) return d.month.label;
    final day = '${until.year}-${until.month.toString().padLeft(2, '0')}-${until.day.toString().padLeft(2, '0')}';
    return '${d.month.label} so far $day';
  }

  /// The card on screen as a PNG, at three times its size.
  Future<Uint8List> _render() async {
    final boundary = _keys[_index].currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('card not on screen');
    final image = await boundary.toImage(pixelRatio: 3);
    final ByteData? data;
    try {
      data = await image.toByteData(format: ui.ImageByteFormat.png);
    } finally {
      image.dispose();
    }
    final bytes = data?.buffer.asUint8List();
    if (bytes == null) throw StateError('no image');
    return bytes;
  }

  String get _fileName => 'Riflay Wrap ${_fileTitle(widget.data)} ${_index + 1}.png';

  /// What goes with a shared card: the month, the top song and artist.
  String get _caption {
    final d = widget.data;
    return 'My ${d.month.label} on Riflay: ${formatListened(d.listened)} of music. '
        'Top song: ${d.topSong.title}. Top artist: ${d.topArtist.title}.'
        '${d.bestStreak >= 2 ? ' 🔥 ${d.bestStreak} days in a row.' : ''}';
  }

  /// Saves the card to Downloads (the app's documents where there is none; the browser's downloads on the web);
  /// the saved file's name, or null if it failed.
  Future<String?> _save({bool quiet = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await _render();
      if (BrowserFiles.available) {
        BrowserFiles.save(bytes, _fileName, mime: 'image/png');
        if (!quiet) messenger.showSnackBar(SnackBar(content: Text('Saved $_fileName')));
        return _fileName;
      }
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, _fileName));
      await file.writeAsBytes(bytes, flush: true);
      if (!quiet) messenger.showSnackBar(SnackBar(content: Text('Saved ${p.basename(file.path)}')));
      return p.basename(file.path);
    } catch (e) {
      debugPrint('Saving a Wrap card failed: $e');
      messenger.showSnackBar(const SnackBar(content: Text('Couldn\'t save the image')));
      return null;
    }
  }

  /// The phone's share sheet with the card and a caption. A computer has none: the card is saved and the caption
  /// copied, to paste beside it.
  Future<void> _share() async {
    final messenger = ScaffoldMessenger.of(context);
    if (Host.isAndroid) {
      try {
        final bytes = await _render();
        // The cache's shared/ folder: the one the share sheet may lend out (res/xml/update_file_paths.xml).
        final dir = Directory(p.join((await getTemporaryDirectory()).path, 'shared'))..createSync(recursive: true);
        final file = File(p.join(dir.path, _fileName));
        await file.writeAsBytes(bytes, flush: true);
        final shown = await const MethodChannel('riflay/share').invokeMethod<bool>('share', {
          'text': _caption,
          'subject': 'Riflay Wrap',
          'file': file.path,
          'mime': 'image/png',
        });
        if (shown ?? false) return;
      } catch (e) {
        debugPrint('Sharing a Wrap card failed: $e');
      }
    }
    final name = await _save(quiet: true);
    if (name == null) return;
    await Clipboard.setData(ClipboardData(text: _caption));
    messenger.showSnackBar(SnackBar(content: Text('Saved $name; the caption is copied')));
  }

  @override
  Widget build(BuildContext context) {
    final top = widget.trackFor(widget.data.topSong.sample);
    return AccentBuilder(
      track: top,
      builder: (context, accent) {
        return Material(
          color: AppColors.panel,
          child: Focus(
            focusNode: _focus,
            autofocus: true,
            onKeyEvent: (_, e) {
              if (e is! KeyDownEvent) return KeyEventResult.ignored;
              if (e.logicalKey == LogicalKeyboardKey.arrowRight || e.logicalKey == LogicalKeyboardKey.space) {
                _go(_index + 1);
              } else if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
                _go(_index - 1);
              } else if (e.logicalKey == LogicalKeyboardKey.escape) {
                Navigator.of(context).maybePop();
              } else {
                return KeyEventResult.ignored;
              }
              return KeyEventResult.handled;
            },
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              for (var i = 0; i < _cards.length; i++)
                                Expanded(
                                  child: Container(
                                    height: 3,
                                    margin: const EdgeInsets.symmetric(horizontal: 2),
                                    decoration: BoxDecoration(
                                      color: i <= _index ? AppColors.textPrimary : AppColors.tile,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final wide = box.maxWidth > 600;
                        return Row(
                          children: [
                            if (wide)
                              IconButton(
                                tooltip: 'Previous',
                                onPressed: _index == 0 ? null : () => _go(_index - 1),
                                icon: const Icon(Icons.chevron_left_rounded),
                              ),
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapUp: (d) => _go(d.localPosition.dx < box.maxWidth / 3 ? _index - 1 : _index + 1),
                                child: PageView.builder(
                                  controller: _pages,
                                  itemCount: _cards.length,
                                  onPageChanged: (i) => setState(() => _index = i),
                                  itemBuilder: (context, i) {
                                    // Each card its own shade of the cover's colour, so the story moves.
                                    final own = _shade(accent, i);
                                    final base = AppColors.sink(own, 0.55);
                                    return Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Center(
                                        child: AspectRatio(
                                          aspectRatio: 9 / 16,
                                          child: RepaintBoundary(
                                            key: _keys[i],
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(16),
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  CustomPaint(
                                                    painter: _Backdrop(base: base, glow: own, seed: i),
                                                  ),
                                                  // The top song's cover, soft and dim behind every card: the month's
                                                  // own picture, not a decoration.
                                                  Opacity(
                                                    opacity: 0.22,
                                                    child: FadedCover(track: top, sharp: false, darken: 0.55),
                                                  ),
                                                  // Darker at the foot, so the footer reads on any cover.
                                                  DecoratedBox(
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        begin: Alignment.topCenter,
                                                        end: Alignment.bottomCenter,
                                                        colors: [
                                                          Colors.transparent,
                                                          Colors.black.withValues(alpha: 0.35),
                                                        ],
                                                        stops: const [0.6, 1],
                                                      ),
                                                    ),
                                                  ),
                                                  FittedBox(
                                                    fit: BoxFit.contain,
                                                    child: SizedBox(
                                                      width: 360,
                                                      height: 640,
                                                      child: Padding(
                                                        padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                                                        child: _WrapTint(
                                                          tint: Color.lerp(own, Colors.white, 0.45)!,
                                                          child: Column(
                                                            children: [
                                                              _Brand(month: widget.data.month.label),
                                                              Expanded(
                                                                child: Padding(
                                                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                                                  child: _cards[i](context, base),
                                                                ),
                                                              ),
                                                              _Footer(index: i, count: _cards.length),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            if (wide)
                              IconButton(
                                tooltip: 'Next',
                                onPressed: _index == _cards.length - 1 ? null : () => _go(_index + 1),
                                icon: const Icon(Icons.chevron_right_rounded),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: _share,
                          icon: const Icon(Icons.ios_share_rounded, size: 18),
                          label: Text(tr.share),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                          onPressed: _save,
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: const Text('Save image'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// How far each card turns the cover's hue, in degrees: neighbours differ, and the story comes back to it.
  static const _turns = [0.0, 28, -24, 46, -40, 16, -12, 58, -52, 34, -30, 8];

  /// The cover's colour for card [i], turned around the colour wheel and a touch more saturated.
  static Color _shade(Color accent, int i) {
    final hsl = HSLColor.fromColor(accent);
    return hsl
        .withHue((hsl.hue + _turns[i % _turns.length] + 360) % 360)
        .withSaturation((hsl.saturation * 1.15).clamp(0.35, 0.9))
        .toColor();
  }

  static const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  static String _day(DateTime d) => '${_weekdays[d.weekday - 1]}, ${ListeningStats.months[d.month - 1]} ${d.day}';

  static String _count(int n, String one, String many) => '$n ${n == 1 ? one : many}';

  /// The cards, in order. Each is drawn on a 360 x 640 canvas.
  static List<Widget Function(BuildContext, Color)> _buildCards(WrapData d, Track Function(SongInfo) trackFor) {
    return [
      (c, _) => _Card(
        kicker: d.inProgress ? 'Your Wrap so far' : 'Your monthly Wrap',
        headline: d.inProgress ? '${d.month.name} so far' : 'Your ${d.month.name} in music',
        body: d.inProgress ? 'Up to ${_day(d.until!)}' : d.month.label,
        center: true,
      ),
      (c, _) => _Card(
        kicker: 'You listened for',
        headline: formatListened(d.listened),
        body: 'across ${_count(d.plays, 'play', 'plays')} ${d.inProgress ? 'so far in' : 'in'} ${d.month.name}.',
        center: true,
      ),
      (c, _) => _Card(
        kicker: 'You played',
        headline: _count(d.songs, 'song', 'songs'),
        body: 'by ${_count(d.artists, 'artist', 'artists')}.',
        center: true,
      ),
      (c, _) => _Card(
        kicker: 'Your top song',
        headline: d.topSong.title,
        body: '${d.topSong.subtitle}\n${_count(d.topSong.plays, 'play', 'plays')}',
        art: Artwork(track: trackFor(d.topSong.sample), size: 220, radius: 8),
        center: true,
      ),
      (c, _) => _Card(
        kicker: 'Your top songs',
        list: [
          for (final (i, s) in d.topSongs.indexed)
            _Line(
              rank: i + 1,
              art: Artwork(track: trackFor(s.sample), size: 44),
              title: s.title,
              subtitle: s.subtitle,
              trailing: _count(s.plays, 'play', 'plays'),
            ),
        ],
      ),
      (c, _) => _Card(
        kicker: 'Your top artist',
        headline: d.topArtist.title,
        body: _count(d.topArtist.plays, 'play', 'plays'),
        art: Artwork(track: trackFor(d.topArtist.sample), size: 200, circle: true),
        center: true,
      ),
      (c, _) => _Card(
        kicker: 'Your top artists',
        list: [
          for (final (i, a) in d.topArtists.indexed)
            _Line(
              rank: i + 1,
              art: Artwork(track: trackFor(a.sample), size: 44, circle: true),
              title: a.title,
              subtitle: formatListened(a.listened),
              trailing: _count(a.plays, 'play', 'plays'),
            ),
        ],
      ),
      if (d.topAlbum case final album?)
        (c, _) => _Card(
          kicker: 'Your top album',
          headline: album.title,
          body: '${album.subtitle}\n${_count(album.plays, 'play', 'plays')}',
          art: Artwork(track: trackFor(album.sample), size: 220, radius: 8),
          center: true,
        ),
      (c, _) => _Card(
        kicker: 'Your biggest day',
        headline: _day(d.busiestDay),
        body: '${formatListened(d.busiestDayListened)} of music.',
        center: true,
      ),
      // Worth showing off from two days in a row; the flame takes the colour the streak reached.
      if (d.bestStreak >= 2)
        (c, _) => _Card(
          kicker: d.streakNow >= 2 && d.streakNow == d.bestStreak ? 'Your streak, still going' : 'Your longest streak',
          headline: '${d.bestStreak} days in a row',
          body:
              'You listened on ${d.daysListened} of ${_count(d.days, 'day', 'days')}${d.inProgress ? ' so far' : ''}.',
          art: StreakFlame(tier: StreakTier.of(d.bestStreak), size: 150),
          center: true,
        ),
      if (d.mostReplayed case final song?)
        (c, _) => _Card(
          kicker: 'Most replayed',
          headline: song.title,
          body: '${song.artist}\nPlayed ${d.mostReplayedCount} times on ${_day(d.mostReplayedDay!)}.',
          art: Artwork(track: trackFor(song), size: 160, radius: 8),
          center: true,
        ),
      (c, _) => _Card(
        kicker: 'New this month',
        headline: _count(d.newSongs, 'new song', 'new songs'),
        body: d.newSongs == 0 ? 'You stayed with the songs you know.' : 'Songs you had never played before.',
        center: true,
      ),
      (c, _) => _Card(
        kicker: d.title,
        headline: formatListened(d.listened),
        body:
            'Top song: ${d.topSong.title}\nTop artist: ${d.topArtist.title}\n'
            '${_count(d.songs, 'song', 'songs')}, ${_count(d.artists, 'artist', 'artists')}'
            '${d.newSongs > 0 ? ', ${d.newSongs} new' : ''}',
        art: Artwork(track: trackFor(d.topSong.sample), size: 120, radius: 8),
        footer: d.bestStreak >= 2 ? _StreakPill(days: d.bestStreak) : null,
        center: true,
      ),
    ];
  }
}

/// The summary's streak: the flame in the colour the streak reached, on a pill lit the same way.
class _StreakPill extends StatelessWidget {
  const _StreakPill({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final tier = StreakTier.of(days);
    final color = tier.colors[tier.colors.length ~/ 2];
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 16, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 24)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreakFlame(tier: tier, size: 30),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '$days days in a row',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// A card's background: a diagonal wash of its colour, soft glows of light placed by [seed] (so each card's are
/// somewhere else), and thin rings in a corner. Plain gradients: nothing here blurs, and it draws once.
class _Backdrop extends CustomPainter {
  const _Backdrop({required this.base, required this.glow, required this.seed});

  final Color base;
  final Color glow;
  final int seed;

  /// Where the glows sit, as fractions of the card, one set per card in turn.
  static const _spots = [
    [Offset(0.15, 0.1), Offset(0.95, 0.55), Offset(0.3, 0.95)],
    [Offset(0.9, 0.12), Offset(0.05, 0.6), Offset(0.7, 0.9)],
    [Offset(0.5, 0.0), Offset(0.0, 0.85), Offset(1.0, 0.75)],
    [Offset(0.05, 0.35), Offset(0.85, 0.05), Offset(0.6, 1.0)],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hsl = HSLColor.fromColor(glow);
    final second = hsl.withHue((hsl.hue + 40) % 360).toColor();
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(base, glow, 0.35)!, base, Color.lerp(base, Colors.black, 0.35)!],
          stops: const [0, 0.55, 1],
        ).createShader(rect),
    );
    final spots = _spots[seed % _spots.length];
    final colors = [glow.withValues(alpha: 0.55), second.withValues(alpha: 0.4), Colors.white.withValues(alpha: 0.1)];
    final radii = [0.75, 0.6, 0.5];
    for (var k = 0; k < spots.length; k++) {
      final center = Offset(spots[k].dx * size.width, spots[k].dy * size.height);
      final r = size.width * radii[k];
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(colors: [colors[k], colors[k].withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }
    // Rings round the corner opposite the first glow.
    final corner = Offset(
      spots[0].dx < 0.5 ? size.width : 0,
      spots[0].dy < 0.5 ? size.height * 0.82 : size.height * 0.18,
    );
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.07);
    for (var k = 1; k <= 4; k++) {
      canvas.drawCircle(corner, size.width * 0.14 * k, ring);
    }
  }

  @override
  bool shouldRepaint(_Backdrop old) => old.base != base || old.glow != glow || old.seed != seed;
}

/// The cover's colour for the small lines of every card.
class _WrapTint extends InheritedWidget {
  const _WrapTint({required this.tint, required super.child});

  final Color tint;

  static Color of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_WrapTint>()?.tint ?? AppColors.textSecondary;

  @override
  bool updateShouldNotify(_WrapTint old) => old.tint != tint;
}

/// The top of every card: whose Wrap this is, so a saved or shared card says Riflay on it.
class _Brand extends StatelessWidget {
  const _Brand({required this.month});

  final String month;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        const AppLogo(size: 22),
        const SizedBox(width: 8),
        Text('Riflay', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        const SizedBox(width: 6),
        Text(
          'Wrap',
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: _WrapTint.of(context)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            month.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: text.labelSmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

/// The foot of every card: where it comes from and which card it is.
class _Footer extends StatelessWidget {
  const _Footer({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600, letterSpacing: 0.8);
    final tint = _WrapTint.of(context);
    return Row(
      children: [
        Expanded(
          child: Text('Made with Riflay', maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
        ),
        // Where this card is in the story: a long mark for this one (the marks say it, no "3 / 12" beside them).
        for (var i = 0; i < count; i++)
          Container(
            width: i == index ? 12 : 4,
            height: 4,
            margin: const EdgeInsets.only(left: 3),
            decoration: BoxDecoration(
              color: i == index ? tint : Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}

class _Line {
  const _Line({
    required this.rank,
    required this.art,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });
  final int rank;
  final Widget art;
  final String title;
  final String subtitle;
  final String trailing;
}

/// One card's layout: a small line above, a big statement, and the detail under it.
class _Card extends StatelessWidget {
  const _Card({this.kicker, this.headline, this.body, this.art, this.list, this.footer, this.center = false});

  final String? kicker;
  final String? headline;
  final String? body;
  final Widget? art;
  final List<_Line>? list;

  /// Under the words: the summary's streak.
  final Widget? footer;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tint = _WrapTint.of(context);
    final align = center ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = center ? TextAlign.center : TextAlign.start;
    final picture = art;
    final round = picture is Artwork && picture.circle;
    return Column(
      crossAxisAlignment: align,
      // A short list sits in the middle too, not under the brand with the card empty below it.
      mainAxisAlignment: center || list != null ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        if (kicker != null)
          Text(
            kicker!,
            textAlign: textAlign,
            style: text.titleMedium?.copyWith(color: tint, fontWeight: FontWeight.w700, letterSpacing: 0.2),
          ),
        if (picture != null) ...[
          const SizedBox(height: 28),
          if (round)
            // A ring of the card's colours round the artist.
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(colors: [tint, Colors.white, tint.withValues(alpha: 0.4), tint]),
                boxShadow: [BoxShadow(color: tint.withValues(alpha: 0.45), blurRadius: 36)],
              ),
              child: picture,
            )
          else if (picture is Artwork)
            // Tilted a little and lit from behind, like a sleeve on a table.
            Transform.rotate(
              angle: -0.04,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(color: tint.withValues(alpha: 0.4), blurRadius: 40, spreadRadius: 2),
                    BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 10)),
                  ],
                ),
                child: picture,
              ),
            )
          else
            // Not a cover (the streak's flame): it lights itself.
            picture,
        ],
        if (headline != null) ...[
          const SizedBox(height: 22),
          // White into the card's colour across the words.
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (r) => LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color.lerp(Colors.white, tint, 0.7)!],
            ).createShader(r),
            child: Text(
              headline!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: textAlign,
              style: text.displaySmall?.copyWith(fontWeight: FontWeight.w900, height: 1.02, letterSpacing: -1.2),
            ),
          ),
        ],
        if (body != null) ...[
          const SizedBox(height: 14),
          Text(
            body!,
            textAlign: textAlign,
            style: text.titleMedium?.copyWith(color: AppColors.textPrimary.withValues(alpha: 0.78), height: 1.4),
          ),
        ],
        if (footer != null) ...[const SizedBox(height: 18), footer!],
        if (list != null) ...[
          const SizedBox(height: 18),
          for (final l in list!)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
              decoration: BoxDecoration(
                // Glass tiles; the first one lit in the card's colour.
                color: l.rank == 1 ? tint.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: l.rank == 1 ? tint.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Text(
                      '${l.rank}',
                      style: (l.rank == 1 ? text.headlineSmall : text.titleLarge)?.copyWith(
                        color: l.rank == 1 ? tint : AppColors.textSecondary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  l.art,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          l.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l.trailing,
                    style: text.bodySmall?.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
