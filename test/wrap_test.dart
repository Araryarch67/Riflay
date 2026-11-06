import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/play_history.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/wrap.dart';
import 'package:riflay/services/wrap_notifications.dart';
import 'package:riflay/ui/pages/listening_stats_page.dart';
import 'package:riflay/ui/pages/privacy_settings.dart';
import 'package:riflay/ui/pages/wrap_page.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

Track song(String name, {String artist = 'Artist', String? album}) => Track(
  id: 'file:///music/$name.mp3',
  uri: Uri.parse('file:///music/$name.mp3'),
  title: name,
  artist: artist,
  album: album,
);

/// A history with a busy March 2026 and a first play well over 30 days before April.
PlayHistory march() {
  final h = PlayHistory();
  void p(String name, DateTime at, {String artist = 'Ann', String album = 'First', int heard = 200}) => h.record(
    song(name, artist: artist, album: album),
    Duration(seconds: heard),
    at: at,
  );
  p('old', DateTime(2026, 2, 3, 10)); // first heard in February: not new in March
  p('old', DateTime(2026, 3, 2, 10));
  p('hit', DateTime(2026, 3, 5, 9));
  p('hit', DateTime(2026, 3, 5, 12));
  p('hit', DateTime(2026, 3, 5, 18));
  p('hit', DateTime(2026, 3, 9, 18));
  p('b', DateTime(2026, 3, 9, 19), artist: 'Bo', album: 'Second');
  p('c', DateTime(2026, 3, 9, 20), artist: 'Bo', album: 'Second');
  p('d', DateTime(2026, 3, 20, 20), artist: 'Cy', album: 'Third');
  p('e', DateTime(2026, 3, 31, 23, 59), artist: 'Cy', album: 'Third');
  p('f', DateTime(2026, 4, 1, 0, 1)); // April: not in March
  p('g', DateTime(2026, 3, 21, 8), artist: 'Dee', album: 'Fourth');
  return h;
}

class FakeSink implements WrapNoteSink {
  FakeSink({this.canSchedule = false});
  @override
  final bool canSchedule;
  final shown = <WrapMonth>[];
  final scheduled = <(WrapMonth, DateTime)>[];
  int cancelled = 0;

  @override
  Future<void> show(WrapMonth month) async => shown.add(month);
  @override
  Future<void> schedule(WrapMonth month, DateTime at) async => scheduled.add((month, at));
  @override
  Future<void> cancelScheduled() async => cancelled++;
}

void main() {
  group('months', () {
    test('boundaries in local time, across the new year', () {
      const dec = WrapMonth(2026, 12);
      expect(dec.start, DateTime(2026, 12));
      expect(dec.end, DateTime(2027));
      expect(dec.next, const WrapMonth(2027, 1));
      expect(const WrapMonth(2027, 1).previous, dec);
      expect(WrapMonth.of(DateTime(2026, 3, 31, 23, 59)), const WrapMonth(2026, 3));
      expect(WrapMonth.of(DateTime(2026, 4, 1)), const WrapMonth(2026, 4));
      expect(dec.key, '2026-12');
      expect(WrapMonth.parse('2026-03'), const WrapMonth(2026, 3));
      expect(WrapMonth.parse('2026-13'), isNull);
      expect(WrapMonth.parse(null), isNull);
      expect(const WrapMonth(2026, 3).label, 'March 2026');
    });
  });

  group('eligibility', () {
    final now = DateTime(2026, 4, 2, 9);
    test('30 days of use, counted from the earliest sign of use', () {
      expect(MonthlyWrap.unlocked(firstPlay: now.subtract(const Duration(days: 29)), now: now), isFalse);
      expect(MonthlyWrap.unlocked(firstPlay: now.subtract(const Duration(days: 30)), now: now), isTrue);
      expect(MonthlyWrap.unlocked(now: now), isFalse);
      // No history yet, but the app has been installed for weeks.
      expect(MonthlyWrap.unlocked(firstSeen: now.subtract(const Duration(days: 45)), now: now), isTrue);
      expect(
        MonthlyWrap.unlocked(
          firstPlay: now.subtract(const Duration(days: 3)),
          firstSeen: now.subtract(const Duration(days: 40)),
          now: now,
        ),
        isTrue,
      );
    });

    test('a past month needs 10 plays and nothing else; the running month is not listed', () {
      final h = march();
      // No first-seen date and a short history: viewing is never gated.
      expect(MonthlyWrap.available(h, now: now), [const WrapMonth(2026, 3)]);
      // February has 1 play; April is not over.
      expect(MonthlyWrap.available(h, now: DateTime(2026, 4, 20)), [const WrapMonth(2026, 3)]);
      expect(MonthlyWrap.compute(h, const WrapMonth(2026, 2)), isNull);
      // March itself, on the day it ends: still running, so not listed.
      expect(MonthlyWrap.available(h, now: DateTime(2026, 3, 31)), isEmpty);
    });

    test('a past month is available the day after, without 30 days of use', () {
      final h = PlayHistory();
      for (var i = 0; i < 12; i++) {
        h.record(song('s$i'), const Duration(seconds: 100), at: DateTime(2026, 3, 1 + i));
      }
      expect(MonthlyWrap.unlocked(firstPlay: DateTime(2026, 3, 1), now: DateTime(2026, 4, 1, 10)), isTrue);
      expect(MonthlyWrap.unlocked(firstPlay: DateTime(2026, 3, 25), now: DateTime(2026, 4, 1, 10)), isFalse);
      expect(MonthlyWrap.available(h, now: DateTime(2026, 4, 1)), [const WrapMonth(2026, 3)]);
    });
  });

  group('this month so far', () {
    PlayHistory history(int plays) {
      final h = PlayHistory();
      for (var i = 0; i < plays; i++) {
        h.record(song('s${i % 2}'), const Duration(seconds: 100), at: DateTime(2026, 11, 1 + i, 9));
      }
      return h;
    }

    const nov = WrapMonth(2026, 11);

    test('is computed up to now, from three plays, with no waiting', () {
      final now = DateTime(2026, 11, 3, 12);
      final h = history(3);
      h.record(song('later'), const Duration(seconds: 100), at: DateTime(2026, 11, 20)); // after "now"
      final d = MonthlyWrap.compute(h, nov, now: now)!;
      expect(d.inProgress, isTrue);
      expect(d.until, now);
      expect(d.plays, 3);
      expect(d.title, 'November so far');
      // Without a clock it is the whole month, which has too few plays to be a finished Wrap.
      expect(MonthlyWrap.compute(h, nov), isNull);
    });

    test('needs a few plays, not ten', () {
      expect(MonthlyWrap.compute(history(2), nov, now: DateTime(2026, 11, 5)), isNull);
      expect(MonthlyWrap.compute(history(3), nov, now: DateTime(2026, 11, 5)), isNotNull);
      // A finished month still needs ten.
      expect(MonthlyWrap.compute(history(5), nov, now: DateTime(2026, 12, 5)), isNull);
    });

    test('a play at this very moment counts', () {
      final now = DateTime(2026, 11, 3, 12);
      final h = history(2);
      h.record(song('now'), const Duration(seconds: 100), at: now);
      expect(MonthlyWrap.compute(h, nov, now: now)!.plays, 3);
    });
  });

  group('the streak', () {
    test('a finished month counts its days and its longest run', () {
      final h = PlayHistory();
      // March 2, 3, 4 and 10, 11: five days, three in a row at most; two plays a day.
      for (final day in [2, 3, 4, 10, 11]) {
        h.record(song('a$day'), const Duration(seconds: 100), at: DateTime(2026, 3, day, 9));
        h.record(song('b$day'), const Duration(seconds: 100), at: DateTime(2026, 3, day, 21));
      }
      final d = MonthlyWrap.compute(h, const WrapMonth(2026, 3))!;
      expect(d.daysListened, 5);
      expect(d.longestStreak, 3);
      expect(d.streakNow, 0);
      expect(d.bestStreak, 3);
      expect(d.days, 31);
    });

    test('the running month shows the streak still going, from before the month began', () {
      final h = PlayHistory();
      for (final at in [DateTime(2026, 10, 30), DateTime(2026, 10, 31)]) {
        h.record(song('october'), const Duration(seconds: 100), at: at.add(const Duration(hours: 12)));
      }
      for (var day = 1; day <= 4; day++) {
        h.record(song('n$day'), const Duration(seconds: 100), at: DateTime(2026, 11, day, 12));
      }
      final d = MonthlyWrap.compute(h, const WrapMonth(2026, 11), now: DateTime(2026, 11, 4, 20))!;
      expect(d.longestStreak, 4);
      expect(d.streakNow, 6);
      expect(d.bestStreak, 6);
      expect(d.days, 4);
    });

    testWidgets('the story shows the streak card and the share card names the streak', (tester) async {
      final h = PlayHistory();
      for (var day = 1; day <= 12; day++) {
        h.record(song('s$day'), const Duration(seconds: 200), at: DateTime(2026, 3, day, 12));
      }
      final d = MonthlyWrap.compute(h, const WrapMonth(2026, 3))!;
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: WrapStory(data: d, trackFor: (s) => s.toTrack()),
        ),
      );
      var sawStreak = false;
      for (var i = 0; i < 20 && !sawStreak; i++) {
        sawStreak = find.text('12 days in a row').evaluate().isNotEmpty;
        if (!sawStreak) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
        }
      }
      expect(sawStreak, isTrue);
      expect(find.text('Your longest streak'), findsOneWidget);
      expect(find.text('You listened on 12 of 31 days.'), findsOneWidget);
      for (var i = 0; i < 20; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('Streak: 12 days in a row'), findsOneWidget);
      // Let the last card's timers run out before the test ends.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    });
  });

  group('the numbers', () {
    test('every statistic of March', () {
      final d = MonthlyWrap.compute(march(), const WrapMonth(2026, 3))!;
      expect(d.plays, 10);
      expect(d.listened, const Duration(seconds: 10 * 200));
      expect(d.songs, 7);
      expect(d.artists, 4);
      expect(d.topSong.title, 'hit');
      expect(d.topSong.plays, 4);
      expect(d.topSongs, hasLength(5));
      expect(d.topArtist.title, 'Ann');
      expect(d.topAlbum!.title, 'First');
      // March 5 and 9 both have 600 s: the earlier day wins a tie.
      expect(d.busiestDay, DateTime(2026, 3, 5));
      expect(d.busiestDayListened, const Duration(seconds: 600));
      expect(d.mostReplayed!.title, 'hit');
      expect(d.mostReplayedCount, 3);
      expect(d.mostReplayedDay, DateTime(2026, 3, 5));
      // hit, b, c, d, e, g are first heard in March; old was February's.
      expect(d.newSongs, 6);
    });

    test('nothing played twice in a day has no most-replayed', () {
      final h = PlayHistory();
      for (var i = 0; i < 12; i++) {
        h.record(song('s$i'), const Duration(seconds: 100), at: DateTime(2026, 3, 1 + i));
      }
      final d = MonthlyWrap.compute(h, const WrapMonth(2026, 3))!;
      expect(d.mostReplayed, isNull);
      expect(d.newSongs, 12);
    });
  });

  group('release time', () {
    test('the next 1st at 10:00 local', () {
      expect(MonthlyWrap.nextRelease(DateTime(2026, 3, 1, 9)), DateTime(2026, 3, 1, 10));
      expect(MonthlyWrap.nextRelease(DateTime(2026, 3, 1, 10)), DateTime(2026, 4, 1, 10));
      expect(MonthlyWrap.nextRelease(DateTime(2026, 3, 15)), DateTime(2026, 4, 1, 10));
      expect(MonthlyWrap.nextRelease(DateTime(2026, 12, 31, 23)), DateTime(2027, 1, 1, 10));
    });

    test('which month is announced', () {
      const m = WrapMonth(2026, 3);
      final now = DateTime(2026, 4, 2);
      expect(MonthlyWrap.dueNotice(enabled: true, available: [m], lastNotified: null, now: now), m);
      expect(MonthlyWrap.dueNotice(enabled: false, available: [m], lastNotified: null, now: now), isNull);
      expect(MonthlyWrap.dueNotice(enabled: true, available: [m], lastNotified: m, now: now), isNull);
      expect(MonthlyWrap.dueNotice(enabled: true, available: const [], lastNotified: null, now: now), isNull);
      // Months long gone are not announced late.
      expect(
        MonthlyWrap.dueNotice(enabled: true, available: [m], lastNotified: null, now: DateTime(2026, 6, 2)),
        isNull,
      );
    });
  });

  group('notifying once a month', () {
    setUp(
      () => SharedPreferences.setMockInitialValues({
        WrapNotifier.firstSeenKey: DateTime(2026, 1, 1).millisecondsSinceEpoch,
      }),
    );

    test('shows March\'s Wrap on opening after the 1st, then never again', () async {
      final sink = FakeSink();
      final n = WrapNotifier(sink);
      await n.run(march(), now: DateTime(2026, 4, 2, 8));
      expect(sink.shown, [const WrapMonth(2026, 3)]);
      await n.run(march(), now: DateTime(2026, 4, 2, 9));
      await n.run(march(), now: DateTime(2026, 4, 20));
      expect(sink.shown, hasLength(1));
      expect(wrapNoteTitle(sink.shown.single), 'Your March in music is ready');
    });

    test('off: nothing is shown; back on, the month is still announced', () async {
      final sink = FakeSink();
      final n = WrapNotifier(sink);
      final h = march();
      await n.setEnabled(false, h, now: DateTime(2026, 4, 2));
      await n.run(h, now: DateTime(2026, 4, 2));
      expect(sink.shown, isEmpty);
      await n.setEnabled(true, h, now: DateTime(2026, 4, 3));
      expect(sink.shown, [const WrapMonth(2026, 3)]);
    });

    test(
      'where scheduling works, the next 1st is set once the month has enough plays; a delivered one is not repeated',
      () async {
        final sink = FakeSink(canSchedule: true);
        final n = WrapNotifier(sink);
        final h = march();
        // Mid-March with 10+ March plays already: March's Wrap is scheduled for April 1, 10:00.
        await n.run(h, now: DateTime(2026, 3, 25));
        expect(sink.scheduled.last, (const WrapMonth(2026, 3), DateTime(2026, 4, 1, 10)));
        // The system delivered it; opening the app afterwards must not show a second one.
        await n.run(h, now: DateTime(2026, 4, 1, 12));
        expect(sink.shown, isEmpty);
        await n.run(h, now: DateTime(2026, 4, 5));
        expect(sink.shown, isEmpty);
        // April has one play: nothing to schedule for May.
        expect(sink.scheduled.where((s) => s.$1 == const WrapMonth(2026, 4)), isEmpty);
      },
    );

    test('a brand-new user is not told about a month they had barely started', () async {
      SharedPreferences.setMockInitialValues({WrapNotifier.firstSeenKey: DateTime(2026, 3, 20).millisecondsSinceEpoch});
      final sink = FakeSink();
      final h = PlayHistory();
      for (var i = 0; i < 12; i++) {
        h.record(song('s$i'), const Duration(seconds: 100), at: DateTime(2026, 3, 20 + i % 10));
      }
      await WrapNotifier(sink).run(h, now: DateTime(2026, 4, 2));
      expect(sink.shown, isEmpty);
      // Viewing is not gated, though.
      expect(MonthlyWrap.available(h, now: DateTime(2026, 4, 2)), [const WrapMonth(2026, 3)]);
    });

    test('the running month is never announced', () async {
      final sink = FakeSink();
      final h = PlayHistory();
      for (var i = 0; i < 12; i++) {
        h.record(song('s$i'), const Duration(seconds: 100), at: DateTime(2026, 4, 1 + i));
      }
      await WrapNotifier(sink).run(h, now: DateTime(2026, 4, 20));
      expect(sink.shown, isEmpty);
      expect(
        MonthlyWrap.dueNotice(
          enabled: true,
          available: const [WrapMonth(2026, 4)],
          lastNotified: null,
          now: DateTime(2026, 4, 20),
        ),
        isNull,
      );
    });

    test('a month that does not qualify yet is not scheduled', () async {
      final sink = FakeSink(canSchedule: true);
      final h = PlayHistory();
      for (var i = 0; i < 5; i++) {
        h.record(song('s$i'), const Duration(seconds: 100), at: DateTime(2026, 3, 1 + i));
      }
      await WrapNotifier(sink).run(h, now: DateTime(2026, 3, 25));
      expect(sink.scheduled, isEmpty);
    });
  });

  group('screens', () {
    Future<void> pump(WidgetTester tester, Widget child, {Size size = const Size(420, 860)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final orig = FlutterError.onError;
      FlutterError.onError = (d) {
        final s = d.toString();
        if (!s.contains('google_fonts') && !s.contains('GoogleFonts') && !s.contains('MissingPlugin')) orig?.call(d);
      };
      addTearDown(() => FlutterError.onError = orig);
      await tester.pumpWidget(child);
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('the story shows each card and advances by tap and arrow key', (tester) async {
      final d = MonthlyWrap.compute(march(), const WrapMonth(2026, 3))!;
      await pump(
        tester,
        MaterialApp(
          home: WrapStory(data: d, trackFor: (s) => s.toTrack()),
        ),
      );
      expect(find.text('Your March in music'), findsOneWidget);

      // Tap on the right of the card: next.
      await tester.tapAt(const Offset(380, 400));
      await tester.pumpAndSettle();
      expect(find.text('You listened for'), findsOneWidget);
      expect(find.text('Your March in music'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('You played'), findsOneWidget);

      // Tap on the left third: back.
      await tester.tapAt(const Offset(30, 400));
      await tester.pumpAndSettle();
      expect(find.text('You listened for'), findsOneWidget);

      // Through to the last card.
      for (var i = 0; i < 20; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
      }
      expect(find.text('March 2026'), findsOneWidget);
      expect(find.textContaining('Top song: hit'), findsOneWidget);
      expect(find.text('Save image'), findsOneWidget);
    });

    testWidgets('the story\'s top-song card names the song and its plays', (tester) async {
      final d = MonthlyWrap.compute(march(), const WrapMonth(2026, 3))!;
      await pump(
        tester,
        MaterialApp(
          home: WrapStory(data: d, trackFor: (s) => s.toTrack()),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
      }
      expect(find.text('Your top song'), findsOneWidget);
      expect(find.text('hit'), findsOneWidget);
      expect(find.textContaining('4 plays'), findsOneWidget);
    });

    testWidgets('the stats page lists the top songs and past Wraps from fake data', (tester) async {
      SharedPreferences.setMockInitialValues({WrapNotifier.firstSeenKey: DateTime(2026, 1, 1).millisecondsSinceEpoch});
      final controller = PlayerController();
      final h = march();
      await pump(
        tester,
        MaterialApp(
          home: PlayerScope(
            controller: controller,
            child: ShellScope(
              compact: true,
              width: 420,
              open: (_, {location}) {},
              openCollection: (_) {},
              openQueue: () {},
              openNowPlaying: () {},
              openLyrics: () {},
              openDownloads: () {},
              importFromYoutube: () {},
              addFiles: () {},
              addFolder: null,
              child: Scaffold(
                body: ListeningStatsPage(history: h, now: DateTime(2026, 4, 15)),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Your listening'), findsWidgets);
      expect(find.text('This month'), findsOneWidget);
      expect(find.text('2026'), findsNothing); // the current year is "This year"
      expect(find.text('Top songs'), findsOneWidget);
      expect(find.text('Your monthly Wraps'), findsOneWidget);
      expect(find.text('Your March in music'), findsOneWidget);
      // April has one play: the "so far" entry is there, but waiting for a few more.
      expect(find.text('April so far'), findsOneWidget);
      expect(find.text('Play a few songs to see your Wrap'), findsOneWidget);

      await tester.tap(find.text('All time'));
      await tester.pumpAndSettle();
      expect(find.text('Top songs'), findsOneWidget);
      expect(find.text('hit'), findsWidgets);
    });

    testWidgets('settings: the history switch, Wrap notification and clear with a confirmation', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final h = march();
      await pump(
        tester,
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: PrivacySettings(history: h)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Keep a listening history on this device'), findsOneWidget);
      expect(find.text('Monthly Wrap notification'), findsOneWidget);
      expect(find.text('Clear listening history'), findsOneWidget);

      await tester.tap(find.text('Keep a listening history on this device'));
      await tester.pump();
      expect(h.enabled, isFalse);

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(find.text('Clear listening history?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.length, 12);

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
      await tester.pumpAndSettle();
      expect(h.length, 0);
    });
  });
}
