import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/audio_engine.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/sleep_timer.dart';
import 'package:riflay/ui/pages/sound_settings.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/sleep_timer_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(PlayerController c, Widget body) => MaterialApp(
  home: PlayerScope(
    controller: c,
    child: ShellScope(
      compact: false,
      width: 900,
      open: (_, {location}) {},
      openCollection: (_) {},
      openQueue: () {},
      openNowPlaying: () {},
      openLyrics: () {},
      openDownloads: () {},
      importFromYoutube: () {},
      addFiles: () {},
      addFolder: null,
      child: Scaffold(body: SingleChildScrollView(child: body)),
    ),
  ),
);

void main() {
  void onLinux(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  group('sleep timer in the player', () {
    for (final width in const <double>[400, 1000]) {
      onLinux('${width.toInt()} wide: pick a length, see the time left, add 10 minutes, cancel', (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final c = PlayerController();

        await tester.pumpWidget(_app(c, const Center(child: SleepTimerButton())));
        expect(find.byTooltip('Sleep timer'), findsOneWidget);

        await tester.tap(find.byTooltip('Sleep timer'));
        await tester.pumpAndSettle();
        for (final label in ['15 minutes', '30 minutes', '45 minutes', '60 minutes', '90 minutes']) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
        expect(find.text('End of this song'), findsOneWidget);
        expect(find.text('Custom time'), findsOneWidget);

        await tester.tap(find.text('30 minutes'));
        await tester.pumpAndSettle();
        expect(c.sleep.mode, SleepMode.countdown);
        expect(find.text('30 minutes'), findsNothing, reason: 'the sheet closed');
        // The time left shows beside the moon.
        expect(find.text('30:00'), findsOneWidget);
        expect(find.byTooltip('Sleep timer: 30:00'), findsOneWidget);

        await tester.tap(find.byTooltip('Sleep timer: 30:00'));
        await tester.pumpAndSettle();
        expect(find.textContaining('The music stops in'), findsOneWidget);
        await tester.tap(find.text('Add 10 minutes'));
        await tester.pump();
        expect(c.sleep.remaining!.inMinutes, inInclusiveRange(39, 40));
        await tester.tap(find.text('Cancel timer'));
        await tester.pumpAndSettle();
        expect(c.sleep.active, isFalse);
        expect(find.byTooltip('Sleep timer'), findsOneWidget);
      });
    }

    onLinux('End of this song is shown as such', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final c = PlayerController();
      await tester.pumpWidget(_app(c, const Center(child: SleepTimerButton())));
      await tester.tap(find.byTooltip('Sleep timer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End of this song'));
      await tester.pumpAndSettle();
      expect(c.sleep.mode, SleepMode.endOfSong);
      expect(find.text('End of song'), findsOneWidget);
      c.sleep.cancel();
    });

    onLinux('a custom time', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final c = PlayerController();
      await tester.pumpWidget(_app(c, const Center(child: SleepTimerButton())));
      await tester.tap(find.byTooltip('Sleep timer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom time'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Hours'), '1');
      await tester.enterText(find.widgetWithText(TextField, 'Minutes'), '5');
      await tester.pump();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(c.sleep.remaining!.inMinutes, inInclusiveRange(64, 65));
      c.sleep.cancel();
    });

    onLinux('the label goes under the moon on a tight row', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final c = PlayerController();
      c.sleep.start(const Duration(minutes: 15));
      await tester.pumpWidget(_app(c, const Center(child: SleepTimerButton(labelBelow: true))));
      expect(find.text('15:00'), findsOneWidget);
      c.sleep.cancel();
    });
  });

  group('Settings › Sound › Playback', () {
    onLinux('Crossfade is off; turning it on shows the length and "Skip for albums"', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = PlayerController();
      await tester.pumpWidget(_app(c, const PlaybackSettings()));
      expect(find.text('Crossfade'), findsOneWidget, skip: !AudioEngine.supported);
      expect(c.audio.crossfade, isFalse);
      expect(find.text('Fade length'), findsNothing);
      expect(find.text('Skip for albums'), findsNothing);

      await tester.tap(find.text('Crossfade'));
      await tester.pumpAndSettle();
      expect(c.audio.crossfade, isTrue);
      expect(find.text('Fade length'), findsOneWidget);
      expect(find.text('5 s'), findsWidgets);
      expect(find.text('Skip for albums'), findsOneWidget);
      expect(c.audio.crossfadeSkipAlbums, isTrue, reason: 'on by default');

      await tester.tap(find.text('Skip for albums'));
      await tester.pumpAndSettle();
      expect(c.audio.crossfadeSkipAlbums, isFalse);

      // Let the coalesced save finish, so no timer is left running.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    });

    onLinux('bit-perfect mode turns it off and the subtitle says so', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = PlayerController();
      c.audio.crossfade = true;
      c.audio.bitPerfectWanted = true;
      await tester.pumpWidget(_app(c, const PlaybackSettings()));
      expect(c.audio.bitPerfect, isTrue);
      expect(find.text('Off while bit-perfect mode is on'), findsWidgets);
      expect(find.text('Fade length'), findsNothing);
      final tile = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Crossfade'));
      expect(tile.onChanged, isNull);
    });
  });
}
