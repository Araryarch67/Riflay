import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/smart_merge.dart';
import 'package:riflay/ui/player_scope.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/track_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => Directory.systemTemp.path,
  );

  final song = Track.youtube(
    videoId: 'abcdefghijk',
    title: 'LOVE MISSION♡',
    artist: 'Vestia Zeta',
    duration: const Duration(minutes: 2, seconds: 54),
  );

  Future<void> show(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = PlayerController();
    await tester.runAsync(c.load);
    addTearDown(() => tester.runAsync(() async => c.dispose()));
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScope(
          controller: c,
          child: ShellScope(
            compact: false,
            width: 1200,
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
              body: SizedBox(width: 940, child: TrackRow(track: song, index: 7, onTap: () {})),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(SmartMerge.instance.clear);
  tearDown(SmartMerge.instance.clear);

  testWidgets('a streamed song\'s row fits its source mark', (tester) async {
    await show(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a row fits Smart merge\'s joined mark too', (tester) async {
    SmartMerge.instance.markUsed('abcdefghijk', sound: (source: TrackSource.monochrome, name: 'Monochrome'));
    await show(tester);
    expect(tester.takeException(), isNull);
  });
}
