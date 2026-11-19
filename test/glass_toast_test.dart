import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/ui/widgets/glass_toast.dart';

void main() {
  testWidgets('glass toasts keep actions and open their page when the message is tapped', (tester) async {
    final previous = LayoutPrefs.instance.performance;
    LayoutPrefs.instance.performance = PerformanceMode.balanced;
    addTearDown(() => LayoutPrefs.instance.performance = previous);
    final key = GlobalKey<ScaffoldMessengerState>();
    var opened = false;
    var restored = false;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => GlassToastMessenger(key: key, child: child!),
        home: const Scaffold(body: Center(child: Text('Home'))),
      ),
    );
    key.currentState!.showSnackBar(LinkedToast('Download ready', label: 'Downloads', open: () => opened = true));
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsOneWidget);
    await tester.tap(find.text('Download ready'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    expect(find.text('Download ready'), findsNothing);
    key.currentState!.showSnackBar(
      SnackBar(
        content: const Text('Removed'),
        action: SnackBarAction(label: 'Undo', onPressed: () => restored = true),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(restored, isTrue);
  });
}
