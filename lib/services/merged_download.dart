// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

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
    for (final d in _all.values) {
      d.dispose();
    }
    _all.clear();
  }

  final String url;
  final http.Client? _client;

  /// What has come, from the file's start; grown as more comes (a song got ready ahead holds only its start).
  Uint8List _bytes = Uint8List(0);
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
    try {
      while (!_disposed && !_done) {
        if (_limit case final limit? when _received >= limit) await _playing.future;
        if (_disposed) return;
        try {
          final request = http.Request('GET', Uri.parse(url))
            ..headers['User-Agent'] = 'Riflay'
            ..headers['Range'] = 'bytes=$_received-';
          final response = await client.send(request).timeout(_silence);
          if (_disposed) return;
          final status = response.statusCode;
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
            _grow(end);
            _bytes.setRange(at, end, chunk);
            at = end;
            // Bytes already had (a whole file sent again) don't count twice.
            if (at > _received) {
              _received = at;
              _lastProgress = DateTime.now();
              failures = 0;
              _notify();
            }
            // Got ready ahead: the start is here, the connection is let go until the song plays.
            if (_limit case final limit? when _received >= limit) break;
          }
          if (_received >= total) {
            _done = true;
            _notify();
          }
        } catch (e) {
          if (_disposed) return;
          if (++failures > _tries) rethrow;
          debugPrint('Smart merge download: ${e.runtimeType}, again from byte $_received ($failures)');
          await Future<void>.delayed(Duration(milliseconds: math.min(5000, 500 * failures)));
        }
      }
    } catch (e) {
      _error = e;
      if (!_sized.isCompleted) _sized.completeError(e);
      _notify();
    } finally {
      if (_client == null) client.close();
    }
  }

  void _size(int? length) {
    if (_total != null || length == null || length <= 0) return;
    _total = length;
    if (!_sized.isCompleted) _sized.complete();
    if (_playing.isCompleted && length > 4 * _endSize) unawaited(_fetchEnd(length));
  }

  /// Room for the first [bytes]: doubled as it fills, the whole file once it is played.
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
          final response = await client.send(request).timeout(_silence);
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
    return Uint8List.sublistView(_bytes, 0, math.min(count, _received));
  }

  /// Bytes [start] to [end] (exclusive), each as soon as it is here.
  ///
  /// A download that failed or was let go leaves the read waiting, not ended: just_audio's proxy reports a short
  /// answer as an error nobody catches. The player gives up on it itself, and Smart merge's watch takes the song
  /// back to its own sound.
  Stream<List<int>> read(int start, int end) async* {
    _readers++;
    try {
      await sized;
      var at = start;
      while (at < end) {
        if (_disposed) await Completer<void>().future;
        if (at < _received) {
          final upTo = math.min(end, _received);
          // A copy: the player may hold on to it after this download is let go.
          yield Uint8List.fromList(Uint8List.sublistView(_bytes, at, upTo));
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
    }
  }

  /// The download as something to play, each byte as soon as it is here. Playing it fetches the whole file.
  StreamAudioSource source({Object? tag}) => _DownloadSource(this, tag);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _bytes = Uint8List(0);
    _end = null;
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
