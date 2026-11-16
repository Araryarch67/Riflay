import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/smart_merge.dart';
import 'package:riflay/ui/widgets/controls.dart';

void main() {
  final song = Track(
    id: 'yt:abcdefghijk',
    uri: Uri.parse('https://music.youtube.com/watch?v=abcdefghijk'),
    title: 'Glass Weather',
    artist: 'Marlow Quartet',
    videoId: 'abcdefghijk',
  );

  setUp(SmartMerge.instance.clear);
  tearDown(SmartMerge.instance.clear);

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
}
