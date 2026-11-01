import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/audio_engine.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/stay_awake.dart';
import 'package:riflay/services/power_policy.dart';
import 'package:riflay/ui/pages/sound_settings.dart';
import 'package:riflay/ui/navigation.dart';
import 'package:riflay/ui/pages/settings_page.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings in a small app of its own: [open] pushes the page and writes down its location, as the shell does.
Widget _app(PlayerController c, List<String> visited, {bool compact = false}) {
  final navigator = GlobalKey<NavigatorState>();
  return MaterialApp(
    navigatorKey: navigator,
    builder: (context, child) => PlayerScope(
      controller: c,
      child: ShellScope(
        compact: compact,
        width: compact ? 400 : 900,
        open: (page, {location}) {
          visited.add(location ?? '');
          navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => page));
        },
        openCollection: (_) {},
        openQueue: () {},
        openNowPlaying: () {},
        openLyrics: () {},
        openDownloads: () {},
        importFromYoutube: () {},
        addFiles: () {},
        addFolder: null,
        child: child!,
      ),
    ),
    home: const SettingsPage(),
  );
}

class _PowerTestBackend implements PowerBackend {
  @override
  Future<void> apply(PowerLocks from, PowerLocks to) async {}
}

void main() {
  // The test binding pretends to be Android; the hi-fi page is a desktop one.
  void onLinux(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await body(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5)); // lets a page's delayed save run out
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  onLinux('the top level shows groups followed by Listen together', (tester) async {
    final c = PlayerController();
    await tester.pumpWidget(_app(c, []));
    final titles = [
      for (final t in ['Sound', 'Look & feel', 'Library & downloads', 'Accounts & services', 'Listen together'])
        tester.getTopLeft(find.text(t)).dy,
    ];
    expect(titles, orderedEquals([...titles]..sort()), reason: 'in this order');
    for (final gone in ['Appearance', 'Playback', 'Downloads', 'Privacy', 'Integrations', 'Account']) {
      expect(find.text(gone), findsNothing, reason: '$gone moved inside a group');
    }
  });

  onLinux('power has its own page and DSP owns crossfade and detailed controls', (tester) async {
    final c = PlayerController();
    final awake = await StayAwake.start(c, backend: _PowerTestBackend());
    final visited = <String>[];
    await tester.pumpWidget(_app(c, visited));
    await tester.tap(find.text('Power & background'));
    await tester.pumpAndSettle();
    expect(visited.last, 'settings:power');
    expect(find.text('Keep screen on'), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sound'));
    await tester.pumpAndSettle();
    expect(find.text('Power & background'), findsNothing);
    await tester.tap(find.text('Playback'));
    await tester.pumpAndSettle();
    expect(find.text('Autoplay'), findsOneWidget);
    expect(find.text('Crossfade'), findsNothing);
    expect(find.text('Keep screen on'), findsNothing);
    await tester.tap(find.text('Sound'));
    await tester.pumpAndSettle();
    c.audio.virtualSpeakers = true;
    c.audio.hrirPath = AudioEngine.hrirAsset;
    await tester.tap(find.text('Sound effects (DSP)'));
    await tester.pumpAndSettle();
    expect(find.text('Crossfade'), findsOneWidget);
    expect(find.text('Virtual speaker level'), findsOneWidget);
    final level = find.ancestor(of: find.text('Virtual speaker level'), matching: find.byType(SettingTile));
    tester.widget<Slider>(find.descendant(of: level, matching: find.byType(Slider))).onChanged!(-3);
    await tester.pumpAndSettle();
    expect(c.audio.virtualSpeakerGain, -3);
    expect(find.text('-3.0 dB'), findsOneWidget);
    awake.dispose();
  });

  onLinux('Beta Features opens its own page with audio analysis off by default', (tester) async {
    final c = PlayerController();
    final visited = <String>[];
    await tester.pumpWidget(_app(c, visited));
    await tester.tap(find.text('Beta Features'));
    await tester.pumpAndSettle();
    expect(visited.last, 'settings:beta');
    final toggle = find.widgetWithText(SwitchListTile, 'Audio visualizer');
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.text('Visualizer style'), findsNothing);
  });

  onLinux('each group lists its sections', (tester) async {
    final c = PlayerController();
    final visited = <String>[];
    await tester.pumpWidget(_app(c, visited));
    final expected = {
      'Sound': [
        'Playback',
        if (AudioEngine.supported) ...['Sound effects (DSP)', 'Output & quality'],
      ],
      'Look & feel': ['Appearance', 'Layout'],
      'Library & downloads': ['Library', 'Downloads', 'Listening history & Wrap', 'Backup & restore'],
      'Accounts & services': [
        'YouTube Music account',
        'Spotify',
        'Last.fm & ListenBrainz',
        'Discord & lyrics services',
      ],
    };
    for (final MapEntry(key: group, value: rows) in expected.entries) {
      await tester.tap(find.text(group));
      await tester.pumpAndSettle();
      for (final r in rows) {
        expect(find.text(r), findsOneWidget, reason: '$r under $group');
      }
      expect(
        find.byIcon(Icons.chevron_right_rounded),
        findsNWidgets(rows.length + 1),
        reason: 'a chevron per row, and the trail',
      );
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
    }
    expect(visited, [
      for (final g in SettingsGroup.values) ...[g.location, Locations.settings],
    ]);
  });

  onLinux('Spotify is listed under Accounts & services, no longer behind a Beta switch', (tester) async {
    final c = PlayerController();
    await tester.pumpWidget(_app(c, []));
    await tester.tap(find.text('Accounts & services'));
    await tester.pumpAndSettle();
    expect(find.text('YouTube Music account'), findsOneWidget);
    expect(find.text('Spotify'), findsWidgets);
  });

  onLinux('each section opens its page, with its own location and a trail back up', (tester) async {
    final c = PlayerController();
    final visited = <String>[];
    await tester.pumpWidget(_app(c, visited));

    // group, section, something only that page shows, location
    final cases = [
      ('Sound', 'Playback', 'Gapless playback', 'settings:sound/playback'),
      if (AudioEngine.supported) ('Sound', 'Sound effects (DSP)', 'Crossfade', 'settings:sound/dsp'),
      if (AudioEngine.supported) ('Sound', 'Output & quality', 'Output sample rate', 'settings:sound/hifi'),
      ('Look & feel', 'Appearance', 'Theme', 'settings:look/appearance'),
      ('Look & feel', 'Layout', 'Motion', 'settings:look/layout'),
      ('Library & downloads', 'Library', 'Find songs you have twice', 'settings:library/library'),
      ('Library & downloads', 'Downloads', 'Ask every time', 'settings:library/downloads'),
      (
        'Library & downloads',
        'Listening history & Wrap',
        'Keep a listening history on this device',
        'settings:library/history',
      ),
      ('Accounts & services', 'YouTube Music account', 'Sign in with Google', 'settings:accounts/youtube-music'),
      ('Accounts & services', 'Discord & lyrics services', 'Better Lyrics API key', 'settings:accounts/services'),
    ];
    for (final (group, section, marker, location) in cases) {
      visited.clear();
      await tester.tap(find.text(group));
      await tester.pumpAndSettle();
      await tester.tap(find.text(section));
      await tester.pumpAndSettle();
      expect(visited.last, location, reason: section);
      expect(find.text(marker, skipOffstage: false), findsWidgets, reason: '$section shows its own page');
      // The trail reads Settings › Group › Section: the group crumb leads back to the group.
      expect(find.text(group), findsOneWidget, reason: 'the trail names the group');
      await tester.tap(find.text(group));
      await tester.pumpAndSettle();
      expect(visited.last, 'settings:${location.split('/').first.split(':').last}');
      expect(find.text(section), findsOneWidget, reason: 'back on the $group page, $section listed');
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(visited.last, Locations.settings);
      expect(find.text('Listen together'), findsOneWidget);
    }
  });

  onLinux('Listen together sits under Settings, and every location is its own', (tester) async {
    final c = PlayerController();
    final visited = <String>[];
    await tester.pumpWidget(_app(c, visited));
    await tester.tap(find.text('Listen together'));
    await tester.pumpAndSettle();
    expect(visited.last, Locations.listen);
    expect(find.text('Start a session'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    final all = [
      Locations.settings,
      Locations.listen,
      for (final g in SettingsGroup.values) g.location,
      for (final t in SettingsTopic.values) t.location,
    ];
    expect(all.toSet().length, all.length, reason: 'the shell skips a page whose location is already on screen');
  });

  onLinux('on a phone, the trail and Back lead up one level at a time', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    final c = PlayerController();
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(c, [], compact: true));
    await tester.tap(find.text('Look & feel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel(RegExp('Settings, then Look & feel, then Appearance')), findsOneWidget);
    expect(find.text('Look & feel'), findsOneWidget);
    semantics.dispose();
  });
}
