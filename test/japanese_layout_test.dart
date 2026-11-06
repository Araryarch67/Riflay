import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/services/language.dart';
import 'package:riflay/services/play_history.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/wrap.dart';
import 'package:riflay/ui/pages/home_page.dart';
import 'package:riflay/ui/pages/listening_stats_page.dart';
import 'package:riflay/ui/pages/settings_page.dart';
import 'package:riflay/ui/pages/wrap_page.dart';
import 'package:riflay/ui/player/now_playing_page.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Japanese runs longer per line than English in places (no spaces to break at, full-width glyphs). The key
// screens in Japanese at a phone width and a desktop width: an overflow is a FlutterError, which fails the test.

final _track = Track(
  id: 'ja-test',
  uri: Uri.parse('file:///ja-test.flac'),
  title: 'とても長い曲のタイトルがここに入る',
  artist: 'アーティスト名',
  album: 'アルバム名',
);

class _Player extends PlayerController {
  @override
  Track get currentTrack => _track;
  @override
  bool get canPlay => true;
  @override
  Duration? get duration => const Duration(minutes: 3);
}

PlayHistory _history() {
  final h = PlayHistory();
  for (var day = 1; day <= 20; day++) {
    h.record(_track, const Duration(seconds: 200), at: DateTime(2026, 3, day, 12));
  }
  return h;
}

Widget _tree(PlayerController c, double width, Widget page) => PlayerScope(
  controller: c,
  child: MaterialApp(
    locale: const Locale('ja'),
    home: ShellScope(
      compact: width < 700,
      width: width,
      open: (_, {location}) {},
      openCollection: (_) {},
      openQueue: () {},
      openNowPlaying: () {},
      openLyrics: () {},
      openDownloads: () {},
      importFromYoutube: ({url}) {},
      addFiles: () {},
      addFolder: null,
      child: Scaffold(body: page),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => Directory.systemTemp.path,
  );

  const sizes = [Size(360, 760), Size(1200, 800)];

  Future<void> show(WidgetTester tester, Size size, Widget Function() page, {String? shows}) async {
    SharedPreferences.setMockInitialValues({
      'library.v1': jsonEncode([_track.toJson()]),
    });
    await tester.runAsync(() => Language.instance.set(AppLanguage.japanese));
    addTearDown(() => tester.runAsync(() => Language.instance.set(AppLanguage.english)));
    final c = _Player();
    await tester.runAsync(c.load);
    // A music video background would start the video machinery: not what this is about.
    await tester.runAsync(() => Appearance.instance.setNowPlaying(NowPlayingBackground.color));
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final orig = FlutterError.onError;
    FlutterError.onError = (d) {
      final s = d.toString();
      if (!s.contains('google_fonts') && !s.contains('GoogleFonts') && !s.contains('MissingPlugin')) orig?.call(d);
    };
    addTearDown(() => FlutterError.onError = orig);
    await tester.pumpWidget(_tree(c, size.width, page()));
    await tester.pump(const Duration(milliseconds: 300));
    if (shows != null) expect(find.textContaining(shows), findsWidgets, reason: 'the screen is in Japanese');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    await tester.runAsync(() async => c.dispose());
  }

  for (final size in sizes) {
    final at = '${size.width.toInt()}x${size.height.toInt()}';
    testWidgets('Home in Japanese at $at', (tester) async {
      await show(tester, size, () => const HomePage(), shows: 'すべての曲');
    });
    testWidgets('Now Playing in Japanese at $at', (tester) async {
      await show(tester, size, () => const NowPlayingPage(), shows: '再生');
    });
    testWidgets('Settings and every group in Japanese at $at', (tester) async {
      await show(tester, size, () => const SettingsPage(), shows: '見た目と操作感');
      for (final g in SettingsGroup.values) {
        await show(tester, size, () => SettingsGroupPage(group: g), shows: g.label);
      }
    });
    testWidgets('Wrap and the stats page in Japanese at $at', (tester) async {
      final h = _history();
      final d = MonthlyWrap.compute(h, const WrapMonth(2026, 3))!;
      await show(tester, size, () => WrapStory(data: d, trackFor: (s) => s.toTrack()));
      await show(tester, size, () => ListeningStatsPage(history: h, now: DateTime(2026, 4, 15)));
    });
  }
}
