import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/app_updates.dart';
import 'package:riflay/ui/widgets/app_update_tile.dart';

import 'app_updates_test.dart' show releaseJson;

class FakeUpdates extends AppUpdates {
  FakeUpdates() : super(android: true);
  int checks = 0;
  int downloads = 0;
  int installs = 0;
  bool fail = false;
  String currentVersion = '1.9.9';

  @override
  Future<AppRelease> check() async {
    checks++;
    if (fail) throw StateError('Internal network details must stay out of the UI');
    installedVersion = currentVersion;
    return AppRelease.parse(releaseJson());
  }

  @override
  Future<String> download(AppRelease release, void Function(double) progress) async {
    downloads++;
    progress(0.5);
    if (fail) throw const FormatException('Bad APK');
    return '/cache/app-updates/update.apk';
  }

  @override
  Future<bool> install(String path) async {
    installs++;
    return true;
  }
}

void main() {
  testWidgets('an up-to-date install can check again without offering a download', (tester) async {
    final updates = FakeUpdates()..currentVersion = '1.10.0';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AppUpdateTile(updates: updates)),
      ),
    );
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(find.text("You're using the latest version"), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);
    expect(find.text('Download update'), findsNothing);
  });

  testWidgets('the popup from the check at start offers the found release, and Not now closes it', (tester) async {
    final updates = FakeUpdates();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showUpdatePopup(context, updates, AppRelease.parse(releaseJson())),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Version 1.10.0 is available'), findsOneWidget);
    expect(find.text('Download update'), findsOneWidget, reason: 'no second check');
    expect(updates.checks, 0);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(updates.downloads, 0);
  });

  testWidgets('updates happen only on tap: check, download, then system installer', (tester) async {
    final updates = FakeUpdates();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AppUpdateTile(updates: updates)),
      ),
    );
    expect(updates.checks, 0);
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(find.text('Version 1.10.0 is available'), findsOneWidget);
    expect(updates.downloads, 0);
    await tester.tap(find.text('Download update'));
    await tester.pumpAndSettle();
    expect(updates.downloads, 1);
    expect(updates.installs, 0);
    await tester.tap(find.text('Install update'));
    await tester.pumpAndSettle();
    expect(updates.installs, 1);
    expect(find.text('Complete the update in the Android installer'), findsOneWidget);
  });

  testWidgets('a failed check has a usable retry and hides internal error details', (tester) async {
    final updates = FakeUpdates()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AppUpdateTile(updates: updates)),
      ),
    );
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't check for updates. Try again"), findsOneWidget);
    expect(find.textContaining('Internal network'), findsNothing);
    updates.fail = false;
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(find.text('Download update'), findsOneWidget);
  });

  testWidgets('a corrupt download cannot open the installer and can be retried', (tester) async {
    final updates = FakeUpdates();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AppUpdateTile(updates: updates)),
      ),
    );
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    updates.fail = true;
    await tester.tap(find.text('Download update'));
    await tester.pumpAndSettle();
    expect(updates.installs, 0);
    expect(find.text("Couldn't verify the update. Try downloading it again"), findsOneWidget);
    updates.fail = false;
    await tester.tap(find.text('Download update'));
    await tester.pumpAndSettle();
    expect(find.text('Install update'), findsOneWidget);
  });
}
