import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/desktop_visibility.dart';
import 'package:riflay/services/window_focus.dart';
import 'package:riflay/ui/player/mini_window.dart';

void main() {
  test('a docked player follows monitors to the left and above the primary display', () {
    const main = Rect.fromLTWH(0, 0, 1920, 1040);
    const left = Rect.fromLTWH(-1280, 300, 1280, 690);
    const top = Rect.fromLTWH(200, -900, 1440, 880);
    expect(nearestMonitorWorkArea(const Offset(-800, 400), [main, left, top]), left);
    expect(nearestMonitorWorkArea(const Offset(900, -500), [main, left, top]), top);
    expect(nearestMonitorWorkArea(const Offset(900, -15), [main, left, top]), top);
  });

  test('focus and Alt+Tab do not hide a shown window', () {
    final window = DesktopVisibility();
    addTearDown(window.dispose);
    window.onWindowBlur();
    window.onWindowEvent('blur');
    expect(window.value, isTrue);
    window.onWindowEvent('focus');
    expect(window.value, isTrue);
  });

  test('minimize stops rendering without requiring Flutter hidden', () {
    final window = DesktopVisibility();
    addTearDown(window.dispose);
    window.onWindowMinimize();
    expect(window.value, isFalse);
    window.onWindowEvent('show');
    window.onWindowFocus();
    expect(window.value, isFalse, reason: 'a minimized window must be restored first');
    window.onWindowRestore();
    expect(window.value, isTrue);
  });

  test('tray hide stays hidden until show, regardless of focus or restore', () {
    final window = DesktopVisibility();
    addTearDown(window.dispose);
    window.onWindowEvent('hide');
    window.onWindowFocus();
    window.onWindowRestore();
    expect(window.value, isFalse);
    window.onWindowEvent('show');
    expect(window.value, isTrue);
  });

  testWidgets('restoring an unfocused desktop window enables frames again', (tester) async {
    const channel = MethodChannel('window_manager');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    final window = DesktopVisibility.instance;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await WindowFocus.start();
    await tester.pump();
    expect(tester.binding.lifecycleState, AppLifecycleState.inactive);
    window.onWindowMinimize();
    await tester.pump();
    expect(tester.binding.lifecycleState, AppLifecycleState.hidden);
    expect(tester.binding.framesEnabled, isFalse);
    window.onWindowRestore();
    await tester.pump();
    expect(tester.binding.lifecycleState, AppLifecycleState.inactive);
    expect(tester.binding.framesEnabled, isTrue);
  });
}
