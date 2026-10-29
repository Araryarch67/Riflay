import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/metadata.dart';
import 'package:riflay/services/webm_opus.dart';
import 'package:riflay/services/youtube_importer.dart';

const _link = 'https://music.youtube.com/watch?v=AM3DIzTpcw4';

/// A downloaded file's tags as a download writes them.
TagEdit _edit(Uint8List cover) =>
    TagEdit(title: 'Blinding Lights', artist: 'The Weeknd', album: 'After Hours', year: 2019)
      ..comment = _link
      ..cover = cover;

void main() {
  late Directory dir;
  late Uint8List cover;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('download_tags_test');
    cover = File('test/fixtures/cover_square.jpg').readAsBytesSync();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// [fixture] copied here as `<id>.<ext>`, tagged like a download, and read back with the app's own reader.
  Future<File> tagged(String fixture, String ext) async {
    final file = File('${dir.path}/AM3DIzTpcw4.$ext');
    if (fixture.endsWith('.webm')) {
      await WebmOpus.remuxFile(fixture, file.path);
    } else {
      File(fixture).copySync(file.path);
    }
    await Metadata.tagFile(file.path, _edit(cover));
    return file;
  }

  Future<void> expectTagged(File file) async {
    final tags = await Metadata.readTags(Track(id: file.path, uri: file.uri, title: '', artist: ''));
    expect(tags.title, 'Blinding Lights');
    expect(tags.artist, 'The Weeknd');
    expect(tags.album, 'After Hours');
    expect(tags.year, 2019);
    final m = readMetadata(file, getImage: true);
    expect(m.pictures, hasLength(1));
    expect(m.pictures.single.bytes, cover);
    expect(m.pictures.single.mimetype, 'image/jpeg');
    expect(m.pictures.single.pictureType, PictureType.coverFront);
  }

  test('Opus: OpusTags and a METADATA_BLOCK_PICTURE, the link as a comment', () async {
    final file = await tagged('test/fixtures/sine.webm', 'opus');
    await expectTagged(file);
    final text = latin1.decode(file.readAsBytesSync());
    expect(text, contains('COMMENT=$_link'));
    expect(text, contains('METADATA_BLOCK_PICTURE='));
    expect(text, startsWith('OggS'));
  });

  test('M4A: ©nam, ©ART, ©alb and covr', () async {
    await expectTagged(await tagged('test/fixtures/sine.m4a', 'm4a'));
  });

  test('M4A as YouTube serves it (fragmented)', () async {
    final file = await tagged('test/fixtures/sine_frag.m4a', 'm4a');
    await expectTagged(file);
    // Other players still read the audio.
    final ProcessResult r;
    try {
      r = await Process.run('ffmpeg', ['-v', 'error', '-i', file.path, '-f', 'null', '-']);
    } on ProcessException {
      return;
    }
    expect(r.stderr, isEmpty);
  });

  test('FLAC: Vorbis comments and a PICTURE block', () async {
    await expectTagged(await tagged('test/fixtures/sine.flac', 'flac'));
  });

  test('MP3: ID3v2 TIT2, TPE1, TALB, APIC and the link in COMM', () async {
    final file = await tagged('test/fixtures/sine.mp3', 'mp3');
    await expectTagged(file);
    final bytes = file.readAsBytesSync();
    expect(latin1.decode(bytes.sublist(0, 3)), 'ID3');
    expect(bytes[3], 4, reason: 'ID3v2.4 stays what ffmpeg wrote');
    final text = latin1.decode(bytes);
    expect(text, contains('COMM'));
    expect(text, contains(_link));
  });

  test('tagging leaves the audio as it was', () async {
    for (final (fixture, ext) in [('sine.mp3', 'mp3'), ('sine.flac', 'flac'), ('sine.m4a', 'm4a')]) {
      final before = readMetadata(File('test/fixtures/$fixture')).duration;
      final after = readMetadata(await tagged('test/fixtures/$fixture', ext)).duration;
      expect(after, before, reason: ext);
    }
  });

  test('a file that can not be tagged is an error the download catches, not a changed file', () async {
    final file = File('${dir.path}/x.webm')..writeAsBytesSync([1, 2, 3]);
    await expectLater(Metadata.tagFile(file.path, _edit(cover)), throwsA(anything));
    expect(file.readAsBytesSync(), [1, 2, 3]);
    expect(dir.listSync(), hasLength(1), reason: 'no temp file left behind');
  });

  test('remuxOpus replaces the WebM with an .opus; a broken WebM stays as it is', () async {
    final webm = File('${dir.path}/AM3DIzTpcw4.webm')
      ..writeAsBytesSync(File('test/fixtures/sine.webm').readAsBytesSync());
    final opus = await YoutubeImporter.remuxOpus(webm);
    expect(opus.path, endsWith('.opus'));
    expect(webm.existsSync(), isFalse);
    final bad = File('${dir.path}/bad.webm')..writeAsBytesSync([1, 2, 3, 4]);
    expect((await YoutubeImporter.remuxOpus(bad)).path, bad.path);
    expect(bad.existsSync(), isTrue);
    expect(dir.listSync().map((e) => e.path.split('/').last).toSet(), {'AM3DIzTpcw4.opus', 'bad.webm'});
  });

  test('toMp3 makes a constant-bitrate MP3 and removes the stream', () async {
    final webm = File('${dir.path}/AM3DIzTpcw4.webm')
      ..writeAsBytesSync(File('test/fixtures/sine.webm').readAsBytesSync());
    final File mp3;
    try {
      mp3 = await YoutubeImporter.toMp3(webm, File('${dir.path}/AM3DIzTpcw4.mp3'), 128);
    } on ProcessException {
      markTestSkipped('ffmpeg is not installed');
      return;
    }
    expect(mp3.existsSync(), isTrue);
    expect(webm.existsSync(), isFalse);
    expect(File('${mp3.path}.part').existsSync(), isFalse);
    final probe = await Process.run('ffprobe', [
      '-v',
      'error',
      '-show_entries',
      'stream=codec_name,bit_rate',
      '-of',
      'default=nw=1',
      mp3.path,
    ]);
    expect(probe.stdout, contains('codec_name=mp3'));
    expect(probe.stdout, contains('bit_rate=128000'));
    await Metadata.tagFile(mp3.path, _edit(cover));
    await expectTagged(mp3);
  });

  group('square cover', () {
    Future<Uint8List> jpeg(String size) async {
      final out = '${dir.path}/c.jpg';
      final r = await Process.run('ffmpeg', [
        '-v',
        'error',
        '-y',
        '-f',
        'lavfi',
        '-i',
        'testsrc=s=$size',
        '-frames:v',
        '1',
        out,
      ]);
      if (r.exitCode != 0) throw StateError('${r.stderr}');
      return File(out).readAsBytesSync();
    }

    test('a square JPEG is kept as it is', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final r = await YoutubeImporter.squareCover(cover);
      expect(r.bytes, cover);
      expect(r.mime, 'image/jpeg');
    });

    test('a 16:9 thumbnail is cropped to a centred square', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final Uint8List wide;
      try {
        wide = await jpeg('640x360');
      } on ProcessException {
        markTestSkipped('ffmpeg is not installed');
        return;
      }
      final r = await YoutubeImporter.squareCover(wide);
      expect(r.mime, 'image/png');
      final d = ByteData.sublistView(r.bytes);
      expect(d.getUint32(16), 360);
      expect(d.getUint32(20), 360);
    });
  });
}
