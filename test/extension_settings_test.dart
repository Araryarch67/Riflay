import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riflay/services/extensions/extension_store.dart';
import 'package:riflay/ui/pages/extension_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'extension_store_test.dart' show manifest, sflx;

void main() {
  testWidgets('a suggested repository is added, its extensions listed, one installed and turned off', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // Tall enough that every row is on screen to tap.
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final root = Directory.systemTemp.createTempSync('riflay-ext-ui');
    addTearDown(() => root.deleteSync(recursive: true));
    final package = sflx({'manifest.json': manifest('demo', '1.0.0'), 'index.js': 'registerExtension({});'});
    final store = ExtensionStore(
      root: () async => root,
      runnerFor: (_, _) => throw StateError('nothing runs here'),
      client: MockClient((req) async {
        if (req.url.toString() == officialRegistry) {
          return http.Response(
            jsonEncode({
              'extensions': [
                {
                  'id': 'demo',
                  'display_name': 'Demo Music',
                  'version': '1.0.0',
                  'description': 'Finds demo songs.',
                  'download_url': 'https://repo.example/demo.sflx',
                  'sha256': ExtensionStore.sha256Hex(package),
                },
              ],
            }),
            200,
          );
        }
        if (req.url.path == '/demo.sflx') return http.Response.bytes(package, 200);
        return http.Response('', 404);
      }),
    );

    // Loaded outside the test's fake clock: its file reads would never finish inside it.
    await tester.runAsync(store.load);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ExtensionSettings(store: store))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mornye (official)'), findsOneWidget);
    expect(find.text('zarzet (community)'), findsOneWidget);
    expect(find.text('No extensions yet'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Mornye (official)'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(store.repositories, [officialRegistry]);
    expect(find.textContaining('1 extension'), findsOneWidget);
    expect(find.text('Demo Music  1.0.0'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Install'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
    expect(store.installedOf('demo')?.enabled, isTrue);
    expect(find.text('No extensions yet'), findsNothing);
    expect(find.textContaining('Adds results to Search'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byType(Switch));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(store.installedOf('demo')?.enabled, isFalse);
  });
}
