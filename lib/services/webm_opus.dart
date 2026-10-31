import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../platform/background.dart';

/// The WebM file could not be turned into Ogg Opus (not Opus, lacing, damaged, cut off).
class WebmOpusException implements Exception {
  const WebmOpusException(this.reason);

  final String reason;

  @override
  String toString() => 'WebmOpusException: $reason';
}

/// Moves YouTube's Opus out of its WebM (Matroska) box into an Ogg file (`.opus`), which every player and tagger
/// understands. The Opus packets are copied byte for byte: nothing is decoded or encoded, so there is no loss.
///
/// Limits: one Opus audio track is taken (the first); files with several tracks keep only that one. Laced blocks
/// (several packets in one block; YouTube never makes them) and encrypted or compressed tracks are turned down.
/// A file cut off in the middle gives the packets before the cut. Ogg pages hold whole packets only (an Opus packet
/// is at most 1275 bytes), and the stream's gaps in time, if any, are not kept: packets are played back to back.
abstract final class WebmOpus {
  /// Reads [source] and writes the Ogg Opus file at [target] (replaced). The work runs off the calling isolate.
  static Future<void> remuxFile(String source, String target, {String vendor = 'Riflay'}) =>
      inBackground(() => remuxFileSync(source, target, vendor: vendor));

  /// [remuxFile], on the calling isolate.
  static void remuxFileSync(String source, String target, {String vendor = 'Riflay'}) {
    final ogg = remux(File(source).readAsBytesSync(), vendor: vendor);
    File(target).writeAsBytesSync(ogg, flush: true);
  }

  /// The Ogg Opus file made of [webm]. [vendor] goes in the empty OpusTags page.
  static Uint8List remux(Uint8List webm, {String vendor = 'Riflay', int serial = 0x52666c79}) {
    final m = _Matroska.parse(webm);
    final head = m.opusHead;
    if (head == null || head.length < 19 || ascii.decode(head.sublist(0, 8), allowInvalid: true) != 'OpusHead') {
      throw const WebmOpusException('no OpusHead in the track');
    }
    if (m.packets.isEmpty) throw const WebmOpusException('no audio in the file');
    final out = BytesBuilder(copy: false);
    var sequence = 0;
    out.add(_page(serial, sequence++, flags: 2, granule: 0, packets: [head]));
    final v = utf8.encode(vendor);
    final tags = BytesBuilder(copy: false)
      ..add(ascii.encode('OpusTags'))
      ..add(_le32(v.length))
      ..add(v)
      ..add(_le32(0));
    out.add(_page(serial, sequence++, flags: 0, granule: 0, packets: [tags.takeBytes()]));

    // Granule = 48 kHz samples decoded so far, pre-skip included (RFC 7845); a DiscardPadding on the last block
    // (ns of its end that are padding) trims the final count.
    var total = 0;
    var page = <Uint8List>[];
    var segments = 0, bytes = 0;
    void flush({required bool last}) {
      var granule = total;
      if (last && m.discardPaddingNs > 0) {
        granule = (total - (m.discardPaddingNs * 48 / 1000000).round()).clamp(0, total);
      }
      out.add(_page(serial, sequence++, flags: last ? 4 : 0, granule: granule, packets: page));
      page = [];
      segments = 0;
      bytes = 0;
    }

    for (var i = 0; i < m.packets.length; i++) {
      final p = m.packets[i];
      final lacing = p.length ~/ 255 + 1;
      if (page.isNotEmpty && (segments + lacing > 255 || bytes + p.length > 4000)) flush(last: false);
      page.add(p);
      segments += lacing;
      bytes += p.length;
      total += _packetSamples(p);
    }
    flush(last: true);
    return out.takeBytes();
  }

  /// Samples (at 48 kHz) an Opus packet decodes to, from its TOC byte (RFC 6716, section 3.1).
  static int _packetSamples(Uint8List p) {
    if (p.isEmpty) return 0;
    final toc = p[0];
    final config = toc >> 3;
    final int frame;
    if (config < 12) {
      frame = const [480, 960, 1920, 2880][config & 3]; // SILK: 10, 20, 40, 60 ms
    } else if (config < 16) {
      frame = (config & 1) == 0 ? 480 : 960; // hybrid: 10, 20 ms
    } else {
      frame = const [120, 240, 480, 960][config & 3]; // CELT: 2.5, 5, 10, 20 ms
    }
    final code = toc & 3;
    final frames = switch (code) {
      0 => 1,
      1 || 2 => 2,
      _ => p.length > 1 ? p[1] & 0x3f : 0,
    };
    return frame * frames;
  }

  static final _crcTable = List<int>.generate(256, (i) {
    var r = i << 24;
    for (var j = 0; j < 8; j++) {
      r = r & 0x80000000 != 0 ? (r << 1) ^ 0x04c11db7 : r << 1;
    }
    return r & 0xffffffff;
  });

  /// The Ogg page checksum of [page] (its CRC field zeroed).
  static int oggCrc(Uint8List page) {
    var crc = 0;
    for (final b in page) {
      crc = ((crc << 8) & 0xffffffff) ^ _crcTable[(crc >> 24) ^ b];
    }
    return crc;
  }

  static Uint8List _le32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);

  /// One Ogg page of whole [packets] (at most 255 lacing segments in all).
  static Uint8List _page(
    int serial,
    int sequence, {
    required int flags,
    required int granule,
    required List<Uint8List> packets,
  }) {
    final lacing = <int>[];
    for (final p in packets) {
      var left = p.length;
      while (left >= 255) {
        lacing.add(255);
        left -= 255;
      }
      lacing.add(left);
    }
    if (lacing.length > 255) throw const WebmOpusException('too many segments for one Ogg page');
    final b = BytesBuilder(copy: false)
      ..add(ascii.encode('OggS'))
      ..addByte(0)
      ..addByte(flags);
    final g = ByteData(8)..setUint64(0, granule, Endian.little);
    b
      ..add(g.buffer.asUint8List())
      ..add(_le32(serial))
      ..add(_le32(sequence))
      ..add(Uint8List(4))
      ..addByte(lacing.length)
      ..add(lacing);
    for (final p in packets) {
      b.add(p);
    }
    final bytes = b.takeBytes();
    bytes.buffer.asByteData().setUint32(22, oggCrc(bytes), Endian.little);
    return bytes;
  }
}

/// What the remuxer needs from a Matroska file: the Opus track's header and its packets in order.
class _Matroska {
  _Matroska._(this.opusHead, this.packets, this.discardPaddingNs);

  final Uint8List? opusHead;
  final List<Uint8List> packets;
  final int discardPaddingNs;

  // Elements that hold others: walked into, not skipped. Everything else is skipped by its size, so a Segment or
  // Cluster of unknown size (a live stream) needs no special case.
  static const _segment = 0x18538067,
      _tracks = 0x1654AE6B,
      _trackEntry = 0xAE,
      _cluster = 0x1F43B675,
      _blockGroup = 0xA0;
  static const _trackNumber = 0xD7, _codecId = 0x86, _codecPrivate = 0x63A2;
  static const _simpleBlock = 0xA3, _block = 0xA1, _discardPadding = 0x75A2;

  static _Matroska parse(Uint8List d) {
    var pos = 0;
    // The EBML header comes first; it is skipped like any element.
    int? trackNumber; // of the Opus track
    Uint8List? head;
    // The track being described.
    int? entryNumber;
    String? entryCodec;
    Uint8List? entryPrivate;
    void closeEntry() {
      if (entryCodec == 'A_OPUS' && trackNumber == null && entryNumber != null) {
        trackNumber = entryNumber;
        head = entryPrivate;
      }
      entryNumber = null;
      entryCodec = null;
      entryPrivate = null;
    }

    final packets = <Uint8List>[];
    var discard = 0;
    var sawEbml = false;

    while (pos < d.length) {
      final id = _readId(d, pos);
      if (id == null) break;
      pos += id.length;
      final size = _readSize(d, pos);
      if (size == null) break;
      pos += size.length;
      final key = id.value;
      if (!sawEbml) {
        if (key != 0x1A45DFA3) throw const WebmOpusException('not a WebM file');
        sawEbml = true;
      }
      if (key == _trackEntry) closeEntry();
      if (key == _segment || key == _tracks || key == _trackEntry || key == _cluster || key == _blockGroup) {
        if (key == _cluster || key == _blockGroup) closeEntry();
        continue;
      }
      final unknown = size.value < 0;
      if (unknown) break; // an unknown-size element that is not a container cannot be walked
      final end = pos + size.value;
      if (end > d.length) {
        // Cut off: nothing partial is kept.
        break;
      }
      switch (key) {
        case _trackNumber:
          entryNumber = _uint(d, pos, end);
        case _codecId:
          entryCodec = ascii.decode(d.sublist(pos, end), allowInvalid: true).replaceAll('\u0000', '');
        case _codecPrivate:
          entryPrivate = Uint8List.fromList(d.sublist(pos, end));
        case _simpleBlock || _block:
          closeEntry();
          if (trackNumber == null) break;
          final frame = _blockFrame(d, pos, end, trackNumber!);
          if (frame != null) packets.add(frame);
        case _discardPadding:
          // Signed, nanoseconds; only the one on the final block matters, which is the last one seen.
          discard = _int(d, pos, end);
      }
      pos = end;
    }
    closeEntry();
    return _Matroska._(head, packets, discard < 0 ? 0 : discard);
  }

  /// The one frame in a (Simple)Block of [track], or null when it belongs to another track.
  static Uint8List? _blockFrame(Uint8List d, int start, int end, int track) {
    final number = _readSize(d, start);
    if (number == null || number.value != track) return null;
    final flagsAt = start + number.length + 2;
    if (flagsAt >= end) throw const WebmOpusException('a damaged block');
    if (d[flagsAt] & 0x06 != 0) throw const WebmOpusException('laced blocks are not supported');
    return Uint8List.fromList(d.sublist(flagsAt + 1, end));
  }

  static int _uint(Uint8List d, int start, int end) {
    var v = 0;
    for (var i = start; i < end; i++) {
      v = (v << 8) | d[i];
    }
    return v;
  }

  static int _int(Uint8List d, int start, int end) {
    if (end <= start) return 0;
    var v = _uint(d, start, end);
    final bits = (end - start) * 8;
    if (bits < 64 && d[start] & 0x80 != 0) v -= 1 << bits;
    return v;
  }

  /// An element ID: its bytes, marker bits kept.
  static ({int value, int length})? _readId(Uint8List d, int pos) {
    if (pos >= d.length) return null;
    final first = d[pos];
    var length = 1;
    while (length <= 4 && first & (0x80 >> (length - 1)) == 0) {
      length++;
    }
    if (length > 4 || pos + length > d.length) return null;
    var v = 0;
    for (var i = 0; i < length; i++) {
      v = (v << 8) | d[pos + i];
    }
    return (value: v, length: length);
  }

  /// A size or track number: the marker bit removed; -1 when every value bit is set (unknown size).
  static ({int value, int length})? _readSize(Uint8List d, int pos) {
    if (pos >= d.length) return null;
    final first = d[pos];
    var length = 1;
    while (length <= 8 && first & (0x80 >> (length - 1)) == 0) {
      length++;
    }
    if (length > 8 || pos + length > d.length) return null;
    var v = first & ((0x80 >> (length - 1)) - 1);
    var allOnes = v == (0x80 >> (length - 1)) - 1;
    for (var i = 1; i < length; i++) {
      v = (v << 8) | d[pos + i];
      if (d[pos + i] != 0xff) allOnes = false;
    }
    return (value: allOnes ? -1 : v, length: length);
  }
}
