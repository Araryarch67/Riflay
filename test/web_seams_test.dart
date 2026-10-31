import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riflay/platform/background.dart';
import 'package:riflay/platform/features.dart';
import 'package:riflay/platform/host.dart';
import 'package:riflay/platform/network.dart';
import 'package:riflay/platform/proxy_client.dart';
import 'package:riflay/platform/proxy_route.dart';
import 'package:riflay/services/youtube_player_api.dart';

/// The seams that keep the web build apart (lib/platform): native builds must see exactly what they saw before, and
/// the web build's routing must send only what the proxy forwards.
void main() {
  final proxy = Uri.parse('http://localhost:8787/');

  group('native side of the seams', () {
    test('Host answers what dart:io answers', () {
      expect(Host.isWeb, isFalse);
      expect(Host.isLinux, Platform.isLinux);
      expect(Host.isWindows, Platform.isWindows);
      expect(Host.isMacOS, Platform.isMacOS);
      expect(Host.isAndroid, Platform.isAndroid);
      expect(Host.isIOS, Platform.isIOS);
      expect(Host.environment, Platform.environment);
      expect(Host.pathSeparator, Platform.pathSeparator);
    });

    test('every feature is on', () {
      expect(Features.localLibrary, isTrue);
      expect(Features.downloads, isTrue);
      expect(Features.youtubeSignIn, isTrue);
      expect(Features.playlistImport, isTrue);
      expect(Features.casting, isTrue);
      expect(Features.listenTogether, isTrue);
      expect(Features.discord, isTrue);
      expect(Features.videoMode, isTrue);
      expect(Features.miniPlayer, isTrue);
      expect(Features.listeningHistory, isTrue);
    });

    test('no proxy: URLs stay as they are and songs stream the native way', () {
      final url = Uri.parse('https://music.youtube.com/youtubei/v1/search?prettyPrint=false');
      expect(webProxy, isNull);
      expect(routed(url), url);
      expect(webAudioUri('dQw4w9WgXcQ'), isNull);
      expect(runWithNetwork(() => 42), 42);
    });

    test('background work runs and returns its result', () async {
      expect(await inBackground(() => [for (var i = 0; i < 4; i++) i * i]), [0, 1, 4, 9]);
    });
  });

  group('proxy routes', () {
    test('InnerTube calls go to /fetch/<host>/<path> with their query', () {
      final out = toProxy(
        Uri.parse('https://music.youtube.com/youtubei/v1/browse?prettyPrint=false'),
        proxy,
        method: 'POST',
      );
      expect(out.toString(), 'http://localhost:8787/fetch/music.youtube.com/youtubei/v1/browse?prettyPrint=false');
      expect(
        fromProxy('POST', out!.path, out.query).toString(),
        'https://music.youtube.com/youtubei/v1/browse?prettyPrint=false',
      );
    });

    test('a proxy under a path keeps it', () {
      final out = toProxy(Uri.parse('https://lrclib.net/api/get?x=1'), Uri.parse('https://example.org/riflay/'));
      expect(out.toString(), 'https://example.org/riflay/fetch/lrclib.net/api/get?x=1');
    });

    test('only the listed hosts, paths and methods are forwarded', () {
      expect(isForwarded('POST', 'music.youtube.com', '/youtubei/v1/search'), isTrue);
      expect(isForwarded('GET', 'music.youtube.com', '/youtubei/v1/search'), isFalse);
      expect(isForwarded('POST', 'www.youtube.com', '/account'), isFalse);
      expect(isForwarded('GET', 'www.youtube.com', '/watch'), isTrue);
      expect(isForwarded('GET', 'rr3---sn-abc.googlevideo.com', '/videoplayback'), isTrue);
      expect(isForwarded('POST', 'rr3---sn-abc.googlevideo.com', '/videoplayback'), isFalse);
      expect(isForwarded('GET', 'evil-googlevideo.com', '/videoplayback'), isFalse);
      expect(isForwarded('GET', 'lh3.googleusercontent.com', '/abc=w120'), isTrue);
      expect(isForwarded('POST', 'lh3.googleusercontent.com', '/abc'), isFalse);
      expect(isForwarded('GET', 'example.com', '/'), isFalse);
      expect(toProxy(Uri.parse('https://example.com/'), proxy), isNull);
      expect(toProxy(Uri.parse('http://lrclib.net/api/get'), proxy), isNull, reason: 'plain http is never sent');
    });

    test('a proxy path that names no allowed host is refused', () {
      expect(fromProxy('GET', '/fetch/example.com/', ''), isNull);
      expect(fromProxy('GET', '/fetch/lrclib.net:8080/api/get', ''), isNull);
      expect(fromProxy('GET', '/fetch/user@lrclib.net/api/get', ''), isNull);
      expect(fromProxy('GET', '/other/lrclib.net/api/get', ''), isNull);
    });

    test('songs play from /audio/<videoId>, AAC on request', () {
      expect(audioOnProxy('dQw4w9WgXcQ', proxy).toString(), 'http://localhost:8787/audio/dQw4w9WgXcQ');
      expect(audioOnProxy('dQw4w9WgXcQ', proxy, aac: true).query, 'aac=1');
      expect(isVideoId('dQw4w9WgXcQ'), isTrue);
      expect(isVideoId('../etc/pass'), isFalse);
      expect(isVideoId('short'), isFalse);
    });
  });

  group('ProxyClient', () {
    test('sends forwarded requests to the proxy, with the headers a browser blocks renamed', () async {
      late http.Request seen;
      final client = ProxyClient(
        MockClient((r) async {
          seen = r;
          return http.Response('{"ok":true}', 200);
        }),
        proxy,
      );
      final res = await client.post(
        Uri.parse('https://music.163.com/api/song/lyric?id=1'),
        headers: {'User-Agent': 'Mozilla/5.0', 'Cookie': 'os=pc', 'content-type': 'application/json'},
        body: jsonEncode({'a': 1}),
      );
      expect(res.body, '{"ok":true}');
      expect(seen.url.toString(), 'http://localhost:8787/fetch/music.163.com/api/song/lyric?id=1');
      expect(seen.method, 'POST');
      expect(seen.headers['x-riflay-user-agent'], 'Mozilla/5.0');
      expect(seen.headers['x-riflay-cookie'], 'os=pc');
      expect(seen.headers['content-type'], startsWith('application/json'));
      expect(seen.headers.keys.map((k) => k.toLowerCase()), isNot(contains('user-agent')));
      expect(jsonDecode(seen.body), {'a': 1});
    });

    test('leaves requests the proxy does not forward alone', () async {
      late http.Request seen;
      final client = ProxyClient(
        MockClient((r) async {
          seen = r;
          return http.Response('', 204);
        }),
        proxy,
      );
      await client.get(Uri.parse('https://api.github.com/repos/x/y'), headers: {'User-Agent': 'Riflay'});
      expect(seen.url.toString(), 'https://api.github.com/repos/x/y');
      expect(seen.headers['User-Agent'], 'Riflay');
    });
  });

  group('YoutubePlayerApi', () {
    Map<String, dynamic> format(int itag, String mime, int bitrate, {bool drc = false}) => {
      'itag': itag,
      'mimeType': mime,
      'averageBitrate': bitrate,
      'url': 'https://rr1---sn.googlevideo.com/videoplayback?itag=$itag&expire=1900000000',
      'isDrc': ?(drc ? true : null),
    };

    test('Opus wins a near tie, AAC when asked, never the stable-volume copy', () {
      final formats = [
        format(140, 'audio/mp4; codecs="mp4a.40.2"', 130000),
        format(251, 'audio/webm; codecs="opus"', 120000),
        format(774, 'audio/webm; codecs="opus"', 260000, drc: true),
        format(137, 'video/mp4; codecs="avc1"', 4000000),
      ];
      expect(YoutubePlayerApi.pickBest(formats, aacOnly: false)?['itag'], 251);
      expect(YoutubePlayerApi.pickBest(formats, aacOnly: true)?['itag'], 140);
    });

    test('reads the visitor id, a URL expiry and why a song cannot play', () {
      expect(
        YoutubePlayerApi.visitorFrom({
          'responseContext': {'visitorData': 'abc'},
        }),
        'abc',
      );
      expect(YoutubePlayerApi.visitorFrom('nope'), isNull);
      expect(
        YoutubePlayerApi.urlExpiry(Uri.parse('https://x.googlevideo.com/videoplayback?expire=1900000000')),
        DateTime.fromMillisecondsSinceEpoch(1900000000 * 1000),
      );
      expect(
        YoutubePlayerApi.unplayable({
          'playabilityStatus': {'status': 'OK'},
        }),
        isNull,
      );
      expect(
        YoutubePlayerApi.unplayable({
          'playabilityStatus': {'status': 'LOGIN_REQUIRED', 'reason': 'Sign in'},
        }),
        'Sign in',
      );
    });
  });
}
