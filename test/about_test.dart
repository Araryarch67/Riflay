import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/app_version.dart';
import 'package:riflay/ui/pages/about_settings.dart';

void main() {
  test('Windows client builds identify Windows 11 without relabeling servers', () {
    expect(systemVersionLabel('windows', 'Windows 10 Home 10.0 (Build 22631)'), 'Windows 11 Home 10.0 (Build 22631)');
    expect(systemVersionLabel('windows', '10.0.22000'), 'Windows 11 (10.0.22000)');
    expect(systemVersionLabel('windows', 'Windows 10 (Build 19045)'), 'Windows 10 (Build 19045)');
    expect(systemVersionLabel('windows', 'Windows Server 2025 (Build 26100)'), 'Windows Server 2025 (Build 26100)');
    expect(systemVersionLabel('windows', 'unknown'), 'unknown');
    expect(systemVersionLabel('linux', '10.0.26100'), '10.0.26100');
  });
  test('the version shown in About is the one in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*([^+\s]+)', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(appVersion, version, reason: 'bump lib/app_version.dart with pubspec.yaml');
  });

  testWidgets('About shows the version, its details and the links', (tester) async {
    tester.view.physicalSize = const Size(700, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: AboutSettings())),
      ),
    );
    expect(find.text('Version $appVersion'), findsOneWidget);
    expect(find.textContaining('Riflay $appVersion · '), findsOneWidget);
    expect(find.textContaining(' #'), findsNothing, reason: 'no kernel build line');
    for (final row in [
      'Check for updates',
      'Delete executables',
      "What's new",
      'Report a problem',
      'Source code',
      'Licence',
      'Open-source licences',
    ]) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
  });
}
