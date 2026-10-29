import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'models/track.dart';
import 'services/appearance.dart';
import 'services/layout_prefs.dart';
import 'services/media_session.dart';
import 'services/metadata.dart';
import 'services/legacy_data.dart';
import 'services/download_notifications.dart';
import 'services/play_history.dart';
import 'services/player_controller.dart';
import 'services/stay_awake.dart';
import 'services/wrap_notifications.dart';
import 'ui/home_shell.dart';
import 'ui/player_panels.dart' show MiniPlayerWindow, miniPlayer, windowFullScreen;
import 'ui/theme.dart';
import 'ui/widgets/title_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // just_audio has no native Linux/Windows backend; route those through libmpv.
  // Android, macOS and iOS too: libmpv gives them the equalizer, Virtual
  // speakers, ReplayGain, gapless, the signal path and decoders (ALAC,
  // WavPack, DSD) that ExoPlayer and AVPlayer lack.
  JustAudioMediaKit.ensureInitialized(linux: true, windows: true, android: true, macOS: true, iOS: true);
  // The KEMAR data behind Virtual speakers asks to be credited.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'KEMAR HRTF data (Virtual speakers)',
    ], await rootBundle.loadString('assets/audio/HRIR-NOTICE.txt'));
  });
  // The typeface asks to be credited too.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Figtree'], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });

  // Independent of each other: the old data is brought over (it must land before the settings are read),
  // while the window's manager starts and the screen is measured.
  Size? startSize;
  await Future.wait([
    LegacyData.bringOver(),
    if (kDebugMode) _logErrorsToFile(),
    if (hasCustomTitleBar)
      () async {
        await windowManager.ensureInitialized();
        startSize = await _startSize();
      }(),
  ]);
  await Future.wait([Appearance.instance.load(), LayoutPrefs.instance.load()]);

  // The window opens (sized, centred, in the theme's colour) while the player loads behind it.
  final windowShown = _showWindow(startSize);
  final windowSettled = windowShown.then((_) => Appearance.instance.applyWindow());

  final controller = PlayerController();
  await controller.load();
  await windowSettled;
  runApp(RiflayApp(controller: controller));
  // Nothing here is needed to draw the first frame; it starts right after it. The media session must exist
  // before anything can be played, and playing needs a tap on that first frame.
  WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_startServices(controller)));
}

Future<void> _showWindow(Size? size) async {
  if (!hasCustomTitleBar) return;
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      title: 'Riflay',
      // Opens in the middle of the screen, sized to it (tiling WMs place it themselves).
      size: size ?? const Size(1280, 820),
      center: true,
      minimumSize: const Size(320, 420),
      // Linux: the window has an alpha channel; Flutter paints the background.
      backgroundColor: Platform.isLinux ? Colors.transparent : AppColors.background,
      titleBarStyle: TitleBarStyle.hidden,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
}

/// Media controls, wake locks, the download queue, notifications and the listening history.
Future<void> _startServices(PlayerController controller) async {
  await Future.wait(
    [
      MediaSession.start(controller),
      StayAwake.start(controller),
      // Notifications watch the queue, so they attach once it is restored.
      controller.youtube.restoreQueue().then((_) => DownloadNotifications.attach(controller.youtube)),
      // Keeps the listening history (on this device only), then announces a monthly Wrap that is due.
      PlayHistory.instance.start(controller).then((_) => WrapNotifier.instance.run(PlayHistory.instance)),
    ].map((f) => f.catchError((Object e) => debugPrint('Start-up task failed: $e'))),
  );
}

/// A window that suits the screen: 85% of its height (up to 960), about
/// 16:10 wide, never wider than 85% of the screen. Falls back to 1280 x 820.
Future<Size> _startSize() async {
  try {
    final screen = (await screenRetriever.getPrimaryDisplay()).visibleSize;
    if (screen == null || screen.isEmpty) throw StateError('no display size');
    final height = math.min(screen.height * 0.85, 960.0);
    final width = math.min(screen.width * 0.85, height * 1.6);
    return Size(width.roundToDouble(), height.roundToDouble());
  } catch (_) {
    return const Size(1280, 820);
  }
}

/// Debug builds: also append every framework error (with full stack) to
/// `<app support>/errors.log`. The terminal only shows the first error in full and
/// collapses repeats to "Another exception was thrown", which hides the cause.
Future<void> _logErrorsToFile() async {
  final file = File(p.join((await getApplicationSupportDirectory()).path, 'errors.log'));
  await file.parent.create(recursive: true);
  if (file.existsSync() && file.lengthSync() > 2 << 20) await file.writeAsString('');
  final sink = file.openWrite(mode: FileMode.append)..writeln('\n===== run ${DateTime.now()} =====');
  var logged = 0;
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (logged++ < 50) sink.writeln('--- ${DateTime.now()}\n${details.toString()}\n${details.stack}');
    previous?.call(details);
  };
}

class RiflayApp extends StatefulWidget {
  const RiflayApp({super.key, required this.controller, this.theme});

  final PlayerController controller;

  /// Overridable so tests can render with a locally loaded font.
  final ThemeData? theme;

  @override
  State<RiflayApp> createState() => _RiflayAppState();
}

class _RiflayAppState extends State<RiflayApp> with WidgetsBindingObserver {
  final _appearance = Appearance.instance;
  final _layout = LayoutPrefs.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appearance.addListener(_restyle);
    _layout.addListener(_restyle);
    widget.controller.addListener(_syncTint);
    _syncTint();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appearance.removeListener(_restyle);
    _layout.removeListener(_restyle);
    widget.controller.removeListener(_syncTint);
    super.dispose();
  }

  // Library changes are saved after a short pause; write them before the system may end the app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      unawaited(widget.controller.flushSaves());
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await widget.controller.flushSaves();
    return AppExitResponse.exit;
  }

  @override
  void didChangePlatformBrightness() => _appearance.platformBrightnessChanged();

  String? _tintTrack;
  String? _colorsTrack;
  ThemeChoice? _colorsTheme;

  /// "Colours from what's playing: Whole app": follows the current song's cover colour (the same cached
  /// extraction the player uses, so a cover is never read twice). Nothing playing: the theme's own colours.
  void _syncTint() {
    final track = widget.controller.currentTrack;
    _syncCoverColors(track);
    if (_appearance.coverMode != CoverColorMode.app || track == null) {
      _tintTrack = null;
      _appearance.setCoverTint(null);
      return;
    }
    if (_tintTrack == track.id) return;
    _tintTrack = track.id;
    Color? usable(Color c) => c == Metadata.fallbackAccent ? null : c;
    final cached = Metadata.cachedAccent(track);
    if (cached != null) {
      _appearance.setCoverTint(usable(cached));
      return;
    }
    Metadata.accent(track).then((c) {
      if (mounted && _tintTrack == track.id) _appearance.setCoverTint(usable(c));
    });
  }

  /// The Dynamic theme follows the song's cover colours (null when nothing plays or it has no artwork).
  void _syncCoverColors(Track? track) {
    if (_colorsTheme != _appearance.theme) {
      _colorsTheme = _appearance.theme;
      _colorsTrack = null;
    }
    // Only the Dynamic theme needs them: other themes don't spend a decode per song.
    if (track == null || _appearance.theme != ThemeChoice.dynamic) {
      _colorsTrack = null;
      _appearance.setCoverColors(null);
      return;
    }
    if (_colorsTrack == track.id) return;
    _colorsTrack = track.id;
    final cached = Metadata.cachedCoverColors(track);
    if (cached != null) {
      _appearance.setCoverColors(cached);
      return;
    }
    Metadata.coverColors(track).then((c) {
      if (mounted && _colorsTrack == track.id) _appearance.setCoverColors(c);
    });
  }

  /// A palette, accent, font or layout change. The theme is rebuilt once per distinct set of settings (a cache
  /// answers repeats) and handed to [MaterialApp], which has no animation of its own here ([Appearance] fades
  /// the colours itself); widgets that read colours through [AppColors.of] or [Theme] follow by dependency.
  /// Widgets that still read [AppColors] statically are rebuilt by [restyleTree], which leaves out everything
  /// that cannot show a colour.
  void _restyle() {
    _syncTint();
    setState(() {});
    restyleTree(context as Element);
  }

  @override
  Widget build(BuildContext context) {
    // Decoded images: covers are decoded at their on-screen size, so 40 MiB
    // still holds a few hundred (Flutter's default is 100 MiB).
    PaintingBinding.instance.imageCache.maximumSizeBytes = 40 << 20;
    final theme = widget.theme == null ? appThemeNow(desktopFrame: hasCustomTitleBar) : _layout.themed(widget.theme!);
    return PlayerScope(
      controller: widget.controller,
      child: MaterialApp(
        title: 'Riflay',
        debugShowCheckedModeBanner: false,
        // The colours already ease in [Appearance]; a second animation here would run them twice.
        themeAnimationDuration: Duration.zero,
        // On desktop the frame paints the (maybe see-through) window
        // background once; pages on top mustn't stack a second layer.
        theme: widget.theme != null && hasCustomTitleBar
            ? theme.copyWith(scaffoldBackgroundColor: Colors.transparent)
            : theme,
        builder: (context, child) {
          final scaled = MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: LayoutPrefs.effectiveMotion != Motion.full,
              textScaler: TextScaler.linear(MediaQuery.textScalerOf(context).scale(1) * _appearance.textScale),
            ),
            child: child!,
          );
          // The title bar sits above every route (including full-screen ones like Now Playing).
          return AppColorsScope(
            colors: AppColorsScope.current(),
            child: hasCustomTitleBar ? _DesktopFrame(child: scaled) : scaled,
          );
        },
        home: const HomeShell(),
      ),
    );
  }
}

/// Custom title bar on top; on Linux also invisible resize edges, since the
/// window has no native frame there (tiling WMs simply ignore them).
class _DesktopFrame extends StatelessWidget {
  const _DesktopFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final frame = ColoredBox(
      color: AppColors.of(context).background,
      child: Column(
        children: [
          // Hidden while the player fills the screen (the expanded player inside the window keeps it).
          ListenableBuilder(
            listenable: Listenable.merge([windowFullScreen, titleBarInShell]),
            builder: (context, bar) => windowFullScreen.value || titleBarInShell.value ? const SizedBox.shrink() : bar!,
            child: const AppTitleBar(),
          ),
          Expanded(
            child: MediaQuery.removePadding(context: context, removeTop: true, child: child),
          ),
        ],
      ),
    );
    // Mini player: the app stays alive (hidden) under it, so leaving it returns to the same page.
    final withMini = ValueListenableBuilder(
      valueListenable: miniPlayer,
      builder: (context, mini, app) => Stack(
        fit: StackFit.expand,
        children: [
          Offstage(offstage: mini, child: app),
          if (mini) const Material(type: MaterialType.transparency, child: MiniPlayerWindow()),
        ],
      ),
      child: frame,
    );
    return Platform.isLinux ? DragToResizeArea(resizeEdgeSize: 6, child: withMini) : withMini;
  }
}
