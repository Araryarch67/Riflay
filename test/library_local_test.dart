import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/library_views.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/navigation.dart';
import 'package:riflay/ui/pages/collection_page.dart';
import 'package:riflay/ui/pages/library_page.dart';
import 'package:riflay/ui/shell/desktop_sidebar.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

Track _file(String path, String title, {String artist = 'Someone', String? sourceUrl}) => Track(
  id: Uri.file(path).toString(),
  uri: Uri.file(path),
  title: title,
  artist: artist,
  tagged: true,
  sourceUrl: sourceUrl,
);

final _library = [
  _file('/music/Rock/b.flac', 'Second rock song'),
  _file('/music/Rock/a.flac', 'First rock song'),
  _file('/music/Rock/Live/c.flac', 'Live rock song'),
  _file('/music/Rocky/d.flac', 'Not in Rock'),
  _file('/other/Jazz/e.flac', 'Jazz song'),
  _file('/downloads/f.opus', 'Downloaded song', sourceUrl: 'https://music.youtube.com/watch?v=abc'),
  Track.youtube(videoId: 'zzz', title: 'Streamed song', artist: 'Someone'),
];

final _folders = ['/music/Rock', '/other/Jazz', '/empty/Folder'].map(p.normalize).toList();

/// The real library, with the music folders given here instead of read from FolderWatch's saved list.
class _Controller extends PlayerController {
  @override
  List<Collection> get folders => LibraryViews(library, 0).foldersOf(_folders);
}

Future<PlayerController> _controller(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'library.v1': jsonEncode([for (final t in _library) t.toJson()]),
  });
  final c = _Controller();
  await tester.runAsync(c.load);
  addTearDown(() => tester.runAsync(() async => c.dispose()));
  return c;
}

Widget _app(PlayerController c, Widget page, {void Function(Collection)? openCollection}) => MaterialApp(
  home: PlayerScope(
    controller: c,
    child: ShellScope(
      compact: false,
      width: 1200,
      open: (_, {location}) {},
      openCollection: openCollection ?? (_) {},
      openQueue: () {},
      openNowPlaying: () {},
      openLyrics: () {},
      openDownloads: () {},
      importFromYoutube: () {},
      addFiles: () {},
      addFolder: null,
      child: Scaffold(body: page),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => Directory.systemTemp.path,
  );

  testWidgets('the sidebar title stays on one line and the actions fit when resized', (tester) async {
    final c = await _controller(tester);
    c.createPlaylist('First mix');
    c.createPlaylist('Second mix');
    final title = find.text('Your Library');
    final menu = find.byTooltip('More options');
    for (final width in [360.0, 200.0, 260.0, 360.0]) {
      await tester.pumpWidget(
        _app(
          c,
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: const ShellPanel(gradient: true, child: LibraryList(dense: true)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(title).maxLines, 1);
      final titleRect = tester.getRect(title);
      final menuRect = tester.getRect(menu);
      expect(menuRect.right, lessThanOrEqualTo(width));
      expect(titleRect.center.dy, closeTo(menuRect.center.dy, 1));
      expect(
        find.byWidgetPredicate((w) {
          final decoration = w is Ink ? w.decoration : null;
          return decoration is BoxDecoration && decoration.gradient != null;
        }),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Library sorts playlists by name and moves the pinned playlist above them', (tester) async {
    SharedPreferences.setMockInitialValues({
      'library.v1': '[]',
      'discord.enabled': false,
      'playlists.v1': jsonEncode([
        for (final name in ['Zulu', 'Alpha', 'Beta'])
          UserPlaylist(id: name, name: name, tracks: const [], createdAt: 0).toJson(),
      ]),
    });
    final c = PlayerController();
    addTearDown(c.dispose);
    await tester.runAsync(() async {
      await LayoutPrefs.instance.reset();
      await c.load();
    });
    await tester.pumpWidget(_app(c, const LibraryList()));
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sort playlists'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name A–Z'));
    await tester.pumpAndSettle();
    double row(String name) => tester.getCenter(find.text(name)).dy;
    expect(row('Alpha'), lessThan(row('Zulu')));
    await tester.tap(find.byTooltip('Playlist options').at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin playlist'));
    await tester.pumpAndSettle();
    expect(row('Zulu'), lessThan(row('Alpha')));
    expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);
    expect(find.byIcon(Icons.drag_handle_rounded), findsNothing);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit playlists'));
    await tester.pumpAndSettle();
    final handles = find.byIcon(Icons.drag_handle_rounded);
    expect(handles, findsNWidgets(3));
    final gesture = await tester.startGesture(tester.getCenter(handles.at(2)), kind: PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    for (var step = 0; step < 5; step++) {
      await gesture.moveBy(const Offset(0, -14));
      await tester.pump(const Duration(milliseconds: 45));
    }
    expect(tester.takeException(), isNull);
    expect(find.text('Beta'), findsWidgets, reason: 'the drag proxy still has the row layout');
    await gesture.up();
    await tester.pumpAndSettle();
    expect(row('Zulu'), lessThan(row('Beta')));
    expect(row('Beta'), lessThan(row('Alpha')));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(handles, findsNothing);
    expect(row('Beta'), lessThan(row('Alpha')));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(LayoutPrefs.instance.reset);
  });
  group('LibraryViews.foldersOf', () {
    test('each folder holds the files under it, by path; a streamed song is in none', () {
      final folders = LibraryViews(_library, 0).foldersOf(_folders);
      expect(folders.map((f) => f.title), ['Rock', 'Jazz', 'Folder']);
      expect(folders.map((f) => f.kind).toSet(), {CollectionKind.folder});
      expect(folders.map((f) => f.id), _folders);
      // '/music/Rocky' only starts like '/music/Rock'; the subfolder's song sorts where its path does.
      expect(folders[0].tracks.map((t) => t.title), ['Live rock song', 'First rock song', 'Second rock song']);
      expect(folders[1].tracks.map((t) => t.title), ['Jazz song']);
      expect(folders[2].tracks, isEmpty);
    });

    test('a download saved inside a music folder is in it', () {
      final folders = LibraryViews(_library, 0).foldersOf([p.normalize('/downloads')]);
      expect(folders.single.tracks.map((t) => t.title), ['Downloaded song']);
    });

    test('is worked out once per list of folders', () {
      final views = LibraryViews(_library, 0);
      expect(views.foldersOf(_folders), same(views.foldersOf([..._folders])));
      expect(views.foldersOf(const ['/music/Rock']), hasLength(1));
    });

    test('two folders of the same name are two places in the history', () {
      final folders = LibraryViews(_library, 0).foldersOf(const ['/a/Music', '/b/Music']);
      expect(Locations.collection(folders[0]), isNot(Locations.collection(folders[1])));
    });
  });

  testWidgets('Library › Local lists the music folders and Downloaded, and a folder opens its songs', (tester) async {
    final c = await _controller(tester);
    final opened = <Collection>[];
    await tester.pumpWidget(_app(c, const LibraryList(), openCollection: opened.add));
    await tester.pump();

    // Everything: no folder rows.
    expect(find.text('All Songs'), findsOneWidget);
    expect(find.text('Rock'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Local'));
    await tester.pump();
    expect(find.text('Rock'), findsOneWidget);
    expect(find.text('Jazz'), findsOneWidget);
    expect(find.text('Folder • 3 songs'), findsOneWidget);
    expect(find.text('Downloaded'), findsNWidgets(2), reason: 'its chip and its row');
    expect(find.text('All Songs'), findsNothing);

    await tester.tap(find.text('Rock'));
    expect(opened.single.kind, CollectionKind.folder);
    expect(opened.single.tracks.map((t) => t.title), ['Live rock song', 'First rock song', 'Second rock song']);

    // The folder's page shows the songs in it.
    await tester.pumpWidget(_app(c, CollectionPage(collection: opened.single)));
    await tester.pump();
    expect(find.text('First rock song'), findsOneWidget);
    expect(find.text('Live rock song'), findsOneWidget);
    expect(find.text('Jazz song'), findsNothing);
    // The covers' lookups (files that aren't there) finish on the fake clock.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Library › Local says what goes there while it is empty', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = PlayerController();
    await tester.runAsync(c.load);
    addTearDown(() => tester.runAsync(() async => c.dispose()));
    await tester.pumpWidget(_app(c, const LibraryList()));
    await tester.pump();

    await tester.tap(find.widgetWithText(FilterChip, 'Local'));
    await tester.pump();
    expect(find.text('Music folders you add and songs you download show up here.'), findsOneWidget);
  });
}
