import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/download_prefs.dart';
import 'package:riflay/services/folder_watch.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/youtube_importer.dart';
import 'package:riflay/ui/pages/download_settings.dart';
import 'package:riflay/ui/pages/home_page.dart';
import 'package:riflay/ui/pages/library_settings.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Library extends PlayerController {
  @override
  List<Track> get library => [
    Track(
      id: 'file:///music/song.mp3',
      uri: Uri.file('/music/song.mp3'),
      title: 'Song',
      artist: 'Artist',
      tagged: true,
    ),
  ];
}

class _Picker extends FilePickerPlatform {
  String? chosen;
  String? initial;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    initial = initialDirectory;
    return chosen;
  }
}

Widget _app(Widget child, PlayerController c, VoidCallback add, double width) => MaterialApp(
  home: PlayerScope(
    controller: c,
    child: ShellScope(
      compact: width < 600,
      width: width,
      open: (_, {location}) {},
      openCollection: (_) {},
      openQueue: () {},
      openNowPlaying: () {},
      openLyrics: () {},
      openDownloads: () {},
      importFromYoutube: () {},
      addFiles: () {},
      addFolder: add,
      child: Scaffold(body: child),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Folder validation rejects duplicates and symlinks, but accepts another folder', () async {
    SharedPreferences.setMockInitialValues({});
    final root = Directory.systemTemp.createTempSync('riflay-folder-validation-');
    final first = Directory('${root.path}/First')..createSync();
    final second = Directory('${root.path}/Second')..createSync();
    final c = PlayerController();
    addTearDown(() async {
      for (final folder in FolderWatch.instance.folders) {
        if (folder.startsWith(root.path)) await FolderWatch.instance.forget(folder);
      }
      c.dispose();
      root.deleteSync(recursive: true);
    });
    expect(await c.scanFolder(first.path), 0);
    await expectLater(c.scanFolder(first.path), throwsA(isA<MusicFolderAlreadyAdded>()));
    await expectLater(c.scanFolder('${first.path}/../First/'), throwsA(isA<MusicFolderAlreadyAdded>()));
    if (!Platform.isWindows) {
      final alias = Link('${root.path}/Alias')..createSync(first.path);
      await expectLater(c.scanFolder(alias.path), throwsA(isA<MusicFolderAlreadyAdded>()));
    }
    expect(await c.scanFolder(second.path), 0);
    expect(FolderWatch.instance.folders.where((f) => f.startsWith(root.path)), hasLength(2));

    final missing = '${root.path}/Retry';
    await expectLater(c.scanFolder(missing), throwsA(isA<FileSystemException>()));
    expect(await FolderWatch.instance.containsFolder(missing), isFalse);
    Directory(missing).createSync();
    expect(await c.scanFolder(missing), 0, reason: 'a failed scan can be retried');

    final concurrent = Directory('${root.path}/Concurrent')..createSync();
    final results = await Future.wait([
      for (var i = 0; i < 2; i++)
        c.scanFolder(concurrent.path).then<Object>((count) => count, onError: (Object e) => e),
    ]);
    expect(results.whereType<int>(), [0]);
    expect(results.whereType<MusicFolderAlreadyAdded>(), hasLength(1));
  });

  for (final width in [400.0, 1200.0]) {
    testWidgets('Home can add another folder with existing music at $width px', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = _Library();
      var added = 0;
      await tester.pumpWidget(_app(const HomePage(), c, () => added++, width));
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('Add music'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add a folder'));
        await tester.pumpAndSettle();
      }
      expect(added, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    });
  }

  testWidgets('Library settings can add folders repeatedly', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = _Library();
    var added = 0;
    await tester.pumpWidget(_app(const SingleChildScrollView(child: LibrarySettings()), c, () => added++, 800));
    await tester.tap(find.text('Add a folder'));
    await tester.tap(find.text('Add a folder'));
    expect(added, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('Downloads loads the saved folder, changes it and keeps it on cancellation', (tester) async {
    final root = Directory.systemTemp.createTempSync('riflay-folders-');
    final first = Directory('${root.path}/First')..createSync();
    final second = Directory('${root.path}/Second folder')..createSync();
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(paths, (_) async => root.path);
    final originalPicker = FilePickerPlatform.instance;
    final picker = _Picker()..chosen = second.path;
    FilePickerPlatform.instance = picker;
    addTearDown(() async {
      FilePickerPlatform.instance = originalPicker;
      messenger.setMockMethodCallHandler(paths, null);
      await DownloadPrefs.instance.setFolder(null);
      root.deleteSync(recursive: true);
    });
    SharedPreferences.setMockInitialValues({'downloads.folder': first.path});
    // No explicit preferences load: the directory resolver must await it itself.
    expect((await tester.runAsync(YoutubeImporter.downloadsDir))!.path, first.path);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: DownloadSettings())),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    await tester.ensureVisible(find.text('Downloads folder'));
    final tile = tester.widget<ListTile>(
      find.ancestor(of: find.text('Downloads folder'), matching: find.byType(ListTile)),
    );
    await tester.runAsync(() => Future<void>.sync(tile.onTap!));
    await tester.pump();
    final folderView = tester.widget<FutureBuilder<Directory>>(find.byType(FutureBuilder<Directory>));
    await tester.runAsync(() => folderView.future!);
    await tester.pump();
    expect(picker.initial, first.path);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text(second.path), findsOneWidget);
    expect((await tester.runAsync(YoutubeImporter.downloadsDir))!.path, second.path);
    expect((await SharedPreferences.getInstance()).getString('downloads.folder'), second.path);
    expect(second.listSync(), isEmpty, reason: 'folder validation cleans up its probe');
    picker.chosen = null;
    await tester.tap(find.text('Downloads folder'));
    await tester.pumpAndSettle();
    expect((await tester.runAsync(YoutubeImporter.downloadsDir))!.path, second.path);
    final reset = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Reset'));
    await tester.runAsync(() => Future<void>.sync(reset.onPressed!));
    await tester.pump();
    final resetFolder = tester.widget<FutureBuilder<Directory>>(find.byType(FutureBuilder<Directory>));
    final defaultFolder = await tester.runAsync(() => resetFolder.future!);
    await tester.pump();
    expect(defaultFolder!.path, startsWith(root.path));
    expect(DownloadPrefs.instance.folder, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
