import 'dart:async';
import 'dart:typed_data';

/// A streaming FLAC encoder for TV conversions, with no prediction at all:
/// every channel of every frame is a VERBATIM subframe, the samples as they
/// are. That is a valid FLAC any decoder reads, it costs next to no CPU (a
/// phone can do it while decoding), and a local network has the bandwidth for
/// an uncompressed stream.
///
/// The length isn't known up front (the input is a live decode), so
/// STREAMINFO says "unknown" and the frames carry the rest.
abstract final class FlacStream {
  /// Samples per frame (per channel), except the last frame.
  static const blockSize = 4096;

  /// Wraps interleaved little-endian PCM into FLAC. [bits] is 16 (input is
  /// s16le) or 24 (input is s32le; the top three bytes of each sample are kept).
  static Stream<Uint8List> encode(Stream<List<int>> pcm, {required int rate, required int channels, int bits = 16}) {
    assert(bits == 16 || bits == 24);
    assert(channels >= 1 && channels <= 8);
    assert(rate > 0 && rate < (1 << 20));
    final inWidth = bits == 16 ? 2 : 4;
    final frameBytes = blockSize * channels * inWidth;
    late StreamController<Uint8List> out;
    StreamSubscription<List<int>>? sub;
    final pending = BytesBuilder(copy: false);
    var number = 0;

    void emit(Uint8List block, int samples) {
      out.add(_frame(block, samples, number++, rate, channels, bits, inWidth));
    }

    out = StreamController<Uint8List>(
      onListen: () {
        out.add(_header(rate, channels, bits));
        sub = pcm.listen(
          (chunk) {
            pending.add(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
            if (pending.length < frameBytes) return;
            final all = pending.takeBytes();
            var o = 0;
            while (all.length - o >= frameBytes) {
              emit(Uint8List.sublistView(all, o, o + frameBytes), blockSize);
              o += frameBytes;
            }
            if (o < all.length) pending.add(Uint8List.sublistView(all, o));
          },
          onError: out.addError,
          onDone: () {
            final rest = pending.takeBytes();
            final whole = rest.length - rest.length % (channels * inWidth);
            if (whole > 0) emit(Uint8List.sublistView(rest, 0, whole), whole ~/ (channels * inWidth));
            out.close();
          },
        );
      },
      onPause: () => sub?.pause(),
      onResume: () => sub?.resume(),
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  static Uint8List _header(int rate, int channels, int bits) {
    final b = ByteData(4 + 4 + 34);
    b.setUint32(0, 0x664C6143); // "fLaC"
    b.setUint32(4, (0x80 << 24) | 34); // last metadata block, STREAMINFO, 34 bytes
    b.setUint16(8, blockSize);
    b.setUint16(10, blockSize);
    // Frame sizes (min, max) 0 = unknown, then rate (20) | channels - 1 (3) | bits - 1 (5) | samples (36).
    b.setUint32(18, (rate << 12) | ((channels - 1) << 9) | ((bits - 1) << 4));
    // Total samples 0 (unknown), MD5 zero: already zero.
    return b.buffer.asUint8List();
  }

  static int _rateCode(int rate) {
    switch (rate) {
      case 88200:
        return 1;
      case 176400:
        return 2;
      case 192000:
        return 3;
      case 8000:
        return 4;
      case 16000:
        return 5;
      case 22050:
        return 6;
      case 24000:
        return 7;
      case 32000:
        return 8;
      case 44100:
        return 9;
      case 48000:
        return 10;
      case 96000:
        return 11;
    }
    if (rate % 1000 == 0 && rate ~/ 1000 < 256) return 12;
    if (rate < 65536) return 13;
    if (rate % 10 == 0 && rate ~/ 10 < 65536) return 14;
    return 0; // STREAMINFO's
  }

  static Uint8List _frame(Uint8List pcm, int samples, int number, int rate, int channels, int bits, int inWidth) {
    final outWidth = bits ~/ 8;
    final head = BytesBuilder(copy: false)
      ..addByte(0xFF)
      ..addByte(0xF8) // fixed block size
      ..addByte(((samples == blockSize ? 12 : 7) << 4) | _rateCode(rate))
      ..addByte(((channels - 1) << 4) | ((bits == 16 ? 4 : 6) << 1))
      ..add(_utf8Number(number));
    if (samples != blockSize) {
      head
        ..addByte((samples - 1) >> 8)
        ..addByte((samples - 1) & 0xFF);
    }
    switch (_rateCode(rate)) {
      case 12:
        head.addByte(rate ~/ 1000);
      case 13:
        head
          ..addByte(rate >> 8)
          ..addByte(rate & 0xFF);
      case 14:
        head
          ..addByte((rate ~/ 10) >> 8)
          ..addByte((rate ~/ 10) & 0xFF);
    }
    final headBytes = head.takeBytes();
    final frame = Uint8List(headBytes.length + 1 + channels * (1 + samples * outWidth) + 2);
    frame.setRange(0, headBytes.length, headBytes);
    var o = headBytes.length;
    final crc8 = _crc8(frame, 0, o);
    frame[o++] = crc8;
    final stride = channels * inWidth;
    for (var c = 0; c < channels; c++) {
      frame[o++] = 0x02; // VERBATIM, no wasted bits
      var i = c * inWidth + (inWidth - outWidth); // 24-bit: skip the low byte of s32
      for (var s = 0; s < samples; s++, i += stride) {
        if (outWidth == 2) {
          frame[o++] = pcm[i + 1];
          frame[o++] = pcm[i];
        } else {
          frame[o++] = pcm[i + 2];
          frame[o++] = pcm[i + 1];
          frame[o++] = pcm[i];
        }
      }
    }
    final crc = _crc16(frame, 0, o);
    frame[o++] = crc >> 8;
    frame[o] = crc & 0xFF;
    return frame;
  }

  /// FLAC's UTF-8-style coding of the frame number (up to 36 bits).
  static List<int> _utf8Number(int n) {
    if (n < 0x80) return [n];
    var extra = 1;
    while (n >= (1 << (5 * extra + 6))) {
      extra++;
    }
    final lead = (0xFF00 >> (extra + 1)) & 0xFF;
    return [
      lead | (n >> (6 * extra)),
      for (var i = extra - 1; i >= 0; i--) 0x80 | ((n >> (6 * i)) & 0x3F),
    ];
  }

  static final _crc8Table = Uint8List.fromList([
    for (var i = 0; i < 256; i++)
      () {
        var c = i;
        for (var k = 0; k < 8; k++) {
          c = (c & 0x80) != 0 ? ((c << 1) ^ 0x07) & 0xFF : (c << 1) & 0xFF;
        }
        return c;
      }(),
  ]);

  static final _crc16Table = Uint16List.fromList([
    for (var i = 0; i < 256; i++)
      () {
        var c = i << 8;
        for (var k = 0; k < 8; k++) {
          c = (c & 0x8000) != 0 ? ((c << 1) ^ 0x8005) & 0xFFFF : (c << 1) & 0xFFFF;
        }
        return c;
      }(),
  ]);

  static int _crc8(Uint8List d, int from, int to) {
    var c = 0;
    for (var i = from; i < to; i++) {
      c = _crc8Table[c ^ d[i]];
    }
    return c;
  }

  static int _crc16(Uint8List d, int from, int to) {
    var c = 0;
    for (var i = from; i < to; i++) {
      c = ((c << 8) & 0xFFFF) ^ _crc16Table[(c >> 8) ^ d[i]];
    }
    return c;
  }
}
