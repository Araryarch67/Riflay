import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/ui/pages/appearance_settings.dart';
import 'package:riflay/ui/pages/listen_together_page.dart' show BetaBadge;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final look = Appearance.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await look.reset();
  });

  Future<void> open(WidgetTester tester, {double width = 1000}) async {
    tester.view.physicalSize = Size(width, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: const AppearanceSettings())),
      ),
    );
    await tester.pump();
  }

  testWidgets('Dynamic card is no longer Beta; choosing it hides Colours from cover art', (tester) async {
    await open(tester);
    expect(find.text('Dynamic'), findsOneWidget);
    expect(find.byType(BetaBadge), findsNothing);
    expect(find.text('Colours from cover art'), findsOneWidget);
    expect(find.text('Colour strength'), findsNothing);

    await tester.tap(find.text('Dynamic'));
    await tester.pump();
    expect(look.theme, ThemeChoice.dynamic);
    expect(find.text('Colours from cover art'), findsNothing);
    expect(find.text('Colour strength'), findsOneWidget);
    expect(find.text('Colours come from the cover of what\'s playing'), findsOneWidget);
  });

  testWidgets('theme cards sit two to a row on a phone', (tester) async {
    await open(tester, width: 360);
    final first = tester.getRect(find.bySemanticsLabel(RegExp('^Default theme')));
    final second = tester.getRect(find.bySemanticsLabel(RegExp('^Dynamic theme')));
    expect(second.top, first.top);
    expect(second.right, lessThanOrEqualTo(360 - 16 + 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mode picker switches brightness and is hidden for Custom', (tester) async {
    await open(tester);
    expect(find.text('Mode'), findsOneWidget);
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light').last);
    await tester.pumpAndSettle();
    expect(look.brightness, ThemeBrightness.light);

    await look.setTheme(ThemeChoice.custom);
    await tester.pump();
    expect(find.text('Mode'), findsNothing);
  });

  testWidgets('High contrast toggles', (tester) async {
    await open(tester);
    expect(look.highContrast, isFalse);
    await tester.tap(find.text('High contrast'));
    await tester.pump();
    expect(look.highContrast, isTrue);
  });
}
