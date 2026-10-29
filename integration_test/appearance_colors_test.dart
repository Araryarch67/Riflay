// "Colours from cover art: Whole app" and the custom colours of Settings › Look & feel › Appearance.
//
// Plays songs with two different solid-ish covers in a throwaway library, measures how much a song
// change costs in each mode (frame build times and app-wide restyles), and takes pictures when SHOTS is set:
//
//   env -u DISPLAY WAYLAND_DISPLAY=om-theme GDK_BACKEND=wayland XDG_DATA_HOME=/tmp/x PIPEWIRE_REMOTE=om-none \
//     PULSE_SERVER=unix:/nonexistent dbus-run-session -- flutter test integration_test/appearance_colors_test.dart \
//     -d linux --dart-define=SHOTS=/tmp/om-theme-shots
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer;
import 'package:riflay/main.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/services/color_tools.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const shots = String.fromEnvironment('SHOTS');

Future<void> _ffmpeg(List<String> args) async {
  final r = await Process.run('ffmpeg', ['-loglevel', 'error', '-y', ...args]);
  if (r.exitCode != 0) throw StateError('ffmpeg: ${r.stderr}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('whole-app cover colours', (tester) async {
    JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
    if (shots.isNotEmpty) Directory(shots).createSync(recursive: true);

    final dir = Directory.systemTemp.createTempSync('om-theme');
    addTearDown(() => dir.deleteSync(recursive: true));
    final files = <String>[];
    // Two albums, each with one solid-ish cover: a warm red and a deep blue.
    for (final (name, hex) in [('red', 'C0392B'), ('blue', '2E5FC0'), ('green', '2E8B57')]) {
      final cover = '${dir.path}/$name.jpg';
      await _ffmpeg(['-f', 'lavfi', '-i', 'color=c=0x$hex:s=600x600,noise=alls=10:allf=t', '-frames:v', '1', cover]);
      for (var t = 1; t <= 4; t++) {
        final f = '${dir.path}/${name}_$t.flac';
        await _ffmpeg([
          '-f', 'lavfi', '-i', 'sine=f=${200 + t * 30}:d=30', '-i', cover, '-map', '0', '-map', '1', //
          '-c:v', 'mjpeg', '-disposition:v', 'attached_pic',
          '-metadata', 'title=${name[0].toUpperCase()}${name.substring(1)} song $t', '-metadata', 'artist=Test Artist',
          '-metadata', 'album=${name[0].toUpperCase()}${name.substring(1)} album', '-metadata', 'track=$t', f,
        ]);
        files.add(f);
      }
    }
    SharedPreferences.setMockInitialValues({
      'library.v1': jsonEncode([for (final f in files..sort()) Track.fromUri(Uri.file(f)).toJson()]),
    });

    final c = PlayerController();
    final apply = JustAudioMediaKit.onPlayerCreated!;
    JustAudioMediaKit.onPlayerCreated = (p) async {
      await (p.platform as NativePlayer).setProperty('ao', 'null');
      apply(p);
    };
    await c.load();
    while (c.scanning) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final look = Appearance.instance;
    await look.reset();

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(child: RiflayApp(controller: c)));

    Future<void> settle([int ms = 800]) async {
      for (var i = 0; i < ms ~/ 50; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> shot(String name) async {
      await settle(900);
      if (shots.isEmpty) return;
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage();
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File('$shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    Track byTitle(String t) => c.allSongs.tracks.firstWhere((x) => x.title == t);

    await settle();
    await shot('1-default-nothing-playing');

    // Songs alternate between the red and blue albums.
    final queue = [
      for (var t = 1; t <= 4; t++) ...[byTitle('Red song $t'), byTitle('Blue song $t')],
    ];
    await tester.runAsync(() => c.playList(queue, 0, from: 'Test'));
    await settle(1500);

    // ── Cost of a song change: Player only (what it was) against Whole app ──
    final timings = <FrameTiming>[];
    SchedulerBinding.instance.addTimingsCallback(timings.addAll);
    var restyles = 0;
    void count() => restyles++;
    look.addListener(count);
    addTearDown(() => look.removeListener(count));

    Future<String> measure(String label, CoverColorMode mode) async {
      await look.setCoverMode(mode);
      await settle(1200);
      final build = <double>[], raster = <double>[];
      var frames = 0, n = 0;
      restyles = 0;
      for (var round = 0; round < 6; round++) {
        timings.clear();
        await tester.runAsync(() => c.playList(queue, round + 1, from: 'Test'));
        // ~1 s per change: the fade is 500 ms.
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          await Future<void>.delayed(const Duration(milliseconds: 16));
        }
        build.addAll(timings.map((t) => t.buildDuration.inMicroseconds / 1000));
        raster.addAll(timings.map((t) => t.rasterDuration.inMicroseconds / 1000));
        frames += timings.length;
        n++;
      }
      build.sort();
      raster.sort();
      double pct(List<double> l, double p) => l.isEmpty ? 0 : l[((l.length - 1) * p).round()];
      return '$label: $n song changes, $frames frames, build p50 ${pct(build, .5).toStringAsFixed(2)} '
          'p90 ${pct(build, .9).toStringAsFixed(2)} max ${pct(build, 1).toStringAsFixed(2)} ms, '
          'raster p90 ${pct(raster, .9).toStringAsFixed(2)} ms, app restyles per change ${(restyles / n).toStringAsFixed(1)}';
    }

    final lines = [
      await measure('Player only', CoverColorMode.player),
      await measure('Whole app ', CoverColorMode.app),
    ];
    for (final l in lines) {
      debugPrint('PERF $l');
    }
    if (shots.isNotEmpty) File('$shots/perf.txt').writeAsStringSync('${lines.join('\n')}\n');

    // ── Whole app, two covers ──
    await look.setCoverMode(CoverColorMode.app);
    await tester.runAsync(() => c.playList([byTitle('Red song 1')], 0, from: 'Test'));
    await settle(1200);
    expect(AppColors.accent, isNot(look.basePalette.accent), reason: 'the accent follows the cover');
    for (final s in [AppColors.panel, AppColors.elevated, AppColors.hover, AppColors.menu]) {
      expect(contrastRatio(AppColors.textPrimary, s.withValues(alpha: 1)), greaterThanOrEqualTo(4.5));
    }
    await shot('2-whole-app-red-cover');
    final red = AppColors.accent;
    await tester.runAsync(() => c.playList([byTitle('Blue song 1')], 0, from: 'Test'));
    await settle(1200);
    expect(AppColors.accent, isNot(red), reason: 'another cover, another accent');
    await shot('3-whole-app-blue-cover');

    // Nothing playing: the theme's own colours again.
    await tester.runAsync(c.player.stop);
    await tester.runAsync(() => c.playList(const [], 0));

    // ── Settings › Look & feel › Appearance ──
    await tester.runAsync(() => c.playList([byTitle('Green song 1')], 0, from: 'Test'));
    await settle(1200);
    await tester.tap(find.byTooltip('More'));
    await settle();
    await tester.tap(find.text('Settings').first);
    await settle();
    await tester.tap(find.text('Look & feel'));
    await settle();
    await tester.tap(find.text('Appearance'));
    await settle();
    await shot('4-appearance-whole-app-green');

    await tester.ensureVisible(find.bySemanticsLabel('Custom… accent'));
    await settle();
    await tester.tap(find.bySemanticsLabel('Custom… accent'));
    await settle();
    expect(find.text('Use this colour'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Hex'), '#E8590C');
    await shot('5-custom-accent-picker');
    await tester.tap(find.text('Use this colour'));
    await settle();
    expect(look.accent, AccentChoice.custom);
    // (flutter drive in profile mode doesn't deliver typed text to the field; flutter test does.)
    if (!kProfileMode) expect(look.customAccent, const Color(0xFFE8590C));

    // A light custom theme.
    await look.setCoverMode(CoverColorMode.off);
    await look.setCustomBackground(const Color(0xFFF2E8D5));
    await look.setCustomAccent(const Color(0xFF0B6E4F));
    expect(look.palette.light, isTrue);
    await shot('6-light-custom-theme');

    // Reset puts the default look back.
    await tester.ensureVisible(find.text('Reset to default'));
    await settle();
    await tester.tap(find.text('Reset to default'));
    await settle();
    expect(look.theme, ThemeChoice.standard);
    expect(look.coverMode, CoverColorMode.player);
    await shot('7-after-reset');
    await tester.runAsync(c.player.stop);
    JustAudioMediaKit.onPlayerCreated = apply;
  });
}
