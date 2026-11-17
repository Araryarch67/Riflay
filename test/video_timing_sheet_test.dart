import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/video_timing.dart';
import 'package:riflay/ui/widgets/video_timing_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Earlier and Later adjust by half a second and Reset restores automatic timing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    VideoTiming.clearCache();
    final song = Track.youtube(videoId: 'sheet', title: 'Song', artist: 'Artist');
    final timing = VideoTiming.of(song, song, 'mv');
    await timing.ready;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoTimingSheet(timing: timing, title: song.title),
        ),
      ),
    );
    expect(find.text('On time'), findsOneWidget);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Reset')).onPressed, isNull);
    await tester.tap(find.text('Earlier'));
    await tester.pump();
    expect(find.text('0.5 s earlier'), findsOneWidget);
    await tester.tap(find.text('Earlier'));
    await tester.pump();
    expect(find.text('1.0 s earlier'), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pump();
    expect(find.text('0.5 s earlier'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(find.text('On time'), findsOneWidget);
    expect(timing.value, Duration.zero);
    await tester.tap(find.text('Later'));
    await tester.pump();
    expect(find.text('0.5 s later'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
