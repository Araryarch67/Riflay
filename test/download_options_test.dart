import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/download_prefs.dart';
import 'package:riflay/ui/download_options.dart';

// 250 seconds of Opus 128 kbps (4,000,000 bytes) and AAC 130 kbps.
const _offered = [
  AudioCandidate(id: '251', opus: true, kbps: 128, sizeBytes: 4000000),
  AudioCandidate(id: '140', opus: false, kbps: 130, sizeBytes: 4062500),
];

Future<Future<DownloadChoice?>> _open(
  WidgetTester tester, {
  required DownloadChoice initial,
  Future<List<AudioCandidate>>? candidates,
  bool mp3 = true,
  bool flac = true,
  bool ffmpeg = true,
}) async {
  tester.view.physicalSize = const Size(600, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late BuildContext host;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          host = context;
          return const Scaffold();
        },
      ),
    ),
  );
  final result = showDialog<DownloadChoice>(
    context: host,
    builder: (_) => DownloadOptionsDialog(
      initial: initial,
      candidates: candidates,
      canMakeMp3: mp3,
      canMakeFlac: flac,
      canReencode: ffmpeg,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return result;
}

Finder _chip(String startsWith) =>
    find.byWidgetPredicate((w) => w is ChoiceChip && w.label is Text && (w.label as Text).data!.startsWith(startsWith));

bool _selected(WidgetTester tester, Finder chip) => tester.widget<ChoiceChip>(chip).selected;

void main() {
  testWidgets('each bitrate shows its size once the formats are known', (tester) async {
    await _open(tester, initial: const DownloadChoice(DownloadFormat.opus), candidates: Future.value(_offered));
    await tester.pump();
    expect(find.text('Best available · ~3.8 MB'), findsOneWidget);
    expect(find.text('128 kbps · ~3.8 MB'), findsOneWidget, reason: 'YouTube\'s own stream is within 15%');
    expect(find.text('96 kbps · ~2.9 MB'), findsOneWidget, reason: '250 s at 96 kbps');
    expect(find.text('64 kbps · ~1.9 MB'), findsOneWidget);
  });

  testWidgets('chips spin while the formats are looked up, then show sizes', (tester) async {
    final found = Completer<List<AudioCandidate>>();
    await _open(tester, initial: const DownloadChoice(DownloadFormat.opus), candidates: found.future);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.textContaining('~'), findsNothing);
    found.complete(_offered);
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('~3.8 MB'), findsWidgets);
  });

  testWidgets('no sizes without a song (Download all) or when the lookup fails', (tester) async {
    await _open(tester, initial: const DownloadChoice(DownloadFormat.opus));
    expect(find.textContaining('~'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Best available'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
    final failing = Completer<List<AudioCandidate>>();
    await _open(tester, initial: const DownloadChoice(DownloadFormat.opus), candidates: failing.future);
    failing.completeError(StateError('offline'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('~'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the recommended choice is tagged and preselected for someone who never chose', (tester) async {
    await _open(tester, initial: recommendedChoice, candidates: Future.value(_offered));
    await tester.pump();
    expect(find.text('Recommended'), findsOneWidget);
    expect(_selected(tester, _chip('Best available')), isTrue);
    expect(
      tester.widget<RadioListTile<DownloadFormat>>(find.byType(RadioListTile<DownloadFormat>).first).value,
      DownloadFormat.opus,
    );
    final group = tester.widget<RadioGroup<DownloadFormat>>(find.byType(RadioGroup<DownloadFormat>));
    expect(group.groupValue, DownloadFormat.opus);
  });

  testWidgets('a saved choice is preselected', (tester) async {
    await _open(
      tester,
      initial: const DownloadChoice(DownloadFormat.m4a, kbps: 96),
      candidates: Future.value(_offered),
    );
    await tester.pump();
    expect(
      tester.widget<RadioGroup<DownloadFormat>>(find.byType(RadioGroup<DownloadFormat>)).groupValue,
      DownloadFormat.m4a,
    );
    expect(_selected(tester, _chip('96 kbps')), isTrue);
    expect(_selected(tester, _chip('Best available')), isFalse);
  });

  testWidgets('MP3 is offered only where it can be made, with sizes and a "best" of 192', (tester) async {
    await _open(tester, initial: const DownloadChoice(DownloadFormat.opus), mp3: false);
    expect(find.text('MP3'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));

    await _open(tester, initial: const DownloadChoice(DownloadFormat.opus), candidates: Future.value(_offered));
    await tester.pump();
    await tester.tap(find.text('MP3'));
    await tester.pump();
    expect(find.text('192 kbps (best) · ~5.7 MB'), findsOneWidget);
    expect(find.text('128 kbps · ~3.8 MB'), findsOneWidget);
    expect(find.text('96 kbps · ~2.9 MB'), findsOneWidget);
  });

  testWidgets('FLAC shows a size for each quality', (tester) async {
    await _open(
      tester,
      initial: const DownloadChoice(DownloadFormat.flac),
      candidates: Future.value(_offered),
      ffmpeg: true,
    );
    await tester.pump();
    // 250 s: 16-bit / 48 kHz packs to 28.8 MB, 24-bit to 43.2 MB.
    expect(find.text('16-bit / 48 kHz · ~27.5 MB'), findsOneWidget);
    expect(find.text('24-bit / 48 kHz · ~41.2 MB'), findsOneWidget);
  });

  testWidgets('Download hands back the choice made', (tester) async {
    final result = await _open(
      tester,
      initial: const DownloadChoice(DownloadFormat.opus),
      candidates: Future.value(_offered),
    );
    await tester.pump();
    await tester.tap(find.text('MP3'));
    await tester.pump();
    await tester.tap(_chip('128 kbps'));
    await tester.pump();
    await tester.tap(find.text('Download'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(await result, const DownloadChoice(DownloadFormat.mp3, kbps: 128));
  });
}
