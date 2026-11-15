// ignore_for_file: experimental_member_use
import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/monochrome.dart';
import 'package:riflay/services/smart_merge.dart';
import 'package:riflay/services/sources/music_sources.dart';
import 'package:shared_preferences/shared_preferences.dart';

Track _youtube({String title = 'Glass Weather', String artist = 'Marlow Quartet', int seconds = 200}) => Track.youtube(
  videoId: 'abcdefghijk',
  title: title,
  artist: artist,
  duration: Duration(seconds: seconds),
);

Track _mono(String id, {String title = 'Glass Weather', String artist = 'Marlow Quartet', int? seconds = 200}) => Track(
  id: 'monochrome:$id',
  uri: Uri.parse('https://tracks.monochrome.st/track/${id.split(':').last}'),
  title: title,
  artist: artist,
  duration: seconds == null ? null : Duration(seconds: seconds),
);

Track _file(String path, {String title = 'Glass Weather', String artist = 'Marlow Quartet', int seconds = 200}) =>
    Track(
      id: path,
      uri: Uri.file(path),
      title: title,
      artist: artist,
      duration: Duration(seconds: seconds),
    );

/// A streaming source that answers from [results].
class _Source implements MergeProvider {
  _Source(
    this.name,
    this.results, {
    this.fails = false,
    this.streamFails = false,
    this.on = true,
    this.searcher,
    this.resolver,
  });
  @override
  final String name;
  @override
  bool on;
  final List<Track> results;
  final bool fails;
  final bool streamFails;
  final asked = <String>[];
  final Future<List<Track>> Function(String)? searcher;
  final Future<String> Function(Track)? resolver;

  @override
  Future<List<Track>> search(String query) async {
    asked.add(query);
    if (searcher != null) return searcher!(query);
    if (fails) throw const FormatException('down');
    return results;
  }

  @override
  Future<String> stream(Track match) async {
    if (resolver != null) return resolver!(match);
    if (streamFails) throw const FormatException('gone');
    return 'https://$name.example/${match.id}';
  }
}

class _Monochrome extends Monochrome {
  @override
  Future<String> manifest(String id) async => 'https://cdn.example/$id.flac';
}

class _Youtube extends StreamAudioSource {
  var requests = 0;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    requests++;
    return StreamAudioResponse(
      sourceLength: 3,
      contentLength: 3,
      offset: 0,
      contentType: 'audio/webm',
      stream: Stream.value([1, 2, 3]),
    );
  }
}

SmartMerge _merge(List<MergeProvider> providers) => SmartMerge(providers: providers, enabled: () => true);

Future<String> _body(StreamAudioResponse r) async => utf8.decode([await for (final chunk in r.stream) ...chunk]);

void main() {
  test('automatic matching rejects near titles, misleading credits and unknown artists', () {
    expect(
      SmartMerge.same(_youtube(title: 'One Two Three Four'), _mono('1', title: 'One Two Three Four Five')),
      isFalse,
    );
    expect(SmartMerge.same(_youtube(title: 'Glass Weather (Soft Mix)'), _mono('1')), isFalse);
    expect(
      SmartMerge.same(
        _youtube(title: 'Marlow Quartet', artist: 'Other Artist'),
        _mono('1', title: 'Marlow Quartet', artist: 'Marlow Quartet'),
      ),
      isFalse,
    );
    expect(SmartMerge.same(_youtube(artist: Track.unknownArtist), _mono('1', artist: Track.unknownArtist)), isFalse);
    expect(SmartMerge.same(_youtube(), _mono('1').copyWith(duration: const Duration(milliseconds: 203001))), isFalse);
    expect(SmartMerge.same(_youtube(seconds: 0), _mono('1', seconds: 0)), isFalse);
  });

  test('conflicting recording IDs reject a same-title candidate', () {
    final origin = Track.fromJson({
      ..._youtube().toJson(),
      'extensionData': {'isrc': 'A1'},
    });
    final candidate = Track.fromJson({
      ..._mono('1').toJson(),
      'extensionData': {'isrc': 'B2'},
    });
    expect(SmartMerge.same(origin, candidate), isFalse);
  });

  test('enabled providers and changed metadata invalidate cached answers', () async {
    final preferred = _Source('preferred', [_mono('1')], on: false);
    final other = _Source('other', [_mono('2')]);
    final merge = _merge([preferred, other]);
    expect((await merge.match(_youtube())).first.provider, same(other));
    preferred.on = true;
    expect((await merge.match(_youtube())).first.provider, same(preferred));
    preferred.on = other.on = false;
    expect(await merge.match(_youtube()), isEmpty);
    preferred.on = true;
    expect((await merge.match(_youtube())).single.provider, same(preferred));
    expect(preferred.asked.length, 2);
    expect(await merge.match(_youtube(title: 'Other Song')), isEmpty);
  });

  test('a late old failure cannot evict a newer cached match', () async {
    final pending = Completer<List<Track>>();
    var calls = 0;
    final provider = _Source(
      'source',
      [],
      searcher: (_) async {
        if (++calls == 1) return pending.future;
        return [_mono('2')];
      },
    );
    final merge = _merge([provider]);
    final old = merge.match(_youtube());
    merge.clear();
    expect((await merge.match(_youtube())).single.track.id, 'monochrome:2');
    pending.completeError(const FormatException('old failure'));
    await old;
    await merge.match(_youtube());
    expect(calls, 2);
  });

  test('a hanging catalogue is bounded and does not suppress another source', () async {
    final pending = Completer<List<Track>>();
    final merge = SmartMerge(
      providers: [
        _Source('hung', [], searcher: (_) => pending.future),
        _Source('working', [_mono('1')]),
      ],
      enabled: () => true,
      lookupTimeout: const Duration(milliseconds: 5),
    );
    expect((await merge.match(_youtube())).single.provider.name, 'working');
  });

  test('a hanging resolver or invalid payload falls through to a working source', () async {
    final pending = Completer<String>();
    final merge = SmartMerge(
      providers: [
        _Source('hung', [_mono('1')], resolver: (_) => pending.future),
        _Source('invalid', [_mono('2')], resolver: (_) async => 'https://audio.example/file\n#bad'),
        _Source('html', [_mono('3')], resolver: (_) async => '<html>Error</html>'),
        _Source('working', [_mono('4')]),
      ],
      enabled: () => true,
      streamTimeout: const Duration(milliseconds: 5),
    );
    final source = SmartMergeAudioSource(_youtube(), youtube: _Youtube(), merge: merge);
    expect(await _body(await source.request()), contains('https://working.example/'));
    expect(source.from?.name, 'working');
  });

  test('queued sources honour disable and discard stale in-flight resolution', () async {
    var enabled = true;
    final pending = Completer<String>();
    final merge = SmartMerge(
      providers: [
        _Source('source', [_mono('1')], resolver: (_) => pending.future),
      ],
      enabled: () => enabled,
    );
    final youtube = _Youtube();
    final source = SmartMergeAudioSource(_youtube(), youtube: youtube, merge: merge);
    enabled = false;
    expect((await source.request()).contentType, 'audio/webm');
    expect(source.from, isNull);

    enabled = true;
    final other = SmartMergeAudioSource(_youtube(), youtube: youtube, merge: merge);
    final response = other.request();
    await pumpEventQueue();
    merge.clear();
    pending.complete('https://audio.example/file.flac');
    expect((await response).contentType, 'audio/webm');
    expect(other.from, isNull);
    expect(merge.wants(_youtube()), isTrue);
  });

  test('missing local matches are skipped, measured ALAC is accepted, and failed local audio falls back', () {
    final merge = _merge([]);
    final missing = _file('/missing.flac');
    final available = _file('/available.flac');
    expect(merge.local(_youtube(), [missing, available], 1, available: (track) => track != missing), same(available));
    final alac = _file('/audio.m4a').copyWith(audioQuality: 'ALAC · 24-bit / 96 kHz');
    expect(merge.local(_youtube(), [alac], 2), same(alac));
    merge.markUsed('abcdefghijk');
    merge.giveUp('abcdefghijk');
    expect(merge.local(_youtube(), [alac], 2), isNull);
    merge.clear();
    expect(merge.local(_youtube(), [alac], 2), same(alac));
  });

  group('the same recording', () {
    test('is taken when title, artist and length agree', () {
      final match = _mono('tracks:track:1');
      expect(SmartMerge.best(_youtube(), [_mono('tracks:track:9', title: 'Other Song'), match]), same(match));
    });

    test('is not taken when the length differs or is unknown', () {
      expect(SmartMerge.best(_youtube(), [_mono('tracks:track:1', seconds: 215)]), isNull);
      expect(SmartMerge.best(_youtube(), [_mono('tracks:track:1', seconds: null)]), isNull);
      expect(
        SmartMerge.best(Track.youtube(videoId: 'abcdefghijk', title: 'Glass Weather', artist: 'Marlow Quartet'), [
          _mono('tracks:track:1'),
        ]),
        isNull,
        reason: 'a YouTube song without a length cannot be checked',
      );
    });

    test('is not taken for another version, another artist or a different title', () {
      expect(SmartMerge.best(_youtube(), [_mono('tracks:track:1', title: 'Glass Weather (Live)')]), isNull);
      expect(SmartMerge.best(_youtube(title: 'Glass Weather (Remix)'), [_mono('tracks:track:1')]), isNull);
      expect(SmartMerge.best(_youtube(), [_mono('tracks:track:1', artist: 'Someone Else')]), isNull);
      expect(SmartMerge.best(_youtube(), [_mono('tracks:track:1', title: 'Paper Moons')]), isNull);
    });

    test('is found across spacing, artist order and scripts, and a bracketed addition', () {
      final match = _mono('tracks:track:1', title: 'I I I', artist: '宝鐘マリン, Kobo Kanaeru', seconds: 186);
      expect(
        SmartMerge.best(_youtube(title: 'III', artist: 'Kobo Kanaeru & Houshou Marine', seconds: 187), [match]),
        same(match),
      );
      expect(
        SmartMerge.best(_youtube(title: 'I I I (Official MV)', artist: 'Kobo Kanaeru', seconds: 188), [match]),
        same(match),
      );
      expect(
        SmartMerge.best(_youtube(title: 'III', artist: 'Sleep Theory', seconds: 186), [match]),
        isNull,
        reason: 'the same title by nobody in common is another song',
      );
      expect(SmartMerge.best(_youtube(artist: 'Marlow Band'), [_mono('1', artist: 'Marlow B')]), isNull);
    });

    test('the closest in length wins among the same recording', () {
      final near = _mono('2', seconds: 200), far = _mono('1', seconds: 202);
      expect(SmartMerge.best(_youtube(), [far, near]), same(near));
    });

    test('is still found when YouTube Music names more artists', () {
      final match = _mono('tracks:track:1');
      expect(SmartMerge.best(_youtube(artist: 'Marlow Quartet, Nova Vesper'), [match]), same(match));
    });
  });

  test('a song is looked up once, and a lookup with a source down is asked again later', () async {
    final found = _Source('a', [_mono('tracks:track:1')]);
    final merge = _merge([found]);
    expect((await merge.match(_youtube())).single.track.id, 'monochrome:tracks:track:1');
    await merge.match(_youtube());
    expect(found.asked, ['Glass Weather'], reason: 'by title; the artist is only asked when that finds nothing');

    final down = _Source('b', const [], fails: true);
    final failing = _merge([down]);
    expect(await failing.match(_youtube()), isEmpty);
    await pumpEventQueue();
    await failing.match(_youtube());
    expect(down.asked, hasLength(2));
  });

  test('every source that is on is asked, in order of preference, and one that is off is left alone', () async {
    final first = _Source('first', [_mono('1')]);
    final off = _Source('off', [_mono('2')], on: false);
    final down = _Source('down', const [], fails: true);
    final last = _Source('last', [_mono('3')]);
    final matches = await _merge([first, off, down, last]).match(_youtube());
    expect([for (final m in matches) m.provider.name], ['first', 'last']);
    expect(off.asked, isEmpty);
  });

  test('a matched song plays from the first source that has it, and YouTube is never asked', () async {
    final youtube = _Youtube();
    final source = SmartMergeAudioSource(
      _youtube(),
      youtube: youtube,
      merge: _merge([
        _Source('first', [_mono('77')]),
        _Source('second', [_mono('88')]),
      ]),
    );
    final response = await source.request();
    expect(response.contentType, 'application/vnd.apple.mpegurl');
    expect(await _body(response), contains('https://first.example/monochrome:77'));
    expect(source.from?.name, 'first');
    await source.request(0, 10);
    expect(youtube.requests, 0);
  });

  test('when the best source cannot stream it, the next one that has it plays', () async {
    final source = SmartMergeAudioSource(
      _youtube(),
      youtube: _Youtube(),
      merge: _merge([
        _Source('first', [_mono('77')], streamFails: true),
        _Source('second', [_mono('88')]),
      ]),
    );
    expect(await _body(await source.request()), contains('https://second.example/monochrome:88'));
  });

  test('Monochrome: a native song plays from its address, an older share from a fresh manifest', () async {
    final provider = MonochromeMerge(_Monochrome());
    expect(await provider.stream(_mono('tracks:track:77')), 'https://tracks.monochrome.st/track/77');
    expect(await provider.stream(_mono('12345')), 'https://cdn.example/12345.flac');
  });

  test('without a match, or when no source can stream it, the song plays from YouTube', () async {
    final youtube = _Youtube();
    final none = SmartMergeAudioSource(_youtube(), youtube: youtube, merge: _merge([_Source('a', const [])]));
    expect((await none.request()).contentType, 'audio/webm');

    final merge = _merge([
      _Source('a', [_mono('12345')], streamFails: true),
    ]);
    final broken = SmartMergeAudioSource(_youtube(), youtube: youtube, merge: merge);
    expect((await broken.request()).contentType, 'audio/webm');
    expect(youtube.requests, 2);
    expect(merge.gaveUpOn('abcdefghijk'), isTrue);
    expect(merge.wants(_youtube()), isFalse, reason: 'the rest of the session stays on YouTube');
  });

  test('merged sound that failed to play is not tried again', () async {
    final merge = _merge([
      _Source('a', [_mono('tracks:track:1')]),
    ]);
    merge.giveUp('abcdefghijk');
    expect(merge.wants(_youtube()), isTrue, reason: 'a song that was never merged has nothing to give up');
    await merge.match(_youtube());
    merge.giveUp('abcdefghijk');
    expect(merge.wants(_youtube()), isFalse);
  });

  test('a lossless file of the same recording in the library plays first', () {
    final merge = _merge(const []);
    final flac = _file('/music/Glass Weather.flac');
    final library = [
      _file('/music/Glass Weather.mp3'),
      _file('/music/Paper Moons.flac', title: 'Paper Moons'),
      _file('/music/Glass Weather (Live).flac', title: 'Glass Weather (Live)'),
      flac,
    ];
    expect(merge.local(_youtube(), library, 1), same(flac));
    expect(merge.local(_youtube(), [library.first], 2), isNull, reason: 'a lossy file is no better than the stream');
    expect(merge.local(_youtube(seconds: 260), library, 3), isNull, reason: 'another length is another recording');
    expect(merge.local(_youtube(), const [], 3), same(flac), reason: 'the same revision keeps its index');
    expect(merge.local(_youtube(), const [], 4), isNull);
  });

  test('off until turned on; the streaming sources are asked only when one is on', () async {
    SharedPreferences.setMockInitialValues({});
    final sources = MusicSources.instance..reset();
    await sources.load();
    final song = _youtube();
    expect(SmartMerge.instance.wants(song), isFalse);
    await sources.setSmartMerge(true);
    expect(SmartMerge.instance.wants(song), isTrue, reason: 'the library is always there');
    expect(SmartMerge.instance.streams(song), isFalse, reason: 'Monochrome is still off');
    await sources.setMonochrome(true);
    expect(SmartMerge.instance.streams(song), isTrue);
    expect(SmartMerge.instance.wants(_mono('tracks:track:1')), isFalse, reason: 'only YouTube Music songs');
    sources.reset();
    await sources.load();
    expect(sources.smartMerge, isTrue, reason: 'the choice is kept');
    sources.reset();
  });
}
