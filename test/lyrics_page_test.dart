import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/lyrics.dart';
import 'package:riflay/services/lyrics_translation.dart';
import 'package:riflay/ui/pages/lyrics_page.dart';
import 'package:riflay/ui/theme.dart';

Color get _primary => AppColors.textPrimary;

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
  late ValueNotifier<bool> playing;
  var now = Duration.zero;

  setUp(() {
    ticks = StreamController<Duration>.broadcast();
    smooth = StreamController<Duration>.broadcast();
    seeks = [];
    playing = ValueNotifier(true);
    now = Duration.zero;
    LayoutPrefs.instance.dimUnsungLyrics = true;
  });
  tearDown(() {
    ticks.close();
    smooth.close();
    playing.dispose();
    LayoutPrefs.instance
      ..lyricsLines = LyricsLines.all
      ..lyricsSync = LyricsSync.word;
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
            playing: playing,
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
    return c == _primary || c == _primary.withValues(alpha: 0.75);
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
    expect(colorOf(tester, 'Line 1'), _primary);
    expect(lit(tester, 'Line 0'), isTrue); // sung before it
    expect([for (var i = 2; i < 6; i++) lit(tester, 'Line $i')], everyElement(isFalse));
    expect(colorOf(tester, 'Line 0'), isNot(_primary));
  });

  testWidgets('moving to the next line rebuilds two lines, not all of them', (tester) async {
    await pump(tester, _long(), length: const Duration(seconds: 120), start: const Duration(seconds: 1));
    final first = lyricLineBuilds;
    expect(first, greaterThanOrEqualTo(1));

    // Line 0 -> 1: the old and the new current line.
    var before = lyricLineBuilds;
    ticks.add(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));
    expect(lyricLineBuilds - before, 2);
    expect(colorOf(tester, 'Line 1'), _primary);

    // Line 1 -> 2, the same.
    before = lyricLineBuilds;
    ticks.add(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 400));
    expect(lyricLineBuilds - before, 2);

    // A tick inside the same line builds nothing.
    before = lyricLineBuilds;
    ticks.add(const Duration(seconds: 7));
    await tester.pump(const Duration(milliseconds: 400));
    expect(lyricLineBuilds - before, 0);
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

  testWidgets('first, middle and final active lines stay at the viewport center after seeks', (tester) async {
    await pump(tester, _long(), length: const Duration(seconds: 120));
    await tester.pumpAndSettle();
    void centered(int line) {
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      expect(tester.getCenter(find.text('Line $line')).dy, closeTo(viewport.center.dy, 1));
    }

    centered(0);
    for (final line in [18, 39, 2, 0]) {
      ticks.add(Duration(seconds: line * 3));
      await tester.pump();
      await tester.pumpAndSettle();
      centered(line);
    }
    tester.view.physicalSize = const Size(1170, 1800);
    await tester.pumpAndSettle();
    centered(0);
  });

  testWidgets('tapping a line seeks to its time', (tester) async {
    await pump(tester, _short(), length: const Duration(seconds: 30));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Line 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Line 2'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(seeks, [const Duration(seconds: 10)]);
  });

  testWidgets('a word-timed line fills word by word', (tester) async {
    await pump(tester, _karaoke(), length: const Duration(seconds: 30));
    final state = tester.state<KaraokeLineState>(find.byType(KaraokeLine));
    expect(state.progress, (sung: 0, fill: 0.0));

    // On the frame clock: the position is read on each beat, not taken from the stream.
    now = const Duration(milliseconds: 1500);
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.progress.sung, 1);
    expect(state.progress.fill, closeTo(0.5, 0.001));

    now = const Duration(seconds: 3);
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.progress, (sung: 3, fill: 0.0));
    // Painting the fill works on a wrapped line too.
    expect(tester.takeException(), isNull);
  });

  testWidgets('the pronunciation under a word-timed line lights up whole while the line is sung', (tester) async {
    await pump(tester, _karaoke(), length: const Duration(seconds: 30));
    // Pronunciation as the translation service would bring it (no word timings of its own).
    final view = tester.state(find.byType(SyncedLyricsView)) as dynamic;
    LyricsTranslation.romanize.value = true;
    addTearDown(() => LyricsTranslation.romanize.value = false);
    view.extras = const [LineExtras(romanized: 'haro biggu waarudo'), LineExtras.none];
    // ignore: invalid_use_of_protected_member
    view.setState(() {});
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(KaraokeLine), findsOneWidget, reason: 'the line itself fills word by word');
    expect(colorOf(tester, 'haro biggu waarudo'), _primary.withValues(alpha: 0.8), reason: 'not dim like the unsung');
  });

  testWidgets('word fill advances on every Balanced beat (20 fps) without resetting at word boundaries', (
    tester,
  ) async {
    final prefs = LayoutPrefs.instance;
    final previous = prefs.performance;
    prefs.performance = PerformanceMode.balanced;
    addTearDown(() => prefs.performance = previous);
    await pump(tester, _karaoke(), length: const Duration(seconds: 30));
    final state = tester.state<KaraokeLineState>(find.byType(KaraokeLine));
    var last = 0.0;
    for (var i = 1; i <= 25; i++) {
      now = Duration(milliseconds: i * 50);
      await tester.pump(const Duration(milliseconds: 50));
      final current = state.progress.sung + state.progress.fill;
      expect(current, greaterThan(last), reason: 'beat $i must advance, including across the first word boundary');
      final minimum = karaokeProgress(_karaoke().lines.first.words, now - const Duration(milliseconds: 80));
      expect(current, greaterThanOrEqualTo(minimum.sung + minimum.fill - 0.001));
      last = current;
    }
    expect(state.progress.sung, 1);
  });

  testWidgets('rough word stamps glide, but a seek still lands immediately', (tester) async {
    final words = [
      const LyricWord(Duration.zero, Duration(milliseconds: 200), 'One '),
      const LyricWord(Duration(milliseconds: 200), Duration(milliseconds: 200), 'tiny '),
      const LyricWord(Duration(milliseconds: 200), Duration(seconds: 2), 'word'),
    ];
    final lyrics = Lyrics(
      source: 'Test',
      lines: [LyricLine(Duration.zero, 'One tiny word', end: const Duration(seconds: 2), words: words)],
    );
    await pump(tester, lyrics, length: const Duration(seconds: 30));
    final state = tester.state<KaraokeLineState>(find.byType(KaraokeLine));
    // One Balanced beat (50 ms) a step.
    for (var i = 1; i <= 3; i++) {
      now = Duration(milliseconds: i * 50);
      await tester.pump(const Duration(milliseconds: 50));
    }
    now = const Duration(milliseconds: 216);
    await tester.pump(const Duration(milliseconds: 50));
    expect(state.progress.sung + state.progress.fill, lessThan(2), reason: 'a zero-length word should not flash on');
    for (var i = 1; i <= 3; i++) {
      now = Duration(milliseconds: 216 + i * 50);
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(state.progress.sung + state.progress.fill, greaterThan(2));
    now = const Duration(milliseconds: 1600);
    await tester.pump(const Duration(milliseconds: 50));
    expect(state.progress, karaokeProgress(words, now), reason: 'forward seeks snap');
    now = const Duration(milliseconds: 500);
    await tester.pump(const Duration(milliseconds: 50));
    expect(state.progress, karaokeProgress(words, now), reason: 'backward seeks snap');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the fill advances between position ticks while playing, and holds still when paused', (tester) async {
    await pump(tester, _karaoke(), length: const Duration(seconds: 30));
    final state = tester.state<KaraokeLineState>(find.byType(KaraokeLine));
    expect(state.onBeat, isTrue);
    // No stream tick at all: only the clock moves the fill.
    var last = state.progress.fill;
    for (var ms = 100; ms <= 900; ms += 200) {
      now = Duration(milliseconds: ms);
      await tester.pump(const Duration(milliseconds: 100));
      expect(state.progress.fill, greaterThan(last), reason: '$ms ms');
      last = state.progress.fill;
    }

    playing.value = false;
    await tester.pump();
    expect(state.onBeat, isFalse, reason: 'a paused song takes no beats');
    now = const Duration(milliseconds: 1500);
    await tester.pump(const Duration(milliseconds: 200));
    expect(state.progress.sung, 0, reason: 'nothing moved it');
    // A seek while paused still shows: the position stream moves it.
    smooth.add(const Duration(milliseconds: 1500));
    await tester.pump();
    expect(state.progress.sung, 1);

    playing.value = true;
    await tester.pump();
    expect(state.onBeat, isTrue);
  });

  testWidgets('the beat is given up when the line stops being the current one, and when the page is hidden', (
    tester,
  ) async {
    await pump(tester, _karaoke(), length: const Duration(seconds: 30));
    expect(find.byType(KaraokeLine), findsOneWidget);
    ticks.add(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(KaraokeLine), findsNothing, reason: 'the next line has no word timings');
    // No listener is left on the clock: the test ends without a timer pending.

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TickerMode(
            enabled: false,
            child: SyncedLyricsView(
              lyrics: _karaoke(),
              ticks: ticks.stream,
              smoothTicks: smooth.stream,
              position: () => Duration.zero,
              length: () => const Duration(seconds: 30),
              onSeek: seeks.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.state<KaraokeLineState>(find.byType(KaraokeLine)).onBeat, isFalse, reason: 'hidden page');
  });

  testWidgets('Line by line never builds a KaraokeLine, even with word timings', (tester) async {
    LayoutPrefs.instance.lyricsSync = LyricsSync.line;
    await pump(tester, _karaoke(), length: const Duration(seconds: 30));
    expect(find.byType(KaraokeLine), findsNothing);
    expect(colorOf(tester, 'Hello big world'), _primary, reason: 'the whole line is lit at once');
    ticks.add(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(KaraokeLine), findsNothing);
  });

  testWidgets('Focused shows the previous, the current and the next line, and follows the song', (tester) async {
    LayoutPrefs.instance.lyricsLines = LyricsLines.focused;
    await pump(tester, _long(), length: const Duration(seconds: 120), start: const Duration(seconds: 7));
    // Line 2 is current at 7 s: lines 1, 2 and 3, and no others.
    expect(find.textContaining('Line '), findsNWidgets(3));
    expect(find.text('Line 1'), findsOneWidget);
    expect(find.text('Line 2'), findsOneWidget);
    expect(find.text('Line 3'), findsOneWidget);
    expect(colorOf(tester, 'Line 2'), _primary);
    // The current line sits in the middle of the view.
    final box = tester.getRect(find.byType(SyncedLyricsView));
    expect(tester.getCenter(find.text('Line 2')).dy, closeTo(box.center.dy, 12));

    ticks.add(const Duration(seconds: 13));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500)); // the old trio leaves once its fade is done
    await tester.pump(const Duration(milliseconds: 700)); // the new one fades in after it, never both at once
    expect(find.textContaining('Line '), findsNWidgets(3));
    expect(find.text('Line 3'), findsOneWidget);
    expect(find.text('Line 4'), findsOneWidget);
    expect(find.text('Line 5'), findsOneWidget);
    expect(find.text('Line 1'), findsNothing);

    // The lines either side still seek.
    await tester.tap(find.text('Line 3'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(seeks, [const Duration(seconds: 9)]);
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
    now = const Duration(milliseconds: 6500);
    await tester.pump(const Duration(milliseconds: 100));
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
    expect(colorOf(tester, 'Line 4'), _primary);
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
  testWidgets('while lyrics load, grey lines stand in for them instead of a spinner', (tester) async {
    final dir = Directory.systemTemp.createTempSync('lyrics_skeleton');
    UserLyrics.dirOverride = dir;
    addTearDown(() {
      UserLyrics.dirOverride = null;
      dir.deleteSync(recursive: true);
    });
    final track = Track.youtube(videoId: 'skeleton001', title: 'Song', artist: 'Artist');
    LyricsService.forget(track);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 600, child: LyricsView(track: track)),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Loading lyrics'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // Let the lookup give up, so nothing is left running.
    await tester.pumpWidget(const SizedBox());
    LyricsService.forget(track);
  });

  testWidgets('lyrics timed for another version say so', (tester) async {
    await pump(
      tester,
      const Lyrics(lines: [LyricLine(Duration(seconds: 1), 'Line 0')], source: 'Kugou', otherVersion: true),
    );
    expect(find.byKey(const ValueKey('lyrics-other-version')), findsOneWidget);
    expect(find.textContaining('different recording of the same song'), findsOneWidget);
    expect(find.textContaining('timing may not match'), findsOneWidget);
  });

  testWidgets('Adjust timing moves a song\'s lyrics half a second a step, and keeps it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final track = Track.youtube(videoId: 'shift000001', title: 'Song', artist: 'Artist');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LyricsTimingSheet(track: track)),
      ),
    );
    String shown() => tester.widget<Text>(find.byKey(const ValueKey('lyrics-timing'))).data!;
    expect(shown(), 'On time');
    await tester.tap(find.text('Later'));
    await tester.tap(find.text('Later'));
    await tester.pump();
    expect(shown(), '1.0 s later');
    await tester.tap(find.text('Earlier'));
    await tester.tap(find.text('Earlier'));
    await tester.tap(find.text('Earlier'));
    await tester.pump();
    expect(shown(), '0.5 s earlier');
    expect(LyricsTiming.of(track).value, const Duration(milliseconds: -500));
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    expect(prefs!.getInt('lyrics.shift.shift000001'), -500);
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(shown(), 'On time');
  });
}
