import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/ui/widgets/app_logo.dart';
import 'package:riflay/ui/widgets/startup_splash.dart';

Widget _app(Future<void> ready) => MaterialApp(
  home: StartupSplash(
    ready: ready,
    child: const SizedBox(key: ValueKey('home')),
  ),
);

void main() {
  testWidgets('a fast launch shows the icon briefly then opens Home once', (tester) async {
    await tester.pumpWidget(_app(Future<void>.value()));
    expect(find.byType(AppLogo), findsOneWidget);
    expect(find.byKey(const ValueKey('home')), findsNothing);
    await tester.pump(const Duration(milliseconds: 499));
    expect(find.byType(AppLogo), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('home')), findsOneWidget);
    expect(find.byType(AppLogo), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('home')), findsOneWidget);
  });

  testWidgets('a slower library load keeps the icon until ready', (tester) async {
    final ready = Completer<void>();
    await tester.pumpWidget(_app(ready.future));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AppLogo), findsOneWidget);
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home')), findsOneWidget);
  });

  testWidgets('closing during startup cancels the timer', (tester) async {
    final ready = Completer<void>();
    await tester.pumpWidget(_app(ready.future));
    await tester.pumpWidget(const SizedBox.shrink());
    ready.complete();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
