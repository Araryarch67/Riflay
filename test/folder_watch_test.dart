import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/folder_watch.dart';

Track song(String path, {String? title, Duration? duration, int addedAt = 1}) {
  final t = Track.fromUri(Uri.file(path));
  return Track(
    id: t.id,
    uri: t.uri,
    title: title ?? t.title,
    artist: 'Artist',
    album: 'Album',
    duration: duration ?? const Duration(minutes: 3),
    addedAt: addedAt,
    tagged: true,
  );
}

void main() {
  const root = '/music';
  final t0 = DateTime(2026, 1, 1, 12);

  group('ignored files', () {
    test('temp and partial files are ignored', () {
      for (final f in [
        '/music/a.mp3.part',
        '/music/a.crdownload',
        '/music/a.tmp',
        '/music/.hidden.mp3',
        '/music/~a.mp3',
        '/music/a.mp3~',
        '/music/Song.f251.webm',
        '/music/.stfolder/a.mp3',
        '/music/a.mp3.part-Frag12',
      ]) {
        expect(isIgnoredPath(f, root: root), isTrue, reason: f);
      }
      expect(isIgnoredPath('/music/Album/01 Song.flac', root: root), isFalse);
    });

    test('a hidden folder above the root does not hide the music', () {
      expect(isIgnoredPath('/home/me/.local/music/a.mp3', root: '/home/me/.local/music'), isFalse);
    });

    test('music files and cue sheets count, other files do not', () {
      expect(isLibraryFile('/m/a.FLAC'), isTrue);
      expect(isLibraryFile('/m/a.cue'), isTrue);
      expect(isLibraryFile('/m/disc.iso'), isTrue);
      expect(isLibraryFile('/m/cover.jpg'), isFalse);
    });
  });

  group('ChangeSettler (a file being copied)', () {
    test('waits until events stop and the size is the same twice', () {
      final s = ChangeSettler(quiet: const Duration(seconds: 3));
      var size = 100;
      s.note('/music/a.mp3', t0);
      // Events are still fresh.
      expect(s.ready(t0.add(const Duration(seconds: 1)), (_) => size), isEmpty);
      // Quiet now, but the first look only records the size.
      expect(s.ready(t0.add(const Duration(seconds: 4)), (_) => size), isEmpty);
      // The copy grew: not stable.
      size = 5000;
      expect(s.ready(t0.add(const Duration(seconds: 6)), (_) => size), isEmpty);
      // Same size again: ready, and it leaves the queue.
      expect(s.ready(t0.add(const Duration(seconds: 8)), (_) => size), ['/music/a.mp3']);
      expect(s.isEmpty, isTrue);
    });

    test('a new event restarts the wait', () {
      final s = ChangeSettler(quiet: const Duration(seconds: 3));
      s.note('/music/a.mp3', t0);
      s.note('/music/a.mp3', t0.add(const Duration(seconds: 2)));
      expect(s.ready(t0.add(const Duration(seconds: 4)), (_) => 10), isEmpty);
      expect(s.ready(t0.add(const Duration(seconds: 6)), (_) => 10), isEmpty);
      expect(s.ready(t0.add(const Duration(seconds: 8)), (_) => 10), ['/music/a.mp3']);
    });

    test('a deleted file is ready as soon as it is quiet', () {
      final s = ChangeSettler();
      s.note('/music/gone.mp3', t0);
      expect(s.ready(t0.add(const Duration(seconds: 1)), (_) => null), isEmpty);
      expect(s.ready(t0.add(const Duration(seconds: 4)), (_) => null), ['/music/gone.mp3']);
    });

    test('many events for one file make one entry', () {
      final s = ChangeSettler();
      for (var i = 0; i < 50; i++) {
        s.note('/music/a.mp3', t0.add(Duration(milliseconds: i * 10)));
      }
      expect(s.length, 1);
    });
  });

  group('phone rescans', () {
    test('at most every interval', () {
      const gap = Duration(minutes: 10);
      expect(shouldRescan(last: null, now: t0, interval: gap), isTrue);
      expect(shouldRescan(last: t0, now: t0.add(const Duration(minutes: 9)), interval: gap), isFalse);
      expect(shouldRescan(last: t0, now: t0.add(const Duration(minutes: 10)), interval: gap), isTrue);
    });

    test('diffSnapshots finds added, removed and changed files', () {
      final before = {
        '/m/a.mp3': const FileStamp(10, 1),
        '/m/b.mp3': const FileStamp(20, 1),
        '/m/c.mp3': const FileStamp(30, 1),
      };
      final after = {
        '/m/a.mp3': const FileStamp(10, 1), // same
        '/m/b.mp3': const FileStamp(25, 2), // changed
        '/m/d.mp3': const FileStamp(40, 3), // new
      };
      final d = diffSnapshots(before, after);
      expect(d.added, {'/m/d.mp3'});
      expect(d.removed, {'/m/c.mp3'});
      expect(d.changed, {'/m/b.mp3'});
      expect(diffSnapshots(after, after).isEmpty, isTrue);
    });

    test('readSnapshotSync lists music only, skipping hidden and partial files', () {
      final dir = Directory.systemTemp.createTempSync('fw_snap');
      addTearDown(() => dir.deleteSync(recursive: true));
      File(p.join(dir.path, 'a.mp3')).writeAsBytesSync([1, 2, 3]);
      File(p.join(dir.path, 'a.mp3.part')).writeAsBytesSync([1]);
      File(p.join(dir.path, 'cover.jpg')).writeAsBytesSync([1]);
      Directory(p.join(dir.path, 'Album')).createSync();
      File(p.join(dir.path, 'Album', 'b.flac')).writeAsBytesSync([1, 2]);
      Directory(p.join(dir.path, '.cache')).createSync();
      File(p.join(dir.path, '.cache', 'c.mp3')).writeAsBytesSync([1]);
      final snap = readSnapshotSync(dir.path)!;
      expect(snap.keys.map(p.basename).toSet(), {'a.mp3', 'b.flac'});
      expect(snap[p.join(dir.path, 'a.mp3')]!.size, 3);
      expect(readSnapshotSync(p.join(dir.path, 'nope')), isNull);
    });
  });

  group('planSync', () {
    bool never(String _) => false;

    test('new files are added, files already in the library are not', () {
      final lib = [song('/music/a.mp3')];
      final plan = planSync(
        root: root,
        disk: {'/music/a.mp3': const FileStamp(1, 1), '/music/b.mp3': const FileStamp(2, 1)},
        library: lib,
        exists: never,
      );
      expect(plan.addedPaths, ['/music/b.mp3']);
      expect(plan.removedIds, isEmpty);
    });

    test('a song the person removed on purpose is not brought back', () {
      final plan = planSync(
        root: root,
        disk: {'/music/b.mp3': const FileStamp(2, 1)},
        library: [song('/music/a.mp3')],
        excluded: {'/music/b.mp3'},
        exists: (_) => true,
      );
      expect(plan.addedPaths, isEmpty);
    });

    test('a deleted file leaves the library, a file that is still there does not', () {
      final a = song('/music/a.mp3');
      final b = song('/music/b.mp3');
      final plan = planSync(root: root, disk: {'/music/b.mp3': const FileStamp(2, 1)}, library: [a, b], exists: never);
      expect(plan.removedIds, {a.id});
      // The listing missed it (a folder it couldn't read) but the file exists: keep it.
      final kept = planSync(
        root: root,
        disk: {'/music/b.mp3': const FileStamp(2, 1)},
        library: [a, b],
        exists: (_) => true,
      );
      expect(kept.removedIds, isEmpty);
    });

    test('an empty listing is an unplugged drive, not a deleted library', () {
      final plan = planSync(root: root, disk: {}, library: [song('/music/a.mp3')], exists: never);
      expect(plan.isEmpty, isTrue);
    });

    test('songs outside the folder and streamed songs are left alone', () {
      final other = song('/other/x.mp3');
      final yt = Track.youtube(videoId: 'abc', title: 'S', artist: 'A');
      final plan = planSync(
        root: root,
        disk: {'/music/b.mp3': const FileStamp(2, 1)},
        library: [other, yt],
        exists: never,
      );
      expect(plan.removedIds, isEmpty);
      expect(plan.addedPaths, ['/music/b.mp3']);
    });

    test('a moved file keeps its tags (matched by exact size)', () {
      final old = song('/music/a.mp3', title: 'Real Title');
      final plan = planSync(
        root: root,
        disk: {'/music/Sorted/a-renamed.mp3': const FileStamp(500, 9)},
        previous: {'/music/a.mp3': const FileStamp(500, 1)},
        library: [old],
        exists: never,
      );
      expect(plan.addedPaths, isEmpty);
      expect(plan.removedIds, isEmpty);
      final moved = plan.moved[old.id]!;
      expect(moved.path, '/music/Sorted/a-renamed.mp3');
      expect(moved.id, Uri.file('/music/Sorted/a-renamed.mp3').toString());
      expect(moved.title, 'Real Title');
      expect(moved.addedAt, old.addedAt);
      expect(moved.tagged, isTrue);
    });

    test('a different size is not a move', () {
      final old = song('/music/a.mp3');
      final plan = planSync(
        root: root,
        disk: {'/music/b.mp3': const FileStamp(999, 9)},
        previous: {'/music/a.mp3': const FileStamp(500, 1)},
        library: [old],
        exists: never,
      );
      expect(plan.moved, isEmpty);
      expect(plan.removedIds, {old.id});
      expect(plan.addedPaths, ['/music/b.mp3']);
    });

    test('without an earlier listing only the same file name counts, and only if there is one match', () {
      final old = song('/music/a.mp3');
      final byName = planSync(
        root: root,
        disk: {'/music/New/a.mp3': const FileStamp(500, 9)},
        library: [old],
        exists: never,
      );
      expect(byName.moved.keys, [old.id]);
      final renamed = planSync(
        root: root,
        disk: {'/music/New/other.mp3': const FileStamp(500, 9)},
        library: [old],
        exists: never,
      );
      expect(renamed.moved, isEmpty);
      final twins = planSync(
        root: root,
        disk: {'/music/X/a.mp3': const FileStamp(500, 9), '/music/Y/a.mp3': const FileStamp(500, 9)},
        library: [old],
        exists: never,
      );
      expect(twins.moved, isEmpty);
      expect(twins.removedIds, {old.id});
      expect(twins.addedPaths, hasLength(2));
    });

    test('two gone songs with the same size are not guessed between', () {
      final a = song('/music/a.mp3');
      final b = song('/music/b.mp3');
      final plan = planSync(
        root: root,
        disk: {'/music/n/c.mp3': const FileStamp(500, 9)},
        previous: {'/music/a.mp3': const FileStamp(500, 1), '/music/b.mp3': const FileStamp(500, 1)},
        library: [a, b],
        exists: never,
      );
      expect(plan.moved, isEmpty);
      expect(plan.removedIds, {a.id, b.id});
      expect(plan.addedPaths, ['/music/n/c.mp3']);
    });

    test('a changed file is read again, an unchanged one is not', () {
      final a = song('/music/a.mp3');
      final b = song('/music/b.mp3');
      final plan = planSync(
        root: root,
        disk: {'/music/a.mp3': const FileStamp(10, 5), '/music/b.mp3': const FileStamp(20, 1)},
        previous: {'/music/a.mp3': const FileStamp(10, 1), '/music/b.mp3': const FileStamp(20, 1)},
        library: [a, b],
        exists: (_) => true,
      );
      expect(plan.retagIds, {a.id});
      expect(plan.addedPaths, isEmpty);
    });

    test('slices of a cue sheet go when their audio file goes', () {
      final cue = Track(
        id: '${Uri.file('/music/album.flac')}#cue1',
        uri: Uri.file('/music/album.flac'),
        title: 'One',
        artist: 'A',
        start: Duration.zero,
        tagged: true,
      );
      final plan = planSync(root: root, disk: {'/music/z.mp3': const FileStamp(1, 1)}, library: [cue], exists: never);
      expect(plan.removedIds, {cue.id});
      expect(plan.moved, isEmpty);
    });
  });
}
