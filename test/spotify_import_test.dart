import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/playlist_transfer.dart';
import 'package:riflay/services/spotify_account.dart';
import 'package:riflay/services/spotify_import.dart';
import 'package:riflay/services/spotify_library.dart';
import 'package:riflay/services/spotify_session.dart';
import 'package:riflay/services/youtube_music_account.dart';
import 'package:riflay/ui/pages/spotify_page.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

SpotifyItem item(SpotifyItemKind kind, String name, {String? subtitle, int? count}) =>
    SpotifyItem(kind: kind, uri: 'spotify:${kind.name}:$name', name: name, subtitle: subtitle, count: count);

SpotifyItem playlist(String name) => item(SpotifyItemKind.playlist, name, subtitle: 'Ana', count: 2);
SpotifyItem album(String name) => item(SpotifyItemKind.album, name, subtitle: 'Daft Punk');
SpotifyItem artist(String name) => item(SpotifyItemKind.artist, name);

Track yt(String q) =>
    Track.youtube(videoId: q, title: q.split(' ').first, artist: 'A', duration: const Duration(seconds: 200));

ForeignPlaylist songsOf(SpotifyItem i) => ForeignPlaylist(
  title: i.name,
  service: 'Spotify',
  songs: const [
    ForeignSong(title: 'One', artist: 'A', duration: Duration(seconds: 200)),
    ForeignSong(title: 'Gone', artist: 'A', duration: Duration(seconds: 200)),
  ],
);

class Calls {
  final saved = <String>[];
  final albumsSaved = <String>[];
  final followed = <String>[];
  final imported = <String>[];
}

SpotifyImporter importer(
  Calls calls, {
  bool canEdit = true,
  Future<ForeignPlaylist> Function(SpotifyItem)? songs,
  Future<List<Track>> Function(String)? search,
  String? Function(SpotifyItem)? albumId,
  bool albumTaken = true,
  String? Function(SpotifyItem)? artistId,
}) => SpotifyImporter(
  songs: songs ?? (i) async => songsOf(i),
  search: search ?? (q) async => q.startsWith('Gone') ? [] : [yt(q)],
  videos: (_) async => [],
  save: (title, tracks) async => calls.saved.add('$title:${tracks.length}'),
  canEdit: canEdit,
  findAlbum: (a) async => albumId == null ? 'MPRE${a.name}' : albumId(a),
  saveAlbum: (id) async {
    calls.albumsSaved.add(id);
    return albumTaken;
  },
  findArtist: (a) async => artistId == null ? 'UC${a.name}' : artistId(a),
  follow: (id) async => calls.followed.add(id),
  onImported: calls.imported.add,
);

SpotifySession session({Duration expiresIn = const Duration(hours: 1), String token = 'tok'}) => SpotifySession(
  cookies: 'sp_dc=abc',
  accessToken: token,
  expiresAt: DateTime.now().add(expiresIn),
  clientToken: 'ct',
  appVersion: '1.0',
);

class FakeLibrary implements SpotifyLibraryClient {
  FakeLibrary({this.lists = const {}});

  final Map<String, List<SpotifyItem>> lists;

  @override
  Future<String?> profileName() async => 'Ana';
  @override
  Future<List<SpotifyItem>> playlists() async => lists['playlists'] ?? [];
  @override
  Future<List<SpotifyItem>> albums() async => lists['albums'] ?? [];
  @override
  Future<List<SpotifyItem>> artists() async => lists['artists'] ?? [];
  @override
  Future<ForeignPlaylist> songs(SpotifyItem item, {int max = 5000}) async => songsOf(item);
  @override
  void close() {}
  @override
  Future<SpotifyAuth> Function({bool force}) get auth => throw UnimplementedError();
}

class FakeAccount extends SpotifyAccount {
  FakeAccount({this.library, super.refresher});

  final SpotifyLibraryClient? library;

  @override
  SpotifyLibraryClient get client => library ?? FakeLibrary();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SpotifyImporter', () {
    test('a playlist is matched and saved', () async {
      final calls = Calls();
      final run = importer(calls);
      await run.run([playlist('Road trip')]);
      expect(calls.saved, ['Road trip:1']);
      expect(run.results.single.outcome, SpotifyOutcome.playlist);
      expect(run.results.single.line, 'Road trip: 1 of 2 songs');
      expect(run.results.single.missing.single.title, 'Gone');
      expect(calls.imported, ['spotify:playlist:Road trip']);
      expect(run.succeeded, 1);
    });

    test('nothing matched counts as failed and is not saved', () async {
      final calls = Calls();
      final run = importer(calls, search: (_) async => []);
      await run.run([playlist('Old mix')]);
      expect(calls.saved, isEmpty);
      expect(run.results.single.outcome, SpotifyOutcome.noSongs);
      expect(run.results.single.line, 'Old mix: no songs found on YouTube Music');
      expect(run.succeeded, 0);
      expect(calls.imported, isEmpty);
    });

    test('an album is saved to the YouTube Music library when signed in', () async {
      final calls = Calls();
      await importer(calls).run([album('Discovery')]);
      expect(calls.albumsSaved, ['MPREDiscovery']);
      expect(calls.saved, isEmpty);
    });

    test('an album not on YouTube Music becomes a playlist', () async {
      final calls = Calls();
      final run = importer(calls, albumId: (_) => null);
      await run.run([album('Discovery')]);
      expect(calls.albumsSaved, isEmpty);
      expect(calls.saved, ['Discovery:1']);
      expect(run.results.single.outcome, SpotifyOutcome.playlist);
    });

    test('an album YouTube Music will not take becomes a playlist; signed out too', () async {
      final calls = Calls();
      await importer(calls, albumTaken: false).run([album('Discovery')]);
      expect(calls.saved, ['Discovery:1']);
      final signedOut = Calls();
      await importer(signedOut, canEdit: false).run([album('Homework')]);
      expect(signedOut.albumsSaved, isEmpty);
      expect(signedOut.saved, ['Homework:1']);
    });

    test('an artist is followed, or listed as missing', () async {
      final calls = Calls();
      final run = importer(calls, artistId: (a) => a.name == 'Nobody' ? null : 'UC1');
      await run.run([artist('Daft Punk'), artist('Nobody')]);
      expect(calls.followed, ['UC1']);
      expect(run.results.map((r) => r.line), ['Daft Punk: followed', 'Nobody: not found on YouTube Music']);
      expect(run.succeeded, 1);
    });

    test('one item failing does not stop the others', () async {
      final calls = Calls();
      final run = importer(
        calls,
        songs: (i) async => i.name == 'Bad' ? throw const PlaylistTransferError('Spotify said no.') : songsOf(i),
      );
      await run.run([playlist('Bad'), playlist('Good')]);
      expect(run.results.map((r) => r.outcome), [SpotifyOutcome.failed, SpotifyOutcome.playlist]);
      expect(run.results.first.line, 'Bad: Spotify said no.');
      expect(calls.saved, ['Good:1']);
    });

    test('cancel stops the run', () async {
      final calls = Calls();
      late SpotifyImporter run;
      run = importer(
        calls,
        songs: (i) async {
          if (i.name == 'First') run.cancel();
          return songsOf(i);
        },
      );
      await run.run([playlist('First'), playlist('Second')]);
      expect(run.cancelled, isTrue);
      expect(run.running, isFalse);
      expect(calls.saved, isEmpty);
      expect(run.results, isEmpty);
    });

    test('signed out stops the run', () async {
      final calls = Calls();
      final run = importer(calls, songs: (i) async => i.name == 'Second' ? throw const SpotifySignedOut() : songsOf(i));
      await run.run([playlist('First'), playlist('Second'), playlist('Third')]);
      expect(run.signedOut, isTrue);
      expect(calls.saved, ['First:1']);
      expect(run.results, hasLength(1));
    });

    test('progress is reported', () async {
      final calls = Calls();
      final run = importer(calls);
      final seen = <String>[];
      run.addListener(() => seen.add('${run.positionLabel} ${run.matched}/${run.matchTotal}'));
      await run.run([playlist('A'), playlist('B')]);
      expect(seen, contains('Playlist 2 of 2 0/2'));
      expect(seen, contains('Playlist 1 of 2 2/2'));
    });

    test('albums and artists are picked by name and artist', () {
      final a = album('Discovery');
      RemotePlaylist hit(String t, String sub, String id) =>
          RemotePlaylist(id: id, browseId: id, title: t, subtitle: sub, count: 0);
      expect(
        SpotifyImporter.pickAlbum(a, [
          hit('Discovery (Deluxe)', 'Album • Daft Punk', 'x'),
          hit('Discovery', 'Album • Other', 'y'),
          hit('discovery', 'Album • Daft Punk', 'z'),
        ]),
        'z',
      );
      expect(SpotifyImporter.pickAlbum(a, [hit('Homework', 'Album • Daft Punk', 'x')]), isNull);
      expect(
        SpotifyImporter.pickArtist(artist('Daft Punk'), [
          hit('Daft Punk Tribute', '', 'a'),
          hit('Daft  Punk', '', 'b'),
        ]),
        'b',
      );
    });
  });

  group('SpotifyAccount.auth', () {
    test('signed out throws', () async {
      expect(FakeAccount().auth(), throwsA(isA<SpotifySignedOut>()));
    });

    test('uses the stored token while fresh', () async {
      var refreshed = 0;
      final account = FakeAccount(
        refresher: (_) async => session(token: 'new', expiresIn: const Duration(hours: 1)),
      );
      await account.connect(session());
      expect((await account.auth()).accessToken, 'tok');
      expect(refreshed, 0);
    });

    test('refreshes when expired or forced, once at a time', () async {
      var refreshes = 0;
      final gate = Completer<void>();
      final account = FakeAccount(
        refresher: (cookies) async {
          refreshes++;
          expect(cookies, 'sp_dc=abc');
          await gate.future;
          return session(token: 'new$refreshes');
        },
      );
      await account.connect(session(expiresIn: const Duration(seconds: 30)));
      final a = account.auth();
      final b = account.auth();
      gate.complete();
      expect((await a).accessToken, 'new1');
      expect((await b).accessToken, 'new1');
      expect(refreshes, 1);
      expect((await account.auth()).accessToken, 'new1');
      expect((await account.auth(force: true)).accessToken, 'new2');
      expect(refreshes, 2);
    });

    test('a refused refresh signs out', () async {
      final account = FakeAccount(refresher: (_) async => null);
      await account.connect(session(expiresIn: const Duration(seconds: 30)));
      expect(account.isSignedIn, isTrue);
      await expectLater(account.auth(), throwsA(isA<SpotifySignedOut>()));
      expect(account.isSignedIn, isFalse);
      expect(account.error, SpotifySignedOut.message);
    });

    test('remembers imported items until sign out', () async {
      final account = FakeAccount();
      await account.connect(session());
      expect(account.name, 'Ana');
      await account.markImported(['spotify:playlist:x']);
      expect(account.importedAt('spotify:playlist:x'), isNotNull);
      expect(account.importedAt('spotify:playlist:y'), isNull);
      await account.signOut();
      expect(account.importedAt('spotify:playlist:x'), isNull);
      expect(account.isSignedIn, isFalse);
    });
  });

  group('SpotifyPage', () {
    Widget app(Widget page) => MaterialApp(
      home: ShellScope(
        compact: true,
        width: 400,
        open: (_, {location}) {},
        openCollection: (_) {},
        openQueue: () {},
        openNowPlaying: () {},
        openLyrics: () {},
        openDownloads: () {},
        importFromYoutube: () {},
        addFiles: () {},
        addFolder: null,
        child: Scaffold(body: page),
      ),
    );

    testWidgets('signed out: one sign-in button, no Beta badge any more', (t) async {
      await t.pumpWidget(app(SpotifyPage(account: FakeAccount(), youtubeSignedIn: true)));
      await t.pumpAndSettle();
      expect(find.text('Beta'), findsNothing);
      expect(find.text('Sign in with Spotify'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.textContaining('Copy your Spotify playlists'), findsOneWidget);
      expect(find.textContaining('never changes your Spotify account'), findsOneWidget);
    });

    testWidgets('signed in: Import all is on, Import N waits for a tick', (t) async {
      final account = FakeAccount(
        library: FakeLibrary(
          lists: {
            'playlists': [item(SpotifyItemKind.liked, 'Liked Songs', count: 5), playlist('Road trip')],
            'artists': [artist('Daft Punk')],
          },
        ),
      );
      await t.runAsync(() => account.connect(session()));
      final calls = Calls();
      await t.pumpWidget(
        app(
          SpotifyPage(account: account, youtubeSignedIn: false, importerFor: (_, _) => importer(calls, canEdit: false)),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Liked Songs'), findsOneWidget);
      expect(find.text('Playlists become Riflay playlists.'), findsOneWidget);
      FilledButton button(String label) => t.widget<FilledButton>(find.widgetWithText(FilledButton, label));
      expect(button('Import all').onPressed, isNotNull);
      expect(button('Import').onPressed, isNull);

      await t.tap(find.byType(Checkbox).last);
      await t.pump();
      expect(button('Import 1').onPressed, isNotNull);

      // Artists aren't offered: following them in YouTube Music isn't safe yet.
      expect(find.text('Artists'), findsNothing);

      // Import the playlist, then see the summary.
      await t.tap(find.text('Import 1'));
      await t.pumpAndSettle();
      expect(find.text('Imported 1 of 1'), findsOneWidget);
      expect(find.text('Road trip: 1 of 2 songs'), findsOneWidget);
      await t.tap(find.text('Done'));
      await t.pumpAndSettle();
      expect(find.text('Imported'), findsOneWidget);
      expect(calls.saved, ['Road trip:1']);
    });
  });
}
