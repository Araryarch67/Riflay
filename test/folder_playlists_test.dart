import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/folder_watch.dart';
import 'package:riflay/services/library_views.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/folder_add_dialog.dart';
import 'package:riflay/ui/pages/library_page.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Paths in this platform's own form: folders are matched by path, with its separator.
final _root = p.join(Directory.systemTemp.path, 'riflay-folder-playlists');
final _rock = p.join(_root, 'Rock');
final _jazz = p.join(_root, 'Jazz');

Track _file(String path, String title) =>
    Track(id: Uri.file(path).toString(), uri: Uri.file(path), title: title, artist: 'Someone', tagged: true);

final _library = [
  _file(p.join(_rock, 'a.flac'), 'First rock song'),
  _file(p.join(_rock, 'Live', 'b.flac'), 'Live rock song'),
  _file(p.join(_jazz, 'c.flac'), 'Jazz song'),
  Track.youtube(videoId: 'zzz', title: 'Streamed song', artist: 'Someone'),
];

/// The music folders given here, and [playlistFolders] as the folder playlists.
class _Controller extends PlayerController {
  _Controller(this.tracks, this.playlistFolders);

  final List<Track> tracks;
  final List<String> playlistFolders;

  @override
  List<Collection> get folders => LibraryViews(tracks, 0).foldersOf([_rock, _jazz]);

  @override
  List<Collection> get folderPlaylists => LibraryViews.folderPlaylistsOf(folders, playlistFolders);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => Directory.systemTemp.path,
  );

  group('LibraryViews.folderPlaylistsOf', () {
    test('a folder playlist is the folder: its name, and the songs under it, subfolders included', () {
      final folders = LibraryViews(_library, 0).foldersOf([_rock, _jazz]);
      final lists = LibraryViews.folderPlaylistsOf(folders, [_rock]);
      expect(lists.single.title, 'Rock');
      expect(lists.single.kind, CollectionKind.folder);
      expect(lists.single.id, _rock);
      expect(lists.single.tracks.map((t) => t.title), [
        'Live rock song',
        'First rock song',
      ], reason: 'by path, as in Library › Local');
    });

    test('keeps the order they were made playlists in, and leaves out a folder no longer added', () {
      final folders = LibraryViews(_library, 0).foldersOf([_rock, _jazz]);
      final lists = LibraryViews.folderPlaylistsOf(folders, [_jazz, p.join(_root, 'Forgotten'), _rock]);
      expect(lists.map((l) => l.title), ['Jazz', 'Rock']);
    });

    test('follows the folder: songs added to it or gone from it change the playlist, nothing is copied', () {
      final now = [
        for (final t in _library)
          if (t.title != 'Live rock song') t,
        _file(p.join(_rock, 'New', 'd.flac'), 'New rock song'),
      ];
      final lists = LibraryViews.folderPlaylistsOf(LibraryViews(now, 1).foldersOf([_rock, _jazz]), [_rock]);
      expect(lists.single.tracks.map((t) => t.title), ['New rock song', 'First rock song']);
    });
  });

  test('FolderWatch keeps folder playlists, and forgetting the folder takes its playlist away', () async {
    SharedPreferences.setMockInitialValues({});
    final watch = FolderWatch.instance;
    final dir = Directory(_root)..createSync(recursive: true);
    addTearDown(() async {
      await watch.setPlaylist(_rock, false);
      for (final f in watch.folders.where((f) => f.startsWith(_root))) {
        await watch.forget(f);
      }
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    await watch.remember(_rock);
    await watch.setPlaylist(_rock, true);
    expect(watch.isPlaylist(_rock), isTrue);
    expect((await SharedPreferences.getInstance()).getStringList('library.folderPlaylists.v1'), [_rock]);
    await watch.setPlaylist(_rock, true);
    expect(watch.playlistFolders, [_rock], reason: 'made a playlist once');

    await watch.forget(_rock);
    expect(watch.isPlaylist(_rock), isFalse);
    expect((await SharedPreferences.getInstance()).getStringList('library.folderPlaylists.v1'), isEmpty);
  });

  test('Adding a folder as a playlist adds its songs and makes it a playlist; only adding does not', () async {
    SharedPreferences.setMockInitialValues({});
    final root = Directory.systemTemp.createTempSync('riflay-folder-add-');
    final asList = Directory(p.join(root.path, 'Mixtape'))..createSync();
    final only = Directory(p.join(root.path, 'Other'))..createSync();
    File(p.join(asList.path, 'song.mp3')).writeAsBytesSync(const [0]);
    final c = PlayerController();
    addTearDown(() async {
      for (final f in FolderWatch.instance.folders.where((f) => f.startsWith(root.path))) {
        await FolderWatch.instance.forget(f);
      }
      c.dispose();
      root.deleteSync(recursive: true);
    });

    expect(await c.scanFolder(asList.path, asPlaylist: true), 1);
    await c.scanFolder(only.path);
    final mixtape = FolderWatch.instance.folders.firstWhere((f) => f.endsWith('Mixtape'));
    expect(FolderWatch.instance.isPlaylist(mixtape), isTrue);
    expect(FolderWatch.instance.playlistFolders.where((f) => f.startsWith(root.path)), [mixtape]);
    expect(c.folderPlaylists.single.title, 'Mixtape');
    expect(c.folderPlaylists.single.tracks, hasLength(1));
  });

  testWidgets('The folder dialog: Only add is picked first, Add as playlist can be picked, Cancel gives null', (
    tester,
  ) async {
    final answers = <FolderAddChoice?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answers.add(await askFolderAddChoice(context, _rock)),
            child: const Text('open'),
          ),
        ),
      ),
    );
    Future<void> open() async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    await open();
    expect(find.text('Add “Rock”'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await open();
    await tester.tap(find.text('Add as playlist'));
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await open();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(answers, [FolderAddChoice.onlyAdd, FolderAddChoice.asPlaylist, null]);
  });

  testWidgets('Playlists shows a folder playlist with its folder name, marked as a folder', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = _Controller(_library, [_rock]);
    await tester.runAsync(c.load);
    addTearDown(() => tester.runAsync(() async => c.dispose()));
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScope(
          controller: c,
          child: ShellScope(
            compact: false,
            width: 1200,
            open: (_, {location}) {},
            openCollection: (_) {},
            openQueue: () {},
            openNowPlaying: () {},
            openLyrics: () {},
            openDownloads: () {},
            importFromYoutube: () {},
            addFiles: () {},
            addFolder: null,
            child: const Scaffold(body: LibraryList()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, 'Playlists'));
    await tester.pump();
    expect(find.text('Rock'), findsOneWidget);
    expect(find.text('Folder playlist • 2 songs'), findsOneWidget);
    expect(find.text('Jazz'), findsNothing, reason: 'only added, not a playlist');
    expect(
      find.descendant(
        of: find.ancestor(of: find.text('Rock'), matching: find.byType(InkWell)),
        matching: find.byIcon(Icons.folder_rounded),
      ),
      findsOneWidget,
    );
  });
}
