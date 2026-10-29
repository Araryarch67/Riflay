import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

/// How hard [FlacStream.encode] works to make the file small.
enum FlacCompression {
  /// Every channel is a VERBATIM subframe, the samples as they are: next to no CPU (a phone can do it while
  /// decoding live), and a local network has the bandwidth. This is what TV casting wants.
  none,

  /// Per frame: stereo decorrelation (left/side, side/right, mid/side, picked by estimated size), then per channel
  /// the smallest of CONSTANT, VERBATIM and a FIXED predictor (order 0 to 4) with partitioned Rice residuals.
  /// Typically 50 to 60% of verbatim on music, for a few percent of a core.
  fast,
}

/// A streaming FLAC encoder (for TV conversions and for downloads on phones without ffmpeg).
///
/// The length isn't known up front (the input is a live decode), so
/// STREAMINFO says "unknown" (and min/max frame size 0, which is allowed) and the frames carry the rest.
abstract final class FlacStream {
  /// Samples per frame (per channel), except the last frame.
  static const blockSize = 4096;

  /// Wraps interleaved little-endian PCM into FLAC. [bits] is 16 (input is
  /// s16le) or 24 (input is s32le; the top three bytes of each sample are kept).
  static Stream<Uint8List> encode(
    Stream<List<int>> pcm, {
    required int rate,
    required int channels,
    int bits = 16,
    FlacCompression compression = FlacCompression.none,
  }) {
    assert(bits == 16 || bits == 24);
    assert(channels >= 1 && channels <= 8);
    assert(rate > 0 && rate < (1 << 20));
    final inWidth = bits == 16 ? 2 : 4;
    final frameBytes = blockSize * channels * inWidth;
    late StreamController<Uint8List> out;
    StreamSubscription<List<int>>? sub;
    final pending = BytesBuilder(copy: false);
    var number = 0;
    final enc = compression == FlacCompression.fast ? _Encoder(rate, channels, bits) : null;

    void emit(Uint8List block, int samples) {
      out.add(
        enc != null
            ? enc.frame(ByteData.sublistView(block), samples, number++)
            : _frame(block, samples, number++, rate, channels, bits, inWidth),
      );
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

  static int rateCode(int rate) {
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
      ..addByte(((samples == blockSize ? 12 : 7) << 4) | rateCode(rate))
      ..addByte(((channels - 1) << 4) | ((bits == 16 ? 4 : 6) << 1))
      ..add(utf8Number(number));
    if (samples != blockSize) {
      head
        ..addByte((samples - 1) >> 8)
        ..addByte((samples - 1) & 0xFF);
    }
    switch (rateCode(rate)) {
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
    final headCrc = crc8(frame, 0, o);
    frame[o++] = headCrc;
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
    final crc = crc16(frame, 0, o);
    frame[o++] = crc >> 8;
    frame[o] = crc & 0xFF;
    return frame;
  }

  /// FLAC's UTF-8-style coding of the frame number (up to 36 bits).
  static List<int> utf8Number(int n) {
    if (n < 0x80) return [n];
    var extra = 1;
    while (n >= (1 << (5 * extra + 6))) {
      extra++;
    }
    final lead = (0xFF00 >> (extra + 1)) & 0xFF;
    return [lead | (n >> (6 * extra)), for (var i = extra - 1; i >= 0; i--) 0x80 | ((n >> (6 * i)) & 0x3F)];
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

  static int crc8(Uint8List d, int from, int to) {
    var c = 0;
    for (var i = from; i < to; i++) {
      c = _crc8Table[c ^ d[i]];
    }
    return c;
  }

  static int crc16(Uint8List d, int from, int to) {
    var c = 0;
    for (var i = from; i < to; i++) {
      c = ((c << 8) & 0xFFFF) ^ _crc16Table[(c >> 8) ^ d[i]];
    }
    return c;
  }
}

/// Bits, most significant first, into a fixed buffer.
final class _Bits {
  _Bits(int capacity) : buf = Uint8List(capacity);
  final Uint8List buf;
  int pos = 0;
  int _acc = 0;
  int _n = 0;

  void reset() {
    pos = 0;
    _acc = 0;
    _n = 0;
  }

  /// The low [count] (0 to 32) bits of [v].
  void write(int v, int count) {
    if (count == 0) return;
    _acc = (_acc << count) | (v & ((1 << count) - 1));
    _n += count;
    while (_n >= 8) {
      _n -= 8;
      buf[pos++] = (_acc >> _n) & 0xFF;
    }
    _acc &= (1 << _n) - 1;
  }

  void align() {
    if (_n > 0) write(0, 8 - _n);
  }
}

/// The compressing frame builder; owns the scratch buffers so a frame allocates only its output.
final class _Encoder {
  _Encoder(this.rate, this.channels, this.bits)
    : _bits = _Bits(channels * (FlacStream.blockSize * 4 + 16) + 64),
      _raw = [for (var c = 0; c < channels; c++) Int32List(FlacStream.blockSize)],
      _mid = Int32List(FlacStream.blockSize),
      _side = Int32List(FlacStream.blockSize),
      _res = Int32List(FlacStream.blockSize),
      _tree = Int64List(1 << 10);

  final int rate;
  final int channels;
  final int bits;
  final _Bits _bits;
  final List<Int32List> _raw;
  final Int32List _mid;
  final Int32List _side;
  final Int32List _res;
  final Int64List _tree; // partition sums, level p at [1 << p, 2 << p)
  // Per analysed signal: best FIXED order, or -1 for verbatim only, -2 for constant.
  final _order = List<int>.filled(4, -1);

  static const _maxPartitionOrder = 8;

  Uint8List frame(ByteData pcm, int n, int number) {
    final inWidth = bits == 16 ? 2 : 4;
    final stride = channels * inWidth;
    for (var c = 0; c < channels; c++) {
      final x = _raw[c];
      var i = c * inWidth;
      if (bits == 16) {
        for (var s = 0; s < n; s++, i += stride) {
          x[s] = pcm.getInt16(i, Endian.little);
        }
      } else {
        for (var s = 0; s < n; s++, i += stride) {
          x[s] = pcm.getInt32(i, Endian.little) >> 8;
        }
      }
    }

    // Which signals each channel carries, and the channel assignment code.
    var assign = channels - 1;
    var a = _raw[0];
    var b = channels > 1 ? _raw[1] : _raw[0];
    var aBits = bits;
    var bBits = bits;
    final est = List<double>.filled(4, 0);
    if (channels == 2) {
      final l = _raw[0], r = _raw[1];
      for (var s = 0; s < n; s++) {
        _mid[s] = (l[s] + r[s]) >> 1;
        _side[s] = l[s] - r[s];
      }
      est[0] = _analyze(l, n, 0);
      est[1] = _analyze(r, n, 1);
      est[2] = _analyze(_mid, n, 2);
      est[3] = _analyze(_side, n, 3);
      var best = est[0] + est[1];
      if (est[0] + est[3] < best) {
        best = est[0] + est[3];
        assign = 8;
      }
      if (est[1] + est[3] < best) {
        best = est[1] + est[3];
        assign = 9;
      }
      if (est[2] + est[3] < best) assign = 10;
      switch (assign) {
        case 8:
          b = _side;
          bBits = bits + 1;
          _order[1] = _order[3];
        case 9:
          a = _side;
          aBits = bits + 1;
          _order[0] = _order[3];
        case 10:
          a = _mid;
          b = _side;
          bBits = bits + 1;
          _order[0] = _order[2];
          _order[1] = _order[3];
      }
    }

    final w = _bits..reset();
    w
      ..write(0xFFF8, 16)
      ..write(n == FlacStream.blockSize ? 12 : 7, 4)
      ..write(FlacStream.rateCode(rate), 4)
      ..write(assign, 4)
      ..write(bits == 16 ? 4 : 6, 3)
      ..write(0, 1);
    for (final byte in FlacStream.utf8Number(number)) {
      w.write(byte, 8);
    }
    if (n != FlacStream.blockSize) w.write(n - 1, 16);
    switch (FlacStream.rateCode(rate)) {
      case 12:
        w.write(rate ~/ 1000, 8);
      case 13:
        w.write(rate, 16);
      case 14:
        w.write(rate ~/ 10, 16);
    }
    w.write(FlacStream.crc8(w.buf, 0, w.pos), 8);

    if (channels == 2) {
      _subframe(a, n, aBits, _order[0]);
      _subframe(b, n, bBits, _order[1]);
    } else {
      for (var c = 0; c < channels; c++) {
        _analyze(_raw[c], n, 0);
        _subframe(_raw[c], n, bits, _order[0]);
      }
    }
    w.align();
    w.write(FlacStream.crc16(w.buf, 0, w.pos), 16);
    return Uint8List.fromList(Uint8List.sublistView(w.buf, 0, w.pos));
  }

  /// Picks the FIXED order for [x] into `_order[slot]` and returns a rough size in bits, for comparing choices.
  double _analyze(Int32List x, int n, int slot) {
    if (n < 5) {
      _order[slot] = x[0] == x[n - 1] && _allEqual(x, n) ? -2 : -1;
      return n * 32.0;
    }
    var a = x[3], b = x[2], c = x[1], d = x[0];
    var s0 = 0, s1 = 0, s2 = 0, s3 = 0, s4 = 0;
    for (var i = 4; i < n; i++) {
      final v = x[i];
      final e1 = v - a;
      final e2 = e1 - (a - b);
      final e3 = e2 - (a - b - (b - c));
      final e4 = e3 - (a - b - (b - c) - (b - c - (c - d)));
      s0 += v < 0 ? -v : v;
      s1 += e1 < 0 ? -e1 : e1;
      s2 += e2 < 0 ? -e2 : e2;
      s3 += e3 < 0 ? -e3 : e3;
      s4 += e4 < 0 ? -e4 : e4;
      d = c;
      c = b;
      b = a;
      a = v;
    }
    if (s1 == 0 && _allEqual(x, n)) {
      _order[slot] = -2;
      return 8.0 + bits;
    }
    var order = 0, m = s0;
    if (s1 < m) (order, m) = (1, s1);
    if (s2 < m) (order, m) = (2, s2);
    if (s3 < m) (order, m) = (3, s3);
    if (s4 < m) (order, m) = (4, s4);
    _order[slot] = order;
    final mean = m / (n - 4);
    return n * (math.log(mean + 1) * 1.4426950408889634 + 1.5);
  }

  static bool _allEqual(Int32List x, int n) {
    final v = x[0];
    for (var i = 1; i < n; i++) {
      if (x[i] != v) return false;
    }
    return true;
  }

  /// One subframe of [x] ([bps] bits a sample) with FIXED [order] (-1: only VERBATIM, -2: CONSTANT).
  void _subframe(Int32List x, int n, int bps, int order) {
    final w = _bits;
    if (order == -2) {
      w
        ..write(0, 8)
        ..write(x[0], bps);
      return;
    }
    final verbatimBits = 8 + n * bps;
    if (order >= 0) {
      _residual(x, n, order);
      final plan = _plan(n, order);
      final riceBits = 8 + order * bps + plan.bits;
      if (riceBits < verbatimBits) {
        w.write((8 + order) << 1, 8);
        for (var i = 0; i < order; i++) {
          w.write(x[i], bps);
        }
        _writeRice(n, order, plan);
        return;
      }
    }
    w.write(0x02, 8);
    for (var i = 0; i < n; i++) {
      w.write(x[i], bps);
    }
  }

  void _residual(Int32List x, int n, int order) {
    final r = _res;
    switch (order) {
      case 0:
        for (var i = 0; i < n; i++) {
          r[i] = x[i];
        }
      case 1:
        for (var i = 1; i < n; i++) {
          r[i] = x[i] - x[i - 1];
        }
      case 2:
        for (var i = 2; i < n; i++) {
          r[i] = x[i] - 2 * x[i - 1] + x[i - 2];
        }
      case 3:
        for (var i = 3; i < n; i++) {
          r[i] = x[i] - 3 * x[i - 1] + 3 * x[i - 2] - x[i - 3];
        }
      default:
        for (var i = 4; i < n; i++) {
          r[i] = x[i] - 4 * x[i - 1] + 6 * x[i - 2] - 4 * x[i - 3] + x[i - 4];
        }
    }
  }

  /// The Rice parameter for a partition of [count] residuals whose zigzag values add up to [sum].
  static int _bestK(int sum, int count, int cap) {
    final mean = sum ~/ count;
    final k0 = mean <= 0 ? 0 : mean.bitLength - 1;
    var bestK = 0, best = -1;
    for (var k = math.max(0, k0 - 1); k <= math.min(cap, k0 + 1); k++) {
      final cost = count * (k + 1) + (sum >> k);
      if (best < 0 || cost < best) (bestK, best) = (k, cost);
    }
    return bestK;
  }

  int _levelBits(int p, int n, int order, int cap, int paramBits) {
    var total = 0;
    final parts = 1 << p;
    final size = n >> p;
    for (var j = 0; j < parts; j++) {
      final count = j == 0 ? size - order : size;
      final sum = _tree[parts + j];
      final k = _bestK(sum, count, cap);
      total += paramBits + count * (k + 1) + (sum >> k);
    }
    return total;
  }

  ({int bits, int p, bool wide}) _plan(int n, int order) {
    var pmax = 0;
    while (pmax < _maxPartitionOrder && n % (2 << pmax) == 0 && (n >> (pmax + 1)) > order) {
      pmax++;
    }
    final top = 1 << pmax;
    final size = n >> pmax;
    for (var j = 0; j < top; j++) {
      final from = j == 0 ? order : j * size;
      var sum = 0;
      for (var i = from; i < (j + 1) * size; i++) {
        final r = _res[i];
        sum += r >= 0 ? r << 1 : (-r << 1) - 1;
      }
      _tree[top + j] = sum;
    }
    for (var p = pmax - 1; p >= 0; p--) {
      for (var j = 0; j < (1 << p); j++) {
        _tree[(1 << p) + j] = _tree[(2 << p) + 2 * j] + _tree[(2 << p) + 2 * j + 1];
      }
    }
    var bestP = 0, best = -1;
    for (var p = 0; p <= pmax; p++) {
      final cost = _levelBits(p, n, order, 14, 4);
      if (best < 0 || cost < best) (bestP, best) = (p, cost);
    }
    final wide = _levelBits(bestP, n, order, 30, 5);
    if (wide < best) return (bits: 2 + 4 + wide, p: bestP, wide: true);
    return (bits: 2 + 4 + best, p: bestP, wide: false);
  }

  void _writeRice(int n, int order, ({int bits, int p, bool wide}) plan) {
    final w = _bits;
    final p = plan.p;
    final cap = plan.wide ? 30 : 14;
    w
      ..write(plan.wide ? 1 : 0, 2)
      ..write(p, 4);
    final parts = 1 << p;
    final size = n >> p;
    for (var j = 0; j < parts; j++) {
      final count = j == 0 ? size - order : size;
      final k = _bestK(_tree[parts + j], count, cap);
      w.write(k, plan.wide ? 5 : 4);
      final mask = (1 << k) - 1;
      for (var i = j == 0 ? order : j * size; i < (j + 1) * size; i++) {
        final r = _res[i];
        final u = r >= 0 ? r << 1 : (-r << 1) - 1;
        var q = u >> k;
        while (q + 1 + k > 32) {
          // A long unary run: zeros in chunks, then the stop bit and the remainder.
          final z = math.min(q, 24);
          w.write(0, z);
          q -= z;
        }
        w.write(((1 << k) | (u & mask)), q + 1 + k);
      }
    }
  }
}
