import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
import 'package:riflay/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Translations run longer than English in places: Indonesian has longer words, Japanese full-width glyphs and no
// spaces to break at. The key screens in each at a phone width and a desktop width: an overflow is a FlutterError,
// which fails the test.

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

Widget _tree(PlayerController c, double width, String locale, Widget page) => PlayerScope(
  controller: c,
  child: MaterialApp(
    locale: Locale(locale),
    theme: buildAppTheme(),
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

  // The app's own font, so Latin words are as wide as on a device (the test font draws every letter a square).
  // Japanese has no glyphs in it and falls back to the square test font, which is about as wide as real kana.
  setUpAll(() async {
    final figtree = FontLoader('Figtree')
      ..addFont(File('assets/fonts/Figtree.ttf').readAsBytes().then(ByteData.sublistView));
    await figtree.load();
  });

  const sizes = [Size(360, 760), Size(1200, 800)];

  for (final language in [AppLanguage.japanese, AppLanguage.indonesian]) {
    Future<void> show(WidgetTester tester, Size size, Widget Function() page, {String Function()? shows}) async {
      SharedPreferences.setMockInitialValues({
        'library.v1': jsonEncode([_track.toJson()]),
      });
      await tester.runAsync(() => Language.instance.set(language));
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
      await tester.pumpWidget(_tree(c, size.width, language.code!, page()));
      await tester.pump(const Duration(milliseconds: 300));
      if (shows != null) {
        expect(find.textContaining(shows()), findsWidgets, reason: 'the screen is in ${language.name}');
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
      await tester.runAsync(() async => c.dispose());
    }

    for (final size in sizes) {
      final at = '${language.name} at ${size.width.toInt()}x${size.height.toInt()}';
      testWidgets('Home in $at', (tester) async {
        await show(tester, size, () => const HomePage(), shows: () => tr.allSongs);
      });
      testWidgets('Now Playing in $at', (tester) async {
        await show(tester, size, () => const NowPlayingPage(), shows: () => tr.playingFromCaps);
      });
      testWidgets('Settings and every group in $at', (tester) async {
        await show(tester, size, () => const SettingsPage(), shows: () => tr.groupLook);
        for (final g in SettingsGroup.values) {
          await show(tester, size, () => SettingsGroupPage(group: g), shows: () => g.label);
        }
      });
      testWidgets('every Settings page in $at', (tester) async {
        // The test binding pretends to be Android; the desktop-only pages need a desktop.
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          for (final s in SettingsTopic.values.where((s) => s.available && s != SettingsTopic.spotify)) {
            await show(tester, size, () => SettingsTopicPage(section: s), shows: () => s.label);
          }
          await show(tester, size, () => const SettingsPowerPage(), shows: () => tr.settingsPower);
          await show(tester, size, () => const SettingsAboutPage(), shows: () => tr.version);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
      testWidgets('Wrap and the stats page in $at', (tester) async {
        final h = _history();
        final d = MonthlyWrap.compute(h, const WrapMonth(2026, 3))!;
        await show(
          tester,
          size,
          () => WrapStory(data: d, trackFor: (s) => s.toTrack()),
          shows: () => tr.wrapMonthlyKicker,
        );
        await show(
          tester,
          size,
          () => ListeningStatsPage(history: h, now: DateTime(2026, 4, 15)),
          shows: () => tr.yourMonthlyWraps,
        );
      });
    }
  }
}
