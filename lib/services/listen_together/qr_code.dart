import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

import 'internet.dart';

/// A QR carries only the room code, never a URL or device address.
String? listenCodeFromQr(String text) => normalizeCode(text);

String listenQrPayload(String code) => listenCodeFromQr(code) ?? (throw ArgumentError.value(code, 'code'));

/// Reads an imported QR image on platforms with or without camera scanning.
/// Returns null for unrelated QR codes, invalid images, and images without a QR.
String? listenCodeFromImage(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final image = decoded.width > 1600 || decoded.height > 1600
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? 1600 : null,
            height: decoded.height > decoded.width ? 1600 : null,
          )
        : decoded;
    final pixels = image.convert(numChannels: 4).getBytes(order: img.ChannelOrder.abgr);
    final source = RGBLuminanceSource(image.width, image.height, pixels.buffer.asInt32List());
    final result = QRCodeReader().decode(BinaryBitmap(HybridBinarizer(source)));
    return listenCodeFromQr(result.text);
  } catch (_) {
    return null;
  }
}
