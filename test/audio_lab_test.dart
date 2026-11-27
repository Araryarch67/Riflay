import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/audio_engine.dart';
import 'package:riflay/services/audio_lab.dart';
import 'package:riflay/services/auto_eq.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/pages/audio_lab_page.dart';

void main() {
  test('reads REW and squig.link text, AutoEQ CSV and semicolons, passing over comments and headers', () {
    final rew = AudioLab.parse(
      '* Measurement data measured by REW\n* Format: sweep\n20.3\t111.68\t175.4\n1000\t100.0\t12\n',
    );
    expect(rew.freqs, [20.3, 1000]);
    expect(rew.db, [111.68, 100.0]);
    final csv = AudioLab.parse('frequency,raw,smoothed\n20.00,-6.91,-6.92\n20.20,-6.87,-6.86\n');
    expect(csv.freqs, [20.0, 20.2]);
    expect(csv.db, [-6.91, -6.87]);
    final semi = AudioLab.parse('"Freq";"dB"\n2000;3,5\n100;1\n');
    expect(semi.freqs, [100, 2000], reason: 'sorted by frequency');
  });

  test('samples a curve straight between its points on a log scale, holding its ends', () {
    final c = (freqs: [100.0, 400.0], db: [0.0, 6.0]);
    final s = AudioLab.sample(c, [50, 100, 200, 400, 800]);
    expect(s[0], 0);
    expect(s[2], closeTo(3, 1e-9), reason: '200 Hz is halfway on a log scale');
    expect(s[4], 6);
  });

  test('the fitted equalizer takes out a bump the headphone has over the target', () {
    final freqs = AutoEq.fitFrequencies;
    final target = (freqs: freqs, db: List.filled(freqs.length, 0.0));
    // 6 dB too much around 3 kHz, an octave wide.
    final bump = [for (final f in freqs) 6 * math.exp(-math.pow(math.log(f / 3000) / math.ln2, 2) * 2)];
    final fit = AudioLab.fit((freqs: freqs, db: bump), target);
    var before = 0.0, after = 0.0;
    for (var i = 0; i < freqs.length; i++) {
      before = math.max(before, (fit.headphone[i] - fit.target[i]).abs());
      after = math.max(after, (fit.after[i] - fit.target[i]).abs());
    }
    expect(before, greaterThan(4), reason: "the bump, levelled in the midrange with the target");
    expect(after, lessThan(1.5));
    expect(fit.bands.any((b) => b.gain < -3 && b.frequency > 1500 && b.frequency < 6000), isTrue);
  });

  test('a squig.link phone book: each variant its own, files as left and right, sandboxes left out', () {
    const book = '''
[
  {"name": "_EQ", "phones": [{"name": "Sandbox", "file": "EQ sandbox"}]},
  {"name": "64 Audio", "phones": [
    {"name": "Aspire 1", "file": ["64 Audio Aspire 1", "64 Audio Aspire 1 deep"], "suffix": ["", "(insert: deep)"]},
    {"name": "U12t", "file": "64 Audio U12t"}
  ]}
]''';
    final phones = AudioLab.squigPhones(book, Uri.parse('https://squig.link/data/'), 'squig.link');
    expect(
      [for (final p in phones) p.name],
      ['64 Audio Aspire 1', '64 Audio Aspire 1 (insert: deep)', '64 Audio U12t'],
    );
    expect(phones.last.urls.map((u) => '$u'), [
      'https://squig.link/data/64%20Audio%20U12t%20L.txt',
      'https://squig.link/data/64%20Audio%20U12t%20R.txt',
    ]);
  });

  test("a squig.link config: its data folder, and the targets it lists that aren't commented out", () {
    const config = '''
const DIR = "data/",
      something = 1;
const targets = [
    { type:"Δ", files: [
        "∆ 5128DF",
//        "∆ Harman MoA 2025",
        "∆ JM-1 - 10dB Tilt"
    ]},
//    { type:"Δ", files:["Δ 10dB"] },
    { type:"Reference", files:["Super 22", "Harman IE 2019"] }
];
const other = { files: ["not a target"] };
''';
    expect(AudioLab.squigDir(config), 'data/');
    expect(AudioLab.squigTargetNames(config), ['∆ 5128DF', '∆ JM-1 - 10dB Tilt', 'Super 22', 'Harman IE 2019']);
  });

  test('a squig.link address, however typed, as the folder its files are in', () {
    expect('${AudioLab.squigBase('squig.link')}', 'https://squig.link/');
    expect('${AudioLab.squigBase('https://example.squig.link/lab')}', 'https://example.squig.link/lab/');
    expect(
      '${AudioLab.squigBase('https://example.squig.link/lab/index.html?share=x')}',
      'https://example.squig.link/lab/',
    );
  });

  test("an AutoEQ model's measurement is its results CSV; in-ears start with Harman's in-ear target", () {
    final iem = AudioLab.fromAutoEq(
      const AutoEqEntry(
        name: 'KZ ZSN Pro',
        path: 'crinacle/711%20in-ear/KZ%20ZSN%20Pro',
        source: 'crinacle',
        rig: '711',
      ),
    );
    expect('${iem.urls.single}', endsWith('/results/crinacle/711%20in-ear/KZ%20ZSN%20Pro/KZ%20ZSN%20Pro.csv'));
    expect(iem.inEar, isTrue);
    expect(AudioLab.defaultTarget(iem).name, 'Harman in-ear 2019');
  });

  for (final (name, size) in [('a phone', const Size(1080, 6000)), ('a wide window', const Size(1400, 2600))]) {
    testWidgets('the lab opens on $name with its sources and targets and nothing loaded yet', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = size.width > 1200 ? 1 : 2.75;
      addTearDown(tester.view.reset);
      final c = PlayerController();
      addTearDown(() async => tester.runAsync(() async => c.dispose()));
      await tester.pumpWidget(
        PlayerScope(
          controller: c,
          child: const MaterialApp(home: AudioLabPage()),
        ),
      );
      await tester.pump();
      expect(find.text('Audio Lab'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('No target (equalizer only)'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Pick a headphone'), findsOneWidget);
      expect(find.text('Use another headphone as the target'), findsOneWidget);
      await tester.tap(find.text('squig.link'));
      await tester.pump();
      expect(find.text('squig.link site'), findsOneWidget);
      expect(find.text('CSI Zone'), findsOneWidget);
      expect(find.text('Kuping Sensi'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets("dragging a band's point on the graph sets the equalizer, live, with no headphone or target", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = PlayerController();
    addTearDown(() async => tester.runAsync(() async => c.dispose()));
    await tester.pumpWidget(
      PlayerScope(
        controller: c,
        child: const MaterialApp(home: AudioLabPage()),
      ),
    );
    await tester.pump();
    final graph = tester.getRect(
      find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == '_GraphPainter'),
    );
    final before = c.audio.bands[5];
    // The 1 kHz point (the sixth of the ten) sits on the 0 dB line: drag it up.
    final from = Offset(
      graph.left + 34 + (graph.width - 34) * math.log(before.frequency / 20) / math.log(1000),
      graph.top + (graph.height - 18) * 15 / 35,
    );
    final drag = await tester.startGesture(from);
    for (var i = 0; i < 10; i++) {
      await drag.moveBy(const Offset(0, -8));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await drag.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(c.audio.bands[5].gain, greaterThan(3));
    expect(c.audio.eqEnabled, isTrue, reason: 'editing turns the equalizer on');
  });

  test('a target adjusted to taste: more bass below 100 Hz, a tilt brighter up top', () {
    final flat = List.filled(AutoEq.fitFrequencies.length, 0.0);
    double at(List<double> t, double f) => t[AutoEq.fitFrequencies.indexWhere((x) => x >= f)];
    final bass = AudioLab.adjusted(flat, bass: 6);
    expect(at(bass, 30) - at(bass, 1000), greaterThan(5));
    final tilt = AudioLab.adjusted(flat, tilt: 0.5);
    expect(at(tilt, 10000) - at(tilt, 1000), closeTo(0.5 * math.log(10) / math.ln2, 0.1));
  });

  test("the equalizer as AutoEQ's ParametricEQ.txt, with a preamp that keeps its peak from clipping", () {
    final text = AudioLab.parametricText(const [EqBand(105, 4, q: 0.7), EqBand(3000, -2.5, q: 2)]);
    final lines = text.split('\n');
    expect(lines.first, startsWith('Preamp: -'));
    expect(lines[1], 'Filter 1: ON PK Fc 105 Hz Gain 4.0 dB Q 0.70');
    expect(lines[2], 'Filter 2: ON PK Fc 3000 Hz Gain -2.5 dB Q 2.00');
  });

  testWidgets('a drag on the graph away from the points scrolls the page and leaves the equalizer alone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final c = PlayerController();
    addTearDown(() async => tester.runAsync(() async => c.dispose()));
    await tester.pumpWidget(
      PlayerScope(
        controller: c,
        child: const MaterialApp(home: AudioLabPage()),
      ),
    );
    await tester.pump();
    final graph = tester.getRect(
      find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == '_GraphPainter'),
    );
    final before = [for (final b in c.audio.bands) b.gain];
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    // Low on the graph, far below the bands' points on the 0 dB line.
    await tester.dragFrom(Offset(graph.center.dx, graph.bottom - 30), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(50), reason: 'the page scrolled');
    expect([for (final b in c.audio.bands) b.gain], before);
  });
}
