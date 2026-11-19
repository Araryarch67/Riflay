import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../platform/features.dart';
import '../../services/daily_mix.dart';
import '../../services/language.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../../services/playlist_covers.dart';
import '../../services/youtube_music_account.dart';
import '../debug_switches.dart';
import '../playlist_cover_edit.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/controls.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/shelf.dart';
import '../widgets/streak_badge.dart';
import '../widgets/track_row.dart' show openArtist;
import 'downloads_page.dart';
import 'layout_settings.dart';
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
  static Object _recentKey(PlayerController c) => c.recentlyPlayedRevision;

  @override
  Widget build(BuildContext context) {
    // The library, the YouTube Music account and Layout settings, not each change of what's playing
    // (a song starting, play / pause): what shows that is a small leaf below.
    final c = PlayerScope.identity(context);
    return ListenableBuilder(
      listenable: Listenable.merge([c.libraryRevision, c.ytMusic, LayoutPrefs.instance, PlaylistCovers.instance]),
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
    final followedArtists = online?.artists ?? const <RemotePlaylist>[];
    final followedChannels = followedArtists.map((artist) => artist.id).toSet();
    final artists = followedChannels.isEmpty
        ? c.artists
        : c.artists.where((artist) => !followedChannels.contains(youtubeSongOf(artist)?.artistId)).toList();
    final liked = online == null || online.liked.isEmpty ? null : likedCollection(online.liked);
    final playlists = c.playlists;
    final remotePlaylists = online?.playlists ?? const <RemotePlaylist>[];

    final carousel =
        LayoutPrefs.instance.homeStyle == HomeStyle.carousel &&
        LayoutPrefs.instance.performance != PerformanceMode.lightweight;
    final quickPicks = <QuickTile>[
      if (c.library.isNotEmpty)
        QuickTile(
          title: tr.allSongs,
          leading: PlaylistArtwork(
            coverKey: c.allSongs.coverKey,
            fallback: CoverMosaic(tracks: c.allSongs.tracks, radius: 0),
          ),
          onTap: () => shell.openCollection(c.allSongs),
          onPlay: () => c.playCollection(c.allSongs),
        ),
      if (liked != null)
        QuickTile(
          title: tr.likedMusic,
          leading: PlaylistArtwork(
            coverKey: liked.coverKey,
            fallback: CoverMosaic(tracks: liked.tracks, radius: 0),
          ),
          onTap: () => shell.openCollection(liked),
          onPlay: () => c.playCollection(liked),
        ),
      for (final p in playlists.take(3))
        QuickTile(
          title: p.name,
          leading: PlaylistArtwork(
            coverKey: PlaylistCovers.playlistKey(p.id),
            fallback: CoverMosaic(tracks: p.tracks, radius: 0),
          ),
          onTap: () => shell.openCollection(c.playlistCollection(p)),
          onPlay: p.tracks.isEmpty ? null : () => c.playCollection(c.playlistCollection(p)),
        ),
      for (final p in remotePlaylists.take(3))
        QuickTile(
          title: p.title,
          leading: PlaylistArtwork(
            coverKey: PlaylistCovers.remoteKey(p.id),
            fallback: Artwork(track: playlistCover(p), radius: 0),
          ),
          onTap: () => openRemotePlaylist(context, p),
        ),
      for (final a in albums.take(3))
        QuickTile(
          title: a.title,
          leading: Artwork(track: a.cover, radius: 0),
          onTap: () => shell.openCollection(a),
          onPlay: () => c.playCollection(a),
        ),
    ].take(shell.compact ? 6 : 8).toList();

    // Home's sections, in the order and with the ones switched on in Settings › Look & feel › Pages & navigation.
    final sections = <HomeSection, List<Widget>>{
      HomeSection.quickPicks: [
        if (carousel)
          PlayerSelect<Object>(
            select: _recentKey,
            builder: (context, _, _) {
              final picks = {
                for (final track in [
                  ...c.recentlyPlayed.take(8),
                  ...c.recentlyAdded.take(8),
                  ...?account.discovered?.expand((shelf) => shelf.tracks).take(8),
                ])
                  track.id: track,
              }.values.take(8).toList();
              if (picks.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
              return SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionTitle(tr.quickPicks, compactSpacing: true),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: pad),
                      child: _QuickPicksCarousel(tracks: picks),
                    ),
                  ],
                ),
              );
            },
          ),
        if (carousel && quickPicks.isNotEmpty)
          _shelf(tr.speedDial, quickPicks.length, (i) {
            final pick = quickPicks[i];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Align(
                alignment: Alignment.topCenter,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: _HomeArtworkCard(artwork: pick.leading, title: pick.title, onTap: pick.onTap, compact: true),
                ),
              ),
            );
          }, artworkOnly: true),
        if (quickPicks.isNotEmpty && !carousel)
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
      HomeSection.dailyMix: [
        _DailyMixShelf(
          key: const ValueKey(HomeSection.dailyMix),
          player: c,
          available: c.library
              .followedBy(online?.liked ?? const [])
              .followedBy(account.discovered?.expand((shelf) => shelf.tracks) ?? const []),
        ),
      ],
      HomeSection.recentlyPlayed: [
        // What was played changes with each song, but the shelf only when the list does. Keyed: a section
        // appearing above it must not rebuild it from scratch (SteadyOrder would forget the order it shows).
        PlayerSelect<Object>(
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
                  mergedMark: true,
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
                track: PlaylistCovers.instance.coverOr(PlaylistCovers.playlistKey(p.id), p.tracks.firstOrNull),
                title: p.name,
                subtitle: tr.playlistOnRiflay(p.tracks.length),
                onTap: () => shell.openCollection(c.playlistCollection(p)),
                onPlay: p.tracks.isEmpty ? null : () => c.playCollection(c.playlistCollection(p)),
              );
            }
            final p = remotePlaylists[i - playlists.length];
            return MediaCard(
              track: PlaylistCovers.instance.coverOr(PlaylistCovers.remoteKey(p.id), playlistCover(p)),
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
        if (artists.isNotEmpty || followedArtists.isNotEmpty)
          _shelf(tr.artists, followedArtists.length + artists.length, (i) {
            if (i < followedArtists.length) {
              final artist = followedArtists[i];
              return MediaCard(
                track: playlistCover(artist),
                title: artist.title,
                subtitle: tr.artist,
                circle: true,
                online: true,
                onTap: () => openRemotePlaylist(context, artist),
              );
            }
            final a = artists[i - followedArtists.length];
            return MediaCard(
              track: a.cover,
              title: a.title,
              subtitle: tr.artist,
              circle: true,
              onTap: openHomeArtist(context, c, a, shell: shell),
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
      IconButton(
        tooltip: tr.customizeHome,
        icon: const Icon(Icons.tune_rounded),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (context) => AppDialog(
            title: tr.customizeHome,
            content: const HomeCustomization(),
            actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr.done))],
          ),
        ),
      ),
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
      if (shell.compact && Features.downloads) const DownloadsButton(),
      if (Features.localLibrary) _AddMenu(shell: shell),
    ];

    // The header's colour follows the cover of what plays (or was played last). Only this leaf is redrawn when
    // that changes; the sections above are the same widgets as before and are not rebuilt.
    return PlayerSelect<Track?>(
      select: (c) => c.currentTrack ?? c.recentlyPlayed.firstOrNull,
      builder: (context, track, _) => AccentBuilder(
        track: track,
        builder: (context, accent) => PageScaffold(
          gradientColor: accent,
          brand: true,
          hideToolbar: !LayoutPrefs.instance.showHomeToolbar,
          actions: actions,
          slivers: slivers,
        ),
      ),
    );
  }

  Widget _shelf(
    String title,
    int count,
    Widget Function(int i) card, {
    VoidCallback? onShowAll,
    bool artworkOnly = false,
  }) => SliverToBoxAdapter(
    child: Shelf.builder(
      title: title,
      count: count,
      card: card,
      onShowAll: onShowAll,
      compactSpacing: true,
      artworkOnly: artworkOnly,
    ),
  );
}

class _DailyMixShelf extends StatefulWidget {
  const _DailyMixShelf({super.key, required this.player, required this.available});

  final PlayerController player;
  final Iterable<Track> available;

  @override
  State<_DailyMixShelf> createState() => _DailyMixShelfState();
}

class _DailyMixShelfState extends State<_DailyMixShelf> {
  late Timer _midnight;

  @override
  void initState() {
    super.initState();
    _scheduleRefresh();
  }

  void _scheduleRefresh() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(tomorrow.difference(now), () {
      setState(() {});
      _scheduleRefresh();
    });
  }

  @override
  void dispose() {
    _midnight.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PlayerSelect<Object>(
    select: HomePage._recentKey,
    builder: (context, _, _) {
      final player = widget.player;
      final tracks = buildDailyMix(recent: player.recentlyPlayed, available: widget.available, day: DateTime.now());
      if (tracks.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
      final mix = Collection(
        kind: CollectionKind.smart,
        id: 'daily-mix',
        title: tr.dailyMix,
        subtitle: tr.dailyMixDescription,
        tracks: tracks,
      );
      return SliverToBoxAdapter(
        child: Shelf.builder(
          title: tr.madeForYou,
          count: 1,
          compactSpacing: true,
          card: (_) => MediaCard(
            track: mix.cover,
            title: mix.title,
            subtitle: mix.subtitle,
            onTap: () => ShellScope.of(context).openCollection(mix),
            onPlay: () => player.playCollection(mix),
          ),
        ),
      );
    },
  );
}

class _QuickPicksCarousel extends StatelessWidget {
  const _QuickPicksCarousel({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final player = PlayerScope.read(context);
    final height = (shell.width * .74).clamp(180.0, 300.0);
    Widget item(int index) {
      final track = tracks[index];
      Future<void> play() => player.playList(tracks, index, from: tr.quickPicks);
      return _HomeArtworkCard(
        artwork: Artwork(track: track, radius: 0),
        title: track.title,
        subtitle: track.artist,
        onTap: () => shell.playAndOpen(play),
        onPlay: play,
      );
    }

    final scrollBehavior = ScrollConfiguration.of(context);
    return SizedBox(
      height: height,
      child: tracks.length == 1
          ? Align(
              alignment: AlignmentDirectional.centerStart,
              child: SizedBox(width: height, height: height, child: item(0)),
            )
          : ScrollConfiguration(
              behavior: scrollBehavior.copyWith(dragDevices: {...scrollBehavior.dragDevices, PointerDeviceKind.mouse}),
              child: CarouselView.weightedBuilder(
                enableSplash: false,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                flexWeights: shell.compact ? const [8, 2, 1] : const [6, 3, 1],
                itemSnapping: true,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                itemCount: tracks.length,
                itemBuilder: (context, index) => item(index),
              ),
            ),
    );
  }
}

class _HomeArtworkCard extends StatelessWidget {
  const _HomeArtworkCard({
    required this.artwork,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.onPlay,
    this.compact = false,
  });

  final Widget artwork;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final VoidCallback? onPlay;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(compact ? 20 : 28);
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: title,
      child: Material(
        clipBehavior: Clip.antiAlias,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          child: LayoutBuilder(
            builder: (context, limits) => Stack(
              fit: StackFit.expand,
              children: [
                artwork,
                if (limits.maxWidth >= 80)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: .68),
                      child: Padding(
                        padding: EdgeInsets.all(compact ? 8 : 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: compact ? 1 : 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: (compact ? text.labelLarge : text.titleLarge)?.copyWith(color: Colors.white),
                                  ),
                                  if (subtitle case final subtitle? when !compact)
                                    Text(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: text.bodyMedium?.copyWith(color: Colors.white),
                                    ),
                                ],
                              ),
                            ),
                            if (onPlay != null && !compact && limits.maxWidth > 145)
                              IconButton.filled(
                                tooltip: tr.play,
                                onPressed: onPlay,
                                icon: const Icon(Icons.play_arrow_rounded),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The song Home opens [artist] through: one of theirs that came from YouTube Music (a download remembers its
/// video), so the card leads to their page there. Best is one that names them first and knows their channel;
/// then one that names them first (the channel is looked up by name); then any (they are a featured artist).
/// Null when every song of theirs is a file of the person's own.
@visibleForTesting
Track? youtubeSongOf(Collection artist) {
  Track? first, any;
  for (final t in artist.tracks) {
    if (!t.isRemote && !t.isDownload) continue;
    any ??= t;
    if (t.artists.firstOrNull != artist.title) continue;
    if (t.artistId != null) return t;
    first ??= t;
  }
  return first ?? any;
}

/// What a tap on [artist] in Home's Artists shelf does. An artist with even one song from YouTube Music opens
/// their YouTube Music page (albums, singles, About), not the library's page holding only what was downloaded;
/// an artist known from the person's own files alone opens the library's page, the only one there is.
/// `RIFLAY_LOCAL_HOME_ARTISTS` opens the library's page for all of them, as before.
VoidCallback openHomeArtist(BuildContext host, PlayerController c, Collection artist, {ShellScope? shell}) {
  final navigation = shell ?? ShellScope.of(host);
  final song = DebugSwitches.localHomeArtists ? null : youtubeSongOf(artist);
  final open = song == null ? null : openArtist(host, c, song, shell: navigation, name: artist.title);
  return open ?? () => navigation.openCollection(artist);
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
        if (shell.addFolder != null)
          PopupMenuItem(
            value: shell.addFolder,
            child: MenuRow(leading: Icon(Icons.folder_open_rounded), title: Text(tr.addFolder)),
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
