import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/main.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/player_panels.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<PlayerController> _app(WidgetTester tester, Size size) async {
  SharedPreferences.setMockInitialValues({'library.v1': jsonEncode(<Object>[])});
  final c = PlayerController();
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

/// The two panels on their own, in the scope the shell gives them.
Future<PlayerController> _panels(WidgetTester tester, Widget panel) async {
  SharedPreferences.setMockInitialValues({'library.v1': jsonEncode(<Object>[])});
  final c = PlayerController();
  await tester.runAsync(c.load);
  await tester.pumpWidget(
    PlayerScope(
      controller: c,
      child: MaterialApp(
        home: ShellScope(
          compact: false,
          width: 1000,
          open: (_, {location}) {},
          openCollection: (_) {},
          openQueue: () {},
          openNowPlaying: () {},
          openLyrics: () {},
          openDownloads: () {},
          importFromYoutube: ({url}) {},
          addFiles: () {},
          addFolder: null,
          child: Scaffold(body: panel),
        ),
      ),
    ),
  );
  return c;
}

void main() {
  testWidgets('phone: Home, Search, Library, Downloads and Settings are the tabs', (tester) async {
    await _app(tester, const Size(400, 800));
    for (final label in ['Home', 'Search', 'Library', 'Downloads', 'Settings']) {
      expect(find.text(label), findsWidgets, reason: 'tab $label');
    }
    // No page has a gear of its own any more.
    await tester.tap(find.text('Library').last);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byTooltip('Settings'), findsNothing);

    await tester.tap(find.text('Settings').last);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Sound'), findsWidgets);
    expect(find.text('Look & feel'), findsWidgets);
  });

  testWidgets('phone: the tab bar floats clear of the edges and survives large text', (tester) async {
    await _app(tester, const Size(360, 640));
    final label = tester.getRect(find.text('Settings').last);
    expect(label.right, lessThanOrEqualTo(352), reason: 'inside the bar\'s 8 px margin');
    expect(label.bottom, lessThanOrEqualTo(632), reason: 'above the bottom margin');
    expect(tester.takeException(), isNull);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('play state and other controller changes leave the side panel and the bar alone', (tester) async {
    final c = await _panels(
      tester,
      Row(
        children: [
          Expanded(child: NowPlayingSidePanel(onClose: () {})),
          const SizedBox(width: 600, child: DesktopPlayerBar(sidePanelOpen: true, onToggleSidePanel: null)),
        ],
      ),
    );
    final panel = NowPlayingSidePanel.builds, bar = DesktopPlayerBar.builds;
    expect(panel, greaterThan(0));
    for (var i = 0; i < 5; i++) {
      // A play / pause, a buffering step, a library batch: all notify the controller.
      // ignore: invalid_use_of_protected_member
      c.notifyListeners();
      await tester.pump();
    }
    expect(NowPlayingSidePanel.builds, panel);
    expect(DesktopPlayerBar.builds, bar);
  });

  testWidgets('the player\'s ⋯ sheet keeps every function that left the phone player\'s face', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late BuildContext player;
      await _panels(
        tester,
        Builder(
          builder: (context) {
            player = context;
            return const SizedBox();
          },
        ),
      );
      await tester.pumpWidget(
        PlayerScope(
          controller: PlayerScope.read(player),
          child: MaterialApp(
            home: ShellScope(
              compact: true,
              width: 400,
              open: (_, {location}) {},
              openCollection: (_) {},
              openQueue: () {},
              openNowPlaying: () {},
              openLyrics: () {},
              openDownloads: () {},
              importFromYoutube: ({url}) {},
              addFiles: () {},
              addFolder: null,
              child: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: TextButton(
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        // The real sheet re-provides the shell's scope the same way.
                        builder: (_) =>
                            ShellScope.of(context)
                                .wrap(PlayerMoreSheet(player: context, track: Track.fromUri(Uri.file('/m/a.mp3')))),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      for (final label in [
        'Add to playlist',
        'Sleep timer',
        'Play on a device',
        'Listen together',
        'Equalizer',
        'Signal path',
        'Stats for nerds',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
