import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/language.dart';
import '../../services/layout_prefs.dart';
import '../../services/lyrics.dart';
import '../../services/visualizer_levels.dart';
import '../player/desktop_player_bar.dart';
import '../player/now_playing_page.dart';
import '../player/player_parts.dart';
import '../player_scope.dart';
import '../shell/phone_navigation.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/controls.dart';
import '../widgets/live_preview.dart';
import '../widgets/shelf.dart';
import '../widgets/track_row.dart';
import 'lyrics_page.dart';
import 'settings_index.dart';

/// A song for the parts that need one while nothing plays: its cover is the placeholder (no file, no address).
Track _sampleSong() => Track(
  id: 'preview:song',
  uri: Uri(scheme: 'preview', path: 'song'),
  title: tr.previewYourSong,
  artist: tr.previewItsArtist,
);

/// The real widgets [kind] changes, small (see [LivePreview]).
class SettingPreviewView extends StatelessWidget {
  const SettingPreviewView({super.key, required this.kind});

  final SettingPreview kind;

  @override
  Widget build(BuildContext context) {
    final compact = ShellScope.of(context).compact;
    return switch (kind) {
      // A phone's Now Playing: the layout parts are about it, and a computer's player shows the same choices.
      .nowPlaying => const LivePreview(canvas: Size(390, 844), child: NowPlayingPage()),
      .lyrics => const LivePreview(canvas: Size(390, 600), child: _LyricsPreview()),
      .visualizer => const LivePreview(canvas: Size(320, 380), child: _VisualizerPreview()),
      .cards => LivePreview(canvas: Size(compact ? 390 : 760, double.infinity), child: const _CardsPreview()),
      .tabBar => const LivePreview(canvas: Size(390, 260), child: _TabBarPreview()),
      .desktopBar => const LivePreview(canvas: Size(1100, double.infinity), child: _DesktopBarPreview()),
    };
  }
}

/// The lyrics page as its settings draw it: its header or bottom card around a few lines, the second one sung.
class _LyricsPreview extends StatelessWidget {
  const _LyricsPreview();

  @override
  Widget build(BuildContext context) {
    final track = PlayerScope.read(context).currentTrack ?? _sampleSong();
    final layout = LayoutPrefs.instance.lyricsLayout;
    final lines = tr.previewLyrics.split('\n');
    // Four seconds a line, word by word, so the word-timed look and the fill show.
    final lyrics = Lyrics(
      source: '',
      lines: [
        for (final (i, line) in lines.indexed)
          LyricLine(
            Duration(seconds: i * 4),
            line,
            end: Duration(seconds: i * 4 + 4),
            words: [
              for (final (j, w) in line.split(' ').indexed)
                LyricWord(
                  Duration(milliseconds: i * 4000 + j * 600),
                  Duration(milliseconds: i * 4000 + j * 600 + 600),
                  '$w ',
                ),
            ],
          ),
      ],
    );
    final text = Theme.of(context).textTheme;
    return Material(
      color: AppColors.of(context).panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
            child: layout == LyricsLayout.topHeader
                ? LyricsTopHeader(track: track)
                : Text(tr.lyrics, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
          Expanded(
            child: SyncedLyricsView(
              lyrics: lyrics,
              ticks: const Stream.empty(),
              smoothTicks: const Stream.empty(),
              position: () => const Duration(milliseconds: 5300),
              onSeek: (_) {},
            ),
          ),
          if (layout == LyricsLayout.bottomCard)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: LyricsBottomCard(track: track),
            ),
        ],
      ),
    );
  }
}

/// The cover with the visualizer as the player draws it, on a still, made-up moment of a song.
class _VisualizerPreview extends StatefulWidget {
  const _VisualizerPreview();

  @override
  State<_VisualizerPreview> createState() => _VisualizerPreviewState();
}

class _VisualizerPreviewState extends State<_VisualizerPreview> {
  // A bass-heavy shape, falling towards the treble.
  final _levels = VisualizerLevels()
    ..value = Float64List.fromList([
      for (var i = 0; i < VisualizerLevels.samples; i++)
        0.25 + 0.6 * (1 - i / VisualizerLevels.samples) * (i.isEven ? 1 : 0.75),
    ])
    ..beat = 0.5
    ..backgroundEnergy = 0.5;

  @override
  void dispose() {
    _levels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = LayoutPrefs.instance;
    final track = PlayerScope.read(context).currentTrack;
    final accent = AppColors.of(context).accent;
    final art = Artwork(track: track, size: 220, radius: LayoutPrefs.radius(8));
    Widget canvas({Widget? child}) => VisualizerCanvas(
      levels: _levels,
      color: accent,
      style: p.visualizerStyle,
      coverShape: p.visualizerCoverShape,
      radius: LayoutPrefs.radius(8),
      radialMotion: p.visualizerRadius,
      thickness: p.visualizerThickness,
      child: child,
    );
    return ColoredBox(
      color: AppColors.of(context).background,
      child: Center(
        child: !p.visualizer
            ? art
            : p.visualizerStyle.radial
            ? SizedBox.square(
                dimension: 260,
                child: Center(child: canvas(child: art)),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  art,
                  const SizedBox(height: 16),
                  SizedBox(height: 80, width: 280, child: canvas()),
                ],
              ),
      ),
    );
  }
}

/// A shelf of covers and two song rows: corners, spacing and cover size.
class _CardsPreview extends StatelessWidget {
  const _CardsPreview();

  @override
  Widget build(BuildContext context) {
    final songs = PlayerScope.read(context).library.take(4).toList();
    return ColoredBox(
      color: AppColors.of(context).background,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Shelf(
            title: tr.recentlyAdded,
            onShowAll: () {},
            cards: [
              for (var i = 0; i < 4; i++)
                MediaCard(
                  track: i < songs.length ? songs[i] : null,
                  title: i < songs.length ? songs[i].title : tr.previewYourSong,
                  subtitle: i < songs.length ? songs[i].artist : tr.previewItsArtist,
                  onTap: () {},
                ),
            ],
          ),
          for (final (i, t) in (songs.isEmpty ? [_sampleSong(), _sampleSong()] : songs.take(2)).indexed)
            TrackRow(track: t, index: i + 1, onTap: () {}),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// The phone's tab bar and mini player at the foot of a page.
class _TabBarPreview extends StatefulWidget {
  const _TabBarPreview();

  @override
  State<_TabBarPreview> createState() => _TabBarPreviewState();
}

class _TabBarPreviewState extends State<_TabBarPreview> {
  final _link = GlassBarLink();

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ColoredBox(
      color: colors.background,
      child: Stack(
        children: [
          // Something behind the bar, for glass to show through.
          Positioned(
            left: 24,
            right: 24,
            top: 24,
            height: 120,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.5),
                borderRadius: LayoutPrefs.corner(12),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: PhoneBottomBar(onOpenPlayer: () {}, tab: PhoneTab.home, onSelect: (_) {}, link: _link),
          ),
        ],
      ),
    );
  }
}

/// A computer's player bar.
class _DesktopBarPreview extends StatelessWidget {
  const _DesktopBarPreview();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.of(context).background,
    child: DesktopPlayerBar(sidePanelOpen: false, onToggleSidePanel: () {}),
  );
}

/// The preview of [option] in its card: its name, a close button and the picture.
class SettingPreviewCard extends StatelessWidget {
  const SettingPreviewCard({super.key, required this.option, required this.onClose, this.height = 300});

  final SettingsOption option;
  final VoidCallback onClose;

  /// The picture's height at most.
  final double height;

  static const closeKey = ValueKey('settings-preview-close');

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return Material(
      color: colors.elevated,
      elevation: 6,
      shadowColor: Colors.black54,
      borderRadius: LayoutPrefs.corner(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
            child: Row(
              children: [
                Icon(Icons.visibility_outlined, size: 18, color: colors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${tr.settingsPreview} · ${option.title(tr)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  key: closeKey,
                  tooltip: tr.closePreview,
                  iconSize: 20,
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: ClipRRect(
                borderRadius: LayoutPrefs.corner(8),
                child: Center(heightFactor: 1, child: SettingPreviewView(kind: option.preview!)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
