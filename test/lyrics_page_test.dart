import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/lyrics.dart';
import 'package:riflay/ui/pages/lyrics_page.dart';

const _white = Colors.white;

/// 6 lines, 5 s apart, for a 30 s song.
Lyrics _short() => Lyrics(
  source: 'Test',
  lines: [for (var i = 0; i < 6; i++) LyricLine(Duration(seconds: i * 5), 'Line $i')],
);

/// 40 lines, 3 s apart: long enough to scroll on a phone.
Lyrics _long() => Lyrics(
  source: 'Test',
  lines: [for (var i = 0; i < 40; i++) LyricLine(Duration(seconds: i * 3), 'Line $i')],
);

Lyrics _karaoke() => Lyrics(
  source: 'Test',
  lines: [
    LyricLine(
      Duration.zero,
      'Hello big world',
      end: const Duration(seconds: 3),
      words: const [
        LyricWord(Duration.zero, Duration(seconds: 1), 'Hello '),
        LyricWord(Duration(seconds: 1), Duration(seconds: 2), 'big '),
        LyricWord(Duration(seconds: 2), Duration(seconds: 3), 'world'),
      ],
    ),
    const LyricLine(Duration(seconds: 5), 'Next line'),
  ],
);

void main() {
  late StreamController<Duration> ticks;
  late StreamController<Duration> smooth;
  late List<Duration> seeks;
  var now = Duration.zero;

  setUp(() {
    ticks = StreamController<Duration>.broadcast();
    smooth = StreamController<Duration>.broadcast();
    seeks = [];
    now = Duration.zero;
    LayoutPrefs.instance.dimUnsungLyrics = true;
  });
  tearDown(() {
    ticks.close();
    smooth.close();
  });

  Future<void> pump(WidgetTester tester, Lyrics lyrics, {Duration? length, Duration? start}) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    now = start ?? Duration.zero;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyncedLyricsView(
            lyrics: lyrics,
            ticks: ticks.stream,
            smoothTicks: smooth.stream,
            position: () => now,
            length: () => length,
            onSeek: seeks.add,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  Color? colorOf(WidgetTester tester, String text) => tester
      .widget<AnimatedDefaultTextStyle>(
        find.ancestor(of: find.text(text), matching: find.byType(AnimatedDefaultTextStyle)).first,
      )
      .style
      .color;

  bool lit(WidgetTester tester, String text) {
    final c = colorOf(tester, text)!;
    return c == _white || c == _white.withValues(alpha: 0.75);
  }

  int litCount(WidgetTester tester, int lines) =>
      [for (var i = 0; i < lines; i++) lit(tester, 'Line $i')].where((b) => b).length;

  testWidgets('a position past the end lights nothing, then a real tick lights one line', (tester) async {
    await pump(tester, _short(), length: const Duration(seconds: 30), start: const Duration(minutes: 10));
    expect(litCount(tester, 6), 0);
    ticks.add(const Duration(minutes: 10));
    await tester.pump(const Duration(milliseconds: 400));
    expect(litCount(tester, 6), 0);

    ticks.add(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(colorOf(tester, 'Line 1'), _white);
    expect(lit(tester, 'Line 0'), isTrue); // sung before it
    expect([for (var i = 2; i < 6; i++) lit(tester, 'Line $i')], everyElement(isFalse));
    expect(colorOf(tester, 'Line 0'), isNot(_white));
  });

  testWidgets('long press and double tap select nothing', (tester) async {
    await pump(tester, _short(), length: const Duration(seconds: 30), start: const Duration(seconds: 1));
    final before = litCount(tester, 6);
    await tester.longPress(find.text('Line 3'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SelectionArea), findsNothing);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.byType(SelectableRegion), findsNothing);
    expect(litCount(tester, 6), before);

    await tester.tap(find.text('Line 3'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Line 3'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SelectableRegion), findsNothing);
    expect(litCount(tester, 6), before);
  });

  testWidgets('tapping a line seeks to its time', (tester) async {
    await pump(tester, _short(), length: const Duration(seconds: 30));
    await tester.tap(find.text('Line 2'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(seeks, [const Duration(seconds: 10)]);
  });

  testWidgets('a word-timed line fills word by word', (tester) async {
    await pump(tester, _karaoke(), length: const Duration(seconds: 30));
    final state = tester.state<KaraokeLineState>(find.byType(KaraokeLine));
    expect(state.progress, (sung: 0, fill: 0.0));

    smooth.add(const Duration(milliseconds: 1500));
    await tester.pump();
    expect(state.progress.sung, 1);
    expect(state.progress.fill, closeTo(0.5, 0.001));

    smooth.add(const Duration(seconds: 3));
    await tester.pump();
    expect(state.progress, (sung: 3, fill: 0.0));
    // Painting the fill works on a wrapped line too.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a karaoke line wraps and centres without errors', (tester) async {
    LayoutPrefs.instance.lyricsAlign = LyricsAlign.centre;
    addTearDown(() => LayoutPrefs.instance.lyricsAlign = LyricsAlign.left);
    final words = [
      for (var i = 0; i < 14; i++) LyricWord(Duration(seconds: i), Duration(seconds: i + 1), 'longword$i '),
    ];
    await pump(
      tester,
      Lyrics(
        source: 'Test',
        lines: [LyricLine(Duration.zero, words.map((w) => w.text).join(), words: words)],
      ),
      length: const Duration(seconds: 60),
    );
    smooth.add(const Duration(milliseconds: 6500));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.state<KaraokeLineState>(find.byType(KaraokeLine)).progress.sung, 6);
  });

  testWidgets('touch and stylus hover do not light a line; a mouse does', (tester) async {
    await pump(tester, _short(), length: const Duration(seconds: 30), start: const Duration(seconds: 1));
    final unlit = colorOf(tester, 'Line 4');
    final spot = tester.getCenter(find.text('Line 4'));

    final touch = await tester.startGesture(spot, kind: PointerDeviceKind.touch);
    await touch.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(colorOf(tester, 'Line 4'), unlit);

    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.addPointer(location: Offset.zero);
    await pen.moveTo(spot);
    await tester.pump(const Duration(milliseconds: 400));
    expect(colorOf(tester, 'Line 4'), unlit);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(spot);
    await tester.pump(const Duration(milliseconds: 400));
    expect(colorOf(tester, 'Line 4'), _white);
  });

  testWidgets('scrolling away shows "Back to current line"; tapping it follows again', (tester) async {
    await pump(tester, _long(), length: const Duration(seconds: 120));
    ticks.add(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 600));
    final back = find.text('Back to current line');
    double opacity() =>
        tester.widget<AnimatedOpacity>(find.ancestor(of: back, matching: find.byType(AnimatedOpacity))).opacity;
    expect(opacity(), 0);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -3000));
    await tester.pump(const Duration(milliseconds: 600));
    expect(opacity(), 1);

    // New lines don't pull the view back while the button is up.
    ticks.add(const Duration(seconds: 9));
    await tester.pump(const Duration(milliseconds: 600));
    expect(opacity(), 1);

    await tester.tap(back);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(opacity(), 0);
    expect(tester.getTopLeft(find.text('Line 3')).dy, inInclusiveRange(0, 844));

    // Following again: the next line scrolls into place by itself.
    ticks.add(const Duration(seconds: 90));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getTopLeft(find.text('Line 30')).dy, inInclusiveRange(0, 844));
    expect(opacity(), 0);
  });

  group('the page menu', () {
    late Directory dir;
    final track = Track(
      id: 'file:///nowhere/a.webm',
      uri: Uri.parse('file:///nowhere/a.webm'),
      title: 'Song',
      artist: 'Artist',
    );

    setUp(() {
      dir = Directory.systemTemp.createTempSync('riflay-lyrics-page');
      UserLyrics.dirOverride = dir;
      LyricsService.sourceTimeout = const Duration(milliseconds: 1);
    });
    tearDown(() {
      UserLyrics.dirOverride = null;
      dir.deleteSync(recursive: true);
    });

    testWidgets('copies plain lyrics without timestamps, and removes my lyrics', (tester) async {
      await tester.runAsync(() => UserLyrics.save(track, '[00:01.00]one\n[00:02.00]two'));
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(children: [LyricsExtrasButtons(track: track)]),
          ),
        ),
      );
      for (var i = 0; i < 20 && find.byTooltip('More').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Use my lyrics file'), findsOneWidget);
      await tester.tap(find.text('Copy lyrics'));
      await tester.pump();
      await tester.pump();
      expect(copied, 'one\ntwo');
      expect(find.text('Lyrics copied'), findsOneWidget);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove my lyrics'));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      expect(await tester.runAsync(() => UserLyrics.read(track)), isNull);
    });
  });
}
