import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

/// Bounds external extractor processes shared by playback and format lookups.
/// Their heaps belong to child processes, outside the app's Dart/image caches.
class LookupProcessRunner {
  LookupProcessRunner({this.maxConcurrent = 2, Future<ProcessResult> Function(String, List<String>)? execute})
    : assert(maxConcurrent > 0),
      _execute = execute ?? _start;

  final int maxConcurrent;
  final Future<ProcessResult> Function(String, List<String>) _execute;
  final _waiting = Queue<Completer<void>>();
  int _running = 0;

  static Future<ProcessResult> _start(String executable, List<String> arguments) =>
      Process.run(executable, arguments, stdoutEncoding: utf8, stderrEncoding: utf8);

  Future<ProcessResult> run(String executable, List<String> arguments) async {
    if (_running < maxConcurrent) {
      _running++;
    } else {
      final ready = Completer<void>();
      _waiting.add(ready);
      await ready.future;
    }
    try {
      return await _execute(executable, arguments);
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _running--;
      }
    }
  }
}
