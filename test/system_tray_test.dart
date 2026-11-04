import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/platform/tray.dart';
import 'package:riflay/services/system_tray.dart';
import 'package:riflay/ui/debug_switches.dart';
import 'package:riflay/ui/widgets/power_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CloseToTray.instance.load();
  });

  tearDown(() {
    DebugSwitches.noTray = false;
    SystemTray.available.value = null;
  });

  group('Close to tray setting', () {
    test('is on by default', () {
      expect(CloseToTray.instance.enabled, isTrue);
      expect(CloseToTray.instance.active, isTrue);
    });

    test('turning it off is kept for the next start', () async {
      await CloseToTray.instance.setEnabled(false);
      expect((await SharedPreferences.getInstance()).getBool('window.closeToTray.v1'), isFalse);

      await CloseToTray.instance.load();
      expect(CloseToTray.instance.enabled, isFalse);
      await CloseToTray.instance.setEnabled(true);
    });

    test('RIFLAY_NO_TRAY turns it off whatever the setting says', () {
      DebugSwitches.noTray = true;
      expect(CloseToTray.instance.enabled, isTrue);
      expect(CloseToTray.instance.active, isFalse);
      expect(SystemTray.offered, isFalse);
    });
  });

  group('closing the window', () {
    Future<List<String>> close({required bool on}) async {
      final calls = <String>[];
      WindowCloseHandler(
        hideOnClose: () => on,
        hide: () async => calls.add('hide'),
        quit: () async => calls.add('quit'),
      ).onWindowClose();
      await Future<void>.delayed(Duration.zero);
      return calls;
    }

    test('hides Riflay in the tray while Close to tray is on', () async {
      expect(await close(on: true), ['hide']);
    });

    test('quits while it is off', () async {
      expect(await close(on: false), ['quit']);
    });
  });

  group('tray menu', () {
    List<TrayEntry> menu(TrayState s) =>
        trayMenu(s, toggleWindow: () {}, playPause: () {}, previous: () {}, next: () {}, quit: () {});
    TrayEntry find(List<TrayEntry> m, String label) => m.firstWhere((e) => e.label == label);

    test('shows the song and Pause while it plays', () {
      final m = menu((windowShown: true, song: 'Song · Artist', playing: true, hasNext: true));
      expect(m.first.label, 'Hide Riflay');
      expect(find(m, 'Song · Artist').enabled, isFalse, reason: 'the song is a label, not a button');
      expect(find(m, 'Pause').enabled, isTrue);
      expect(find(m, 'Previous').enabled, isTrue);
      expect(find(m, 'Next').enabled, isTrue);
      expect(find(m, 'Quit Riflay').enabled, isTrue);
    });

    test('greys out the controls with nothing to play', () {
      final m = menu((windowShown: false, song: null, playing: false, hasNext: false));
      expect(m.first.label, 'Show Riflay');
      expect(find(m, 'Nothing playing').enabled, isFalse);
      expect(find(m, 'Play').enabled, isFalse);
      expect(find(m, 'Previous').enabled, isFalse);
      expect(find(m, 'Next').enabled, isFalse);
      expect(find(m, 'Quit Riflay').enabled, isTrue);
    });

    test('keeps a long song name to one menu line', () {
      expect(traySongLabel('Title', ''), 'Title');
      expect(traySongLabel('Title', 'Artist'), 'Title · Artist');
      final long = traySongLabel('A' * 80, 'Artist');
      expect(long.length, 60);
      expect(long, endsWith('…'));
    });
  });

  group('Settings row', () {
    Future<void> pump(WidgetTester tester) =>
        tester.pumpWidget(const MaterialApp(home: Scaffold(body: CloseToTrayRow())));

    testWidgets('switches Close to tray off and on', (tester) async {
      SystemTray.available.value = true;
      await pump(tester);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);

      await tester.tap(find.text('Close to tray'));
      await tester.pumpAndSettle();
      expect(CloseToTray.instance.enabled, isFalse);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);

      await tester.tap(find.text('Close to tray'));
      await tester.pumpAndSettle();
      expect(CloseToTray.instance.enabled, isTrue);
    });

    testWidgets('explains a desktop without tray icons', (tester) async {
      SystemTray.available.value = false;
      await pump(tester);
      final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(tile.value, isFalse);
      expect(tile.onChanged, isNull);
      expect(find.textContaining('doesn\'t show tray icons'), findsOneWidget);
    });
  });
}
