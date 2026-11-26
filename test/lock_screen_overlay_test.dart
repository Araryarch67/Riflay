import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/pages/lock_screen_lyrics_page.dart';

void main() {
  testWidgets('over the lock screen Back stays put, and Unlock asks the lock screen', (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('riflay/lock_screen'), (call) async {
      calls.add(call.method);
      return null;
    });
    final c = PlayerController();
    addTearDown(() async => tester.runAsync(() async => c.dispose()));
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      PlayerScope(
        controller: c,
        child: MaterialApp(navigatorKey: nav, home: const Scaffold(body: Text('The app'))),
      ),
    );
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const LockScreenLyricsPage()));
    await tester.pumpAndSettle();

    await nav.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(LockScreenLyricsPage), findsOneWidget, reason: 'the app stays behind the lock');
    expect(find.text('The app'), findsNothing);

    await tester.tap(find.text('UNLOCK'));
    expect(calls, ['unlock']);
  });
}
