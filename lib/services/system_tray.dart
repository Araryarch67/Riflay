import 'dart:async';
import 'dart:ui' show AppExitType;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../platform/host.dart';
import '../platform/tray.dart';
import '../ui/debug_switches.dart';
import 'player_controller.dart';
import 'language.dart';

/// Settings › Performance & power › Close to tray (computers): closing the window hides Riflay in the tray and
/// the music keeps playing; Quit in the tray menu ends it. On by default.
class CloseToTray extends ChangeNotifier {
  CloseToTray._();

  static final instance = CloseToTray._();

  static const _key = 'window.closeToTray.v1';

  bool _enabled = true;

  /// What the switch in Settings shows.
  bool get enabled => _enabled;

  /// The setting, unless the build turned the tray off (`RIFLAY_NO_TRAY`).
  bool get active => _enabled && !DebugSwitches.noTray;

  Future<void> load() async {
    _enabled = (await SharedPreferences.getInstance()).getBool(_key) ?? true;
    notifyListeners();
  }

  Future<void> setEnabled(bool v) async {
    if (v == _enabled) return;
    _enabled = v;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_key, v);
  }
}

/// What the tray menu shows; the menu is sent again only when this changes. [mini] is null where there is no mini
/// player.
typedef TrayState = ({
  bool windowShown,
  String? song,
  bool playing,
  bool hasQueue,
  bool hasNext,
  bool shuffle,
  LoopMode loop,
  bool? mini,
});

/// The tray menu, the way a music player's is laid out: the window (Show / Hide, Mini player), then the music (the
/// song as a greyed-out heading, Play / Pause, Previous, Next, Shuffle, Repeat ▸ Off / All / One song), then Quit.
List<TrayEntry> trayMenu(
  TrayState s, {
  required VoidCallback toggleWindow,
  required VoidCallback playPause,
  required VoidCallback previous,
  required VoidCallback next,
  required VoidCallback toggleShuffle,
  required void Function(LoopMode) setLoop,
  VoidCallback? toggleMini,
  required VoidCallback quit,
}) {
  final song = s.song;
  final queue = song != null && s.hasQueue;
  TrayEntry loop(String label, LoopMode mode) =>
      TrayEntry.check(label, checked: s.loop == mode, onTap: queue ? () => setLoop(mode) : null);
  return [
    TrayEntry(s.windowShown ? tr.hideRiflay : tr.showRiflay, toggleWindow),
    if (s.mini case final mini? when toggleMini != null)
      TrayEntry.check(tr.miniPlayer, checked: mini, onTap: toggleMini),
    const TrayEntry.divider(),
    TrayEntry(song ?? tr.nothingPlaying),
    TrayEntry(s.playing ? tr.pause : tr.play, song == null ? null : playPause),
    TrayEntry(tr.previous, song == null ? null : previous),
    TrayEntry(tr.next, s.hasNext ? next : null),
    const TrayEntry.divider(),
    TrayEntry.check(tr.trayShuffle, checked: s.shuffle, onTap: queue ? toggleShuffle : null),
    TrayEntry.submenu(tr.trayRepeat, [
      loop(tr.off, LoopMode.off),
      loop(tr.all, LoopMode.all),
      loop(tr.trayRepeatOne, LoopMode.one),
    ]),
    const TrayEntry.divider(),
    TrayEntry(tr.quitRiflay, quit),
  ];
}

/// "Title · Artist", short enough for a menu line.
String traySongLabel(String title, String artist) {
  final full = artist.isEmpty ? title : '$title · $artist';
  return full.length <= 60 ? full : '${full.substring(0, 59)}…';
}

/// What closing the window does while the tray icon is up: hide it to the tray when [hideOnClose] says so,
/// otherwise quit as if there were no tray.
class WindowCloseHandler with WindowListener {
  WindowCloseHandler({required this.hideOnClose, required this.hide, required this.quit});

  final bool Function() hideOnClose;
  final Future<void> Function() hide;
  final Future<void> Function() quit;

  @override
  void onWindowClose() => unawaited(hideOnClose() ? hide() : quit());
}

/// The tray icon on computers, while Close to tray is on: it follows [PlayerController] and catches the
/// window's close button. With the setting off (or no tray on this desktop) the window closes as it always has.
class SystemTray with WindowListener {
  SystemTray._(this._c);

  final PlayerController _c;
  NativeTray? _tray;
  WindowCloseHandler? _closer;
  TrayState? _shown;
  bool _windowShown = true;

  /// Whether this build may offer the tray at all (computers, not turned off with `RIFLAY_NO_TRAY`).
  static bool get offered => !Host.isWeb && (Host.isLinux || Host.isWindows || Host.isMacOS) && !DebugSwitches.noTray;

  /// Whether this desktop shows tray icons; null until checked. Settings explains a missing tray with it.
  static final available = ValueNotifier<bool?>(null);

  /// Starts following the setting and [c]. Nothing happens where the tray isn't [offered].
  static Future<void> start(PlayerController c) async {
    if (!offered) return;
    await CloseToTray.instance.load();
    available.value = await NativeTray.available();
    final tray = _running = SystemTray._(c);
    CloseToTray.instance.addListener(tray._apply);
    windowManager.addListener(tray);
    await tray._apply();
  }

  static SystemTray? _running;

  /// Exits the process so an installer can replace its executable and libraries.
  static Future<void> quitForUpdate() async {
    if (_running case final tray?) return tray.quit();
    await ServicesBinding.instance.exitApplication(AppExitType.cancelable);
  }

  /// The mini player's state and switch, from the UI (the services don't know its window); null leaves Mini player
  /// out of the menu.
  static ValueListenable<bool>? miniPlayer;
  static Future<void> Function(bool on)? setMiniPlayer;

  /// Computers: brings the window back from the tray, or from under other windows (a link opened with Riflay).
  static Future<void> bringToFront() async {
    if (_running case final tray?) return tray._showWindow();
    if (Host.isWeb || !(Host.isLinux || Host.isWindows || Host.isMacOS)) return;
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void>? _applying;

  /// Puts the icon up or takes it down to match the setting, one change at a time.
  Future<void> _apply() => _applying = (_applying ?? Future.value()).then((_) async {
    try {
      final want = CloseToTray.instance.active && available.value == true;
      if (want && _tray == null) {
        final tray = await NativeTray.show(
          tooltip: 'Riflay',
          onOpen: () => unawaited(_showWindow()),
          beforeMenu: _refresh,
        );
        if (tray == null) return;
        _tray = tray;
        _shown = null;
        _c.addListener(_sync);
        miniPlayer?.addListener(_sync);
        _sync();
        _closer = WindowCloseHandler(hideOnClose: () => CloseToTray.instance.active, hide: _hideWindow, quit: quit);
        windowManager.addListener(_closer!);
        await windowManager.setPreventClose(true);
      } else if (!want && _tray != null) {
        await windowManager.setPreventClose(false);
        windowManager.removeListener(_closer!);
        _closer = null;
        _c.removeListener(_sync);
        miniPlayer?.removeListener(_sync);
        await _tray!.remove();
        _tray = null;
      }
    } catch (e) {
      debugPrint('Tray: $e');
    }
  });

  void _sync() => unawaited(_refresh());

  /// Sends the menu again if what it shows changed. Also just before the right-click opens it: a repeat mode
  /// changed in the app tells no listener.
  Future<void> _refresh() async {
    final tray = _tray;
    if (tray == null) return;
    final t = _c.currentTrack;
    final now = (
      windowShown: _windowShown,
      song: t == null ? null : traySongLabel(t.title, t.artist),
      playing: _c.isPlaying,
      hasQueue: _c.hasQueue,
      hasNext: _c.hasNext,
      shuffle: _c.shuffle,
      loop: _c.loopMode,
      mini: setMiniPlayer == null ? null : miniPlayer?.value,
    );
    if (now == _shown) return;
    _shown = now;
    await tray
        .setMenu(
          trayMenu(
            now,
            toggleWindow: () => unawaited(_windowShown ? _hideWindow() : _showWindow()),
            playPause: () => unawaited(_c.togglePlay()),
            previous: () => unawaited(_c.previous()),
            next: () => unawaited(_c.next()),
            toggleShuffle: () => unawaited(_c.toggleShuffle().whenComplete(_sync)),
            setLoop: (mode) => unawaited(_setLoop(mode)),
            toggleMini: () => unawaited(_toggleMini()),
            quit: () => unawaited(quit()),
          ),
        )
        .catchError((Object e) => debugPrint('Tray menu: $e'));
  }

  /// Repeat ▸ Off / All / One song: the player's own cycle (it remembers the choice) until it lands there.
  Future<void> _setLoop(LoopMode mode) async {
    for (var i = 0; i < LoopMode.values.length && _c.loopMode != mode; i++) {
      await _c.cycleLoopMode();
    }
    _sync();
  }

  /// Mini player on or off, the window shown either way (it may have been in the tray).
  Future<void> _toggleMini() async {
    final set = setMiniPlayer;
    if (set == null) return;
    final on = !(miniPlayer?.value ?? false);
    if (!_windowShown) await _showWindow();
    await set(on);
    _sync();
  }

  void _setShown(bool shown) {
    if (shown == _windowShown) return;
    _windowShown = shown;
    _sync();
  }

  Future<void> _showWindow() async {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
    _setShown(true);
  }

  Future<void> _hideWindow() async {
    await windowManager.hide();
    _setShown(false);
  }

  /// Quit in the tray menu (or closing with the setting just turned off): the music stops, the library is
  /// written, and the app ends.
  Future<void> quit() async {
    try {
      await _c.pause();
      await _c.flushSaves();
    } catch (e) {
      debugPrint('Quit: $e');
    }
    try {
      await _tray?.remove();
      _tray = null;
      await windowManager.setPreventClose(false);
    } catch (e) {
      debugPrint('Quit: $e');
    }
    await windowManager.destroy();
  }

  // The window also comes and goes without the tray: the taskbar, the title bar's Minimize, macOS's Dock.
  @override
  void onWindowMinimize() => _setShown(false);

  @override
  void onWindowRestore() => _setShown(true);

  @override
  void onWindowFocus() => _setShown(true);
}
