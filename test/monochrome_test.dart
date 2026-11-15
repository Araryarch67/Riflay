import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/incoming_links.dart';
import 'package:riflay/services/monochrome.dart';
import 'package:riflay/services/monochrome_audio_source.dart';
import 'package:riflay/services/playlist_transfer.dart';

void main() {
  const native = {
    'trackId': '155102871061270528',
    'title': 'One More Time',
    'artistNames': ['Daft Punk'],
    'duration': 320357,
    'artwork': 'https://tracks.monochrome.st/proxy/cover.jpg',
  };
  test('share URLs accept supported hosts and preserve provider ids', () {
    for (final kind in ['track', 'album', 'playlist', 'userplaylist']) {
      final url = 'https://monochrome.st/$kind/tracks%3Atrack%3A123?share=1';
      final link = MonochromeLink.parse('Listen: $url');
      expect((link?.kind, link?.id), (kind, 'tracks:track:123'));
      expect(IncomingLinks.isLink(url), isTrue);
      expect(PlaylistTransfer.looksLikeLink(url), kind != 'track');
    }
    for (final bad in [
      'https://monochrome.st.evil/track/123',
      'https://evil/track/123',
      'https://monochrome.st/track/..',
      'https://monochrome.st/artist/123',
      'https://monochrome.st/track/a%2Fb',
      'file://monochrome.st/track/123',
    ]) {
      expect(MonochromeLink.parse(bad), isNull, reason: bad);
    }
  });

  test('search yields persistent streaming tracks with millisecond durations', () async {
    final api = Monochrome(
      client: MockClient((r) async {
        expect(r.url.path, '/search/tracks');
        expect(r.url.queryParameters, {'q': 'Daft & Punk', 'limit': '2'});
        expect(r.headers.containsKey('origin'), isFalse);
        return http.Response(
          jsonEncode({
            'tracks': [
              native,
              {...native, 'playable': false},
            ],
          }),
          200,
        );
      }),
    );
    final songs = await api.search(' Daft & Punk ', limit: 2);
    expect(songs, hasLength(1));
    final t = Track.fromJson(songs.single.toJson());
    expect(t.uri.toString(), '${Monochrome.tracksBase}/track/155102871061270528');
    expect(t.artist, 'Daft Punk');
    expect(t.duration, const Duration(milliseconds: 320357));
    expect(t.streams, isTrue);
    expect(t.isRemote, isFalse);
    expect(t.path, isNull);
    expect(t.source, TrackSource.monochrome);
  });

  test('refused and malformed responses fail instead of becoming empty search results', () async {
    for (final response in [http.Response('{}', 403), http.Response('{}', 200)]) {
      final api = Monochrome(client: MockClient((_) async => response));
      await expectLater(api.search('song'), throwsA(anything));
    }
  });

  test('native albums use the release endpoint and inherit artwork', () async {
    final api = Monochrome(
      client: MockClient((r) async {
        expect(r.url.path, '/releases/123');
        return http.Response(
          jsonEncode({
            'title': 'Discovery',
            'artwork': 'https://example.org/cover.jpg',
            'tracks': [
              {...native, 'artwork': null},
            ],
          }),
          200,
        );
      }),
    );
    final page = await api.resolve(const MonochromeLink('album', 'tracks:album:123'));
    expect(page.title, 'Discovery');
    expect(page.tracks.single.album, 'Discovery');
    expect(page.tracks.single.artworkUrl, 'https://example.org/cover.jpg');
  });

  test('playlist import follows pagination and retains original source tracks', () async {
    final transfer = PlaylistTransfer(
      client: MockClient((r) async {
        final offset = int.parse(r.url.queryParameters['offset']!);
        return http.Response(
          jsonEncode({
            'data': {
              'playlist': {'title': 'Mix', 'numberOfTracks': 3},
              'items': [
                for (var i = offset; i < (offset == 0 ? 2 : 3); i++)
                  {
                    'item': {
                      'id': i + 1,
                      'title': 'Song $i',
                      'artist': {'name': 'Artist'},
                      'duration': 123,
                    },
                  },
              ],
            },
          }),
          200,
        );
      }),
    );
    addTearDown(transfer.close);
    final page = await transfer.read('https://monochrome.st/playlist/demo');
    expect(page.nativeTracks?.map((t) => t.monochromeId), ['1', '2', '3']);
    expect(page.songs.map((t) => t.title), ['Song 0', 'Song 1', 'Song 2']);
    expect(page.title, 'Mix');
  });

  test('an ignored offset fails without silently importing a partial playlist', () async {
    final api = Monochrome(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'playlist': {'title': 'Mix', 'numberOfTracks': 3},
            'items': [
              {'id': 1, 'title': 'First'},
            ],
          }),
          200,
        ),
      ),
    );
    await expectLater(api.resolve(const MonochromeLink('playlist', 'demo')), throwsFormatException);
  });

  test('public user playlists accept serialized tracks, keeping native provider ids', () async {
    final api = Monochrome(
      client: MockClient((r) async {
        expect(r.url.host, 'auth.monochrome.st');
        expect(r.url.path, '/api/public/playlists/demo');
        return http.Response(
          jsonEncode({
            'name': 'My mix',
            'tracks': jsonEncode([
              {'item_id': 'tracks:track:155102871061270528', 'metadata': native},
            ]),
          }),
          200,
        );
      }),
    );
    final page = await api.resolve(const MonochromeLink('userplaylist', 'demo'));
    expect(page.tracks.single.uri.host, 'tracks.monochrome.st');
    expect(page.title, 'My mix');
  });

  test('legacy playback decodes manifests on request and honors byte ranges', () async {
    var calls = 0;
    final api = Monochrome(
      client: MockClient((r) async {
        calls++;
        expect(r.url.queryParameters, {'id': '123', 'quality': 'LOSSLESS'});
        return http.Response(
          jsonEncode({
            'data': {
              'manifest': base64Encode(
                utf8.encode(
                  jsonEncode({
                    'urls': ['https://example.org/audio.flac'],
                  }),
                ),
              ),
            },
          }),
          200,
        );
      }),
    );
    final source = MonochromeAudioSource('123', client: api);
    expect(calls, 0);
    final response = await source.request();
    final bytes = await response.stream.expand((e) => e).toList();
    expect(utf8.decode(bytes), contains('https://example.org/audio.flac'));
    expect(response.contentType, 'application/vnd.apple.mpegurl');
    final range = await source.request(1, 6);
    expect(await range.stream.expand((e) => e).toList(), bytes.sublist(1, 6));
    expect(range.offset, 1);
    expect(range.sourceLength, bytes.length);
  });
}
