import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/download_notifications.dart';
import 'package:riflay/services/youtube_importer.dart' show DownloadStatus;

JobSnapshot job(
  String id,
  DownloadStatus status, {
  double progress = 0,
  bool converting = false,
  String title = 'Song',
}) => JobSnapshot(videoId: id, title: title, status: status, progress: progress, converting: converting);

void main() {
  group('noteFor', () {
    test('a running download shows title, percent, a bar and Cancel', () {
      final n = noteFor(job('a', DownloadStatus.downloading, progress: 0.451, title: 'Blue'))!;
      expect(n.title, 'Blue · 45%');
      expect(n.percent, 45);
      expect(n.indeterminate, isFalse);
      expect(n.ongoing, isTrue);
      expect(n.actions.map((a) => a.id), [cancelAction]);
      expect(n.videoId, 'a');
    });

    test('converting and just-started downloads have an indeterminate bar', () {
      final c = noteFor(job('a', DownloadStatus.downloading, progress: 1, converting: true))!;
      expect(c.body, 'Converting…');
      expect(c.indeterminate, isTrue);
      expect(c.percent, isNull);
      final s = noteFor(job('a', DownloadStatus.downloading))!;
      expect(s.indeterminate, isTrue);
      expect(s.title, 'Song');
      expect(noteFor(job('a', DownloadStatus.queued))!.indeterminate, isTrue);
    });

    test('a failure offers Retry and can be swiped away', () {
      final n = noteFor(job('a', DownloadStatus.failed, title: 'Blue'))!;
      expect(n.title, "Couldn't download Blue");
      expect(n.ongoing, isFalse);
      expect(n.showsProgress, isFalse);
      expect(n.actions.map((a) => a.id), [retryAction]);
    });

    test('a finished download is plain and has no actions', () {
      final n = noteFor(job('a', DownloadStatus.done, title: 'Blue'))!;
      expect(n.title, 'Downloaded Blue');
      expect(n.ongoing, isFalse);
      expect(n.actions, isEmpty);
    });

    test('a cancelled download needs no notification', () {
      expect(noteFor(job('a', DownloadStatus.cancelled)), isNull);
    });

    test('ids are stable and differ per song', () {
      expect(noteIdFor('abcdefghijk'), noteIdFor('abcdefghijk'));
      expect(noteIdFor('abcdefghijk'), isNot(noteIdFor('abcdefghijl')));
      expect(noteIdFor('abcdefghijk'), greaterThan(summaryNoteId));
    });
  });

  group('summaryFor', () {
    test('nothing active, no summary', () {
      expect(summaryFor([job('a', DownloadStatus.done), job('b', DownloadStatus.failed)]), isNull);
    });

    test('one active download is its own summary under the summary id', () {
      final n = summaryFor([job('a', DownloadStatus.downloading, progress: 0.5), job('b', DownloadStatus.done)])!;
      expect(n.id, summaryNoteId);
      expect(n.title, 'Song · 50%');
      expect(n.actions.map((a) => a.id), [cancelAction]);
      expect(n.videoId, 'a');
    });

    test('several downloads are grouped with their overall progress', () {
      final n = summaryFor([
        job('a', DownloadStatus.downloading, progress: 0.5, title: 'One'),
        job('b', DownloadStatus.queued, title: 'Two'),
        job('c', DownloadStatus.downloading, progress: 1, title: 'Three'),
      ])!;
      expect(n.title, 'Downloading 3 songs');
      expect(n.body, 'One, Two +1');
      expect(n.percent, 50);
      expect(n.ongoing, isTrue);
      expect(n.actions, isEmpty);
      expect(n.videoId, isNull);
    });

    test('several that have not started yet show an indeterminate bar', () {
      final n = summaryFor([job('a', DownloadStatus.queued), job('b', DownloadStatus.queued)])!;
      expect(n.indeterminate, isTrue);
      expect(n.percent, isNull);
    });
  });

  group('NoteThrottle', () {
    final t0 = DateTime(2026, 1, 1, 12);

    test('lets two updates a second through per song', () {
      final t = NoteThrottle();
      expect(t.allow(1, t0), isTrue);
      expect(t.allow(1, t0.add(const Duration(milliseconds: 200))), isFalse);
      expect(t.allow(1, t0.add(const Duration(milliseconds: 499))), isFalse);
      expect(t.allow(1, t0.add(const Duration(milliseconds: 500))), isTrue);
    });

    test('songs do not hold each other back', () {
      final t = NoteThrottle();
      expect(t.allow(1, t0), isTrue);
      expect(t.allow(2, t0), isTrue);
    });

    test('a forced update goes through and restarts the wait', () {
      final t = NoteThrottle();
      t.allow(1, t0);
      expect(t.allow(1, t0.add(const Duration(milliseconds: 10)), force: true), isTrue);
      expect(t.wait(1, t0.add(const Duration(milliseconds: 110))), const Duration(milliseconds: 400));
    });

    test('wait is zero for a song never shown, and after the interval', () {
      final t = NoteThrottle();
      expect(t.wait(9, t0), Duration.zero);
      t.allow(9, t0);
      expect(t.wait(9, t0.add(const Duration(seconds: 2))), Duration.zero);
    });
  });
}
