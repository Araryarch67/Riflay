import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/audio_engine.dart';
import 'package:riflay/services/crossfade.dart';
import 'package:shared_preferences/shared_preferences.dart';

Track _t(
  String id, {
  String? album,
  int? no,
  int? disc,
  Duration? length,
  Duration? start,
  Duration? end,
  String? file,
}) => Track(
  id: id,
  uri: Uri.parse('file:///music/${file ?? id}.flac'),
  title: id,
  artist: 'A',
  album: album,
  trackNumber: no,
  discNumber: disc,
  duration: length,
  start: start,
  end: end,
);

void main() {
  group('songs that flow into each other', () {
    test('the next track of the same album flows', () {
      expect(CrossfadeRules.flowsInto(_t('a', album: 'X', no: 3), _t('b', album: 'X', no: 4)), isTrue);
      expect(CrossfadeRules.flowsInto(_t('a', album: 'x ', no: 3), _t('b', album: 'X', no: 4)), isTrue);
    });

    test('the same album but not in order (shuffled) does not', () {
      expect(CrossfadeRules.flowsInto(_t('a', album: 'X', no: 3), _t('b', album: 'X', no: 9)), isFalse);
      expect(CrossfadeRules.flowsInto(_t('a', album: 'X', no: 4), _t('b', album: 'X', no: 3)), isFalse);
    });

    test('another album does not, and neither does a song with no album', () {
      expect(CrossfadeRules.flowsInto(_t('a', album: 'X', no: 3), _t('b', album: 'Y', no: 4)), isFalse);
      expect(CrossfadeRules.flowsInto(_t('a', no: 3), _t('b', no: 4)), isFalse);
      expect(CrossfadeRules.flowsInto(_t('a', album: '', no: 3), _t('b', album: '', no: 4)), isFalse);
    });

    test('a disc ends and the next begins', () {
      expect(
        CrossfadeRules.flowsInto(_t('a', album: 'X', disc: 1, no: 12), _t('b', album: 'X', disc: 2, no: 1)),
        isTrue,
      );
      expect(
        CrossfadeRules.flowsInto(_t('a', album: 'X', disc: 1, no: 12), _t('b', album: 'X', disc: 2, no: 2)),
        isFalse,
      );
      expect(
        CrossfadeRules.flowsInto(_t('a', album: 'X', disc: 2, no: 3), _t('b', album: 'X', disc: 2, no: 4)),
        isTrue,
      );
    });

    test('an album with no track numbers, played back to back, is taken as playing in order', () {
      expect(CrossfadeRules.flowsInto(_t('a', album: 'X'), _t('b', album: 'X')), isTrue);
    });

    test('parts of one cue-sheet file flow when one ends where the next starts', () {
      const s = Duration(minutes: 3);
      final a = _t('a', file: 'rip', start: Duration.zero, end: s);
      expect(CrossfadeRules.flowsInto(a, _t('b', file: 'rip', start: s, end: s * 2)), isTrue);
      expect(CrossfadeRules.flowsInto(a, _t('c', file: 'rip', start: s * 5, end: s * 6)), isFalse);
      expect(CrossfadeRules.flowsInto(a, _t('d', file: 'other', start: s, end: s * 2)), isFalse);
    });
  });

  group('how long the fade is', () {
    const song = Duration(minutes: 3);

    test('is what was asked for, kept within 1 to 12 seconds', () {
      expect(CrossfadeRules.fadeLength(seconds: 5, current: song, next: song), const Duration(seconds: 5));
      expect(CrossfadeRules.fadeLength(seconds: 99, current: song, next: song), const Duration(seconds: 12));
      expect(CrossfadeRules.fadeLength(seconds: 0, current: song, next: song), const Duration(seconds: 1));
    });

    test('never covers more than 40% of either song', () {
      expect(
        CrossfadeRules.fadeLength(seconds: 12, current: const Duration(seconds: 20), next: song),
        const Duration(seconds: 8),
      );
      expect(
        CrossfadeRules.fadeLength(seconds: 12, current: song, next: const Duration(seconds: 15)),
        const Duration(seconds: 6),
      );
    });

    test('is none for a song too short to fade, or of unknown length', () {
      expect(CrossfadeRules.fadeLength(seconds: 5, current: const Duration(seconds: 2), next: song), isNull);
      expect(CrossfadeRules.fadeLength(seconds: 5, current: null, next: song), isNull);
      expect(CrossfadeRules.fadeLength(seconds: 5, current: song, next: null), const Duration(seconds: 5));
    });
  });

  group('when it starts', () {
    const song = Duration(minutes: 4);
    final a = _t('a', album: 'X', no: 1, length: song);
    final other = _t('b', album: 'Y', no: 7, length: song);
    final nextOnAlbum = _t('c', album: 'X', no: 2, length: song);

    test('the fade starts its length before the end, and getting ready 8 seconds earlier', () {
      final plan = CrossfadeRules.plan(current: a, next: other, duration: song, seconds: 6, skipAlbums: true)!;
      expect(plan.fade, const Duration(seconds: 6));
      expect(plan.startAt, song - const Duration(seconds: 6));
      expect(plan.prepareAt, song - const Duration(seconds: 14));
    });

    test('skip for albums: the next album track keeps its gapless change', () {
      expect(CrossfadeRules.plan(current: a, next: nextOnAlbum, duration: song, seconds: 6, skipAlbums: true), isNull);
    });

    test('with skip for albums off, it fades there too', () {
      expect(
        CrossfadeRules.plan(current: a, next: nextOnAlbum, duration: song, seconds: 6, skipAlbums: false),
        isNotNull,
      );
    });

    test('without a known length there is no plan', () {
      expect(CrossfadeRules.plan(current: a, next: other, duration: null, seconds: 6, skipAlbums: true), isNull);
    });

    test('getting ready is not too early, and not too late to be worth it', () {
      final plan = CrossfadeRules.plan(current: a, next: other, duration: song, seconds: 6, skipAlbums: true)!;
      expect(CrossfadeRules.shouldPrepare(plan, plan.prepareAt - const Duration(milliseconds: 1)), isFalse);
      expect(CrossfadeRules.shouldPrepare(plan, plan.prepareAt), isTrue);
      expect(CrossfadeRules.shouldPrepare(plan, plan.startAt - const Duration(seconds: 1)), isFalse);
    });

    test('the fade starts exactly at its time', () {
      final plan = CrossfadeRules.plan(current: a, next: other, duration: song, seconds: 6, skipAlbums: true)!;
      expect(CrossfadeRules.shouldStart(plan, plan.startAt - const Duration(milliseconds: 1)), isFalse);
      expect(CrossfadeRules.shouldStart(plan, plan.startAt), isTrue);
      expect(CrossfadeRules.shouldStart(plan, song), isTrue);
    });

    test('a short song gets ready from its very start', () {
      final short = _t('s', length: const Duration(seconds: 12));
      final plan = CrossfadeRules.plan(
        current: short,
        next: other,
        duration: short.duration,
        seconds: 12,
        skipAlbums: true,
      )!;
      expect(plan.fade, const Duration(milliseconds: 4800));
      expect(plan.startAt, const Duration(milliseconds: 7200));
      expect(plan.prepareAt, Duration.zero);
    });
  });

  group('the two volumes', () {
    test('keep the loudness level all the way through', () {
      for (var i = 0; i <= 100; i++) {
        final x = i / 100;
        final power = math.pow(CrossfadeRules.gainOut(x), 2) + math.pow(CrossfadeRules.gainIn(x), 2);
        expect(power, closeTo(1, 1e-9));
      }
    });

    test('start and end where they should', () {
      expect(CrossfadeRules.gainOut(0), 1);
      expect(CrossfadeRules.gainIn(0), 0);
      expect(CrossfadeRules.gainOut(1), closeTo(0, 1e-12));
      expect(CrossfadeRules.gainIn(1), 1);
      expect(CrossfadeRules.gainIn(5), 1, reason: 'clamped');
      expect(CrossfadeRules.gainOut(-1), 1);
    });
  });

  group('off where it would be wrong', () {
    test('bit-perfect mode and a DAC held directly switch it off, and say so', () {
      expect(CrossfadeRules.blockedNote(bitPerfect: true, direct: false), contains('bit-perfect'));
      expect(CrossfadeRules.blockedNote(bitPerfect: false, direct: true), contains('DAC'));
      expect(CrossfadeRules.blockedNote(bitPerfect: false, direct: false), isNull);
    });

    test('the engine: off by default, 5 s, albums skipped', () {
      final audio = AudioEngine();
      addTearDown(audio.dispose);
      expect(audio.crossfade, isFalse);
      expect(audio.crossfadeActive, isFalse);
      expect(audio.crossfadeSeconds, 5);
      expect(audio.crossfadeSkipAlbums, isTrue);
    });

    test('the engine: on, it works until bit-perfect mode is turned on', () {
      final audio = AudioEngine();
      addTearDown(audio.dispose);
      audio.crossfade = true;
      expect(audio.crossfadeActive, isTrue);
      audio.bitPerfectWanted = true; // (Linux and desktop: the switch itself)
      if (audio.bitPerfect) {
        expect(audio.crossfadeActive, isFalse);
        expect(audio.crossfadeBlock, isNotNull);
      }
    });
  });

  group('saved settings', () {
    test('survive a restart, within range', () async {
      SharedPreferences.setMockInitialValues({
        'audio.v1': jsonEncode({'crossfade': true, 'crossfadeSeconds': 9, 'crossfadeSkipAlbums': false}),
      });
      final a = AudioEngine();
      addTearDown(a.dispose);
      await a.load();
      expect(a.crossfade, isTrue);
      expect(a.crossfadeSeconds, 9);
      expect(a.crossfadeSkipAlbums, isFalse);

      SharedPreferences.setMockInitialValues({
        'audio.v1': jsonEncode({'crossfade': true, 'crossfadeSeconds': 400}),
      });
      final b = AudioEngine();
      addTearDown(b.dispose);
      await b.load();
      expect(b.crossfadeSeconds, 12);
    });

    test('a setting change is written out', () async {
      SharedPreferences.setMockInitialValues({});
      final a = AudioEngine();
      addTearDown(a.dispose);
      await a.setCrossfade(true);
      await a.setCrossfadeSeconds(7);
      await a.setCrossfadeSkipAlbums(false);
      final saved = jsonDecode((await SharedPreferences.getInstance()).getString('audio.v1')!) as Map<String, dynamic>;
      expect(saved['crossfade'], true);
      expect(saved['crossfadeSeconds'], 7);
      expect(saved['crossfadeSkipAlbums'], false);
      await a.setCrossfadeSeconds(0);
      expect(a.crossfadeSeconds, 1);
    });
  });
}
