import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/download_prefs.dart';

/// Audio formats as `yt-dlp -J` lists them for a typical music video
/// (itag 139/140 AAC, 249/250/251 Opus, a "stable volume" copy, a video stream and a dubbed track).
final _sample = <Map<String, dynamic>>[
  {'format_id': '139', 'acodec': 'mp4a.40.5', 'vcodec': 'none', 'abr': 48.8, 'ext': 'm4a'},
  {'format_id': '140', 'acodec': 'mp4a.40.2', 'vcodec': 'none', 'abr': 129.5, 'ext': 'm4a'},
  {'format_id': '140-drc', 'acodec': 'mp4a.40.2', 'vcodec': 'none', 'abr': 129.5, 'ext': 'm4a'},
  {'format_id': '249', 'acodec': 'opus', 'vcodec': 'none', 'abr': 52.1, 'ext': 'webm'},
  {'format_id': '250', 'acodec': 'opus', 'vcodec': 'none', 'abr': 76.6, 'ext': 'webm'},
  {'format_id': '251', 'acodec': 'opus', 'vcodec': 'none', 'abr': 137.2, 'ext': 'webm'},
  {'format_id': '251-drc', 'acodec': 'opus', 'vcodec': 'none', 'abr': 137.2, 'ext': 'webm'},
  {'format_id': '251-1', 'acodec': 'opus', 'vcodec': 'none', 'abr': 137.2, 'ext': 'webm', 'language_preference': -1},
  {'format_id': '18', 'acodec': 'mp4a.40.2', 'vcodec': 'avc1.42001E', 'abr': 96, 'ext': 'mp4'},
  {'format_id': 'sb0', 'acodec': 'none', 'vcodec': 'none', 'ext': 'mhtml'},
];

List<AudioCandidate> get _candidates => [for (final f in _sample) ?AudioCandidate.fromYtDlp(f)];

AudioPick? _pick(DownloadFormat f, int? kbps, {bool ffmpeg = true, FlacQuality flac = FlacQuality.standard}) =>
    pickForDownload(
      _candidates,
      DownloadChoice(f, kbps: kbps, flac: flac),
      canReencode: ffmpeg,
    );

const _opus = DownloadFormat.opus;
const _m4a = DownloadFormat.m4a;

void main() {
  test('video streams, storyboards, stable-volume and dubbed copies are never candidates', () {
    expect(_candidates.map((c) => c.id), ['139', '140', '140-drc', '249', '250', '251', '251-drc', '251-1']);
    final usable = _candidates.where((c) => !c.processed).map((c) => c.id);
    expect(usable, ['139', '140', '249', '250', '251']);
  });

  group('best available', () {
    test('null kbps is the highest stream of the format, unconverted', () {
      final o = _pick(_opus, null)!;
      expect((o.candidate.id, o.convert, o.ext), ('251', null, 'webm'));
      final m = _pick(_m4a, null)!;
      expect((m.candidate.id, m.convert, m.ext), ('140', null, 'm4a'));
    });

    test('a target at or near the best is the best, never converted up', () {
      for (final ffmpeg in [true, false]) {
        expect(_pick(_opus, 128, ffmpeg: ffmpeg)!.candidate.id, '251');
        expect(_pick(_opus, 128, ffmpeg: ffmpeg)!.convert, isNull);
        expect(_pick(_m4a, 128, ffmpeg: ffmpeg)!.candidate.id, '140');
        expect(_pick(_m4a, 128, ffmpeg: ffmpeg)!.convert, isNull);
      }
      const quiet = [AudioCandidate(id: 'x', opus: false, kbps: 48)];
      final pick = pickForDownload(quiet, const DownloadChoice(_m4a, kbps: 96), canReencode: true)!;
      expect((pick.convert, pick.kbps), (null, 48));
    });
  });

  group('lower targets', () {
    test('a served stream within 15% is used as it is', () {
      final o = _pick(_opus, 48)!;
      expect((o.candidate.id, o.convert), ('249', null));
      final m = _pick(_m4a, 48)!;
      expect((m.candidate.id, m.convert), ('139', null));
    });

    test('otherwise, with ffmpeg, the best stream is re-encoded to the target', () {
      final o96 = _pick(_opus, 96)!;
      expect((o96.candidate.id, o96.convert, o96.kbps, o96.ext), ('251', const Reencode(96), 96, 'webm'));
      final o64 = _pick(_opus, 64)!;
      expect((o64.candidate.id, o64.convert), ('251', const Reencode(64)));
      final m96 = _pick(_m4a, 96)!;
      expect((m96.candidate.id, m96.convert, m96.label), ('140', const Reencode(96), 'AAC · 96 kbps'));
      final m64 = _pick(_m4a, 64)!;
      expect((m64.candidate.id, m64.convert), ('140', const Reencode(64)));
    });

    test('without ffmpeg: the highest stream at or under the target, else the smallest', () {
      expect(_pick(_opus, 96, ffmpeg: false)!.candidate.id, '250');
      expect(_pick(_opus, 64, ffmpeg: false)!.candidate.id, '249');
      expect(_pick(_m4a, 96, ffmpeg: false)!.candidate.id, '139');
      expect(_pick(_m4a, 64, ffmpeg: false)!.candidate.id, '139');
      for (final f in [_opus, _m4a]) {
        for (final k in [null, 128, 96, 64, 48]) {
          expect(_pick(f, k, ffmpeg: false)!.convert, isNull);
        }
      }
      const heavy = [AudioCandidate(id: 'a', opus: true, kbps: 160), AudioCandidate(id: 'b', opus: true, kbps: 128)];
      final p = pickForDownload(heavy, const DownloadChoice(_opus, kbps: 96), canReencode: false)!;
      expect((p.candidate.id, p.convert, p.kbps), ('b', null, 128), reason: 'smallest, and its honest bitrate');
    });

    test('a result is never above what YouTube serves', () {
      for (final f in [_opus, _m4a]) {
        for (final k in f.bitrates) {
          for (final ffmpeg in [true, false]) {
            final pick = _pick(f, k, ffmpeg: ffmpeg)!;
            expect(pick.kbps, lessThanOrEqualTo(137));
            expect(pick.opus, f == _opus);
          }
        }
      }
    });
  });

  group('FLAC', () {
    test('is made from the best stream, Opus first, whether or not ffmpeg is there', () {
      for (final ffmpeg in [true, false]) {
        final p = _pick(DownloadFormat.flac, 64, ffmpeg: ffmpeg)!;
        expect(p.candidate.id, '251');
        expect(p.convert, const ToFlac(FlacQuality.standard));
        expect(p.ext, 'flac');
        expect(p.label, 'FLAC · 16-bit / 48 kHz · from Opus 137 kbps');
        expect(p.reencodeKbps, isNull);
        expect(p.kbps, 137, reason: 'the stream it was made from');
      }
    });

    test('carries the chosen quality', () {
      final p = _pick(DownloadFormat.flac, null, flac: FlacQuality.hiRes)!;
      expect(p.convert, const ToFlac(FlacQuality.hiRes));
      expect(p.label, 'FLAC · 24-bit / 48 kHz · from Opus 137 kbps');
      expect(
        _pick(DownloadFormat.flac, null, flac: FlacQuality.cd)!.label,
        'FLAC · 16-bit / 44.1 kHz · from Opus 137 kbps',
      );
    });

    test('falls back to AAC when there is no Opus', () {
      final p = pickForDownload(
        _candidates.where((c) => !c.opus),
        const DownloadChoice(DownloadFormat.flac),
        canReencode: false,
      )!;
      expect((p.candidate.id, p.ext), ('140', 'flac'));
    });
  });

  test('DownloadChoice equality ignores what does not apply to the format', () {
    expect(const DownloadChoice(DownloadFormat.flac, kbps: 64), const DownloadChoice(DownloadFormat.flac, kbps: 96));
    expect(
      const DownloadChoice(DownloadFormat.flac, kbps: 64).hashCode,
      const DownloadChoice(DownloadFormat.flac, kbps: 96).hashCode,
    );
    expect(
      const DownloadChoice(DownloadFormat.flac),
      isNot(const DownloadChoice(DownloadFormat.flac, flac: FlacQuality.hiRes)),
    );
    expect(const DownloadChoice(_opus, flac: FlacQuality.cd), const DownloadChoice(_opus, flac: FlacQuality.hiRes));
    expect(const DownloadChoice(_opus, kbps: 96), isNot(const DownloadChoice(_opus, kbps: 64)));
    expect(const DownloadChoice(_opus), isNot(const DownloadChoice(_opus, kbps: 128)));
    expect(const DownloadChoice(_opus, kbps: 96), isNot(const DownloadChoice(_m4a, kbps: 96)));
  });

  test('the other format is used only when the video has none of the one asked for', () {
    final onlyAac = _candidates.where((c) => !c.opus);
    final pick = pickForDownload(onlyAac, const DownloadChoice(_opus), canReencode: true)!;
    expect(pick.opus, isFalse);
    expect(pick.label, 'AAC · 130 kbps', reason: 'the list says what was really saved');
    expect(pickForDownload(const [], const DownloadChoice(_opus), canReencode: true), isNull);
    expect(pickForDownload(const [], const DownloadChoice(DownloadFormat.flac), canReencode: true), isNull);
  });

  test('a near-silent Opus beside a normal AAC is not taken for the best', () {
    const odd = [
      AudioCandidate(id: '251', opus: true, kbps: 4),
      AudioCandidate(id: '140', opus: false, kbps: 130),
      AudioCandidate(id: '139', opus: false, kbps: 49),
    ];
    final best = pickForDownload(odd, const DownloadChoice(_opus), canReencode: true)!;
    expect(best.candidate.id, '140');
    expect(best.label, 'AAC · 130 kbps');
    final small = pickForDownload(odd, const DownloadChoice(_opus, kbps: 48), canReencode: true)!;
    expect((small.candidate.id, small.convert), ('139', null));
    final down = pickForDownload(odd, const DownloadChoice(_opus, kbps: 96), canReencode: true)!;
    expect((down.candidate.id, down.convert), ('140', const Reencode(96)));
    expect(pickForDownload(odd, const DownloadChoice(DownloadFormat.flac), canReencode: true)!.candidate.id, '140');
    // But a low Opus with no real AAC to prefer is left alone.
    const onlyLow = [AudioCandidate(id: '251', opus: true, kbps: 4), AudioCandidate(id: '139', opus: false, kbps: 49)];
    expect(pickForDownload(onlyLow, const DownloadChoice(_opus), canReencode: true)!.candidate.id, '251');
  });

  test('the player API\'s formats are read the same way', () {
    final c = AudioCandidate.fromPlayer({
      'itag': 251,
      'url': 'https://example.invalid/a',
      'mimeType': 'audio/webm; codecs="opus"',
      'bitrate': 150000,
      'averageBitrate': 133000,
    })!;
    expect((c.id, c.opus, c.kbps, c.processed), ('251', true, 133, false));
    expect(AudioCandidate.fromPlayer({'itag': 18, 'url': 'x', 'mimeType': 'video/mp4; codecs="avc1"'}), isNull);
    expect(
      AudioCandidate.fromPlayer({'itag': 140, 'url': 'x', 'mimeType': 'audio/mp4; codecs="mp4a.40.2"', 'isDrc': true})!
          .processed,
      isTrue,
    );
  });

  test('a FLAC label names the stream it was made from; its size is estimated from the length', () {
    expect(describeFlac(FlacQuality.standard), 'FLAC · 16-bit / 48 kHz');
    expect(
      describeFlac(FlacQuality.cd, fromOpus: false, fromKbps: 130),
      'FLAC · 16-bit / 44.1 kHz · from AAC 130 kbps',
    );
    const minute = Duration(minutes: 1);
    expect(estimateFlacBytes(minute, FlacQuality.standard, compressed: false), 11520000);
    expect(estimateFlacBytes(minute, FlacQuality.hiRes, compressed: false), 17280000);
    expect(estimateFlacBytes(minute, FlacQuality.standard, compressed: true), 6912000);
  });
}
