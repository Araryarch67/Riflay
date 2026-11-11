import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/device_setup.dart';
import '../services/language.dart';
import '../models/track.dart';
import '../services/download_notifications.dart';
import '../services/gate_hooks.dart';
import 'pages/youtube_music_page.dart' show likedCollection, openRemotePlaylist;
import 'widgets/track_row.dart' show openArtist;
import '../services/player_presets.dart';
import '../services/layout_prefs.dart';
import '../services/player_controller.dart';
import '../services/wrap.dart';
import 'pages/device_setup_page.dart';
import 'pages/collection_page.dart';
import 'pages/downloads_page.dart';
import 'pages/home_page.dart';
import 'pages/library_page.dart';
import 'pages/lyrics_page.dart';
import 'pages/queue_page.dart';
import 'pages/search_page.dart';
import 'pages/settings_page.dart';
import 'pages/wrap_page.dart';
import 'navigation.dart';
import 'player_panels.dart';
import 'shell_scope.dart';
import 'pages/search/soundcloud_results.dart' show SearchSourceToggle;
import 'soundcloud_pages.dart';
import 'widgets/power_settings.dart';
import 'shortcuts.dart';
import 'theme.dart';
import 'youtube_import.dart';
import '../platform/features.dart';
import '../services/incoming_links.dart';
import '../services/soundcloud.dart';
import '../services/system_tray.dart';
import '../services/youtube_importer.dart';
import '../services/youtube_links.dart';
import '../services/youtube_music_account.dart' show RemotePlaylist;
import '../services/listen_together/listen_together.dart';
import 'pages/listen_together_page.dart';
import 'shell/desktop_sidebar.dart';
import 'shell/first_frame_gate.dart';
import 'shell/phone_navigation.dart';
import 'shell/resize_handle.dart';
import 'widgets/auto_hide_bar.dart';
import 'widgets/title_bar.dart';

/// Root layout.
///  * < 700px: bottom tabs + floating mini player, full-screen now playing.
///  * 700–1200px: library rail + content + player bar; from [sidePanelFrom] the now-playing side panel fits beside
///    them too, and the full library sidebar replaces the rail wherever it fits there (`SidebarFit.fullFits`).
///  * ≥ 1200px: full library sidebar + content + now-playing side panel.
class HomeShell extends StatefulWidget {
  /// The narrowest window the now-playing side panel opens in: the rail, its minimum and the pages' minimum.
  static const sidePanelFrom = 900.0;

  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  PhoneTab _tab = PhoneTab.home;
  final _visitedTabs = <PhoneTab>{PhoneTab.home};
  bool _desktopVisited = false;
  bool _sidePanel = true;

  /// The phone's Liquid glass bar: shrinks on scroll, and carries the search field (its focus is Search's).
  final _bar = GlassBarLink();
  FocusNode get _searchFocus => _bar.search.focus;

  /// Whether the title bar is in sight over the expanded player.
  final _titleBarShown = ValueNotifier<bool>(false);

  /// Whether the player bar is in sight over the expanded player, and how tall it is.
  final _playerBarShown = ValueNotifier<bool>(false);
  final _playerBarHeight = ValueNotifier<double>(0);

  /// The title bar's search box (desktop); the phone tab has its own.
  final _search = SearchInput();
  final _navigators = {for (final t in PhoneTab.values) t: GlobalKey<NavigatorState>()};
  final _titleBarKey = GlobalKey();

  NavigatorState? get _nav => _navigators[_tab]!.currentState;

  /// Desktop: one browser-style history for the content area.
  late final _history = DesktopHistory(routeBuilder: (page, location) => _route(page, location: location));

  StreamSubscription<String>? _errors;
  StreamSubscription<String>? _listenEvents;
  PlayerController? _player;
  bool _hasTrack = false;

  @override
  void initState() {
    super.initState();
    GateHooks.attach(_gate);
    LayoutPrefs.instance.addListener(_syncWidths);
    _history.addListener(_followLocation);
    // Tapping a download notification brings up the Downloads page.
    DownloadNotifications.registerOpenDownloads(() {
      if (mounted) _open(const DownloadsPage());
    });
    // Tapping "Your <Month> in music is ready" opens that Wrap.
    DownloadNotifications.registerOpenWrap((key) {
      final month = WrapMonth.parse(key);
      if (mounted && month != null) _open(WrapPage(month: month), location: Locations.wrap);
    });
    IncomingLinks.instance.listen(_openIncoming);
    // A computer's first start: what it can take decides how much the app moves (lib/services/device_setup.dart).
    if (DeviceSetup.instance.due) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && DeviceSetup.instance.due) unawaited(showDeviceSetup(context));
      });
    }
  }

  String? _location;

  /// A page opened from the title bar (or the player bar's links) would open
  /// under the expanded player, unseen: it steps aside.
  void _followLocation() {
    if (_history.location == _location) return;
    _location = _history.location;
    _leaveExpandedPlayer();
  }

  void _leaveExpandedPlayer() {
    if (fullScreenPlayer.value) showExpandedPlayer(false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = PlayerScope.identity(context);
    if (identical(c, _player)) return;
    _player?.removeListener(_followTrack);
    _player = c..addListener(_followTrack);
    _hasTrack = c.currentTrack != null;
    _errors?.cancel();
    _errors = c.errors.listen((message) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    });
    // "Ana joined" and the like, while a Listen together session is on.
    _listenEvents?.cancel();
    _listenEvents = ListenTogether.of(c).events.listen((message) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    });
  }

  /// All the shell itself needs from the player is whether a song is loaded
  /// (for the side panel). Rebuilding it on every change the player notifies
  /// rebuilt the whole window, several times a song; whatever shows what's
  /// playing listens on its own.
  void _followTrack() {
    PowerSettings.offerOnce(context, _player!);
    final has = _player!.currentTrack != null;
    if (has != _hasTrack) setState(() => _hasTrack = has);
  }

  @override
  void dispose() {
    GateHooks.detach(_gate);
    _titleBarShown.dispose();
    _playerBarShown.dispose();
    _playerBarHeight.dispose();
    LayoutPrefs.instance.removeListener(_syncWidths);
    _sidebarWidth.dispose();
    _sidePanelWidth.dispose();
    _player?.removeListener(_followTrack);
    _history.removeListener(_followLocation);
    DownloadNotifications.registerOpenDownloads(null);
    DownloadNotifications.registerOpenWrap(null);
    IncomingLinks.instance.stopListening(_openIncoming);
    _errors?.cancel();
    _listenEvents?.cancel();
    _bar.dispose();
    _search.dispose();
    if (titleBarInShell.value) titleBarInShell.value = false;
    super.dispose();
  }

  /// Desktop: a new step in the one history. Phone: a page on the current tab.
  void _open(Widget page, {String? location}) {
    // Downloads and Settings are tabs of their own on a phone.
    final tab = !_compact
        ? null
        : (page is DownloadsPage ? PhoneTab.downloads : (page is SettingsPage ? PhoneTab.settings : null));
    if (tab != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _selectTab(tab);
      });
      return;
    }
    final where = location ?? _locationOf(page);
    if (!_compact) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _history.open(page, where));
      return;
    }
    // Root-level player/queue/sheets must step aside before a tab page opens.
    // Otherwise navigation succeeds underneath a still-visible full-screen player.
    Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
    WidgetsBinding.instance.addPostFrameCallback((_) => _nav?.push(_route(page, location: where)));
  }

  static String _locationOf(Widget page) => switch (page) {
    HomePage() => Locations.home,
    SearchPage() => Locations.search,
    SettingsPage() => Locations.settings,
    DownloadsPage() => Locations.downloads,
    ListenTogetherPage() => Locations.listen,
    LibraryPage() => Locations.library,
    CollectionPage(:final collection) => Locations.collection(collection),
    _ => page.runtimeType.toString(),
  };

  void _openSettings() {
    if (_history.location != Locations.settings) _open(const SettingsPage());
  }

  /// Profile builds: the release gate's commands (see [GateHooks]).
  Future<Object?> _gate(String command, Map<String, String> args) async {
    final c = _player!;
    switch (command) {
      case 'play':
        final want = (args['song'] ?? 'official').toLowerCase();
        final recent = c.recentlyPlayed;
        final song = recent.firstWhere((t) => t.title.toLowerCase().contains(want), orElse: () => recent.first);
        await c.playList([song], 0);
        return song.title;
      case 'playing':
        return c.isPlaying;
      case 'expanded':
        await showExpandedPlayer(args['on'] == 'true');
      case 'panel':
        final want = ExpandedPanel.values.byName(args['name']!);
        if (expandedPlayerPanel.value != want) toggleExpandedPanel(want);
      case 'lyrics':
        _openLyrics();
      case 'collection':
        final albums = c.albums.where((a) => a.tracks.length > 5);
        final col = albums.isEmpty ? c.allSongs : albums.first;
        _open(CollectionPage(collection: col), location: Locations.collection(col));
        return col.title;
      case 'wheel':
        final size = MediaQuery.sizeOf(context);
        GateHooks.wheel(Offset(size.width * 0.45, size.height * 0.5), double.parse(args['dy'] ?? '120'));
      case 'home':
        _closePhoneRoutes();
        _nav?.popUntil((r) => r.isFirst);
        _goHome();
      case 'preset':
        final want = args['name']!.toLowerCase();
        await (CustomPresets.named(want) ?? (throw ArgumentError('No preset "$want"'))).apply(LayoutPrefs.instance);
      case 'nowplaying':
        _openNowPlaying();
      case 'more':
        final host = _compact ? _nav?.context : _history.navigatorKey.currentContext;
        if (host != null) unawaited(showPlayerMore(host, openPlayer: _openNowPlaying));
      case 'playlist':
        // A Riflay playlist, else Liked music, else All Songs: a collection of real songs either way.
        final list = c.playlists.firstOrNull;
        final liked = c.ytMusic.libraryNow?.liked ?? const [];
        final col = list != null
            ? c.playlistCollection(list)
            : liked.isNotEmpty
            ? likedCollection(liked)
            : c.allSongs;
        _open(CollectionPage(collection: col), location: Locations.collection(col));
        return col.title;
      case 'artist':
        final track = c.currentTrack;
        final host = _compact ? _nav?.context : _history.navigatorKey.currentContext;
        final open = track == null || host == null ? null : openArtist(host, c, track);
        open?.call();
        return open != null;
      case 'back':
        if (_phoneRoutes.isNotEmpty) {
          Navigator.of(context).pop();
        } else if (_compact) {
          await _phoneBack();
        } else {
          _history.back();
        }
      case 'pause':
        await c.pause();
      default:
        throw ArgumentError('unknown gate command $command');
    }
    return null;
  }

  void _goHome() {
    if (_compact) return _selectTab(PhoneTab.home);
    _leaveExpandedPlayer();
    if (_history.location != Locations.home) _history.open(const HomePage(), Locations.home);
  }

  void _goSearch({bool focusInput = false}) {
    if (_compact) {
      _selectTab(PhoneTab.search);
      if (focusInput) WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
      return;
    }
    _showSearchResults();
    if (focusInput) WidgetsBinding.instance.addPostFrameCallback((_) => _search.focus.requestFocus());
  }

  /// The search page, fed by the title bar's box (opened as soon as you type).
  void _showSearchResults() {
    _leaveExpandedPlayer();
    if (_history.location == Locations.search) return;
    final typing = _search.focus.hasFocus;
    // Without a title bar (a tablet, a browser) the page has the box itself; the focus node still lets Search
    // put the cursor in it.
    _history.open(
      hasCustomTitleBar ? SearchPage(input: _search) : SearchPage(focusNode: _search.focus),
      Locations.search,
    );
    // The new page takes keyboard focus once it's built; the next keystrokes belong in the box.
    if (typing) WidgetsBinding.instance.addPostFrameCallback((_) => _search.focus.requestFocus());
  }

  /// Back / Forward, Home and search, in the desktop title bar.
  Widget _titleBar() => AppTitleBar(
    height: AppTitleBar.tallHeight,
    leading: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TitleBarMenu(
          onDownloads: () => _open(const DownloadsPage()),
          onListen: () => _open(const ListenTogetherPage(), location: Locations.listen),
          onSettings: _openSettings,
        ),
        const SizedBox(width: 4),
        HistoryButtons(history: _history),
      ],
    ),
    center: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Row(
        children: [
          ListenableBuilder(
            listenable: _history,
            builder: (context, _) {
              final home = _history.location == Locations.home;
              return IconButton.filled(
                tooltip: tr.navHome,
                onPressed: _goHome,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.tile,
                  hoverColor: AppColors.hover,
                  foregroundColor: home ? AppColors.textPrimary : AppColors.textSecondary,
                  fixedSize: const Size(48, 48),
                ),
                icon: Icon(home ? Icons.home_rounded : Icons.home_outlined, size: 26),
              );
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SearchBox(
              onBar: true,
              controller: _search.controller,
              focusNode: _search.focus,
              onChanged: (q) {
                if (q.trim().isNotEmpty) _showSearchResults();
              },
              onSubmitted: (q) {
                _showSearchResults();
                _search.submit(q);
              },
            ),
          ),
          // Where Search looks: YouTube Music or SoundCloud.
          if (Features.soundcloud) ...[const SizedBox(width: 8), const SearchSourceToggle(height: 48)],
        ],
      ),
    ),
  );

  static Route<void> _route(Widget page, {String? location, bool firstFrame = false}) => PageRouteBuilder(
    // The page rides along so Forward can rebuild it after Back.
    settings: RouteSettings(name: location, arguments: page),
    transitionDuration: LayoutPrefs.pageDuration(),
    reverseTransitionDuration: LayoutPrefs.pageDuration(reverse: true),
    // The first page of the app waits for the window's frame to be drawn, then fills in.
    pageBuilder: (_, _, _) => firstFrame ? FirstFrameGate(child: page) : page,
    transitionsBuilder: (context, anim, secondary, child) =>
        LayoutPrefs.pageTransition(context, anim, secondary, child),
  );

  void _selectTab(PhoneTab tab) {
    _lastExitBack = null;
    _searchFocus.unfocus();
    if (tab == _tab) {
      _nav?.popUntil((r) => r.isFirst);
    } else {
      setState(() {
        _visitedTabs.add(tab);
        _tab = tab;
      });
    }
  }

  Future<void> _add(Future<int> Function() pick) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final added = await pick();
      if (added > 0) {
        messenger.showSnackBar(SnackBar(content: Text(tr.addedSongsCount(added))));
      }
    } on MusicPermissionDenied {
      messenger.showSnackBar(SnackBar(content: Text(tr.allowReadMusic)));
    } on MusicFolderAlreadyAdded {
      messenger.showSnackBar(SnackBar(content: Text(tr.musicFolderAlreadyAdded)));
    } catch (e) {
      debugPrint('Adding music failed: $e');
      messenger.showSnackBar(SnackBar(content: Text(tr.couldntAddMusic)));
    }
  }

  DateTime? _lastExitBack;

  Future<void> _phoneBack() async {
    if (await _nav?.maybePop() ?? false) {
      _lastExitBack = null;
      return;
    }
    if (_tab != PhoneTab.home) {
      _lastExitBack = null;
      _selectTab(PhoneTab.home);
      return;
    }
    final now = DateTime.now();
    if (_lastExitBack != null && now.difference(_lastExitBack!) < const Duration(seconds: 2)) {
      _lastExitBack = null;
      await SystemNavigator.pop();
      return;
    }
    _lastExitBack = now;
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr.pressBackToExit), duration: Duration(seconds: 2)));
    }
  }

  bool _compact = false;
  double _contentWidth = 0;

  // The sidebars' widths while dragging: only the sized boxes listen, so a drag doesn't rebuild the shell.
  final _sidebarWidth = ValueNotifier(LayoutPrefs.instance.sidebarWidth);
  final _sidePanelWidth = ValueNotifier(LayoutPrefs.instance.sidePanelWidth);

  // What the last build knew, for the drag to clamp against.
  double _window = 0;
  bool _sideOpenNow = false;

  /// Reset layout (or a restored backup) changed the saved widths.
  void _syncWidths() {
    if (_saving) return;
    final p = LayoutPrefs.instance;
    if (_sidebarWidth.value == p.sidebarWidth && _sidePanelWidth.value == p.sidePanelWidth) return;
    _sidebarWidth.value = p.sidebarWidth;
    _sidePanelWidth.value = p.sidePanelWidth;
    if (mounted) setState(() {});
  }

  void _dragSidebar(double dx) =>
      _sidebarWidth.value = SidebarFit.left(_sidebarWidth.value + dx, _window, sideOpen: _sideOpenNow);

  /// The library sidebar's width: dragged in the expanded layout, the fixed rail when it doesn't fit.
  double _leftWidth(double window, {required bool sideOpen}) =>
      window >= 1200 || window >= HomeShell.sidePanelFrom && SidebarFit.fullFits(window, sideOpen: sideOpen)
      ? SidebarFit.left(_sidebarWidth.value, window, sideOpen: sideOpen)
      : 84.0;

  void _dragSidePanel(double dx) {
    final left = _leftWidth(_window, sideOpen: true);
    _sidePanelWidth.value = SidebarFit.right(_sidePanelWidth.value - dx, _window, left: left);
  }

  /// Drag over (or reset): save once, and let the pages learn their new width.
  void _saveWidths() {
    _saving = true;
    unawaited(LayoutPrefs.instance.setSidebarWidth(_sidebarWidth.value));
    unawaited(LayoutPrefs.instance.setSidePanelWidth(_sidePanelWidth.value));
    _saving = false;
    if (mounted) setState(() {});
  }

  bool _saving = false;

  /// Wraps [child] with layout facts + actions. Root-level routes (now playing,
  /// phone queue) need their own copy since they sit outside the shell tree.
  Widget _scoped(Widget child) {
    final c = PlayerScope.read(context);
    return ShellScope(
      compact: _compact,
      width: _contentWidth,
      history: _compact ? null : _history,
      open: _open,
      openCollection: (Collection col) => _open(CollectionPage(collection: col), location: Locations.collection(col)),
      openQueue: _openQueue,
      openNowPlaying: _openNowPlaying,
      openLyrics: _openLyrics,
      openDownloads: () => _open(const DownloadsPage()),
      importFromYoutube: _importFromYoutube,
      addFiles: () => _add(c.pickFiles),
      addFolder: c.canScanFolders ? () => _add(c.pickFolder) : null,
      child: child,
    );
  }

  Future<void> _importFromYoutube({String? url}) async {
    final messenger = ScaffoldMessenger.of(context);
    final queued = await showYoutubeImport(context, compact: _compact, initialUrl: url);
    if (!queued || !mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(tr.downloadingAudio),
        action: SnackBarAction(label: tr.view, onPressed: () => _open(const DownloadsPage())),
      ),
    );
  }

  /// A YouTube link opened with Riflay or shared to it (lib/services/incoming_links.dart): a song or video
  /// plays (phones show it playing), a playlist or album opens.
  Future<void> _openIncoming(String text) async {
    if (!mounted) return;
    unawaited(SystemTray.bringToFront());
    final messenger = ScaffoldMessenger.of(context);
    final c = PlayerScope.read(context);
    final link = IncomingLinks.read(text);
    // Phones: the full-screen player would cover the page or message the link brings.
    if (link is! VideoLink && _phoneRoutes.isNotEmpty) _closePhoneRoutes();
    if (link == null) {
      if (IncomingLinks.readSoundcloud(text) case final soundcloud?) return _openSoundcloud(c, soundcloud);
      messenger.showSnackBar(SnackBar(content: Text(Features.soundcloud ? tr.linkNotSupported : tr.linkNotYoutube)));
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(tr.linkOpening)));
    try {
      switch (link) {
        case VideoLink(:final videoId, :final startAt):
          final track = await _incomingSong(c, videoId);
          if (!mounted) return;
          messenger.hideCurrentSnackBar();
          await c.playList([track], 0);
          if (startAt != null) await c.seek(startAt);
          if (mounted && _compact && _phoneRoutes.isEmpty) _openNowPlaying();
        case PlaylistLink(:final playlistId):
          // The page shows the title it is given; a mix or private list may have none to read.
          final title = await c.youtube.client.playlists
              .get(playlistId)
              .then((p) => p.title, onError: (Object _) => tr.playlist);
          if (!mounted) return;
          messenger.hideCurrentSnackBar();
          _openRemote(RemotePlaylist(id: playlistId, title: title, count: 0));
        case AlbumLink(:final browseId):
          messenger.hideCurrentSnackBar();
          _openRemote(RemotePlaylist(id: browseId, browseId: browseId, title: tr.album, count: 0));
      }
    } catch (e) {
      debugPrint('Opening $link failed: $e');
      if (!mounted) return;
      if (_phoneRoutes.isNotEmpty) _closePhoneRoutes();
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(tr.linkFailed)));
    }
  }

  /// A SoundCloud link: a track plays, a playlist or profile opens as a page.
  Future<void> _openSoundcloud(PlayerController c, SoundcloudLink link) async {
    final messenger = ScaffoldMessenger.of(context);
    if (_phoneRoutes.isNotEmpty && !link.isTrack) _closePhoneRoutes();
    messenger.showSnackBar(SnackBar(content: Text(tr.linkOpening)));
    try {
      final page = await c.soundcloud.resolve(link);
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      if (page.kind == SoundcloudKind.track) {
        await c.playList(page.tracks, 0);
        if (mounted && _compact && _phoneRoutes.isEmpty) _openNowPlaying();
      } else {
        openSoundcloud(
          context,
          kind: page.kind,
          id: page.id,
          title: page.title,
          shell: _scoped(const SizedBox.shrink()) as ShellScope,
        );
      }
    } catch (e) {
      debugPrint('Opening $link failed: $e');
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(e is SoundcloudUnplayable ? tr.soundcloudUnplayable : tr.linkFailed)),
      );
    }
  }

  /// YouTube Music's own title and artist when it has the song; otherwise read from the video's title
  /// ("Artist - Song", as downloads are named).
  Future<Track> _incomingSong(PlayerController c, String videoId) async {
    try {
      if (await c.ytMusic.song(videoId).timeout(const Duration(seconds: 8)) case final song?) return song;
    } catch (e) {
      debugPrint('YouTube Music has no song $videoId: $e');
    }
    final video = await c.youtube.client.videos.get(videoId);
    final names = YoutubeImporter.parseTitle(video.title, video.author);
    return Track.youtube(
      videoId: videoId,
      title: names.title,
      artist: names.artist,
      duration: video.duration,
      artworkUrl: video.thumbnails.highResUrl,
    );
  }

  void _openRemote(RemotePlaylist p) =>
      openRemotePlaylist(context, p, shell: _scoped(const SizedBox.shrink()) as ShellScope);

  /// Ctrl/Cmd+V anywhere outside a text field: a copied YouTube link opens the importer.
  Future<void> _pasteLink() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (text != null && IncomingLinks.isLink(text)) await _importFromYoutube(url: text);
  }

  /// Full-screen routes of the phone layout (now playing, queue, lyrics).
  /// They're built for a phone, so they close when the window becomes wide.
  final _phoneRoutes = <Route<void>>[];

  void _pushPhoneRoute(Route<void> route) {
    _phoneRoutes.add(route);
    Navigator.of(context).push(route).whenComplete(() => _phoneRoutes.remove(route));
  }

  void _closePhoneRoutes() {
    final nav = Navigator.of(context);
    for (final r in [..._phoneRoutes]) {
      if (r.isActive) nav.removeRoute(r);
    }
    _phoneRoutes.clear();
    if (mounted) setState(() {});
  }

  void _openQueue() {
    if (!_compact) return _open(const QueuePage());
    _pushPhoneRoute(MaterialPageRoute(builder: (_) => _scoped(const Scaffold(body: QueuePage()))));
  }

  void _openLyrics() {
    if (!_compact) return _open(const LyricsPage());
    _pushPhoneRoute(MaterialPageRoute(builder: (_) => _scoped(const LyricsPage(fullScreen: true))));
  }

  void _openNowPlaying() {
    _pushPhoneRoute(
      PageRouteBuilder(
        settings: const RouteSettings(name: nowPlayingRouteName),
        transitionDuration: LayoutPrefs.pageDuration(player: true),
        reverseTransitionDuration: LayoutPrefs.pageDuration(reverse: true, player: true),
        pageBuilder: (_, _, _) => _scoped(const NowPlayingPage()),
        transitionsBuilder: (context, anim, secondary, child) =>
            LayoutPrefs.pageTransition(context, anim, secondary, child, player: true),
      ),
    );
  }

  Widget _desktopNavigator() => Navigator(
    key: _history.navigatorKey,
    observers: [_history.observer],
    onGenerateRoute: (_) => _route(const HomePage(), location: Locations.home, firstFrame: true),
  );

  Widget _tabNavigator(PhoneTab tab) => Navigator(
    key: _navigators[tab],
    onGenerateRoute: (_) => _route(switch (tab) {
      PhoneTab.home => const HomePage(),
      PhoneTab.search => SearchPage(focusNode: _searchFocus, input: _bar.search, boxInBar: _bar.searchInBar),
      PhoneTab.library => const LibraryPage(),
      PhoneTab.downloads => const DownloadsPage(),
      PhoneTab.settings => const SettingsPage(),
    }),
  );

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    final size = MediaQuery.sizeOf(context);
    final width = size.width;
    // A phone keeps its layout when turned sideways (it's still held in the
    // hand); tablets and desktop windows switch by width.
    final mobile = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
    final phone = mobile && size.shortestSide < 600;
    // Stay in the phone layout for the one frame it takes to close its full-screen pages.
    final compact = width < 700 || phone || _phoneRoutes.isNotEmpty;
    if (!compact) _desktopVisited = true;
    if (width >= 700 && !phone && _phoneRoutes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _closePhoneRoutes());
    }
    final sideRoom = width >= HomeShell.sidePanelFrom;
    // The full (resizable) library sidebar whenever it fits at its narrowest beside the pages and an open side
    // panel; the rail only when it doesn't.
    final expanded = width >= 1200 || sideRoom && SidebarFit.fullFits(width, sideOpen: _sidePanel && _hasTrack);

    _compact = compact;
    // The frame's plain title bar steps aside while this layout draws the full one.
    final ownBar = !compact && hasCustomTitleBar;
    if (titleBarInShell.value != ownBar) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) titleBarInShell.value = ownBar;
      });
    }

    final shortcuts = {
      ...bindShortcuts({
        AppAction.playPause: c.togglePlay,
        AppAction.next: c.next,
        AppAction.previous: c.previous,
        AppAction.volumeUp: () => c.nudgeVolume(0.05),
        AppAction.volumeDown: () => c.nudgeVolume(-0.05),
        AppAction.search: () => _goSearch(focusInput: true),
        AppAction.back: _history.back,
        AppAction.forward: _history.forward,
        AppAction.pasteLink: _pasteLink,
        // From the expanded player too: on to full screen.
        AppAction.fullScreen: () => setFullScreenPlayer(!windowFullScreen.value),
        if (hasKeyboardShortcuts) AppAction.help: () => showShortcutsDialog(context),
      }, compact: compact),
      if (!compact) const SingleActivator(LogicalKeyboardKey.escape): () => setFullScreenPlayer(false),
    };

    // Phone only: one stack per bottom tab, fading between tabs. The hidden
    // tabs' tickers are off: no animation runs there (a playing song's bars in
    // a list nobody sees kept the screen redrawing), and they catch up on what
    // changed when shown.
    Widget tabs() => _FadeOnChange(
      index: _tab.index,
      child: IndexedStack(
        index: _tab.index,
        children: [
          for (final t in PhoneTab.values)
            TickerMode(
              enabled: t == _tab,
              // Unopened tabs used to build their pages, listeners and network requests on every phone start.
              // Once visited, keep their navigator alive so returning preserves its history and scroll position.
              child: _visitedTabs.contains(t) ? _tabNavigator(t) : const SizedBox.shrink(),
            ),
        ],
      ),
    );

    Widget body;
    if (compact) {
      // Sideways the tabs move to a rail on the left, leaving the height to the pages.
      final sideways = width > size.height && size.height < 500;
      final insets = MediaQuery.paddingOf(context);
      _contentWidth = sideways ? width - PhoneSideTabs.width - insets.left - insets.right : width;
      // The desktop history stays alive (hidden) while the window is narrow,
      // so widening it again returns to the same page.
      // Every page's scrolling reaches the Liquid glass bar from here.
      final pages = NotificationListener<ScrollNotification>(
        onNotification: _bar.onScroll,
        child: Stack(
          children: [
            Positioned.fill(child: tabs()),
            // Full size even while hidden: laid out at width 0 its pages would break.
            if (_desktopVisited)
              Positioned.fill(
                child: Offstage(child: TickerMode(enabled: false, child: _desktopNavigator())),
              ),
          ],
        ),
      );
      body = _scoped(
        Scaffold(
          // Pages scroll on under the see-through tab bar; they pad their ends by its height.
          extendBody: true,
          body: sideways
              ? Row(
                  children: [
                    PhoneSideTabs(tab: _tab, onSelect: _selectTab),
                    Expanded(
                      // The rail took the left inset; a camera cutout on the right stays clear.
                      child: SafeArea(
                        left: false,
                        top: false,
                        bottom: false,
                        child: MediaQuery.removePadding(context: context, removeLeft: true, child: pages),
                      ),
                    ),
                  ],
                )
              : pages,
          bottomNavigationBar: PhoneBottomBar(
            onOpenPlayer: _openNowPlaying,
            link: _bar,
            tab: _tab,
            onSelect: _selectTab,
            showTabs: !sideways,
          ),
        ),
      );
    } else {
      final sideOpen = sideRoom && _sidePanel && _hasTrack;
      _window = width;
      _sideOpenNow = sideOpen;
      // The rail at narrow widths is fixed; the dragged widths apply to the expanded layout only.
      final sidebarWidth = expanded ? SidebarFit.left(_sidebarWidth.value, width, sideOpen: sideOpen) : 84.0;
      final panelWidth = SidebarFit.right(_sidePanelWidth.value, width, left: sidebarWidth);
      _contentWidth = width - sidebarWidth - (sideOpen ? panelWidth + 8 : 0) - 24;
      // Expanded: the cover takes the whole window and both bars slide away until the pointer comes to them.
      // The pages stay alive (and their history) underneath.
      final pages = Padding(
        padding: EdgeInsets.fromLTRB(8, hasCustomTitleBar ? 0 : 8, 8, 0),
        child: Row(
          children: [
            ValueListenableBuilder(
              valueListenable: _sidebarWidth,
              builder: (context, want, sidebar) => SizedBox(
                width: expanded ? SidebarFit.left(want, width, sideOpen: sideOpen) : sidebarWidth,
                child: sidebar,
              ),
              child: ListenableBuilder(
                listenable: _history,
                builder: (context, _) => DesktopSidebar(
                  collapsed: !expanded,
                  location: _history.location,
                  onHome: _goHome,
                  onSearch: _goSearch,
                  // Home and search sit in the title bar instead.
                  inTitleBar: hasCustomTitleBar,
                ),
              ),
            ),
            expanded
                ? ResizeHandle(
                    label: tr.resizeSidebar,
                    onDrag: _dragSidebar,
                    onEnd: _saveWidths,
                    onReset: () {
                      _sidebarWidth.value = SidebarFit.left(LayoutPrefs.sidebarDefault, width, sideOpen: sideOpen);
                      _saveWidths();
                    },
                  )
                : const SizedBox(width: 8),
            Expanded(child: ShellPanel(child: _desktopNavigator())),
            if (sideRoom)
              // The sidebar listens too: widening it takes the room from this panel.
              ListenableBuilder(
                listenable: Listenable.merge([_sidePanelWidth, _sidebarWidth]),
                builder: (context, panel) => SlidingPanel(
                  open: sideOpen,
                  width: SidebarFit.right(_sidePanelWidth.value, width, left: _leftWidth(width, sideOpen: sideOpen)),
                  handle: ResizeHandle(
                    label: tr.resizeSidePanel,
                    onDrag: _dragSidePanel,
                    onEnd: _saveWidths,
                    onReset: () {
                      _sidePanelWidth.value = SidebarFit.right(
                        LayoutPrefs.sidePanelDefault,
                        width,
                        left: _leftWidth(width, sideOpen: true),
                      );
                      _saveWidths();
                    },
                  ),
                  child: panel!,
                ),
                child: ShellPanel(child: NowPlayingSidePanel(onClose: () => setState(() => _sidePanel = false))),
              ),
          ],
        ),
      );
      body = _scoped(
        ValueListenableBuilder(
          valueListenable: fullScreenPlayer,
          builder: (context, full, pages) {
            // Keyed: it moves between the column and the overlay without losing what's typed in it.
            final titleBar = AutoHideBar(
              key: _titleBarKey,
              edge: AxisDirection.up,
              enabled: full,
              shown: _titleBarShown,
              // Over the player it brings the window's colour with it, as it has above the pages. Always there
              // (clear above the pages), so the bar keeps its state, such as what is typed, between the two.
              child: ColoredBox(color: full ? AppColors.background : Colors.transparent, child: _titleBar()),
            );
            return Scaffold(
              extendBody: full,
              // In the bottom slot so floating snackbars stack above the player instead of covering it.
              bottomNavigationBar: AutoHideBar(
                edge: AxisDirection.down,
                enabled: full,
                shown: _playerBarShown,
                child: _ReportHeight(
                  height: _playerBarHeight,
                  child: SafeArea(
                    top: false,
                    child: DesktopPlayerBar(
                      sidePanelOpen: sideOpen,
                      onToggleSidePanel: sideRoom ? () => setState(() => _sidePanel = !_sidePanel) : null,
                    ),
                  ),
                ),
              ),
              body: SafeArea(
                bottom: false,
                child: Stack(
                  children: [
                    Column(
                      children: [
                        if (hasCustomTitleBar && !full) titleBar,
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(
                                // Under Now Playing nothing on the pages moves: their seek bar, visualizer and
                                // marquees would keep the window drawing for a screen no one sees.
                                child: Offstage(
                                  offstage: full,
                                  child: pages == null ? null : TickerMode(enabled: !full, child: pages),
                                ),
                              ),
                              if (full)
                                Positioned.fill(
                                  // Both bars float over the player and slide away: its picture always fills
                                  // the window, and its content makes room for a bar only while it is in sight.
                                  child: ListenableBuilder(
                                    listenable: Listenable.merge([_titleBarShown, _playerBarShown, _playerBarHeight]),
                                    builder: (context, player) => _Insets(
                                      top: hasCustomTitleBar && _titleBarShown.value ? AppTitleBar.tallHeight : 0,
                                      topShown: _titleBarShown.value,
                                      bottom: _playerBarShown.value ? _playerBarHeight.value : 0,
                                      bottomShown: _playerBarShown.value,
                                      child: player!,
                                    ),
                                    child: const FullScreenPlayer(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (hasCustomTitleBar && full) Positioned(top: 0, left: 0, right: 0, child: titleBar),
                  ],
                ),
              ),
            );
          },
          child: pages,
        ),
      );
    }

    if (_compact) {
      body = PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(_phoneBack());
        },
        child: body,
      );
    }

    return Listener(
      // Mouse side buttons step through the history, as in a browser.
      onPointerDown: (e) {
        if (_compact) return;
        if (e.buttons & kBackMouseButton != 0) _history.back();
        if (e.buttons & kForwardMouseButton != 0) _history.forward();
      },
      // A scope, so focus leaving the title bar's search box lands here (where Space plays) and not above.
      child: FocusScope(autofocus: true, onKeyEvent: (node, event) => _handleShortcut(event, shortcuts), child: body),
    );
  }

  /// App-wide shortcuts, except while typing: Space, Ctrl+V etc. must reach text fields.
  /// (A CallbackShortcuts here would sit between a TextField and the app's
  /// default text-editing shortcuts and swallow them.)
  KeyEventResult _handleShortcut(KeyEvent event, Map<ShortcutActivator, VoidCallback> shortcuts) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final focused = FocusManager.instance.primaryFocus?.context;
    final typing =
        focused != null &&
        (focused.widget is EditableText || focused.findAncestorWidgetOfExactType<EditableText>() != null);
    if (typing) return KeyEventResult.ignored;
    for (final entry in shortcuts.entries) {
      if (entry.key.accepts(event, HardwareKeyboard.instance)) {
        entry.value();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }
}

/// Fades the tab content in when switching tabs (the stack keeps each tab's state).
class _FadeOnChange extends StatefulWidget {
  const _FadeOnChange({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_FadeOnChange> createState() => _FadeOnChangeState();
}

class _FadeOnChangeState extends State<_FadeOnChange> with SingleTickerProviderStateMixin {
  late final _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 220), value: 1);

  @override
  void didUpdateWidget(_FadeOnChange old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _fade.duration = LayoutPrefs.pageDuration();
      if (LayoutPrefs.effectiveMotion == Motion.off) {
        _fade.value = 1;
      } else {
        _fade.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (LayoutPrefs.effectiveMotion == Motion.off) return widget.child;
    if (LayoutPrefs.instance.pageMotion == PageMotionStyle.classic) {
      return FadeTransition(
        opacity: _fade.drive(CurveTween(curve: Curves.easeOut)),
        child: widget.child,
      );
    }
    return LayoutPrefs.pageTransition(context, _fade, const AlwaysStoppedAnimation(0), widget.child);
  }
}

/// The expanded player's room for the bars that slide in over it: [top] and [bottom] follow each bar as it
/// slides, with the same timing.
class _Insets extends StatelessWidget {
  const _Insets({
    required this.top,
    required this.topShown,
    required this.bottom,
    required this.bottomShown,
    required this.child,
  });

  final double top, bottom;
  final bool topShown, bottomShown;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: top),
    duration: topShown ? AutoHideBar.slideIn : AutoHideBar.slideOut,
    curve: topShown ? Curves.easeOutCubic : Curves.easeInCubic,
    builder: (context, top, child) => TweenAnimationBuilder<double>(
      tween: Tween(end: bottom),
      duration: bottomShown ? AutoHideBar.slideIn : AutoHideBar.slideOut,
      curve: bottomShown ? Curves.easeOutCubic : Curves.easeInCubic,
      builder: (context, bottom, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            padding: media.padding.copyWith(top: media.padding.top + top, bottom: bottom),
          ),
          child: child!,
        );
      },
      child: child,
    ),
    child: child,
  );
}

/// [child], telling [height] how tall it is after each layout.
class _ReportHeight extends StatefulWidget {
  const _ReportHeight({required this.height, required this.child});

  final ValueNotifier<double> height;
  final Widget child;

  @override
  State<_ReportHeight> createState() => _ReportHeightState();
}

class _ReportHeightState extends State<_ReportHeight> {
  void _report() {
    final h = context.size?.height;
    if (mounted && h != null && h != widget.height.value) widget.height.value = h;
  }

  @override
  Widget build(BuildContext context) => NotificationListener<SizeChangedLayoutNotification>(
    onNotification: (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _report());
      return false;
    },
    child: SizeChangedLayoutNotifier(
      child: Builder(
        builder: (context) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _report());
          return widget.child;
        },
      ),
    ),
  );
}
