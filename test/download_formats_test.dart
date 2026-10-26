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

AudioPick? _pick(DownloadFormat f, DownloadQuality q, {bool ffmpeg = true}) =>
    pickForDownload(_candidates, DownloadChoice(f, q), canReencode: ffmpeg);

void main() {
  test('video streams, storyboards, stable-volume and dubbed copies are never candidates', () {
    expect(_candidates.map((c) => c.id), ['139', '140', '140-drc', '249', '250', '251', '251-drc', '251-1']);
    final usable = _candidates.where((c) => !c.processed).map((c) => c.id);
    expect(usable, ['139', '140', '249', '250', '251']);
  });

  test('best available keeps today\'s choice: the highest-bitrate stream of the format', () {
    expect(_pick(DownloadFormat.opus, DownloadQuality.best)!.candidate.id, '251');
    expect(_pick(DownloadFormat.m4a, DownloadQuality.best)!.candidate.id, '140');
    expect(_pick(DownloadFormat.opus, DownloadQuality.best)!.reencodeKbps, isNull);
  });

  test('smaller steps take YouTube\'s own lower stream', () {
    expect(_pick(DownloadFormat.opus, DownloadQuality.smaller)!.candidate.id, '250');
    expect(_pick(DownloadFormat.opus, DownloadQuality.smallest)!.candidate.id, '249');
    expect(_pick(DownloadFormat.m4a, DownloadQuality.smaller)!.candidate.id, '139');
    expect(_pick(DownloadFormat.m4a, DownloadQuality.smallest)!.candidate.id, '139');
    for (final f in DownloadFormat.values) {
      for (final q in [DownloadQuality.smaller, DownloadQuality.smallest]) {
        expect(_pick(f, q)!.reencodeKbps, isNull, reason: 'a native stream fits $f $q, so nothing is converted');
      }
    }
  });

  test('a result is never above what YouTube serves, or above the step\'s cap when a stream fits', () {
    final served = _candidates.where((c) => !c.processed).map((c) => c.kbps).reduce((a, b) => a > b ? a : b);
    for (final f in DownloadFormat.values) {
      for (final q in DownloadQuality.values) {
        final pick = _pick(f, q)!;
        expect(pick.kbps, lessThanOrEqualTo(served));
        if (q.capKbps != null) expect(pick.kbps, lessThanOrEqualTo(q.capKbps!));
        expect(pick.opus, f == DownloadFormat.opus);
      }
    }
  });

  test('only when every stream is above the cap is one converted down, and only with ffmpeg', () {
    const heavy = [AudioCandidate(id: 'a', opus: true, kbps: 160), AudioCandidate(id: 'b', opus: true, kbps: 128)];
    const choice = DownloadChoice(DownloadFormat.opus, DownloadQuality.smaller);
    final down = pickForDownload(heavy, choice, canReencode: true)!;
    expect(down.candidate.id, 'b');
    expect(down.reencodeKbps, 96);
    expect(down.kbps, 96);
    final noFfmpeg = pickForDownload(heavy, choice, canReencode: false)!;
    expect(noFfmpeg.candidate.id, 'b');
    expect(noFfmpeg.reencodeKbps, isNull);
    expect(noFfmpeg.kbps, 128, reason: 'the honest bitrate of the file that is saved');
  });

  test('a stream already under the cap is never converted up', () {
    const quiet = [AudioCandidate(id: 'x', opus: false, kbps: 48)];
    final pick = pickForDownload(
      quiet,
      const DownloadChoice(DownloadFormat.m4a, DownloadQuality.smaller),
      canReencode: true,
    )!;
    expect(pick.reencodeKbps, isNull);
    expect(pick.kbps, 48);
  });

  test('the other format is used only when the video has none of the one asked for', () {
    final onlyAac = _candidates.where((c) => !c.opus);
    final pick = pickForDownload(
      onlyAac,
      const DownloadChoice(DownloadFormat.opus, DownloadQuality.best),
      canReencode: true,
    )!;
    expect(pick.opus, isFalse);
    expect(pick.label, 'AAC · 130 kbps', reason: 'the list says what was really saved');
    expect(
      pickForDownload(const [], const DownloadChoice(DownloadFormat.opus, DownloadQuality.best), canReencode: true),
      isNull,
    );
  });

  test('a near-silent Opus beside a normal AAC is not taken for the best', () {
    const odd = [
      AudioCandidate(id: '251', opus: true, kbps: 4),
      AudioCandidate(id: '140', opus: false, kbps: 130),
      AudioCandidate(id: '139', opus: false, kbps: 49),
    ];
    final best = pickForDownload(
      odd,
      const DownloadChoice(DownloadFormat.opus, DownloadQuality.best),
      canReencode: true,
    )!;
    expect(best.candidate.id, '140');
    expect(best.label, 'AAC · 130 kbps');
    final small = pickForDownload(
      odd,
      const DownloadChoice(DownloadFormat.opus, DownloadQuality.smaller),
      canReencode: true,
    )!;
    expect(small.candidate.id, '139');
    // But a low Opus with no real AAC to prefer is left alone.
    const onlyLow = [AudioCandidate(id: '251', opus: true, kbps: 4), AudioCandidate(id: '139', opus: false, kbps: 49)];
    expect(
      pickForDownload(
        onlyLow,
        const DownloadChoice(DownloadFormat.opus, DownloadQuality.best),
        canReencode: true,
      )!.candidate.id,
      '251',
    );
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
}
