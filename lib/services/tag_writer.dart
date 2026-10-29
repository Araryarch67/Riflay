import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'metadata.dart' show TagEdit;

/// A file whose tags can't be changed safely here (an unusual layout). Nothing is written.
class UnsupportedTagLayout implements Exception {
  const UnsupportedTagLayout(this.reason);

  final String reason;

  @override
  String toString() => 'UnsupportedTagLayout: $reason';
}

/// Writes tag edits into MP3, Ogg (Vorbis, Opus), WAV, AIFF, WavPack and
/// Monkey's Audio files in Dart, so the tag editor needs no FFmpeg and works on
/// phones too. Only the edited fields change: every other frame, comment, item
/// and chunk (ReplayGain, lyrics, a tagger's own fields) is copied as it was,
/// and so is the audio, byte for byte.
abstract final class TagWriter {
  /// Extensions [write] handles, cover art included.
  static const formats = {'mp3', 'ogg', 'oga', 'opus', 'wav', 'aiff', 'aif', 'wv', 'ape'};

  /// Writes [src] with [edit] applied into [dst] (created or overwritten).
  /// Synchronous file work: call it off the UI isolate.
  static void write(String src, File dst, TagEdit edit) {
    final ext = src.split('.').last.toLowerCase();
    final input = File(src).openSync();
    final output = dst.openSync(mode: FileMode.write);
    try {
      final file = _Source(input);
      switch (ext) {
        case 'mp3':
          _writeMp3(file, output, edit);
        case 'ogg' || 'oga' || 'opus':
          _Ogg(file, output).write(edit);
        case 'wav':
          _writeWav(file, output, edit);
        case 'aiff' || 'aif':
          _writeAiff(file, output, edit);
        case 'wv' || 'ape':
          _writeApeFile(file, output, edit);
        default:
          throw UnsupportedTagLayout('.$ext');
      }
    } finally {
      input.closeSync();
      output.closeSync();
    }
  }
}

/// The source file, read in place (songs can be large).
class _Source {
  _Source(this.file) : length = file.lengthSync();

  final RandomAccessFile file;
  final int length;

  Uint8List read(int start, int count) {
    file.setPositionSync(start);
    final bytes = file.readSync(count);
    if (bytes.length != count) throw const UnsupportedTagLayout('the file ends early');
    return bytes;
  }

  /// Copies [start, end) of the source to [to].
  void copy(RandomAccessFile to, int start, int end) {
    file.setPositionSync(start);
    var left = end - start;
    while (left > 0) {
      final chunk = file.readSync(left < 1 << 20 ? left : 1 << 20);
      if (chunk.isEmpty) throw const UnsupportedTagLayout('the file ends early');
      to.writeFromSync(chunk);
      left -= chunk.length;
    }
  }
}

/// "N", keeping a total that was there ("3/12" edited to 4 is "4/12").
String? _numbered(int? n, String? old) {
  if (n == null) return null;
  final slash = old?.indexOf('/') ?? -1;
  return slash < 0 ? '$n' : '$n${old!.substring(slash)}';
}

/// [year], keeping a full date that is in that year ("2019-05-03" stays).
String? _dated(int? year, String? old) {
  if (year == null) return null;
  return old != null && old.trim().startsWith('$year') ? old.trim() : '$year';
}

int _u32be(Uint8List b, int o) => b[o] << 24 | b[o + 1] << 16 | b[o + 2] << 8 | b[o + 3];

int _u32le(Uint8List b, int o) => b[o] | b[o + 1] << 8 | b[o + 2] << 16 | b[o + 3] << 24;

Uint8List _be32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);

Uint8List _le32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);

int _syncsafe(Uint8List b, int o) =>
    (b[o] & 0x7f) << 21 | (b[o + 1] & 0x7f) << 14 | (b[o + 2] & 0x7f) << 7 | b[o + 3] & 0x7f;

Uint8List _toSyncsafe(int v) {
  if (v >= 1 << 28) throw const UnsupportedTagLayout('the tag would be too large');
  return Uint8List.fromList([v >> 21 & 0x7f, v >> 14 & 0x7f, v >> 7 & 0x7f, v & 0x7f]);
}

bool _isLatin1(String s) => s.codeUnits.every((c) => c < 0x100);

// ── ID3v2 (MP3, and the ID3 chunk of WAV and AIFF) ───────────────────────────

class _Id3Frame {
  _Id3Frame(this.id, this.flags, this.data);

  final String id;
  final int flags;
  final Uint8List data;
}

/// An ID3v2.3 or 2.4 tag as a list of frames, the untouched ones kept raw.
class _Id3Tag {
  _Id3Tag(this.version, this.frames);

  /// A new tag: ID3v2.3, which every player reads.
  _Id3Tag.empty() : version = 3, frames = [];

  final int version;
  final List<_Id3Frame> frames;

  /// The tag's whole length (header, frames, padding, footer) from its first 10 bytes.
  static int lengthOf(Uint8List header) => 10 + _syncsafe(header, 6) + (header[5] & 0x10 != 0 ? 10 : 0);

  static bool isTag(Uint8List bytes) =>
      bytes.length >= 10 && bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33; // "ID3"

  /// Reads a tag from [bytes] (header first).
  static _Id3Tag parse(Uint8List bytes) {
    if (!isTag(bytes)) throw const UnsupportedTagLayout('not an ID3 tag');
    final version = bytes[3];
    // ID3v2.2 has three-letter frames; rewriting it would lose them.
    if (version != 3 && version != 4) throw UnsupportedTagLayout('ID3v2.$version');
    final flags = bytes[5];
    final size = _syncsafe(bytes, 6);
    if (10 + size > bytes.length) throw const UnsupportedTagLayout('the ID3 tag runs past the file');
    var data = Uint8List.sublistView(bytes, 10, 10 + size);
    // v2.3 unsynchronises the whole tag; it is written back without.
    if (version == 3 && flags & 0x80 != 0) data = _resync(data);
    var pos = 0;
    if (flags & 0x40 != 0) pos = version == 3 ? 4 + _u32be(data, 0) : _syncsafe(data, 0);
    final frames = <_Id3Frame>[];
    while (pos + 10 <= data.length && _isFrameId(data, pos)) {
      final id = ascii.decode(data.sublist(pos, pos + 4));
      final frameSize = version == 4 ? _v4FrameSize(data, pos) : _u32be(data, pos + 4);
      final end = pos + 10 + frameSize;
      if (end > data.length) throw UnsupportedTagLayout('the $id frame runs past the tag');
      var frameFlags = data[pos + 8] << 8 | data[pos + 9];
      var body = Uint8List.fromList(data.sublist(pos + 10, end));
      // v2.4 marks unsynchronised frames one by one (0x02); with the tag's flag
      // set, all are. They are written back plain, as the tag will say.
      if (version == 4 && (flags & 0x80 != 0 || frameFlags & 0x02 != 0)) {
        body = _resync(body);
        frameFlags &= ~0x02;
      }
      frames.add(_Id3Frame(id, frameFlags, body));
      pos = end;
    }
    return _Id3Tag(version, frames);
  }

  static bool _isFrameId(Uint8List d, int at) {
    for (var i = at; i < at + 4; i++) {
      final c = d[i];
      if (!(c >= 0x41 && c <= 0x5a || c >= 0x30 && c <= 0x39)) return false;
    }
    return true;
  }

  /// v2.4 frame sizes are syncsafe, but some writers (old iTunes) stored plain
  /// numbers: take whichever lands on the next frame or the end of the frames.
  static int _v4FrameSize(Uint8List d, int at) {
    final safe = _syncsafe(d, at + 4), plain = _u32be(d, at + 4);
    if (safe == plain) return safe;
    bool fits(int size) {
      final next = at + 10 + size;
      return next == d.length || next < d.length && (d[next] == 0 || next + 4 <= d.length && _isFrameId(d, next));
    }

    return fits(safe) || !fits(plain) ? safe : plain;
  }

  static Uint8List _resync(Uint8List d) {
    final out = BytesBuilder(copy: false);
    for (var i = 0; i < d.length; i++) {
      out.addByte(d[i]);
      if (d[i] == 0xff && i + 1 < d.length && d[i + 1] == 0) i++;
    }
    return out.takeBytes();
  }

  /// The text of the first [id] frame.
  String? text(String id) {
    final f = frames.where((f) => f.id == id).firstOrNull;
    if (f == null || f.data.isEmpty || f.flags & 0xff != 0) return null; // compressed or encrypted: unknown
    final body = f.data.sublist(1);
    final text = switch (f.data[0]) {
      0 => latin1.decode(body),
      1 || 2 => _utf16(body, bigEndian: f.data[0] == 2),
      _ => utf8.decode(body, allowMalformed: true),
    };
    return text.split('\u0000').first;
  }

  static String _utf16(Uint8List b, {required bool bigEndian}) {
    var i = 0;
    if (b.length >= 2 && (b[0] == 0xff && b[1] == 0xfe || b[0] == 0xfe && b[1] == 0xff)) {
      bigEndian = b[0] == 0xfe;
      i = 2;
    }
    final units = <int>[];
    for (; i + 1 < b.length; i += 2) {
      units.add(bigEndian ? b[i] << 8 | b[i + 1] : b[i + 1] << 8 | b[i]);
    }
    return String.fromCharCodes(units);
  }

  Uint8List _encodeText(String value) {
    if (version == 4) return Uint8List.fromList([3, ...utf8.encode(value)]);
    if (_isLatin1(value)) return Uint8List.fromList([0, ...latin1.encode(value)]);
    final out = BytesBuilder()..add([1, 0xff, 0xfe]);
    for (final u in value.codeUnits) {
      out.add([u & 0xff, u >> 8]);
    }
    return out.takeBytes();
  }

  /// Replaces every [id] frame with one holding [value] (none when null), where the first one was.
  void _set(String id, String? value) {
    final at = frames.indexWhere((f) => f.id == id);
    frames.removeWhere((f) => f.id == id);
    if (value == null) return;
    final frame = _Id3Frame(id, 0, _encodeText(value));
    frames.insert(at < 0 ? frames.length : at, frame);
  }

  /// Applies [edit]; [oldTrack] is the file's track ("3/12") when this tag has none (a WAV's INFO).
  void apply(TagEdit edit, {String? oldTrack}) {
    _set('TIT2', edit.title);
    _set('TPE1', edit.artist);
    _set('TALB', edit.album);
    _set('TCON', edit.genre);
    _set('TRCK', _numbered(edit.trackNumber, text('TRCK') ?? oldTrack));
    _set('TPOS', _numbered(edit.discNumber, text('TPOS')));
    if (version == 4) {
      final old = text('TDRC') ?? text('TYER');
      frames.removeWhere((f) => f.id == 'TYER' || f.id == 'TDAT' || f.id == 'TIME');
      _set('TDRC', _dated(edit.year, old));
    } else {
      final old = text('TYER');
      frames.removeWhere((f) => f.id == 'TDRC');
      _set('TYER', _dated(edit.year, old));
      if (edit.year == null) frames.removeWhere((f) => f.id == 'TDAT' || f.id == 'TIME');
    }
    if (edit.comment case final comment?) {
      final text = _encodeText(comment);
      final utf16 = text[0] == 1;
      final at = frames.indexWhere((f) => f.id == 'COMM');
      frames.removeWhere((f) => f.id == 'COMM');
      // Encoding, language, an empty description, the text.
      final body = Uint8List.fromList([
        text[0],
        ...'eng'.codeUnits,
        ...(utf16 ? [0, 0] : [0]),
        ...text.sublist(1),
      ]);
      frames.insert(at < 0 ? frames.length : at, _Id3Frame('COMM', 0, body));
    }
    if (edit.cover case final cover?) {
      final at = frames.indexWhere((f) => f.id == 'APIC');
      frames.removeWhere((f) => f.id == 'APIC');
      // Latin-1 MIME type, "front cover", an empty description.
      final apic = Uint8List.fromList([0, ...latin1.encode(edit.coverMime), 0, 3, 0, ...cover]);
      frames.insert(at < 0 ? frames.length : at, _Id3Frame('APIC', 0, apic));
    }
  }

  /// The tag with [padding] zero bytes after the frames (room for later edits).
  Uint8List encode({int padding = 0}) {
    final body = BytesBuilder(copy: false);
    for (final f in frames) {
      body
        ..add(ascii.encode(f.id))
        ..add(version == 4 ? _toSyncsafe(f.data.length) : _be32(f.data.length))
        ..add([f.flags >> 8, f.flags & 0xff])
        ..add(f.data);
    }
    final size = body.length + padding;
    return (BytesBuilder(copy: false)
          ..add([0x49, 0x44, 0x33, version, 0, 0])
          ..add(_toSyncsafe(size))
          ..add(body.takeBytes())
          ..add(Uint8List(padding)))
        .takeBytes();
  }
}

// ── APEv2 (WavPack, Monkey's Audio, some MP3s) ───────────────────────────────

class _ApeItem {
  _ApeItem(this.key, this.flags, this.value);

  final String key;
  final int flags;
  final Uint8List value;
}

/// An APEv2 tag at the end of a file (before any ID3v1 tag).
class _ApeTag {
  _ApeTag(this.start, this.end, this.items);

  /// Where it starts (header included) and ends (after the footer); a new tag starts and ends at the same place.
  final int start, end;
  final List<_ApeItem> items;

  static const _textFlags = 0, _binaryFlags = 1 << 1;
  static const _coverKey = 'Cover Art (Front)';

  /// The tag ending at [end], or an empty one to insert there.
  static _ApeTag find(_Source f, int end) {
    if (end < 32) return _ApeTag(end, end, []);
    final footer = f.read(end - 32, 32);
    if (ascii.decode(footer.sublist(0, 8), allowInvalid: true) != 'APETAGEX') return _ApeTag(end, end, []);
    final size = _u32le(footer, 12), count = _u32le(footer, 16), flags = _u32le(footer, 20);
    final itemsStart = end - size;
    final start = flags & 0x80000000 != 0 ? itemsStart - 32 : itemsStart;
    if (size < 32 || start < 0) throw const UnsupportedTagLayout('a broken APE tag');
    final data = f.read(itemsStart, size - 32);
    final items = <_ApeItem>[];
    var pos = 0;
    for (var i = 0; i < count; i++) {
      if (pos + 8 > data.length) throw const UnsupportedTagLayout('a broken APE tag');
      final length = _u32le(data, pos), itemFlags = _u32le(data, pos + 4);
      final keyEnd = data.indexOf(0, pos + 8);
      if (keyEnd < 0 || keyEnd + 1 + length > data.length) throw const UnsupportedTagLayout('a broken APE tag');
      final key = ascii.decode(data.sublist(pos + 8, keyEnd), allowInvalid: true);
      items.add(_ApeItem(key, itemFlags, Uint8List.fromList(data.sublist(keyEnd + 1, keyEnd + 1 + length))));
      pos = keyEnd + 1 + length;
    }
    return _ApeTag(start, end, items);
  }

  bool get exists => end > start;

  String? text(String key) {
    final item = items.where((i) => i.key.toLowerCase() == key.toLowerCase()).firstOrNull;
    return item == null || item.flags & 0x6 != _textFlags ? null : utf8.decode(item.value, allowMalformed: true);
  }

  void _set(String key, String? value) {
    final at = items.indexWhere((i) => i.key.toLowerCase() == key.toLowerCase());
    final keep = at < 0 ? key : items[at].key;
    items.removeWhere((i) => i.key.toLowerCase() == key.toLowerCase());
    if (value == null) return;
    items.insert(at < 0 ? items.length : at, _ApeItem(keep, _textFlags, utf8.encode(value)));
  }

  void apply(TagEdit edit) {
    _set('Title', edit.title);
    _set('Artist', edit.artist);
    _set('Album', edit.album);
    _set('Genre', edit.genre);
    _set('Year', _dated(edit.year, text('Year')));
    _set('Track', _numbered(edit.trackNumber, text('Track')));
    _set('Disc', _numbered(edit.discNumber, text('Disc')));
    if (edit.cover case final cover?) {
      final at = items.indexWhere((i) => i.key.toLowerCase() == _coverKey.toLowerCase());
      items.removeWhere((i) => i.key.toLowerCase() == _coverKey.toLowerCase());
      final name = edit.coverMime == 'image/png' ? 'cover.png' : 'cover.jpg';
      final value = Uint8List.fromList([...ascii.encode(name), 0, ...cover]);
      items.insert(at < 0 ? items.length : at, _ApeItem(_coverKey, _binaryFlags, value));
    }
  }

  /// Header, items and footer (APEv2).
  Uint8List encode() {
    final body = BytesBuilder(copy: false);
    for (final i in items) {
      body
        ..add(_le32(i.value.length))
        ..add(_le32(i.flags))
        ..add(ascii.encode(i.key))
        ..addByte(0)
        ..add(i.value);
    }
    final size = body.length + 32;
    Uint8List mark(int flags) =>
        (BytesBuilder()
              ..add(ascii.encode('APETAGEX'))
              ..add(_le32(2000))
              ..add(_le32(size))
              ..add(_le32(items.length))
              ..add(_le32(flags))
              ..add(Uint8List(8)))
            .takeBytes();
    // Both carry "has a header"; the header also says it is one.
    return (BytesBuilder(copy: false)
          ..add(mark(0xa0000000))
          ..add(body.takeBytes())
          ..add(mark(0x80000000)))
        .takeBytes();
  }
}

/// The ID3v1 tag at the end of [f] (128 bytes from "TAG"), or null.
Uint8List? _id3v1(_Source f) {
  if (f.length < 128) return null;
  final tag = f.read(f.length - 128, 128);
  return tag[0] == 0x54 && tag[1] == 0x41 && tag[2] == 0x47 ? tag : null;
}

/// [tag] (ID3v1) with the edited text fields; its genre byte stays.
Uint8List _editId3v1(Uint8List tag, TagEdit edit) {
  final out = Uint8List.fromList(tag);
  void put(int at, int length, String? value) {
    final bytes = latin1.encode(String.fromCharCodes((value ?? '').runes.map((r) => r < 0x100 ? r : 0x3f)));
    out.fillRange(at, at + length, 0);
    out.setRange(at, at + (bytes.length < length ? bytes.length : length), bytes);
  }

  put(3, 30, edit.title);
  put(33, 30, edit.artist);
  put(63, 30, edit.album);
  put(93, 4, edit.year?.toString());
  // ID3v1.1 keeps the track number in the comment's last byte, after a zero.
  if (out[125] == 0) out[126] = (edit.trackNumber ?? 0) <= 255 ? edit.trackNumber ?? 0 : 0;
  return out;
}

// ── Files ────────────────────────────────────────────────────────────────────

void _writeMp3(_Source f, RandomAccessFile out, TagEdit edit) {
  var audioStart = 0;
  _Id3Tag tag;
  final head = f.length >= 10 ? f.read(0, 10) : Uint8List(0);
  if (_Id3Tag.isTag(head)) {
    audioStart = _Id3Tag.lengthOf(head);
    if (audioStart > f.length) throw const UnsupportedTagLayout('the ID3 tag runs past the file');
    tag = _Id3Tag.parse(f.read(0, audioStart));
  } else {
    tag = _Id3Tag.empty();
  }
  tag.apply(edit);
  final v1 = _id3v1(f);
  final end = f.length - (v1 == null ? 0 : 128);
  // An APE tag some taggers add: kept in step, since a few players read it first.
  final ape = _ApeTag.find(f, end);
  out.writeFromSync(tag.encode(padding: 1024));
  f.copy(out, audioStart, ape.start);
  if (ape.exists) {
    ape.apply(edit);
    out.writeFromSync(ape.encode());
  }
  if (v1 != null) out.writeFromSync(_editId3v1(v1, edit));
}

void _writeApeFile(_Source f, RandomAccessFile out, TagEdit edit) {
  final v1 = _id3v1(f);
  final end = f.length - (v1 == null ? 0 : 128);
  final ape = _ApeTag.find(f, end)..apply(edit);
  f.copy(out, 0, ape.start);
  out.writeFromSync(ape.encode());
  if (v1 != null) out.writeFromSync(_editId3v1(v1, edit));
}

/// A RIFF or IFF chunk: where its header starts, its id and its payload size.
typedef _Chunk = ({int at, String id, int size});

/// The chunks of a RIFF (little-endian) or IFF (big-endian) file after its 12-byte header.
List<_Chunk> _chunks(_Source f, {required bool bigEndian}) {
  final chunks = <_Chunk>[];
  var pos = 12;
  while (pos + 8 <= f.length) {
    final h = f.read(pos, 8);
    final size = bigEndian ? _u32be(h, 4) : _u32le(h, 4);
    final end = pos + 8 + size;
    if (end > f.length) throw const UnsupportedTagLayout('a chunk runs past the end of the file');
    chunks.add((at: pos, id: latin1.decode(h.sublist(0, 4)), size: size));
    pos = end + (size & 1); // chunks are padded to an even length
  }
  return chunks;
}

/// Copies chunk [c] as it is, with its pad byte (written fresh: a last chunk may lack it).
void _copyChunk(_Source f, RandomAccessFile out, _Chunk c) {
  f.copy(out, c.at, c.at + 8 + c.size);
  if (c.size.isOdd) out.writeByteSync(0);
}

/// A chunk's header, [body] and pad byte.
Uint8List _chunk(String id, Uint8List body, {required bool bigEndian}) =>
    (BytesBuilder(copy: false)
          ..add(latin1.encode(id))
          ..add(bigEndian ? _be32(body.length) : _le32(body.length))
          ..add(body)
          ..add(body.length.isOdd ? [0] : const <int>[]))
        .takeBytes();

/// The ID3 tag in a chunk payload, edited; a new one when there is none.
Uint8List _editedId3(Uint8List? body, TagEdit edit, {String? oldTrack}) {
  var tag = _Id3Tag.empty();
  if (body != null && _Id3Tag.isTag(body)) tag = _Id3Tag.parse(body);
  return (tag..apply(edit, oldTrack: oldTrack)).encode();
}

void _writeWav(_Source f, RandomAccessFile out, TagEdit edit) {
  if (f.length < 12 || latin1.decode(f.read(0, 4)) != 'RIFF' || latin1.decode(f.read(8, 4)) != 'WAVE') {
    throw const UnsupportedTagLayout('not a RIFF WAVE file');
  }
  final chunks = _chunks(f, bigEndian: false);
  bool isInfo(_Chunk c) => c.id == 'LIST' && c.size >= 4 && latin1.decode(f.read(c.at + 8, 4)) == 'INFO';
  final infoChunk = chunks.where(isInfo).firstOrNull;
  final infoItems = infoChunk == null ? null : _infoEntries(f.read(infoChunk.at + 12, infoChunk.size - 4));
  // A new ID3 tag keeps the track total INFO had.
  final oldTrack = infoItems == null ? null : _infoText(infoItems, 'ITRK') ?? _infoText(infoItems, 'IPRT');
  var id3 = false;
  out.writeFromSync([...latin1.encode('RIFF'), 0, 0, 0, 0, ...latin1.encode('WAVE')]);
  for (final c in chunks) {
    if (c == infoChunk) {
      out.writeFromSync(_chunk('LIST', _editedInfo(infoItems!, edit), bigEndian: false));
    } else if ((c.id == 'id3 ' || c.id == 'ID3 ') && !id3) {
      id3 = true;
      out.writeFromSync(_chunk(c.id, _editedId3(f.read(c.at + 8, c.size), edit, oldTrack: oldTrack), bigEndian: false));
    } else {
      _copyChunk(f, out, c);
    }
  }
  if (infoChunk == null) out.writeFromSync(_chunk('LIST', _editedInfo([], edit), bigEndian: false));
  // INFO has no disc number or cover: the ID3 chunk carries everything, and readers prefer it.
  if (!id3) out.writeFromSync(_chunk('id3 ', _editedId3(null, edit, oldTrack: oldTrack), bigEndian: false));
  final size = out.lengthSync() - 8;
  if (size > 0xffffffff) throw const UnsupportedTagLayout('larger than a WAV file can be');
  out
    ..setPositionSync(4)
    ..writeFromSync(_le32(size));
}

/// The entries of a LIST/INFO payload (after "INFO").
List<(String, Uint8List)> _infoEntries(Uint8List items) {
  final entries = <(String, Uint8List)>[];
  for (var pos = 0; pos + 8 <= items.length;) {
    final size = _u32le(items, pos + 4);
    if (pos + 8 + size > items.length) break;
    entries.add((
      latin1.decode(items.sublist(pos, pos + 4)),
      Uint8List.fromList(items.sublist(pos + 8, pos + 8 + size)),
    ));
    pos += 8 + size + (size & 1);
  }
  return entries;
}

String? _infoText(List<(String, Uint8List)> entries, String id) => entries
    .where((e) => e.$1 == id)
    .map((e) => utf8.decode(e.$2, allowMalformed: true).split('\u0000').first)
    .firstOrNull;

/// A LIST/INFO payload ("INFO" first) with the edited fields; other entries stay.
Uint8List _editedInfo(List<(String, Uint8List)> entries, TagEdit edit) {
  String? old(String id) => _infoText(entries, id);
  void set(String id, String? value) {
    final at = entries.indexWhere((e) => e.$1 == id);
    entries.removeWhere((e) => e.$1 == id);
    if (value == null) return;
    entries.insert(at < 0 ? entries.length : at, (id, Uint8List.fromList([...utf8.encode(value), 0])));
  }

  set('INAM', edit.title);
  set('IART', edit.artist);
  set('IPRD', edit.album);
  set('IGNR', edit.genre);
  set('ICRD', _dated(edit.year, old('ICRD')));
  // FFmpeg writes the track as IPRT, most taggers as ITRK: both follow.
  final track = _numbered(edit.trackNumber, old('ITRK') ?? old('IPRT'));
  if (entries.any((e) => e.$1 == 'IPRT')) set('IPRT', track);
  set('ITRK', track);
  final out = BytesBuilder(copy: false)..add(latin1.encode('INFO'));
  for (final (id, value) in entries) {
    out.add(_chunk(id, value, bigEndian: false));
  }
  return out.takeBytes();
}

void _writeAiff(_Source f, RandomAccessFile out, TagEdit edit) {
  final form = f.length < 12 ? '' : latin1.decode(f.read(8, 4));
  if (f.length < 12 || latin1.decode(f.read(0, 4)) != 'FORM' || (form != 'AIFF' && form != 'AIFC')) {
    throw const UnsupportedTagLayout('not an AIFF file');
  }
  final chunks = _chunks(f, bigEndian: true);
  var id3 = false;
  out.writeFromSync([...latin1.encode('FORM'), 0, 0, 0, 0, ...latin1.encode(form)]);
  for (final c in chunks) {
    // The text chunks follow the edit too, for players that read only them.
    final text = switch (c.id) {
      'NAME' => edit.title,
      'AUTH' => edit.artist,
      _ => '',
    };
    if (c.id == 'NAME' || c.id == 'AUTH') {
      if (text != null) out.writeFromSync(_chunk(c.id, latin1.encode(_latin1(text)), bigEndian: true));
    } else if (c.id == 'ID3 ' && !id3) {
      id3 = true;
      out.writeFromSync(_chunk(c.id, _editedId3(f.read(c.at + 8, c.size), edit), bigEndian: true));
    } else {
      _copyChunk(f, out, c);
    }
  }
  if (!id3) out.writeFromSync(_chunk('ID3 ', _editedId3(null, edit), bigEndian: true));
  final size = out.lengthSync() - 8;
  if (size > 0xffffffff) throw const UnsupportedTagLayout('larger than an AIFF file can be');
  out
    ..setPositionSync(4)
    ..writeFromSync(_be32(size));
}

String _latin1(String s) => String.fromCharCodes(s.runes.map((r) => r < 0x100 ? r : 0x3f));

// ── Ogg (Vorbis, Opus) ───────────────────────────────────────────────────────

/// Rewrites the comment header of an Ogg Vorbis or Opus file. The header
/// packets are laid out on new pages; audio pages are copied, with their page
/// numbers (and checksums) moved along when the header takes more or fewer pages.
class _Ogg {
  _Ogg(this.f, this.out);

  final _Source f;
  final RandomAccessFile out;

  static final _crcTable = List<int>.generate(256, (i) {
    var r = i << 24;
    for (var j = 0; j < 8; j++) {
      r = r & 0x80000000 != 0 ? (r << 1) ^ 0x04c11db7 : r << 1;
    }
    return r & 0xffffffff;
  });

  static int _crc(Uint8List page) {
    var crc = 0;
    for (final b in page) {
      crc = ((crc << 8) & 0xffffffff) ^ _crcTable[(crc >> 24) ^ b];
    }
    return crc;
  }

  /// The page at [at] (header, lacing values and data).
  Uint8List _page(int at) {
    final h = f.read(at, 27);
    if (h[0] != 0x4f || h[1] != 0x67 || h[2] != 0x67 || h[3] != 0x53 || h[4] != 0) {
      throw const UnsupportedTagLayout('a broken Ogg page');
    }
    final lacing = f.read(at + 27, h[26]);
    return f.read(at, 27 + h[26] + lacing.fold(0, (a, b) => a + b));
  }

  void write(TagEdit edit) {
    // Read the header packets: Vorbis has three (identification, comments,
    // setup), Opus two. Audio starts on a fresh page after them.
    final packets = <Uint8List>[];
    final current = BytesBuilder(copy: false);
    var pos = 0, headerPages = 0, needed = 0;
    late final int serial;
    var vorbis = false;
    while (needed == 0 || packets.length < needed) {
      if (pos >= f.length) throw const UnsupportedTagLayout('the Ogg headers are cut off');
      final page = _page(pos);
      final pageSerial = _u32le(page, 14);
      if (headerPages == 0) {
        if (page[5] & 2 == 0) throw const UnsupportedTagLayout('no Ogg start page');
        serial = pageSerial;
      } else if (pageSerial != serial) {
        throw const UnsupportedTagLayout('more than one Ogg stream');
      }
      headerPages++;
      pos += page.length;
      final segments = page[26];
      var data = 27 + segments;
      for (var i = 0; i < segments; i++) {
        final lace = page[27 + i];
        current.add(Uint8List.sublistView(page, data, data + lace));
        data += lace;
        if (lace < 255) {
          packets.add(current.takeBytes());
          if (packets.length == 1) {
            final id = packets.first;
            if (id.length > 7 && id[0] == 1 && ascii.decode(id.sublist(1, 7), allowInvalid: true) == 'vorbis') {
              vorbis = true;
              needed = 3;
            } else if (id.length > 8 && ascii.decode(id.sublist(0, 8), allowInvalid: true) == 'OpusHead') {
              needed = 2;
            } else {
              throw const UnsupportedTagLayout('an Ogg stream that is not Vorbis or Opus');
            }
          }
          if (needed > 0 && packets.length > needed) {
            throw const UnsupportedTagLayout('audio shares a page with the Ogg headers');
          }
        }
      }
    }
    if (current.length > 0) throw const UnsupportedTagLayout('audio shares a page with the Ogg headers');

    packets[1] = _editedComments(packets[1], edit, vorbis: vorbis);
    final pages = [
      ..._paginate([packets[0]], serial: serial, firstSequence: 0, first: true),
      ..._paginate(packets.sublist(1), serial: serial, firstSequence: 1),
    ];
    for (final p in pages) {
      out.writeFromSync(p);
    }
    final shift = pages.length - headerPages;
    if (shift == 0) {
      f.copy(out, pos, f.length);
      return;
    }
    // Renumber this stream's pages up to its end; anything after (a chained stream) is copied as it is.
    while (pos < f.length) {
      final page = _page(pos);
      if (_u32le(page, 14) != serial) break;
      final data = ByteData.sublistView(page);
      data.setUint32(18, data.getUint32(18, Endian.little) + shift, Endian.little);
      data.setUint32(22, 0, Endian.little);
      data.setUint32(22, _crc(page), Endian.little);
      out.writeFromSync(page);
      pos += page.length;
      if (page[5] & 4 != 0) break; // end of stream
    }
    f.copy(out, pos, f.length);
  }

  /// [packets] on pages, a packet carried over from one page to the next as Ogg lays them out.
  static List<Uint8List> _paginate(
    List<Uint8List> packets, {
    required int serial,
    required int firstSequence,
    bool first = false,
  }) {
    // Each packet is laced as 255-byte segments and a final shorter one (0 when it divides evenly).
    final segments = <({Uint8List packet, int start, int lace, bool last})>[];
    for (final packet in packets) {
      var start = 0;
      while (true) {
        final lace = packet.length - start >= 255 ? 255 : packet.length - start;
        segments.add((packet: packet, start: start, lace: lace, last: lace < 255));
        start += lace;
        if (lace < 255) break;
      }
    }
    final pages = <Uint8List>[];
    var continued = false;
    for (var i = 0; i < segments.length; i += 255) {
      final onPage = segments.sublist(i, i + 255 < segments.length ? i + 255 : segments.length);
      // Header pages sit at granule 0; a page where no packet ends has none (-1).
      final granule = Uint8List(8);
      if (!onPage.any((s) => s.last)) granule.fillRange(0, 8, 0xff);
      final page = BytesBuilder(copy: false)
        ..add(ascii.encode('OggS'))
        ..add([0, (first && pages.isEmpty ? 2 : 0) | (continued ? 1 : 0)])
        ..add(granule)
        ..add(_le32(serial))
        ..add(_le32(firstSequence + pages.length))
        ..add(Uint8List(4))
        ..addByte(onPage.length)
        ..add([for (final s in onPage) s.lace]);
      for (final s in onPage) {
        page.add(Uint8List.sublistView(s.packet, s.start, s.start + s.lace));
      }
      final bytes = page.takeBytes();
      bytes.buffer.asByteData().setUint32(22, _crc(bytes), Endian.little);
      pages.add(bytes);
      continued = !onPage.last.last;
    }
    return pages;
  }

  /// The comment packet with the edited fields; other comments, the vendor
  /// string and anything after the list (Opus allows extra data) stay.
  static Uint8List _editedComments(Uint8List packet, TagEdit edit, {required bool vorbis}) {
    final prefix = vorbis ? 7 : 8;
    if (packet.length < prefix + 8) throw const UnsupportedTagLayout('a broken Ogg comment header');
    var pos = prefix;
    final vendorLength = _u32le(packet, pos);
    final vendor = packet.sublist(pos + 4, pos + 4 + vendorLength);
    pos += 4 + vendorLength;
    final count = _u32le(packet, pos);
    pos += 4;
    final comments = <Uint8List>[];
    for (var i = 0; i < count; i++) {
      final length = _u32le(packet, pos);
      if (pos + 4 + length > packet.length) throw const UnsupportedTagLayout('a broken Ogg comment header');
      comments.add(packet.sublist(pos + 4, pos + 4 + length));
      pos += 4 + length;
    }
    final rest = packet.sublist(pos);

    String keyOf(Uint8List c) {
      final eq = c.indexOf(0x3d);
      return ascii.decode(eq < 0 ? c : c.sublist(0, eq), allowInvalid: true).toUpperCase();
    }

    String? old(String key) {
      final c = comments.where((c) => keyOf(c) == key).firstOrNull;
      return c == null ? null : utf8.decode(c.sublist(c.indexOf(0x3d) + 1), allowMalformed: true);
    }

    void set(String key, String? value, {Set<String> also = const {}}) {
      final at = comments.indexWhere((c) => keyOf(c) == key || also.contains(keyOf(c)));
      comments.removeWhere((c) => keyOf(c) == key || also.contains(keyOf(c)));
      if (value == null) return;
      comments.insert(at < 0 ? comments.length : at, utf8.encode('$key=$value'));
    }

    set('TITLE', edit.title);
    set('ARTIST', edit.artist);
    set('ALBUM', edit.album);
    set('GENRE', edit.genre);
    set('DATE', _dated(edit.year, old('DATE') ?? old('YEAR')), also: {'YEAR'});
    set('TRACKNUMBER', _numbered(edit.trackNumber, old('TRACKNUMBER')));
    set('DISCNUMBER', _numbered(edit.discNumber, old('DISCNUMBER')));
    if (edit.comment != null) set('COMMENT', edit.comment, also: {'DESCRIPTION'});
    if (edit.cover case final cover?) {
      // A FLAC picture block, base64: the standard way to put a cover in Ogg.
      final mime = ascii.encode(edit.coverMime);
      final block = BytesBuilder(copy: false)
        ..add(_be32(3))
        ..add(_be32(mime.length))
        ..add(mime)
        ..add(_be32(0))
        ..add(Uint8List(16))
        ..add(_be32(cover.length))
        ..add(cover);
      set('METADATA_BLOCK_PICTURE', base64.encode(block.takeBytes()), also: {'COVERART', 'COVERARTMIME'});
    }

    final out = BytesBuilder(copy: false)
      ..add(packet.sublist(0, prefix))
      ..add(_le32(vendor.length))
      ..add(vendor)
      ..add(_le32(comments.length));
    for (final c in comments) {
      out
        ..add(_le32(c.length))
        ..add(c);
    }
    return (out..add(rest)).takeBytes();
  }
}
