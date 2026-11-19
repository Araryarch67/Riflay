import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:riflay/services/merged_download.dart';
import 'package:riflay/services/language.dart';
import 'package:riflay/services/network_settings.dart';
import 'package:riflay/services/sources/music_sources.dart';
import 'package:riflay/ui/pages/music_sources_settings.dart';
import 'package:riflay/ui/theme.dart';

void main() {
  for (final width in [360.0, 960.0]) {
    testWidgets('source settings omit storage controls and the proxy form fits at $width', (tester) async {
      SharedPreferences.setMockInitialValues({});
      late Directory directory;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('riflay-source-settings-');
        MergedDownload.keptFolder = directory.path;
        MusicSources.instance.reset();
        await MusicSources.instance.load();
        await NetworkSettings.instance.save(enabled: false, address: 'http://127.0.0.1:7890', bypass: '');
      });
      addTearDown(() async {
        MergedDownload.keptFolder = null;
        await directory.delete(recursive: true);
      });
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: SingleChildScrollView(child: MusicSourcesSettings())),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
      expect(find.byType(Slider), findsNothing);
      final proxy = find.widgetWithText(SwitchListTile, 'Network proxy');
      await tester.ensureVisible(proxy);
      await tester.tap(proxy);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(2));
      final address = find.byType(TextField).at(0);
      final bypass = find.byType(TextField).at(1);
      expect(tester.getBottomLeft(find.text(tr.networkProxyAddress)).dy, lessThan(tester.getTopLeft(address).dy));
      expect(tester.getBottomLeft(find.text(tr.networkProxyBypass)).dy, lessThan(tester.getTopLeft(bypass).dy));
      final save = find.widgetWithText(FilledButton, 'Save');
      await tester.enterText(address, 'invalid-address');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text(tr.networkProxyInvalid), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'http://127.0.0.1:8080');
      await tester.enterText(find.byType(TextField).at(1), '*.example.com');
      expect(find.text(tr.networkProxyInvalid), findsNothing);
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(NetworkSettings.instance.enabled, isTrue);
      expect(NetworkSettings.instance.route(Uri.parse('https://cdn.example.com')), 'DIRECT');
      expect(NetworkSettings.instance.route(Uri.parse('https://music.youtube.com')), 'PROXY 127.0.0.1:8080');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
