import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/main.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/download_prefs.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/download_editor.dart';
import 'package:riflay/ui/widgets/editable_title.dart';
import 'package:riflay/ui/ytmusic_edit.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _app(WidgetTester tester, Size size) async {
  SharedPreferences.setMockInitialValues({'library.v1': jsonEncode(<Object>[])});
  final c = PlayerController();
  await tester.runAsync(c.load);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final orig = FlutterError.onError;
  // Fonts and plugins aren't there in tests.
  FlutterError.onError = (d) {
    final s = d.toString();
    if (!s.contains('google_fonts') && !s.contains('GoogleFonts') && !s.contains('MissingPlugin')) orig?.call(d);
  };
  addTearDown(() => FlutterError.onError = orig);
  await tester.pumpWidget(RiflayApp(controller: c));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('phone: Downloads is its own bottom tab and opens the downloads page', (tester) async {
    await _app(tester, const Size(400, 800));
    for (final label in ['Home', 'Search', 'Library', 'Downloads', 'Settings']) {
      expect(find.text(label), findsWidgets, reason: 'tab $label');
    }
    expect(find.textContaining('Nothing downloading'), findsNothing);
    await tester.tap(find.text('Downloads').last);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('Nothing downloading'), findsOneWidget);
    // Back to Home with its tab.
    await tester.tap(find.text('Home').last);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('Nothing downloading'), findsNothing);
  });

  for (final width in const <double>[900, 1400]) {
    testWidgets('desktop ${width.toInt()} wide: Downloads is always in the sidebar', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await _app(tester, Size(width, 800));
        // Expanded: the word; collapsed: its tooltip.
        final visible =
            find.text('Downloads').evaluate().isNotEmpty || find.byTooltip('Downloads').evaluate().isNotEmpty;
        expect(visible, isTrue);
        await tester.tap(
          find.text('Downloads').evaluate().isNotEmpty
              ? find.text('Downloads').first
              : find.byTooltip('Downloads').first,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.textContaining('Nothing downloading'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  group('edit sheet', () {
    final track = Track(
      id: 'file:///music/abc.webm',
      uri: Uri.parse('file:///music/abc.webm'),
      title: 'Poison Dagger',
      artist: 'D-low',
      album: 'Old Album',
      duration: const Duration(minutes: 3),
      sourceUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    );

    Future<List<DownloadEdits>> open(WidgetTester tester, {String? mine}) async {
      final saved = <DownloadEdits>[];
      tester.view.physicalSize = const Size(500, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DownloadEditForm(
              track: track,
              myLyrics: mine,
              onSave: (e) async {
                saved.add(e);
                return null;
              },
            ),
          ),
        ),
      );
      return saved;
    }

    testWidgets('the artist is shown, locked, with a plain note', (tester) async {
      await open(tester);
      final artist = tester.widget<TextField>(find.byKey(const ValueKey('artist-field')));
      expect(artist.readOnly, isTrue);
      expect(artist.controller!.text, 'D-low');
      expect(find.text('Artist names stay as the artist released them.'), findsOneWidget);
      // Typing does nothing to it.
      await tester.enterText(find.byKey(const ValueKey('artist-field')), 'Someone else');
      expect(artist.controller!.text, 'D-low');
    });

    testWidgets('title, album and lyrics can be changed and are handed back', (tester) async {
      final saved = await open(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Poison Dagger'), 'Poison Dagger (Live)');
      await tester.enterText(find.widgetWithText(TextField, 'Old Album'), 'Live Set');
      await tester.enterText(find.byKey(const ValueKey('lyrics-field')), '[00:01.00]Hello\n[00:04.00]World');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(saved, hasLength(1));
      expect(saved.single.title, 'Poison Dagger (Live)');
      expect(saved.single.album, 'Live Set');
      expect(saved.single.lyrics, '[00:01.00]Hello\n[00:04.00]World');
    });

    testWidgets('lyrics with a bad time are not saved, and one calm sentence says why', (tester) async {
      final saved = await open(tester);
      await tester.enterText(find.byKey(const ValueKey('lyrics-field')), '[00:99.00]Hello');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(saved, isEmpty);
      expect(find.textContaining('aren\'t written correctly'), findsOneWidget);
    });

    testWidgets('Remove my lyrics empties them, and saving hands back empty lyrics', (tester) async {
      final saved = await open(tester, mine: '[00:01.00]Old');
      await tester.tap(find.text('Remove my lyrics'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(saved.single.lyrics, '');
    });

    testWidgets('untouched lyrics are left alone', (tester) async {
      final saved = await open(tester, mine: '[00:01.00]Old');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(saved.single.lyrics, isNull);
    });
  });

  group('inline rename', () {
    Future<List<String>> title(WidgetTester tester) async {
      final renamed = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditableTitle(title: 'Road trip', style: const TextStyle(fontSize: 30), onRename: renamed.add),
          ),
        ),
      );
      return renamed;
    }

    testWidgets('tapping the title opens a box; Enter saves', (tester) async {
      final renamed = await title(tester);
      await tester.tap(find.byKey(const ValueKey('rename-title')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('rename-field')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('rename-field')), '  Night drive ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(renamed, ['Night drive']);
      expect(find.byKey(const ValueKey('rename-field')), findsNothing);
    });

    testWidgets('the pencil does the same, and Esc cancels', (tester) async {
      final renamed = await title(tester);
      await tester.tap(find.byKey(const ValueKey('rename-pencil')));
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('rename-field')), 'Something else');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(renamed, isEmpty);
      expect(find.byKey(const ValueKey('rename-field')), findsNothing);
      expect(find.text('Road trip'), findsOneWidget);
    });

    testWidgets('an empty or unchanged name changes nothing', (tester) async {
      final renamed = await title(tester);
      await tester.tap(find.byKey(const ValueKey('rename-title')));
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('rename-field')), '   ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(renamed, isEmpty);
    });
  });

  group('download button', () {
    final song = Track.youtube(videoId: 'dQw4w9WgXcQ', title: 'Never Gonna', artist: 'Rick');

    Future<PlayerController> pumpButton(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'library.v1': jsonEncode(<Object>[])});
      final prefs = DownloadPrefs.instance;
      await tester.runAsync(() async {
        await prefs.load();
        await prefs.setFormat(DownloadFormat.m4a);
        await prefs.setKbps(DownloadFormat.m4a, 96);
        await prefs.setAskEveryTime(true);
      });
      addTearDown(() async {
        await prefs.setAskEveryTime(false);
        await prefs.setFormat(DownloadFormat.opus);
        await prefs.setKbps(DownloadFormat.m4a, null);
      });
      final c = PlayerController();
      await tester.runAsync(c.load);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerScope(
              controller: c,
              child: Center(child: DownloadButton(track: song)),
            ),
          ),
        ),
      );
      return c;
    }

    testWidgets('a long press downloads at once in the saved format, without asking even on "Ask every time"', (
      tester,
    ) async {
      final c = await pumpButton(tester);
      await tester.longPress(find.byType(IconButton));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      final job = c.youtube.jobFor('dQw4w9WgXcQ');
      expect(job, isNotNull);
      expect(job!.choice, const DownloadChoice(DownloadFormat.m4a, kbps: 96));
      expect(find.text('Downloading in M4A · 96 kbps…'), findsOneWidget);
      c.youtube.cancel(job);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a tap asks when "Ask every time" is on, and downloads nothing until Download is pressed', (
      tester,
    ) async {
      final c = await pumpButton(tester);
      await tester.tap(find.byType(IconButton));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Download as'), findsOneWidget);
      expect(c.youtube.jobFor('dQw4w9WgXcQ'), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.youtube.jobFor('dQw4w9WgXcQ'), isNull);
    });

    testWidgets('the tooltip says what a long press does', (tester) async {
      await pumpButton(tester);
      final tip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tip.message, contains('Hold to download now as M4A · 96 kbps'));
    });
  });
}
