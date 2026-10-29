import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/download_prefs.dart';
import 'package:riflay/services/youtube_importer.dart';

DownloadJob job(String id, DownloadStatus status, {DownloadChoice? choice, String? album}) => DownloadJob(
  videoId: id,
  title: 'Song $id',
  channel: 'Artist',
  thumbnailUrl: 'https://example.com/$id.jpg',
  knownNames: true,
  choice: choice,
  album: album,
)..status = status;

void main() {
  const a = 'aaaaaaaaaaa', b = 'bbbbbbbbbbb', c = 'ccccccccccc', d = 'ddddddddddd';

  test('queued, running and failed jobs round-trip; done and cancelled are not kept', () {
    final text = YoutubeImporter.encodeQueue([
      job(a, DownloadStatus.queued, choice: const DownloadChoice(DownloadFormat.flac, flac: FlacQuality.hiRes)),
      job(b, DownloadStatus.downloading, choice: const DownloadChoice(DownloadFormat.m4a, kbps: 128), album: 'Blue'),
      job(c, DownloadStatus.failed)..error = 'No internet connection. Try again.',
      job(d, DownloadStatus.done),
      job('eeeeeeeeeee', DownloadStatus.cancelled),
    ]);
    final back = YoutubeImporter.decodeQueue(text);
    expect(back.map((j) => j.videoId), [a, b, c]);
    expect(back[0].choice, const DownloadChoice(DownloadFormat.flac, flac: FlacQuality.hiRes));
    expect(back[1].choice, const DownloadChoice(DownloadFormat.m4a, kbps: 128));
    expect(back[1].album, 'Blue');
    expect(back[1].title, 'Song $b');
    expect(back[1].knownNames, isTrue);
    expect(back[1].thumbnailUrl, 'https://example.com/$b.jpg');
    expect(back[2].error, 'No internet connection. Try again.');
  });

  test('on a new start, running goes back to waiting and failed stays failed', () {
    final back = YoutubeImporter.decodeQueue(
      YoutubeImporter.encodeQueue([job(a, DownloadStatus.downloading), job(b, DownloadStatus.failed)]),
    );
    expect(back[0].status, DownloadStatus.queued);
    expect(back[1].status, DownloadStatus.failed);
  });

  test('damaged text, bad ids and duplicates are dropped', () {
    expect(YoutubeImporter.decodeQueue('not json'), isEmpty);
    expect(YoutubeImporter.decodeQueue('{"jobs": 3}'), isEmpty);
    final text =
        '{"jobs":[{"videoId":"../../etc","title":"x"},{"videoId":"$a","title":"x"},{"videoId":"$a","title":"y"}]}';
    expect(YoutubeImporter.decodeQueue(text).map((j) => j.title), ['x']);
  });

  group('resume', () {
    bool can({String? sItag = '251', int? sSize = 1000, String? fItag = '251', int? fSize = 1000, int part = 400}) =>
        canResumePart(savedItag: sItag, savedSize: sSize, freshItag: fItag, freshSize: fSize, partBytes: part);

    test('the same itag and size continues', () => expect(can(), isTrue));
    test('another itag or size starts again', () {
      expect(can(fItag: '140'), isFalse);
      expect(can(fSize: 1200), isFalse);
    });
    test('nothing to continue from', () {
      expect(can(part: 0), isFalse);
      expect(can(part: 1000), isFalse);
      expect(can(sItag: null, fItag: null), isFalse);
    });
  });

  group('partial file identity', () {
    test('the stream a partial file holds is kept with the job', () {
      final j = job(a, DownloadStatus.downloading)
        ..partItag = '251'
        ..partSize = 4096
        ..partExt = 'webm';
      final back = YoutubeImporter.decodeQueue(YoutubeImporter.encodeQueue([j])).single;
      expect(back.partItag, '251');
      expect(back.partSize, 4096);
      expect(back.partExt, 'webm');
    });

    test('a job without one, or with a damaged one, has none', () {
      expect(
        YoutubeImporter.decodeQueue(YoutubeImporter.encodeQueue([job(a, DownloadStatus.queued)])).single.partItag,
        isNull,
      );
      final text = '{"jobs":[{"videoId":"$a","title":"x","part":{"itag":251,"size":"big","ext":"../x"}}]}';
      final back = YoutubeImporter.decodeQueue(text).single;
      expect(back.partItag, isNull);
      expect(back.partExt, isNull);
    });
  });

  group('phases', () {
    test('only a real conversion converts; a plain save finishes', () {
      expect(DownloadPhase.afterDownload(null), DownloadPhase.finishing);
      expect(DownloadPhase.afterDownload(const ToMp3(192)), DownloadPhase.converting);
      expect(DownloadPhase.afterDownload(const Reencode(96)), DownloadPhase.converting);
    });

    test('labels', () {
      expect(DownloadPhase.downloading.label, 'Downloading');
      expect(DownloadPhase.converting.label, 'Converting…');
      expect(DownloadPhase.finishing.label, 'Finishing…');
    });

    test('a job says converting only in that phase', () {
      final j = job(a, DownloadStatus.downloading);
      expect(j.converting, isFalse);
      j.phase = DownloadPhase.finishing;
      expect(j.converting, isFalse);
      j.phase = DownloadPhase.converting;
      expect(j.converting, isTrue);
    });
  });
}
