import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/beta_features.dart';
import 'package:riflay/ui/pages/sound_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Direct USB is a beta that starts off, and only Android has it', () async {
    SharedPreferences.setMockInitialValues({});
    final b = BetaFeatures();
    await b.load();
    expect(BetaFeature.directUsb.defaultOn, isFalse);
    expect(BetaFeature.directUsb.available, isFalse, reason: 'these tests run on a computer');
    expect(b.isOn(BetaFeature.directUsb), isFalse);
  });

  Future<bool?> ask(WidgetTester tester, String button) async {
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) =>
              TextButton(onPressed: () async => answer = await confirmDirectUsb(context), child: const Text('open')),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Turn on Direct USB?'), findsOneWidget);
    expect(find.textContaining('full volume'), findsOneWidget);
    await tester.tap(find.text(button));
    await tester.pumpAndSettle();
    return answer;
  }

  testWidgets('the warning turns it on only when asked to', (tester) async {
    expect(await ask(tester, 'Turn on'), isTrue);
    expect(await ask(tester, 'Cancel'), isFalse);
  });
}
