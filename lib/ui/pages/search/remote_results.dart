import 'package:flutter/material.dart';

import '../../../models/track.dart';
import '../../../services/player_controller.dart';
import '../../../services/youtube_music_account.dart';
import '../../../services/ytmusic_web.dart' show WebResultKind;
import '../../shell_scope.dart';
import '../../theme.dart';
import '../../widgets/controls.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/shelf.dart';
import '../../widgets/track_row.dart';
import '../youtube_music_page.dart' show openRemotePlaylist, playlistCover;
import 'search_parts.dart';
import '../../widgets/skeleton.dart';
import '../../../services/language.dart';

/// Opens a search hit: plays a song, opens an artist / album / playlist.
void openSearchHit(BuildContext context, SearchHit hit) {
  final c = PlayerScope.read(context);
  if (hit.track case final t?) {
    c.playList([t], 0, from: tr.navSearch);
  } else {
    openRemotePlaylist(context, hit.collection!);
  }
}

/// Plays a YouTube Music album / playlist / artist straight from its card.
Future<void> playRemote(BuildContext context, RemotePlaylist p) async {
  final c = PlayerScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final tracks = await c.ytMusic.collectionTracks(p);
    if (tracks.isNotEmpty) await c.playList(tracks, 0, from: p.title);
  } catch (e) {
    debugPrint('Playing ${p.title} failed: $e');
    messenger.showSnackBar(SnackBar(content: Text(tr.couldntPlay(p.title))));
  }
}

class RemoteCard extends StatelessWidget {
  const RemoteCard({super.key, required this.collection});

  final RemotePlaylist collection;

  @override
  Widget build(BuildContext context) => MediaCard(
    track: playlistCover(collection),
    title: collection.title,
    subtitle: collection.subtitle ?? '',
    circle: collection.browseId?.startsWith('UC') ?? false,
    online: true,
    onTap: () => openRemotePlaylist(context, collection),
    onPlay: () => playRemote(context, collection),
  );
}

/// The big "Top result" card.
class TopResult extends StatelessWidget {
  const TopResult({super.key, required this.hit});

  final SearchHit hit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final artist = hit.kind == WebResultKind.artist;
    return Material(
      color: AppColors.elevated,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openSearchHit(context, hit),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Artwork(track: hit.cover, size: 96, radius: 6, circle: artist),
                    const SizedBox(height: 16),
                    Text(
                      hit.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hit.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              PlayButton(
                playing: false,
                size: 48,
                color: AppColors.accent,
                iconColor: AppColors.onAccent,
                onPressed: () => hit.track != null ? openSearchHit(context, hit) : playRemote(context, hit.collection!),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A request's two answers with failures turned into nulls, made once per search
/// (not in a build, which would hand the [FutureBuilder] a new future each time
/// and flash its spinner on every rebuild).
Future<List<Object?>> topAndSongsFuture(Future<SearchResults>? all, Future<List<Track>>? youtube) =>
    Future.wait<Object?>([
      all?.then<SearchResults?>((r) => r, onError: (Object _) => null) ?? Future.value(null),
      youtube?.then<List<Track>?>((r) => r, onError: (Object _) => null) ?? Future.value(null),
    ]);

/// "All": the top result card next to the first songs (stacked on phones).
class TopAndSongs extends StatelessWidget {
  const TopAndSongs({super.key, required this.future});

  /// From [topAndSongsFuture]; null before the first search goes out.
  final Future<List<Object?>>? future;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    final shell = ShellScope.of(context);
    final pad = shell.compact ? 16.0 : 24.0;
    return FutureBuilder<List<Object?>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return SearchSpinner(pad: pad);
        final all = snap.data![0] as SearchResults?;
        final songs = (snap.data![1] as List<Track>?) ?? all?.songs ?? const <Track>[];
        final top = all?.top;
        if (top == null && songs.isEmpty) {
          return SearchNote(all == null ? tr.ytSearchFailed : tr.noYtResults, pad: pad);
        }
        final topCard = top == null ? null : TopResult(hit: top);
        final list = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, t) in songs.take(4).indexed)
              maybeFade(
                i,
                TrackRow(
                  track: t,
                  showAlbum: false,
                  onTap: () => c.playList(songs, i, from: tr.ytSearchSource),
                ),
              ),
          ],
        );
        Widget heading(String title) => SectionTitle(title);
        return SliverToBoxAdapter(
          child: shell.compact || shell.width < 760
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (topCard != null) ...[
                      heading(tr.topResult),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: pad),
                        child: topCard,
                      ),
                    ],
                    if (songs.isNotEmpty) ...[
                      heading(tr.songs),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: list),
                    ],
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (topCard != null)
                      SizedBox(
                        width: 420,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            heading(tr.topResult),
                            Padding(
                              padding: EdgeInsets.only(left: pad),
                              child: topCard,
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          heading(tr.songs),
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: list),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

/// A titled shelf as a sliver.
Widget _row(String title, List<Widget> cards) => SliverToBoxAdapter(
  child: Shelf(title: title, cards: cards),
);

/// "All": rows of artists, albums and playlists from YouTube Music.
class RemoteShelves extends StatelessWidget {
  const RemoteShelves({super.key, required this.future});

  final Future<SearchResults>? future;

  @override
  Widget build(BuildContext context) => FutureBuilder<SearchResults>(
    future: future,
    builder: (context, snap) {
      final r = snap.data;
      if (r == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
      return SliverMainAxisGroup(
        slivers: [
          if (r.artists.isNotEmpty) _row(tr.artists, [for (final a in r.artists) RemoteCard(collection: a)]),
          if (r.albums.isNotEmpty) _row(tr.albums, [for (final a in r.albums) RemoteCard(collection: a)]),
          if (r.playlists.isNotEmpty) _row(tr.playlists, [for (final a in r.playlists) RemoteCard(collection: a)]),
        ],
      );
    },
  );
}

/// The shelf of the library's own artists / albums.
Widget libraryShelf(String title, List<Widget> cards) => _row(title, cards);

/// A filter chip other than Songs: every matching artist / album / playlist.
class CollectionGrid extends StatelessWidget {
  const CollectionGrid({super.key, required this.future});

  final Future<List<RemotePlaylist>>? future;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final pad = shell.compact ? 16.0 : 24.0;
    return FutureBuilder<List<RemotePlaylist>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return SearchSpinner(pad: pad);
        final items = snap.data ?? const <RemotePlaylist>[];
        if (items.isEmpty) {
          return SearchNote(snap.hasError ? tr.ytSearchFailed : tr.nothingFound, pad: pad);
        }
        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: shell.compact ? 6 : 14),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: shell.compact ? 180 : 210,
              mainAxisExtent: (shell.compact ? 180 : 210) + 64,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) => maybeFade(i, RemoteCard(collection: items[i])),
          ),
        );
      },
    );
  }
}

/// The songs last shown, kept by the page: they stay (dimmed) while the next query loads, instead of a spinner.
class ShownSongs {
  List<Track> tracks = const [];
}

/// The "Songs" chip: YouTube Music songs for the query (or SoundCloud's, with its own [from] and notes).
class YoutubeSongResults extends StatelessWidget {
  const YoutubeSongResults({
    super.key,
    required this.future,
    required this.shown,
    this.from,
    this.failedNote,
    this.emptyNote,
  });

  final Future<List<Track>>? future;
  final ShownSongs shown;

  /// What the queue says it plays from; YouTube search when null.
  final String? from;

  /// The line shown when the search fails, or finds nothing; YouTube's when null.
  final String? failedNote;
  final String? emptyNote;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    final shell = ShellScope.of(context);
    final pad = shell.compact ? 16.0 : 24.0;
    return FutureBuilder<List<Track>>(
      future: future,
      builder: (context, snap) {
        final loading = future == null || snap.connectionState != ConnectionState.done;
        if (!loading && snap.hasData) shown.tracks = snap.data!;
        if (loading && shown.tracks.isNotEmpty) {
          final previous = shown.tracks;
          return SliverMainAxisGroup(
            slivers: [
              SliverOpacity(
                opacity: 0.5,
                sliver: SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: shell.compact ? 12 : 16),
                  sliver: SliverList.builder(
                    itemCount: previous.length,
                    itemBuilder: (context, i) => TrackRow(
                      track: previous[i],
                      showAlbum: false,
                      onTap: () => c.playList(previous, i, from: from ?? tr.ytSearchSource),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        if (loading) return SearchSpinner(pad: pad);
        final tracks = snap.data ?? const <Track>[];
        if (snap.hasError || tracks.isEmpty) {
          return SearchNote(snap.hasError ? failedNote ?? tr.ytSearchFailed : emptyNote ?? tr.noYtResults, pad: pad);
        }
        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: shell.compact ? 12 : 16),
          sliver: SliverList.builder(
            itemCount: tracks.length,
            itemBuilder: (context, i) => maybeFade(
              i,
              TrackRow(
                track: tracks[i],
                showAlbum: false,
                onTap: () => c.playList(tracks, i, from: from ?? tr.ytSearchSource),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// "Videos": plain YouTube results as playable rows, the next page loading as the end comes into view.
class VideoResults extends StatelessWidget {
  const VideoResults({
    super.key,
    required this.tracks,
    required this.loading,
    required this.failed,
    required this.atEnd,
    required this.onMore,
  });

  final List<Track> tracks;
  final bool loading;
  final bool failed;
  final bool atEnd;

  /// The end of the list scrolled into view: fetch the next page.
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    final shell = ShellScope.of(context);
    final pad = shell.compact ? 16.0 : 24.0;
    const spinner = Padding(padding: EdgeInsets.symmetric(vertical: 8), child: SkeletonList(count: 4, rowSize: 44));
    if (loading && tracks.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: spinner,
        ),
      );
    }
    if (tracks.isEmpty) {
      return SearchNote(failed ? tr.ytSearchFailed : tr.noYtVideos, pad: pad);
    }
    final tail = !atEnd && !loading;
    return SliverMainAxisGroup(
      slivers: [
        SliverOpacity(
          opacity: loading ? 0.5 : 1,
          sliver: SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: shell.compact ? 12 : 16),
            sliver: SliverList.builder(
              itemCount: tracks.length + (tail ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= tracks.length) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (context.mounted) onMore();
                  });
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: pad - 12),
                    child: spinner,
                  );
                }
                return maybeFade(
                  i,
                  TrackRow(
                    track: tracks[i],
                    showAlbum: false,
                    onTap: () => c.playList(tracks, i, from: tr.ytVideosSource),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
