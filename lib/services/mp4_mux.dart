import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'webm_mux.dart' show MuxException, MuxTags;

/// Puts the video of one fragmented MP4 and the audio of another into a single MP4, without decoding or encoding
/// anything. YouTube serves its H.264 video and AAC audio this way (DASH: a `moov` with no samples, then a
/// `moof` + `mdat` pair per few seconds). This is what phones, which have no ffmpeg, use.
///
/// The output is a fragmented MP4 too: an `ftyp`, one `moov` that holds both tracks (video is track 1, audio
/// track 2) with the whole length in it, the song's tags and cover (`udta` › `meta` › `ilst`), and then every
/// fragment of both streams in time order. Fragment offsets are relative to their own `moof`, so the fragments
/// are copied unchanged but for their track number and sequence number. Players see a length and seek through
/// the fragments themselves.
///
/// Limits: each file must be a fragmented MP4 whose fragments use `default-base-is-moof` addressing (YouTube's
/// always do); one video track is taken from the first file and one audio track from the second.
abstract final class Mp4Mux {
  /// Writes [out] from [video] and [audio]; the work runs off the calling isolate.
  static Future<void> muxFile({required String video, required String audio, required String out, MuxTags? tags}) =>
      Isolate.run(() => muxFileSync(video: video, audio: audio, out: out, tags: tags));

  /// [muxFile] on the calling isolate.
  static void muxFileSync({required String video, required String audio, required String out, MuxTags? tags}) {
    final v = _Fmp4.open(video, 'vide'), a = _Fmp4.open(audio, 'soun');
    RandomAccessFile? file;
    try {
      file = File(out).openSync(mode: FileMode.write);
      _write(file, v, a, tags);
      file.flushSync();
    } finally {
      v.close();
      a.close();
      file?.closeSync();
    }
  }

  /// Whether the file at [path] is a fragmented MP4 this muxer can read.
  static bool canRead(String path) {
    try {
      _Fmp4.open(path, null).close();
      return true;
    } catch (_) {
      return false;
    }
  }

  static const _movieScale = 1000;

  static void _write(RandomAccessFile f, _Fmp4 v, _Fmp4 a, MuxTags? tags) {
    // The length of the movie, from where the last fragment of either stream ends.
    final endSeconds = [v.endSeconds, a.endSeconds].reduce((x, y) => x > y ? x : y);
    final movieMs = (endSeconds * _movieScale).ceil();

    f.writeFromSync(
      _box('ftyp', [_ascii('isom'), _u32(512), _ascii('isom'), _ascii('iso6'), _ascii('mp41'), _ascii('avc1')]),
    );

    final mvhd = BytesBuilder()
      ..add(_u32(0)) // version, flags
      ..add(_u32(0))
      ..add(_u32(0))
      ..add(_u32(_movieScale))
      ..add(_u32(movieMs))
      ..add(_u32(0x00010000)) // rate
      ..add(Uint8List.fromList([1, 0])) // volume
      ..add(Uint8List(10))
      ..add([
        for (final m in [0x10000, 0, 0, 0, 0x10000, 0, 0, 0, 0x40000000]) ..._u32(m),
      ])
      ..add(Uint8List(24))
      ..add(_u32(3)); // next track id

    final vt = v.patchedTrak(1, movieMs), at = a.patchedTrak(2, movieMs);
    final moov = <Uint8List>[
      _box('mvhd', [mvhd.takeBytes()]),
      vt,
      at,
      _box('mvex', [
        _box('mehd', [_u32(0), _u32(movieMs)]),
        v.patchedTrex(1),
        a.patchedTrex(2),
      ]),
      if (tags != null && !tags.isEmpty) _udta(tags),
    ];
    f.writeFromSync(_box('moov', moov));

    // Fragments of both streams in time order, numbered as one.
    var vi = 0, ai = 0, sequence = 1;
    while (vi < v.fragments.length || ai < a.fragments.length) {
      final takeVideo =
          vi < v.fragments.length &&
          (ai >= a.fragments.length ||
              v.fragments[vi].startSeconds(v.timescale) <= a.fragments[ai].startSeconds(a.timescale));
      final (src, frag, track) = takeVideo ? (v, v.fragments[vi++], 1) : (a, a.fragments[ai++], 2);
      src.copyFragment(f, frag, track, sequence++);
    }
  }

  // ---- tags ----

  static Uint8List _udta(MuxTags t) {
    Uint8List item(List<int> name, int type, List<int> data) => _box(String.fromCharCodes(name), [
      _box('data', [_u32(type), _u32(0), Uint8List.fromList(data)]),
    ]);
    Uint8List text(List<int> name, String s) => item(name, 1, utf8.encode(s));
    final ilst = _box('ilst', [
      if (t.title != null) text(const [0xA9, 0x6e, 0x61, 0x6d], t.title!),
      if (t.artist != null) text(const [0xA9, 0x41, 0x52, 0x54], t.artist!),
      if (t.album != null) text(const [0xA9, 0x61, 0x6c, 0x62], t.album!),
      if (t.year != null) text(const [0xA9, 0x64, 0x61, 0x79], '${t.year}'),
      if (t.comment != null) text(const [0xA9, 0x63, 0x6d, 0x74], t.comment!),
      if (t.cover != null) item(ascii.encode('covr'), t.coverMime == 'image/png' ? 14 : 13, t.cover!),
    ]);
    final hdlr = _box('hdlr', [_u32(0), _u32(0), _ascii('mdir'), _ascii('appl'), Uint8List(9)]);
    return _box('udta', [
      _box('meta', [_u32(0), hdlr, ilst]),
    ]);
  }

  // ---- box pieces ----

  static Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);

  static Uint8List _ascii(String s) => Uint8List.fromList(ascii.encode(s));

  /// A box whose type may hold Latin-1 characters (the iTunes names start with 0xA9).
  static Uint8List _box(String type, List<Uint8List> children) {
    var size = 8;
    for (final c in children) {
      size += c.length;
    }
    final out = Uint8List(size);
    out.buffer.asByteData().setUint32(0, size);
    for (var i = 0; i < 4; i++) {
      out[4 + i] = type.codeUnitAt(i);
    }
    var at = 8;
    for (final c in children) {
      out.setRange(at, at + c.length, c);
      at += c.length;
    }
    return out;
  }
}

/// A box found in a buffer: [start] is the box's first byte, [payload] where its content starts.
class _Box {
  _Box(this.type, this.start, this.payload, this.end);

  final String type;
  final int start;
  final int payload;
  final int end;
}

List<_Box> _boxesIn(Uint8List d, int start, int end) {
  final out = <_Box>[];
  var pos = start;
  while (pos + 8 <= end) {
    final bd = ByteData.sublistView(d);
    var size = bd.getUint32(pos);
    var head = 8;
    if (size == 1) {
      if (pos + 16 > end) break;
      size = bd.getUint64(pos + 8);
      head = 16;
    } else if (size == 0) {
      size = end - pos;
    }
    if (size < head || pos + size > end) break;
    out.add(_Box(String.fromCharCodes(d.sublist(pos + 4, pos + 8)), pos, pos + head, pos + size));
    pos += size;
  }
  return out;
}

_Box? _child(Uint8List d, _Box parent, String type) {
  for (final b in _boxesIn(d, parent.payload, parent.end)) {
    if (b.type == type) return b;
  }
  return null;
}

/// One `moof` + `mdat` pair of a source file.
class _Fragment {
  _Fragment(this.offset, this.length, this.moofLength, this.start, this.duration);

  final int offset;
  final int length;
  final int moofLength;

  /// Where it starts and how long it is, in the track's timescale.
  final int start;
  final int duration;

  double startSeconds(int timescale) => start / timescale;
}

/// A fragmented MP4 being read: its moov up front, its fragments indexed, their bytes read when copied.
class _Fmp4 {
  _Fmp4._(this._f, this.length, this._handler);

  factory _Fmp4.open(String path, String? handler) {
    final f = File(path).openSync();
    final s = _Fmp4._(f, f.lengthSync(), handler);
    try {
      s._index();
    } catch (_) {
      f.closeSync();
      rethrow;
    }
    return s;
  }

  final RandomAccessFile _f;
  final int length;
  final String? _handler;

  late Uint8List _moov;
  late _Box _trak;
  late int trackId;
  late int timescale;
  late int _defaultDuration;
  final fragments = <_Fragment>[];

  void close() => _f.closeSync();

  double get endSeconds {
    if (fragments.isEmpty) return 0;
    final last = fragments.last;
    return (last.start + last.duration) / timescale;
  }

  Uint8List _read(int pos, int n) {
    _f.setPositionSync(pos);
    final b = _f.readSync(n);
    if (b.length != n) throw const MuxException('the file is cut off');
    return b;
  }

  /// A box header at [pos]: its type, size and header length; null at the end.
  (String, int, int)? _head(int pos) {
    if (pos + 8 > length) return null;
    final b = _read(pos, 16 > length - pos ? length - pos : 16);
    final bd = ByteData.sublistView(b);
    var size = bd.getUint32(0);
    var head = 8;
    if (size == 1) {
      if (b.length < 16) return null;
      size = bd.getUint64(8);
      head = 16;
    } else if (size == 0) {
      size = length - pos;
    }
    if (size < head) return null;
    return (String.fromCharCodes(b.sublist(4, 8)), size, head);
  }

  void _index() {
    var pos = 0;
    var running = 0;
    var sawMoov = false;
    int? moofAt;
    while (true) {
      final h = _head(pos);
      if (h == null) break;
      final (type, size, _) = h;
      if (pos + size > length) break; // cut off: whole fragments only
      if (type == 'moov') {
        _moov = _read(pos, size);
        _readMoov();
        sawMoov = true;
      } else if (type == 'moof') {
        moofAt = pos;
      } else if (type == 'mdat' && moofAt != null) {
        if (!sawMoov) throw const MuxException('a fragment before the moov');
        final moofLength = pos - moofAt;
        final info = _readMoof(_read(moofAt, moofLength), running);
        fragments.add(_Fragment(moofAt, pos + size - moofAt, moofLength, info.start, info.duration));
        running = info.start + info.duration;
        moofAt = null;
      }
      pos += size;
    }
    if (!sawMoov) throw const MuxException('no moov box');
    if (fragments.isEmpty) throw const MuxException('no fragments (not a fragmented MP4)');
  }

  void _readMoov() {
    final moov = _boxesIn(_moov, 0, _moov.length).firstOrNull;
    if (moov == null || moov.type != 'moov') throw const MuxException('no moov box');
    final inner = _Box('moov', 0, 8, _moov.length);
    final bd = ByteData.sublistView(_moov);
    for (final trak in _boxesIn(_moov, inner.payload, inner.end).where((b) => b.type == 'trak')) {
      final mdia = _child(_moov, trak, 'mdia');
      final hdlr = mdia == null ? null : _child(_moov, mdia, 'hdlr');
      if (mdia == null || hdlr == null) continue;
      final kind = String.fromCharCodes(_moov.sublist(hdlr.payload + 8, hdlr.payload + 12));
      if (_handler != null && kind != _handler) continue;
      final tkhd = _child(_moov, trak, 'tkhd'), mdhd = _child(_moov, mdia, 'mdhd');
      if (tkhd == null || mdhd == null) continue;
      _trak = trak;
      trackId = bd.getUint32(tkhd.payload + (_moov[tkhd.payload] == 1 ? 20 : 12));
      timescale = bd.getUint32(mdhd.payload + (_moov[mdhd.payload] == 1 ? 20 : 12));
      final mvex = _child(_moov, inner, 'mvex');
      if (mvex == null) throw const MuxException('not a fragmented MP4 (no mvex)');
      _trex = null;
      for (final t in _boxesIn(_moov, mvex.payload, mvex.end).where((b) => b.type == 'trex')) {
        if (bd.getUint32(t.payload + 4) == trackId) _trex = t;
      }
      _defaultDuration = _trex == null ? 0 : bd.getUint32(_trex!.payload + 12);
      return;
    }
    throw MuxException('no ${_handler == 'vide' ? 'video' : 'audio'} track');
  }

  _Box? _trex;

  /// The start and length (in the track's timescale) of the fragment whose `moof` is [moof]; checks that it is
  /// addressed the way the muxer copies it.
  ({int start, int duration}) _readMoof(Uint8List moof, int running) {
    final bd = ByteData.sublistView(moof);
    final top = _Box('moof', 0, 8, moof.length);
    final traf = _child(moof, top, 'traf');
    final tfhd = traf == null ? null : _child(moof, traf, 'tfhd');
    if (traf == null || tfhd == null) throw const MuxException('a fragment without a track');
    final flags = bd.getUint32(tfhd.payload) & 0xffffff;
    if (flags & 0x1 != 0) throw const MuxException('fragments with their own base offset');
    var at = tfhd.payload + 8;
    if (flags & 0x2 != 0) at += 4;
    final defaultDuration = flags & 0x8 != 0 ? bd.getUint32(at) : _defaultDuration;
    var start = running;
    final tfdt = _child(moof, traf, 'tfdt');
    if (tfdt != null) {
      start = moof[tfdt.payload] == 1 ? bd.getUint64(tfdt.payload + 4) : bd.getUint32(tfdt.payload + 4);
    }
    var total = 0;
    for (final trun in _boxesIn(moof, traf.payload, traf.end).where((b) => b.type == 'trun')) {
      final tf = bd.getUint32(trun.payload) & 0xffffff;
      final count = bd.getUint32(trun.payload + 4);
      var p = trun.payload + 8;
      if (tf & 0x1 != 0) p += 4;
      if (tf & 0x4 != 0) p += 4;
      final each =
          (tf & 0x100 != 0 ? 4 : 0) + (tf & 0x200 != 0 ? 4 : 0) + (tf & 0x400 != 0 ? 4 : 0) + (tf & 0x800 != 0 ? 4 : 0);
      if (tf & 0x100 == 0) {
        total += defaultDuration * count;
      } else {
        for (var i = 0; i < count; i++) {
          total += bd.getUint32(p + i * each);
        }
      }
    }
    return (start: start, duration: total);
  }

  /// This stream's `trak`, as track [id], with its length in the movie header and media header.
  Uint8List patchedTrak(int id, int movieMs) {
    final t = Uint8List.fromList(_moov.sublist(_trak.start, _trak.end));
    final bd = ByteData.sublistView(t);
    final top = _Box('trak', 0, 8, t.length);
    final tkhd = _child(t, top, 'tkhd')!, mdia = _child(t, top, 'mdia')!, mdhd = _child(t, mdia, 'mdhd')!;
    final v1 = t[tkhd.payload] == 1;
    t[tkhd.payload + 1] = 0;
    t[tkhd.payload + 2] = 0;
    t[tkhd.payload + 3] = 3; // enabled, in the movie
    bd.setUint32(tkhd.payload + (v1 ? 20 : 12), id);
    if (v1) {
      bd.setUint64(tkhd.payload + 28, movieMs);
    } else {
      bd.setUint32(tkhd.payload + 20, movieMs);
    }
    final ticks = fragments.isEmpty ? 0 : fragments.last.start + fragments.last.duration;
    if (t[mdhd.payload] == 1) {
      bd.setUint64(mdhd.payload + 24, ticks);
    } else {
      bd.setUint32(mdhd.payload + 16, ticks);
    }
    return t;
  }

  /// This stream's `trex`, as track [id].
  Uint8List patchedTrex(int id) {
    final trex = _trex;
    if (trex == null) throw const MuxException('no trex for the track');
    final t = Uint8List.fromList(_moov.sublist(trex.start, trex.end));
    ByteData.sublistView(t).setUint32(trex.payload - trex.start + 4, id);
    return t;
  }

  /// Copies [fragment] to [out] as track [track], numbered [sequence].
  void copyFragment(RandomAccessFile out, _Fragment fragment, int track, int sequence) {
    final moof = _read(fragment.offset, fragment.moofLength);
    final bd = ByteData.sublistView(moof);
    final top = _Box('moof', 0, 8, moof.length);
    final mfhd = _child(moof, top, 'mfhd'), traf = _child(moof, top, 'traf');
    final tfhd = traf == null ? null : _child(moof, traf, 'tfhd');
    if (mfhd == null || tfhd == null) throw const MuxException('a damaged fragment');
    bd.setUint32(mfhd.payload + 4, sequence);
    bd.setUint32(tfhd.payload + 4, track);
    out.writeFromSync(moof);
    var left = fragment.length - fragment.moofLength;
    var at = fragment.offset + fragment.moofLength;
    while (left > 0) {
      final n = left > (1 << 20) ? 1 << 20 : left;
      out.writeFromSync(_read(at, n));
      at += n;
      left -= n;
    }
  }
}
