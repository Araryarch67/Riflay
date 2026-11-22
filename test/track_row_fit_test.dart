import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/smart_merge.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/track_row.dart';
import 'package:riflay/ui/ytmusic_edit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _QueuePlayer extends PlayerController {
  final actions = <String>[];

  @override
  Future<void> playNext(List<Track> tracks) async => actions.add('next');

  @override
  Future<void> addToQueue(List<Track> tracks) async => actions.add('queue');
}

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

  Future<void> show(
    WidgetTester tester, {
    bool compact = false,
    PlayerController? player,
    Future<void> Function(BuildContext, Track)? remove,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final c = player ?? PlayerController();
    await tester.runAsync(c.load);
    addTearDown(() => tester.runAsync(() async => c.dispose()));
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScope(
          controller: c,
          child: ShellScope(
            compact: compact,
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
              body: PlaylistEditScope(
                canRemove: (_) => remove != null,
                remove: remove ?? (_, _) async {},
                child: SizedBox(
                  width: 940,
                  child: TrackRow(track: song, index: 7, onTap: () {}),
                ),
              ),
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

  testWidgets('compact track swipes play next or queue the track', (tester) async {
    final player = _QueuePlayer();
    await show(tester, compact: true, player: player);
    final row = find.byType(TrackRow);
    await tester.drag(row, const Offset(110, 0));
    await tester.pump();
    await tester.drag(row, const Offset(-110, 0));
    await tester.pump();
    expect(player.actions, ['next', 'queue']);
  });

  testWidgets('swiping an editable row exposes remove from playlist', (tester) async {
    final removed = <Track>[];
    await show(tester, compact: true, remove: (_, track) async => removed.add(track));
    await tester.drag(find.byType(TrackRow), const Offset(-110, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.playlist_remove_rounded));
    await tester.pumpAndSettle();
    expect(removed, [song]);
  });
}
