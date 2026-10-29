import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/player_controller.dart';
import '../../services/youtube_music_account.dart';
import '../../services/youtube_video_search.dart';
import '../../services/ytmusic_web.dart' show WebResultKind;
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/track_row.dart';
import 'search/local_results.dart';
import 'search/remote_results.dart';
import 'search/search_box.dart';
import 'search/search_input.dart';
import 'search/search_parts.dart';

// The search page's other parts live in search/: the box (and its suggestions),
// the saved searches, the library's memoised answer and the YouTube sections.
export 'search/local_results.dart' show LocalSearchMemo;
export 'search/search_box.dart' show SearchBox;
export 'search/search_input.dart' show SearchInput, RecentSearches;

/// How long typing must pause before the library is scanned again (YouTube waits longer, below).
const _localDebounce = Duration(milliseconds: 80);

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.focusNode, this.input});

  final FocusNode? focusNode;

  /// Desktop: the title bar's search box types into this page, which then
  /// shows no box of its own.
  final SearchInput? input;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final TextEditingController _controller = widget.input?.controller ?? TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.input case final input?) {
      input.controller.addListener(_fromBar);
      input.submitted.addListener(_submittedFromBar);
      // Opened by typing: pick up what's there already.
      WidgetsBinding.instance.addPostFrameCallback((_) => _fromBar());
    }
  }

  void _fromBar() {
    if (mounted && _controller.text != _query) _onQuery(_controller.text);
  }

  void _submittedFromBar() {
    if (mounted) _submit(widget.input!.submitted.value.$1);
  }

  String _query = '';

  /// What the library is searched for: [_query], a moment after typing pauses.
  String _localQuery = '';
  final _memo = LocalSearchMemo();
  Timer? _debounce;
  Timer? _localTimer;
  Future<List<Track>>? _youtube;
  Future<SearchResults>? _all;

  /// [_all] and [_youtube] together, made when the search goes out (not in a build).
  Future<List<Object?>>? _top;

  /// Filter chip: null is "All".
  WebResultKind? _filter;
  Future<List<RemotePlaylist>>? _only;

  /// "Videos": plain YouTube instead of YouTube Music songs.
  bool _videos = false;
  YoutubeVideoSearch? _videoSearch;
  List<Track> _videoTracks = const [];
  bool _videoLoading = false;
  bool _videoFailed = false;
  bool _videoLoadingMore = false;
  bool _videoEnd = false;
  int _videoRun = 0;

  /// The last results shown: they stay (dimmed) while the next query loads, instead of flashing a spinner.
  final _shown = ShownSongs();

  @override
  void dispose() {
    _debounce?.cancel();
    _localTimer?.cancel();
    _videoSearch?.dispose();
    if (widget.input case final input?) {
      input.controller.removeListener(_fromBar);
      input.submitted.removeListener(_submittedFromBar);
    } else {
      _controller.dispose();
    }
    super.dispose();
  }

  void _onQuery(String value) {
    // The first letter (and clearing the box) answers at once; after that, once typing pauses.
    final now = value.trim().isEmpty || _localQuery.trim().isEmpty;
    _localTimer?.cancel();
    setState(() {
      _query = value;
      if (now) _localQuery = value;
    });
    if (!now) {
      _localTimer = Timer(_localDebounce, () {
        if (mounted) setState(() => _localQuery = _query);
      });
    }
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      _videoRun++;
      setState(() {
        _youtube = _all = _only = _top = null;
        _videoTracks = const [];
        _videoLoading = false;
      });
      return;
    }
    // Debounced: only hit YouTube once typing pauses.
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted) setState(() => _searchYoutube(q));
    });
  }

  void _submit(String value) {
    // Enter: search now instead of waiting out the debounce.
    _debounce?.cancel();
    _localTimer?.cancel();
    if (_controller.text != value) _controller.text = value;
    setState(() {
      _query = value;
      _localQuery = value;
    });
    final q = value.trim();
    if (q.length >= 2) {
      setState(() => _searchYoutube(q));
      RecentSearches.add(q);
    }
  }

  void _searchYoutube(String q) {
    if (_videos) return _searchVideos(q);
    final c = PlayerScope.read(context);
    _youtube = c.searchYoutube(q);
    _all = c.ytMusic.search(q);
    _top = topAndSongsFuture(_all, _youtube);
    _only = _filter == null || _filter == WebResultKind.song ? null : c.ytMusic.searchOnly(q, _filter!);
  }

  void _searchVideos(String q) {
    final run = ++_videoRun;
    final search = _videoSearch ??= YoutubeVideoSearch();
    _videoLoading = true;
    _videoFailed = false;
    _videoLoadingMore = false;
    _videoEnd = false;
    search
        .search(q)
        .then(
          (tracks) {
            if (!mounted || run != _videoRun) return;
            setState(() {
              _videoTracks = tracks;
              _videoLoading = false;
              _videoEnd = !search.hasMore;
            });
          },
          onError: (Object e) {
            debugPrint('Video search failed: $e');
            if (!mounted || run != _videoRun) return;
            setState(() {
              _videoTracks = const [];
              _videoLoading = false;
              _videoFailed = true;
            });
          },
        );
  }

  /// The end of the list scrolled into view: fetch the next page.
  Future<void> _moreVideos() async {
    if (!mounted) return;
    final search = _videoSearch;
    if (search == null || _videoLoadingMore || _videoLoading || _videoEnd) return;
    _videoLoadingMore = true;
    final run = _videoRun;
    try {
      final more = await search.more();
      if (!mounted || run != _videoRun) return;
      setState(() {
        _videoTracks = [..._videoTracks, ...more];
        _videoEnd = more.isEmpty || !search.hasMore;
      });
    } catch (e) {
      debugPrint('More videos failed: $e');
      if (mounted && run == _videoRun) setState(() => _videoEnd = true);
    } finally {
      if (run == _videoRun) _videoLoadingMore = false;
    }
  }

  void _setVideos(bool videos) {
    if (videos == _videos) return;
    setState(() {
      _videos = videos;
      final q = _query.trim();
      if (q.length >= 2) {
        _searchYoutube(q);
      } else {
        _videoRun++;
      }
    });
  }

  void _setFilter(WebResultKind? f) {
    setState(() {
      _filter = f;
      final q = _query.trim();
      _only = f == null || f == WebResultKind.song || q.length < 2
          ? null
          : PlayerScope.read(context).ytMusic.searchOnly(q, f);
    });
  }

  @override
  Widget build(BuildContext context) {
    // The library changing (a scan, an edit), not every change of what's playing:
    // song rows follow that themselves.
    final c = PlayerScope.identity(context);
    return ValueListenableBuilder<int>(
      valueListenable: c.libraryRevision,
      builder: (context, revision, _) => _build(context, c, revision),
    );
  }

  Widget _build(BuildContext context, PlayerController c, int revision) {
    final shell = ShellScope.of(context);
    final text = Theme.of(context).textTheme;
    final pad = shell.compact ? 16.0 : 24.0;
    final local = _memo.of(c, _localQuery, revision);
    final results = local.songs;
    final artists = local.artists;
    final albums = local.albums;
    final q = _query.trim().toLowerCase();
    final searching = q.length >= 2;

    return PageScaffold(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (shell.compact) ...[
                  Text('Search', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                ],
                if (widget.input == null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: SearchBox(
                      controller: _controller,
                      focusNode: widget.focusNode,
                      onChanged: _onQuery,
                      onSubmitted: _submit,
                    ),
                  ),
                if (searching) ...[
                  if (widget.input == null) const SizedBox(height: 16),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, label: Text('Songs')),
                      ButtonSegment(value: true, label: Text('Videos')),
                    ],
                    selected: {_videos},
                    onSelectionChanged: (s) => _setVideos(s.first),
                  ),
                  if (!_videos) const SizedBox(height: 12),
                  if (!_videos)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (label, kind) in const [
                          ('All', null),
                          ('Songs', WebResultKind.song),
                          ('Artists', WebResultKind.artist),
                          ('Albums', WebResultKind.album),
                          ('Playlists', WebResultKind.playlist),
                        ])
                          FilterChip(
                            label: Text(label),
                            selected: _filter == kind,
                            onSelected: (_) => _setFilter(kind),
                          ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        ),
        if (q.isEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
              child: Text(
                'Searches your own music and all of YouTube Music together. Songs with a cloud stream online; '
                'the rest play offline.',
                style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ),
          if (artists.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionTitle('Browse artists')),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  childAspectRatio: 1.6,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                ),
                itemCount: artists.length,
                itemBuilder: (context, i) => AccentBuilder(
                  track: artists[i].cover,
                  builder: (context, color) => BrowseTile(
                    title: artists[i].title,
                    color: color,
                    cover: Artwork(track: artists[i].cover, radius: 4),
                    onTap: () => shell.openCollection(artists[i]),
                  ),
                ),
              ),
            ),
          ],
        ] else if (_videos) ...[
          if (searching)
            VideoResults(
              tracks: _videoTracks,
              loading: _videoLoading,
              failed: _videoFailed,
              atEnd: _videoEnd,
              onMore: _moreVideos,
            ),
        ] else if (_filter == WebResultKind.song) ...[
          YoutubeSongResults(future: _youtube, shown: _shown),
        ] else if (_filter != null) ...[
          CollectionGrid(future: _only),
        ] else ...[
          if (searching) TopAndSongs(future: _top),
          if (results.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionTitle('In your library')),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: shell.compact ? 12 : 16),
              sliver: SliverList.builder(
                itemCount: results.length.clamp(0, 8),
                itemBuilder: (context, i) => TrackRow(
                  track: results[i],
                  onTap: () => c.playList(results, i, from: 'Search'),
                ),
              ),
            ),
          ],
          if (searching) RemoteShelves(future: _all),
          if (artists.isNotEmpty && results.isNotEmpty)
            libraryShelf('Your artists', [
              for (final a in artists)
                MediaCard(
                  track: a.cover,
                  title: a.title,
                  subtitle: 'Artist',
                  circle: true,
                  onTap: () => shell.openCollection(a),
                ),
            ]),
          if (albums.isNotEmpty)
            libraryShelf('Your albums', [
              for (final a in albums)
                MediaCard(
                  track: a.cover,
                  title: a.title,
                  subtitle: a.subtitle,
                  onTap: () => shell.openCollection(a),
                  onPlay: () => c.playCollection(a),
                ),
            ]),
        ],
      ],
    );
  }
}
