import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/media_session/media_session_service.dart';
import '../services/device_setup.dart';
import '../services/language.dart';
import '../models/track.dart';
import '../services/download_notifications.dart';
import 'widgets/glass_toast.dart';
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
import 'widgets/controls.dart' show AccentBuilder;
import 'widgets/live_preview.dart';
import 'shell_scope.dart';
import 'soundcloud_pages.dart';
import 'widgets/power_settings.dart';
import 'shortcuts.dart';
import 'theme.dart';
import 'youtube_import.dart';
import 'folder_add_dialog.dart';
import '../platform/features.dart';
import '../services/incoming_links.dart';
import '../services/source_verification.dart';
import 'pages/spotiflac_verification_page.dart';
import '../services/monochrome.dart';
import 'pages/monochrome_page.dart';
import '../services/soundcloud.dart';
import '../services/system_tray.dart';
import '../services/youtube_importer.dart';
import '../services/youtube_links.dart';
import '../services/youtube_music_account.dart' show RemotePlaylist;
import '../services/connect/connect_host.dart';
import '../services/listen_together/listen_together.dart';
import 'pages/listen_together_page.dart';
import 'shell/desktop_sidebar.dart';
import 'shell/first_frame_gate.dart';
import 'shell/phone_navigation.dart';
import 'shell/resize_handle.dart';
import 'widgets/auto_hide_bar.dart';
import 'widgets/over_video.dart';
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

class _HomeShellState extends State<HomeShell> with SingleTickerProviderStateMixin {
  PhoneTab _tab = PhoneTab.home;
  final _visitedTabs = <PhoneTab>{PhoneTab.home};
  bool _desktopVisited = false;
  bool _sidePanel = true;

  /// The phone's Liquid glass bar: shrinks on scroll, and carries the search field (its focus is Search's).
  final _bar = GlassBarLink();
  final _phonePlayerArea = GlobalKey();
  final _miniPlayerAnchor = GlobalKey();
  late final _playerExpansion = AnimationController(vsync: this);
  Rect? _playerDragOrigin;
  FocusNode get _searchFocus => _bar.search.focus;

  /// Whether the title bar is in sight over the expanded player.
  final _titleBarShown = ValueNotifier<bool>(false);

  /// Whether the player bar is in sight over the expanded player, and how tall it is.
  final _playerBarShown = ValueNotifier<bool>(false);
  final _playerBarHeight = ValueNotifier<double>(0);

  /// The title bar's search box (desktop); the phone tab has its own.
  final _search = SearchInput();

  /// Settings › Centered search: Search opens over the page (its own focus: a Search page left in the history keeps
  /// the title bar's).
  final _popupFocus = FocusNode(debugLabel: 'search popup');
  BuildContext? _popupContext;
  final _navigators = {for (final t in PhoneTab.values) t: GlobalKey<NavigatorState>()};
  final _titleBarKey = GlobalKey();

  NavigatorState? get _nav => _navigators[_tab]!.currentState;

  /// Desktop: one browser-style history for the content area.
  late final _history = DesktopHistory(routeBuilder: (page, location) => _route(page, location: location));

  StreamSubscription<String>? _errors;
  StreamSubscription<String>? _listenEvents;
  PlayerController? _player;
  SourceVerificationQueue? _sourceVerification;
  bool _hasTrack = false;

  @override
  void initState() {
    super.initState();
    final initial = PhoneTab.values.asNameMap()[LayoutPrefs.instance.startupTab];
    if (initial != null && initial.available) _tab = initial;
    GateHooks.attach(_gate);
    LayoutPrefs.instance.addListener(_syncWidths);
    _history.addListener(_followLocation);
    // Tapping a download notification brings up the Downloads page.
    DownloadNotifications.registerOpenDownloads(() {
      if (mounted) _open(const DownloadsPage());
    });
    DownloadNotifications.registerInAppDownloadToast((note) {
      if (!mounted || WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return false;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return false;
      messenger.showSnackBar(
        LinkedToast(
          note.title,
          label: tr.navDownloads,
          open: () {
            if (mounted) _open(const DownloadsPage());
          },
        ),
      );
      return true;
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
    final wasLibrary = _location == Locations.library;
    _location = _history.location;
    if (!_compact && mounted && wasLibrary != (_location == Locations.library)) setState(() {});
    _player?.setBrowsingLocation(_location);
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
    _sourceVerification?.dispose();
    _player = c..addListener(_followTrack);
    _player?.setBrowsingLocation(_location ?? _history.location);
    _sourceVerification = SourceVerificationQueue(
      c.youtube,
      verify: (job, provider) async {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return false;
        return showSpotiflacVerification(context, job.extensionTrack!, provider: provider);
      },
    );
    _hasTrack = c.currentTrack != null;
    _errors?.cancel();
    _errors = c.errors.listen((message) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    });
    // "Ana joined" and the like, while a Listen together session is on.
    // A desktop that left remote control on starts listening again (nothing else about playback changes).
    if (Features.connectHost) unawaited(ConnectHost.of(c).load());
    _listenEvents?.cancel();
    _listenEvents = ListenTogether.of(c).events.listen((message) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    });
  }

  /// All the shell needs from the player is whether a song is loaded (for the side panel): rebuilding on every
  /// change the player notifies would rebuild the whole window several times a song.
  void _followTrack() {
    PowerSettings.offerOnce(context, _player!);
    final has = _player!.currentTrack != null;
    if (has != _hasTrack) setState(() => _hasTrack = has);
  }

  @override
  void dispose() {
    _popupFocus.dispose();
    GateHooks.detach(_gate);
    _sourceVerification?.dispose();
    _titleBarShown.dispose();
    _playerBarShown.dispose();
    _playerBarHeight.dispose();
    LayoutPrefs.instance.removeListener(_syncWidths);
    _sidebarWidth.dispose();
    _sidePanelWidth.dispose();
    _player?.removeListener(_followTrack);
    _history.removeListener(_followLocation);
    DownloadNotifications.registerOpenDownloads(null);
    DownloadNotifications.registerInAppDownloadToast(null);
    DownloadNotifications.registerOpenWrap(null);
    IncomingLinks.instance.stopListening(_openIncoming);
    _errors?.cancel();
    _listenEvents?.cancel();
    _bar.dispose();
    _playerExpansion.dispose();
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
    LyricsPage() => Locations.lyrics,
    QueuePage() => Locations.queue,
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
    if (_centeredSearch) return unawaited(_openSearchPopup());
    _showSearchResults();
    if (focusInput) WidgetsBinding.instance.addPostFrameCallback((_) => _search.focus.requestFocus());
  }

  /// Search over the page: the box on top, the results on a panel under it, the page dimmed behind. A click
  /// outside or Esc closes it, and so does going to a page from its results.
  Future<void> _openSearchPopup() async {
    if (_popupContext case final open? when open.mounted) {
      _popupFocus.requestFocus();
      return;
    }
    _leaveExpandedPlayer();
    WidgetsBinding.instance.addPostFrameCallback((_) => _popupFocus.requestFocus());
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: tr.navSearch,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: LayoutPrefs.dur(const Duration(milliseconds: 200)),
      pageBuilder: (dialog, _, _) {
        _popupContext = dialog;
        return _scoped(SearchPopup(input: _search, focusNode: _popupFocus));
      },
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, -0.02), end: Offset.zero).animate(curved),
            child: child,
          ),
        );
      },
    );
    _popupContext = null;
  }

  /// Closes the search popup (and any menu over it) before a page opens under it.
  void _closeSearchPopup() {
    final popup = _popupContext;
    if (popup == null || !popup.mounted) return;
    _popupContext = null;
    Navigator.of(popup).popUntil((route) => route.isFirst);
  }

  /// The search page, fed by the title bar's box (opened as soon as you type).
  void _showSearchResults() {
    if (_centeredSearch && !_compact) return unawaited(_openSearchPopup());
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
    height: _fullHeightRail ? AppTitleBar.railHeight : AppTitleBar.tallHeight,
    pillControls: _fullHeightRail,
    leading: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The rail holds Downloads, Listen together and Settings.
        if (!_fullHeightRail) ...[
          TitleBarMenu(
            onDownloads: () => _open(const DownloadsPage()),
            onListen: () => _open(const ListenTogetherPage(), location: Locations.listen),
            onSettings: _openSettings,
          ),
          const SizedBox(width: 4),
        ],
        HistoryButtons(history: _history),
      ],
    ),
    // Centered search draws its own box on the page; the rail has Home.
    center: _centeredSearch ? null : _titleBarSearch(),
  );

  Widget _titleBarSearch() => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 560),
    child: Row(
      children: [
        if (!_fullHeightRail) ...[
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
        ],
        Expanded(
          child: SearchBox(
            onBar: true,
            controller: _search.controller,
            focusNode: _search.focus,
            onSourceSelected: _search.selectSource,
            onChanged: (q) {
              if (q.trim().isNotEmpty) _showSearchResults();
            },
            onSubmitted: (q) {
              _showSearchResults();
              _search.submit(q);
            },
          ),
        ),
      ],
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
      _player?.setBrowsingLocation(tab.name);
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

  /// Picks a music folder, then asks whether it is only added or added as a playlist that follows it.
  Future<void> _addFolder() => _add(() async {
    final c = PlayerScope.read(context);
    final dir = await c.chooseFolder();
    if (dir == null || !mounted) return 0;
    final choice = await askFolderAddChoice(context, dir);
    if (choice == null) return 0;
    return c.scanFolder(dir, asPlaylist: choice == FolderAddChoice.asPlaylist);
  });

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
  DesktopSidebarStyle _sidebarStyle = LayoutPrefs.instance.desktopSidebarStyle;
  bool _fullHeightRailPref = LayoutPrefs.instance.fullHeightRail;
  bool _centeredSearch = LayoutPrefs.instance.centeredSearch;

  // What the last build knew, for the drag to clamp against.
  double _window = 0;
  bool _sideOpenNow = false;

  /// Apply sidebar preferences when settings change or a backup is restored.
  void _syncWidths() {
    if (_saving) return;
    final p = LayoutPrefs.instance;
    if (_sidebarWidth.value == p.sidebarWidth &&
        _sidePanelWidth.value == p.sidePanelWidth &&
        _sidebarStyle == p.desktopSidebarStyle &&
        _fullHeightRailPref == p.fullHeightRail &&
        _centeredSearch == p.centeredSearch) {
      return;
    }
    _sidebarStyle = p.desktopSidebarStyle;
    _fullHeightRailPref = p.fullHeightRail;
    _centeredSearch = p.centeredSearch;
    _sidebarWidth.value = p.sidebarWidth;
    _sidePanelWidth.value = p.sidePanelWidth;
    if (mounted) setState(() {});
  }

  void _dragSidebar(double dx) =>
      _sidebarWidth.value = SidebarFit.left(_sidebarWidth.value + dx, _window, sideOpen: _sideOpenNow);

  /// The library sidebar's width: dragged in the expanded layout, the fixed rail when it doesn't fit.
  double _leftWidth(double window, {required bool sideOpen}) => _fullHeightRail
      ? 0
      : !_shortcutRail &&
            (window >= 1200 || window >= HomeShell.sidePanelFrom && SidebarFit.fullFits(window, sideOpen: sideOpen))
      ? SidebarFit.left(_sidebarWidth.value, window, sideOpen: sideOpen)
      : _shortcutRail
      ? ShortcutRail.width
      : 84.0;

  bool get _shortcutRail => _sidebarStyle == DesktopSidebarStyle.shortcuts;

  /// Settings › Full-height rail: the shortcut rail outside the pages, from the window's top to its foot.
  bool get _fullHeightRail => _shortcutRail && _fullHeightRailPref;

  void _dragSidePanel(double dx) {
    final left = _history.location == Locations.library ? 0.0 : _leftWidth(_window, sideOpen: true);
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
      // Each closes the search popup first, when it is open, so the page isn't opened under it.
      open: (page, {location}) {
        _closeSearchPopup();
        _open(page, location: location);
      },
      openCollection: (Collection col) {
        _closeSearchPopup();
        _open(CollectionPage(collection: col), location: Locations.collection(col));
      },
      openQueue: () {
        _closeSearchPopup();
        _openQueue();
      },
      openNowPlaying: () {
        _closeSearchPopup();
        _openNowPlaying();
      },
      openLyrics: () {
        _closeSearchPopup();
        _openLyrics();
      },
      openDownloads: () {
        _closeSearchPopup();
        _open(const DownloadsPage());
      },
      importFromYoutube: _importFromYoutube,
      addFiles: () => _add(c.pickFiles),
      addFolder: c.canScanFolders ? _addFolder : null,
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
      if (MonochromeLink.parse(text) case final monochrome?) {
        if (monochrome.kind != 'track') {
          _openMonochrome(monochrome);
          return;
        }
        messenger.showSnackBar(SnackBar(content: Text(tr.linkOpening)));
        try {
          final page = await Monochrome.instance.resolve(monochrome);
          if (!mounted) return;
          messenger.hideCurrentSnackBar();
          await c.playList(page.tracks, 0, from: 'Monochrome');
          if (mounted && _compact && _phoneRoutes.isEmpty) _openNowPlaying();
        } catch (e) {
          debugPrint('Monochrome link: $e');
          if (mounted) {
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(SnackBar(content: Text(tr.sourceUnavailable('Monochrome'))));
          }
        }
        return;
      }
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

  void _openMonochrome(MonochromeLink link) =>
      (_scoped(const SizedBox.shrink()) as ShellScope).open(MonochromePage(link: link));

  /// Ctrl/Cmd+V anywhere outside a text field: a copied YouTube link opens the importer.
  Future<void> _pasteLink() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (text != null && IncomingLinks.isLink(text)) {
      if (MonochromeLink.parse(text) != null) {
        await _openIncoming(text);
      } else {
        await _importFromYoutube(url: text);
      }
    }
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

  void _updatePlayerExpansion(Rect origin, double distance) {
    if (!_compact || _phoneRoutes.isNotEmpty || _playerExpansion.isAnimating) return;
    final box = _phonePlayerArea.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    if (_playerDragOrigin == null) {
      final local = box.globalToLocal(origin.topLeft) & origin.size;
      setState(() => _playerDragOrigin = local);
    }
    final top = _playerDragOrigin!.top;
    if (top > 0) _playerExpansion.value = (distance / top).clamp(0, 1);
  }

  void _finishPlayerExpansion(double velocity, {required bool cancelled}) {
    if (_playerDragOrigin == null || _playerExpansion.isAnimating) return;
    final progress = _playerExpansion.value;
    final open = !cancelled && velocity < 520 && (progress >= 0.24 || (progress > 0.035 && velocity < -680));
    final goal = open ? 1.0 : 0.0;
    final settle = LayoutPrefs.dur(Duration(milliseconds: (160 + 160 * (goal - progress).abs()).round()));
    _playerExpansion.animateTo(goal, duration: settle, curve: Curves.easeOutCubic).whenComplete(() {
      if (!mounted) return;
      setState(() => _playerDragOrigin = null);
      _playerExpansion.value = 0;
      if (open && _compact && _phoneRoutes.isEmpty && _player?.currentTrack != null) {
        _openNowPlaying(expanded: true);
      }
    });
  }

  Widget _phonePlayerPreview(Rect origin) => Positioned.fill(
    child: IgnorePointer(
      child: ExcludeSemantics(
        child: AccentBuilder(
          track: _player?.currentTrack,
          builder: (context, accent) => LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              return Stack(
                children: [
                  AnimatedBuilder(
                    animation: _playerExpansion,
                    child: LivePreview(canvas: size, preserveInsets: true, child: const NowPlayingPage()),
                    builder: (context, page) {
                      final progress = _playerExpansion.value;
                      final frame = Rect.lerp(origin, Offset.zero & size, progress)!;
                      final opacity = const Interval(0.15, 0.58, curve: Curves.easeOut).transform(progress);
                      final corner = lerpDouble(LayoutPrefs.radius(12), 0, progress)!;
                      return Positioned.fromRect(
                        rect: frame,
                        child: ClipRRect(
                          key: const ValueKey('interactive-player-frame'),
                          borderRadius: BorderRadius.circular(corner),
                          child: ColoredBox(
                            color: AppColors.sink(accent, 0.75),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (opacity < 1)
                                  Positioned(
                                    left: -8,
                                    right: -8,
                                    top: 0,
                                    child: Opacity(
                                      opacity: 1 - opacity,
                                      child: HeroMode(
                                        enabled: false,
                                        child:
                                            LayoutPrefs.instance.tabBar == TabBarStyle.glass &&
                                                _player?.currentTrack != null
                                            ? GlassMiniPlayer(track: _player!.currentTrack!, onOpen: () {})
                                            : MiniPlayer(onOpen: () {}),
                                      ),
                                    ),
                                  ),
                                if (opacity > 0)
                                  Opacity(
                                    opacity: opacity,
                                    child: OverflowBox(
                                      alignment: Alignment.topCenter,
                                      minWidth: size.width,
                                      maxWidth: size.width,
                                      minHeight: size.height,
                                      maxHeight: size.height,
                                      child: page,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );

  void _openNowPlaying({bool expanded = false}) {
    final box = _miniPlayerAnchor.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    final origin = box == null || !box.hasSize || overlay == null
        ? null
        : (box.localToGlobal(Offset.zero, ancestor: overlay) & box.size);
    late final _PhonePlayerRoute route;
    route = _PhonePlayerRoute(
      origin: origin,
      expanded: expanded,
      buildPage: () => _scoped(
        NowPlayingPage(
          onDragUpdate: (details) => route.drag(details.delta.dy),
          onDragEnd: (details) => route.finish(details.primaryVelocity ?? 0),
          onDragCancel: () => route.finish(0, cancelled: true),
        ),
      ),
    );
    _pushPhoneRoute(route);
  }

  Widget _desktopNavigator() => Navigator(
    key: _history.navigatorKey,
    observers: [_history.observer, OverVideo.pages],
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

  /// A play / next / previous key: to the media session when it runs, straight to the player otherwise.
  static void _mediaKey(MediaCommand command, Future<void> Function() fallback) {
    if (MediaSessionService.instance case final session?) {
      session.dispatch(command);
    } else {
      unawaited(fallback());
    }
  }

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
    final expanded =
        !_shortcutRail && (width >= 1200 || sideRoom && SidebarFit.fullFits(width, sideOpen: _sidePanel && _hasTrack));

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
        // Through the media session, which runs a key seen both here and by the system (a media key while the
        // window has focus) once.
        AppAction.playPause: () =>
            _mediaKey(const MediaCommand.toggle(source: MediaCommandSource.keyboard), c.togglePlay),
        AppAction.next: () => _mediaKey(const MediaCommand.next(source: MediaCommandSource.keyboard), c.next),
        AppAction.previous: () =>
            _mediaKey(const MediaCommand.previous(source: MediaCommandSource.keyboard), c.previous),
        AppAction.seekBackward: () => c.seekByStep(forward: false),
        AppAction.seekForward: () => c.seekByStep(forward: true),
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
              // A tab builds nothing until first visited; then its navigator stays alive, keeping its history and scroll.
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
        Stack(
          key: _phonePlayerArea,
          fit: StackFit.expand,
          children: [
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
              bottomNavigationBar: MiniPlayerExpansion(
                anchorKey: _miniPlayerAnchor,
                update: _updatePlayerExpansion,
                finish: _finishPlayerExpansion,
                child: PhoneBottomBar(
                  onOpenPlayer: _openNowPlaying,
                  link: _bar,
                  tab: _tab,
                  onSelect: _selectTab,
                  showTabs: !sideways,
                ),
              ),
            ),
            if (_playerDragOrigin case final origin?) _phonePlayerPreview(origin),
          ],
        ),
      );
    } else {
      final sideOpen = sideRoom && _sidePanel && _hasTrack;
      _window = width;
      _sideOpenNow = sideOpen;
      // The rail at narrow widths is fixed; the dragged widths apply to the expanded layout only.
      final fullHeightRail = _fullHeightRail;
      final sidebarWidth = expanded
          ? SidebarFit.left(_sidebarWidth.value, width, sideOpen: sideOpen)
          : _shortcutRail
          ? ShortcutRail.width
          : 84.0;
      final libraryExpanded = _history.location == Locations.library;
      // A full-height rail stands outside the pages and stays put when the Library takes the room.
      final left = fullHeightRail ? ShortcutRail.width + 8 : (libraryExpanded ? 0.0 : sidebarWidth);
      final panelWidth = SidebarFit.right(_sidePanelWidth.value, width, left: left);
      _contentWidth = width - left - (sideOpen ? panelWidth + 8 : 0) - (libraryExpanded ? 16 : 24);
      final sidebar = RepaintBoundary(
        child: Row(
          mainAxisSize: MainAxisSize.min,
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
                  shortcuts: _shortcutRail,
                  location: _history.location,
                  onHome: _goHome,
                  onSearch: _goSearch,
                  inTitleBar: hasCustomTitleBar,
                ),
              ),
            ),
            if (expanded)
              ResizeHandle(
                label: tr.resizeSidebar,
                onDrag: _dragSidebar,
                onEnd: _saveWidths,
                onReset: () {
                  _sidebarWidth.value = SidebarFit.left(LayoutPrefs.sidebarDefault, width, sideOpen: sideOpen);
                  _saveWidths();
                },
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      );
      final mainPanel = ShellPanel(child: _desktopNavigator());
      final playingPanel = ShellPanel(child: NowPlayingSidePanel(onClose: () => setState(() => _sidePanel = false)));
      final panelWidths = Listenable.merge([_sidePanelWidth, _sidebarWidth]);
      final pages = Padding(
        padding: EdgeInsets.fromLTRB(8, hasCustomTitleBar ? 0 : 8, 8, 0),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: libraryExpanded ? 0 : 1),
          duration: LayoutPrefs.pageDuration(reverse: !libraryExpanded),
          curve: Curves.easeInOutCubic,
          builder: (context, fraction, _) => Row(
            children: [
              if (!fullHeightRail)
                Visibility(
                  visible: fraction > 0,
                  maintainState: true,
                  child: IgnorePointer(
                    ignoring: libraryExpanded || fraction < 1,
                    child: ClipRect(
                      child: Align(alignment: Alignment.centerRight, widthFactor: fraction, child: sidebar),
                    ),
                  ),
                ),
              Expanded(child: mainPanel),
              if (sideRoom)
                ListenableBuilder(
                  listenable: panelWidths,
                  builder: (context, panel) => SlidingPanel(
                    open: sideOpen,
                    width: SidebarFit.right(
                      _sidePanelWidth.value,
                      width,
                      left: fraction * _leftWidth(width, sideOpen: sideOpen),
                    ),
                    handle: ResizeHandle(
                      label: tr.resizeSidePanel,
                      onDrag: _dragSidePanel,
                      onEnd: _saveWidths,
                      onReset: () {
                        _sidePanelWidth.value = SidebarFit.right(
                          LayoutPrefs.sidePanelDefault,
                          width,
                          left: libraryExpanded ? 0 : _leftWidth(width, sideOpen: true),
                        );
                        _saveWidths();
                      },
                    ),
                    child: panel!,
                  ),
                  child: playingPanel,
                ),
            ],
          ),
        ),
      );
      body = _scoped(
        ValueListenableBuilder(
          valueListenable: fullScreenPlayer,
          builder: (context, full, pages) {
            // Over the expanded player the bar floats on the player's own background (one picture, no seam);
            // elsewhere it slides away, but Rail keeps it in sight.
            final barFloats = full;
            final barHides = full && !_fullHeightRail;
            // The player bar stays too with the rail (sliding up whenever the pointer neared the foot got in the way),
            // still over the player's picture, as one.
            final playerBarHides = full && !_shortcutRail;
            final barHeight = _fullHeightRail ? AppTitleBar.railHeight : AppTitleBar.tallHeight;
            // Keyed: it moves between the column and the overlay without losing what's typed in it.
            final titleBar = AutoHideBar(
              key: _titleBarKey,
              edge: AxisDirection.up,
              enabled: barHides,
              shown: _titleBarShown,
              visibility: _playerBarShown,
              // Over the player it brings the window's colour with it, as it has above the pages. Always there
              // (clear above the pages), so the bar keeps its state, such as what is typed, between the two.
              child: ColoredBox(color: barHides ? AppColors.background : Colors.transparent, child: _titleBar()),
            );
            final scaffold = Scaffold(
              extendBody: full,
              // In the bottom slot so floating snackbars stack above the player instead of covering it.
              bottomNavigationBar: AutoHideBar(
                edge: AxisDirection.down,
                enabled: playerBarHides,
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
                        if (hasCustomTitleBar && !barFloats) titleBar,
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
                                      top: hasCustomTitleBar && (barHides ? _titleBarShown.value : barFloats)
                                          ? barHeight
                                          : 0,
                                      topShown: barHides ? _titleBarShown.value : barFloats,
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
                    if (hasCustomTitleBar && barFloats) Positioned(top: 0, left: 0, right: 0, child: titleBar),
                  ],
                ),
              ),
            );
            if (!fullHeightRail || full) return scaffold;
            return ColoredBox(
              color: AppColors.background,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
                    child: SizedBox(
                      width: ShortcutRail.width,
                      child: ListenableBuilder(
                        listenable: _history,
                        builder: (context, _) =>
                            ShortcutRail(location: _history.location, onHome: _goHome, onSearch: _goSearch),
                      ),
                    ),
                  ),
                  Expanded(child: scaffold),
                ],
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
/// The open player remains the scroll target while its route shrinks toward the mini-player.
class _PhonePlayerRoute extends PageRouteBuilder<void> {
  _PhonePlayerRoute({required this.origin, required bool expanded, required Widget Function() buildPage})
    : super(
        settings: const RouteSettings(name: nowPlayingRouteName),
        transitionDuration: expanded ? Duration.zero : LayoutPrefs.pageDuration(player: true),
        reverseTransitionDuration: LayoutPrefs.pageDuration(reverse: true, player: true),
        pageBuilder: (_, _, _) => buildPage(),
      );

  final Rect? origin;
  bool _dragging = false;

  void drag(double dy) {
    final animation = controller;
    if (!isCurrent || animation == null || animation.isAnimating || (!_dragging && dy <= 0)) return;
    if (!_dragging) {
      _dragging = true;
      changedInternalState();
    }
    final travel = (origin?.top ?? 560).clamp(1.0, double.infinity);
    animation.value = (animation.value - dy / travel).clamp(0.015, 1);
  }

  void finish(double velocity, {bool cancelled = false}) {
    final animation = controller;
    if (!_dragging || animation == null || !isCurrent) return;
    final travelled = 1 - animation.value;
    if (!cancelled && velocity > -520 && (travelled >= 0.24 || (travelled > 0.035 && velocity > 640))) {
      navigator?.pop();
      return;
    }
    animation
        .animateTo(1, duration: LayoutPrefs.dur(const Duration(milliseconds: 220)), curve: Curves.easeOutCubic)
        .whenComplete(() {
          if (!isActive) return;
          _dragging = false;
          changedInternalState();
        });
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!_dragging) return LayoutPrefs.pageTransition(context, animation, secondaryAnimation, child, player: true);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final anchor = origin ?? Rect.fromLTWH(8, size.height - 86, size.width - 16, 60);
        return AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, page) {
            final t = animation.value;
            final rect = Rect.lerp(anchor, Offset.zero & size, t)!;
            return Stack(
              children: [
                Positioned.fromRect(
                  rect: rect,
                  child: ClipRRect(
                    key: const ValueKey('interactive-player-dismiss-frame'),
                    borderRadius: BorderRadius.circular(lerpDouble(LayoutPrefs.radius(12), 0, t)!),
                    child: Opacity(
                      opacity: const Interval(0.04, 0.34, curve: Curves.easeOut).transform(t),
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minWidth: size.width,
                        maxWidth: size.width,
                        minHeight: size.height,
                        maxHeight: size.height,
                        child: page,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

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
