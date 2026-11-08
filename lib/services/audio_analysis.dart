import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';
import 'audio_analysis_core.dart';
import 'pcm_decoder.dart';
import 'youtube_stream.dart';

export 'audio_analysis_core.dart' show AudioAnalyzer, AudioReport, SourceVerdict;

/// Measures songs on this device (files, not streams): their loudness, for leveling songs without ReplayGain
/// tags; their dynamic range; and their spectrum, which shows a "lossless" file made from an MP3. One decode with
/// mpv gives all three, measured in an isolate of its own. What is measured is kept per file (its path, size and
/// date), all but the spectrogram, which is measured again when shown.
abstract final class AudioAnalysis {
  /// Off with `RIFLAY_NO_SCANNED_GAIN`: songs without ReplayGain tags play unleveled, measured or not.
  static const useScannedGain = !bool.fromEnvironment('RIFLAY_NO_SCANNED_GAIN');

  static Map<String, AudioReport>? _saved;
  static Future<void>? _loading;
  static final _measuring = <String, Future<AudioReport?>>{};
  static final _spectrograms = <String, AudioReport>{}; // the last few, with their pictures

  /// The library scan's progress: songs done and songs to do; null when not scanning.
  static final scan = ValueNotifier<(int, int)?>(null);
  static bool _stopScan = false;

  static bool get supported => MpvPcm.supported;

  /// The file [track] plays from, if it is one on this device.
  static String? fileOf(Track track) => track.path ?? (track.uri.isScheme('file') ? track.uri.toFilePath() : null);

  static String? _key(String path) {
    try {
      final s = File(path).statSync();
      if (s.type != FileSystemEntityType.file) return null;
      return '$path|${s.size}|${s.modified.millisecondsSinceEpoch}';
    } catch (_) {
      return null;
    }
  }

  static Future<File> _file() async =>
      File(p.join((await getApplicationSupportDirectory()).path, 'audio-analysis.json'));

  static Future<void> load() => _loading ??= () async {
    final saved = <String, AudioReport>{};
    try {
      final f = await _file();
      if (f.existsSync()) {
        for (final MapEntry(:key, :value) in (jsonDecode(await f.readAsString()) as Map<String, dynamic>).entries) {
          saved[key] = AudioReport.fromJson(value as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('Audio analysis: could not read what was measured: $e');
    }
    _saved = saved;
  }();

  static Timer? _saveSoon;
  static void _save() {
    _saveSoon?.cancel();
    _saveSoon = Timer(const Duration(seconds: 2), () async {
      final saved = _saved;
      if (saved == null) return;
      // The newest few thousand: a big library is a few hundred KB.
      while (saved.length > 5000) {
        saved.remove(saved.keys.first);
      }
      try {
        final f = await _file();
        final part = File('${f.path}.part');
        await part.writeAsString(jsonEncode({for (final e in saved.entries) e.key: e.value.toJson()}));
        await part.rename(f.path);
      } catch (e) {
        debugPrint('Audio analysis: could not save: $e');
      }
    });
  }

  /// What was measured of the file at [path], if it hasn't changed since.
  static AudioReport? savedFor(String path) {
    final key = _key(path);
    return key == null ? null : _saved?[key];
  }

  /// The gain leveling gives the file at [path] when it has no ReplayGain tags: -18 LUFS less its measured
  /// loudness, or null when it hasn't been measured.
  static double? gainFor(String path) => useScannedGain ? savedFor(path)?.gainDb : null;

  /// [track] measured: from what was kept, or decoded now. With [spectrogram] the picture comes too (measured
  /// again if only the numbers were kept). Null for a file that can't be decoded, and for a stream unless
  /// [streams] (the seek bar's waveform), then only where prefetching is allowed (not on mobile data): its sound
  /// is fetched once more to be measured.
  static Future<AudioReport?> of(
    Track track, {
    bool spectrogram = false,
    bool streams = false,
    bool waveform = false,
  }) async {
    if (!supported) return null;
    var path = fileOf(track);
    await load();
    String? key;
    if (path != null) {
      key = _key(path);
    } else if (streams && track.videoId != null) {
      key = 'yt:${track.videoId}';
      if (_saved![key] case final known? when !spectrogram && (!waveform || known.waveform != null)) return known;
      if (!await YoutubeStream.prefetchAllowed()) return null;
      path = (await YoutubeStream.resolve(track.videoId!)).url.toString();
    }
    if (key == null || path == null) return null;
    if (spectrogram) {
      if (_spectrograms[key] case final shown?) return shown;
    } else if (_saved![key] case final known? when !waveform || known.waveform != null) {
      // Kept from before the waveform was measured too: measured again for it.
      return known;
    }
    final measuring = _measuring['$key|$spectrogram'] ??= _measure(path, spectrogram: spectrogram);
    try {
      final r = await measuring;
      if (r != null) {
        _saved![key] = r;
        _save();
        if (spectrogram) {
          _spectrograms[key] = r;
          while (_spectrograms.length > 6) {
            _spectrograms.remove(_spectrograms.keys.first);
          }
        }
      }
      return r;
    } finally {
      _measuring.remove('$key|$spectrogram');
    }
  }

  /// Measures every song of [tracks] on this device not measured yet, one at a time, until done or [stopScan].
  static Future<void> scanAll(List<Track> tracks) async {
    if (scan.value != null || !supported) return;
    await load();
    final todo = [
      for (final t in tracks)
        if (fileOf(t) case final path? when savedFor(path) == null) t,
    ];
    _stopScan = false;
    scan.value = (0, todo.length);
    try {
      for (var i = 0; i < todo.length && !_stopScan; i++) {
        try {
          await of(todo[i]);
        } catch (e) {
          debugPrint('Audio analysis: ${todo[i].title}: $e');
        }
        scan.value = (i + 1, todo.length);
      }
    } finally {
      scan.value = null;
    }
  }

  static void stopScan() => _stopScan = true;

  /// How many of [tracks] (files on this device) are measured.
  static int measuredOf(List<Track> tracks) => tracks.where((t) {
    final path = fileOf(t);
    return path != null && savedFor(path) != null;
  }).length;

  /// 8 of mpv's 64 KiB reads: half a megabyte of samples between the decoder and the worker.
  static const _chunksInFlight = 8;

  static Future<AudioReport?> _measure(String path, {required bool spectrogram}) async {
    final pcm = await MpvPcm.decode(PcmInput.file(path), maxRate: 192000, bits: 32);
    final results = ReceivePort();
    final worker = await Isolate.spawn(_work, (results.sendPort, pcm.rate, pcm.channels, spectrogram));
    final answer = Completer<AudioReport?>();
    SendPort? feed;
    final queued = <TransferableTypedData>[];
    var ended = false;
    // Chunks sent and not yet measured. mpv decodes far faster than the worker measures: without a limit the whole
    // song piled up in the worker's queue: 180 MiB for four minutes of 24/96, twice that at 192 kHz.
    var inFlight = 0;
    Completer<void>? room;
    results.listen((message) {
      switch (message) {
        case true:
          inFlight--;
          if (room case final r? when !r.isCompleted) r.complete();
        case SendPort port:
          feed = port;
          for (final q in queued) {
            port.send(q);
          }
          queued.clear();
          if (ended) port.send(null);
        case (Map<String, dynamic> report, TransferableTypedData? picture, int columns):
          var r = AudioReport.fromJson(report);
          if (picture != null) r = r.withSpectrogram(picture.materialize().asUint8List(), columns);
          answer.complete(r);
        case String error:
          answer.completeError(StateError(error));
          if (room case final r? when !r.isCompleted) r.complete();
      }
    });
    try {
      await for (final chunk in pcm.data) {
        // Waiting here pauses the stream, and mpv waits on the full pipe.
        while (inFlight >= _chunksInFlight && !answer.isCompleted) {
          await (room = Completer<void>()).future;
        }
        if (answer.isCompleted) break; // the worker failed
        inFlight++;
        final t = TransferableTypedData.fromList([chunk]);
        if (feed case final port?) {
          port.send(t);
        } else {
          queued.add(t);
        }
      }
      ended = true;
      feed?.send(null);
      return await answer.future.timeout(const Duration(minutes: 2));
    } finally {
      await pcm.cancel();
      results.close();
      worker.kill(priority: Isolate.beforeNextEvent);
    }
  }

  /// The worker: 32-bit samples in, the report out.
  static void _work((SendPort, int, int, bool) start) {
    final (out, rate, channels, spectrogram) = start;
    final input = ReceivePort();
    out.send(input.sendPort);
    final analyzer = AudioAnalyzer(rate: rate, channels: channels);
    var leftover = Uint8List(0);
    input.listen((message) {
      try {
        if (message == null) {
          final r = analyzer.finish(spectrogram: spectrogram);
          final picture = r.spectrogram;
          out.send((r.toJson(), picture == null ? null : TransferableTypedData.fromList([picture]), r.columns));
          input.close();
          return;
        }
        var bytes = (message as TransferableTypedData).materialize().asUint8List();
        if (leftover.isNotEmpty) bytes = Uint8List.fromList([...leftover, ...bytes]);
        final whole = bytes.length - bytes.length % (4 * channels);
        leftover = Uint8List.fromList(bytes.sublist(whole));
        final ints = bytes.buffer.asByteData(bytes.offsetInBytes, whole);
        final samples = Float64List(whole ~/ 4);
        for (var i = 0; i < samples.length; i++) {
          samples[i] = ints.getInt32(i * 4, Endian.little) / 2147483648;
        }
        analyzer.add(samples);
        out.send(true);
      } catch (e) {
        out.send('$e');
        input.close();
      }
    });
  }
}
