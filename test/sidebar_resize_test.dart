import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/main.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/language.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/navigation.dart';
import 'package:riflay/ui/pages/library_page.dart';
import 'package:riflay/ui/pages/lyrics_page.dart';
import 'package:riflay/ui/player_panels.dart';
import 'package:riflay/ui/shell/desktop_sidebar.dart';
import 'package:riflay/ui/shell/resize_handle.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/theme.dart';
import 'package:riflay/ui/widgets/faded_cover.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SongPlayer extends PlayerController {
  final track = Track(id: 'resize', uri: Uri.parse('file:///resize.mp3'), title: 'Resize', artist: 'Artist');
  final swipeActions = <String>[];
  Duration? progressDuration;
  Stream<Duration>? miniTicks;
  @override
  Duration? get duration => progressDuration ?? super.duration;
  @override
  Stream<Duration> smoothPosition() => miniTicks ?? super.smoothPosition();
  @override
  Track get currentTrack => track;
  @override
  Future<void> previousTrack() async => swipeActions.add('previous');
  @override
  Future<void> next() async => swipeActions.add('next');
}

Future<_SongPlayer> _app(WidgetTester tester, Size size, {_SongPlayer? player}) async {
  SharedPreferences.setMockInitialValues({'library.v1': jsonEncode(<Object>[]), 'discord.enabled': false});
  await LayoutPrefs.instance.reset();
  final c = player ?? _SongPlayer();
  await tester.runAsync(c.load);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final orig = FlutterError.onError;
  FlutterError.onError = (d) {
    final s = d.toString();
    if (!s.contains('google_fonts') && !s.contains('GoogleFonts') && !s.contains('MissingPlugin')) orig?.call(d);
  };
  addTearDown(() => FlutterError.onError = orig);
  await tester.pumpWidget(RiflayApp(controller: c));
  await tester.pump(const Duration(milliseconds: 500));
  return c;
}

/// Lets the app's own timers run out before the binding checks for stragglers.
Future<void> _settle(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

/// A mouse drag by [dx]. The move that crosses the slop is not counted by the drag, so a small one goes first.
Future<void> _drag(WidgetTester tester, Finder handle, double dx) async {
  final g = await tester.startGesture(tester.getCenter(handle), kind: PointerDeviceKind.mouse);
  await g.moveBy(Offset(dx.sign * 20, 0));
  await g.moveBy(Offset(dx, 0));
  await g.up();
  await tester.pump();
}

Finder _handle(String label) => find.byWidgetPredicate((w) => w is ResizeHandle && w.label == label);
double _sidebarW(WidgetTester t) => t.getSize(find.byType(DesktopSidebar)).width;

void main() {
  testWidgets('the Library header opens a searchable desktop grid and restores the sidebar', (tester) async {
    final player = await _app(tester, const Size(1440, 900));
    player.createPlaylist('Morning mix');
    player.createPlaylist('Evening mix');
    await tester.pump();
    final sidebar = find.byType(DesktopSidebar);
    final width = tester.getSize(sidebar).width;
    final restingLeft = tester.getTopLeft(sidebar).dx;
    final search = find.byType(SearchBar);
    final filters = find.byType(FilterChip);
    expect(tester.getTopLeft(search).dy, greaterThan(tester.getBottomLeft(filters.first).dy));
    final panelColor = AppColors.of(tester.element(sidebar)).panel;
    expect(
      find.descendant(
        of: sidebar,
        matching: find.byWidgetPredicate((widget) => widget is Material && widget.color == panelColor),
      ),
      findsWidgets,
    );

    Finder menu() => find.descendant(
      of: find.byType(LibraryList),
      matching: find.byWidgetPredicate((widget) => widget is IconButton && widget.tooltip == tr.moreOptions),
    );
    expect(menu(), findsOneWidget);
    await tester.tap(menu());
    await tester.pumpAndSettle();
    expect(find.text(tr.editPlaylists), findsOneWidget);
    expect(find.text(tr.sortPlaylists), findsOneWidget);
    expect(find.text(tr.expandLibrary), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(tr.expandLibrary));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 72));
    expect(tester.getTopLeft(sidebar).dx, lessThan(restingLeft));
    await tester.pumpAndSettle();

    expect(sidebar, findsNothing);
    expect(find.byType(NowPlayingSidePanel), findsOneWidget);
    expect(find.byType(SliverGrid), findsOneWidget);
    expect(find.text('Morning mix'), findsOneWidget);
    expect(find.text('Evening mix'), findsOneWidget);
    expect(tester.getSize(search).height, 40);
    expect(tester.getSize(search).width, lessThanOrEqualTo(248));
    expect(tester.getTopLeft(search).dx, greaterThan(tester.getTopRight(find.text(tr.yourLibrary)).dx));
    expect(tester.getBottomLeft(search).dy, lessThan(tester.getTopLeft(filters.first).dy));
    final firstCard = find.ancestor(of: find.text('Morning mix'), matching: find.byType(Card)).first;
    final artScale = find.descendant(of: firstCard, matching: find.byType(AnimatedScale));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(firstCard));
    await tester.pump();
    expect(tester.widget<AnimatedScale>(artScale).scale, 1.04);
    final transition = find.descendant(of: artScale, matching: find.byType(ScaleTransition));
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.widget<ScaleTransition>(transition).scale.value, allOf(greaterThan(1), lessThan(1.04)));
    await mouse.removePointer();
    final field = find.descendant(of: find.byType(SearchBar), matching: find.byType(TextField));
    await tester.enterText(field, 'morning');
    await tester.pump();
    expect(find.text('Morning mix'), findsOneWidget);
    expect(find.text('Evening mix'), findsNothing);
    await tester.enterText(field, 'missing');
    await tester.pump();
    expect(find.text(tr.noLibraryMatches), findsOneWidget);

    await tester.tap(find.byTooltip(tr.restoreLibrarySidebar));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 72));
    expect(tester.getTopLeft(sidebar).dx, lessThan(restingLeft));
    await tester.pumpAndSettle();
    expect(sidebar, findsOneWidget);
    expect(tester.getSize(sidebar).width, width);
    await _settle(tester);
  });

  testWidgets('desktop lyrics use the blurred cover when selected and skip it in Lightweight', (tester) async {
    final player = await _app(tester, const Size(1440, 900));
    final prefs = LayoutPrefs.instance;
    final sidebar = find.byType(DesktopSidebar);
    ShellScope.of(tester.element(sidebar)).open(const LyricsPage(), location: Locations.lyrics);
    await tester.pumpAndSettle();
    expect(find.byType(FadedCover), findsNothing);

    await tester.runAsync(() => prefs.setDesktopLyricsBackground(LyricsBackground.blurredCover));
    await tester.pumpAndSettle();
    final cover = tester.widget<FadedCover>(find.byType(FadedCover));
    expect(cover.track, player.track);
    expect(cover.sharp, isFalse);

    await tester.runAsync(() => prefs.setPerformance(PerformanceMode.lightweight));
    await tester.pumpAndSettle();
    expect(find.byType(FadedCover), findsNothing);
    await _settle(tester);
  });

  testWidgets('the desktop shortcut rail opens the Library and survives a settings reload', (tester) async {
    final player = await _app(tester, const Size(1440, 900));
    player.createPlaylist('Morning mix');
    final prefs = LayoutPrefs.instance;
    expect(prefs.desktopSidebarStyle, DesktopSidebarStyle.library);
    await tester.runAsync(() => prefs.setDesktopSidebarStyle(DesktopSidebarStyle.shortcuts));
    await tester.pumpAndSettle();

    final sidebar = find.byType(DesktopSidebar);
    expect(tester.widget<DesktopSidebar>(sidebar).shortcuts, isTrue);
    expect(_sidebarW(tester), 84);
    await tester.tap(find.byTooltip(tr.playlists));
    await tester.pumpAndSettle();
    expect(sidebar, findsNothing);
    expect(find.byType(NowPlayingSidePanel), findsOneWidget);
    expect(find.text('Morning mix'), findsOneWidget);

    await tester.tap(find.byTooltip(tr.restoreLibrarySidebar));
    await tester.pumpAndSettle();
    expect(find.byTooltip(tr.expandLibrary), findsOneWidget);
    expect(_sidebarW(tester), 84);
    await tester.runAsync(prefs.load);
    expect(prefs.desktopSidebarStyle, DesktopSidebarStyle.shortcuts);
    await _settle(tester);
  });

  for (final style in [TabBarStyle.classic, TabBarStyle.glass]) {
    testWidgets('${style.name}: the mini-player border follows the current position', (tester) async {
      final ticks = StreamController<Duration>.broadcast(sync: true);
      addTearDown(ticks.close);
      final player = _SongPlayer()
        ..progressDuration = const Duration(minutes: 2)
        ..miniTicks = ticks.stream;
      await _app(tester, const Size(412, 915), player: player);
      await tester.runAsync(() => LayoutPrefs.instance.setTabBar(style));
      await tester.pump(const Duration(milliseconds: 400));
      final progress = find.byKey(const ValueKey('mini-playback-progress'));
      ticks.add(const Duration(seconds: 30));
      await tester.pump();
      expect(tester.widget<Semantics>(progress).properties.value, '25%');
      ticks.add(const Duration(seconds: 90));
      await tester.pump();
      expect(tester.widget<Semantics>(progress).properties.value, '75%');
      ticks.add(const Duration(minutes: 2));
      await tester.pump();
      expect(tester.widget<Semantics>(progress).properties.value, '100%');
      await _settle(tester);
    });

    testWidgets('${style.name}: swipe left goes to the previous track and right goes to the next', (tester) async {
      final c = await _app(tester, const Size(412, 915));
      await tester.runAsync(() => LayoutPrefs.instance.setTabBar(style));
      await tester.pump(const Duration(milliseconds: 350));
      final mini = style == TabBarStyle.glass ? find.byType(GlassMiniPlayer) : find.byType(MiniPlayer);
      for (final distance in [-115.0, 115.0]) {
        final finger = await tester.startGesture(tester.getCenter(mini));
        await finger.moveBy(Offset(distance.sign * 24, 0));
        await finger.moveBy(Offset(distance, 0));
        await finger.up();
        await tester.pump();
      }
      expect(c.swipeActions, ['previous', 'next']);
      await _settle(tester);
    });

    testWidgets('${style.name}: the mini-player expands under the finger and a short drag snaps back', (tester) async {
      await _app(tester, const Size(412, 915));
      await tester.runAsync(() => LayoutPrefs.instance.setTabBar(style));
      await tester.pump(const Duration(milliseconds: 350));
      final mini = style == TabBarStyle.glass ? find.byType(GlassMiniPlayer) : find.byType(MiniPlayer);
      final frame = find.byKey(const ValueKey('interactive-player-frame'));
      final origin = tester.getRect(mini);
      final point = Offset(origin.left + 30, origin.top + 24);

      final short = await tester.startGesture(point);
      await short.moveBy(const Offset(0, -24));
      await short.moveBy(const Offset(0, -32));
      await tester.pump();
      expect(frame, findsOneWidget);
      expect(tester.getRect(frame).top, lessThan(origin.top));
      await short.cancel();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(frame, findsNothing);
      expect(find.byType(NowPlayingPage), findsNothing);

      final long = await tester.startGesture(point);
      await long.moveBy(const Offset(0, -24));
      await long.moveBy(const Offset(0, -270));
      await tester.pump();
      expect(tester.getRect(frame).top, lessThan(origin.top - 200));
      await long.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(frame, findsNothing);
      expect(find.byType(NowPlayingPage), findsOneWidget);
      expect(ModalRoute.of(tester.element(find.byType(NowPlayingPage)))?.settings.name, nowPlayingRouteName);
      final closing = find.byKey(const ValueKey('interactive-player-dismiss-frame'));
      final shortDown = await tester.startGesture(const Offset(205, 150));
      await shortDown.moveBy(const Offset(0, 32));
      await shortDown.moveBy(const Offset(0, 52));
      await tester.pump();
      expect(tester.getRect(closing).top, greaterThan(25));
      await shortDown.cancel();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(closing, findsNothing);
      expect(find.byType(NowPlayingPage), findsOneWidget);

      final down = await tester.startGesture(const Offset(205, 150));
      await down.moveBy(const Offset(0, 32));
      await down.moveBy(const Offset(0, 330));
      await tester.pump();
      expect(tester.getRect(closing).top, greaterThan(250));
      await down.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump();
      expect(find.byType(NowPlayingPage), findsNothing);
      expect(mini, findsOneWidget);
      await _settle(tester);
    });
  }
  testWidgets('the sidebar handle resizes live, clamps, saves on release and resets on double click', (tester) async {
    await _app(tester, const Size(1600, 900));
    final handle = _handle('Resize sidebar');
    expect(_sidebarW(tester), LayoutPrefs.sidebarDefault);

    await _drag(tester, handle, 60);
    expect(_sidebarW(tester), LayoutPrefs.sidebarDefault + 60);
    expect(LayoutPrefs.instance.sidebarWidth, LayoutPrefs.sidebarDefault + 60);
    final saved = (await SharedPreferences.getInstance()).getString('layout.v1')!;
    expect((jsonDecode(saved) as Map)['sidebarWidth'], LayoutPrefs.sidebarDefault + 60);

    await _drag(tester, handle, 500);
    expect(_sidebarW(tester), LayoutPrefs.sidebarMax);
    await _drag(tester, handle, -900);
    expect(_sidebarW(tester), LayoutPrefs.sidebarMin);

    await tester.tap(handle);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(handle);
    await tester.pump();
    expect(_sidebarW(tester), LayoutPrefs.sidebarDefault);
    expect(LayoutPrefs.instance.sidebarWidth, LayoutPrefs.sidebarDefault);
    await _settle(tester);
  });

  testWidgets('the side panel handle resizes the other way, clamps, saves and resets', (tester) async {
    await _app(tester, const Size(1600, 900));
    final handle = _handle('Resize side panel');
    final panel = find.byType(SlidingPanel);
    double panelW() => tester.getSize(panel).width - SlidingPanel.gap;
    expect(panelW(), LayoutPrefs.sidePanelDefault);

    await _drag(tester, handle, -80);
    expect(panelW(), LayoutPrefs.sidePanelDefault + 80);
    expect(LayoutPrefs.instance.sidePanelWidth, LayoutPrefs.sidePanelDefault + 80);

    await _drag(tester, handle, -900);
    expect(panelW(), LayoutPrefs.sidePanelMax);
    await _drag(tester, handle, 900);
    expect(panelW(), LayoutPrefs.sidePanelMin);

    await tester.tap(handle);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(handle);
    await tester.pump();
    expect(panelW(), LayoutPrefs.sidePanelDefault);
    await _settle(tester);
  });

  testWidgets('a small window keeps the pages at least 480 wide', (tester) async {
    await _app(tester, const Size(1200, 800));
    await _drag(tester, _handle('Resize sidebar'), 500);
    final side = tester.getSize(find.byType(SlidingPanel)).width - SlidingPanel.gap;
    final content = 1200 - 16 - 8 - 8 - _sidebarW(tester) - side;
    expect(content, greaterThanOrEqualTo(SidebarFit.minContent));
    expect(side, greaterThanOrEqualTo(LayoutPrefs.sidePanelMin));
    await _settle(tester);
  });

  testWidgets('Reset layout brings the default widths back and the rail has no handle', (tester) async {
    await _app(tester, const Size(1600, 900));
    await _drag(tester, _handle('Resize sidebar'), 50);
    expect(LayoutPrefs.instance.isCustomised, isTrue);
    await tester.runAsync(LayoutPrefs.instance.reset);
    await tester.pump();
    expect(_sidebarW(tester), LayoutPrefs.sidebarDefault);
    expect(LayoutPrefs.instance.isCustomised, isFalse);

    // Below HomeShell.sidePanelFrom the library is a rail; above it the full sidebar shows wherever it fits.
    tester.view.physicalSize = const Size(850, 800);
    await tester.pump();
    expect(_handle('Resize sidebar'), findsNothing);
    expect(_sidebarW(tester), 84);
    await _settle(tester);
  });

  test('saved widths are read back clamped', () {
    final p = LayoutPrefs.instance;
    p.restore({'sidebarWidth': 9999, 'sidePanelWidth': 1});
    expect(p.sidebarWidth, LayoutPrefs.sidebarMax);
    expect(p.sidePanelWidth, LayoutPrefs.sidePanelMin);
    p.restore(const {});
    expect(p.sidebarWidth, LayoutPrefs.sidebarDefault);
    expect(p.sidePanelWidth, LayoutPrefs.sidePanelDefault);
  });
}
