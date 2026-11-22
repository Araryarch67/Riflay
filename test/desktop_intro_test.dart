import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/l10n/generated/app_localizations.dart';
import 'package:riflay/platform/host.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/splash_window.dart';
import 'package:riflay/ui/widgets/desktop_intro.dart';
import 'package:riflay/ui/widgets/startup_splash.dart';

const _home = ValueKey('home');

Widget _app(Future<void> ready, {bool intro = true}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: StartupSplash(
    ready: ready,
    intro: intro,
    child: const SizedBox(key: _home),
  ),
);

void main() {
  testWidgets('native phone-sized launch uses animated logo and stops drawing when Home opens', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final motion = LayoutPrefs.instance.motion;
    final performance = LayoutPrefs.instance.performance;
    LayoutPrefs.instance.motion = Motion.full;
    LayoutPrefs.instance.performance = PerformanceMode.balanced;
    addTearDown(() {
      LayoutPrefs.instance.motion = motion;
      LayoutPrefs.instance.performance = performance;
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StartupSplash(
          ready: Future<void>.value(),
          child: const SizedBox(key: _home),
        ),
      ),
    );
    expect(find.byType(DesktopIntro), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(_home), findsOneWidget);
    expect(find.byKey(const ValueKey('intro')), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plays the whole intro, then opens Home once', (tester) async {
    await tester.pumpWidget(_app(Future<void>.value()));
    expect(find.byType(DesktopIntro), findsOneWidget);
    expect(find.byKey(_home), findsNothing);
    await tester.pump(); // the first frame starts the clock
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.byKey(_home), findsNothing);
    expect(find.byKey(const ValueKey('intro')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1000)); // past the hold: the exit begins, Home under it
    expect(find.byKey(_home), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(_home), findsOneWidget);
    expect(find.byKey(const ValueKey('intro')), findsNothing);
  });

  testWidgets('a click skips to the end', (tester) async {
    await tester.pumpWidget(_app(Future<void>.value()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tapAt(const Offset(400, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byKey(_home), findsOneWidget);
    expect(find.byKey(const ValueKey('intro')), findsNothing);
  });

  testWidgets('any key skips too', (tester) async {
    await tester.pumpWidget(_app(Future<void>.value()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.byKey(_home), findsOneWidget);
  });

  testWidgets('a slow library load keeps the mark breathing until ready', (tester) async {
    final ready = Completer<void>();
    await tester.pumpWidget(_app(ready.future));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(_home), findsNothing);
    expect(find.byKey(const ValueKey('intro')), findsOneWidget);
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(_home), findsOneWidget);
  });

  testWidgets('Home keeps its state when the intro on top of it goes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StartupSplash(ready: Future<void>.value(), intro: true, child: const _Counter()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2000)); // exiting: Home is built under the intro
    final state = tester.state(find.byType(_Counter));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(_Counter)), same(state));
  });

  testWidgets('closing during the intro leaves nothing running', (tester) async {
    final ready = Completer<void>();
    await tester.pumpWidget(_app(ready.future));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox.shrink());
    ready.complete();
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Linux transparent intro hands off without changing the native window', (tester) async {
    final nativeCalls = <MethodCall>[];
    const channel = MethodChannel('window_manager');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call);
      return true;
    });
    addTearDown(() {
      SplashWindow.active.value = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });
    expect(await SplashWindow.open(appSize: const Size(1280, 820), appMinimum: const Size(320, 420)), isTrue);
    await tester.pumpWidget(_app(Future<void>.value()));
    expect(tester.widget<DesktopIntro>(find.byType(DesktopIntro)).transparent, isTrue);
    expect(SplashWindow.active.value, isTrue);
    expect(find.byKey(_home), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byKey(_home), findsOneWidget);
    expect(SplashWindow.active.value, isFalse);
    expect(nativeCalls, isEmpty);
  }, skip: !Host.isLinux);

  testWidgets('without the intro the plain mark shows instead', (tester) async {
    await tester.pumpWidget(_app(Future<void>.value(), intro: false));
    expect(find.byType(DesktopIntro), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(_home), findsOneWidget);
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
