import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A cancellation signal shared by a reader, its retries and HTTP requests.
class StreamCancellation {
  final _done = Completer<void>();
  bool get cancelled => _done.isCompleted;
  Future<void> get whenCancelled => _done.future;
  void cancel() {
    if (!cancelled) _done.complete();
  }

  Future<void> wait(Duration delay) async {
    final wake = Completer<void>();
    final timer = Timer(delay, wake.complete);
    try {
      await Future.any([wake.future, whenCancelled]);
    } finally {
      timer.cancel();
    }
  }
}

/// Unlike an async* awaiting a retry, this cancels immediately when its reader leaves.
Stream<List<int>> cancellableAudio(Stream<List<int>> Function(StreamCancellation) create) {
  final cancellation = StreamCancellation();
  StreamSubscription<List<int>>? subscription;
  var finished = false;
  late final StreamController<List<int>> output;
  output = StreamController<List<int>>(
    onListen: () {
      subscription = create(cancellation).listen(
        output.add,
        onError: output.addError,
        onDone: () {
          finished = true;
          output.close();
        },
      );
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () {
      cancellation.cancel();
      return finished ? null : subscription?.cancel();
    },
  );
  return output.stream;
}

/// Session-only disk cache. One download feeds every reader; only complete-file
/// prefixes are exposed, so a network interruption stays buffering, not EOF.
class AudioStreamCache<T> {
  AudioStreamCache({this.maxBytes = 64 << 20, this.maxSongBytes = 32 << 20, Future<Directory> Function()? directory})
    : _directory = directory ?? _temporary;
  final int maxBytes;
  final int maxSongBytes;
  final Future<Directory> Function() _directory;
  Future<Directory>? _folder;
  final _entries = <String, CachedAudio<T>>{};
  final _opening = <String, Future<CachedAudio<T>?>>{};
  final _all = <CachedAudio<T>>{};
  Set<String>? _wanted;
  int _serial = 0;
  int _reserved = 0;

  static Future<Directory> _temporary() async =>
      Directory((await getTemporaryDirectory()).path).createTemp('riflay-stream-');

  CachedAudio<T>? find(String key) => _entries[key];

  Future<CachedAudio<T>?> open(
    String key, {
    required T metadata,
    required int length,
    required Stream<List<int>> Function(Future<void> cancelled) download,
  }) {
    if (_entries[key] case final entry?) return Future.value(entry);
    if (length <= 0 || length > maxSongBytes || (_wanted != null && !_wanted!.contains(key))) return Future.value();
    return _opening[key] ??= _open(key, metadata, length, download).whenComplete(() {
      _opening.remove(key);
    });
  }

  Future<CachedAudio<T>?> _open(
    String key,
    T metadata,
    int length,
    Stream<List<int>> Function(Future<void>) download,
  ) async {
    final folder = await (_folder ??= _directory());
    if (_wanted != null && !_wanted!.contains(key)) return null;
    if (_reserved + length > maxBytes) return null;
    _reserved += length;
    final File file;
    try {
      file = await File('${folder.path}/song-${_serial++}').create();
    } catch (_) {
      _reserved -= length;
      rethrow;
    }
    final entry = CachedAudio<T>._(file, length, metadata, download, () {});
    entry._onDeleted = () {
      _all.remove(entry);
      _reserved -= length;
    };
    _entries[key] = entry;
    _all.add(entry);
    entry._done = entry._write();
    if (_wanted != null && !_wanted!.contains(key)) {
      _entries.remove(key);
      entry.retire();
      return null;
    }
    return entry;
  }

  /// Retires completed/abandoned songs as the queue moves. Active readers finish
  /// or cancel first, so a crossfade/seek cannot read a file while it is deleted.
  void retain(Set<String> keys) {
    _wanted = Set.of(keys);
    for (final key in _entries.keys.where((key) => !keys.contains(key)).toList()) {
      _entries.remove(key)!.retire();
    }
  }

  Future<void> clear() async {
    await Future.wait(_opening.values.toList());
    retain({});
    await Future.wait(_all.toList().map((entry) => entry.deleted));
    final folder = await _folder;
    if (folder != null && await folder.exists()) await folder.delete();
    _folder = null;
    _wanted = null;
  }
}

class CachedAudio<T> {
  CachedAudio._(this.file, this.length, this.metadata, this._download, this._onDeleted);
  final File file;
  final int length;
  final T metadata;
  final Stream<List<int>> Function(Future<void>) _download;
  void Function() _onDeleted;
  final _abort = Completer<void>();
  final _deleted = Completer<void>();
  late Future<void> _done;
  Completer<void> _changed = Completer<void>();
  int available = 0;
  int _readers = 0;
  bool complete = false;
  bool _retired = false;
  bool _deleting = false;
  Object? _error;
  Future<void> get deleted => _deleted.future;

  void _notify() {
    final changed = _changed;
    _changed = Completer<void>();
    changed.complete();
  }

  Future<void> _write() async {
    RandomAccessFile? writer;
    try {
      writer = await file.open(mode: FileMode.write);
      await for (final bytes in _download(_abort.future)) {
        if (_abort.isCompleted) break;
        final remaining = length - available;
        if (bytes.length > remaining) throw StateError('Audio exceeds its advertised length');
        await writer.writeFrom(bytes);
        available += bytes.length;
        _notify();
      }
      if (!_abort.isCompleted && available != length) throw StateError('Audio ended before its advertised length');
      complete = available == length;
    } catch (e) {
      _error = e;
    } finally {
      await writer?.close();
      _notify();
    }
  }

  Stream<List<int>> read(int from, int to) => cancellableAudio((cancel) async* {
    _readers++;
    RandomAccessFile? reader;
    try {
      reader = await file.open();
      var position = from;
      while (position < to && !cancel.cancelled) {
        if (position >= available) {
          if (_error case final error?) throw error;
          if (complete) break;
          await Future.any([_changed.future, cancel.whenCancelled]);
          continue;
        }
        await reader.setPosition(position);
        final end = available < to ? available : to;
        final bytes = await reader.read((end - position).clamp(0, 64 << 10));
        if (bytes.isEmpty) throw StateError('Cached audio could not be read');
        position += bytes.length;
        yield bytes;
      }
    } finally {
      await reader?.close();
      _readers--;
      _disposeWhenUnused();
    }
  });

  void retire() {
    _retired = true;
    _disposeWhenUnused();
  }

  void _disposeWhenUnused() {
    if (!_retired || _readers != 0 || _deleting) return;
    _deleting = true;
    if (!_abort.isCompleted) _abort.complete();
    () async {
      try {
        await _done;
        if (await file.exists()) await file.delete();
      } finally {
        _onDeleted();
        if (!_deleted.isCompleted) _deleted.complete();
      }
    }();
  }
}
