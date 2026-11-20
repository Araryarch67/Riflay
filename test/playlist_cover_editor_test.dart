import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/language.dart';
import 'package:riflay/ui/playlist_cover_edit.dart';

void main() {
  testWidgets('collage selects and removes four covers in a single dialog', (tester) async {
    final tracks = [
      for (var index = 1; index <= 5; index++)
        Track(id: 'test-$index', uri: Uri.file('/music/song-$index.mp3'), title: 'Song $index', artist: 'Artist'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) =>
                TextButton(onPressed: () => collageCover(context, 'test', tracks), child: const Text('Open')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final preview = find.widgetWithText(FilledButton, tr.settingsPreview);
    expect(tester.widget<FilledButton>(preview).onPressed, isNull);
    for (final track in tracks.take(4)) {
      final row = find.widgetWithText(ListTile, track.title);
      await tester.scrollUntilVisible(row, 100, scrollable: find.byType(Scrollable).last);
      await tester.tap(row);
      await tester.pump();
    }
    expect(tester.widget<FilledButton>(preview).onPressed, isNotNull);
    await tester.tap(find.byTooltip('${tr.unselect} · Song 1'));
    await tester.pump();
    expect(tester.widget<FilledButton>(preview).onPressed, isNull);
    await tester.tap(find.text(tr.cancel));
    await tester.pumpAndSettle();
    expect(find.text(tr.coverCollage), findsNothing);
  });

  test('crop exports the selected area at 900 pixels and applies rotation and flip', () {
    final photo = img.Image(width: 160, height: 80);
    for (var y = 0; y < photo.height; y++) {
      for (var x = 0; x < photo.width; x++) {
        photo.setPixelRgb(x, y, x < 80 ? 255 : 0, 0, x < 80 ? 0 : 255);
      }
    }
    final bytes = img.encodePng(photo);
    final left = img.decodeJpg(
      exportPlaylistCover((bytes, (zoom: 2, center: const Offset(0.2, 0.5), turns: 0, flipped: false))),
    )!;
    expect((left.width, left.height), (900, 900));
    expect(left.getPixel(450, 450).r, greaterThan(240));

    final flipped = img.decodeJpg(
      exportPlaylistCover((bytes, (zoom: 2, center: const Offset(0.2, 0.5), turns: 0, flipped: true))),
    )!;
    expect(flipped.getPixel(450, 450).b, greaterThan(240));

    final topAfterRotation = img.decodeJpg(
      exportPlaylistCover((bytes, (zoom: 2, center: const Offset(0.5, 0.2), turns: 1, flipped: false))),
    )!;
    expect(topAfterRotation.getPixel(450, 450).r, greaterThan(240));
  });

  testWidgets('editor opens on a phone, zooms, resets, and cancels without saving', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Future<Object?> result;
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              context = ctx;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      result = previewCover(context, img.encodePng(img.Image(width: 160, height: 80)));
      for (var attempt = 0; attempt < 50 && find.byType(AlertDialog).evaluate().isEmpty; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 100));
      }
    });
    await tester.pumpAndSettle();
    final slider = find.byType(Slider);
    expect(tester.widget<Slider>(slider).value, 1);
    await tester.ensureVisible(find.byTooltip('Zoom in'));
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, greaterThan(1));
    await tester.ensureVisible(find.byTooltip('Reset crop'));
    await tester.tap(find.byTooltip('Reset crop'));
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, 1);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(await tester.runAsync(() => result.timeout(const Duration(seconds: 2))), isNull);
    expect(tester.takeException(), isNull);
  });
}
