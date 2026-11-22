import 'dart:async';
import 'dart:math' as math;

import 'home_page.dart' show openHomeArtist;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/sources/music_sources.dart';
import '../../services/spotiflac.dart';
import '../../services/language.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../../services/soundcloud.dart' show SoundcloudCollection;
import '../../services/youtube_music_account.dart';
import '../../services/youtube_video_search.dart';
import '../../services/ytmusic_web.dart' show WebResultKind;
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/spotiflac_notice.dart';
import '../widgets/track_row.dart';
import 'search/free_sources.dart';
import 'spotiflac_verification_page.dart';
import 'search/local_results.dart';
import 'search/remote_results.dart';
import 'search/search_box.dart';
import 'search/search_input.dart';
import 'search/search_parts.dart';
import 'search/soundcloud_results.dart';

// The search page's other parts live in search/: the box (and its suggestions),
// the saved searches, the library's memoised answer and the YouTube sections.
export 'search/local_results.dart' show LocalSearchMemo;
export 'search/search_box.dart' show SearchBox;
export 'search/search_input.dart' show SearchInput, RecentSearches;

/// How long typing must pause before the library is scanned again (YouTube waits longer, below).
const _localDebounce = Duration(milliseconds: 80);

/// A filter of the centred search: an icon and its name, the picked one on a soft tile, no outline.
class SearchTab extends StatelessWidget {
  const SearchTab({super.key, required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.textPrimary : AppColors.textSecondary;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.hover : Colors.transparent,
        borderRadius: LayoutPrefs.corner(8),
        child: InkWell(
          borderRadius: LayoutPrefs.corner(8),
          onTap: selected ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Settings › Centered search: Search over the page, as wide as a column down its middle.
class SearchPopup extends StatelessWidget {
  const SearchPopup({super.key, required this.input, required this.focusNode});

  final SearchInput input;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // A block of one height in the middle of the window, its box at the top: the box doesn't move as results
    // come and go, and it sits where the eye is rather than at the window's top edge.
    final height = math.min(640.0, size.height * 0.72);
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 920, maxHeight: height),
            child: Material(
              type: MaterialType.transparency,
              child: SearchPage(input: input, focusNode: focusNode, popup: true),
            ),
          ),
        ),
      ),
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.focusNode, this.input, this.boxInBar, this.popup = false});

  final FocusNode? focusNode;

  /// Drawn in [SearchPopup]: the box over the results, whatever the title bar holds.
  final bool popup;

  /// Desktop: the title bar's search box types into this page, which then
  /// shows no box of its own.
  final SearchInput? input;

  /// Phone: while true the Liquid glass tab bar carries the box (typing into [input]); the page shows its own,
  /// on the same [input], otherwise.
  final ValueListenable<bool>? boxInBar;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final TextEditingController _controller = widget.input?.controller ?? TextEditingController();
  StreamSubscription<SearchSource>? _sourceSelection;

  @override
  void initState() {
    super.initState();
    MusicSources.instance.load().ignore();
    MusicSources.instance.addListener(_followMusicSources);
    Spotiflac.instance.addListener(_followMusicSources);
    SearchSource.current.addListener(_followSource);
    SearchSource.load().ignore();
    if (widget.input case final input?) {
      input.controller.addListener(_fromBar);
      input.submitted.addListener(_submittedFromBar);
      _sourceSelection = input.sourceSelection.listen(_selectSource);
      // Opened by typing: the first build already answers what's in the box (no empty page first).
      // One letter has nothing to send to YouTube; longer text goes through the usual path.
      if (_controller.text.trim().length < 2) {
        _query = _localQuery = _controller.text;
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => _fromBar());
      }
    }
  }

  void _fromBar() {
    if (mounted && _controller.text != _query) _onQuery(_controller.text);
  }

  void _submittedFromBar() {
    if (mounted) _submit(widget.input!.submitted.value.$1);
  }

  String _query = '';
  bool _applyingCommand = false;
  SearchSource? _blockedSource;

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

  /// "Videos": YouTube Music's videos (plain YouTube when that fails) instead of its songs.
  bool _videos = false;
  YoutubeVideoSearch? _videoSearch;
  List<Track> _videoTracks = const [];
  bool _videoLoading = false;
  bool _videoFailed = false;
  bool _videoLoadingMore = false;
  bool _videoEnd = false;
  int _videoRun = 0;

  /// "Podcasts": YouTube Music's shows (opening as their episodes) over the episodes themselves.
  bool _podcasts = false;
  Future<List<RemotePlaylist>>? _podcastShows;
  Future<List<Track>>? _episodes;
  final _shownEpisodes = ShownSongs();

  /// The last results shown: they stay (dimmed) while the next query loads, instead of flashing a spinner.
  final _shown = ShownSongs();

  /// Where to search online (always YouTube Music where SoundCloud isn't offered).
  SearchSource get _source => SearchSource.available.contains(SearchSource.current.value)
      ? SearchSource.current.value
      : SearchSource.youtubeMusic;
  bool get _onSoundcloud => _source == SearchSource.soundcloud;
  bool get _onMonochrome => _source == SearchSource.monochrome;
  bool get _onYoutube => _source == SearchSource.youtubeMusic;
  Future<List<Track>>? _monochrome;
  Future<List<Track>>? _extensionResults;
  String? _extensionSelection;
  bool get _onExtensions => _source == SearchSource.extensions;
  Future<List<Track>>? _soundcloud;
  Future<({List<SoundcloudCollection> playlists, List<SoundcloudCollection> users})>? _soundcloudShelves;

  @override
  void dispose() {
    _debounce?.cancel();
    _localTimer?.cancel();
    _videoSearch?.dispose();
    SearchSource.current.removeListener(_followSource);
    MusicSources.instance.removeListener(_followMusicSources);
    Spotiflac.instance.removeListener(_followMusicSources);
    if (widget.input case final input?) {
      input.controller.removeListener(_fromBar);
      input.submitted.removeListener(_submittedFromBar);
      _sourceSelection?.cancel();
    } else {
      _controller.dispose();
    }
    super.dispose();
  }

  String _readCommand(String text) {
    final command = SearchSource.readCommand(text);
    _blockedSource = null;
    if (command == null) return RegExp(r'^\s*:[a-z]*$', caseSensitive: false).hasMatch(text) ? '' : text;
    if (!SearchSource.available.contains(command.source)) {
      _blockedSource = command.source;
    } else {
      _applyingCommand = true;
      command.source.choose();
      _applyingCommand = false;
    }
    return command.query;
  }

  void _selectSource(SearchSource source) {
    final query = SearchSource.readCommand(_controller.text)?.query ?? _controller.text;
    _applyingCommand = true;
    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    source.choose();
    _applyingCommand = false;
    _submit(query);
  }

  void _onQuery(String value) {
    if (_applyingCommand) return;
    value = _readCommand(value);
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
        _soundcloud = _soundcloudShelves = null;
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
    final original = value;
    value = _readCommand(value);
    setState(() {
      _query = value;
      _localQuery = value;
    });
    final q = value.trim();
    if (q.length >= 2) {
      setState(() => _searchYoutube(q));
      RecentSearches.add(original.trim());
    }
  }

  void _searchYoutube(String q, {bool freshExtension = false}) {
    if (_blockedSource != null) return;
    final c = PlayerScope.read(context);
    if (_onExtensions) {
      _extensionSelection = Spotiflac.instance.selected;
      _extensionResults = Spotiflac.instance.search(q, fresh: freshExtension)..ignore();
      _youtube = _all = _only = _top = null;
      _soundcloud = null;
      _soundcloudShelves = null;
      return;
    }
    _monochrome = null;
    if (_onMonochrome) {
      _monochrome = c.monochrome.search(q, limit: 50)..ignore();
      _youtube = _all = _only = _top = null;
      _soundcloud = null;
      _soundcloudShelves = null;
      return;
    }
    _soundcloud = _onSoundcloud ? c.searchSoundcloud(q) : null;
    _soundcloudShelves = _onSoundcloud
        ? c.soundcloud.searchCollections(q).catchError((Object e) {
            debugPrint('SoundCloud playlist / artist search failed: $e');
            return (playlists: <SoundcloudCollection>[], users: <SoundcloudCollection>[]);
          })
        : null;
    if (_onSoundcloud) {
      _youtube = _all = _only = _top = null;
      return;
    }
    if (_videos) return _searchVideos(q);
    if (_podcasts) {
      _podcastShows = c.ytMusic.searchPodcasts(q)..ignore();
      _episodes = c.ytMusic.searchEpisodes(q)..ignore();
      return;
    }
    _youtube = c.searchYoutube(q);
    _all = c.ytMusic.search(q);
    _top = topAndSongsFuture(_all, _youtube);
    _only = _filter == null || _filter == WebResultKind.song ? null : c.ytMusic.searchOnly(q, _filter!);
  }

  void _retryExtension({bool fresh = true}) {
    final query = _query.trim();
    if (!_onExtensions || query.length < 2) return;
    _debounce?.cancel();
    setState(() => _searchYoutube(query, freshExtension: fresh));
  }

  Future<void> _verifySearchExtension() async {
    final provider = _extensionSelection;
    if (provider == null || provider != Spotiflac.instance.selected) return;
    final verified = await showSpotiflacSearchVerification(context, provider);
    if (mounted && verified && provider == Spotiflac.instance.selected) _retryExtension(fresh: false);
  }

  void _searchVideos(String q) {
    final run = ++_videoRun;
    final music = PlayerScope.read(context).ytMusic;
    final search = _videoSearch ??= YoutubeVideoSearch(
      music: (query, continuation) => music.searchVideoPage(query, continuation: continuation),
    );
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

  void _setPodcasts(bool podcasts) {
    if (podcasts == _podcasts) return;
    setState(() {
      _podcasts = podcasts;
      if (podcasts) _videos = false;
      final q = _query.trim();
      if (q.length >= 2) _searchYoutube(q);
    });
  }

  void _setVideos(bool videos) {
    if (videos) _podcasts = false;
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

  /// The source was switched (here or in the top bar): the query is searched there.
  void _followSource() {
    if (!mounted || _applyingCommand) return;
    setState(() {
      final q = _query.trim();
      if (q.length >= 2) _searchYoutube(q);
    });
  }

  void _setFilter(WebResultKind? f) {
    setState(() {
      _filter = f;
      final q = _query.trim();
      _only = f == null || f == WebResultKind.song || q.length < 2 || _onSoundcloud
          ? null
          : PlayerScope.read(context).ytMusic.searchOnly(q, f);
    });
  }

  void _followMusicSources() {
    final previous = SearchSource.current.value;
    SearchSource.ensureAvailable();
    if (previous != SearchSource.current.value) return;
    if (_onExtensions && _extensionSelection != Spotiflac.instance.selected && _query.trim().length >= 2) {
      if (mounted) setState(() => _searchYoutube(_query.trim()));
      return;
    }
    if (mounted) setState(() {});
  }

  /// "In your library": the first songs of the library that match.
  List<Widget> _library(PlayerController c, List<Track> results, ShellScope shell) => [
    if (results.isNotEmpty) ...[
      SliverToBoxAdapter(child: SectionTitle(tr.inYourLibrary)),
      SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: shell.compact ? 12 : 16),
        sliver: SliverList.builder(
          itemCount: results.length.clamp(0, 8),
          itemBuilder: (context, i) => TrackRow(
            track: results[i],
            onTap: () => c.playList(results, i, from: tr.navSearch),
          ),
        ),
      ),
    ],
  ];

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
    // Settings › Centered search: the box over the results, both down the middle of the page.
    final centered = widget.popup || !shell.compact && LayoutPrefs.instance.centeredSearch;
    Widget box({required ValueChanged<String> onChanged}) => ConstrainedBox(
      constraints: BoxConstraints(maxWidth: centered ? double.infinity : 520),
      child: SearchBox(
        controller: _controller,
        // Centered beside a title bar without its box: Ctrl+F and the rail's Search still put the cursor here.
        focusNode: widget.focusNode ?? (centered && widget.boxInBar == null ? widget.input?.focus : null),
        onChanged: onChanged,
        onSubmitted: _submit,
        onSourceSelected: _selectSource,
        flat: centered,
      ),
    );

    final field = box(onChanged: widget.input == null ? _onQuery : (_) {});
    final page = PageScaffold(
      transparent: widget.popup,
      hideToolbar: widget.popup,
      slivers: _arrange(centered, widget.popup, field, [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (shell.compact) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(tr.navSearch, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                if (widget.input == null && !centered)
                  box(onChanged: _onQuery)
                else if (widget.boxInBar case final inBar?)
                  // Typing reaches [_onQuery] through the input's listener.
                  ValueListenableBuilder(
                    valueListenable: inBar,
                    // Carried by the Liquid glass bar: its suggestions are drawn here, the field being at the bottom.
                    builder: (context, carried, _) => carried
                        ? Padding(
                            padding: EdgeInsets.only(bottom: searching ? 16 : 0),
                            child: SearchSuggestions(input: widget.input!),
                          )
                        : Padding(
                            padding: EdgeInsets.only(bottom: searching ? 16 : 0),
                            child: box(onChanged: (_) {}),
                          ),
                  ),
                if (_onExtensions) const Padding(padding: EdgeInsets.only(top: 12), child: SpotiflacNotice()),
                if (searching) ...[
                  if (widget.input == null && !centered) const SizedBox(height: 16),
                  if (centered && _onYoutube)
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final (icon, label, kind) in [
                          (Icons.grid_view_rounded, tr.all, null),
                          (Icons.music_note_rounded, tr.songs, WebResultKind.song),
                          (Icons.person_rounded, tr.artists, WebResultKind.artist),
                          (Icons.album_rounded, tr.albums, WebResultKind.album),
                          (Icons.queue_music_rounded, tr.playlists, WebResultKind.playlist),
                        ])
                          SearchTab(
                            icon: icon,
                            label: label,
                            selected: !_videos && !_podcasts && _filter == kind,
                            onTap: () {
                              _setVideos(false);
                              _setPodcasts(false);
                              _setFilter(kind);
                            },
                          ),
                        SearchTab(
                          icon: Icons.smart_display_rounded,
                          label: tr.videos,
                          selected: _videos,
                          onTap: () => _setVideos(true),
                        ),
                        SearchTab(
                          icon: Icons.podcasts_rounded,
                          label: tr.podcasts,
                          selected: _podcasts,
                          onTap: () => _setPodcasts(true),
                        ),
                      ],
                    ),
                  if (!centered)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (_onYoutube)
                          SegmentedButton<int>(
                            showSelectedIcon: false,
                            segments: [
                              ButtonSegment(value: 0, label: Text(tr.songs)),
                              ButtonSegment(value: 1, label: Text(tr.videos)),
                              ButtonSegment(value: 2, label: Text(tr.podcasts)),
                            ],
                            selected: {_podcasts ? 2 : (_videos ? 1 : 0)},
                            onSelectionChanged: (s) {
                              _setVideos(s.first == 1);
                              _setPodcasts(s.first == 2);
                            },
                          ),
                      ],
                    ),
                  if (!_videos && !_podcasts && _onYoutube && !centered) const SizedBox(height: 12),
                  if (!_videos && !_podcasts && _onYoutube && !centered)
                    SearchChips(
                      children: [
                        for (final (label, kind) in [
                          (tr.all, null),
                          (tr.songs, WebResultKind.song),
                          (tr.artists, WebResultKind.artist),
                          (tr.albums, WebResultKind.album),
                          (tr.playlists, WebResultKind.playlist),
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
        if (_blockedSource case final source?) ...[
          SearchNote(tr.enableSourceForSearch(source.label), pad: pad),
        ] else if (q.isEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
              child: Text(
                tr.searchIntro(_source.label),
                style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ),
          if (artists.isNotEmpty) ...[
            SliverToBoxAdapter(child: SectionTitle(tr.browseArtists)),
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
                    onTap: openHomeArtist(context, c, artists[i], shell: shell),
                  ),
                ),
              ),
            ),
          ],
        ] else if (_onExtensions) ...[
          if (searching)
            MonochromeSection(
              future: _extensionResults,
              source: Spotiflac.instance.selectedName,
              onRetry: _retryExtension,
              onVerify: _verifySearchExtension,
            ),
          ..._library(c, results, shell),
        ] else if (_onMonochrome) ...[
          if (searching) MonochromeSection(future: _monochrome),
          ..._library(c, results, shell),
        ] else if (_onSoundcloud) ...[
          if (searching) SoundcloudSection(future: _soundcloud, count: 10, title: tr.songs),
          if (searching) SoundcloudShelves(future: _soundcloudShelves),
          ..._library(c, results, shell),
        ] else if (_podcasts) ...[
          if (searching) ...[
            SliverToBoxAdapter(child: SectionTitle(tr.podcastShows, compactSpacing: true)),
            CollectionGrid(future: _podcastShows, limit: 6),
            SliverToBoxAdapter(child: SectionTitle(tr.podcastEpisodes, compactSpacing: true)),
            YoutubeSongResults(future: _episodes, shown: _shownEpisodes),
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
          ..._library(c, results, shell),
          if (searching) RemoteShelves(future: _all),
          if (artists.isNotEmpty && results.isNotEmpty)
            libraryShelf(tr.yourArtists, [
              for (final a in artists)
                MediaCard(
                  track: a.cover,
                  title: a.title,
                  subtitle: tr.artist,
                  circle: true,
                  onTap: openHomeArtist(context, c, a, shell: shell),
                ),
            ]),
          if (albums.isNotEmpty)
            libraryShelf(tr.yourAlbums, [
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
      ]),
    );
    if (!widget.popup) return page;
    // The popup: the box holds still on top, only the results scroll (their panel's corners clipped), so the box and
    // anything dropping down from it never move with them.
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: _popupFill, borderRadius: LayoutPrefs.corner(10)),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: field),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: ClipRRect(borderRadius: LayoutPrefs.corner(10), child: page),
        ),
      ],
    );
  }

  /// Over the dimmed window the popup's parts float on their own, so they take the panel's solid colour.
  static Color get _popupFill =>
      AppColors.glass ? AppColors.glassSolid : Color.alphaBlend(AppColors.tile, AppColors.panel);

  /// Centered: the box on top and everything else on a panel below it, the two in a column down the page's middle.
  /// A title-bar box types into the same controller, so both stay in step.
  static List<Widget> _arrange(bool centered, bool popup, Widget box, List<Widget> slivers) {
    if (!centered) return slivers;
    final fill = popup ? _popupFill : AppColors.tile;
    return [
      SliverLayoutBuilder(
        builder: (context, constraints) {
          // The popup is that column already, its box above the scrolling part.
          final side = popup ? 0.0 : math.max(16.0, (constraints.crossAxisExtent - 880) / 2);
          return SliverPadding(
            padding: popup ? EdgeInsets.zero : EdgeInsets.fromLTRB(side, 8, side, 24),
            sliver: SliverMainAxisGroup(
              slivers: [
                if (!popup) ...[SliverToBoxAdapter(child: box), const SliverToBoxAdapter(child: SizedBox(height: 12))],
                DecoratedSliver(
                  decoration: BoxDecoration(color: fill, borderRadius: LayoutPrefs.corner(10)),
                  sliver: SliverPadding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    sliver: SliverMainAxisGroup(slivers: slivers),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ];
  }
}
