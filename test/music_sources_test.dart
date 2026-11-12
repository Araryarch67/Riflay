import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riflay/services/sources/internet_archive.dart';
import 'package:riflay/services/sources/music_sources.dart';
import 'package:riflay/services/sources/radio_paradise.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _item = ArchiveItem(id: 'demo1999', title: 'Live at the Hall', creator: 'The Demos', year: 1999);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MusicSources.instance.reset();
  });

  test('a search asks only for recordings with FLAC, without letting what was typed become query syntax', () async {
    late Uri asked;
    final archive = InternetArchive(
      client: MockClient((req) async {
        asked = req.url;
        return http.Response(
          jsonEncode({
            'response': {
              'docs': [
                {'identifier': 'demo1999', 'title': 'Live at the Hall', 'creator': 'The Demos', 'year': '1999'},
                {
                  'identifier': 'net001',
                  'creator': ['A', 'B'],
                },
              ],
            },
          }),
          200,
        );
      }),
    );
    final items = await archive.search('demos (live) "hall"');
    expect(asked.host, 'archive.org');
    final q = asked.queryParameters['q']!;
    expect(q, contains('format:(Flac OR "24bit Flac")'));
    expect(q, contains('collection:(etree OR netlabels)'), reason: 'open uploads carry licenses as typed');
    expect(q, startsWith('(demos live hall) AND'));
    expect(items.map((i) => (i.id, i.title, i.creator, i.year)), [
      ('demo1999', 'Live at the Hall', 'The Demos', 1999),
      ('net001', 'net001', 'A, B', null),
    ]);
    expect(await archive.search(' "()" '), isEmpty, reason: 'nothing left to look for');
  });

  test('an item\'s FLAC files become songs in order, private ones left out', () {
    final tracks = InternetArchive.parseFiles(_item, {
      'metadata': {'title': 'Live at the Hall', 'creator': 'The Demos'},
      'files': [
        {'name': 'd1t02.flac', 'format': 'Flac', 'title': 'Second', 'track': '2', 'length': '05:12'},
        {'name': 'd1t01.flac', 'format': 'Flac', 'title': 'First', 'track': '1/10', 'length': '312.45'},
        {'name': 'd1t01.mp3', 'format': 'VBR MP3', 'title': 'First'},
        {'name': 'hi/d1t03.flac', 'format': '24bit Flac', 'length': '1:02:03'},
        {'name': 'sbd.flac', 'format': 'Flac', 'private': 'true'},
      ],
    });
    expect(tracks.map((t) => t.title), ['First', 'Second', 'd1t03']);
    expect(tracks.first.uri.toString(), 'https://archive.org/download/demo1999/d1t01.flac');
    expect(tracks.first.duration, const Duration(milliseconds: 312450));
    expect(tracks[1].duration, const Duration(minutes: 5, seconds: 12));
    expect(tracks[2].duration, const Duration(hours: 1, minutes: 2, seconds: 3));
    expect(tracks.first.artist, 'The Demos');
    expect(tracks.first.artworkUrl, 'https://archive.org/services/img/demo1999');
    expect(tracks.first.id, startsWith(InternetArchive.prefix));
    expect(
      InternetArchive.parseFiles(_item, {
        'metadata': {'access-restricted-item': 'true'},
        'files': [
          {'name': 'a.flac', 'format': 'Flac'},
        ],
      }),
      isEmpty,
      reason: 'a restricted item plays only on the site',
    );
  });

  test('untagged files are named for what sets them apart from the item\'s other files', () {
    final tracks = InternetArchive.parseFiles(_item, {
      'metadata': {'title': 'Pack'},
      'files': [
        {'name': 'set/Pack 2025 ～Secret～_AZKi_Special Voice.flac', 'format': 'Flac'},
        {'name': 'set/Pack 2025 ～Secret～_Aqua_Special Voice.flac', 'format': 'Flac'},
      ],
    });
    expect(tracks.map((t) => t.title), ['AZKi Special Voice', 'Aqua Special Voice']);
    final numbered = InternetArchive.parseFiles(_item, {
      'files': [
        {'name': 'Track 1.flac', 'format': 'Flac'},
        {'name': 'Track 12.flac', 'format': 'Flac'},
      ],
    });
    expect(numbered.map((t) => t.title), ['1', '12'], reason: 'cut at a word, never inside a number');
  });

  test('Radio Paradise: four FLAC channels from its own servers, and what each plays now', () {
    expect(RadioParadise.channels.map((c) => c.track.uri.toString()), [
      'https://stream.radioparadise.com/flac',
      'https://stream.radioparadise.com/mellow-flac',
      'https://stream.radioparadise.com/rock-flac',
      'https://stream.radioparadise.com/global-flac',
    ]);
    expect(
      RadioParadise.channels[1].track.artworkUrl,
      'https://img.radioparadise.com/channels/0/1/cover_512x512/0.jpg',
      reason: 'a cover from the start',
    );
    final song = RadioParadise.parseNowPlaying(
      '{"artist":"Energy 52","title":"Cafe del Mar","album":"Café del Mar","cover_med":"https://img/26999.jpg"}',
    );
    expect(song, (artist: 'Energy 52', title: 'Cafe del Mar', album: 'Café del Mar', cover: 'https://img/26999.jpg'));
    expect(RadioParadise.parseNowPlaying('{"title":""}'), isNull);
  });

  test('both sources are on until turned off, and stay as set', () async {
    final s = MusicSources.instance;
    await s.load();
    expect((s.archive, s.radioParadise), (true, true));
    await s.setArchive(false);
    s.reset();
    await s.load();
    expect((s.archive, s.radioParadise), (false, true));
  });
}
