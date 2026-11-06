import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/main.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/shell/desktop_sidebar.dart';
import 'package:riflay/ui/shell/resize_handle.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SongPlayer extends PlayerController {
  final track = Track(id: 'resize', uri: Uri.parse('file:///resize.mp3'), title: 'Resize', artist: 'Artist');
  @override
  Track get currentTrack => track;
}

Future<void> _app(WidgetTester tester, Size size) async {
  SharedPreferences.setMockInitialValues({'library.v1': jsonEncode(<Object>[])});
  await LayoutPrefs.instance.reset();
  final c = _SongPlayer();
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
