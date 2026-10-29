// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/library_views.dart';
import 'package:riflay/services/play_history.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/smart_playlists.dart';
import 'package:shared_preferences/shared_preferences.dart';

Track song(int i, {String? album, String? title, int addedAt = 0, bool tagged = false, String ext = 'flac'}) => Track(
  id: 'file:///music/s$i.$ext',
  uri: Uri.parse('file:///music/s$i.$ext'),
  title: title ?? 'Song ${(i * 7919) % 1000}',
  artist: i % 3 == 0 ? Track.unknownArtist : 'Artist ${i % 5}',
  album: album,
  trackNumber: i % 12,
  addedAt: addedAt,
  tagged: tagged,
);

/// A summary of every view, to compare two [LibraryViews] by value.
Map<String, Object?> summary(LibraryViews v) {
  List<Object?> ids(Iterable<Track> l) => [
    for (final t in l) '${t.id}|${t.title}|${t.artist}|${t.album}|${t.duration}',
  ];
  List<Object?> col(Iterable<Collection> l) => [
    for (final c in l) [c.kind.name, c.title, c.subtitle, ids(c.tracks)],
  ];
  return {
    'byId': ids((v.byId.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => e.value)),
    'keys': v.searchKeys,
    'all': col([v.allSongs]),
    'recent': ids(v.recentlyAdded),
    'yt': v.youtubeDownloads == null ? null : col([v.youtubeDownloads!]),
    'albums': col(v.albums),
    'artists': col(v.artists),
    'both': col(v.albumsAndArtists),
    'albumOf': (v.albumOfTrack.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
        .map((e) => '${e.key}>${e.value.title}')
        .toList(),
    'artistByName': (v.artistByName.keys.toList()..sort()),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => Directory.systemTemp.path,
  );

  group('LibraryViews.patched', () {
    List<Track> library() => [
      for (var i = 0; i < 300; i++) song(i, album: i % 4 == 0 ? null : 'Album ${i % 9}', addedAt: i * 10),
    ];

    LibraryViews warm(List<Track> l) {
      final v = LibraryViews(l, 0);
      summary(v); // everything worked out
      return v;
    }

    test('tags that only fill in (length, track number kept) give the views a full rebuild would', () {
      final l = library();
      final v = warm(l);
      final changed = <String, Track>{}, old = <String, Track>{};
      for (var i = 0; i < 300; i += 7) {
        old[l[i].id] = l[i];
        changed[l[i].id] = l[i] = l[i].copyWith(duration: const Duration(minutes: 3), tagged: true);
      }
      final patched = v.patched(1, changed, old);
      expect(summary(patched), summary(LibraryViews(l, 1)));
    });

    test('titles, artists and albums changing give the same views too', () {
      final l = library();
      final v = warm(l);
      final changed = <String, Track>{}, old = <String, Track>{};
      for (var i = 0; i < 300; i += 5) {
        old[l[i].id] = l[i];
        changed[l[i].id] = l[i] = l[i].copyWith(title: 'Zed $i', artist: 'New ${i % 4}', album: 'Fresh ${i % 6}');
      }
      expect(summary(v.patched(1, changed, old)), summary(LibraryViews(l, 1)));
    });

    test('a view nobody asked for is not worked out by the patch', () {
      final l = library();
      final v = LibraryViews(l, 0)..byId;
      final changed = {l[3].id: l[3].copyWith(tagged: true)};
      final next = v.patched(1, changed, {l[3].id: l[3]});
      expect(next.byId[l[3].id]!.tagged, isTrue);
      expect(next.albums, isNotEmpty); // still available on first use
    });
  });

  group('tag scan', () {
    test('library revision bumps are held back while tags are read, and one comes at the end', () async {
      final tracks = [for (var i = 0; i < 480; i++) song(i)];
      SharedPreferences.setMockInitialValues({
        'library.v1': jsonEncode([for (final t in tracks) t.toJson()]),
      });
      final c = PlayerController();
      var fake = DateTime(2026);
      // Every look at the clock is 300 ms later: a scan of ten batches seems to take a few seconds.
      c.now = () => fake = fake.add(const Duration(milliseconds: 300));
      var bumps = 0, batches = 0, playerNotifies = 0;
      c.libraryRevision.addListener(() => bumps++);
      var seen = 0;
      c.scanProgress.addListener(() {
        batches++;
        if (c.scanProgress.value.done > seen) seen = c.scanProgress.value.done;
      });
      c.addListener(() => playerNotifies++);
      await c.load();
      final start = fake;
      while (c.scanning) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final seconds = fake.difference(start).inMilliseconds / 1000;
      // ignore: avoid_print
      print('SCAN batches=$batches bumps=$bumps notifies=$playerNotifies fakeSeconds=$seconds');
      expect(c.library.every((t) => t.tagged), isTrue);
      expect(seen, 480);
      // The 400 ms rule bumped once per batch (about $batches); now it is one per 2 s of scan, plus the end.
      expect(bumps, lessThanOrEqualTo(seconds ~/ 2 + 3));
      expect(bumps, lessThan(batches));
      // The last bump came after the last tag landed.
      expect(c.libraryRevision.value, greaterThan(0));
      c.dispose();
    });
  });

  group('debounced saves', () {
    test('a run of small changes is one library write after two seconds', () {
      fakeAsync((async) {
        final c = PlayerController();
        c.saveSoon();
        async.elapse(const Duration(milliseconds: 900));
        c.saveSoon();
        async.elapse(const Duration(milliseconds: 900));
        c.saveSoon();
        expect(c.savePending, isTrue);
        async.elapse(const Duration(milliseconds: 300));
        expect(c.savePending, isFalse, reason: 'written once, 2.1 s after the first');
        c.dispose();
      });
    });

    test('dispose writes what is waiting', () {
      fakeAsync((async) {
        final c = PlayerController();
        c.saveSoon();
        expect(c.savePending, isTrue);
        c.dispose();
        expect(c.savePending, isFalse);
      });
    });
  });

  group('smart playlists cache', () {
    test('a play leaves the library lists alone; no change at all is a hit', () async {
      SharedPreferences.setMockInitialValues({
        'library.v1': jsonEncode([for (var i = 0; i < 200; i++) song(i, addedAt: 1000 + i, tagged: true).toJson()]),
      });
      final c = PlayerController();
      await c.load();
      final h = PlayHistory();
      SmartPlaylists.resetCache();
      final first = SmartPlaylists.of(c, h);
      expect(SmartPlaylists.computations, 2, reason: 'library lists + history lists');
      expect(identical(SmartPlaylists.of(c, h), first), isTrue);
      expect(SmartPlaylists.computations, 2, reason: 'a hit');
      final recentlyAdded = first[SmartList.recentlyAdded];
      h.record(c.library[3], const Duration(minutes: 3));
      final after = SmartPlaylists.of(c, h);
      expect(SmartPlaylists.computations, 3, reason: 'only the history lists were redone');
      expect(identical(after[SmartList.recentlyAdded], recentlyAdded), isTrue);
      expect(after[SmartList.mostPlayed]!.tracks.single.id, c.library[3].id);
      c.dispose();
    });
  });
}
