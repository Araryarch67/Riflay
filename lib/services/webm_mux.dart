import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../platform/background.dart';

/// What a muxed video file carries besides its picture and sound: the song's name, artist, album, year, a note and
/// the cover. Written into the file itself (WebM: Tags and an attachment; MP4: the `ilst` atoms).
class MuxTags {
  const MuxTags({
    this.title,
    this.artist,
    this.album,
    this.year,
    this.comment,
    this.cover,
    this.coverMime = 'image/jpeg',
  });

  final String? title;
  final String? artist;
  final String? album;
  final int? year;
  final String? comment;
  final Uint8List? cover;
  final String coverMime;

  bool get isEmpty =>
      title == null && artist == null && album == null && year == null && comment == null && cover == null;
}

/// Two streams could not be put into one file (not the container this muxer reads, damaged, cut off).
class MuxException implements Exception {
  const MuxException(this.reason);

  final String reason;

  @override
  String toString() => 'MuxException: $reason';
}

/// Puts the VP9 (or AV1) video of one WebM and the Opus audio of another into a single WebM, without decoding
/// or encoding anything: every block is copied as it is. This is what phones, which have no ffmpeg, use.
///
/// The output has a SeekHead, Info (with the duration), Tracks (video 1, audio 2), the tags and cover, Clusters
/// that follow the video's key frames with both streams interleaved by time, and Cues for the key frames, so
/// players show a length and seek.
///
/// Limits: the Segment's Info and Tracks must come before the first Cluster (as YouTube writes them), Clusters
/// must have a known size, and only the first video track of one file and the first audio track of the other are
/// used. Blocks keep their lacing and any BlockGroup extras (DiscardPadding on Opus' last block among them).
abstract final class WebmMux {
  /// Writes `[out]` from [video] and [audio]; the work runs off the calling isolate.
  static Future<void> muxFile({required String video, required String audio, required String out, MuxTags? tags}) =>
      inBackground(() => muxFileSync(video: video, audio: audio, out: out, tags: tags));

  /// [muxFile] on the calling isolate.
  static void muxFileSync({required String video, required String audio, required String out, MuxTags? tags}) {
    final v = _Source.open(video), a = _Source.open(audio);
    RandomAccessFile? file;
    try {
      final vt = v.firstTrack(1), at = a.firstTrack(2);
      if (vt == null) throw const MuxException('no video track in the video file');
      if (at == null) throw const MuxException('no audio track in the audio file');
      file = File(out).openSync(mode: FileMode.write);
      _write(file, v, vt, a, at, tags);
    } finally {
      v.close();
      a.close();
      file?.closeSync();
    }
  }

  /// Whether the WebM/Matroska file at [path] has a video track (an audio-only YouTube stream has none).
  static bool hasVideoTrack(String path) {
    _Source? s;
    try {
      s = _Source.open(path);
      return s.firstTrack(1) != null;
    } catch (_) {
      return false;
    } finally {
      s?.close();
    }
  }

  // ---- writing ----

  static const _segmentId = 0x18538067, _seekHeadId = 0x114D9B74, _infoId = 0x1549A966, _tracksId = 0x1654AE6B;
  static const _tagsId = 0x1254C367, _attachmentsId = 0x1941A469, _cuesId = 0x1C53BB6B, _clusterId = 0x1F43B675;

  static void _write(RandomAccessFile f, _Source v, _Track vt, _Source a, _Track at, MuxTags? tags) {
    f.writeFromSync(
      _el(0x1A45DFA3, [
        _uint(0x4286, 1),
        _uint(0x42F7, 1),
        _uint(0x42F2, 4),
        _uint(0x42F3, 8),
        _str(0x4282, 'webm'),
        _uint(0x4287, 4),
        _uint(0x4285, 2),
      ]),
    );
    // The Segment's size is only known at the end: an 8-byte size, patched then.
    f.writeFromSync(_idBytes(_segmentId));
    final segmentSizeAt = f.positionSync();
    f.writeFromSync(Uint8List.fromList([0x01, 0, 0, 0, 0, 0, 0, 0]));
    final base = f.positionSync();

    final hasTags = tags != null && !tags.isEmpty;
    final tagsEl = hasTags ? _tagsElement(tags) : null;
    final attach = tags?.cover != null ? _attachments(tags!) : null;
    final tracksEl = _el(_tracksId, [_trackEntry(vt, 1), _trackEntry(at, 2)]);

    Uint8List seekHead(int info, int tracksPos, int? tagsPos, int? attachPos, int cues) => _el(_seekHeadId, [
      _seek(_infoId, info),
      _seek(_tracksId, tracksPos),
      if (tagsPos != null) _seek(_tagsId, tagsPos),
      if (attachPos != null) _seek(_attachmentsId, attachPos),
      _seek(_cuesId, cues),
    ]);
    final seekLength = seekHead(0, 0, tagsEl == null ? null : 0, attach == null ? null : 0, 0).length;
    final seekAt = f.positionSync();
    f.writeFromSync(Uint8List(seekLength)); // patched below

    Uint8List info(double durationMs) => _el(_infoId, [
      _uint(0x2AD7B1, 1000000),
      _str(0x4D80, 'Riflay'),
      _str(0x5741, 'Riflay'),
      if (tags?.title != null) _str(0x7BA9, tags!.title!),
      _float64(0x4489, durationMs),
    ]);
    final infoAt = f.positionSync() - base;
    f.writeFromSync(info(0));
    final tracksAt = f.positionSync() - base;
    f.writeFromSync(tracksEl);
    int? tagsPos, attachPos;
    if (tagsEl != null) {
      tagsPos = f.positionSync() - base;
      f.writeFromSync(tagsEl);
    }
    if (attach != null) {
      attachPos = f.positionSync() - base;
      f.writeFromSync(attach);
    }

    // Both streams in time order; a Cluster starts at each video key frame (or when one grows long).
    final cues = <Uint8List>[];
    var lastMs = 0;
    var cluster = <_Block>[];
    var clusterHasVideo = false;
    void flush() {
      if (cluster.isEmpty) return;
      final start = cluster.first.ms;
      final body = BytesBuilder(copy: false)..add(_uint(0xE7, start));
      int? cueMs;
      for (final b in cluster) {
        body.add(b.encode(rel: b.ms - start));
        if (cueMs == null && b.isVideo && b.key) cueMs = b.ms;
      }
      final pos = f.positionSync() - base;
      f.writeFromSync(_el(_clusterId, [body.takeBytes()]));
      if (cueMs != null) {
        cues.add(
          _el(0xBB, [
            _uint(0xB3, cueMs),
            _el(0xB7, [_uint(0xF7, 1), _uint(0xF1, pos)]),
          ]),
        );
      }
      cluster = [];
      clusterHasVideo = false;
    }

    final vi = v.blocks(vt.number, 1).iterator, ai = a.blocks(at.number, 2).iterator;
    var vMore = vi.moveNext(), aMore = ai.moveNext();
    while (vMore || aMore) {
      final takeVideo = vMore && (!aMore || vi.current.ms <= ai.current.ms);
      final b = takeVideo ? vi.current : ai.current;
      if (takeVideo) {
        vMore = vi.moveNext();
      } else {
        aMore = ai.moveNext();
      }
      final longRun = cluster.isNotEmpty && b.ms - cluster.first.ms > 20000;
      if (longRun || (b.isVideo && b.key && clusterHasVideo)) flush();
      cluster.add(b);
      if (b.isVideo) clusterHasVideo = true;
      if (b.ms > lastMs) lastMs = b.ms;
    }
    flush();
    if (lastMs == 0 && cues.isEmpty) throw const MuxException('the files hold no frames');

    final cuesAt = f.positionSync() - base;
    f.writeFromSync(_el(_cuesId, cues));
    final end = f.positionSync();

    // The end is known: the real duration (a source's own figure when it is longer), the SeekHead, the size.
    final duration = [lastMs.toDouble(), v.durationMs ?? 0, a.durationMs ?? 0].reduce((x, y) => x > y ? x : y);
    f.setPositionSync(seekAt);
    f.writeFromSync(seekHead(infoAt, tracksAt, tagsPos, attachPos, cuesAt));
    f.setPositionSync(base + infoAt);
    f.writeFromSync(info(duration));
    f.setPositionSync(segmentSizeAt);
    final size = ByteData(8)..setUint64(0, end - base);
    final sizeBytes = size.buffer.asUint8List();
    sizeBytes[0] = 0x01;
    f.writeFromSync(sizeBytes);
    f.setPositionSync(end);
    f.flushSync();
  }

  static Uint8List _seek(int id, int position) =>
      _el(0x4DBB, [_bytes(0x53AB, _idBytes(id)), _uintFixed(0x53AC, position, 8)]);

  static Uint8List _trackEntry(_Track t, int number) => _el(0xAE, [
    for (final (id, data) in t.children)
      if (id == 0xD7 || id == 0x73C5) _uint(id, number) else _bytes(id, data),
  ]);

  static Uint8List _tagsElement(MuxTags t) {
    Uint8List simple(String name, String value) => _el(0x67C8, [_str(0x45A3, name), _str(0x4487, value)]);
    return _el(_tagsId, [
      _el(0x7373, [
        _el(0x63C0, []),
        if (t.title != null) simple('TITLE', t.title!),
        if (t.artist != null) simple('ARTIST', t.artist!),
        if (t.album != null) simple('ALBUM', t.album!),
        if (t.year != null) simple('DATE_RELEASED', '${t.year}'),
        if (t.comment != null) simple('COMMENT', t.comment!),
      ]),
    ]);
  }

  static Uint8List _attachments(MuxTags t) {
    final png = t.coverMime == 'image/png';
    return _el(_attachmentsId, [
      _el(0x61A7, [
        _str(0x466E, png ? 'cover.png' : 'cover.jpg'),
        _str(0x4660, t.coverMime),
        _bytes(0x465C, t.cover!),
        _uint(0x46AE, 0x52666c61),
      ]),
    ]);
  }

  // ---- EBML pieces ----

  static Uint8List _idBytes(int id) {
    final out = <int>[];
    for (var v = id; v > 0; v >>= 8) {
      out.insert(0, v & 0xff);
    }
    return Uint8List.fromList(out);
  }

  static Uint8List _sizeBytes(int size) {
    var length = 1;
    while (length < 8 && size >= (1 << (7 * length)) - 1) {
      length++;
    }
    final out = Uint8List(length);
    var v = size;
    for (var i = length - 1; i >= 0; i--) {
      out[i] = v & 0xff;
      v >>= 8;
    }
    out[0] |= 0x80 >> (length - 1);
    return out;
  }

  static Uint8List _bytes(int id, Uint8List data) {
    final b = BytesBuilder(copy: false)
      ..add(_idBytes(id))
      ..add(_sizeBytes(data.length))
      ..add(data);
    return b.takeBytes();
  }

  static Uint8List _el(int id, List<Uint8List> children) {
    final body = BytesBuilder(copy: false);
    for (final c in children) {
      body.add(c);
    }
    return _bytes(id, body.takeBytes());
  }

  static Uint8List _uint(int id, int v) {
    var length = 1;
    while (length < 8 && v >> (8 * length) != 0) {
      length++;
    }
    return _uintFixed(id, v, length);
  }

  static Uint8List _uintFixed(int id, int v, int length) {
    final data = Uint8List(length);
    for (var i = length - 1, x = v; i >= 0; i--, x >>= 8) {
      data[i] = x & 0xff;
    }
    return _bytes(id, data);
  }

  static Uint8List _str(int id, String s) => _bytes(id, Uint8List.fromList(utf8.encode(s)));

  static Uint8List _float64(int id, double v) => _bytes(id, (ByteData(8)..setFloat64(0, v)).buffer.asUint8List());
}

/// One TrackEntry of a source file: its kind and every child element as it was.
class _Track {
  _Track(this.number, this.type, this.children);

  final int number;
  final int type;
  final List<(int, Uint8List)> children;
}

/// One Block, ready to be written into the output.
class _Block {
  _Block({
    required this.track,
    required this.ms,
    required this.key,
    required this.data,
    required this.isVideo,
    this.extra = const [],
    this.group = false,
  });

  final int track; // in the output
  final int ms;
  final bool key;
  final bool isVideo;

  /// The block after its track number and time: the flags byte and the frame(s).
  final Uint8List data;

  /// The other children of a BlockGroup (duration, references, DiscardPadding).
  final List<(int, Uint8List)> extra;
  final bool group;

  Uint8List encode({required int rel}) {
    final head = Uint8List(3)
      ..[0] = 0x80 | track
      ..[1] = (rel >> 8) & 0xff
      ..[2] = rel & 0xff;
    final payload = BytesBuilder(copy: false)
      ..add(head)
      ..add(data);
    if (!group) return WebmMux._bytes(0xA3, payload.takeBytes());
    return WebmMux._el(0xA0, [
      WebmMux._bytes(0xA1, payload.takeBytes()),
      for (final (id, d) in extra) WebmMux._bytes(id, d),
    ]);
  }
}

/// A WebM file being read: its Info and Tracks up front, its Clusters one at a time.
class _Source {
  _Source._(this._f, this.length);

  factory _Source.open(String path) {
    final f = File(path).openSync();
    final s = _Source._(f, f.lengthSync());
    try {
      s._readHeaders();
    } catch (_) {
      f.closeSync();
      rethrow;
    }
    return s;
  }

  final RandomAccessFile _f;
  final int length;
  final tracks = <_Track>[];
  int _scaleNs = 1000000;
  double? _durationTicks;
  int _next = 0; // where the first Cluster (or the next one) starts
  int _end = 0;

  double? get durationMs => _durationTicks == null ? null : _durationTicks! * _scaleNs / 1e6;

  void close() => _f.closeSync();

  _Track? firstTrack(int type) => tracks.where((t) => t.type == type).firstOrNull;

  /// An element header at [pos]: its id, size (-1 when unknown) and the header's length.
  (int id, int size, int head)? _header(int pos) {
    if (pos >= length) return null;
    _f.setPositionSync(pos);
    final b = _f.readSync(12);
    if (b.isEmpty) return null;
    var idLen = 1;
    while (idLen <= 4 && b[0] & (0x80 >> (idLen - 1)) == 0) {
      idLen++;
    }
    if (idLen > 4 || idLen >= b.length) return null;
    var id = 0;
    for (var i = 0; i < idLen; i++) {
      id = (id << 8) | b[i];
    }
    final first = b[idLen];
    var sizeLen = 1;
    while (sizeLen <= 8 && first & (0x80 >> (sizeLen - 1)) == 0) {
      sizeLen++;
    }
    if (sizeLen > 8 || idLen + sizeLen > b.length) return null;
    var v = first & ((0x80 >> (sizeLen - 1)) - 1);
    var ones = v == (0x80 >> (sizeLen - 1)) - 1;
    for (var i = 1; i < sizeLen; i++) {
      v = (v << 8) | b[idLen + i];
      if (b[idLen + i] != 0xff) ones = false;
    }
    return (id, ones ? -1 : v, idLen + sizeLen);
  }

  Uint8List _read(int pos, int n) {
    _f.setPositionSync(pos);
    final b = _f.readSync(n);
    if (b.length != n) throw const MuxException('the file is cut off');
    return b;
  }

  void _readHeaders() {
    var h = _header(0);
    if (h == null || h.$1 != 0x1A45DFA3) throw const MuxException('not a WebM file');
    var pos = h.$3 + h.$2;
    h = _header(pos);
    if (h == null || h.$1 != 0x18538067) throw const MuxException('no Segment');
    pos += h.$3;
    _end = h.$2 < 0 ? length : (pos + h.$2).clamp(0, length);
    while (pos < _end) {
      final e = _header(pos);
      if (e == null) break;
      final (id, size, head) = e;
      if (id == 0x1F43B675) {
        _next = pos;
        return;
      }
      if (size < 0) throw const MuxException('an element of unknown size');
      final bodyAt = pos + head;
      if (id == 0x1549A966 || id == 0x1654AE6B) {
        final body = _read(bodyAt, size);
        if (id == 0x1549A966) {
          _readInfo(body);
        } else {
          _readTracks(body);
        }
      }
      pos = bodyAt + size;
    }
    _next = _end; // no Clusters: nothing to copy
  }

  static Iterable<(int, Uint8List)> _children(Uint8List d) sync* {
    var pos = 0;
    while (pos < d.length) {
      var idLen = 1;
      while (idLen <= 4 && d[pos] & (0x80 >> (idLen - 1)) == 0) {
        idLen++;
      }
      if (idLen > 4 || pos + idLen >= d.length) return;
      var id = 0;
      for (var i = 0; i < idLen; i++) {
        id = (id << 8) | d[pos + i];
      }
      pos += idLen;
      var sizeLen = 1;
      while (sizeLen <= 8 && d[pos] & (0x80 >> (sizeLen - 1)) == 0) {
        sizeLen++;
      }
      if (sizeLen > 8 || pos + sizeLen > d.length) return;
      var size = d[pos] & ((0x80 >> (sizeLen - 1)) - 1);
      for (var i = 1; i < sizeLen; i++) {
        size = (size << 8) | d[pos + i];
      }
      pos += sizeLen;
      if (pos + size > d.length) return;
      yield (id, Uint8List.sublistView(d, pos, pos + size));
      pos += size;
    }
  }

  static int _uintOf(Uint8List d) {
    var v = 0;
    for (final b in d) {
      v = (v << 8) | b;
    }
    return v;
  }

  void _readInfo(Uint8List body) {
    for (final (id, d) in _children(body)) {
      if (id == 0x2AD7B1) _scaleNs = _uintOf(d);
      if (id == 0x4489 && (d.length == 4 || d.length == 8)) {
        final bd = ByteData.sublistView(d);
        _durationTicks = d.length == 4 ? bd.getFloat32(0) : bd.getFloat64(0);
      }
    }
  }

  void _readTracks(Uint8List body) {
    for (final (id, d) in _children(body)) {
      if (id != 0xAE) continue;
      final kids = [for (final (cid, cd) in _children(d)) (cid, Uint8List.fromList(cd))];
      int? number, type;
      for (final (cid, cd) in kids) {
        if (cid == 0xD7) number = _uintOf(cd);
        if (cid == 0x83) type = _uintOf(cd);
      }
      if (number != null && type != null) tracks.add(_Track(number, type, kids));
    }
  }

  /// The blocks of source track [number], in file order, as output track [outTrack].
  Iterable<_Block> blocks(int number, int outTrack) sync* {
    var pos = _next;
    while (pos < _end) {
      final e = _header(pos);
      if (e == null) return;
      final (id, size, head) = e;
      if (id != 0x1F43B675) {
        if (size < 0) return;
        pos += head + size;
        continue;
      }
      if (size < 0) throw const MuxException('a Cluster of unknown size');
      if (pos + head + size > length) return; // cut off: nothing partial is kept
      yield* _cluster(_read(pos + head, size), number, outTrack);
      pos += head + size;
    }
  }

  Iterable<_Block> _cluster(Uint8List body, int number, int outTrack) sync* {
    var tc = 0;
    int ms(int rel) => ((tc + rel) * _scaleNs / 1e6).round();
    for (final (id, d) in _children(body)) {
      switch (id) {
        case 0xE7:
          tc = _uintOf(d);
        case 0xA3:
          final b = _parseBlock(d, number);
          if (b == null) continue;
          yield _Block(track: outTrack, ms: ms(b.rel), key: b.flags & 0x80 != 0, data: b.data, isVideo: outTrack == 1);
        case 0xA0:
          Uint8List? block;
          final extra = <(int, Uint8List)>[];
          var reference = false;
          for (final (cid, cd) in _children(d)) {
            if (cid == 0xA1) {
              block = cd;
            } else {
              if (cid == 0xFB) reference = true;
              extra.add((cid, Uint8List.fromList(cd)));
            }
          }
          if (block == null) continue;
          final b = _parseBlock(block, number);
          if (b == null) continue;
          yield _Block(
            track: outTrack,
            ms: ms(b.rel),
            key: !reference,
            data: b.data,
            isVideo: outTrack == 1,
            extra: extra,
            group: true,
          );
      }
    }
  }

  static ({int rel, int flags, Uint8List data})? _parseBlock(Uint8List d, int number) {
    if (d.isEmpty) return null;
    var len = 1;
    while (len <= 8 && d[0] & (0x80 >> (len - 1)) == 0) {
      len++;
    }
    if (len > 8 || len + 3 > d.length) throw const MuxException('a damaged block');
    var track = d[0] & ((0x80 >> (len - 1)) - 1);
    for (var i = 1; i < len; i++) {
      track = (track << 8) | d[i];
    }
    if (track != number) return null;
    final rel = ((d[len] << 8) | d[len + 1]).toSigned(16);
    return (rel: rel, flags: d[len + 2], data: Uint8List.sublistView(d, len + 2));
  }
}
