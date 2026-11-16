import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/lyrics.dart';
import 'package:riflay/services/lyrics_translation.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/language.dart';
import 'package:riflay/ui/player/mini_window.dart';
import 'package:riflay/ui/widgets/controls.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _track = Track(id: 'mini', uri: Uri.parse('file:///mini.mp3'), title: 'Mini song', artist: 'Mini artist');

class _Player extends PlayerController {
  @override
  Track get currentTrack => _track;
  @override
  bool get canPlay => true;
  @override
  Duration get duration => const Duration(minutes: 3);
  @override
  Stream<Duration> smoothPosition() => Stream.value(const Duration(minutes: 1));
}

/// The mini player as main.dart shows it: inside the app's builder, outside its Navigator (no Overlay above it).
Widget _app(PlayerController c) => PlayerScope(
  controller: c,
  child: MaterialApp(
    builder: (context, _) => const Material(type: MaterialType.transparency, child: MiniPlayerWindow()),
  ),
);

Future<void> _show(WidgetTester tester, Size size, DesktopMiniStyle style) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  miniPlayerStyle.value = style;
  await tester.pumpWidget(_app(_Player()));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LayoutPrefs.instance.reset();
    // No lyrics lookups (the network) in these tests; the line picking is tested on its own below.
    LayoutPrefs.instance.miniLyrics = false;
  });

  tearDown(() => miniPlayerStyle.value = DesktopMiniStyle.window);

  testWidgets('pointing at the mini window\'s play button shows its tooltip instead of throwing', (tester) async {
    await _show(tester, const Size(460, 224), DesktopMiniStyle.window);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(160, 100));
    await mouse.moveTo(const Offset(160, 120));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Mini song'), findsOneWidget);
    expect(find.text('Mini artist'), findsOneWidget);
    expect(find.byType(PlayButton), findsOneWidget);
    expect(find.byTooltip(tr.showLyrics), findsOneWidget, reason: 'the lyrics switch, off here');

    await mouse.moveTo(tester.getCenter(find.byType(PlayButton)));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    expect(find.byType(Tooltip), findsWidgets);
    expect(find.byTooltip(tr.miniSwitchToIsland), findsOneWidget);
    expect(find.byTooltip(tr.miniBackToApp), findsOneWidget);
  });

  testWidgets('the island opens from its pill into the mini window deck and folds back', (tester) async {
    await _show(tester, const Size(500, 264), DesktopMiniStyle.island);
    expect(tester.takeException(), isNull);
    expect(find.text('Mini song'), findsOneWidget);
    expect(find.byType(PlayButton), findsNothing, reason: 'closed: one row');

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(250, 220));
    await mouse.moveTo(const Offset(250, 20));
    await tester.pump(const Duration(milliseconds: 200));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull, reason: 'no overflow while it grows');
    }
    expect(find.text('Mini artist'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.byType(PlayButton), findsOneWidget);
    expect(find.byTooltip(tr.miniSwitchToWindow), findsOneWidget);
    expect(find.byTooltip(tr.miniSwitchToIsland), findsNothing);

    await mouse.moveTo(const Offset(5, 260));
    await mouse.moveTo(const Offset(-50, 400));
    await tester.pump(const Duration(milliseconds: 450));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
    expect(find.byType(PlayButton), findsNothing, reason: 'folded back');
  });

  test('the desktop mini player style is the window by default and its choice persists', () async {
    final p = LayoutPrefs.instance;
    expect(p.desktopMini, DesktopMiniStyle.window);
    await p.setDesktopMini(DesktopMiniStyle.island);
    final saved = p.toJson();
    p.restore(const {});
    expect(p.desktopMini, DesktopMiniStyle.window);
    p.restore(saved);
    expect(p.desktopMini, DesktopMiniStyle.island);
    p.restore(const {'desktopMini': 'something-new'});
    expect(p.desktopMini, DesktopMiniStyle.window);
  });

  test('the mini player shows the line being sung and the next one, nothing between lines', () {
    const lyrics = Lyrics(
      source: 'test',
      lines: [
        LyricLine(Duration(seconds: 1), 'First line'),
        LyricLine(Duration(seconds: 5), '♪'),
        LyricLine(Duration(seconds: 8), 'Third line', end: Duration(seconds: 10)),
      ],
    );
    expect(miniLyricAt(lyrics, Duration.zero), (line: null, said: null, next: 'First line'));
    expect(miniLyricAt(lyrics, const Duration(seconds: 2)), (line: 'First line', said: null, next: null));
    expect(miniLyricAt(lyrics, const Duration(seconds: 6)), (line: null, said: null, next: 'Third line'));
    expect(miniLyricAt(lyrics, const Duration(seconds: 9)), (line: 'Third line', said: null, next: null));
    expect(miniLyricAt(lyrics, const Duration(seconds: 11)).line, isNull, reason: 'after its end');
  });

  test('a line in another script comes with how it is said; a Latin one never does', () {
    const lyrics = Lyrics(
      source: 'test',
      lines: [LyricLine(Duration(seconds: 1), '今日もまた'), LyricLine(Duration(seconds: 4), 'Hello again')],
    );
    const extras = [LineExtras(romanized: 'kyō mo mata'), LineExtras(romanized: 'should not show')];
    expect(miniLyricAt(lyrics, const Duration(seconds: 2), extras: extras), (
      line: '今日もまた',
      said: 'kyō mo mata',
      next: 'Hello again',
    ));
    expect(miniLyricAt(lyrics, const Duration(seconds: 5), extras: extras).said, isNull);
    expect(miniLyricAt(lyrics, const Duration(seconds: 2)).said, isNull, reason: 'before the pronunciation arrives');
  });
}
