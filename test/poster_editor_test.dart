import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/poster/poster_card.dart';
import 'package:riflay/ui/poster/poster_draft.dart';
import 'package:riflay/ui/poster/poster_editor.dart';
import 'package:riflay/ui/poster/poster_presets.dart';

void main() {
  test('every preset places each card, inside the poster; scatter: one big in the middle, more get smaller', () {
    final one = PosterPreset.scatter.layout(1);
    expect(one.single.at, const Offset(0.5, 0.5));
    final five = PosterPreset.scatter.layout(5);
    expect(five.map((p) => p.at).toSet(), hasLength(5), reason: 'each card its own place');
    expect(five.first.scale, lessThan(one.first.scale));
    for (final preset in PosterPreset.values) {
      for (final count in [1, 2, 5, 8]) {
        final poses = preset.layout(count);
        expect(poses, hasLength(count), reason: '$preset, $count');
        for (final p in poses) {
          expect(p.at.dx, inInclusiveRange(0, 1), reason: '$preset');
          expect(p.at.dy, inInclusiveRange(0, 1), reason: '$preset');
        }
      }
    }
  });

  testWidgets('a picked card shows its controls; Remove takes it off the poster', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final c = PlayerController();
    addTearDown(() async => tester.runAsync(() async => c.dispose()));
    final song = Track(id: 'a', uri: Uri.file('/music/a.flac'), title: 'About You', artist: 'The 1975');
    await tester.pumpWidget(
      PlayerScope(
        controller: c,
        child: MaterialApp(home: PosterEditor(songs: [song])),
      ),
    );
    await tester.pump();
    expect(find.byType(PosterCard), findsOneWidget);
    expect(find.text('Size'), findsNothing);

    await tester.tap(find.byType(PosterCard));
    await tester.pumpAndSettle();
    expect(find.text('Size'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    expect(find.byType(PosterCard), findsNothing);
  });

  testWidgets('the Layers step picks a card, and the canvas can turn landscape', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final c = PlayerController();
    addTearDown(() async => tester.runAsync(() async => c.dispose()));
    final song = Track(id: 'a', uri: Uri.file('/music/a.flac'), title: 'About You', artist: 'The 1975');
    await tester.pumpWidget(
      PlayerScope(
        controller: c,
        child: MaterialApp(home: PosterEditor(songs: [song])),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Layers'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(ReorderableListView), matching: find.text('About You')));
    await tester.pumpAndSettle();
    expect(find.text('Size'), findsOneWidget, reason: 'the card picked from its layer');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Canvas'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Landscape'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Landscape'));
    await tester.pumpAndSettle();
    expect(tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio, 16 / 9);
  });

  testWidgets('Undo brings a removed card back, Redo takes it away again', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final c = PlayerController();
    addTearDown(() async => tester.runAsync(() async => c.dispose()));
    final song = Track(id: 'a', uri: Uri.file('/music/a.flac'), title: 'About You', artist: 'The 1975');
    await tester.pumpWidget(PlayerScope(controller: c, child: MaterialApp(home: PosterEditor(songs: [song]))));
    await tester.pump();
    await tester.tap(find.byType(PosterCard));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    expect(find.byType(PosterCard), findsNothing);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(find.byType(PosterCard), findsOneWidget);

    await tester.tap(find.byTooltip('Redo'));
    await tester.pumpAndSettle();
    expect(find.byType(PosterCard), findsNothing);
  });

  testWidgets('a poster closed by accident is offered again, and Continue brings it back', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('riflay-poster-draft');
    PosterDraft.dirOverride = dir;
    addTearDown(() {
      PosterDraft.dirOverride = null;
      dir.deleteSync(recursive: true);
    });
    final song = Track(id: 'a', uri: Uri.file('/music/a.flac'), title: 'About You', artist: 'The 1975');
    await tester.runAsync(
      () => PosterDraft.save({
        'layers': [
          PosterItem(song, at: const Offset(0.5, 0.5)).toJson(),
          {'person': true},
        ],
        'shape': 'square',
      }),
    );
    final c = PlayerController();
    addTearDown(() async => tester.runAsync(() async => c.dispose()));
    await tester.runAsync(() async {
      await tester.pumpWidget(PlayerScope(controller: c, child: const MaterialApp(home: PosterEditor())));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(find.text('Go on with your last poster?'), findsOneWidget);
    expect(find.byType(PosterCard), findsNothing);

    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.byType(PosterCard), findsOneWidget);
    expect(tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio, 1, reason: 'its canvas too');
  });

  testWidgets('a card locked in Layers is no longer picked or moved on the poster', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final c = PlayerController();
    addTearDown(() async => tester.runAsync(() async => c.dispose()));
    final song = Track(id: 'a', uri: Uri.file('/music/a.flac'), title: 'About You', artist: 'The 1975');
    await tester.pumpWidget(PlayerScope(controller: c, child: MaterialApp(home: PosterEditor(songs: [song]))));
    await tester.pump();
    await tester.tap(find.text('Layers'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Lock'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Unlock'), findsOneWidget);

    final before = tester.getCenter(find.byType(PosterCard));
    await tester.drag(find.byType(PosterCard), const Offset(60, 60), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.byType(PosterCard)), before, reason: 'a locked card stays put');
    expect(find.text('Size'), findsNothing, reason: 'nor is it picked');
  });
}
