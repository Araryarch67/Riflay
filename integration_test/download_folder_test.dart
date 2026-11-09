// Checks Android scoped storage using the app's real UID, including partial-file renames.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:riflay/services/download_prefs.dart';
import 'package:riflay/services/youtube_importer.dart';
import 'package:riflay/ui/pages/download_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android download folder writes, persists and resets', (tester) async {
    expect(Platform.isAndroid, isTrue);
    SharedPreferences.setMockInitialValues({});
    final prefs = DownloadPrefs.instance;
    await prefs.load();
    final folder = '/storage/emulated/0/Download/Riflay-check-${DateTime.now().microsecondsSinceEpoch}';
    addTearDown(() async {
      await prefs.setFolder(null);
      final dir = Directory(folder);
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    expect(await YoutubeImporter.canSaveIn(folder), isTrue);
    expect(await Directory(folder).list().toList(), isEmpty);
    await prefs.setFolder(folder);
    expect((await YoutubeImporter.downloadsDir()).path, folder);
    expect((await SharedPreferences.getInstance()).getString('downloads.folder'), folder);
    // The chosen folder must accept the same temporary file and rename as a real download.
    final partial = await File('$folder/song.opus.part').writeAsBytes([1, 2, 3]);
    final song = await partial.rename('$folder/song.opus');
    expect(await song.readAsBytes(), [1, 2, 3]);
    await song.delete();
    expect(await YoutubeImporter.canSaveIn('/proc/riflay-download-check'), isFalse);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DownloadSettings()))),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.scrollUntilVisible(find.text('Change'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text(folder), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await prefs.setFolder(null);
    expect((await YoutubeImporter.downloadsDir()).path, (await YoutubeImporter.defaultDownloadsDir()).path);
  });
}
