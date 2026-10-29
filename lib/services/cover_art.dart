import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Cover art made fit for a file's tags.
abstract final class CoverArt {
  /// [image] (JPEG, PNG or WebP, any shape) as a centred square JPEG of at most [size] pixels a side.
  /// A JPEG that already is square (within 2%) and no larger than [size] comes back as it is.
  /// The work runs off the UI isolate. Throws when [image] can't be decoded.
  static Future<Uint8List> squareJpeg(Uint8List image, {int size = 1000, int quality = 90}) =>
      Isolate.run(() => _squareJpeg(image, size, quality));

  static Uint8List _squareJpeg(Uint8List bytes, int size, int quality) {
    final jpeg = bytes.length > 3 && bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff;
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw const FormatException('The cover couldn\'t be read.');
    var src = img.bakeOrientation(decoded);
    final w = src.width, h = src.height;
    final side = w < h ? w : h;
    final square = (w - h).abs() <= side * 0.02;
    if (jpeg && square && w <= size && h <= size) return bytes;
    src = img.copyCrop(src, x: (w - side) ~/ 2, y: (h - side) ~/ 2, width: side, height: side);
    if (side > size) src = img.copyResize(src, width: size, height: size, interpolation: img.Interpolation.cubic);
    return img.encodeJpg(src, quality: quality);
  }
}
