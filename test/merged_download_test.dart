import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riflay/services/merged_download.dart';

void main() {
  tearDown(MergedDownload.forgetAll);

  final file = List<int>.generate(1000, (i) => i % 251);

  http.StreamedResponse part(int from, int to) => http.StreamedResponse(
    Stream.value(file.sublist(from, to)),
    206,
    contentLength: to - from,
    headers: {'content-range': 'bytes $from-${file.length - 1}/${file.length}'},
  );

  test('a dropped connection carries on from the byte it had reached', () async {
    final ranges = <String>[];
    final client = MockClient.streaming((request, _) async {
      ranges.add(request.headers['Range']!);
      if (ranges.length == 1) {
        // 400 bytes, then the connection drops.
        final drop = StreamController<List<int>>();
        drop.add(file.sublist(0, 400));
        unawaited(Future<void>.delayed(Duration.zero, () => drop.addError(http.ClientException('reset'))));
        return http.StreamedResponse(
          drop.stream,
          206,
          contentLength: 1000,
          headers: {'content-range': 'bytes 0-999/1000'},
        );
      }
      return part(400, 1000);
    });
    final download = MergedDownload.of('https://tracks.example/drop', client: client);
    final read = <int>[];
    await for (final chunk in download.read(0, 1000)) {
      read.addAll(chunk);
    }
    expect(read, file);
    expect(ranges, ['bytes=0-', 'bytes=400-']);
    expect(download.received, 1000);
  });

  test('too many requests waits as long as the server asks, then carries on', () async {
    final asked = <DateTime>[];
    final client = MockClient.streaming((request, _) async {
      asked.add(DateTime.now());
      if (asked.length == 1) {
        return http.StreamedResponse(const Stream.empty(), 429, headers: {'retry-after': '1'});
      }
      return part(0, 1000);
    });
    final download = MergedDownload.of('https://tracks.example/busy', client: client);
    final read = <int>[];
    await for (final chunk in download.read(0, 1000)) {
      read.addAll(chunk);
    }
    expect(read, file);
    expect(asked, hasLength(2));
    expect(asked[1].difference(asked[0]), greaterThanOrEqualTo(const Duration(milliseconds: 950)));
  });

  test('a read waits for bytes that are on their way', () async {
    final rest = Completer<void>();
    final client = MockClient.streaming((request, _) async {
      final body = StreamController<List<int>>();
      body.add(file.sublist(0, 250));
      unawaited(
        rest.future.then((_) {
          body.add(file.sublist(250));
          return body.close();
        }),
      );
      return http.StreamedResponse(body.stream, 206, headers: {'content-range': 'bytes 0-999/1000'});
    });
    final download = MergedDownload.of('https://tracks.example/slow', client: client);
    await download.sized;
    // Written to its file first: that takes a moment.
    for (var i = 0; i < 200 && !download.covers(250); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(download.covers(250), isTrue);
    expect(download.covers(251), isFalse);
    final reading = download.read(200, 600).fold<int>(0, (n, chunk) => n + chunk.length);
    rest.complete();
    expect(await reading, 400);
    expect(download.covers(1000), isTrue);
  });

  test('the file end is fetched on its own, so a decoder reading it first is answered at once', () async {
    final big = List<int>.generate(5 << 20, (i) => i % 253);
    final ranges = <String>[];
    final hold = Completer<void>();
    final client = MockClient.streaming((request, _) async {
      final range = request.headers['Range']!;
      ranges.add(range);
      final from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)![1]!);
      // The download from the start sends its first bytes, then waits; the end comes at once.
      final body = StreamController<List<int>>();
      body.add(big.sublist(from, from == 0 ? 1000 : big.length));
      if (from == 0) {
        unawaited(hold.future.then((_) => body.close()));
      } else {
        unawaited(body.close());
      }
      return http.StreamedResponse(
        body.stream,
        206,
        headers: {'content-range': 'bytes $from-${big.length - 1}/${big.length}'},
      );
    });
    final download = MergedDownload.of('https://tracks.example/big', client: client)..play();
    final end = await download
        .read(big.length - 100, big.length)
        .fold<List<int>>([], (all, chunk) => all..addAll(chunk))
        .timeout(const Duration(seconds: 5));
    expect(end, big.sublist(big.length - 100));
    expect(ranges, containsAll(['bytes=0-', 'bytes=${big.length - (1 << 20)}-']));
    hold.complete();
  });

  test('a song got ready ahead fetches only its start, and the rest once it plays', () async {
    final big = List<int>.generate(MergedDownload.readyBytes * 3, (i) => i % 241);
    final ranges = <String>[];
    final client = MockClient.streaming((request, _) async {
      final range = request.headers['Range']!;
      ranges.add(range);
      final from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)![1]!);
      // Sent in small pieces, as a network does: the download stops reading once it has its start.
      final pieces = [
        for (var at = from; at < big.length; at += 64 << 10) big.sublist(at, math.min(at + (64 << 10), big.length)),
      ];
      return http.StreamedResponse(
        Stream.fromIterable(pieces),
        206,
        headers: {'content-range': 'bytes $from-${big.length - 1}/${big.length}'},
      );
    });
    final download = MergedDownload.of('https://tracks.example/ahead', client: client);
    await download.head(4);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(download.received, lessThan(MergedDownload.readyBytes + (64 << 10)), reason: 'only its start');
    expect(download.done, isFalse);
    download.play();
    final all = await download.read(0, big.length).fold<int>(0, (n, chunk) => n + chunk.length);
    expect(all, big.length);
    expect(ranges.first, 'bytes=0-');
    expect(ranges, contains('bytes=${MergedDownload.readyBytes}-'), reason: 'the rest, from where the start ended');
    expect(ranges, contains('bytes=${big.length - (1 << 20)}-'), reason: 'and the file end, for seeking');
  });

  test('a download being played from is never let go for newer ones', () async {
    final client = MockClient.streaming((request, _) async {
      // Half the file, then nothing more for now: a player reading it waits.
      final body = StreamController<List<int>>()..add(file.sublist(0, 500));
      return http.StreamedResponse(body.stream, 206, headers: {'content-range': 'bytes 0-999/1000'});
    });
    final playing = MergedDownload.of('https://tracks.example/playing', client: client);
    final reading = playing.read(0, 1000).listen((_) {});
    // Not awaited: a read left waiting ends only when the player lets go of it (as just_audio's proxy does).
    addTearDown(() => unawaited(reading.cancel()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    for (var i = 0; i < 10; i++) {
      MergedDownload.of('https://tracks.example/other$i', client: client);
    }
    expect(identical(MergedDownload.existing('https://tracks.example/playing'), playing), isTrue);
    expect(MergedDownload.existing('https://tracks.example/other0'), isNull, reason: 'the oldest idle one went');
  });

  test('the same address is fetched once', () {
    var asked = 0;
    final client = MockClient.streaming((request, _) async {
      asked++;
      return part(0, 1000);
    });
    final a = MergedDownload.of('https://tracks.example/once', client: client);
    final b = MergedDownload.of('https://tracks.example/once', client: client);
    expect(identical(a, b), isTrue);
    // The request goes once its file is made.
    return Future<void>.delayed(const Duration(milliseconds: 300), () => expect(asked, 1));
  });
}
