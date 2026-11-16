import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/desktop_visibility.dart';

void main() {
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
}
