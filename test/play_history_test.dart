import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/listening_stats.dart';
import 'package:riflay/services/play_history.dart';
import 'package:riflay/services/smart_playlists.dart';
import 'package:shared_preferences/shared_preferences.dart';

Track song(String name, {String artist = 'Artist', String? album, int addedAt = 0, String ext = 'mp3'}) => Track(
  id: 'file:///music/$name.$ext',
  uri: Uri.parse('file:///music/$name.$ext'),
  title: name,
  artist: artist,
  album: album,
  addedAt: addedAt,
);

PlayHistory memory({int maxPlays = 150000}) => PlayHistory(maxPlays: maxPlays);

void main() {
  const s = Duration(seconds: 1);

  group('when a play counts', () {
    final a = song('a');
    final b = song('b');

    /// Plays [a] from 0 to [seconds] of its own time, one look a second.
    List<PlayedSong> listen(PlayTracker t, Track track, int seconds, {int from = 0, bool end = false}) {
      final out = <PlayedSong>[];
      for (var i = from; i <= from + seconds; i++) {
        out.addAll(t.tick(track: track, position: s * i, playing: true, ended: false));
      }
      if (end) out.addAll(t.tick(track: track, position: s * (from + seconds), playing: false, ended: true));
      return out;
    }

    test('29 seconds is not a play, 30 is (when the song is over)', () {
      var t = PlayTracker();
      expect(listen(t, a, 29), isEmpty);
      expect(t.tick(track: b, position: Duration.zero, playing: true, ended: false), isEmpty);
      t = PlayTracker();
      expect(listen(t, a, 35), isEmpty);
      final played = t.tick(track: b, position: Duration.zero, playing: true, ended: false);
      expect(played.single.track.id, a.id);
      expect(played.single.heard.inSeconds, inInclusiveRange(34, 35));
    });

    test('a song that ends counts even if short, once', () {
      final t = PlayTracker();
      final out = listen(t, a, 12, end: true);
      expect(out, hasLength(1));
      expect(out.single.heard.inSeconds, 12);
      // Still "completed" on later looks: not again.
      expect(t.tick(track: a, position: s * 12, playing: false, ended: true), isEmpty);
      expect(t.finish(), isEmpty);
    });

    test('pausing after 30 seconds hands the play over; resuming does not repeat it', () {
      final t = PlayTracker();
      listen(t, a, 31);
      final paused = t.tick(track: a, position: s * 31, playing: false, ended: false);
      expect(paused, hasLength(1));
      expect(listen(t, a, 20, from: 31), isEmpty);
      expect(t.tick(track: b, position: Duration.zero, playing: true, ended: false), isEmpty);
    });

    test('a seek adds no time', () {
      final t = PlayTracker();
      listen(t, a, 20);
      // Jump to 3:00: still 20 seconds heard.
      t.tick(track: a, position: const Duration(minutes: 3), playing: true, ended: false);
      expect(t.tick(track: b, position: Duration.zero, playing: true, ended: false), isEmpty);
    });

    test('repeat one: each pass is a play', () {
      final t = PlayTracker();
      final out = <PlayedSong>[...listen(t, a, 40, end: true)];
      out.addAll(listen(t, a, 40, end: true));
      expect(out, hasLength(2));
    });

    test('finish() hands over a counted play in progress', () {
      final t = PlayTracker();
      listen(t, a, 45);
      expect(t.finish().single.heard.inSeconds, inInclusiveRange(44, 45));
    });
  });

  group('storage', () {
    late Directory dir;
    late File file;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      dir = Directory.systemTemp.createTempSync('history_test');
      file = File('${dir.path}/h.jsonl');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('plays and songs survive a restart', () async {
      final h = PlayHistory(file: file);
      await h.load();
      final yt = Track.youtube(videoId: 'abc', title: 'Streamed', artist: 'X, Y', artworkUrl: 'https://c/x.jpg');
      h.record(song('a', album: 'Alb'), const Duration(seconds: 200), at: DateTime(2026, 3, 1, 12));
      h.record(song('a', album: 'Alb'), const Duration(seconds: 100), at: DateTime(2026, 3, 2, 12));
      h.record(yt, const Duration(seconds: 31), at: DateTime(2026, 3, 3, 12));
      await h.flush();

      final lines = file.readAsLinesSync();
      expect(lines.first, '{"fmt":1}');
      expect(lines.where((l) => l.startsWith('[')), hasLength(3));
      expect(lines.where((l) => l.startsWith('{"i"')), hasLength(2), reason: 'a song is written once');

      final back = PlayHistory(file: file);
      await back.load();
      expect(back.length, 3);
      expect(back.songCount, 2);
      expect(back.playsOf('file:///music/a.mp3'), 2);
      expect(back.playsOf('yt:abc'), 1);
      expect(back.songInfo(back.songIndex(2)).videoId, 'abc');
      expect(back.songInfo(back.songIndex(2)).artworkUrl, 'https://c/x.jpg');
      expect(back.songInfo(0).album, 'Alb');
      expect(back.heardSec(1), 100);
      expect(back.atSec(0), DateTime(2026, 3, 1, 12).millisecondsSinceEpoch ~/ 1000);
      expect(back.lastPlayedSec('file:///music/a.mp3'), DateTime(2026, 3, 2, 12).millisecondsSinceEpoch ~/ 1000);
    });

    test('a cut-short last line is skipped and the file keeps growing cleanly', () async {
      file.writeAsStringSync('{"fmt":1}\n{"i":0,"k":"k","t":"T","a":"A"}\n[100,0,40]\n[200,0,4');
      final h = PlayHistory(file: file);
      await h.load();
      expect(h.length, 1);
      h.record(song('z'), const Duration(seconds: 50), at: DateTime(2026, 1, 1));
      await h.flush();
      final back = PlayHistory(file: file);
      await back.load();
      expect(back.length, 2);
    });

    test('a retagged song shows its newest details', () async {
      final h = PlayHistory(file: file);
      await h.load();
      h.record(song('a'), const Duration(seconds: 40));
      h.record(song('a').copyWith(title: 'Renamed'), const Duration(seconds: 40));
      await h.flush();
      final back = PlayHistory(file: file);
      await back.load();
      expect(back.songCount, 1);
      expect(back.songInfo(0).title, 'Renamed');
      expect(back.playsOf('file:///music/a.mp3'), 2);
    });

    test('past the limit the oldest plays go and unused songs with them', () async {
      final h = PlayHistory(file: file, maxPlays: 10, keepPlays: 6);
      await h.load();
      for (var i = 0; i < 12; i++) {
        h.record(song('s$i'), const Duration(seconds: 40), at: DateTime(2026, 1, 1 + i));
      }
      await h.flush();
      expect(h.length, 6);
      expect(h.songCount, 6);
      expect(h.playsOf('file:///music/s0.mp3'), 0);
      expect(h.playsOf('file:///music/s11.mp3'), 1);
      final back = PlayHistory(file: file);
      await back.load();
      expect(back.length, 6);
      expect(back.songCount, 6);
      expect(back.atSec(0), DateTime(2026, 1, 7).millisecondsSinceEpoch ~/ 1000);
    });

    test('ten thousand plays stay small', () async {
      final h = PlayHistory(file: file, flushAfter: const Duration(hours: 1));
      await h.load();
      for (var i = 0; i < 10000; i++) {
        h.record(
          song('s${i % 800}', artist: 'Artist ${(i % 800) % 90}', album: 'Album ${(i % 800) % 150}'),
          const Duration(seconds: 215),
          at: DateTime(2025, 1, 1).add(Duration(minutes: 20 * i)),
        );
      }
      await h.flush();
      expect(file.lengthSync(), lessThan(600 * 1024));
    });

    test('off records nothing; clear removes everything, on disk too', () async {
      final h = PlayHistory(file: file);
      await h.load();
      h.record(song('a'), const Duration(seconds: 40));
      await h.flush();
      expect(file.existsSync(), isTrue);

      await h.setEnabled(false);
      h.record(song('b'), const Duration(seconds: 40));
      expect(h.length, 1);
      expect((await SharedPreferences.getInstance()).getBool(PlayHistory.enabledKey), isFalse);

      await h.clear();
      expect(h.length, 0);
      expect(file.existsSync(), isFalse);
      await h.setEnabled(true);
      h.record(song('c'), const Duration(seconds: 40));
      await h.flush();
      expect(file.readAsLinesSync().first, '{"fmt":1}');
      expect(file.readAsLinesSync().where((l) => l.startsWith('[')), hasLength(1));
    });
  });

  group('stats', () {
    final now = DateTime(2026, 6, 15, 12);

    PlayHistory data() {
      final h = memory();
      final a = song('a', artist: 'Ann', album: 'First');
      final b = song('b', artist: 'Ann', album: 'First');
      final c = song('c', artist: 'Bo', album: 'Second');
      void p(Track t, DateTime at, [int heard = 100]) => h.record(t, Duration(seconds: heard), at: at);
      p(a, DateTime(2026, 6, 3, 9));
      p(a, DateTime(2026, 6, 4, 9));
      p(b, DateTime(2026, 6, 4, 10));
      p(c, DateTime(2026, 5, 30, 10), 300);
      p(c, DateTime(2026, 2, 1, 10), 300);
      p(c, DateTime(2025, 12, 31, 23), 300);
      p(c, DateTime(2025, 1, 5, 10), 300);
      return h;
    }

    test('periods', () {
      final h = data();
      expect(ListeningStats.compute(h, StatsPeriod.thisMonth, now: now).plays, 3);
      expect(ListeningStats.compute(h, StatsPeriod.thisYear, now: now).plays, 5);
      expect(ListeningStats.compute(h, StatsPeriod.allTime, now: now).plays, 7);
      expect(ListeningStats.compute(h, const StatsPeriod.ofYear(2025), now: now).plays, 2);
      expect(h.years, [2026, 2025]);
    });

    test('totals and rankings', () {
      final st = ListeningStats.compute(data(), StatsPeriod.thisYear, now: now);
      expect(st.listened, const Duration(seconds: 300 * 2 + 300));
      expect(st.songs, 3);
      // a: 2 plays; c: 2 plays but more time; b: 1.
      expect(st.topSongs.map((e) => e.title), ['c', 'a', 'b']);
      expect(st.topArtists.map((e) => e.title), ['Ann', 'Bo']);
      expect(st.topArtists.first.plays, 3);
      expect(st.topAlbums.map((e) => e.title), ['First', 'Second']);
      expect(st.topAlbums.first.sample.title, 'a', reason: 'an album shows its most played song');
    });

    test('bars: days of the month, months of the year, years', () {
      final h = data();
      final month = ListeningStats.compute(h, StatsPeriod.thisMonth, now: now).bars;
      expect(month, hasLength(30));
      expect(month[3].listened, const Duration(seconds: 200));
      final year = ListeningStats.compute(h, StatsPeriod.thisYear, now: now).bars;
      expect(year, hasLength(12));
      expect(year[1].listened, const Duration(seconds: 300));
      expect(year[5].listened, const Duration(seconds: 300));
      final all = ListeningStats.compute(h, StatsPeriod.allTime, now: now).bars;
      expect(all.map((b) => b.name), ['2025', '2026']);
      expect(all.last.listened, const Duration(seconds: 900));
    });

    test('empty history gives empty stats', () {
      expect(ListeningStats.compute(memory(), StatsPeriod.allTime, now: now).isEmpty, isTrue);
    });

    test('formatListened', () {
      expect(formatListened(const Duration(hours: 12, minutes: 40)), '12 h 40 min');
      expect(formatListened(const Duration(hours: 2)), '2 h');
      expect(formatListened(const Duration(minutes: 35)), '35 min');
      expect(formatListened(const Duration(seconds: 20)), '1 min');
    });
  });

  group('smart playlists', () {
    final now = DateTime(2026, 6, 15, 12);
    int ago(int days) => now.subtract(Duration(days: days)).millisecondsSinceEpoch;

    test('Most played: by plays, then most recent; includes streamed songs; Recently played: newest first', () {
      final h = memory();
      final a = song('a');
      final b = song('b');
      final yt = Track.youtube(videoId: 'v', title: 'Streamed', artist: 'Y');
      h.record(a, const Duration(seconds: 40), at: now.subtract(const Duration(days: 5)));
      h.record(b, const Duration(seconds: 40), at: now.subtract(const Duration(days: 4)));
      h.record(b, const Duration(seconds: 40), at: now.subtract(const Duration(days: 3)));
      h.record(yt, const Duration(seconds: 40), at: now.subtract(const Duration(days: 2)));
      final lists = SmartPlaylists.compute([a, b, song('never')], h, now: now);
      expect(lists[SmartList.mostPlayed]!.tracks.map((t) => t.title), ['b', 'Streamed', 'a']);
      expect(lists[SmartList.recentlyPlayed]!.tracks.map((t) => t.title), ['Streamed', 'b', 'a']);
      expect(lists[SmartList.mostPlayed]!.kind, CollectionKind.smart);
      expect(lists[SmartList.mostPlayed]!.subtitle, '3 songs');
    });

    test('Not played for a while: library songs idle over 90 days, longest first', () {
      final h = memory();
      final old = song('old', addedAt: ago(400));
      final playedLongAgo = song('long-ago', addedAt: ago(400));
      final playedRecently = song('recent', addedAt: ago(400));
      final newAndUnplayed = song('new', addedAt: ago(5));
      final addedLongAgoNeverPlayed = song('older', addedAt: ago(300));
      h.record(playedLongAgo, const Duration(seconds: 40), at: now.subtract(const Duration(days: 120)));
      h.record(playedRecently, const Duration(seconds: 40), at: now.subtract(const Duration(days: 10)));
      final lib = [newAndUnplayed, playedRecently, addedLongAgoNeverPlayed, playedLongAgo, old];
      final list = SmartPlaylists.compute(lib, h, now: now)[SmartList.notPlayedForAWhile]!;
      // old (400 days) first, then older (300), then long-ago (last heard 120 days ago).
      expect(list.tracks.map((t) => t.title), ['old', 'older', 'long-ago']);
    });

    test('Recently added: newest first, capped; Lossless: by format', () {
      final lib = [
        for (var i = 0; i < 120; i++) song('t$i', addedAt: ago(200 - i)),
        song('wave', ext: 'wav', addedAt: ago(1)),
        song('tune', ext: 'flac'),
        song('apple', ext: 'm4a'),
        song('dsd', ext: 'DSF'),
        song('ape', ext: 'ape'),
        song('wv', ext: 'wv'),
        song('aif', ext: 'aiff'),
        song('alac', ext: 'alac'),
      ];
      final lists = SmartPlaylists.compute(lib, memory(), now: now);
      expect(lists[SmartList.recentlyAdded]!.tracks, hasLength(100));
      expect(lists[SmartList.recentlyAdded]!.tracks.first.title, 'wave');
      expect(lists[SmartList.lossless]!.tracks.map((t) => t.title), [
        'wave',
        'tune',
        'dsd',
        'ape',
        'wv',
        'aif',
        'alac',
      ]);
      expect(lists.containsKey(SmartList.mostPlayed), isFalse, reason: 'empty lists are not shown');
    });
  });
}
