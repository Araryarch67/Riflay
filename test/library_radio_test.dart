import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/radio_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_audio_platform.dart';

Track _song(String id, {String artist = 'Artist', String? album, String? title, String? sourceUrl}) => Track(
  id: id,
  uri: Uri.file('/music/$id.wav'),
  title: title ?? id,
  artist: artist,
  album: album,
  sourceUrl: sourceUrl,
);

void main() {
  group('RadioQueue.fromLibrary', () {
    final seed = _song('seed', artist: 'Aimer', album: 'Daydream');
    final sameAlbum = _song('album', artist: 'Aimer', album: 'Daydream');
    final sameArtist = _song('artist', artist: 'Aimer', album: 'Walpurgis');
    final featuring = _song('feat', artist: 'LiSA & Aimer');
    final other = _song('other', artist: 'YOASOBI');
    final compilation = _song('comp', artist: 'Ado', album: 'Daydream');
    final stream = Track.youtube(videoId: 'v1', title: 'Stream', artist: 'Aimer');
    final copy = _song('copy', artist: 'Aimer', title: 'seed', sourceUrl: 'https://music.youtube.com/watch?v=x');

    List<String> pick({Iterable<Track> excluded = const [], int limit = 25}) => RadioQueue.fromLibrary(
      seed: seed,
      library: [other, compilation, featuring, stream, copy, sameArtist, seed, sameAlbum],
      excluded: excluded,
      limit: limit,
      random: Random(1),
    ).map((t) => t.id).toList();

    test('closest first: same album, then the same artist, then the rest', () {
      final ids = pick();
      expect(ids.first, 'album');
      expect(ids.sublist(1, 3), unorderedEquals(['artist', 'feat']));
      expect(ids.sublist(3), unorderedEquals(['other', 'comp']));
    });

    test('never the seed, a copy of it, a streamed song or an excluded one', () {
      final ids = pick(excluded: [sameArtist]);
      expect(ids, isNot(contains('seed')));
      expect(ids, isNot(contains('copy')));
      expect(ids, isNot(contains('yt:v1')));
      expect(ids, isNot(contains('artist')));
    });

    test('keeps to the limit', () => expect(pick(limit: 2), hasLength(2)));

    test('an empty library gives nothing', () {
      expect(RadioQueue.fromLibrary(seed: seed, library: const []), isEmpty);
    });

    test('interleave takes each list in turn', () {
      final a = [_song('a1'), _song('a2'), _song('a3')];
      final b = [_song('b1')];
      expect(RadioQueue.interleave(a, b).map((t) => t.id), ['a1', 'b1', 'a2', 'a3']);
    });
  });

  group('radio and autoplay from songs on this device', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    final seed = _song('seed', artist: 'Aimer', album: 'Daydream');
    final mate = _song('mate', artist: 'Aimer', album: 'Daydream');
    final stranger = _song('stranger', artist: 'YOASOBI');
    final played = _song('played', artist: 'Aimer');
    // Stands in for YouTube Music's pick, as a file so the test never streams.
    final online = _song('rec1', artist: 'milet');

    void prefs({required bool autoplay, List<Track> queue = const [], List<String> recent = const []}) =>
        SharedPreferences.setMockInitialValues({
          'library.v1': jsonEncode([
            for (final t in [seed, mate, stranger, played]) t.toJson(),
          ]),
          'autoplay.v1': autoplay,
          'discord.enabled': false,
          'recent.v1': recent,
          if (queue.isNotEmpty)
            'playback.queue.v1': jsonEncode({
              'tracks': [for (final t in queue) t.toJson()],
              'index': queue.length - 1,
              'positionMs': 0,
            }),
        });

    test('Start radio from a local song mixes the library with YouTube Music', () async {
      prefs(autoplay: false, queue: [seed]);
      final seeds = <String>[];
      final c = PlayerController(
        radioLookup: (track) async {
          seeds.add(track.id);
          return [online];
        },
      )..libraryRadioRandom = Random(1);
      addTearDown(c.dispose);
      await c.load();
      final station = await c.startRadio(seed);
      expect(seeds, ['seed'], reason: 'the local song itself is the seed for its YouTube Music match');
      expect(station?.kind, CollectionKind.radio);
      expect(station?.tracks.map((t) => t.id), ['seed', 'rec1', 'mate', 'stranger', 'played']);
      expect(c.recentRadios.value, [same(station)]);
      expect(c.queue.map((t) => t.id), station!.tracks.map((t) => t.id));
    });

    test('offline, Start radio from a local song still plays the library', () async {
      prefs(autoplay: false, queue: [seed]);
      final c = PlayerController(radioLookup: (_) async => throw Exception('offline'))..libraryRadioRandom = Random(1);
      addTearDown(c.dispose);
      await c.load();
      final station = await c.startRadio(seed);
      // The same artist's songs come first; two of theirs in a row are spaced by another artist.
      expect(station?.tracks.map((t) => t.id), ['seed', 'stranger', 'mate', 'played']);
    });

    test('a download seeds the radio with its own YouTube video', () async {
      final download = _song('dl', artist: 'Aimer', sourceUrl: 'https://music.youtube.com/watch?v=abcdefghijk');
      prefs(autoplay: false, queue: [download]);
      final seeds = <String?>[];
      final c = PlayerController(
        radioLookup: (track) async {
          seeds.add(track.youtubeId);
          return [online];
        },
      );
      addTearDown(c.dispose);
      await c.load();
      final station = await c.startRadio(download);
      expect(seeds, ['abcdefghijk']);
      expect(station?.tracks.map((t) => t.id), containsAll(['dl', 'rec1']));
    });

    test('autoplay at the end of a local queue appends similar songs, skipping recent plays', () async {
      prefs(autoplay: false, queue: [seed], recent: ['played']);
      final c = PlayerController(radioLookup: (_) async => throw Exception('offline'))..libraryRadioRandom = Random(1);
      addTearDown(c.dispose);
      await c.load();
      await c.setAutoplay(true);
      for (var i = 0; i < 50 && c.queue.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      // Two of Aimer's in a row are spaced by another artist.
      expect(c.queue.map((t) => t.id), ['seed', 'stranger', 'mate']);
      expect(c.isAutoplayed(mate), isTrue);
    });

    test('autoplay puts YouTube Music matches first, then the library', () async {
      prefs(autoplay: false, queue: [seed]);
      final c = PlayerController(radioLookup: (_) async => [online])..libraryRadioRandom = Random(1);
      addTearDown(c.dispose);
      await c.load();
      await c.setAutoplay(true);
      for (var i = 0; i < 50 && c.queue.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(c.queue.map((t) => t.id).take(3), ['seed', 'rec1', 'mate']);
    });

    test('with autoplay on, playing a local song fills the queue after it by itself', () async {
      JustAudioPlatform.instance = FakeAudioPlatform();
      prefs(autoplay: true);
      final c = PlayerController(radioLookup: (_) async => [online])..libraryRadioRandom = Random(1);
      addTearDown(c.dispose);
      await c.load();
      await c.playList([seed], 0);
      for (var i = 0; i < 50 && c.queue.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(c.queue.map((t) => t.id).take(2), ['seed', 'rec1']);
    });

    test('autoplay off leaves a local queue alone', () async {
      prefs(autoplay: false, queue: [seed]);
      var asked = 0;
      final c = PlayerController(
        radioLookup: (_) async {
          asked++;
          return [online];
        },
      );
      addTearDown(c.dispose);
      await c.load();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(asked, 0);
      expect(c.queue.map((t) => t.id), ['seed']);
    });
  });
}
