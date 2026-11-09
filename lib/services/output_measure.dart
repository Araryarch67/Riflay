import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../platform/host.dart';
import 'audio_engine.dart';
import 'null_test.dart';
import 'pcm_decoder.dart';

/// Where a measurement is.
enum MeasureStage { recording, decoding, comparing }

/// Why a measurement gave nothing.
enum MeasureProblem {
  /// `pw-record` / `pw-dump` aren't there.
  noRecorder,

  /// PipeWire has no stream of Riflay's playing (paused, or the output goes straight to the card).
  noStream,

  /// More than one of Riflay's streams play (a crossfade): which one is the song is unclear.
  twoStreams,

  /// The song was paused, moved, or another one started while recording.
  songMoved,

  /// The song itself couldn't be decoded again.
  noSource,

  /// Nothing came out, or what did doesn't match the song.
  noMatch,
}

class MeasureFailure implements Exception {
  const MeasureFailure(this.problem);
  final MeasureProblem problem;

  @override
  String toString() => 'MeasureFailure($problem)';
}

/// A measurement and what it was taken from.
class OutputMeasurement {
  const OutputMeasurement(this.result, {required this.rate});
  final NullTestResult result;

  /// The rate PipeWire ran at, which the recording was taken at.
  final int rate;
}

/// Measures what Riflay really sends out: records a few seconds of its own PipeWire stream (the samples as they
/// enter the system mixer, after PipeWire's conversion and the stream's volume), decodes the same stretch of the
/// song again, and null-tests one against the other ([NullTest]). Only on demand: nothing runs until asked.
///
/// Linux with PipeWire only: an output straight to the card (bit-perfect mode) has no stream to record, and other
/// systems would need their own loopback (Windows' WASAPI loopback isn't wired). Off with `RIFLAY_NO_OUTPUT_MEASURE`.
abstract final class OutputMeasure {
  static const enabled = !bool.fromEnvironment('RIFLAY_NO_OUTPUT_MEASURE');

  static bool get supported => enabled && Host.isLinux && MpvPcm.supported;

  /// Whether the song playing along [path] can be measured: it goes through PipeWire (native or its Pulse server).
  static bool availableFor(SignalPath path) => supported && (path.output == 'pipewire' || path.output == 'pulse');

  static const length = Duration(seconds: 10);

  /// How much of the song is decoded around where the recording should sit, for the search.
  static const _margin = Duration(seconds: 2);

  static Future<OutputMeasurement> measure(
    AudioEngine audio, {
    void Function(MeasureStage stage, double progress)? onProgress,
  }) async {
    final stream = await _findStream();
    final rate = stream.rate;
    final song = audio.songKey;
    final path = await audio.mainPath();
    if (path == null) throw const MeasureFailure(MeasureProblem.noStream);

    onProgress?.call(MeasureStage.recording, 0);
    final (output, expectedAt) = await _record(audio, stream.serial, rate, (p) {
      onProgress?.call(MeasureStage.recording, p);
    });
    if (audio.songKey != song) throw const MeasureFailure(MeasureProblem.songMoved);

    onProgress?.call(MeasureStage.decoding, 0);
    final from = expectedAt - _margin.inMicroseconds / 1e6;
    final start = from < 0 ? 0.0 : from;
    final end = expectedAt + (length + _margin).inMicroseconds / 1e6;
    final reference = await _decode(path, start, end, rate);

    onProgress?.call(MeasureStage.comparing, 0);
    final expected = (expectedAt - start) * rate;
    final result = await _compare(reference, output, rate, expected);
    if (result == null) throw const MeasureFailure(MeasureProblem.noMatch);
    debugPrint('Output measurement at $rate Hz: $result');
    return OutputMeasurement(result, rate: rate);
  }

  /// [NullTest.compare] in an isolate. Its own function: a closure in [measure] would take that one's whole context
  /// along (the player and all), which can't be sent.
  static Future<NullTestResult?> _compare(Float64List reference, Float64List output, int rate, double expected) =>
      Isolate.run(() => NullTest.compare(reference, output, channels: 2, rate: rate, expected: expected));

  /// Riflay's own playing PipeWire stream: its serial, and the rate the graph runs it at.
  static Future<({String serial, int rate})> _findStream() async {
    final ProcessResult dump;
    try {
      dump = await Process.run('pw-dump', const []).timeout(const Duration(seconds: 5));
    } on ProcessException {
      throw const MeasureFailure(MeasureProblem.noRecorder);
    } on TimeoutException {
      throw const MeasureFailure(MeasureProblem.noRecorder);
    }
    if (dump.exitCode != 0) throw const MeasureFailure(MeasureProblem.noRecorder);
    final found = findStream(jsonDecode(dump.stdout as String) as List<dynamic>, pid);
    if (found == null) throw const MeasureFailure(MeasureProblem.noStream);
    if (found.serial.isEmpty) throw const MeasureFailure(MeasureProblem.twoStreams);
    return found;
  }

  /// From `pw-dump`'s objects: the running output stream of process [process] (its client's process id) and the rate
  /// of the device that drives it; an empty serial when there are several; null when there is none.
  @visibleForTesting
  static ({String serial, int rate})? findStream(List<dynamic> objects, int process) {
    final byId = <int, Map<String, dynamic>>{};
    for (final o in objects) {
      if (o is Map<String, dynamic> && o['id'] is int) byId[o['id'] as int] = o;
    }
    Map<String, dynamic> props(Map<String, dynamic>? o) =>
        ((o?['info'] as Map<String, dynamic>?)?['props'] as Map<String, dynamic>?) ?? const {};
    bool ours(Map<String, dynamic> p) =>
        '${p['application.process.id']}' == '$process' || '${p['pipewire.sec.pid']}' == '$process';
    final streams = [
      for (final o in byId.values)
        if (o['type'] == 'PipeWire:Interface:Node' &&
            props(o)['media.class'] == 'Stream/Output/Audio' &&
            (o['info'] as Map<String, dynamic>?)?['state'] == 'running' &&
            (ours(props(o)) || ours(props(byId[props(o)['client.id']]))))
          o,
    ];
    if (streams.isEmpty) return null;
    if (streams.length > 1) return (serial: '', rate: 0);
    final p = props(streams.single);
    int? formatRate(Map<String, dynamic>? node) {
      final formats = ((node?['info'] as Map<String, dynamic>?)?['params'] as Map<String, dynamic>?)?['Format'];
      return formats is List && formats.isNotEmpty && formats.first is Map
          ? (formats.first as Map)['rate'] as int?
          : null;
    }

    final nodeRate = int.tryParse('${p['node.rate']}'.split('/').last);
    final rate = formatRate(byId[p['node.driver-id']]) ?? nodeRate ?? 48000;
    return (serial: '${p['object.serial'] ?? streams.single['id']}', rate: rate);
  }

  /// [length] of the stream [serial] as stereo 32-bit float at [rate], and where in the song (seconds) its first
  /// sample was expected: where mpv said it was playing when the first samples arrived, less what had arrived.
  static Future<(Float64List, double)> _record(
    AudioEngine audio,
    String serial,
    int rate,
    void Function(double) onProgress,
  ) async {
    final Process recorder;
    try {
      recorder = await Process.start('pw-record', [
        '--target', serial, '--rate', '$rate', '--channels', '2', '--format', 'f32', '--raw', //
        // Its own volume left alone: a level wireplumber kept for "pw-record" would change the samples.
        '--volume', '1.0', '-P', '{ node.dont-reconnect = true state.restore-props = false }', '-',
      ]);
    } on ProcessException {
      throw const MeasureFailure(MeasureProblem.noRecorder);
    }
    recorder.stderr.drain<void>().ignore();
    final want = length.inMilliseconds * rate ~/ 1000 * 8;
    final bytes = BytesBuilder(copy: false);
    final done = Completer<void>();
    double? songAt; // seconds, when the first samples came
    var stopwatch = Stopwatch();
    final sub = recorder.stdout.listen(
      (chunk) {
        if (done.isCompleted) return;
        final first = bytes.isEmpty;
        bytes.add(chunk);
        if (first) {
          final had = bytes.length ~/ 8;
          stopwatch = Stopwatch()..start();
          audio.mainTimePos().then((at) {
            if (at != null) songAt = at - had / rate;
          });
        }
        onProgress((bytes.length / want).clamp(0, 1));
        if (bytes.length >= want) done.complete();
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    try {
      await done.future.timeout(length + const Duration(seconds: 5));
    } on TimeoutException {
      // Paused partway: the stream stopped giving samples.
    } finally {
      await sub.cancel();
      recorder.kill(ProcessSignal.sigint);
      unawaited(
        recorder.exitCode.timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            recorder.kill(ProcessSignal.sigkill);
            return -1;
          },
        ),
      );
    }
    final data = _aligned(bytes.takeBytes());
    if (data.length < want) {
      throw MeasureFailure(data.isEmpty ? MeasureProblem.noStream : MeasureProblem.songMoved);
    }
    // The song's clock should have moved as far as the recording did: otherwise it was paused or moved.
    final end = await audio.mainTimePos();
    final started = songAt;
    if (started == null || end == null) throw const MeasureFailure(MeasureProblem.songMoved);
    final moved = end - started - stopwatch.elapsedMicroseconds / 1e6;
    if (moved.abs() > 1.5) throw const MeasureFailure(MeasureProblem.songMoved);
    final floats = Float32List.sublistView(data, 0, want);
    return (Float64List.fromList(floats), started);
  }

  /// The song at [path] from [start] to [end] seconds, stereo at [rate], as full-scale doubles: mpv's own decode,
  /// 32-bit, with nothing applied (so the song's own samples, padded).
  static Future<Float64List> _decode(String path, double start, double end, int rate) async {
    final PcmStream pcm;
    try {
      pcm = await MpvPcm.decode(
        PcmInput.file(path),
        start: Duration(microseconds: (start * 1e6).round()),
        end: Duration(microseconds: (end * 1e6).round()),
        rate: rate,
        bits: 32,
      );
    } catch (e) {
      debugPrint('Output measurement: $e');
      throw const MeasureFailure(MeasureProblem.noSource);
    }
    final bytes = BytesBuilder(copy: false);
    try {
      await for (final chunk in pcm.data.timeout(const Duration(seconds: 20))) {
        bytes.add(chunk);
      }
    } on TimeoutException {
      throw const MeasureFailure(MeasureProblem.noSource);
    } finally {
      await pcm.cancel();
    }
    if (pcm.channels != 2 || pcm.rate != rate || pcm.bits != 32) throw const MeasureFailure(MeasureProblem.noSource);
    final data = _aligned(bytes.takeBytes());
    final ints = Int32List.sublistView(data, 0, data.length ~/ 4 * 4);
    final out = Float64List(ints.length);
    for (var i = 0; i < ints.length; i++) {
      out[i] = ints[i] / 2147483648.0;
    }
    return out;
  }

  /// [bytes] where a 4-byte view of them can start (a chunk handed on as it is may sit anywhere).
  static Uint8List _aligned(Uint8List bytes) => bytes.offsetInBytes % 4 == 0 ? bytes : Uint8List.fromList(bytes);
}
