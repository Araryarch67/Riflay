import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/audio_stream_cache.dart';

Future<void> until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue);
}

void main() {
  test('a fully consumed audio stream releases cancellation callbacks', () async {
    late StreamCancellation cancellation;
    var released = false;
    final stream = cancellableAudio((signal) {
      cancellation = signal;
      signal.whenCancelled.then((_) => released = true);
      return Stream.value([1, 2, 3]);
    });
    expect(await stream.expand((chunk) => chunk).toList(), [1, 2, 3]);
    expect(cancellation.cancelled, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(released, isTrue);
  });

  late Directory dir;
  late AudioStreamCache<String> cache;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('riflay-cache-test');
    cache = AudioStreamCache<String>(maxBytes: 100, maxSongBytes: 80, directory: () async => dir);
  });
  tearDown(() async {
    await cache.clear();
  });

  test('a single progressive download feeds playback and replays offline', () async {
    final network = StreamController<List<int>>();
    var downloads = 0;
    final first = await cache.open(
      'song',
      metadata: 'opus',
      length: 6,
      download: (_, _) {
        downloads++;
        return network.stream;
      },
    );
    final second = await cache.open(
      'song',
      metadata: 'opus',
      length: 6,
      download: (_, _) => throw StateError('duplicate download'),
    );
    expect(identical(first, second), isTrue);
    final received = <int>[];
    var ended = false;
    final sub = first!.read(0, 6).listen(received.addAll, onDone: () => ended = true);
    printOnFailure('cache phase: first bytes');
    network.add([1, 2, 3]);
    await until(() => received.length == 3);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(ended, isFalse, reason: 'an offline gap must stay buffering, not become EOF');
    network.add([4, 5, 6]);
    printOnFailure('cache phase: closing network');
    await network.close();
    await until(() => ended);
    expect(received, [1, 2, 3, 4, 5, 6]);
    printOnFailure('cache phase: offline replay');
    final replay = await first.read(1, 5).expand((bytes) => bytes).toList();
    expect(replay, [2, 3, 4, 5]);
    expect(downloads, 1);
    await sub.cancel();
    cache.retain({});
    printOnFailure('cache phase: deletion');
    await first.deleted;
    expect(await first.file.exists(), isFalse, reason: 'the song is deleted after it leaves the queue');
  });

  test('concurrent downloads cannot exceed the disk budget', () async {
    Stream<List<int>> bytes(Future<void> _, int _) => Stream.value(List.filled(60, 1));
    final results = await Future.wait([
      cache.open('one', metadata: 'one', length: 60, download: bytes),
      cache.open('two', metadata: 'two', length: 60, download: bytes),
    ]);
    expect(results.whereType<CachedAudio<String>>(), hasLength(1));
    expect(await cache.open('huge', metadata: 'huge', length: 81, download: bytes), isNull);
  });

  test('a dropped download resumes where it stopped, so the song keeps buffering instead of ending', () async {
    final starts = <int>[];
    final entry = await cache.open(
      'flaky',
      metadata: 'opus',
      length: 6,
      download: (_, from) async* {
        starts.add(from);
        yield [for (var i = from; i < from + 2; i++) i];
        if (from + 2 < 6) throw const SocketException('connection dropped');
      },
    );
    expect(await entry!.read(0, 6).expand((bytes) => bytes).toList(), [0, 1, 2, 3, 4, 5]);
    expect(starts, [0, 2, 4]);
  });

  test('a long song that drops many times keeps resuming as long as each try brings bytes', () async {
    var tries = 0;
    final entry = await cache.open(
      'long',
      metadata: 'opus',
      length: 10,
      download: (_, from) async* {
        tries++;
        yield [from];
        if (from + 1 < 10) throw const SocketException('connection dropped');
      },
    );
    expect(await entry!.read(0, 10).expand((bytes) => bytes).toList(), List.generate(10, (i) => i));
    expect(tries, greaterThan(CachedAudio.maxResumes + 1));
  });

  test('a download that gave up is started over by the next play, not failed for the rest of the session', () async {
    var downloads = 0;
    Stream<List<int>> offline(Future<void> _, int _) async* {
      downloads++;
      throw const SocketException('offline');
    }

    final broken = await cache.open('song', metadata: 'opus', length: 3, download: offline);
    await expectLater(broken!.read(0, 3).toList(), throwsA(isA<SocketException>()));
    expect(downloads, CachedAudio.maxResumes + 1, reason: 'resuming is bounded');
    expect(cache.find('song'), isNull);
    final fresh = await cache.open(
      'song',
      metadata: 'opus',
      length: 3,
      download: (_, from) => Stream.value([1, 2, 3].sublist(from)),
    );
    expect(identical(fresh, broken), isFalse);
    expect(await fresh!.read(0, 3).expand((bytes) => bytes).toList(), [1, 2, 3]);
  });

  test('leaving an offline song cancels its reader and background request', () async {
    var cancelled = false;
    final entry = await cache.open(
      'offline',
      metadata: 'offline',
      length: 10,
      download: (abort, _) async* {
        await abort;
        cancelled = true;
      },
    );
    final sub = entry!.read(0, 10).listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    cache.retain({});
    await sub.cancel().timeout(const Duration(seconds: 1));
    await entry.deleted.timeout(const Duration(seconds: 1));
    expect(cancelled, isTrue);
    expect(await entry.file.exists(), isFalse);
  });
}
