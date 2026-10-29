import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:riflay/services/cover_art.dart';

bool _isJpeg(Uint8List b) => b.length > 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff;

img.Image _decode(Uint8List b) => img.decodeJpg(b)!;

/// A picture whose left half is red and right half is blue, so a centre crop is checkable.
img.Image _split(int w, int h) {
  final i = img.Image(width: w, height: h);
  for (final p in i) {
    p.setRgb(p.x < w ~/ 2 ? 255 : 0, 0, p.x < w ~/ 2 ? 0 : 255);
  }
  return i;
}

void main() {
  test('a 16:9 JPEG becomes a centred square JPEG', () async {
    final wide = Uint8List.fromList(img.encodeJpg(_split(640, 360)));
    final out = await CoverArt.squareJpeg(wide);
    expect(_isJpeg(out), isTrue);
    final i = _decode(out);
    expect(i.width, 360);
    expect(i.height, 360);
    // The centre crop keeps the red/blue boundary in the middle.
    expect(i.getPixel(20, 180).r, greaterThan(200));
    expect(i.getPixel(340, 180).b, greaterThan(200));
  });

  test('a PNG thumbnail comes out as a JPEG', () async {
    final out = await CoverArt.squareJpeg(Uint8List.fromList(img.encodePng(_split(480, 360))));
    expect(_isJpeg(out), isTrue);
    expect(_decode(out).width, 360);
  });

  test('a large image is scaled down to at most 1000 px', () async {
    final out = await CoverArt.squareJpeg(Uint8List.fromList(img.encodeJpg(_split(2400, 1350))));
    final i = _decode(out);
    expect([i.width, i.height], [1000, 1000]);
    final small = _decode(await CoverArt.squareJpeg(Uint8List.fromList(img.encodePng(_split(1200, 1200))), size: 500));
    expect(small.width, 500);
  });

  test('a square JPEG of a fitting size is passed through unchanged', () async {
    final cover = File('test/fixtures/cover_square.jpg').readAsBytesSync();
    expect(await CoverArt.squareJpeg(cover), cover);
  });

  test('a square PNG is converted, not passed through', () async {
    final png = Uint8List.fromList(img.encodePng(_split(300, 300)));
    expect(_isJpeg(await CoverArt.squareJpeg(png)), isTrue);
  });

  test('something that is not an image is an error', () async {
    await expectLater(CoverArt.squareJpeg(Uint8List.fromList([1, 2, 3, 4, 5])), throwsA(anything));
  });
}
