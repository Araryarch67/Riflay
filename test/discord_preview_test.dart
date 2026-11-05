import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/widgets/discord_preview.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('the preview shows what Discord gets, and follows the options', (tester) async {
    SharedPreferences.setMockInitialValues({'library.v1': jsonEncode(<Object>[])});
    final c = PlayerController();
    await tester.runAsync(c.load);
    tester.view.physicalSize = const Size(420, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      PlayerScope(
        controller: c,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(body: SingleChildScrollView(child: DiscordPresenceSettings())),
        ),
      ),
    );
    await tester.pump();
    // Nothing plays: a sample song, so the options can be tried.
    expect(find.text('Your song'), findsWidgets);
    expect(find.text('LISTENING TO RIFLAY'), findsOneWidget);
    expect(find.text('Download Riflay'), findsOneWidget);

    await tester.tap(find.text('"Download Riflay" button'));
    await tester.pump();
    expect(find.text('Download Riflay'), findsNothing, reason: 'the button left the card at once');
    expect(c.discordOptions.appButton, isFalse);

    await tester.tap(find.text('Song title in the member list'));
    await tester.pump();
    expect(
      find.text('Listening to Riflay', findRichText: true),
      findsOneWidget,
      reason: 'the member list now names the app',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async => c.dispose());
  });
}
