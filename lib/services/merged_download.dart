// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

import 'request_gate.dart';

/// A song's better sound (Smart merge), fetched from its first byte over one connection and played from here.
///
/// A FLAC file without a seek table is found its way through by many small range requests, and a streaming
/// service can take seconds to answer each (Monochrome: 0.5-9 s measured), so opening one at a point stalls on a
/// slow or unsteady connection. Read from its start it comes at a few times the speed it plays, and seeking in
/// what has come is instant. A dropped connection carries on from the byte it had reached.
///
/// A song got ready ahead (the next in the queue, one the pointer rests on) fetches only its first stretch
/// ([readyBytes]): enough to start at once, without taking the connection from the song playing. Playing it
/// ([play]) fetches the rest.
///
/// What has come is kept in a file in the temporary folder, not in memory: a hi-res FLAC is 50-150 MB, and with
/// several songs kept that alone took the app past 500 MB. The disk's cache makes reading it back as quick. Where
/// no file can be made (the web) it stays in memory.
class MergedDownload {
  MergedDownload._(this.url, this._client) {
    _run();
  }

  /// The one download of [url], started on first ask. Several are kept: a song played again, or one got ready
  /// ahead, opens straight away. Older ones nothing reads from are let go.
  static MergedDownload of(String url, {http.Client? client}) {
    final known = _all.remove(url);
    if (known != null && !known.failed) return _all[url] = known;
    known?.dispose();
    final fresh = _all[url] = MergedDownload._(url, client);
    _trim();
    return fresh;
  }

  static void _trim() {
    while (_all.length > _kept) {
      // The oldest that isn't being played from: a song playing is never let go under it.
      final idle = _all.entries.where((e) => e.value._readers == 0).firstOrNull;
      if (idle == null) return;
      _all.remove(idle.key);
      idle.value.dispose();
    }
  }

  /// The download of [url] if one was started, without starting one.
  static MergedDownload? existing(String url) => _all[url];

  static const _kept = 6;
  static final _all = <String, MergedDownload>{};

  /// What a song got ready ahead fetches: a stretch to start from (about 8 s of 24-bit FLAC, 15 s of 16-bit).
  static const readyBytes = 2 << 20;

  @visibleForTesting
  static void forgetAll() {
    RequestGate.resetAll();
    for (final d in _all.values) {
      d.dispose();
    }
    _all.clear();
  }

  final String url;
  final http.Client? _client;
  late final _gate = RequestGate.of(Uri.parse(url).host);

  /// What has come, from the file's start; grown as more comes (a song got ready ahead holds only its start).
  /// Only without a [_spill] file.
  Uint8List _bytes = Uint8List(0);

  /// The file what has come is written to, and the write under way (closing waits for it).
  File? _spill;
  RandomAccessFile? _writer;
  Future<void> _writing = Future<void>.value();
  Future<void>? _closed;

  /// The folder of this run's files; those an earlier run left behind are deleted the first time.
  static Directory? _folder;
  static int _made = 0;

  static String get _root => '${Directory.systemTemp.path}${Platform.pathSeparator}riflay-smart-merge';
  static final _sep = Platform.pathSeparator;

  /// Whole songs are kept between sessions ([keptBytes] of them, the least recently played going first): a song
  /// played again opens from here, without asking the service (or spending its request limit). Off in tests.
  static bool keepsSongs = keepsByDefault;
  static final bool keepsByDefault = !kIsWeb && !Platform.environment.containsKey('FLUTTER_TEST');

  /// How much the kept songs may take on disk.
  static int keptBytes = 1 << 30;

  /// Where kept songs are (another folder in tests).
  @visibleForTesting
  static String? keptFolder;
  static String get _keptPath => keptFolder ?? '$_root${_sep}kept';

  /// Only an address that names the same file each time can be kept: one with a query (a signed, expiring link)
  /// can't.
  bool get _keepable {
    if (kIsWeb || !keepsSongs) return false;
    final uri = Uri.tryParse(url);
    return uri != null && uri.scheme == 'https' && uri.query.isEmpty && uri.host.isNotEmpty;
  }

  /// The file of [url] among the kept songs, and its mark of being whole (the length it should have).
  static (File, File) _keptOf(String url) {
    // FNV-1a, 64-bit: a short, stable name from the address.
    var h = 0xcbf29ce484222325;
    for (final c in url.codeUnits) {
      h ^= c;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    final name = h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
    return (File('$_keptPath$_sep$name.flac'), File('$_keptPath$_sep$name.ok'));
  }

  /// This song, kept whole by an earlier session (or earlier in this one): its file, or null.
  static Future<File?> _keptWhole(String url) async {
    try {
      final (file, ok) = _keptOf(url);
      if (!await ok.exists() || !await file.exists()) return null;
      final length = int.tryParse((await ok.readAsString()).trim());
      if (length == null || length != await file.length()) return null;
      // The most recently played go last.
      await file.setLastModified(DateTime.now()).catchError((_) {});
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Puts this whole song among the kept ones, and lets the least recently played go past [keptBytes].
  Future<void> _keep() async {
    if (!_keepable || _spill == null || _total == null) return;
    try {
      final (file, ok) = _keptOf(url);
      if (_spill!.path != file.path) return;
      await ok.writeAsString('$_total', flush: true);
      _isKept = true;
      final songs = <File, FileStat>{};
      await for (final e in Directory(_keptPath).list()) {
        if (e is File && e.path.endsWith('.flac')) songs[e] = await e.stat();
      }
      var total = songs.values.fold<int>(0, (n, s) => n + s.size);
      final oldest = songs.keys.toList()..sort((a, b) => songs[a]!.modified.compareTo(songs[b]!.modified));
      for (final f in oldest) {
        if (total <= keptBytes) break;
        if (f.path == file.path) continue;
        try {
          await File('${f.path.substring(0, f.path.length - 5)}.ok').delete();
          await f.delete();
          total -= songs[f]!.size;
        } catch (_) {
          // Being read: the next song kept tries again.
        }
      }
    } catch (e) {
      debugPrint('Smart merge download: not kept ($e)');
    }
  }

  /// Whether this song's file is a kept one: closing leaves it.
  bool _isKept = false;

  /// Opened from a song kept by an earlier session (nothing asked of the service).
  bool get fromKept => _fromKept;
  bool _fromKept = false;

  /// How much the kept songs take on disk now.
  static Future<int> keptSize() async {
    var total = 0;
    try {
      await for (final e in Directory(_keptPath).list()) {
        if (e is File && e.path.endsWith('.flac')) total += await e.length();
      }
    } catch (_) {}
    return total;
  }

  /// Deletes the kept songs (Settings › Music sources); one being played stays until it ends.
  static Future<void> clearKept() async {
    try {
      await for (final e in Directory(_keptPath).list()) {
        if (e is File) await e.delete().catchError((_) => e);
      }
    } catch (_) {}
    for (final d in _all.values) {
      if (d._isKept && d._readers == 0) d._forgetKept();
    }
  }

  /// Its kept file was deleted: the next ask fetches it again.
  void _forgetKept() {
    _all.remove(url);
    dispose();
  }

  Future<File?> _newSpill() async {
    if (kIsWeb) return null;
    try {
      if (_keepable) {
        await Directory(_keptPath).create(recursive: true);
        final (file, ok) = _keptOf(url);
        // A new download of it: whatever was there wasn't whole.
        await ok.delete().catchError((_) => ok);
        return file;
      }
      var folder = _folder;
      if (folder == null) {
        final root = _root;
        folder = Directory('$root$_sep$pid');
        await folder.create(recursive: true);
        _folder = folder;
        // Left by a run that ended without tidying up (one still running keeps its open files). Kept songs stay;
        // a kept file left half fetched (no mark of being whole) goes.
        unawaited(() async {
          try {
            await for (final old in Directory(root).list()) {
              if (old.path == folder!.path) continue;
              if (old.path.endsWith('${_sep}kept')) {
                await for (final f in Directory(old.path).list()) {
                  if (f is! File || !f.path.endsWith('.flac')) continue;
                  final ok = File('${f.path.substring(0, f.path.length - 5)}.ok');
                  final stale = DateTime.now().difference((await f.stat()).modified) > const Duration(hours: 1);
                  if (stale && !await ok.exists()) await f.delete().catchError((_) => f);
                }
                continue;
              }
              await old.delete(recursive: true).catchError((_) => old);
            }
          } catch (_) {}
        }());
      }
      return File('${folder.path}$_sep${_made++}.flac.part');
    } catch (_) {
      return null;
    }
  }

  /// Puts [chunk] at [at]: in the file, or in memory.
  Future<void> _put(int at, List<int> chunk, int count) async {
    final writer = _writer;
    if (writer == null) {
      _grow(at + count);
      _bytes.setRange(at, at + count, chunk);
      return;
    }
    final done = _writing = () async {
      await writer.setPosition(at);
      await writer.writeFrom(chunk, 0, count);
    }();
    await done;
  }

  /// [count] bytes from [at], all of them already here.
  Future<Uint8List> _get(int at, int count, [RandomAccessFile? reader]) async {
    if (_writer == null && _spill == null) {
      // A copy: the player may hold on to it after this download is let go.
      return Uint8List.fromList(Uint8List.sublistView(_bytes, at, at + count));
    }
    final own = reader ?? await _spill!.open();
    try {
      await own.setPosition(at);
      return await own.read(count);
    } finally {
      if (reader == null) await own.close();
    }
  }

  /// The most handed over at once: a player asking from the start of a song already fetched would otherwise get
  /// the whole file (100 MB) as one copy.
  static const _chunk = 256 << 10;
  int? _total;
  int _received = 0;
  bool _done = false;
  bool _disposed = false;
  Object? _error;
  Completer<void> _progress = Completer<void>();
  final _sized = Completer<void>();

  /// Until [play]: how far it fetches.
  int? _limit = readyBytes;
  final _playing = Completer<void>();

  /// Reads under way (a player is playing from it): it is not let go meanwhile.
  int _readers = 0;

  /// Bytes in the file, once the server has said.
  int? get total => _total;

  /// Bytes fetched so far, from the start.
  int get received => _received;
  bool get done => _done;

  /// When the last bytes came (or the download began).
  DateTime get lastProgress => _lastProgress;
  DateTime _lastProgress = DateTime.now();

  /// Gave up: the connection kept failing.
  bool get failed => _error != null;

  /// The server is asking for fewer requests (HTTP 429/503) and nothing has come since: it won't catch up soon.
  bool get busy => _busy;
  bool _busy = false;

  /// The file's size is known (its first answer came).
  Future<void> get sized => _sized.future;

  /// Whether the first [bytes] are here (or the whole file is).
  bool covers(int bytes) => _done || _received >= bytes;

  /// The song is played from it: the whole file is fetched, and its end too ([_fetchEnd]).
  void play() {
    if (_playing.isCompleted) return;
    _limit = null;
    _playing.complete();
    _lastProgress = DateTime.now(); // waiting for the rest starts now, not when the start came
    if (_total case final total? when total > 4 * _endSize) unawaited(_fetchEnd(total));
  }

  /// How many times a broken connection is tried again before giving up, and how long a silent one is waited for.
  static const _tries = 40;
  static const _silence = Duration(seconds: 20);

  Future<void> _run() async {
    final client = _client ?? http.Client();
    var failures = 0;
    // Kept whole by an earlier session: nothing to fetch.
    if (_keepable) {
      if (await _keptWhole(url) case final file?) {
        if (_disposed) return;
        final length = await file.length();
        _spill = file;
        _isKept = true;
        _fromKept = true;
        _total = length;
        _received = length;
        _done = true;
        if (!_sized.isCompleted) _sized.complete();
        _lastProgress = DateTime.now();
        debugPrint('Smart merge download: ${Uri.parse(url).pathSegments.lastOrNull} kept from before');
        _notify();
        return;
      }
    }
    final spill = await _newSpill();
    if (spill != null && !_disposed) {
      try {
        _writer = await spill.open(mode: FileMode.write);
        _spill = spill;
      } catch (e) {
        debugPrint('Smart merge download: kept in memory ($e)');
      }
    }
    try {
      while (!_disposed && !_done) {
        if (_limit case final limit? when _received >= limit) await _playing.future;
        if (_disposed) return;
        try {
          final request = http.Request('GET', Uri.parse(url))
            ..headers['User-Agent'] = 'Riflay'
            ..headers['Range'] = 'bytes=$_received-';
          // The song being played goes ahead of songs got ready; all wait out the service's limit together.
          await _gate.turn(urgent: _playing.isCompleted);
          if (_disposed) return;
          final response = await client.send(request).timeout(_silence);
          if (_disposed) return;
          final status = response.statusCode;
          if (status == 429 || status == 503) {
            // Too many requests: asking again at once only keeps the limit on. Its wait when it says one.
            response.stream.listen(null).cancel().ignore();
            throw SourceBusy(int.tryParse(response.headers['retry-after'] ?? ''));
          }
          _gate.ok();
          if (status != 200 && status != 206) throw http.ClientException('HTTP $status', request.url);
          var at = _received;
          if (status == 200) {
            // The range wasn't honoured: the whole file again, from its start.
            at = 0;
            _size(response.contentLength);
          } else {
            final range = RegExp(r'bytes (\d+)-\d+/(\d+)').firstMatch(response.headers['content-range'] ?? '');
            if (range == null) throw const FormatException('No Content-Range');
            at = int.parse(range[1]!);
            _size(int.parse(range[2]!));
          }
          final total = _total;
          if (total == null) throw const FormatException('Unknown length');
          await for (final chunk in response.stream.timeout(_silence)) {
            if (_disposed) return;
            final end = math.min(at + chunk.length, total);
            await _put(at, chunk, end - at);
            if (_disposed) return;
            at = end;
            // Bytes already had (a whole file sent again) don't count twice.
            if (at > _received) {
              _received = at;
              _busy = false;
              _lastProgress = DateTime.now();
              failures = 0;
              _notify();
            }
            // Got ready ahead: the start is here, the connection is let go until the song plays.
            if (_limit case final limit? when _received >= limit) break;
          }
          if (_received >= total) {
            _done = true;
            // Written through before it counts as whole: then kept for the next time it plays.
            final writer = _writer;
            if (writer != null) {
              await _writing;
              await writer.flush();
              await _keep();
            }
            _notify();
          }
        } catch (e) {
          if (_disposed) return;
          if (e is SourceBusy) {
            // The pause is the gate's: the next request waits it out ([RequestGate.turn]), as every other one to
            // the service does.
            _busy = true;
            _gate.limited(e.seconds);
          }
          if (++failures > _tries) rethrow;
          debugPrint('Smart merge download: $e, again from byte $_received ($failures)');
          if (e is! SourceBusy) await Future<void>.delayed(Duration(milliseconds: math.min(5000, 500 * failures)));
        }
      }
    } catch (e) {
      _error = e;
      if (!_sized.isCompleted) _sized.completeError(e);
      _notify();
    } finally {
      if (_client == null) client.close();
      if (_disposed) unawaited(_close());
    }
  }

  /// Closes and deletes the file (after the write under way).
  Future<void> _close() => _closed ??= () async {
    final writer = _writer;
    _writer = null;
    try {
      await _writing;
    } catch (_) {}
    try {
      await writer?.close();
    } catch (_) {}
    if (_isKept) return;
    try {
      await _spill?.delete();
    } catch (_) {
      // Still open for a read: the next run's tidy-up deletes it.
    }
  }();

  void _size(int? length) {
    if (_total != null || length == null || length <= 0) return;
    _total = length;
    if (!_sized.isCompleted) _sized.complete();
    if (_playing.isCompleted && length > 4 * _endSize) unawaited(_fetchEnd(length));
  }

  /// In memory: room for the first [bytes]: doubled as it fills, the whole file once it is played.
  void _grow(int bytes) {
    if (bytes <= _bytes.length) return;
    final total = _total!;
    final size = _playing.isCompleted ? total : math.min(total, math.max(bytes, _bytes.length * 2));
    _bytes = Uint8List(math.max(size, bytes))..setRange(0, _received, _bytes);
  }

  /// The file's last stretch, fetched once on its own when the song plays: to find a moment in a FLAC file
  /// without a seek table, the decoder reads its end first (where the song's last timestamp is), long before the
  /// download from the start gets there. With it here, a seek lands where the download is.
  static const _endSize = 1 << 20;
  Uint8List? _end;
  int _endStart = 0;

  Future<void> _fetchEnd(int length) async {
    if (_end != null) return;
    final client = _client ?? http.Client();
    try {
      for (var attempt = 1; attempt <= 5 && !_disposed && !_done; attempt++) {
        try {
          final from = length - _endSize;
          final request = http.Request('GET', Uri.parse(url))
            ..headers['User-Agent'] = 'Riflay'
            ..headers['Range'] = 'bytes=$from-';
          await _gate.turn(urgent: true);
          final response = await client.send(request).timeout(_silence);
          if (response.statusCode == 429 || response.statusCode == 503) {
            _gate.limited(int.tryParse(response.headers['retry-after'] ?? ''));
            response.stream.listen(null).cancel().ignore();
            continue;
          }
          if (response.statusCode != 206) return; // no ranges: the download from the start is all there is
          final bytes = await response.stream.toBytes().timeout(_silence);
          if (bytes.length != _endSize || _disposed) return;
          _end = bytes;
          _endStart = from;
          _notify();
          return;
        } catch (e) {
          debugPrint('Smart merge download: the file end, ${e.runtimeType} ($attempt)');
          await Future<void>.delayed(Duration(seconds: attempt));
        }
      }
    } finally {
      if (_client == null) client.close();
    }
  }

  void _notify() {
    final waiting = _progress;
    _progress = Completer<void>();
    waiting.complete();
  }

  /// The first [count] bytes, once they are here.
  Future<Uint8List> head(int count) async {
    await sized;
    while (_received < math.min(count, _total!) && !_done) {
      if (_error != null) throw _error!;
      await _progress.future;
    }
    if (_error != null && _received < count) throw _error!;
    return _get(0, math.min(count, _received));
  }

  /// Bytes [start] to [end] (exclusive), each as soon as it is here.
  ///
  /// A download that failed or was let go leaves the read waiting, not ended: just_audio's proxy reports a short
  /// answer as an error nobody catches. The player gives up on it itself, and Smart merge's watch takes the song
  /// back to its own sound.
  Stream<List<int>> read(int start, int end) async* {
    _readers++;
    RandomAccessFile? reader;
    try {
      await sized;
      var at = start;
      while (at < end) {
        if (_disposed) {
          // Its file goes: nothing more is read from it.
          await reader?.close();
          reader = null;
          await Completer<void>().future;
        }
        if (at < _received) {
          final upTo = math.min(math.min(end, _received), at + _chunk);
          if (_spill case final spill? when reader == null) reader = await spill.open();
          yield await _get(at, upTo - at, reader);
          at = upTo;
        } else if (_end case final tail? when at >= _endStart) {
          final upTo = math.min(end, _endStart + tail.length);
          yield Uint8List.fromList(Uint8List.sublistView(tail, at - _endStart, upTo - _endStart));
          at = upTo;
        } else {
          if (_done) return;
          await _progress.future;
        }
      }
    } finally {
      _readers--;
      await reader?.close();
    }
  }

  /// The download as something to play, each byte as soon as it is here. Playing it fetches the whole file.
  StreamAudioSource source({Object? tag}) => _DownloadSource(this, tag);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _bytes = Uint8List(0);
    _end = null;
    // A download still under way closes it when its write ends ([_run]).
    if (_done || _error != null) unawaited(_close());
    if (!_playing.isCompleted) _playing.complete();
    _notify();
  }
}

class _DownloadSource extends StreamAudioSource {
  _DownloadSource(this.download, Object? tag) : super(tag: tag);
  final MergedDownload download;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    download.play();
    await download.sized.timeout(const Duration(seconds: 30));
    final total = download.total!;
    final from = (start ?? 0).clamp(0, total);
    final to = (end ?? total).clamp(from, total);
    return StreamAudioResponse(
      sourceLength: total,
      contentLength: to - from,
      offset: from,
      contentType: 'audio/flac',
      // Seeking works: what is fetched plays at once, and the rest as soon as it comes.
      rangeRequestsSupported: true,
      stream: download.read(from, to),
    );
  }
}
