import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// liquid_glass_renderer draws its real glass (refraction, dispersion, rim light) with Flutter GPU. Where Flutter
/// GPU is off it silently draws FakeGlass, a flat tinted pill, while `ImageFilter.isShaderFilterSupported` is still
/// true on Impeller, so the phone bar never takes Riflay's own shader-free glass either.
void main() {
  test('Android turns on Flutter GPU for the liquid glass', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(
      RegExp(r'android:name="io\.flutter\.embedding\.android\.EnableFlutterGPU"\s*android:value="true"')
          .hasMatch(manifest),
      isTrue,
    );
    expect(
      RegExp(r'android:name="io\.flutter\.embedding\.android\.EnableImpeller"\s*android:value="false"')
          .hasMatch(manifest),
      isFalse,
      reason: 'Flutter GPU needs Impeller',
    );
  });

  test('iOS turns on Flutter GPU for the liquid glass', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(RegExp(r'<key>FLTEnableFlutterGPU</key>\s*<true/>').hasMatch(plist), isTrue);
  });
}
