import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/metadata.dart';
import 'package:riflay/services/tag_writer.dart';

/// Runs ffmpeg; false when it isn't installed (the test is then skipped).
Future<bool> _ffmpeg(List<String> args) async {
  try {
    final r = await Process.run('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', ...args]);
    if (r.exitCode != 0) throw StateError('ffmpeg ${args.join(' ')}: ${r.stderr}');
    return true;
  } on ProcessException {
    return false;
  }
}

/// Every tag ffprobe sees (format and stream), keys lowercased.
Future<Map<String, String>> _probe(String path) async {
  final r = await Process.run('ffprobe', [
    '-v', 'error', '-select_streams', 'a', '-show_entries', 'format_tags:stream_tags', '-of', 'json', path, //
  ]);
  final json = jsonDecode(r.stdout as String) as Map<String, dynamic>;
  final tags = <String, String>{};
  void add(Object? m) {
    if (m is Map) m.forEach((k, v) => tags['$k'.toLowerCase()] = '$v');
  }

  add((json['format'] as Map?)?['tags']);
  for (final s in (json['streams'] as List?) ?? const []) {
    add((s as Map)['tags']);
  }
  return tags;
}

/// MD5 of the decoded audio, and ffmpeg's complaints while decoding it.
Future<(String, String)> _decode(String path) async {
  final r = await Process.run('ffmpeg', ['-v', 'error', '-i', path, '-map', '0:a:0', '-f', 'md5', '-']);
  return ((r.stdout as String).trim(), (r.stderr as String).trim());
}

/// Checks every Ogg page: capture pattern, checksum and page numbers in order.
void _checkOggPages(Uint8List bytes) {
  final table = List<int>.generate(256, (i) {
    var r = i << 24;
    for (var j = 0; j < 8; j++) {
      r = r & 0x80000000 != 0 ? (r << 1) ^ 0x04c11db7 : r << 1;
    }
    return r & 0xffffffff;
  });
  var pos = 0, expected = 0;
  while (pos < bytes.length) {
    expect(ascii.decode(bytes.sublist(pos, pos + 4)), 'OggS', reason: 'page at $pos');
    final segments = bytes[pos + 26];
    var length = 27 + segments;
    for (var i = 0; i < segments; i++) {
      length += bytes[pos + 27 + i];
    }
    final page = Uint8List.fromList(bytes.sublist(pos, pos + length));
    final data = ByteData.sublistView(page);
    expect(data.getUint32(18, Endian.little), expected++, reason: 'page number at $pos');
    final stored = data.getUint32(22, Endian.little);
    data.setUint32(22, 0, Endian.little);
    var crc = 0;
    for (final b in page) {
      crc = ((crc << 8) & 0xffffffff) ^ table[(crc >> 24) ^ b];
    }
    expect(crc, stored, reason: 'checksum of the page at $pos');
    pos += length;
  }
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('tagwriter'));
  tearDown(() => dir.deleteSync(recursive: true));

  // A small PNG, as the tag editor's cover picker would hand over.
  final cover = base64.decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );

  TagEdit edit() => TagEdit(
    title: 'Poison Dagger — ライブ',
    artist: 'D-low',
    album: 'Beatbox Live',
    year: 2024,
    trackNumber: 4,
    discNumber: 2,
    genre: 'Beatbox',
  );

  // Each format as ffmpeg writes it, with tags the editor must leave alone.
  final cases = <String, List<String>>{
    'id3v23.mp3': ['-c:a', 'libmp3lame', '-write_id3v1', '1'],
    'id3v24.mp3': ['-c:a', 'libmp3lame', '-id3v2_version', '4'],
    'vorbis.ogg': ['-c:a', 'libvorbis'],
    'opus.opus': ['-c:a', 'libopus'],
    'info.wav': ['-c:a', 'pcm_s16le'],
    'id3.wav': ['-c:a', 'pcm_s24le', '-write_id3v2', '1'],
    'id3.aiff': ['-c:a', 'pcm_s16be', '-write_id3v2', '1'],
    'ape.wv': ['-c:a', 'wavpack'],
  };

  for (final MapEntry(key: name, value: codec) in cases.entries) {
    test('$name: the edit reads back, everything else stays', () async {
      final src = '${dir.path}/src-$name', dst = File('${dir.path}/dst-$name');
      final made = await _ffmpeg([
        '-f', 'lavfi', '-i', 'sine=frequency=997:sample_rate=44100:duration=1.5', ...codec, //
        '-metadata', 'title=Old title', '-metadata', 'artist=Old artist', '-metadata', 'album=Old album',
        '-metadata', 'date=2019', '-metadata', 'track=3/12', '-metadata', 'disc=1',
        '-metadata', 'genre=Rock', '-metadata', 'REPLAYGAIN_TRACK_GAIN=-6.20 dB',
        '-metadata', 'comment=keep me', src,
      ]);
      if (!made) return markTestSkipped('ffmpeg not available');
      final before = await _probe(src);
      final (audio, _) = await _decode(src);

      TagWriter.write(
        src,
        dst,
        edit()
          ..cover = Uint8List.fromList(cover)
          ..coverMime = 'image/png',
      );

      final m = readMetadata(dst, getImage: true);
      expect(m.title, 'Poison Dagger — ライブ');
      expect(m.artist, 'D-low');
      expect(m.album, 'Beatbox Live');
      expect(m.year?.year, 2024);
      expect(m.trackNumber, 4);
      expect(m.discNumber, 2);
      expect(m.genres, contains('Beatbox'));
      expect(m.pictures.any((p) => listEquals(p.bytes, cover)), isTrue, reason: 'the new cover is there');

      final after = await _probe(dst.path);
      for (final key in before.keys) {
        if (const {'title', 'artist', 'album', 'date', 'track', 'disc', 'genre', 'encoder'}.contains(key)) continue;
        if (key.startsWith('id3v2_priv') || key == 'tyer' || key == 'tdrc') continue;
        expect(after[key], before[key], reason: '$key is kept');
      }
      if (after.containsKey('track')) expect(after['track'], '4/12', reason: 'the track total stays');

      final (audioAfter, complaints) = await _decode(dst.path);
      expect(audioAfter, audio, reason: 'the audio is untouched');
      expect(complaints, isEmpty);
      if (name.endsWith('.ogg') || name.endsWith('.opus')) _checkOggPages(dst.readAsBytesSync());

      // Editing the result again works the same.
      final again = File('${dir.path}/again-$name');
      TagWriter.write(dst.path, again, edit()..title = 'Second');
      expect(readMetadata(again).title, 'Second');
      expect((await _decode(again.path)).$1, audio);
    });
  }

  test('Ogg: a cover larger than a page moves every audio page along', () async {
    final src = '${dir.path}/big.ogg', dst = File('${dir.path}/big-out.ogg');
    if (!await _ffmpeg(['-f', 'lavfi', '-i', 'sine=duration=3', '-c:a', 'libvorbis', src])) {
      return markTestSkipped('ffmpeg not available');
    }
    final (audio, _) = await _decode(src);
    // A real picture (noise compresses badly, so it spans many pages).
    final png = '${dir.path}/big.png';
    await _ffmpeg(['-f', 'lavfi', '-i', 'color=c=gray:s=400x400,noise=alls=100:allf=t', '-frames:v', '1', png]);
    final big = File(png).readAsBytesSync();
    expect(big.length, greaterThan(100 * 1024));
    TagWriter.write(
      src,
      dst,
      edit()
        ..cover = big
        ..coverMime = 'image/png',
    );
    _checkOggPages(dst.readAsBytesSync());
    final (audioAfter, complaints) = await _decode(dst.path);
    expect(audioAfter, audio);
    expect(complaints, isEmpty);
    expect(readMetadata(dst, getImage: true).pictures.single.bytes.length, big.length);
  });

  test('an MP3 with no tag at all gets one; clearing a field removes it', () async {
    final src = '${dir.path}/bare.mp3', dst = File('${dir.path}/bare-out.mp3');
    if (!await _ffmpeg([
      '-f',
      'lavfi',
      '-i',
      'sine=duration=1',
      '-c:a',
      'libmp3lame',
      '-write_xing',
      '0',
      '-id3v2_version',
      '0',
      src,
    ])) {
      return markTestSkipped('ffmpeg not available');
    }
    TagWriter.write(src, dst, edit());
    expect(readMetadata(dst).title, 'Poison Dagger — ライブ');
    final cleared = File('${dir.path}/cleared.mp3');
    TagWriter.write(
      dst.path,
      cleared,
      edit()
        ..genre = null
        ..year = null,
    );
    final tags = await _probe(cleared.path);
    expect(tags.containsKey('genre'), isFalse);
    expect(tags.containsKey('date'), isFalse);
    expect(tags['title'], 'Poison Dagger — ライブ');
  });

  test('a layout it does not handle is refused, and nothing is claimed', () {
    final src = File('${dir.path}/v22.mp3')
      ..writeAsBytesSync([...ascii.encode('ID3'), 2, 0, 0, 0, 0, 0, 0, ...Uint8List(64)]);
    expect(() => TagWriter.write(src.path, File('${dir.path}/out.mp3'), edit()), throwsA(isA<UnsupportedTagLayout>()));
  });
}
