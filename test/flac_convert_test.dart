import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/download_prefs.dart';
import 'package:riflay/services/ffmpeg.dart';
import 'package:riflay/services/flac_convert.dart';

Track _song(String path, {String? sourceUrl, Duration? start}) => Track(
  id: Uri.file(path).toString(),
  uri: Uri.file(path),
  title: 'Song',
  artist: 'Artist',
  start: start,
  sourceUrl: sourceUrl,
);

void main() {
  group('eligibility', () {
    test('lossy files can be converted', () {
      for (final ext in ['mp3', 'm4a', 'opus', 'ogg', 'webm', 'aac', 'wma', 'MP3']) {
        expect(FlacConvert.isConvertible(_song('/music/a.$ext')), isTrue, reason: ext);
      }
    });

    test('lossless, DSD and unknown files are left alone', () {
      for (final ext in ['flac', 'wav', 'aiff', 'aif', 'alac', 'wv', 'ape', 'dsf', 'dff', 'txt', 'FLAC']) {
        expect(FlacConvert.isConvertible(_song('/music/a.$ext')), isFalse, reason: ext);
      }
    });

    test('cue slices, SACD tracks and streamed songs are left alone', () {
      expect(FlacConvert.isConvertible(_song('/music/a.mp3', start: const Duration(seconds: 5))), isFalse);
      final sacd = Track(id: '/music/disc.iso#sacd3', uri: Uri.file('/music/disc.iso'), title: 'S', artist: 'A');
      expect(FlacConvert.isConvertible(sacd), isFalse);
      expect(FlacConvert.isConvertible(Track.youtube(videoId: 'dQw4w9WgXcQ', title: 'S', artist: 'A')), isFalse);
      final content = Track(id: 'c', uri: Uri.parse('content://media/1'), title: 'S', artist: 'A');
      expect(FlacConvert.isConvertible(content), isFalse);
    });
  });

  group('what is replaced', () {
    test('downloads are replaced, the person\'s own files are kept', () {
      expect(FlacConvert.replacesOriginal(_song('/dl/YouTube/abc.m4a'), '/dl/YouTube'), isTrue);
      expect(FlacConvert.replacesOriginal(_song('/old/abc.m4a', sourceUrl: 'https://youtu.be/abc'), '/dl'), isTrue);
      expect(FlacConvert.replacesOriginal(_song('/music/a.mp3'), '/dl/YouTube'), isFalse);
    });
  });

  group('target path', () {
    test('goes beside the original', () {
      expect(
        FlacConvert.targetPath('/music/a.mp3', keepOriginal: true, downloadsDir: '/dl', exists: (_) => false),
        '/music/a.flac',
      );
    });

    test('falls back to the downloads folder when the song\'s folder is read-only', () {
      expect(
        FlacConvert.targetPath(
          '/music/a.mp3',
          keepOriginal: true,
          downloadsDir: '/dl',
          folderWritable: false,
          exists: (_) => false,
        ),
        '/dl/a.flac',
      );
      // A download is replaced where it is, whatever else.
      expect(
        FlacConvert.targetPath(
          '/dl/a.m4a',
          keepOriginal: false,
          downloadsDir: '/other',
          folderWritable: false,
          exists: (_) => false,
        ),
        '/dl/a.flac',
      );
    });

    test('never takes a name that exists', () {
      final taken = {'/music/a.flac', '/music/a (2).flac'};
      expect(
        FlacConvert.targetPath('/music/a.mp3', keepOriginal: true, downloadsDir: '/dl', exists: taken.contains),
        '/music/a (3).flac',
      );
    });
  });

  group('Apple Lossless', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('flac_convert_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    List<int> box(String type, List<int> body) {
      final size = 8 + body.length;
      return [size >> 24, size >> 16 & 255, size >> 8 & 255, size & 255, ...type.codeUnits, ...body];
    }

    test('is found inside moov, and an AAC file is not', () async {
      final alac = File(p.join(dir.path, 'a.m4a'))
        ..writeAsBytesSync([
          ...box('ftyp', 'M4A '.codeUnits),
          ...box('moov', [0, 0, ...'alac'.codeUnits]),
        ]);
      final aac = File(p.join(dir.path, 'b.m4a'))
        ..writeAsBytesSync([
          ...box('ftyp', 'M4A '.codeUnits),
          ...box('moov', [0, 0, ...'mp4a'.codeUnits]),
        ]);
      expect(await FlacConvert.isAlac(alac.path), isTrue);
      expect(await FlacConvert.isAlac(aac.path), isFalse);
      expect(await FlacConvert.isAlac(p.join(dir.path, 'missing.m4a')), isFalse);
    });
  });

  group('conversion', () {
    late Directory dir;
    late bool haveFfmpeg;
    setUp(() async {
      dir = Directory.systemTemp.createTempSync('flac_convert_test');
      await Ffmpeg.probe();
      haveFfmpeg = Ffmpeg.installed;
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<File> sine(String name) async {
      final out = File(p.join(dir.path, name));
      final r = await Process.run('ffmpeg', [
        '-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=1', out.path, //
      ]);
      if (r.exitCode != 0) throw StateError('${r.stderr}');
      return out;
    }

    test('a file the person added is kept, with a FLAC beside it', () async {
      if (!haveFfmpeg) return markTestSkipped('ffmpeg is not installed');
      final mp3 = await sine('a.mp3');
      final made = await FlacConvert.convertFile(
        _song(mp3.path),
        FlacQuality.standard,
        downloadsDir: Directory(p.join(dir.path, 'dl')),
      );
      expect(made.path, p.join(dir.path, 'a.flac'));
      expect(File(made.path!).existsSync(), isTrue);
      expect(mp3.existsSync(), isTrue);
      expect(made.id, Uri.file(mp3.path).toString());
      expect(dir.listSync().map((e) => p.basename(e.path)), isNot(contains(endsWith('.part'))));
      expect(dir.listSync().map((e) => p.basename(e.path)), isNot(contains(contains('riflay-src'))));
    });

    test('a download is replaced once the FLAC is there', () async {
      if (!haveFfmpeg) return markTestSkipped('ffmpeg is not installed');
      final dl = Directory(p.join(dir.path, 'dl'))..createSync();
      final m4a = await sine('dl/abc.m4a');
      final made = await FlacConvert.convertFile(
        _song(m4a.path, sourceUrl: 'https://youtu.be/abc'),
        FlacQuality.cd,
        downloadsDir: dl,
      );
      expect(made.path, p.join(dl.path, 'abc.flac'));
      expect(m4a.existsSync(), isFalse);
      expect(File(made.path!).existsSync(), isTrue);
    });

    test('a failure leaves the original and no leftovers', () async {
      if (!haveFfmpeg) return markTestSkipped('ffmpeg is not installed');
      final bad = File(p.join(dir.path, 'bad.mp3'))..writeAsStringSync('not audio');
      await expectLater(
        FlacConvert.convertFile(_song(bad.path), FlacQuality.standard, downloadsDir: dir),
        throwsA(anything),
      );
      expect(dir.listSync().map((e) => p.basename(e.path)).toList(), ['bad.mp3']);
    });
  });
}
