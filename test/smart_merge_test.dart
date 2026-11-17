// ignore_for_file: experimental_member_use
import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:just_audio/just_audio.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/merged_download.dart';
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
  TrackSource get source => TrackSource.monochrome;
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
  _Monochrome({this.flac = true});
  final bool flac;
  final checked = <String>[];

  @override
  Future<String> manifest(String id) async => 'https://cdn.example/$id.flac';

  @override
  Future<bool> lossless(String stream) async {
    checked.add(stream);
    return flac;
  }
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

SmartMerge _merge(List<MergeProvider> providers) =>
    SmartMerge(providers: providers, enabled: () => true, downloads: false);

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
    expect(preferred.asked.length, 2, reason: "two lookups, by title (found: the artist isn't asked)");
    expect(await merge.match(_youtube(title: 'Other Song')), isEmpty);
  });

  test('a late old failure cannot evict a newer cached match', () async {
    final pending = Completer<List<Track>>();
    var calls = 0;
    var hanging = true;
    final provider = _Source(
      'source',
      [],
      searcher: (_) async {
        calls++;
        // The old lookup's questions (title and artist) wait; the new one's are answered.
        if (hanging) return pending.future;
        return [_mono('2')];
      },
    );
    final merge = _merge([provider]);
    final old = merge.match(_youtube());
    hanging = false;
    merge.clear();
    expect((await merge.match(_youtube())).single.track.id, 'monochrome:2');
    pending.completeError(const FormatException('old failure'));
    await old;
    await merge.match(_youtube());
    // Each lookup asks the title; the artist only when the title finds nothing or is slow.
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
      downloads: false,
    );
    final source = SmartMergeAudioSource(_youtube(), youtube: _Youtube(), merge: merge);
    expect(await _body(await source.request()), contains('https://working.example/'));
    expect(source.from?.name, 'working');
  });

  test('a source that is only slow to answer is asked again next time, not given up on', () async {
    final merge = SmartMerge(
      providers: [
        _Source('slow', [_mono('1')], resolver: (_) => Completer<String>().future),
      ],
      enabled: () => true,
      streamTimeout: const Duration(milliseconds: 5),
      downloads: false,
    );
    final source = SmartMergeAudioSource(_youtube(), youtube: _Youtube(), merge: merge);
    expect((await source.request()).contentType, 'audio/webm');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(merge.gaveUpOn('abcdefghijk'), isFalse);
    expect(merge.wants(_youtube()), isTrue);
  });

  test('queued sources honour disable and discard stale in-flight resolution', () async {
    var enabled = true;
    final pending = Completer<String>();
    final merge = SmartMerge(
      providers: [
        _Source('source', [_mono('1')], resolver: (_) => pending.future),
      ],
      enabled: () => enabled,
      downloads: false,
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

    test('a title given in two scripts matches its own half; an artist in another script needs the source', () {
      final song = _youtube(
        title: 'A Horny Money World ～伝説の夜～ - A Horny Money World ~legendary night~',
        artist: 'Houshou Marine',
        seconds: 196,
      );
      final match = _mono('1', title: 'A Horny Money World ～伝説の夜～', artist: '宝鐘マリン', seconds: 197);
      expect(SmartMerge.best(song, [match]), isNull, reason: 'the names alone cannot be compared');
      expect(SmartMerge.best(song, [match], byArtist: true), same(match));
      expect(
        SmartMerge.best(song, [
          _mono('2', title: 'A Horny Money World', artist: 'Someone Else', seconds: 197),
        ], byArtist: true),
        isNull,
        reason: 'a name that can be compared and differs is another artist',
      );
      expect(
        SmartMerge.best(song, [_mono('3', title: 'Legendary Night', artist: '宝鐘マリン', seconds: 197)], byArtist: true),
        isNull,
      );
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
    expect(found.asked, ['Glass Weather'], reason: "the title once (it found it: the artist isn't asked)");

    final down = _Source('b', const [], fails: true);
    final failing = _merge([down]);
    expect(await failing.match(_youtube()), isEmpty);
    await pumpEventQueue();
    await failing.match(_youtube());
    expect(down.asked, hasLength(2), reason: 'asked again (a source that is down is asked only by title)');
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

  test('a song waits a while for its better sound, then plays from YouTube; the next play has it at once', () async {
    final answer = Completer<List<Track>>();
    final merge = SmartMerge(
      providers: [_Source('slow', [], searcher: (_) => answer.future)],
      enabled: () => true,
      downloads: false,
      patience: const Duration(milliseconds: 20),
    );
    final first = SmartMergeAudioSource(_youtube(), youtube: _Youtube(), merge: merge);
    expect((await first.request()).contentType, 'audio/webm', reason: 'past its patience the song plays from YouTube');
    expect(first.from, isNull, reason: 'and stays there: no switch in the middle of the song');
    answer.complete([_mono('tracks:track:1')]);
    await pumpEventQueue();
    final again = SmartMergeAudioSource(_youtube(), youtube: _Youtube(), merge: merge);
    expect((await again.request()).contentType, 'application/vnd.apple.mpegurl', reason: 'the lookup carried on');
    expect(again.from?.name, 'slow');
    expect(
      merge.soundFrom('abcdefghijk')?.name,
      'slow',
      reason: 'its cards (Recently played) show where the sound came from',
    );
    merge.giveUp('abcdefghijk');
    expect(merge.soundFrom('abcdefghijk'), isNull);
  });

  test('a song got ready ahead (the next one, or one the pointer rests on) is asked once and opens at once', () async {
    final source = _Source('source', [_mono('tracks:track:1')]);
    final merge = _merge([source]);
    merge.pointerOn(_youtube());
    merge.pointerOff();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(source.asked, isEmpty, reason: 'passing over a row fetches nothing');
    merge.pointerOn(_youtube());
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(source.asked, isNotEmpty, reason: 'resting on it gets it ready');
    final asked = source.asked.length;
    final playing = SmartMergeAudioSource(_youtube(), youtube: _Youtube(), merge: merge);
    await playing.request();
    expect(playing.from?.name, 'source');
    expect(source.asked, hasLength(asked), reason: 'playing it asks nothing more');
  });

  test('a match is remembered between sessions, so a song played before is not looked up again', () async {
    SharedPreferences.setMockInitialValues({});
    final first = _Source('Monochrome', [_mono('tracks:track:1')]);
    final before = SmartMerge(providers: [first], enabled: () => true, downloads: false, remembers: true);
    await before.choose(_youtube());
    await pumpEventQueue();
    final later = _Source('Monochrome', [_mono('tracks:track:1')]);
    final after = SmartMerge(providers: [later], enabled: () => true, downloads: false, remembers: true);
    final playing = SmartMergeAudioSource(_youtube(), youtube: _Youtube(), merge: after);
    await playing.request();
    expect(playing.from, same(later));
    expect(later.asked, isEmpty, reason: 'the remembered match answers at once');
    after.giveUp('abcdefghijk');
    await pumpEventQueue();
    final third = _Source('Monochrome', [_mono('tracks:track:1')]);
    await SmartMerge(providers: [third], enabled: () => true, downloads: false, remembers: true).choose(_youtube());
    expect(third.asked, isNotEmpty, reason: 'one that failed is forgotten and looked up afresh');
  });

  test('Monochrome: a native song plays from its address, an older share from a fresh manifest', () async {
    final provider = MonochromeMerge(_Monochrome());
    expect(await provider.stream(_mono('tracks:track:77')), 'https://tracks.monochrome.st/track/77');
    expect(await provider.stream(_mono('12345')), 'https://cdn.example/12345.flac');
  });

  test('Monochrome: a song it has only in AAC is not merged, and each song is checked once', () async {
    final lossy = _Monochrome(flac: false);
    await expectLater(MonochromeMerge(lossy).stream(_mono('tracks:track:77')), throwsFormatException);
    final flac = _Monochrome();
    final provider = MonochromeMerge(flac);
    await provider.stream(_mono('tracks:track:77'));
    await provider.stream(_mono('tracks:track:77'));
    expect(flac.checked, hasLength(1));
  });

  test('Monochrome: FLAC is told by its first bytes, or by the codecs a manifest names', () async {
    addTearDown(MergedDownload.forgetAll);
    Monochrome serving(List<int> file) => Monochrome(
      client: MockClient.streaming(
        (request, _) async => http.StreamedResponse(
          Stream.value(file),
          206,
          contentLength: file.length,
          headers: {'content-range': 'bytes 0-${file.length - 1}/${file.length}'},
        ),
      ),
    );
    expect(await serving(ascii.encode('fLaC')).lossless('https://tracks.example/1'), isTrue);
    expect(await serving([0, 0, 0, 0x20, ...ascii.encode('ftyp')]).lossless('https://tracks.example/2'), isFalse);
    final m = Monochrome();
    expect(await m.lossless('<MPD><Representation codecs="flac"/></MPD>'), isTrue);
    expect(await m.lossless('<MPD><Representation codecs="mp4a.40.2"/></MPD>'), isFalse);
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

  test('a source that has the song only in lossier quality plays it from YouTube, and is shown as checked', () async {
    final youtube = _Youtube();
    final merge = _merge([
      _Source('Monochrome', [_mono('tracks:track:1')], resolver: (_) async => throw const LossierMatch('AAC only')),
    ]);
    final playing = SmartMergeAudioSource(_youtube(), youtube: youtube, merge: merge);
    expect((await playing.request()).contentType, 'audio/webm');
    expect(merge.soundFrom('abcdefghijk'), isNull);
    expect(merge.lossierAt('abcdefghijk'), (source: TrackSource.monochrome, name: 'Monochrome'));
    expect(merge.wants(_youtube()), isFalse, reason: 'the rest of the session stays on YouTube');

    final broken = _merge([
      _Source('Monochrome', [_mono('tracks:track:1')], streamFails: true),
    ]);
    await broken.choose(_youtube());
    expect(broken.lossierAt('abcdefghijk'), isNull, reason: 'a source that failed for another reason is not "worse"');

    merge.markUsed('abcdefghijk', sound: (source: TrackSource.device, name: ''));
    expect(merge.lossierAt('abcdefghijk'), isNull, reason: 'a better sound found later replaces the mark');
  });

  test('Monochrome: a song only in AAC is a lossier match', () async {
    await expectLater(
      MonochromeMerge(_Monochrome(flac: false)).stream(_mono('tracks:track:78')),
      throwsA(isA<LossierMatch>()),
    );
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

  test('a title given twice finds the library file named by one half of it', () {
    final merge = _merge(const []);
    final kyapi = _file('/music/Kyapi.flac', title: 'Kyapi', artist: 'Houshou Marine', seconds: 200);
    final other = _file('/music/Ahoy!!.flac', title: 'Ahoy!!', artist: 'Houshou Marine', seconds: 200);
    final song = _youtube(title: 'きゃぴ - Kyapi', artist: 'Houshou Marine', seconds: 199);
    expect(merge.local(song, [other, kyapi], 1), same(kyapi));
    expect(SmartMerge.same(song, kyapi), isTrue);
    expect(SmartMerge.same(_youtube(title: 'Kyapi', artist: 'Houshou Marine', seconds: 199), kyapi), isTrue);
    // The library file given twice, the song once.
    final twice = _file('/music/きゃぴ - Kyapi.flac', title: 'きゃぴ - Kyapi', artist: 'Houshou Marine');
    expect(merge.local(_youtube(title: 'Kyapi', artist: 'Houshou Marine'), [twice], 2), same(twice));
    // Another song by the same artist, or a version of it, is not it.
    expect(merge.local(_youtube(title: 'きゃぴ - Ahoy', artist: 'Houshou Marine'), [kyapi], 3), isNull);
    final instrumental = _youtube(title: 'きゃぴ (Instrumental) - Kyapi', artist: 'Houshou Marine', seconds: 201);
    expect(merge.local(instrumental, [kyapi], 4), isNull);
    // The same title by someone else is not it.
    expect(merge.local(_youtube(title: 'きゃぴ - Kyapi', artist: 'Someone Else'), [kyapi], 5), isNull);
  });

  test("a half that is only the artist's name doesn't make two titles the same", () {
    final named = _file('/music/Houshou Marine.flac', title: 'Houshou Marine', artist: 'Houshou Marine');
    final song = _youtube(title: 'Houshou Marine - Kyapi', artist: 'Houshou Marine');
    expect(SmartMerge.same(song, named), isFalse);
    expect(_merge(const []).local(song, [named], 1), isNull);
    final kyapi = _file('/music/Kyapi.flac', title: 'Kyapi', artist: 'Houshou Marine');
    expect(_merge(const []).local(song, [kyapi], 1), same(kyapi));
  });

  test('off once turned off; the streaming sources are asked only when one is on', () async {
    SharedPreferences.setMockInitialValues({'sources.smartMerge.v1': false, 'sources.monochrome.v1': false});
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
