import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../platform/features.dart';
import '../../services/language.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../../services/youtube_music_account.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/shelf.dart';
import '../widgets/streak_badge.dart';
import 'downloads_page.dart';
import 'youtube_music_page.dart';
import '../widgets/menus.dart';
import '../widgets/skeleton.dart';

/// One Home for everything: your files, your Riflay playlists and your
/// YouTube Music library side by side, then YouTube Music's own shelves.
/// Streamed songs carry a cloud mark; everything else plays offline.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static String _greeting() {
    final h = DateTime.now().hour;
    return h < 5
        ? tr.greetingNight
        : h < 12
        ? tr.greetingMorning
        : h < 18
        ? tr.greetingAfternoon
        : tr.greetingEvening;
  }

  /// Home's bodies built, for tests: a song starting or pausing must not add to it.
  @visibleForTesting
  static int debugBuilds = 0;

  /// The ids of what was played last, in order: a change here (and not each song change) redraws "Recently played".
  static String _recentKey(PlayerController c) => c.recentlyPlayed.map((t) => t.id).join('\u0000');

  @override
  Widget build(BuildContext context) {
    // The library, the YouTube Music account and Layout settings, not each change of what's playing
    // (a song starting, play / pause): what shows that is a small leaf below.
    final c = PlayerScope.identity(context);
    return ListenableBuilder(
      listenable: Listenable.merge([c.libraryRevision, c.ytMusic, LayoutPrefs.instance]),
      builder: (context, _) => _build(context, c, c.ytMusic.libraryNow),
    );
  }

  Widget _build(BuildContext context, PlayerController c, YoutubeMusicLibrary? online) {
    debugBuilds++;
    final shell = ShellScope.of(context);
    final text = Theme.of(context).textTheme;
    final pad = shell.compact ? 16.0 : 24.0;
    final account = c.ytMusic;

    final albums = c.albums;
    final artists = c.artists;
    final liked = online == null || online.liked.isEmpty ? null : likedCollection(online.liked);
    final playlists = c.playlists;
    final remotePlaylists = online?.playlists ?? const <RemotePlaylist>[];

    final quickPicks = <Widget>[
      if (c.library.isNotEmpty)
        QuickTile(
          title: tr.allSongs,
          leading: CoverMosaic(tracks: c.allSongs.tracks, radius: 0),
          onTap: () => shell.openCollection(c.allSongs),
          onPlay: () => c.playCollection(c.allSongs),
        ),
      if (liked != null)
        QuickTile(
          title: tr.likedMusic,
          leading: CoverMosaic(tracks: liked.tracks, radius: 0),
          onTap: () => shell.openCollection(liked),
          onPlay: () => c.playCollection(liked),
        ),
      for (final p in playlists.take(3))
        QuickTile(
          title: p.name,
          leading: CoverMosaic(tracks: p.tracks, radius: 0),
          onTap: () => shell.openCollection(c.playlistCollection(p)),
          onPlay: p.tracks.isEmpty ? null : () => c.playCollection(c.playlistCollection(p)),
        ),
      for (final p in remotePlaylists.take(3))
        QuickTile(
          title: p.title,
          leading: Artwork(track: playlistCover(p), radius: 0),
          onTap: () => openRemotePlaylist(context, p),
        ),
      for (final a in albums.take(3))
        QuickTile(
          title: a.title,
          leading: Artwork(track: a.cover),
          onTap: () => shell.openCollection(a),
          onPlay: () => c.playCollection(a),
        ),
    ].take(shell.compact ? 6 : 8).toList();

    // Home's sections, in the order and with the ones switched on in Settings › Look & feel › Pages & navigation.
    final sections = <HomeSection, List<Widget>>{
      HomeSection.quickPicks: [
        if (quickPicks.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: shell.compact ? 260 : 360,
                mainAxisExtent: LayoutPrefs.dense(shell.compact ? 56 : 64, shell.compact ? 48 : 52),
                mainAxisSpacing: LayoutPrefs.dense(8, 4),
                crossAxisSpacing: LayoutPrefs.dense(8, 4),
              ),
              itemCount: quickPicks.length,
              itemBuilder: (_, i) => quickPicks[i],
            ),
          ),
        if (!account.isSignedIn) const SliverToBoxAdapter(child: SignInBanner()),
      ],
      HomeSection.recentlyPlayed: [
        // What was played changes with each song, but the shelf only when the list does. Keyed: a section
        // appearing above it must not rebuild it from scratch (SteadyOrder would forget the order it shows).
        PlayerSelect<String>(
          key: const ValueKey(HomeSection.recentlyPlayed),
          select: _recentKey,
          builder: (context, _, _) => SteadyOrder(
            tracks: c.recentlyPlayed,
            builder: (context, recent) {
              if (recent.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
              return _shelf(tr.recentlyPlayed, recent.length, (i) {
                final t = recent[i];
                return MediaCard(
                  track: t,
                  title: t.title,
                  subtitle: t.artist,
                  online: !c.isOffline(t),
                  onTap: () => shell.playAndOpen(() => c.playList(recent, i, from: tr.recentlyPlayed)),
                  onPlay: () => c.playList(recent, i, from: tr.recentlyPlayed),
                );
              });
            },
          ),
        ),
      ],
      HomeSection.playlists: [
        if (playlists.isNotEmpty || remotePlaylists.isNotEmpty)
          _shelf(tr.yourPlaylists, playlists.length + remotePlaylists.length, (i) {
            if (i < playlists.length) {
              final p = playlists[i];
              return MediaCard(
                track: p.tracks.firstOrNull,
                title: p.name,
                subtitle: tr.playlistOnRiflay(p.tracks.length),
                onTap: () => shell.openCollection(c.playlistCollection(p)),
                onPlay: p.tracks.isEmpty ? null : () => c.playCollection(c.playlistCollection(p)),
              );
            }
            final p = remotePlaylists[i - playlists.length];
            return MediaCard(
              track: playlistCover(p),
              title: p.title,
              subtitle: p.count == 0 ? 'YouTube Music' : tr.playlistOnYoutubeMusic(p.count),
              online: true,
              onTap: () => openRemotePlaylist(context, p),
            );
          }),
      ],
      HomeSection.albums: [
        if (albums.isNotEmpty)
          _shelf(tr.yourAlbums, albums.length, (i) {
            final a = albums[i];
            return MediaCard(
              track: a.cover,
              title: a.title,
              subtitle: a.subtitle,
              onTap: () => shell.openCollection(a),
              onPlay: () => c.playCollection(a),
            );
          }),
      ],
      HomeSection.artists: [
        if (artists.isNotEmpty)
          _shelf(tr.artists, artists.length, (i) {
            final a = artists[i];
            return MediaCard(
              track: a.cover,
              title: a.title,
              subtitle: tr.artist,
              circle: true,
              onTap: () => shell.openCollection(a),
              onPlay: () => c.playCollection(a),
            );
          }),
      ],
      HomeSection.discover: [
        if (c.library.isEmpty) const SliverToBoxAdapter(child: _AddYourMusic()),
        const DiscoverShelves(),
      ],
      HomeSection.recentlyAdded: [
        if (c.library.isNotEmpty)
          _shelf(tr.recentlyAdded, math.min(20, c.recentlyAdded.length), (i) {
            final t = c.recentlyAdded[i];
            return MediaCard(
              track: t,
              title: t.title,
              subtitle: t.artist,
              onTap: () => shell.playAndOpen(() => c.playList(c.recentlyAdded, i, from: tr.recentlyAdded)),
              onPlay: () => c.playList(c.recentlyAdded, i, from: tr.recentlyAdded),
            );
          }, onShowAll: () => shell.openCollection(c.allSongs)),
      ],
    };

    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, 16),
          // The listening streak beside the greeting: the first thing seen, and a reason to come back tomorrow.
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _greeting(),
                  style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
                ),
              ),
              const StreakBadge(),
            ],
          ),
        ),
      ),
      for (final section in LayoutPrefs.instance.homeShown) ...sections[section]!,
      // The invitation to add songs stays even when YouTube Music's shelves are switched off.
      if (c.library.isEmpty && LayoutPrefs.instance.homeHidden.contains(HomeSection.discover))
        const SliverToBoxAdapter(child: _AddYourMusic()),
    ];
    final actions = <Widget>[
      PlayerSelect<bool>(
        select: (c) => c.scanning,
        builder: (context, scanning, _) => scanning
            ? const Padding(padding: EdgeInsets.all(12), child: SkeletonBox.circle(size: 18))
            : const SizedBox.shrink(),
      ),
      IconButton(
        tooltip: tr.refresh,
        onPressed: () {
          account.discover(refresh: true);
          if (account.isSignedIn) account.library(refresh: true);
        },
        icon: const Icon(Icons.refresh_rounded),
      ),
      if (shell.compact) ...[
        if (Features.downloads) const DownloadsButton(),
        if (Features.localLibrary) _AddMenu(shell: shell),
      ],
    ];

    // The header's colour follows the cover of what plays (or was played last). Only this leaf is redrawn when
    // that changes; the sections above are the same widgets as before and are not rebuilt.
    return PlayerSelect<Track?>(
      select: (c) => c.currentTrack ?? c.recentlyPlayed.firstOrNull,
      builder: (context, track, _) => AccentBuilder(
        track: track,
        builder: (context, accent) =>
            PageScaffold(gradientColor: accent, brand: true, actions: actions, slivers: slivers),
      ),
    );
  }

  Widget _shelf(String title, int count, Widget Function(int i) card, {VoidCallback? onShowAll}) => SliverToBoxAdapter(
    child: Shelf.builder(title: title, count: count, card: card, onShowAll: onShowAll),
  );
}

/// Keeps a most-recent-first shelf ("Recently played") from reshuffling under the pointer: playing a card moved it
/// to the front, so the next tap in the same place played another song. While the shelf stays in sight, songs
/// already on it keep their places and newly played ones go in front; the true order comes back when the page is
/// shown again after another one covered it.
class SteadyOrder extends StatefulWidget {
  const SteadyOrder({super.key, required this.tracks, required this.builder});

  /// Most recent first.
  final List<Track> tracks;
  final Widget Function(BuildContext context, List<Track> tracks) builder;

  /// [now]'s ids in the order to show, given the order [shown] last: new ones first (in [now]'s order), then the
  /// ones still there where they were.
  @visibleForTesting
  static List<String> order(List<String> shown, List<String> now) {
    final present = now.toSet();
    final before = shown.toSet();
    return [
      for (final id in now)
        if (!before.contains(id)) id,
      for (final id in shown)
        if (present.contains(id)) id,
    ];
  }

  @override
  State<SteadyOrder> createState() => _SteadyOrderState();
}

class _SteadyOrderState extends State<SteadyOrder> {
  List<String>? _shown;
  bool _visible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A page over this one turns its tickers off; coming back into sight, the shelf is in true order again.
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_visible) _shown = null;
    _visible = visible;
  }

  @override
  Widget build(BuildContext context) {
    final byId = {for (final t in widget.tracks) t.id: t};
    final ids = byId.keys.toList();
    final shown = _shown = _shown == null ? ids : SteadyOrder.order(_shown!, ids);
    return widget.builder(context, [for (final id in shown) byId[id]!]);
  }
}

/// Shown on Home while there are no files yet: a small invitation, not a wall.
class _AddYourMusic extends StatelessWidget {
  const _AddYourMusic();

  @override
  Widget build(BuildContext context) {
    if (!Features.localLibrary) return const SizedBox.shrink();
    final shell = ShellScope.of(context);
    final text = Theme.of(context).textTheme;
    final pad = shell.compact ? 16.0 : 24.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 16, pad, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.elevated, borderRadius: LayoutPrefs.corner(8)),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(tr.addMusicOffline, style: text.bodyMedium?.copyWith(color: AppColors.textSecondary)),
            OutlinedButton.icon(
              onPressed: shell.addFiles,
              icon: const Icon(Icons.audio_file_outlined),
              label: Text(tr.addSongs),
            ),
            if (shell.addFolder != null)
              OutlinedButton.icon(
                onPressed: shell.addFolder,
                icon: const Icon(Icons.folder_open_rounded),
                label: Text(tr.addFolder),
              ),
          ],
        ),
      ),
    );
  }
}

/// Compact "jump back in" tile: artwork on the left, bold title, play button on hover.
class QuickTile extends StatefulWidget {
  const QuickTile({super.key, required this.title, required this.leading, required this.onTap, this.onPlay});

  final String title;
  final Widget leading;
  final VoidCallback onTap;
  final VoidCallback? onPlay;

  @override
  State<QuickTile> createState() => _QuickTileState();
}

class _QuickTileState extends State<QuickTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: _hover ? AppColors.textPrimary.withValues(alpha: 0.16) : AppColors.tile,
        borderRadius: LayoutPrefs.corner(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          hoverColor: Colors.transparent,
          child: Row(
            children: [
              AspectRatio(aspectRatio: 1, child: widget.leading),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (widget.onPlay != null)
                AnimatedOpacity(
                  opacity: _hover ? 1 : 0,
                  duration: LayoutPrefs.dur(const Duration(milliseconds: 150)),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PlayButton(
                      playing: false,
                      size: 36,
                      color: AppColors.accent,
                      iconColor: AppColors.onAccent,
                      onPressed: widget.onPlay,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddMenu extends StatelessWidget {
  const _AddMenu({required this.shell});

  final ShellScope shell;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<VoidCallback>(
      // Over the whole window, so a click anywhere (sidebar included) closes it.
      useRootNavigator: true,
      tooltip: tr.addMusic,
      icon: const Icon(Icons.add_rounded),
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: shell.addFiles,
          child: MenuRow(leading: Icon(Icons.audio_file_outlined), title: Text(tr.addSongs)),
        ),
        PopupMenuItem(
          value: shell.importFromYoutube,
          child: MenuRow(leading: Icon(Icons.add_link_rounded), title: Text(tr.importFromYouTube)),
        ),
      ],
    );
  }
}

class EmptyLibrary extends StatelessWidget {
  const EmptyLibrary({super.key, this.greeting});

  final String? greeting;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final text = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.library_music_outlined, size: 56, color: AppColors.textSecondary),
              const SizedBox(height: 24),
              if (greeting != null) Text(greeting!, style: text.titleMedium?.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              Text(
                tr.noMusicYet,
                textAlign: TextAlign.center,
                style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.8),
              ),
              const SizedBox(height: 12),
              Text(
                tr.noMusicYetBody,
                textAlign: TextAlign.center,
                style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 28),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.inverse,
                      foregroundColor: AppColors.onInverse,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      textStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    onPressed: shell.addFiles,
                    icon: const Icon(Icons.audio_file_rounded),
                    label: Text(tr.addSongs),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: BorderSide(color: AppColors.textMuted),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      textStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    onPressed: shell.importFromYoutube,
                    icon: const Icon(Icons.add_link_rounded),
                    label: Text(tr.fromYouTube),
                  ),
                  if (shell.addFolder != null)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: BorderSide(color: AppColors.textMuted),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        textStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      onPressed: shell.addFolder,
                      icon: const Icon(Icons.folder_open_rounded),
                      label: Text(tr.addFolder),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
