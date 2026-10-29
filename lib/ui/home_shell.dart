import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/track.dart';
import '../services/download_notifications.dart';
import '../services/layout_prefs.dart';
import '../services/player_controller.dart';
import '../services/wrap.dart';
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
import 'widgets/power_settings.dart';
import 'shortcuts.dart';
import 'theme.dart';
import 'youtube_import.dart';
import '../services/youtube_links.dart';
import '../services/listen_together/listen_together.dart';
import 'pages/listen_together_page.dart';
import 'shell/desktop_sidebar.dart';
import 'shell/phone_navigation.dart';
import 'widgets/title_bar.dart';

/// Root layout.
///  * < 700px: bottom tabs + floating mini player, full-screen now playing.
///  * 700–1200px: collapsed library rail + content + player bar.
///  * ≥ 1200px: full library sidebar + content + now-playing side panel.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  PhoneTab _tab = PhoneTab.home;
  bool _sidePanel = true;
  final _searchFocus = FocusNode();

  /// The title bar's search box (desktop); the phone tab has its own.
  final _search = SearchInput();
  final _navigators = {for (final t in PhoneTab.values) t: GlobalKey<NavigatorState>()};

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
    _player?.removeListener(_followTrack);
    _history.removeListener(_followLocation);
    DownloadNotifications.registerOpenDownloads(null);
    DownloadNotifications.registerOpenWrap(null);
    _errors?.cancel();
    _listenEvents?.cancel();
    _searchFocus.dispose();
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

  void _goHome() {
    if (_compact) return _selectTab(PhoneTab.home);
    _leaveExpandedPlayer();
    if (_history.location != Locations.home) _history.open(const HomePage(), Locations.home);
  }

  void _goSearch() {
    if (_compact) return _selectTab(PhoneTab.search);
    _showSearchResults();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search.focus.requestFocus());
  }

  /// The search page, fed by the title bar's box (opened as soon as you type).
  void _showSearchResults() {
    _leaveExpandedPlayer();
    if (_history.location == Locations.search) return;
    final typing = _search.focus.hasFocus;
    _history.open(SearchPage(input: _search), Locations.search);
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
                tooltip: 'Home',
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
        ],
      ),
    ),
  );

  static Route<void> _route(Widget page, {String? location}) => PageRouteBuilder(
    // The page rides along so Forward can rebuild it after Back.
    settings: RouteSettings(name: location, arguments: page),
    transitionDuration: LayoutPrefs.dur(const Duration(milliseconds: 220)),
    reverseTransitionDuration: LayoutPrefs.dur(const Duration(milliseconds: 180)),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0.03, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  );

  void _selectTab(PhoneTab tab) {
    if (tab == _tab) {
      _nav?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _tab = tab);
    }
    if (tab == PhoneTab.search) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
    }
  }

  Future<void> _add(Future<int> Function() pick) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final added = await pick();
      if (added > 0) {
        messenger.showSnackBar(SnackBar(content: Text('Added $added ${added == 1 ? 'song' : 'songs'}')));
      }
    } on MusicPermissionDenied {
      messenger.showSnackBar(const SnackBar(content: Text('Allow Riflay to read your music to add a folder')));
    } catch (e) {
      debugPrint('Adding music failed: $e');
      messenger.showSnackBar(const SnackBar(content: Text('Couldn\'t add that music')));
    }
  }

  bool _compact = false;
  double _contentWidth = 0;

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
        content: const Text('Downloading audio…'),
        action: SnackBarAction(label: 'View', onPressed: () => _open(const DownloadsPage())),
      ),
    );
  }

  /// Ctrl/Cmd+V anywhere outside a text field: a copied YouTube link opens the importer.
  Future<void> _pasteLink() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (text != null && YoutubeLinks.looksLikeLink(text)) await _importFromYoutube(url: text);
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
        transitionDuration: LayoutPrefs.dur(const Duration(milliseconds: 320)),
        reverseTransitionDuration: LayoutPrefs.dur(const Duration(milliseconds: 260)),
        pageBuilder: (_, _, _) => _scoped(const NowPlayingPage()),
        transitionsBuilder: (_, anim, _, child) => SlideTransition(
          position: Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
          child: child,
        ),
      ),
    );
  }

  Widget _desktopNavigator() => Navigator(
    key: _history.navigatorKey,
    observers: [_history.observer],
    onGenerateRoute: (_) => _route(const HomePage(), location: Locations.home),
  );

  Widget _tabNavigator(PhoneTab tab) => Navigator(
    key: _navigators[tab],
    onGenerateRoute: (_) => _route(switch (tab) {
      PhoneTab.home => const HomePage(),
      PhoneTab.search => SearchPage(focusNode: _searchFocus),
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
    if (width >= 700 && !phone && _phoneRoutes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _closePhoneRoutes());
    }
    final expanded = width >= 1200;

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
        AppAction.search: _goSearch,
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
        children: [for (final t in PhoneTab.values) TickerMode(enabled: t == _tab, child: _tabNavigator(t))],
      ),
    );

    final Widget body;
    if (compact) {
      // Sideways the tabs move to a rail on the left, leaving the height to the pages.
      final sideways = width > size.height && size.height < 500;
      final insets = MediaQuery.paddingOf(context);
      _contentWidth = sideways ? width - PhoneSideTabs.width - insets.left - insets.right : width;
      // The desktop history stays alive (hidden) while the window is narrow,
      // so widening it again returns to the same page.
      final pages = Stack(
        children: [
          Positioned.fill(child: tabs()),
          // Full size even while hidden: laid out at width 0 its pages would break.
          Positioned.fill(
            child: Offstage(child: TickerMode(enabled: false, child: _desktopNavigator())),
          ),
        ],
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
            mini: MiniPlayer(onOpen: _openNowPlaying),
            tab: _tab,
            onSelect: _selectTab,
            showTabs: !sideways,
          ),
        ),
      );
    } else {
      final sidebarWidth = expanded ? 300.0 : 84.0;
      final sideOpen = expanded && _sidePanel && _hasTrack;
      _contentWidth = width - sidebarWidth - (sideOpen ? 340 : 0) - 24;
      body = _scoped(
        Scaffold(
          // In the bottom slot so floating snackbars stack above the player instead of covering it.
          bottomNavigationBar: SafeArea(
            top: false,
            child: DesktopPlayerBar(
              sidePanelOpen: sideOpen,
              onToggleSidePanel: expanded ? () => setState(() => _sidePanel = !_sidePanel) : null,
            ),
          ),
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Only full screen hides it: the expanded player inside the window keeps the title bar.
                if (hasCustomTitleBar)
                  ValueListenableBuilder(
                    valueListenable: windowFullScreen,
                    builder: (context, full, bar) => full ? const SizedBox.shrink() : bar!,
                    child: _titleBar(),
                  ),
                Expanded(
                  // Full-screen player on top; the pages stay alive (and their history) underneath.
                  child: ValueListenableBuilder(
                    valueListenable: fullScreenPlayer,
                    builder: (context, full, pages) => Stack(
                      children: [
                        Positioned.fill(
                          child: Offstage(offstage: full, child: pages),
                        ),
                        if (full) const Positioned.fill(child: FullScreenPlayer()),
                      ],
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(8, hasCustomTitleBar ? 0 : 8, 8, 0),
                      child: Row(
                        children: [
                          SizedBox(
                            width: sidebarWidth,
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
                          const SizedBox(width: 8),
                          Expanded(child: ShellPanel(child: _desktopNavigator())),
                          if (expanded)
                            SlidingPanel(
                              open: sideOpen,
                              child: ShellPanel(
                                child: NowPlayingSidePanel(onClose: () => setState(() => _sidePanel = false)),
                              ),
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
    if (old.index != widget.index) _fade.forward(from: 0);
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: CurvedAnimation(parent: _fade, curve: Curves.easeOut),
    child: widget.child,
  );
}
