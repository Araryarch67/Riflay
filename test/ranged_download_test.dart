import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/ranged_download.dart';

/// A local server with Range support that records every range asked for, and can drop connections.
class _Server {
  _Server(this.data);

  final Uint8List data;
  final ranges = <int>[]; // start offsets requested
  late HttpServer http;

  /// Requests (counted from 1) to cut off halfway: the connection closes after a few bytes.
  bool Function(int n)? dropIf;
  int count = 0;

  Uri get url => Uri.parse('http://127.0.0.1:${http.port}/a.webm');

  Future<void> start() async {
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    http.listen((req) async {
      final n = ++count;
      final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(req.headers.value('range') ?? '');
      final start = int.parse(m!.group(1)!);
      final end = min(int.parse(m.group(2)!), data.length - 1);
      ranges.add(start);
      if (dropIf?.call(n) ?? false) {
        // Raw reply with a promised length, then the connection dies after ten bytes.
        final socket = await req.response.detachSocket(writeHeaders: false);
        socket.add(
          'HTTP/1.1 206 Partial Content\r\ncontent-range: bytes $start-$end/${data.length}\r\n'
                  'content-length: ${end - start + 1}\r\n\r\n'
              .codeUnits,
        );
        socket.add(data.sublist(start, start + 10));
        await socket.flush();
        socket.destroy();
        return;
      }
      final res = req.response
        ..statusCode = 206
        ..headers.set('content-range', 'bytes $start-$end/${data.length}')
        ..contentLength = end - start + 1;
      res.add(data.sublist(start, end + 1));
      await res.close();
    });
  }

  Future<void> stop() => http.close(force: true);
}

void main() {
  const chunk = 1000;
  final data = Uint8List.fromList([for (var i = 0; i < 10500; i++) (i * 31 + i ~/ 256) & 0xFF]); // 11 chunks
  late Directory dir;
  late File out;
  late _Server server;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ranged');
    out = File('${dir.path}/a.webm.part');
    server = _Server(data);
    await server.start();
  });
  tearDown(() async {
    await server.stop();
    await dir.delete(recursive: true);
  });

  Future<void> run({
    bool resume = false,
    String? tag = '251',
    int? total,
    bool Function()? cancel,
    void Function(int, int)? progress,
  }) => rangedDownload(
    url: server.url,
    out: out,
    totalBytes: total ?? data.length,
    chunkSize: chunk,
    workers: 3,
    resume: resume,
    tag: tag,
    stateInterval: Duration.zero,
    retryDelay: const Duration(milliseconds: 1),
    isCancelled: cancel,
    onProgress: progress,
  );

  /// Cancels after [n] chunks have been fetched.
  bool Function() cancelAfter(int n) =>
      () => server.ranges.length >= n;

  test('a plain download writes every byte and leaves no state', () async {
    await run();
    expect(out.readAsBytesSync(), data);
    expect(stateFileOf(out).existsSync(), isFalse);
  });

  test('the length is probed when not given', () async {
    await rangedDownload(url: server.url, out: out, chunkSize: chunk);
    expect(out.readAsBytesSync(), data);
  });

  test('an interrupted download continues with only the missing chunks', () async {
    await expectLater(run(cancel: cancelAfter(5)), throwsA(isA<DownloadCancelled>()));
    expect(stateFileOf(out).existsSync(), isTrue);
    final kept = await partialBytes(out);
    expect(kept, greaterThan(0));
    expect(kept, lessThan(data.length));

    final firstRun = server.ranges.toSet();
    server.ranges.clear();
    final seen = <int>[];
    await run(resume: true, progress: (r, t) => seen.add(r));
    expect(out.readAsBytesSync(), data);
    expect(stateFileOf(out).existsSync(), isFalse);
    // Progress starts from what was already there, and nothing finished is fetched again.
    expect(seen.first, greaterThanOrEqualTo(kept));
    expect(seen.last, data.length);
    expect(server.ranges.length, lessThan(11));
    expect(server.ranges.length + kept ~/ chunk + ((kept % chunk) == 0 ? 0 : 1), greaterThanOrEqualTo(11));
    expect(firstRun.length, greaterThanOrEqualTo(5));
  });

  test('connections cut off mid-chunk are retried', () async {
    server.dropIf = (n) => n == 2 || n == 3 || n == 7;
    await run();
    expect(out.readAsBytesSync(), data);
    expect(server.count, greaterThan(11));
  });

  test('a server that keeps failing ends the run but keeps the state; a later run finishes', () async {
    server.dropIf = (n) => n > 4;
    await expectLater(run(), throwsA(anything));
    expect(await partialBytes(out), greaterThan(0));
    server.dropIf = null;
    server.ranges.clear();
    await run(resume: true);
    expect(out.readAsBytesSync(), data);
    expect(server.ranges.length, lessThan(11));
  });

  test('another tag or size starts again', () async {
    await expectLater(run(cancel: cancelAfter(5)), throwsA(isA<DownloadCancelled>()));
    server.ranges.clear();
    await run(resume: true, tag: '140');
    expect(out.readAsBytesSync(), data);
    expect(server.ranges.toSet().length, 11);
  });

  test('a different length starts again', () async {
    await expectLater(run(cancel: cancelAfter(5)), throwsA(isA<DownloadCancelled>()));
    final shorter = Uint8List.sublistView(data, 0, 9000);
    final s2 = _Server(shorter);
    await s2.start();
    addTearDown(s2.stop);
    await rangedDownload(
      url: s2.url,
      out: out,
      totalBytes: 9000,
      chunkSize: chunk,
      resume: true,
      tag: '251',
      retryDelay: const Duration(milliseconds: 1),
    );
    expect(out.readAsBytesSync(), shorter);
    expect(s2.ranges.toSet().length, 9);
  });

  for (final (name, damage) in <(String, void Function())>[
    ('garbage state', () => stateFileOf(out).writeAsStringSync('not json')),
    ('truncated state', () => stateFileOf(out).writeAsStringSync('{"v":1,"total":10500')),
    (
      'state with the wrong shape',
      () => stateFileOf(out).writeAsStringSync('{"v":1,"total":10500,"chunk":1000,"n":11,"bits":"AA=="}'),
    ),
    ('missing state', () => stateFileOf(out).deleteSync()),
    ('a part file of the wrong length', () => out.writeAsBytesSync([1, 2, 3])),
  ]) {
    test('$name starts clean', () async {
      await expectLater(run(cancel: cancelAfter(5)), throwsA(isA<DownloadCancelled>()));
      damage();
      expect(await partialBytes(out), 0);
      server.ranges.clear();
      await run(resume: true);
      expect(out.readAsBytesSync(), data);
      expect(server.ranges.toSet().length, 11);
    });
  }

  test('discardPartial removes the file and its state', () async {
    await expectLater(run(cancel: cancelAfter(5)), throwsA(isA<DownloadCancelled>()));
    discardPartial(out);
    expect(out.existsSync(), isFalse);
    expect(stateFileOf(out).existsSync(), isFalse);
  });

  test('without resume an old partial is overwritten', () async {
    await expectLater(run(cancel: cancelAfter(5)), throwsA(isA<DownloadCancelled>()));
    server.ranges.clear();
    await run();
    expect(out.readAsBytesSync(), data);
    expect(server.ranges.toSet().length, 11);
  });
}
