import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/sources/music_sources.dart';
import 'package:riflay/services/spotiflac.dart';
import 'package:riflay/ui/download_source_dialog.dart';
import 'package:riflay/ui/ytmusic_edit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CatalogueRuntime extends Spotiflac {
  @override
  Future<void> load() async {}
  @override
  Future<void> refresh() async {}
}

void main() {
  testWidgets('a metadata catalogue asks for an enabled audio provider and cancellation queues nothing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final player = PlayerController();
    final runtime = _CatalogueRuntime()
      ..plugins = [
        {'id': 'metadata', 'display_name': 'Catalogue', 'enabled': true, 'has_metadata_provider': true},
        {'id': 'audio', 'display_name': 'Audio provider', 'enabled': true, 'has_download_provider': true},
        {'id': 'disabled', 'display_name': 'Disabled provider', 'enabled': false, 'has_download_provider': true},
      ];
    final source = Spotiflac.track('metadata', {'id': '1', 'name': 'Song'})!;
    bool? queued;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                queued = await downloadExtensionTracks(context, player, [source], runtime: runtime);
              },
              child: const Text('Save'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Audio provider'), findsOneWidget);
    expect(find.text('Disabled provider'), findsNothing);
    expect(find.text('Catalogue'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(queued, isFalse);
    expect(player.youtube.jobs, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    player.dispose();
    runtime.dispose();
  });

  testWidgets('a failed alternate-source lookup never starts an unrequested YouTube download', (tester) async {
    SharedPreferences.setMockInitialValues({'sources.monochrome.v1': true, 'library.v1': jsonEncode([])});
    final player = PlayerController();
    await tester.runAsync(() async {
      await MusicSources.instance.load();
      await Spotiflac.instance.load();
      await player.load();
    });
    final origin = Track.youtube(videoId: 'abcdefghijk', title: 'Song', artist: 'Artist');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerScope(
            controller: player,
            child: DownloadButton(track: origin),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(IconButton));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Download source'), findsOneWidget);
    await tester.tap(find.text('Monochrome'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('Find a match on Monochrome'), findsOneWidget);
    expect(find.text("Couldn't search this source. Try again or choose another source."), findsOneWidget);
    expect(player.youtube.jobs, isEmpty);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    player.dispose();
  });
}
