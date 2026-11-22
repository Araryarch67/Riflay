import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/smart_merge.dart';
import 'package:riflay/services/sources/music_sources.dart';
import 'package:riflay/ui/widgets/controls.dart';

void main() {
  final song = Track(
    id: 'yt:abcdefghijk',
    uri: Uri.parse('https://music.youtube.com/watch?v=abcdefghijk'),
    title: 'Glass Weather',
    artist: 'Marlow Quartet',
    videoId: 'abcdefghijk',
  );

  setUp(() {
    SmartMerge.instance.clear();
    // Off by default: the marks for a song on its way need a source turned on.
    MusicSources.instance.monochrome = true;
  });
  tearDown(() {
    SmartMerge.instance.clear();
    MusicSources.instance.reset();
  });

  Future<void> show(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SmartMergeMark(track: song, fallback: const Text('own')),
        ),
      ),
    ),
  );

  testWidgets('the song\'s own mark, until its sound comes from a lossless file in the library', (tester) async {
    await show(tester);
    expect(find.text('own'), findsOneWidget);
    expect(find.byType(MergedSourceMark), findsNothing);
    SmartMerge.instance.markUsed('abcdefghijk', sound: (source: TrackSource.device, name: ''));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Mid-way: the second mark is still sliding out.
    final opacity = tester.widget<Opacity>(
      find.descendant(of: find.byType(MergedSourceMark), matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(find.text('own'), findsNothing);
    expect(find.byIcon(Icons.library_music_rounded), findsOneWidget);
  });

  testWidgets('a streaming source joins the mark, and giving up on it goes back', (tester) async {
    await show(tester);
    SmartMerge.instance.markUsed('abcdefghijk', sound: (source: TrackSource.monochrome, name: 'Monochrome'));
    await tester.pumpAndSettle();
    expect(find.byType(MergedSourceMark), findsOneWidget);
    expect(tester.widget<MergedSourceMark>(find.byType(MergedSourceMark)).soundName, 'Monochrome');
    SmartMerge.instance.giveUp('abcdefghijk');
    await tester.pumpAndSettle();
    expect(find.byType(MergedSourceMark), findsNothing);
    expect(find.text('own'), findsOneWidget);
  });

  testWidgets('a source that only has a lossier copy joins the mark with ≠ instead of ×', (tester) async {
    await show(tester);
    SmartMerge.instance.markLossier('abcdefghijk', (source: TrackSource.monochrome, name: 'Monochrome'));
    await tester.pumpAndSettle();
    final mark = tester.widget<MergedSourceMark>(find.byType(MergedSourceMark));
    expect(mark.lossier, isTrue);
    expect(mark.sound, TrackSource.monochrome);
    expect(find.byKey(const ValueKey('notEqual')), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    expect(
      find.byTooltip('Monochrome only has this song in lower quality, so it plays from YouTube Music'),
      findsOneWidget,
    );
    SmartMerge.instance.markUsed('abcdefghijk', sound: (source: TrackSource.monochrome, name: 'Monochrome'));
    await tester.pumpAndSettle();
    expect(tester.widget<MergedSourceMark>(find.byType(MergedSourceMark)).lossier, isFalse);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });

  testWidgets('on its way the mark turns a ring where the × goes; held back by a limit it turns red', (tester) async {
    await show(tester);
    SmartMerge.instance.markWaiting('abcdefghijk', true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.widget<MergedSourceMark>(find.byType(MergedSourceMark)).state, MergeMarkState.waiting);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    SmartMerge.instance.markLimited('abcdefghijk');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    final mark = tester.widget<MergedSourceMark>(find.byType(MergedSourceMark));
    expect(mark.state, MergeMarkState.limited);
    expect(find.byIcon(Icons.hourglass_bottom_rounded), findsOneWidget);
    final fill = tester
        .widgetList<DecoratedBox>(
          find.descendant(of: find.byType(MergedSourceMark), matching: find.byType(DecoratedBox)),
        )
        .map((b) => (b.decoration as ShapeDecoration).color)
        .first;
    final scheme = Theme.of(tester.element(find.byType(MergedSourceMark))).colorScheme;
    expect(fill, scheme.errorContainer, reason: 'red while the source is limiting requests');

    // Merged at last: the limit and the wait are over.
    SmartMerge.instance.markUsed('abcdefghijk', sound: (source: TrackSource.monochrome, name: 'Monochrome'));
    await tester.pumpAndSettle();
    expect(tester.widget<MergedSourceMark>(find.byType(MergedSourceMark)).state, MergeMarkState.merged);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });
}
