import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/platform/native_calls.dart';

void main() {
  test('a process that draws nothing in software is not taken for one without a graphics card', () {
    // The test process never loads WARP: false everywhere, and the call itself must not throw on any platform.
    expect(windowsSoftwareRendering(), isFalse);
    expect(Platform.isWindows || !windowsSoftwareRendering(), isTrue);
  });
}
