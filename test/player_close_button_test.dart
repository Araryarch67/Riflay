import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/ui/player/player_parts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('composed player header hides the arrow and lets the user show it again', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = LayoutPrefs.instance;
    await prefs.reset();
    Future<void> render() => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerTopBar(from: 'Downloaded', trailing: null, key: UniqueKey()),
        ),
      ),
    );
    await render();
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
    await prefs.setShowPlayerClose(true);
    await render();
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    await prefs.reset();
  });
}
