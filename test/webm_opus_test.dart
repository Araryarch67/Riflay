import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/webm_opus.dart';

/// The pages of an Ogg file, parsed independently of the remuxer.
List<({int flags, int granule, int serial, int sequence, int crc, bool crcOk, List<int> lacing, Uint8List body})>
_pages(Uint8List ogg) {
  final pages =
      <({int flags, int granule, int serial, int sequence, int crc, bool crcOk, List<int> lacing, Uint8List body})>[];
  var pos = 0;
  while (pos < ogg.length) {
    expect(ascii.decode(ogg.sublist(pos, pos + 4)), 'OggS');
    final d = ByteData.sublistView(ogg, pos);
    final segments = ogg[pos + 26];
    final lacing = ogg.sublist(pos + 27, pos + 27 + segments);
    final bodyLength = lacing.fold<int>(0, (a, b) => a + b);
    final length = 27 + segments + bodyLength;
    final page = Uint8List.fromList(ogg.sublist(pos, pos + length));
    final crc = d.getUint32(22, Endian.little);
    page.buffer.asByteData().setUint32(22, 0, Endian.little);
    pages.add((
      flags: ogg[pos + 5],
      granule: d.getUint64(6, Endian.little),
      serial: d.getUint32(14, Endian.little),
      sequence: d.getUint32(18, Endian.little),
      crc: crc,
      crcOk: WebmOpus.oggCrc(page) == crc,
      lacing: lacing,
      body: Uint8List.sublistView(ogg, pos + 27 + segments, pos + length),
    ));
    pos += length;
  }
  return pages;
}

/// EBML pieces for a hand-made WebM.
Uint8List _id(int id) {
  final b = <int>[];
  for (var v = id; v > 0; v >>= 8) {
    b.insert(0, v & 0xff);
  }
  return Uint8List.fromList(b);
}

Uint8List _el(int id, List<int> body, {bool unknownSize = false}) {
  final size = unknownSize
      ? [0x01, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]
      : [0x01, ...List.generate(7, (i) => (body.length >> (8 * (6 - i))) & 0xff)];
  return Uint8List.fromList([..._id(id), ...size, ...body]);
}

/// A WebM with one Opus track of [frames] 20 ms packets (a CELT mono TOC, 0xFC) and padded random-ish payloads.
Uint8List _webm({int frames = 100, bool unknownSizes = false, int? discardNs, List<int>? payloadSizes}) {
  const head = [
    ...[0x4f, 0x70, 0x75, 0x73, 0x48, 0x65, 0x61, 0x64], // OpusHead
    1, 1, 0x38, 0x01, // version, channels, pre-skip 312
    0x80, 0xbb, 0, 0, 0, 0, 0, // 48000 Hz, gain, mapping family
  ];
  final track = _el(0xAE, [
    ..._el(0xD7, [1]),
    ..._el(0x83, [2]),
    ..._el(0x86, ascii.encode('A_OPUS')),
    ..._el(0x63A2, head),
  ]);
  final blocks = <int>[];
  for (var i = 0; i < frames; i++) {
    final size = payloadSizes?[i % payloadSizes.length] ?? 30 + i % 40;
    final payload = [0xFC, ...List.generate(size - 1, (j) => (i * 7 + j) & 0xff)];
    final block = [0x81, i * 20 >> 8 & 0xff, i * 20 & 0xff, 0x80, ...payload];
    if (discardNs != null && i == frames - 1) {
      blocks.addAll(
        _el(0xA0, [
          ..._el(0xA1, [0x81, 0, 0, 0, ...payload]),
          ..._el(0x75A2, _discard(discardNs)),
        ]),
      );
    } else {
      blocks.addAll(_el(0xA3, block));
    }
  }
  final cluster = _el(0x1F43B675, [
    ..._el(0xE7, [0]),
    ...blocks,
  ], unknownSize: unknownSizes);
  final segment = _el(0x18538067, [..._el(0x1654AE6B, track), ...cluster], unknownSize: unknownSizes);
  return Uint8List.fromList([..._el(0x1A45DFA3, _el(0x4282, ascii.encode('webm'))), ...segment]);
}

List<int> _discard(int ns) => [ns >> 24 & 0xff, ns >> 16 & 0xff, ns >> 8 & 0xff, ns & 0xff];

void main() {
  group('WebmOpus', () {
    test('turns a hand-made WebM into valid Ogg Opus pages', () {
      final ogg = WebmOpus.remux(_webm());
      final pages = _pages(ogg);
      expect(pages.every((p) => p.crcOk), isTrue);
      expect(pages.first.flags, 2);
      expect(ascii.decode(pages.first.body.sublist(0, 8)), 'OpusHead');
      expect(ascii.decode(pages[1].body.sublist(0, 8)), 'OpusTags');
      expect(pages.last.flags & 4, 4);
      expect(pages.map((p) => p.sequence), List.generate(pages.length, (i) => i));
      expect(pages.map((p) => p.serial).toSet().length, 1);
      expect(pages.every((p) => p.lacing.length <= 255), isTrue);
      expect(pages.last.granule, 100 * 960);
      // Granules only grow.
      for (var i = 3; i < pages.length; i++) {
        expect(pages[i].granule, greaterThan(pages[i - 1].granule));
      }
    });

    test('copies every packet byte for byte', () {
      final ogg = WebmOpus.remux(_webm(frames: 30));
      final pages = _pages(ogg).skip(2).toList();
      final all = BytesBuilder();
      var lengths = <int>[];
      var run = 0;
      for (final p in pages) {
        for (final l in p.lacing) {
          run += l;
          if (l < 255) {
            lengths.add(run);
            run = 0;
          }
        }
        all.add(p.body);
      }
      expect(lengths, List.generate(30, (i) => 30 + i % 40));
      final body = all.takeBytes();
      expect(body[0], 0xFC);
      expect(body[1], 0);
    });

    test('a packet of 255 bytes or more is laced and a page never has over 255 segments', () {
      final ogg = WebmOpus.remux(_webm(frames: 200, payloadSizes: [255, 510, 1000, 3]));
      final pages = _pages(ogg);
      expect(pages.every((p) => p.crcOk && p.lacing.length <= 255), isTrue);
      expect(pages.last.granule, 200 * 960);
    });

    test('unknown-size Segment and Cluster (a live stream) are read', () {
      final pages = _pages(WebmOpus.remux(_webm(frames: 10, unknownSizes: true)));
      expect(pages.last.granule, 10 * 960);
    });

    test('a DiscardPadding on the last block trims the final granule', () {
      // 5 ms of padding = 240 samples.
      final pages = _pages(WebmOpus.remux(_webm(frames: 10, discardNs: 5000000)));
      expect(pages.last.granule, 10 * 960 - 240);
    });

    test('a file cut off in the middle keeps the packets before the cut', () {
      final webm = _webm(frames: 50);
      final pages = _pages(WebmOpus.remux(Uint8List.sublistView(webm, 0, webm.length - 20)));
      expect(pages.last.granule, 49 * 960);
    });

    test('turns down what is not Opus WebM', () {
      expect(() => WebmOpus.remux(Uint8List.fromList(List.filled(64, 7))), throwsA(isA<WebmOpusException>()));
      expect(() => WebmOpus.remux(Uint8List(0)), throwsA(isA<WebmOpusException>()));
    });

    test('an ffmpeg-made WebM remuxes to Ogg Opus that ffprobe and ffmpeg read', () async {
      final ogg = WebmOpus.remux(File('test/fixtures/sine.webm').readAsBytesSync());
      final pages = _pages(ogg);
      expect(pages.every((p) => p.crcOk), isTrue);
      final preSkip = pages.first.body[10] | pages.first.body[11] << 8;
      expect(preSkip, greaterThan(0));
      // 1 s of sound, plus the pre-skip.
      expect((pages.last.granule - (48000 + preSkip)).abs(), lessThanOrEqualTo(960));
      expect(pages.last.flags & 4, 4);

      final dir = Directory.systemTemp.createTempSync('webm_opus_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/x.opus')..writeAsBytesSync(ogg);
      final ProcessResult probe;
      try {
        probe = await Process.run('ffprobe', [
          '-v', 'error', '-show_entries', 'format=format_name,duration:stream=codec_name,sample_rate', //
          '-of', 'default=nw=1', file.path,
        ]);
      } on ProcessException {
        markTestSkipped('ffprobe is not installed');
        return;
      }
      expect(probe.exitCode, 0, reason: '${probe.stderr}');
      final out = probe.stdout as String;
      expect(out, contains('format_name=ogg'));
      expect(out, contains('codec_name=opus'));
      final duration = double.parse(RegExp(r'duration=([\d.]+)').firstMatch(out)!.group(1)!);
      expect(duration, closeTo(1.0, 0.03));
      // It decodes without a complaint.
      final decode = await Process.run('ffmpeg', ['-v', 'error', '-i', file.path, '-f', 'null', '-']);
      expect(decode.stderr, isEmpty);
    });

    test('remuxFile writes the file', () async {
      final dir = Directory.systemTemp.createTempSync('webm_opus_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      await WebmOpus.remuxFile('test/fixtures/sine.webm', '${dir.path}/y.opus');
      expect(File('${dir.path}/y.opus').readAsBytesSync().sublist(0, 4), ascii.encode('OggS'));
    });
  });
}
