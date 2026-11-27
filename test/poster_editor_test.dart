import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/poster/poster_card.dart';
import 'package:riflay/ui/poster/poster_decoration.dart';
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
    await tester.pumpWidget(
      PlayerScope(
        controller: c,
        child: MaterialApp(home: PosterEditor(songs: [song])),
      ),
    );
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
      await tester.pumpWidget(
        PlayerScope(
          controller: c,
          child: const MaterialApp(home: PosterEditor()),
        ),
      );
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
    await tester.pumpWidget(
      PlayerScope(
        controller: c,
        child: MaterialApp(home: PosterEditor(songs: [song])),
      ),
    );
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

  testWidgets('a wide window gets the steps down the side and the settings beside the poster', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
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
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byType(PosterCard));
    await tester.pumpAndSettle();
    expect(find.text('Size'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a poster from a list: at least three songs picked there, and those go on it', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final c = PlayerController();
    addTearDown(() async => tester.runAsync(() async => c.dispose()));
    final songs = [
      for (var i = 0; i < 5; i++) Track(id: '$i', uri: Uri.file('/m/$i.flac'), title: 'Song $i', artist: 'A'),
    ];
    await tester.pumpWidget(
      PlayerScope(
        controller: c,
        child: MaterialApp(
          home: Builder(
            builder: (context) =>
                TextButton(onPressed: () => showPosterFromList(context, songs), child: const Text('go')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Song 1'));
    await tester.tap(find.text('Song 3'));
    await tester.pump();
    final make = find.widgetWithText(FilledButton, 'Make a poster');
    expect(tester.widget<FilledButton>(make).onPressed, isNull, reason: 'two songs: at least three are needed');
    await tester.tap(find.text('Song 4'));
    await tester.pump();
    await tester.tap(make);
    await tester.pumpAndSettle();
    expect(find.byType(PosterCard), findsNWidgets(3));
  });

  testWidgets('Change song puts another song on the same card', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final c = PlayerController();
    addTearDown(() async => tester.runAsync(() async => c.dispose()));
    final a = Track(id: 'a', uri: Uri.file('/m/a.flac'), title: 'First', artist: 'A');
    final b = Track(id: 'b', uri: Uri.file('/m/b.flac'), title: 'Second', artist: 'B');
    await tester.pumpWidget(
      PlayerScope(
        controller: c,
        child: MaterialApp(
          home: PosterEditor(songs: [a], pool: [a, b]),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(PosterCard));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Change song'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(ListTile), matching: find.text('Second')));
    await tester.pumpAndSettle();
    expect(find.byType(PosterCard), findsOneWidget);
    expect(tester.widget<PosterCard>(find.byType(PosterCard)).track.id, 'b');
  });

  testWidgets('a cut-out model not on the device is asked for first, with its size; Cancel keeps the built-in one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
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
    ChoiceChip chip(String name) => tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, name));
    expect(chip('Built-in').selected, isTrue);

    await tester.tap(find.widgetWithText(ChoiceChip, 'RMBG'));
    await tester.pumpAndSettle();
    expect(find.text('Download RMBG?'), findsOneWidget);
    expect(find.textContaining('42 MB'), findsOneWidget);
    expect(find.text('Read the licence'), findsOneWidget, reason: 'RMBG is non-commercial: its licence is shown');
    expect(find.text('Accept and download'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(chip('Built-in').selected, isTrue);
    expect(chip('RMBG').selected, isFalse);
  });

  testWidgets('liquid glass cards draw over a photo, flat and turned, without a filled body behind them', (
    tester,
  ) async {
    final song = Track(id: 'a', uri: Uri.file('/music/a.flac'), title: 'About You', artist: 'The 1975');
    final turned = Matrix4.identity()
      ..setEntry(3, 2, 0.0022)
      ..rotateY(-0.5);
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            for (final m in [Matrix4.identity(), turned])
              PosterSlab(
                style: PosterCardStyle.liquid,
                transform: m,
                child: PosterCard(track: song, style: PosterCardStyle.liquid),
              ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(BackdropFilter), findsNothing, reason: 'its own lens, not a blur pane');
    final layers = tester.widgetList<DecoratedBox>(
      find.descendant(of: find.byType(PosterSlab).first, matching: find.byType(DecoratedBox)),
    );
    final slabs = layers.map((d) => d.decoration as BoxDecoration).where((d) => d.border != null && d.color == null);
    expect(slabs, isNotEmpty, reason: 'glass thickness is a rim, so the photo shows through a flat card');
  });

  testWidgets('a card in the middle can be dragged away slowly, not held by the snap', (tester) async {
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
    final start = tester.getCenter(find.byType(PosterCard));
    final gesture = await tester.startGesture(start);
    for (var i = 0; i < 40; i++) {
      await gesture.moveBy(const Offset(2, 2));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    final moved = tester.getCenter(find.byType(PosterCard)) - start;
    expect(moved.dx, greaterThan(40), reason: 'off the upright middle line');
    expect(moved.dy, greaterThan(40), reason: 'off the across middle line');
  });

  testWidgets('the sliders take the look the user picked for sliders, a slim one of their own only with Classic', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final before = LayoutPrefs.instance.volumeSlider;
    addTearDown(() => LayoutPrefs.instance.volumeSlider = before);
    final c = PlayerController();
    addTearDown(() async => tester.runAsync(() async => c.dispose()));
    final song = Track(id: 'a', uri: Uri.file('/music/a.flac'), title: 'About You', artist: 'The 1975');
    // The app's theme carries the picked look; a tall track stands for Pill here.
    final theme = ThemeData(sliderTheme: const SliderThemeData(trackHeight: 12));
    Future<double?> track(VolumeSliderShape look) async {
      LayoutPrefs.instance.volumeSlider = look;
      await tester.pumpWidget(
        PlayerScope(
          controller: c,
          child: MaterialApp(
            theme: theme,
            home: PosterEditor(key: UniqueKey(), songs: [song]),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(PosterCard));
      await tester.pumpAndSettle();
      return SliderTheme.of(tester.element(find.byType(Slider).first)).trackHeight;
    }

    expect(await track(VolumeSliderShape.pill), 12);
    expect(await track(VolumeSliderShape.classic), 1.5);
  });

  test('presets keep clear of the person: a hidden card moves into the free space, a stack moves as one', () {
    // A photo the poster's shape, the person filling its lower two thirds.
    final alpha = Uint8List(9 * 16);
    for (var y = 5; y < 16; y++) {
      for (var x = 0; x < 9; x++) {
        alpha[y * 9 + x] = 255;
      }
    }
    final map = SubjectMap(9, 16, alpha);
    expect(map.covering(const Offset(0.5, 0.8), 0.1, 0.1, posterAspect: 9 / 16), 1);
    expect(map.covering(const Offset(0.5, 0.1), 0.1, 0.05, posterAspect: 9 / 16), 0);
    const halfWide = 130 / 390, halfTall = 230 / 390 * 9 / 16;
    double hidden(Offset at, double s) => map.covering(at, halfWide * s, halfTall * s, posterAspect: 9 / 16);

    final one = clearOfSubject(PosterPreset.scatter.layout(1), hidden, halfWide: halfWide, halfTall: halfTall);
    expect(
      hidden(PosterPreset.scatter.layout(1).single.at, PosterPreset.scatter.layout(1).single.scale),
      greaterThan(0.5),
    );
    expect(hidden(one.single.at, one.single.scale), lessThan(0.45), reason: 'peeks out over the person');

    final stack = PosterPreset.stack.layout(3);
    final moved = clearOfSubject(stack, hidden, halfWide: halfWide, halfTall: halfTall);
    final before = stack[0].at - stack[2].at, after = moved[0].at - moved[2].at;
    expect((after - before * (moved[2].scale / stack[2].scale)).distance, lessThan(0.01), reason: 'still a stack');
    for (final p in moved) {
      expect(hidden(p.at, p.scale), lessThan(0.6));
    }

    // Nothing in the way: every card stays where the preset put it.
    final clear = SubjectMap(9, 16, Uint8List(9 * 16));
    final fan = PosterPreset.fan.layout(4);
    expect(
      clearOfSubject(
        fan,
        (at, s) => clear.covering(at, halfWide * s, halfTall * s, posterAspect: 9 / 16),
        halfWide: halfWide,
        halfTall: halfTall,
      ),
      fan,
    );
  });

  test('a person filling the photo: spread-out presets go across the clear band above them, whole and in order', () {
    const halfWide = 130 / 390, halfTall = 230 / 390 * 9 / 16;
    // The person begins a quarter down; nobody above.
    final alpha = Uint8List(9 * 16);
    for (var i = 4 * 9; i < alpha.length; i++) {
      alpha[i] = 255;
    }
    final outline = SubjectMap(9, 16, alpha).outline(posterAspect: 9 / 16);
    expect(outline.top, closeTo(0.25, 0.02));
    expect(PosterPreset.stack.aboveHead(3, top: 0.25, headX: 0.5, halfWide: halfWide, halfTall: halfTall), isNull);
    for (final preset in [PosterPreset.scatter, PosterPreset.grid, PosterPreset.spotlight, PosterPreset.cascade]) {
      final poses = preset.aboveHead(4, top: 0.25, headX: 0.5, halfWide: halfWide, halfTall: halfTall)!;
      expect(poses, hasLength(4), reason: '$preset');
      for (final p in poses) {
        expect(p.at.dy - halfTall * p.scale, greaterThan(-0.01), reason: '$preset: the card top inside');
        expect(p.at.dy, lessThan(0.25), reason: '$preset: its middle above the person');
        expect(p.scale, greaterThan(0.25), reason: '$preset: big enough to see');
      }
    }
    final row = PosterPreset.grid.aboveHead(3, top: 0.25, headX: 0.5, halfWide: halfWide, halfTall: halfTall)!;
    final xs = [for (final p in row) p.at.dx]..sort();
    expect(xs[1] - xs[0], closeTo(xs[2] - xs[1], 0.001), reason: 'an even row');
  });

  testWidgets('Decor adds a sticker on top, picked; its colour changes, Undo takes it off again', (tester) async {
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
    await tester.tap(find.text('Decor'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byIcon(Icons.favorite_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.favorite_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(PosterDecorationView), findsOneWidget);
    expect(find.text('Colour'), findsOneWidget, reason: 'picked: its controls show');

    Color colour() =>
        tester.widget<Icon>(find.descendant(of: find.byType(PosterDecorationView), matching: find.byType(Icon))).color!;
    expect(colour().toARGB32(), Colors.white.toARGB32());
    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).color == decorationColours[3],
      ),
    );
    await tester.pumpAndSettle();
    expect(colour().toARGB32(), decorationColours[3].toARGB32());

    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(find.byType(PosterDecorationView), findsNothing);
  });

  test('a decoration keeps everything through a draft', () {
    final d =
        PosterDecoration(
            DecorationKind.text,
            at: const Offset(0.2, 0.7),
            scale: 1.5,
            tilt: 0.3,
            colour: decorationColours[4],
            text: 'hai',
          )
          ..opacity = 0.5
          ..locked = true
          ..visible = false;
    final back = PosterDecoration.fromJson(d.toJson());
    expect(
      [
        back.kind,
        back.at,
        back.scale,
        back.tilt,
        back.colour.toARGB32(),
        back.text,
        back.opacity,
        back.locked,
        back.visible,
      ],
      [d.kind, d.at, d.scale, d.tilt, d.colour.toARGB32(), d.text, d.opacity, d.locked, d.visible],
    );
  });

  group('two fingers and the wheel', () {
    late PlayerController c;
    final song = Track(id: 'a', uri: Uri.file('/music/a.flac'), title: 'About You', artist: 'The 1975');

    Future<void> open(WidgetTester tester, {Size size = const Size(1080, 2340), double ratio = 2.75}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = ratio;
      addTearDown(tester.view.reset);
      c = PlayerController();
      addTearDown(() async => tester.runAsync(() async => c.dispose()));
      await tester.pumpWidget(
        PlayerScope(
          controller: c,
          child: MaterialApp(home: PosterEditor(songs: [song])),
        ),
      );
      await tester.pump();
    }

    double cardWidth(WidgetTester tester) => tester.getSize(find.byType(PosterCard)).width;

    // A rendered card's on-screen width, through its transform.
    double shownWidth(WidgetTester tester) {
      final box = tester.renderObject<RenderBox>(find.byType(PosterCard));
      final a = box.localToGlobal(Offset.zero), b = box.localToGlobal(Offset(box.size.width, 0));
      return (b - a).distance;
    }

    testWidgets('one finger on a small decoration and one off it: the pinch sizes the decoration', (tester) async {
      await open(tester);
      await tester.tap(find.text('Decor'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.title_rounded).first, warnIfMissed: false);
      await tester.pumpAndSettle();
      // Text needs words: a sticker instead.
      if (find.byType(AlertDialog).evaluate().isNotEmpty) {
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.byIcon(Icons.star_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.star_rounded));
      await tester.pumpAndSettle();
      final sticker = find.byType(PosterDecorationView);
      final before = tester.getSize(sticker).width;
      final on = tester.getCenter(sticker);
      final first = await tester.startGesture(on);
      final second = await tester.startGesture(on + const Offset(60, 60));
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await second.moveBy(const Offset(6, 6));
        await tester.pump();
      }
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(tester.getSize(sticker).width, greaterThan(before * 1.4));
    });

    testWidgets('a picked card is pinched from anywhere on the poster, the view not zoomed', (tester) async {
      await open(tester);
      await tester.tap(find.byType(PosterCard));
      await tester.pumpAndSettle();
      final before = shownWidth(tester);
      final poster = tester.getRect(find.byType(AspectRatio));
      final a = poster.bottomLeft + const Offset(40, -60), b = poster.bottomLeft + const Offset(120, -60);
      final first = await tester.startGesture(a);
      final second = await tester.startGesture(b);
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await second.moveBy(const Offset(8, 0));
        await tester.pump();
      }
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(shownWidth(tester), greaterThan(before * 1.5));
      expect(find.text('Fit'), findsNothing, reason: 'the poster itself not zoomed');
    });

    testWidgets('the wheel sizes the picked card; with Shift it turns it', (tester) async {
      await open(tester, size: const Size(1400, 900), ratio: 1);
      await tester.tap(find.byType(PosterCard));
      await tester.pumpAndSettle();
      final at = tester.getCenter(find.byType(PosterCard));
      final before = shownWidth(tester);
      tester.binding.handlePointerEvent(PointerScrollEvent(position: at, scrollDelta: const Offset(0, -300)));
      await tester.pumpAndSettle();
      expect(shownWidth(tester), greaterThan(before * 1.1));

      double turn() {
        final box = tester.renderObject<RenderBox>(find.byType(PosterCard));
        final d = box.localToGlobal(Offset(box.size.width, 0)) - box.localToGlobal(Offset.zero);
        return d.direction;
      }

      expect(turn().abs(), lessThan(0.2));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      tester.binding.handlePointerEvent(PointerScrollEvent(position: at, scrollDelta: const Offset(0, 300)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(turn().abs(), greaterThan(0.3));
      expect(cardWidth(tester), greaterThan(0));
    });
  });

  testWidgets('a mouse drag keeps the spot held under the pointer, past the middle and the edge and back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
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
    final card = find.byType(PosterCard);
    final start = tester.getCenter(card) + const Offset(-30, -60);
    final held = start - tester.getCenter(card);
    final mouse = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    // Slowly right through the middle, far out past the poster's right edge, then back in and down.
    for (var i = 0; i < 30; i++) {
      await mouse.moveBy(const Offset(3, 1));
      await tester.pump();
    }
    await mouse.moveBy(const Offset(900, 0));
    await tester.pump();
    await mouse.moveBy(const Offset(-900, 0));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await mouse.moveBy(const Offset(4, 9));
      await tester.pump();
    }
    final end = start + const Offset(90 + 40, 30 + 90);
    expect(((end - tester.getCenter(card)) - held).distance, lessThan(1.5), reason: 'the same spot under the pointer');
    await mouse.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a click beside the poster lets go of the picked card', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
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
    await tester.tap(find.byType(PosterCard));
    await tester.pumpAndSettle();
    expect(find.text('Size'), findsOneWidget);
    final poster = tester.getRect(find.byType(AspectRatio));
    await tester.tapAt(poster.centerLeft - const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(find.text('Size'), findsNothing);
  });
}
