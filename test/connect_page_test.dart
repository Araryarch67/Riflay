import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:riflay/services/connect/connect_controller.dart';
import 'package:riflay/services/connect/connect_host.dart';
import 'package:riflay/services/connect/connect_store.dart';
import 'package:riflay/ui/pages/connect_page.dart';
import 'package:riflay/ui/player_scope.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connect_support.dart';

void main() {
  late FakeBroker broker;
  late FakeConnectPlayer player;
  late ConnectHost host;
  late ConnectController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    broker = FakeBroker();
    player = FakeConnectPlayer()..queued.add(FakeConnectPlayer().remote);
    final store = ConnectStore(await SharedPreferences.getInstance());
    host = ConnectHost(
      player,
      openStore: () async => store,
      opener: broker.open,
      deviceName: 'Windows',
      stateDelay: const Duration(milliseconds: 10),
      backoff: (_) => const Duration(milliseconds: 20),
    );
    controller = ConnectController(
      openStore: () async => store,
      opener: broker.open,
      deviceName: 'Android 7QK2',
      backoff: (_) => const Duration(milliseconds: 20),
      hostSilence: const Duration(seconds: 30),
    );
  });

  /// Lets the real async work (preferences, the made-up broker) run, then draws what it changed.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pump();
  }

  Future<void> open(WidgetTester tester, {bool canHost = true}) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      controller.dispose();
      host.dispose();
    });
    await tester.pumpWidget(
      PlayerScope(
        controller: player,
        child: MaterialApp(
          home: ShellScope(
            compact: false,
            width: 900,
            open: (_, {location}) {},
            openCollection: (_) {},
            openQueue: () {},
            openNowPlaying: () {},
            openLyrics: () {},
            openDownloads: () {},
            importFromYoutube: ({url}) {},
            addFiles: () {},
            addFolder: null,
            child: ConnectPage(host: host, controller: controller, canHost: canHost),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('the pairing screen shows a code and QR, asks before allowing, and lists and revokes controllers', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('No device is paired yet.'), findsOneWidget);

    await tester.tap(find.text('Pair a device'));
    await settle(tester);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text(host.pairingCode!), findsOneWidget);
    expect(find.text('Stop pairing'), findsOneWidget);

    // Someone enters the code: nothing is allowed until the owner taps Allow.
    final other = ConnectController(
      openStore: () async => ConnectStore(await SharedPreferences.getInstance()),
      opener: broker.open,
      deviceName: 'iOS K3M9',
    );
    addTearDown(other.dispose);
    await tester.runAsync(() async {
      other.pair(host.pairingCode!).ignore();
      await until(() => host.pending != null);
    });
    await tester.pump();
    expect(find.text('iOS K3M9 wants to control Riflay on this computer.'), findsOneWidget);
    expect(host.controllers, isEmpty);

    await tester.tap(find.text('Allow'));
    await settle(tester);
    expect(find.text('iOS K3M9'), findsOneWidget);
    expect(find.text('Revoke access'), findsOneWidget);
    expect(find.text('Pairing code'), findsOneWidget, reason: 'the controller form below is still there');
    expect(find.byType(QrImageView), findsNothing, reason: 'a used code is gone');

    await tester.tap(find.text('Revoke access'));
    await settle(tester);
    expect(find.text('No device is paired yet.'), findsOneWidget);
  });

  testWidgets('declining ends the pairing and the controller is told', (tester) async {
    await open(tester);
    await tester.tap(find.text('Pair a device'));
    await settle(tester);
    final other = ConnectController(
      openStore: () async => ConnectStore(await SharedPreferences.getInstance()),
      opener: broker.open,
      deviceName: 'iOS K3M9',
    );
    addTearDown(other.dispose);
    Object? problem;
    await tester.runAsync(() async {
      other.pair(host.pairingCode!).catchError((Object e) => problem = e);
      await until(() => host.pending != null);
    });
    await tester.pump();
    await tester.tap(find.text("Don't allow"));
    await settle(tester);
    expect(problem, isA<ConnectPairException>());
    expect(find.text('Pair a device'), findsOneWidget);
    expect(host.controllers, isEmpty);
  });

  testWidgets('the controller shows what is playing; after a drop it reads "Not connected" and the buttons are off', (
    tester,
  ) async {
    controller = ConnectController(
      openStore: () async => ConnectStore(await SharedPreferences.getInstance()),
      opener: broker.open,
      deviceName: 'Android 7QK2',
      backoff: (_) => const Duration(seconds: 30),
    );
    await open(tester);
    await tester.runAsync(() async {
      await host.beginPairing();
      await until(() => host.pairingCode != null);
      final pairing = controller.pair(host.pairingCode!);
      await until(() => host.pending != null);
      await host.approve();
      await pairing;
      await until(() => controller.state == ConnectLinkState.connected);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      broker.dropAll();
      await until(() => controller.state == ConnectLinkState.disconnected);
    });
    await tester.pump();
    expect(find.text('Not connected. Trying again…'), findsWidgets);
    expect(find.text('Windows'), findsWidgets);
    final play = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.play_arrow_rounded));
    expect(play.onPressed, isNull, reason: 'no command is sent into a dead link');
    expect(find.text('Remote song'), findsWidgets, reason: 'the last state stays on screen');
  });

  testWidgets('a code nobody answers is explained, and a device that cannot be controlled has no host section', (
    tester,
  ) async {
    controller = ConnectController(
      openStore: () async => ConnectStore(await SharedPreferences.getInstance()),
      opener: broker.open,
      pairTimeout: const Duration(milliseconds: 150),
    );
    await open(tester, canHost: false);
    expect(find.text('Allow remote control'), findsNothing);
    expect(find.text('Control a computer'), findsWidgets);
    await tester.enterText(find.byType(TextField), 'ABCDEFGHJK');
    await tester.pump();
    await tester.tap(find.text('Pair'));
    await tester.pump();
    expect(find.text('Waiting for the computer to confirm…'), findsOneWidget);
    // The wait runs on the test's own clock.
    await tester.pump(const Duration(milliseconds: 200));
    // The clean-up after the wait finishes on the real event loop.
    await settle(tester);
    expect(find.textContaining('No answer from the computer'), findsOneWidget);
  });
}
