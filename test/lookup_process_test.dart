import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/lookup_process.dart';

void main() {
  test('bursts of format lookups start only two external processes at a time', () async {
    final started = <int>[];
    final exits = List.generate(8, (_) => Completer<ProcessResult>());
    var active = 0, peak = 0;
    final runner = LookupProcessRunner(
      execute: (exe, args) async {
        expect(exe, 'yt-dlp');
        final id = int.parse(args.single);
        started.add(id);
        active++;
        if (active > peak) peak = active;
        try {
          return await exits[id].future;
        } finally {
          active--;
        }
      },
    );
    final work = [
      for (var i = 0; i < exits.length; i++) runner.run('yt-dlp', ['$i']),
    ];
    await Future<void>.delayed(Duration.zero);
    expect(started, [0, 1]);
    for (var i = 0; i < exits.length; i++) {
      expect(started, contains(i));
      exits[i].complete(ProcessResult(i, 0, 'result $i', ''));
      await Future<void>.delayed(Duration.zero);
    }
    final results = await Future.wait(work);
    expect(peak, 2);
    expect(active, 0);
    expect(started, List.generate(8, (i) => i));
    expect(results.map((r) => r.stdout), List.generate(8, (i) => 'result $i'));
  });

  test('a failed process releases its slot for queued playback lookups', () async {
    final first = Completer<ProcessResult>();
    var starts = 0;
    final runner = LookupProcessRunner(
      maxConcurrent: 1,
      execute: (_, _) {
        starts++;
        return starts == 1 ? first.future : Future.value(ProcessResult(2, 0, 'next', ''));
      },
    );
    final failed = expectLater(runner.run('yt-dlp', ['first']), throwsStateError);
    final next = runner.run('yt-dlp', ['next']);
    expect(starts, 1);
    first.completeError(StateError('failed to launch'));
    await failed;
    expect((await next).stdout, 'next');
    expect(starts, 2);
  });
}
