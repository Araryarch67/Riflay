// StreamAudioSource/Response are just_audio's documented way to feed custom byte streams;
// they are flagged experimental but stable across 0.9-0.10.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'audio_stream_cache.dart';
import 'youtube_importer.dart';
import 'youtube_stream.dart';
import 'ytdlp.dart';

/// How a YouTube song is being streamed, for Detail stats.
class StreamStats {
  /// What YouTube serves for it (null until resolved).
  ResolvedAudio? stream;

  /// Bytes received from YouTube for this song so far, the preloaded start included.
  int received = 0;

  /// Speed of the latest request, in bits per second. Time spent waiting for
  /// the player to read is left out, so this is the connection's speed.
  double? bitsPerSecond;

  void _count(int bytes, Duration took) {
    // A short read (the end of the file, a seek) says little about the connection.
    if (bytes >= 64 << 10 && took > Duration.zero) bitsPerSecond = bytes * 8 / (took.inMicroseconds / 1e6);
  }
}

/// Streams a YouTube video's audio track without downloading it first.
///
/// Stream URLs expire after a few hours, so nothing is resolved until the
/// player actually asks for bytes; a whole playlist can be queued up front.
/// Byte ranges are fetched in chunks because googlevideo rejects very large
/// single ranges.
class YoutubeAudioSource extends StreamAudioSource {
  YoutubeAudioSource(
    this.videoId, {
    required this.yt,
    this.aac = false,
    super.tag,
    this.client,
    this.resolveAudio,
    this.cacheAudio = true,
  });

  @visibleForTesting
  final http.Client? client;
  @visibleForTesting
  final Future<ResolvedAudio> Function()? resolveAudio;

  final bool cacheAudio;
  static final _cache = AudioStreamCache<ResolvedAudio>();

  static String _key(String id, bool aac) => aac ? 'aac:$id' : id;
  static void retainCache(Set<String> ids) => _cache.retain({
    for (final id in ids) ...[id, 'aac:$id'],
  });
  static Future<void> clearCache() => _cache.clear();
  @visibleForTesting
  static bool cacheCompleteFor(String id) => _cache.find(id)?.complete ?? false;

  static const _chunkSize = 1 << 20;
  static const _maxFailedAttempts = 6;

  static final _preloads = <String, Future<void>>{};

  static final _stats = <String, StreamStats>{};

  /// How [videoId] is being streamed, if it has been this session.
  static StreamStats? statsOf(String videoId) => _stats[videoId];

  static StreamStats _statsFor(String videoId) {
    final s = _stats.remove(videoId) ?? StreamStats();
    _stats[videoId] = s; // newest last
    while (_stats.length > 8) {
      _stats.remove(_stats.keys.first);
    }
    return s;
  }

  /// Start one temporary background download of the next song. Playback reads
  /// that same growing file, so prefetch and playback never download it twice.
  static Future<void> preload(String videoId, {required YoutubeExplode yt}) {
    if (_cache.find(videoId) != null) return Future.value();
    return _preloads[videoId] ??= YoutubeAudioSource(videoId, yt: yt)._entry().then<void>((_) {}).whenComplete(() {
      _preloads.remove(videoId);
    });
  }

  Future<CachedAudio<ResolvedAudio>?> _entry() async {
    final key = _key(videoId, aac);
    if (_cache.find(key) case final entry?) return entry;
    final info = await _resolve();
    if (info.size == null) return null;
    try {
      return await _cache.open(
        key,
        metadata: info,
        length: info.size!,
        download: (cancelled) => _ranged(info, 0, info.size!, info.size!, aborted: cancelled),
      );
    } on FileSystemException catch (e) {
      debugPrint('Temporary audio cache unavailable: $e');
      return null;
    }
  }

  final String videoId;
  final YoutubeExplode yt;

  /// AAC instead of Opus (casting: most network players can't decode Opus).
  final bool aac;

  /// One connection pool for every song, not one per queued song that was
  /// never closed: a whole playlist is queued at once.
  static final _http = http.Client();

  /// YouTube's player API (yt-dlp on desktop if refused), with
  /// youtube_explode as a last resort on phones. Always has a size.
  Future<ResolvedAudio> _resolve() async => _statsFor(videoId).stream = await (resolveAudio?.call() ?? _find());

  Future<ResolvedAudio> _find() async {
    try {
      final r = await YoutubeStream.best(videoId, aac: aac);
      if ((r.size ?? 0) > 0) return r;
      if (YtDlp.supported) throw StateError('Unknown stream size for $videoId');
    } catch (e) {
      if (YtDlp.supported) rethrow;
      debugPrint('YouTube stream lookup failed, trying youtube_explode: $e');
    }
    final manifest = await yt.videos.streams.getManifest(videoId);
    final best = YoutubeImporter.pickBestAudio(manifest.audioOnly, aacOnly: aac);
    if (best == null) throw StateError('No audio stream for $videoId');
    return ResolvedAudio(
      url: best.url,
      formatId: '${best.tag}',
      ext: best.container == StreamContainer.webM ? 'webm' : 'm4a',
      codec: best.audioCodec,
      kbps: best.bitrate.kiloBitsPerSecond.round(),
      size: best.size.totalBytes,
      resolvedAt: DateTime.now(),
      via: 'youtube_explode',
    );
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final cached = cacheAudio ? await _entry() : null;
    final info = cached?.metadata ?? await _resolve();
    final total = info.size!;
    final from = start ?? 0;
    final to = (end ?? total).clamp(from, total);
    return StreamAudioResponse(
      sourceLength: total,
      contentLength: to - from,
      offset: from,
      contentType: info.mimeType,
      stream: cached != null && (cached.complete || from <= cached.available + _chunkSize)
          ? _fromCache(cached, info, from, to, total)
          : _ranged(info, from, to, total),
    );
  }

  Stream<List<int>> _fromCache(
    CachedAudio<ResolvedAudio> cached,
    ResolvedAudio info,
    int from,
    int to,
    int total,
  ) async* {
    var position = from;
    try {
      await for (final bytes in cached.read(from, to)) {
        position += bytes.length;
        yield bytes;
      }
    } on FileSystemException catch (e) {
      debugPrint('Audio cache read failed; resuming from network: $e');
      yield* _ranged(info, position, to, total);
    }
  }

  Future<http.StreamedResponse> _send(Uri uri, StreamCancellation cancel, {String? range}) async {
    final timeout = Completer<void>();
    final abort = Future.any([cancel.whenCancelled, timeout.future]);
    final request = http.AbortableRequest('GET', uri, abortTrigger: abort);
    if (range != null) request.headers['Range'] = range;
    return (client ?? _http)
        .send(request)
        .timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            if (!timeout.isCompleted) timeout.complete();
            throw TimeoutException('Timed out waiting for audio headers');
          },
        );
  }

  /// just_audio's proxy drops stream errors without a word (playback just
  /// stops), so say what went wrong here.
  Stream<List<int>> _ranged(ResolvedAudio info, int from, int to, int total, {Future<void>? aborted}) =>
      cancellableAudio((cancel) async* {
        aborted?.then((_) => cancel.cancel());
        try {
          yield* _fetchRange(info, from, to, total, cancel);
        } catch (e) {
          debugPrint('Audio stream failed: $videoId: ${e is http.ClientException ? e.message : e.runtimeType}');
          rethrow;
        }
      });

  Stream<List<int>> _fetchRange(ResolvedAudio info, int from, int to, int total, StreamCancellation cancel) async* {
    var source = info.url;
    var retried = false;
    var pos = from;
    var dropped = 0;
    final stats = _statsFor(videoId);
    while (pos < to && !cancel.cancelled) {
      final last = (pos + _chunkSize).clamp(0, to) - 1;
      final before = pos;
      try {
        // Runs only while waiting for the network, not while the player isn't reading.
        final took = Stopwatch()..start();
        var got = 0;
        final res = await _send(source, cancel, range: 'bytes=$pos-$last');
        if (res.statusCode != 200 && res.statusCode != 206) {
          await res.stream.drain<void>();
          if (res.statusCode == 408 || res.statusCode == 429 || res.statusCode >= 500) {
            throw http.ClientException('Temporary server response ${res.statusCode}', source);
          }
          // Usually an expired or throttled URL: resolve a fresh one and retry once.
          if (!retried) {
            retried = true;
            YoutubeStream.invalidateEverywhere(videoId);
            final ResolvedAudio refreshed;
            try {
              refreshed = await _resolve();
            } catch (_) {
              retried = false;
              throw http.ClientException('Temporary failure refreshing the stream URL', source);
            }
            // Resuming a different encoding mid-file corrupts the decoder's stream.
            if (refreshed.size != total || refreshed.formatId != info.formatId || refreshed.ext != info.ext) {
              throw const HttpException('The audio format changed while resuming');
            }
            source = refreshed.url;
            continue;
          }
          throw http.ClientException('HTTP ${res.statusCode}: YouTube rejected the refreshed audio stream', source);
        }
        if (res.statusCode == 206) {
          final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(res.headers['content-range'] ?? '');
          if (range == null ||
              int.parse(range[1]!) != pos ||
              int.parse(range[3]!) != total ||
              int.parse(range[2]!) < pos ||
              int.parse(range[2]!) >= total) {
            await res.stream.drain<void>();
            throw const HttpException('The server returned a different byte range');
          }
        }
        // A 200 response ignores Range and starts at byte zero. Discard its
        // prefix and stop at the requested end, rather than duplicate audio.
        var discard = res.statusCode == 200 ? pos : 0;
        await for (final bytes in res.stream.timeout(const Duration(seconds: 20))) {
          if (discard >= bytes.length) {
            discard -= bytes.length;
            continue;
          }
          final begin = discard;
          discard = 0;
          final length = (bytes.length - begin).clamp(0, last + 1 - pos);
          if (length == 0) break;
          final chunk = begin == 0 && length == bytes.length ? bytes : bytes.sublist(begin, begin + length);
          got += length;
          stats.received += length;
          pos += length;
          took.stop();
          yield chunk;
          took.start();
          if (pos > last) break;
        }
        stats._count(got, took.elapsed);
        // A response can end cleanly before the range is complete. Resume at
        // the last byte actually delivered; jumping to last + 1 drops audio.
        if (got == 0) throw http.ClientException('Empty audio response', source);
        dropped = 0;
        retried = false;
      } catch (e) {
        if (cancel.cancelled) return;
        if (e is http.ClientException && e.message.startsWith('HTTP ')) rethrow;
        if (e is! http.ClientException && e is! SocketException && e is! TimeoutException) rethrow;
        // Only consecutive attempts with no progress exhaust the retry budget.
        // Several short-lived connections can still deliver the complete song.
        if (pos > before) dropped = 0;
        dropped++;
        if (dropped >= _maxFailedAttempts) {
          throw http.ClientException('Audio connection failed after $dropped attempts without receiving data', source);
        }
        final delay = Duration(milliseconds: (300 * (1 << dropped.clamp(0, 5))).clamp(300, 8000));
        debugPrint(
          'Audio reconnect: $videoId at byte $pos (attempt $dropped): ${e is http.ClientException ? e.message : e.runtimeType}',
        );
        await cancel.wait(delay);
      }
    }
  }
}
