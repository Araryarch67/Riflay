import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/track.dart';
import '../../services/listening_stats.dart';
import '../../services/play_history.dart';
import '../../services/player_controller.dart';
import '../../services/wrap.dart';
import '../theme.dart';
import '../widgets/controls.dart';

/// Riflay Wrap: a finished month as a story. Swipe, tap or use the arrow keys to move on.
class WrapPage extends StatelessWidget {
  const WrapPage({super.key, required this.month, this.history, this.data});

  final WrapMonth month;

  /// The app's history by default.
  final PlayHistory? history;

  /// Ready-made numbers (tests).
  final WrapData? data;

  @override
  Widget build(BuildContext context) {
    final d = data ?? MonthlyWrap.compute(history ?? PlayHistory.instance, month);
    final c = PlayerScope.read(context);
    final library = {for (final t in c.library) t.id: t};
    if (d == null) {
      return Material(
        color: AppColors.panel,
        child: Center(
          child: Text(
            'There is not enough listening in ${month.label} for a Wrap.',
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

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final boundary = _keys[_index].currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('card not on screen');
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))?.buffer.asUint8List();
      if (bytes == null) throw StateError('no image');
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'Riflay Wrap ${widget.data.month.label} ${_index + 1}.png'));
      await file.writeAsBytes(bytes, flush: true);
      messenger.showSnackBar(SnackBar(content: Text('Saved ${p.basename(file.path)}')));
    } catch (e) {
      debugPrint('Saving a Wrap card failed: $e');
      messenger.showSnackBar(const SnackBar(content: Text('Couldn\'t save the image')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = widget.trackFor(widget.data.topSong.sample);
    return AccentBuilder(
      track: top,
      builder: (context, accent) {
        // One flat colour from the top song's cover, pulled toward the app's background so text stays readable.
        final color = AppColors.sink(accent, 0.55);
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
                                  itemBuilder: (context, i) => Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Center(
                                      child: AspectRatio(
                                        aspectRatio: 9 / 16,
                                        child: RepaintBoundary(
                                          key: _keys[i],
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: color,
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                            child: FittedBox(
                                              fit: BoxFit.contain,
                                              child: SizedBox(
                                                width: 360,
                                                height: 640,
                                                child: Padding(
                                                  padding: const EdgeInsets.all(28),
                                                  child: _cards[i](context, color),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
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
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                      onPressed: _save,
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Save image'),
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

  static const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  static String _day(DateTime d) => '${_weekdays[d.weekday - 1]}, ${ListeningStats.months[d.month - 1]} ${d.day}';

  static String _count(int n, String one, String many) => '$n ${n == 1 ? one : many}';

  /// The cards, in order. Each is drawn on a 360 x 640 canvas.
  static List<Widget Function(BuildContext, Color)> _buildCards(WrapData d, Track Function(SongInfo) trackFor) {
    return [
      (c, _) =>
          _Card(kicker: 'Riflay Wrap', headline: 'Your ${d.month.name} in music', body: d.month.label, center: true),
      (c, _) => _Card(
        kicker: 'You listened for',
        headline: formatListened(d.listened),
        body: 'across ${_count(d.plays, 'play', 'plays')} in ${d.month.name}.',
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
        kicker: d.month.label,
        headline: formatListened(d.listened),
        body:
            'Top song: ${d.topSong.title}\nTop artist: ${d.topArtist.title}\n'
            '${_count(d.songs, 'song', 'songs')}, ${_count(d.artists, 'artist', 'artists')}'
            '${d.newSongs > 0 ? ', ${d.newSongs} new' : ''}',
        art: Artwork(track: trackFor(d.topSong.sample), size: 120, radius: 8),
        center: true,
      ),
    ];
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
  const _Card({this.kicker, this.headline, this.body, this.art, this.list, this.center = false});

  final String? kicker;
  final String? headline;
  final String? body;
  final Widget? art;
  final List<_Line>? list;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final align = center ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: align,
      mainAxisAlignment: center ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        if (kicker != null)
          Text(
            kicker!,
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: text.titleMedium?.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
          ),
        if (art != null) ...[const SizedBox(height: 24), art!],
        if (headline != null) ...[
          const SizedBox(height: 20),
          Text(
            headline!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: text.headlineLarge?.copyWith(fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1.1),
          ),
        ],
        if (body != null) ...[
          const SizedBox(height: 12),
          Text(
            body!,
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: text.titleMedium?.copyWith(color: AppColors.textSecondary, height: 1.35),
          ),
        ],
        if (list != null) ...[
          const SizedBox(height: 20),
          for (final l in list!)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text('${l.rank}', style: text.titleSmall?.copyWith(color: AppColors.textSecondary)),
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
                          style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
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
                  Text(l.trailing, style: text.bodySmall?.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
