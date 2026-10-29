import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Downloads [url] into [out] over several parallel HTTP range requests, and can carry on after an interruption.
///
/// One googlevideo connection tops out around 3-6 MB/s and very large ranges
/// get rejected, so the file is split into small chunks that a few workers
/// pull from a shared queue. Each chunk is retried a few times before the
/// whole download fails.
///
/// Chunks land out of order in a preallocated file, so the file alone says nothing about what has arrived. A small
/// sidecar, `<out>.state` ([stateFileOf]), lists the finished chunks; it is rewritten (temp file + rename, after the
/// data is flushed) at most about once a second and when the download stops. With [resume] set, a file whose state
/// matches (same length, chunk size and [tag]) is continued and only the missing chunks are fetched; anything else
/// starts clean, so a damaged or foreign state can never produce a corrupt file. The state is removed on success.
/// A failure or a cancel leaves the file and its state in place; [discardPartial] removes them.
Future<void> rangedDownload({
  required Uri url,
  required File out,
  int? totalBytes,
  int workers = 4,
  int chunkSize = 1 << 20,
  Map<String, String> headers = const {},
  void Function(int received, int total)? onProgress,
  bool Function()? isCancelled,
  bool resume = false,
  String? tag,
  Duration stateInterval = const Duration(seconds: 1),
  Duration retryDelay = const Duration(milliseconds: 300),
}) async {
  final client = http.Client();
  try {
    final total = totalBytes ?? await _probeLength(client, url, headers);
    final chunks = (total + chunkSize - 1) ~/ chunkSize;
    final done = List<bool>.filled(chunks, false);

    var resuming = false;
    if (resume && total > 0) {
      final saved = await _readState(out);
      if (saved != null &&
          saved.total == total &&
          saved.chunkSize == chunkSize &&
          saved.tag == tag &&
          saved.done.length == chunks &&
          out.existsSync() &&
          out.lengthSync() == total) {
        for (var i = 0; i < chunks; i++) {
          done[i] = saved.done[i];
        }
        resuming = true;
      }
    }
    final stateFile = stateFileOf(out);
    if (!resuming) {
      if (stateFile.existsSync()) stateFile.deleteSync();
    }

    final raf = await out.open(mode: resuming ? FileMode.append : FileMode.write);
    Object? failure;
    StackTrace? failureTrace;
    try {
      if (!resuming) await raf.truncate(total);
      var received = 0;
      for (var i = 0; i < chunks; i++) {
        if (done[i]) received += _chunkLength(i, chunkSize, total);
      }
      if (received > 0) onProgress?.call(received, total);

      var cursor = 0;
      // RandomAccessFile allows one pending operation at a time; chain writes.
      var writes = Future<void>.value();
      var stateSaves = Future<void>.value();
      final clock = Stopwatch()..start();
      var lastSaved = Duration.zero;

      Future<void> saveState() {
        // The data first, so a chunk listed as done is really on disk.
        return stateSaves = stateSaves.then((_) async {
          try {
            // Flushed inside the write chain: a RandomAccessFile allows one operation at a time.
            await (writes = writes.then((_) => raf.flush()));
            await _writeState(out, total, chunkSize, tag, done);
          } catch (_) {
            // Not fatal: the next save, or a clean restart, covers it.
          }
        });
      }

      Future<void> worker() async {
        while (failure == null) {
          if (isCancelled?.call() ?? false) throw const _Cancelled();
          while (cursor < chunks && done[cursor]) {
            cursor++;
          }
          if (cursor >= chunks) return;
          final index = cursor++;
          final start = index * chunkSize;
          final end = start + _chunkLength(index, chunkSize, total) - 1;
          final bytes = await _fetchChunk(client, url, headers, start, end, retryDelay, isCancelled);
          writes = writes.then((_) async {
            await raf.setPosition(start);
            await raf.writeFrom(bytes);
            done[index] = true;
          });
          await writes;
          received += bytes.length;
          onProgress?.call(received, total);
          if (clock.elapsed - lastSaved >= stateInterval) {
            lastSaved = clock.elapsed;
            unawaited(saveState());
          }
        }
      }

      // Let every worker finish before the file closes, so none writes into a closed file.
      await Future.wait([
        for (var i = 0; i < workers; i++)
          worker().catchError((Object e, StackTrace s) {
            failure ??= e;
            failureTrace ??= s;
          }),
      ]);
      await stateSaves;
      await writes;
      if (failure == null && done.contains(false)) failure = StateError('Download incomplete');
      if (failure == null) {
        await raf.flush();
        if (await raf.length() != total) failure = StateError('Download has the wrong size');
      }
      if (failure != null) {
        // Keep what arrived for a later try.
        await saveState();
        await stateSaves;
      } else {
        await stateSaves;
      }
    } finally {
      await raf.close();
    }
    if (failure != null) {
      if (failure is _Cancelled) throw const DownloadCancelled();
      Error.throwWithStackTrace(failure!, failureTrace ?? StackTrace.current);
    }
    if (stateFile.existsSync()) stateFile.deleteSync();
  } finally {
    client.close();
  }
}

int _chunkLength(int index, int chunkSize, int total) {
  final start = index * chunkSize;
  return (start + chunkSize < total ? start + chunkSize : total) - start;
}

class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

class _Cancelled implements Exception {
  const _Cancelled();
}

/// The sidecar that records which chunks of [part] have arrived.
File stateFileOf(File part) => File('${part.path}.state');

/// Removes a partial download and its state.
void discardPartial(File part) {
  for (final f in [part, stateFileOf(part), File('${stateFileOf(part).path}.tmp')]) {
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}

/// How many bytes of [part] a resume would keep: 0 unless the file and a readable state agree with each other.
Future<int> partialBytes(File part, {int? chunkSize}) async {
  final s = await _readState(part);
  if (s == null || !part.existsSync() || part.lengthSync() != s.total) return 0;
  if (chunkSize != null && s.chunkSize != chunkSize) return 0;
  var n = 0;
  for (var i = 0; i < s.done.length; i++) {
    if (s.done[i]) n += _chunkLength(i, s.chunkSize, s.total);
  }
  return n;
}

class _State {
  _State(this.total, this.chunkSize, this.tag, this.done);
  final int total, chunkSize;
  final String? tag;
  final List<bool> done;
}

Future<void> _writeState(File out, int total, int chunkSize, String? tag, List<bool> done) async {
  final bits = List<int>.filled((done.length + 7) ~/ 8, 0);
  for (var i = 0; i < done.length; i++) {
    if (done[i]) bits[i >> 3] |= 1 << (i & 7);
  }
  final text = jsonEncode({
    'v': 1,
    'total': total,
    'chunk': chunkSize,
    'tag': tag,
    'n': done.length,
    'bits': base64.encode(bits),
  });
  final tmp = File('${stateFileOf(out).path}.tmp');
  await tmp.writeAsString(text, flush: true);
  await tmp.rename(stateFileOf(out).path);
}

Future<_State?> _readState(File out) async {
  try {
    final f = stateFileOf(out);
    if (!f.existsSync()) return null;
    final j = jsonDecode(await f.readAsString());
    if (j is! Map || j['v'] != 1) return null;
    final total = j['total'], chunk = j['chunk'], n = j['n'], bits = j['bits'];
    if (total is! int || chunk is! int || n is! int || bits is! String || total <= 0 || chunk <= 0) return null;
    if (n != (total + chunk - 1) ~/ chunk) return null;
    final raw = base64.decode(bits);
    if (raw.length != (n + 7) ~/ 8) return null;
    final tag = j['tag'];
    return _State(total, chunk, tag is String ? tag : null, [
      for (var i = 0; i < n; i++) raw[i >> 3] & (1 << (i & 7)) != 0,
    ]);
  } catch (_) {
    return null;
  }
}

Future<List<int>> _fetchChunk(
  http.Client client,
  Uri url,
  Map<String, String> headers,
  int start,
  int end,
  Duration retryDelay,
  bool Function()? isCancelled,
) async {
  Object? lastError;
  for (var attempt = 0; attempt < 4; attempt++) {
    if (isCancelled?.call() ?? false) throw const _Cancelled();
    try {
      final req = http.Request('GET', url)
        ..headers.addAll(headers)
        ..headers['Range'] = 'bytes=$start-$end';
      final res = await client.send(req).timeout(const Duration(seconds: 20));
      if (res.statusCode != 206 && res.statusCode != 200) {
        throw http.ClientException('HTTP ${res.statusCode}', url);
      }
      final body = await res.stream.toBytes().timeout(const Duration(seconds: 60));
      if (body.length != end - start + 1) throw http.ClientException('Short read', url);
      return body;
    } catch (e) {
      lastError = e;
      await Future<void>.delayed(retryDelay * (attempt + 1));
    }
  }
  throw lastError!;
}

Future<int> _probeLength(http.Client client, Uri url, Map<String, String> headers) async {
  final req = http.Request('GET', url)
    ..headers.addAll(headers)
    ..headers['Range'] = 'bytes=0-0';
  final res = await client.send(req);
  await res.stream.drain<void>();
  final range = res.headers['content-range']; // "bytes 0-0/12345"
  final total = int.tryParse(range?.split('/').last ?? '');
  if (total == null) throw http.ClientException('Server did not report a length', url);
  return total;
}
