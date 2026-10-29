import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/youtube_links.dart';

const id = 'dQw4w9WgXcQ';
const pl = 'PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf';

void main() {
  group('videos', () {
    final cases = <String, YoutubeLink>{
      'https://www.youtube.com/watch?v=$id': const VideoLink(id),
      'http://youtube.com/watch?v=$id': const VideoLink(id),
      'youtube.com/watch?v=$id': const VideoLink(id),
      'www.youtube.com/watch?v=$id': const VideoLink(id),
      'https://m.youtube.com/watch?v=$id': const VideoLink(id),
      'https://music.youtube.com/watch?v=$id': const VideoLink(id),
      'https://music.youtube.com/watch?v=$id&si=abcDEF': const VideoLink(id),
      'HTTPS://WWW.YOUTUBE.COM/watch?v=$id': const VideoLink(id),
      'https://www.youtube.com/watch?feature=share&v=$id': const VideoLink(id),
      'https://www.youtube.com/watch?v=$id&pp=ygUHdGVzdA%3D%3D': const VideoLink(id),
      'https://www.youtube.com/watch?v=$id&utm_source=x&utm_medium=y': const VideoLink(id),
      'https://youtu.be/$id': const VideoLink(id),
      'youtu.be/$id': const VideoLink(id),
      'https://youtu.be/$id?si=AbCdEfGhIjKlMnOp': const VideoLink(id),
      'https://youtu.be/$id?feature=shared': const VideoLink(id),
      'https://youtu.be/$id/': const VideoLink(id),
      'https://www.youtube.com/shorts/$id': const VideoLink(id),
      'https://www.youtube.com/shorts/$id?si=AbCdEf': const VideoLink(id),
      'https://www.youtube.com/shorts/$id?feature=share': const VideoLink(id),
      'https://www.youtube.com/shorts/$id/': const VideoLink(id),
      'https://youtube.com/shorts/$id/?si=x': const VideoLink(id),
      'https://m.youtube.com/shorts/$id': const VideoLink(id),
      'https://www.youtube.com/live/$id': const VideoLink(id),
      'https://www.youtube.com/live/$id?feature=share': const VideoLink(id),
      'https://www.youtube.com/embed/$id': const VideoLink(id),
      'https://www.youtube.com/embed/$id?autoplay=1': const VideoLink(id),
      'https://www.youtube-nocookie.com/embed/$id': const VideoLink(id),
      'https://www.youtube.com/v/$id': const VideoLink(id),
      'https://www.youtube.com/e/$id': const VideoLink(id),
      'https://www.youtube.com/attribution_link?a=x&u=%2Fwatch%3Fv%3D$id%26feature%3Dshare': const VideoLink(id),
      'https://www.youtube.com/watch?v=-_-_-_-_-_-': const VideoLink('-_-_-_-_-_-'),
    };
    cases.forEach((input, expected) {
      test(input, () => expect(YoutubeLinks.parse(input), expected));
    });
  });

  group('start time', () {
    final cases = <String, Duration?>{
      'https://youtu.be/$id?t=90': const Duration(seconds: 90),
      'https://youtu.be/$id?t=90s': const Duration(seconds: 90),
      'https://youtu.be/$id?t=1m30s': const Duration(seconds: 90),
      'https://youtu.be/$id?t=1h2m3s': const Duration(hours: 1, minutes: 2, seconds: 3),
      'https://www.youtube.com/watch?v=$id&start=45': const Duration(seconds: 45),
      'https://www.youtube.com/watch?v=$id&t=1:30': const Duration(seconds: 90),
      'https://www.youtube.com/embed/$id?start=12': const Duration(seconds: 12),
      'https://youtu.be/$id?t=0': null,
      'https://youtu.be/$id?t=soon': null,
      'https://youtu.be/$id?si=abc': null,
    };
    cases.forEach((input, expected) {
      test(input, () {
        final link = YoutubeLinks.parse(input);
        expect(link, isA<VideoLink>());
        expect((link! as VideoLink).startAt, expected);
      });
    });
  });

  group('playlists', () {
    test(
      'playlist page',
      () => expect(YoutubeLinks.parse('https://www.youtube.com/playlist?list=$pl'), const PlaylistLink(pl)),
    );
    test('music playlist', () {
      expect(YoutubeLinks.parse('https://music.youtube.com/playlist?list=$pl&si=x'), const PlaylistLink(pl));
    });
    test('album playlist', () {
      const album = 'OLAK5uy_kAbCdEfGhIjKlMnOpQrStUvWxYz';
      expect(YoutubeLinks.parse('https://music.youtube.com/playlist?list=$album'), const PlaylistLink(album));
    });
    test('uploads playlist', () {
      const uploads = 'UUuAXFkgsw1L7xaCfnd5JJOw';
      expect(YoutubeLinks.parse('https://www.youtube.com/playlist?list=$uploads'), const PlaylistLink(uploads));
    });
    test('watch with list is a video in a playlist', () {
      final link = YoutubeLinks.parse('https://www.youtube.com/watch?v=$id&list=$pl&index=3');
      expect(link, const VideoInPlaylistLink(id, pl));
      expect(link, isA<VideoLink>());
    });
    test(
      'youtu.be with list',
      () => expect(YoutubeLinks.parse('https://youtu.be/$id?list=$pl'), const VideoInPlaylistLink(id, pl)),
    );
    test(
      'watch with only a list',
      () => expect(YoutubeLinks.parse('https://www.youtube.com/watch?list=$pl'), const PlaylistLink(pl)),
    );
    test('embed videoseries', () {
      expect(YoutubeLinks.parse('https://www.youtube.com/embed/videoseries?list=$pl'), const PlaylistLink(pl));
    });
    test(
      'junk list is no playlist',
      () => expect(YoutubeLinks.parse('https://www.youtube.com/playlist?list=abc'), isNull),
    );
    test('canonical urls', () {
      expect(const VideoLink(id).canonicalUrl, 'https://www.youtube.com/watch?v=$id');
      expect(const PlaylistLink(pl).canonicalUrl, 'https://www.youtube.com/playlist?list=$pl');
    });
  });

  group('inside shared text', () {
    test('after a sentence', () {
      expect(YoutubeLinks.parse('Check this out https://youtu.be/$id?si=abc via YouTube'), const VideoLink(id));
    });
    test('on its own line', () {
      expect(YoutubeLinks.parse('Song of the day\nhttps://music.youtube.com/watch?v=$id&si=q\n'), const VideoLink(id));
    });
    test('in parentheses', () => expect(YoutubeLinks.parse('(https://youtu.be/$id)'), const VideoLink(id)));
    test('before a full stop', () => expect(YoutubeLinks.parse('Listen: youtu.be/$id.'), const VideoLink(id)));
    test(
      'surrounding whitespace',
      () => expect(YoutubeLinks.parse('  \n https://youtu.be/$id \n'), const VideoLink(id)),
    );
    test('first usable link wins', () {
      expect(YoutubeLinks.parse('https://youtu.be/short then https://youtu.be/$id'), const VideoLink(id));
    });
  });

  group('bare ids', () {
    test('accepted only when asked', () {
      expect(YoutubeLinks.parse(id, allowBareId: true), const VideoLink(id));
      expect(YoutubeLinks.parse(' $id ', allowBareId: true), const VideoLink(id));
      expect(YoutubeLinks.parse(pl, allowBareId: true), const PlaylistLink(pl));
    });
    test('never by default', () {
      expect(YoutubeLinks.parse(id), isNull);
      expect(YoutubeLinks.parse(pl), isNull);
      expect(YoutubeLinks.looksLikeLink(id), isFalse);
    });
    test('helloworld1 is only an id in the paste field', () {
      expect(YoutubeLinks.looksLikeLink('helloworld1'), isFalse);
      expect(YoutubeLinks.parse('helloworld1', allowBareId: true), const VideoLink('helloworld1'));
    });
    test('wrong length is never an id', () {
      expect(YoutubeLinks.parse('abc', allowBareId: true), isNull);
      expect(YoutubeLinks.parse('dQw4w9WgXcQx', allowBareId: true), isNull);
      expect(YoutubeLinks.parse('hello world', allowBareId: true), isNull);
    });
  });

  group('not a link', () {
    const junk = [
      '',
      '   ',
      'helloworld1',
      'youtube rocks',
      'I love youtube',
      'youtube',
      'youtube.com',
      'https://www.youtube.com/',
      'https://www.youtube.com/feed/subscriptions',
      'https://www.youtube.com/@somechannel',
      'https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw',
      'https://www.youtube.com/watch?v=tooshort',
      'https://www.youtube.com/watch?v=has spaces!',
      'https://www.youtube.com/shorts/',
      'https://youtu.be/',
      'https://example.com/watch?v=$id',
      'https://example.com/shorts/$id',
      'https://notyoutube.com/watch?v=$id',
      'https://youtube.com.evil.com/watch?v=$id',
      'https://evil.com/youtube.com/watch?v=$id',
      'https://evil.com/?u=youtube.com/watch?v=$id',
      'https://youtube.com@evil.com/watch?v=$id',
      'https://vimeo.com/123456789',
      'https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC',
      'dQw4w9WgXcQ is a song',
    ];
    for (final text in junk) {
      test('"$text"', () {
        expect(YoutubeLinks.parse(text), isNull);
        expect(YoutubeLinks.looksLikeLink(text), isFalse);
      });
    }
  });
}
