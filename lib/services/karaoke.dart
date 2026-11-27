import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import '../platform/host.dart';
import 'audio_analysis_core.dart';
import 'pcm_decoder.dart';

/// How loud each stem plays, 0–1.
typedef KaraokeLevels = ({double vocals, double music});

/// Where Karaoke is with the playing song.
enum KaraokeStage {
  idle,

  /// Fetching the separation model (once).
  downloading,

  /// Decoding the song for the model.
  reading,

  /// The model is splitting the song: [Karaoke.progress] says how far.
  separating,

  /// The song's stems are ready (or play already).
  ready,

  /// The song can't be decoded here (a source Riflay plays but can't hand to a decoder).
  unsupported,
  failed,
}

/// Karaoke: the playing song split, on this device, into its lead vocals and the music behind them, so the vocals
/// can be turned down or off. The split is made once per song with UVR's Kim Vocal 2 (MDX-Net, from Ultimate Vocal
/// Remover's model set), fetched on first use and checked by its SHA-256, and kept as
/// one 4-channel WAV per song (instrumental left/right, vocals left/right); the engine mixes the two at the chosen
/// levels ([karaokeFilter]), each turned up or down on its own, so moving a slider needs no new split.
class Karaoke extends ChangeNotifier {
  Karaoke({required this.current, required this.input, required this.reload, required this.applyLevels}) {
    _prepare();
  }

  /// The song playing now.
  final Track? Function() current;

  /// What to decode for a song (its file, or the stream it plays from), with its slice of a cue sheet; null when
  /// its source can't be decoded here.
  final (PcmInput, Duration?, Duration?)? Function(Track) input;

  /// Rebuilds the queue's sources where the song is, so it plays from its stems (or no longer does).
  final Future<void> Function() reload;

  /// The levels the engine mixes the stems at; null with Karaoke off.
  final void Function(KaraokeLevels?) applyLevels;

  // Kim Vocal 2's STFT and output, from UVR's model data (mdx_n_fft_scale_set 7680, hop 1024, mdx_dim_f_set 3072,
  // mdx_dim_t_set 8, compensate 1.009): the model reads the first [bins] of the STFT's 3841 bins.
  static const nFft = 7680, hop = 1024, bins = 3072, frames = 256, rate = 44100;

  /// The model's vocals come out a touch quiet: UVR scales them by this.
  static const compensate = 1.009;

  /// Samples one run of the model reads, and the [trim] at each side of them it gets wrong (the STFT's edges): each
  /// run keeps only the [step] in the middle.
  static const window = hop * (frames - 1), trim = nFft ~/ 2, step = window - 2 * trim;

  /// UVR's Kim Vocal 2 (MDX-Net, by KimberleyJSN; Apache-2.0 as published), one of the cleanest vocal splitters:
  /// the vocals out, the music what's left. Pinned to a revision and checked by its SHA-256.
  static const modelName = 'Kim_Vocal_2';
  static const modelUrl =
      'https://huggingface.co/diarizeapp/uvr-kim-vocal-2/resolve/e24eb91da6035652bf05d6d721bf83da24fe782c/Kim_Vocal_2.onnx';
  static const modelSha256 = 'ce74ef3b6a6024ce44211a07be9cf8bc6d87728cc852a68ab34eb8e58cde9c8b';
  static const modelBytes = 66759214;

  /// Stems kept at most, in bytes (a 4-minute song is about 42 MB); the least recently played go first.
  static const cacheLimit = 1500 * 1024 * 1024;

  static const _vocalsKey = 'karaoke.vocals', _musicKey = 'karaoke.music';

  /// ONNX Runtime can't be built into the iOS app for now, and a browser has no decoder for it.
  static bool get supported => !kIsWeb && !Host.isIOS;

  bool enabled = false;

  /// How loud the vocals play over the music, 0 (off) to 1 (as recorded).
  double vocals = 0;

  /// How loud the music behind them plays, 0 (off: the vocals alone) to 1 (as recorded).
  double music = 1;

  KaraokeLevels get levels => (vocals: vocals, music: music);

  KaraokeStage stage = KaraokeStage.idle;

  /// 0–1 while downloading or separating; null when it can't be told.
  double? progress;

  String? _modelDir, _stemsDir;
  _Job? _job;
  static Future<void>? _downloading;

  Future<void> _prepare() async {
    if (!supported) return;
    try {
      _modelDir = p.join((await getApplicationSupportDirectory()).path, 'karaoke-model');
      _stemsDir = p.join((await getApplicationCacheDirectory()).path, 'karaoke');
      final prefs = await SharedPreferences.getInstance();
      vocals = prefs.getDouble(_vocalsKey) ?? 0;
      music = prefs.getDouble(_musicKey) ?? 1;
    } catch (_) {
      // No app folders (tests): nothing is cached.
    }
  }

  String? get _modelPath => _modelDir == null ? null : p.join(_modelDir!, '$modelName.onnx');

  bool get modelDownloaded => _modelPath != null && File(_modelPath!).existsSync();

  /// The file [t] plays from while Karaoke is on and its stems are made; null otherwise.
  String? stemsFor(Track t) {
    if (!enabled || _stemsDir == null) return null;
    final file = File(p.join(_stemsDir!, '${_keyFor(t)}.wav'));
    return file.existsSync() ? file.path : null;
  }

  /// Whether [uri] is a song's stems.
  bool isStems(Uri? uri) =>
      uri != null && uri.scheme == 'file' && _stemsDir != null && p.isWithin(_stemsDir!, uri.toFilePath());

  String _keyFor(Track t) {
    FileStat? stat;
    if (t.path case final path?) stat = FileStat.statSync(path);
    return keyOf(t, size: stat?.size, modified: stat?.modified);
  }

  /// The name of [t]'s stems: the song (its slice of a cue sheet too) and, for a file, its size and date, so an
  /// edited file is split again.
  @visibleForTesting
  static String keyOf(Track t, {int? size, DateTime? modified}) => sha1
      .convert(
        '$modelName|${t.uri}|${t.start?.inMilliseconds}|${t.end?.inMilliseconds}|$size|'
                '${modified?.millisecondsSinceEpoch}'
            .codeUnits,
      )
      .toString();

  Future<void> setEnabled(bool on) async {
    if (on == enabled || (on && !supported)) return;
    enabled = on;
    applyLevels(on ? levels : null);
    if (!on) {
      _job?.cancel();
      _job = null;
      stage = KaraokeStage.idle;
      progress = null;
    }
    notifyListeners();
    // Off: the song goes back to its own source. On: it moves to its stems if they are made, or they are made now.
    if (!on) return reload();
    return follow();
  }

  /// The vocal level while its slider moves (shown at once, sent to the engine on [commitLevels]).
  void setVocals(double v) {
    vocals = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// The music's level while its slider moves (shown at once, sent to the engine on [commitLevels]).
  void setMusic(double v) {
    music = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// Sends the levels to the engine (rebuilding its filters), and keeps them for next time.
  Future<void> commitLevels() async {
    if (enabled) applyLevels(levels);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_vocalsKey, vocals);
    await prefs.setDouble(_musicKey, music);
  }

  /// The song changed, or Karaoke was turned on: the playing song plays from its stems, made now if need be.
  Future<void> follow({bool playingStems = false}) async {
    final t = current();
    if (!enabled || t == null || _stemsDir == null) return;
    if (stemsFor(t) case final stems?) {
      _job?.cancel();
      _job = null;
      stage = KaraokeStage.ready;
      progress = null;
      notifyListeners();
      File(stems).setLastModifiedSync(DateTime.now()); // played: kept longest
      if (!playingStems) await reload();
      return;
    }
    final key = _keyFor(t);
    if (_job?.key == key) return;
    _job?.cancel();
    final job = _job = _Job(key);
    try {
      await _make(t, job);
      if (job.cancelled) return;
      _job = null;
      stage = KaraokeStage.ready;
      progress = null;
      notifyListeners();
      _evict();
      final now = current();
      if (enabled && now != null && _keyFor(now) == job.key) await reload();
    } on _Unsupported {
      if (job.cancelled) return;
      _job = null;
      stage = KaraokeStage.unsupported;
      notifyListeners();
    } catch (e) {
      if (job.cancelled) return;
      debugPrint('Karaoke: $e');
      _job = null;
      stage = KaraokeStage.failed;
      notifyListeners();
    }
  }

  void _show(KaraokeStage s, [double? p]) {
    stage = s;
    progress = p;
    notifyListeners();
  }

  Future<void> _make(Track t, _Job job) async {
    final dir = _stemsDir!;
    await Directory(dir).create(recursive: true);
    if (!modelDownloaded) {
      _show(KaraokeStage.downloading, 0);
      // One download, whichever song asked first: a song changed meanwhile waits for the same one.
      await (_downloading ??= _download((v) {
        if (_job != null && stage == KaraokeStage.downloading) _show(KaraokeStage.downloading, v);
      }).whenComplete(() => _downloading = null));
      if (job.cancelled) return;
    }
    final source = input(t);
    if (source == null) throw const _Unsupported();
    _show(KaraokeStage.reading);
    final raw = p.join(dir, '${job.key}.raw'), part = p.join(dir, '${job.key}.part');
    try {
      await _decode(source, raw, job);
      if (job.cancelled) return;
      _show(KaraokeStage.separating, 0);
      final ports = ReceivePort();
      final done = Completer<void>();
      ports.listen((m) {
        if (m is double) {
          if (!job.cancelled) _show(KaraokeStage.separating, m);
        } else if (m == true) {
          done.complete();
        } else if (!done.isCompleted) {
          done.completeError(StateError('$m'));
        }
      });
      final isolate = await Isolate.spawn(_separate, (ports.sendPort, _modelPath!, raw, part), onError: ports.sendPort);
      job.onCancel = () {
        isolate.kill(priority: Isolate.immediate);
        if (!done.isCompleted) done.complete();
      };
      try {
        await done.future;
      } finally {
        ports.close();
      }
      if (job.cancelled) return;
      await File(part).rename(p.join(dir, '${job.key}.wav'));
    } finally {
      for (final f in [raw, part]) {
        try {
          if (File(f).existsSync()) File(f).deleteSync();
        } catch (_) {} // Windows: still open by the killed isolate; the next [_evict] takes it
      }
    }
  }

  /// [source] as 16-bit stereo at the model's rate into [raw], its cue sheet slice only.
  Future<void> _decode((PcmInput, Duration?, Duration?) source, String raw, _Job job) async {
    final (input, start, end) = source;
    final pcm = MpvPcm.supported
        ? await MpvPcm.decode(input, rate: rate, bits: 16)
        : await FfmpegPcm.decode(input.path!, rate: rate, bits: 16);
    job.onCancel = () => pcm.cancel();
    final sink = File(raw).openWrite();
    // Bytes to skip and to keep (4 a frame), for a song that is a slice of a cue sheet's file.
    var skip = ((start?.inMicroseconds ?? 0) * rate ~/ 1000000) * 4;
    var keep = end == null ? -1 : ((end - (start ?? Duration.zero)).inMicroseconds * rate ~/ 1000000) * 4;
    try {
      await for (var chunk in pcm.data) {
        if (job.cancelled) break;
        if (skip > 0) {
          final n = math.min(skip, chunk.length);
          skip -= n;
          chunk = Uint8List.sublistView(chunk, n);
        }
        if (keep >= 0) {
          if (chunk.length > keep) chunk = Uint8List.sublistView(chunk, 0, keep);
          keep -= chunk.length;
        }
        sink.add(chunk);
        if (keep == 0) break;
      }
    } finally {
      await sink.close();
      await pcm.cancel();
    }
  }

  Future<void> _download(void Function(double) progress) async {
    final target = File(_modelPath!);
    await target.parent.create(recursive: true);
    final part = File('${target.path}.part');
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(modelUrl))).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw HttpException('karaoke model ${res.statusCode}');
      final sink = part.openWrite();
      final digest = _DigestSink();
      final hash = sha256.startChunkedConversion(digest);
      var received = 0;
      try {
        await for (final chunk in res.stream.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          hash.add(chunk);
          received += chunk.length;
          progress(received / modelBytes);
        }
      } finally {
        await sink.close();
        hash.close();
      }
      if (digest.value.toString() != modelSha256) throw const FormatException('karaoke model checksum mismatch');
      await part.rename(target.path);
      // A model this one replaced (an earlier version's) goes, with the room it took.
      for (final old in target.parent.listSync().whereType<File>()) {
        if (old.path != target.path && old.path.endsWith('.onnx')) old.deleteSync();
      }
    } finally {
      client.close();
      if (part.existsSync()) await part.delete();
    }
  }

  /// Drops the least recently played stems past [cacheLimit], and what an interrupted split left.
  void _evict() {
    try {
      final files = Directory(_stemsDir!).listSync().whereType<File>().toList();
      for (final f in files.where((f) => !f.path.endsWith('.wav') && _job?.key != p.basenameWithoutExtension(f.path))) {
        f.deleteSync();
      }
      final stems = files.where((f) => f.path.endsWith('.wav')).toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      var total = 0;
      for (final f in stems) {
        total += f.lengthSync();
        if (total > cacheLimit) f.deleteSync();
      }
    } catch (e) {
      debugPrint('Karaoke cache: $e');
    }
  }

  @override
  void dispose() {
    _job?.cancel();
    super.dispose();
  }

  /// [raw] (16-bit stereo at [rate]) through [model] (a [spectrum] to the vocals' spectrum) run by run, into [out]
  /// as a 4-channel WAV ([stemFrames]), telling [progress] (0–1) after each run.
  @visibleForTesting
  static Future<void> separateFile(
    String raw,
    String out,
    Float32List Function(Float32List) model,
    void Function(double) progress, {
    double compensate = Karaoke.compensate,
  }) async {
    final reader = await File(raw).open();
    final writer = await File(out).open(mode: FileMode.write);
    try {
      final samples = (await reader.length()) ~/ 4;
      await writer.writeFrom(wavHeader(samples));
      final runs = runsFor(samples);
      final left = Float32List(window), right = Float32List(window);
      for (var run = 0; run < runs; run++) {
        // The run reads [trim] samples before the part it keeps and as many after (silence past the song's ends).
        final from = run * step - trim;
        final first = math.max(0, from), last = math.min(samples, from + window);
        left.fillRange(0, window, 0);
        right.fillRange(0, window, 0);
        await reader.setPosition(first * 4);
        final bytes = await reader.read((last - first) * 4);
        final mix = Int16List.sublistView(bytes, 0, bytes.length ~/ 2 * 2); // in bytes
        for (var i = 0; i < mix.length ~/ 2; i++) {
          left[first - from + i] = mix[2 * i] / 32768;
          right[first - from + i] = mix[2 * i + 1] / 32768;
        }
        final (vl, vr) = waves(model(spectrum(left, right)));
        for (var i = 0; i < window; i++) {
          vl[i] *= compensate;
          vr[i] *= compensate;
        }
        final keepFrom = run * step, keep = math.min(step, samples - keepFrom);
        final kept = Int16List.sublistView(mix, (keepFrom - first) * 2, (keepFrom - first + keep) * 2);
        await writer.writeFrom(stemFrames(kept, vl, vr, trim, keep));
        progress((run + 1) / runs);
      }
    } finally {
      await reader.close();
      await writer.close();
    }
  }

  /// The engine's filter that plays stems: the music at [music] with the vocals at [vocals] (each 0–1) over it.
  /// Each output side takes its own side of both stems; a stereo song (no channels 3 and 4) passes as it is.
  static String karaokeFilter(double vocals, {double music = 1}) {
    final g = vocals.clamp(0.0, 1.0).toStringAsFixed(3), m = music.clamp(0.0, 1.0).toStringAsFixed(3);
    return '@karaoke:lavfi=[pan=stereo|c0=$m*c0+$g*c2|c1=$m*c1+$g*c3]';
  }

  /// How many runs of the model a song of [samples] (per channel) takes.
  static int runsFor(int samples) => (samples / step).ceil();

  static final _dft = _Dft(nFft);

  static final _hann = Float64List.fromList([
    for (var i = 0; i < nFft; i++) 0.5 - 0.5 * math.cos(2 * math.pi * i / nFft),
  ]);

  /// What the model reads for [window] samples of [left] and [right]: torch's centred STFT of each (periodic Hann,
  /// reflected at the ends), its first [bins] bins, as [left re, left im, right re, right im] × [bins] × [frames].
  @visibleForTesting
  static Float32List spectrum(Float32List left, Float32List right) {
    assert(left.length == window && right.length == window);
    final out = Float32List(4 * bins * frames);
    final re = Float64List(nFft), im = Float64List(nFft);
    int reflect(int i) => i < 0 ? -i : (i >= window ? 2 * (window - 1) - i : i);
    for (var t = 0; t < frames; t++) {
      // Both channels in one complex FFT: left as the real part, right as the imaginary.
      for (var i = 0; i < nFft; i++) {
        final at = reflect(t * hop - nFft ~/ 2 + i);
        re[i] = left[at] * _hann[i];
        im[i] = right[at] * _hann[i];
      }
      _dft.transform(re, im);
      for (var f = 0; f < bins; f++) {
        final g = (nFft - f) % nFft;
        // X[f] = L[f] + i R[f], and L, R are Hermitian: L = (X[f] + conj X[-f]) / 2, R = (X[f] - conj X[-f]) / 2i.
        out[(0 * bins + f) * frames + t] = (re[f] + re[g]) / 2;
        out[(1 * bins + f) * frames + t] = (im[f] - im[g]) / 2;
        out[(2 * bins + f) * frames + t] = (im[f] + im[g]) / 2;
        out[(3 * bins + f) * frames + t] = (re[g] - re[f]) / 2;
      }
    }
    return out;
  }

  /// The [window] samples of each channel [spec] (laid out as [spectrum]'s) stands for: the inverse STFT, each frame
  /// windowed again and overlap-added, divided by the windows' sum.
  @visibleForTesting
  static (Float32List, Float32List) waves(Float32List spec) {
    final left = Float64List(window), right = Float64List(window), sum = Float64List(window);
    final re = Float64List(nFft), im = Float64List(nFft);
    for (var t = 0; t < frames; t++) {
      re.fillRange(0, nFft, 0);
      im.fillRange(0, nFft, 0);
      // Z = L + i R, conjugated (an inverse FFT as a forward one): Re Z = Re L - Im R, Im Z = Im L + Re R.
      for (var f = 0; f < bins; f++) {
        final lr = spec[(0 * bins + f) * frames + t], li = spec[(1 * bins + f) * frames + t];
        final rr = spec[(2 * bins + f) * frames + t], ri = spec[(3 * bins + f) * frames + t];
        re[f] = lr - ri;
        im[f] = -(li + rr);
        if (f > 0) {
          // The mirrored bin: conj L + i conj R, conjugated.
          re[nFft - f] = lr + ri;
          im[nFft - f] = li - rr;
        }
      }
      _dft.transform(re, im);
      final at = t * hop - nFft ~/ 2;
      for (var i = 0; i < nFft; i++) {
        final j = at + i;
        if (j < 0 || j >= window) continue;
        final w = _hann[i];
        left[j] += re[i] / nFft * w;
        right[j] += -im[i] / nFft * w;
        sum[j] += w * w;
      }
    }
    final l = Float32List(window), r = Float32List(window);
    for (var j = 0; j < window; j++) {
      final s = sum[j] > 1e-8 ? sum[j] : 1.0;
      l[j] = left[j] / s;
      r[j] = right[j] / s;
    }
    return (l, r);
  }

  /// A WAV header for [samples] frames of 16-bit audio in [channels] at [rate].
  @visibleForTesting
  static Uint8List wavHeader(int samples, {int channels = 4}) {
    final data = samples * channels * 2;
    final b = ByteData(44);
    void tag(int at, String s) {
      for (var i = 0; i < 4; i++) {
        b.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    b.setUint32(4, 36 + data, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little);
    b.setUint16(22, channels, Endian.little);
    b.setUint32(24, rate, Endian.little);
    b.setUint32(28, rate * channels * 2, Endian.little);
    b.setUint16(32, channels * 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    b.setUint32(40, data, Endian.little);
    return b.buffer.asUint8List();
  }

  /// [mix] (interleaved stereo) and the [vocalsLeft]/[vocalsRight] found in it, from [from] for [count] frames, as
  /// 4-channel 16-bit frames: the music (the mix less the vocals), then the vocals.
  @visibleForTesting
  static Uint8List stemFrames(Int16List mix, Float32List vocalsLeft, Float32List vocalsRight, int from, int count) {
    final out = Int16List(count * 4);
    int s16(double v) => (v * 32768).round().clamp(-32768, 32767);
    for (var i = 0; i < count; i++) {
      final l = mix[2 * i] / 32768, r = mix[2 * i + 1] / 32768;
      final vl = vocalsLeft[from + i], vr = vocalsRight[from + i];
      out[4 * i] = s16(l - vl);
      out[4 * i + 1] = s16(r - vr);
      out[4 * i + 2] = s16(vl);
      out[4 * i + 3] = s16(vr);
    }
    return out.buffer.asUint8List();
  }
}

/// The split itself, in its own isolate: [raw] through the model into [out], sending its progress (0–1), then `true`
/// when done.
Future<void> _separate((SendPort, String, String, String) args) async {
  final (port, model, raw, out) = args;
  OrtEnv.instance.init();
  final session = OrtSession.fromBuffer(await File(model).readAsBytes(), OrtSessionOptions());
  final options = OrtRunOptions();
  try {
    await Karaoke.separateFile(raw, out, (spec) {
      final input = OrtValueTensor.createTensorWithDataList(spec, [1, 4, Karaoke.bins, Karaoke.frames]);
      final outputs = session.run(options, {session.inputNames.first: input});
      input.release();
      try {
        return _flatten(outputs.first!.value as List);
      } finally {
        for (final o in outputs) {
          o?.release();
        }
      }
    }, port.send);
    port.send(true);
  } catch (e) {
    port.send('$e');
  } finally {
    options.release();
    session.release();
    OrtEnv.instance.release();
  }
}

/// The model's [1][4][bins][frames] output as one list, laid out as [Karaoke.spectrum]'s.
Float32List _flatten(List batch) {
  final out = Float32List(4 * Karaoke.bins * Karaoke.frames);
  var i = 0;
  for (final channel in batch[0] as List) {
    for (final row in channel as List) {
      for (final v in row as List) {
        out[i++] = (v as num).toDouble();
      }
    }
  }
  return out;
}

/// A forward DFT of any length [n], in place (Bluestein's: a convolution done with power-of-two FFTs). Karaoke's
/// model wants 7680 points, which the analyzer's radix-2 FFT can't do.
class _Dft {
  _Dft(this.n) : _m = _pow2(2 * n - 1) {
    _wr = Float64List(n);
    _wi = Float64List(n);
    for (var k = 0; k < n; k++) {
      // exp(-iπk²/n), k² taken mod 2n so the angle stays exact for large k.
      final a = math.pi * ((k * k) % (2 * n)) / n;
      _wr[k] = math.cos(a);
      _wi[k] = -math.sin(a);
    }
    _br = Float64List(_m);
    _bi = Float64List(_m);
    for (var k = 0; k < n; k++) {
      _br[k] = _wr[k];
      _bi[k] = -_wi[k];
      if (k > 0) {
        _br[_m - k] = _wr[k];
        _bi[_m - k] = -_wi[k];
      }
    }
    AudioAnalyzer.fft(_br, _bi);
  }

  final int n;
  final int _m;
  late final Float64List _wr, _wi, _br, _bi;
  late final _ar = Float64List(_m), _ai = Float64List(_m);

  static int _pow2(int v) {
    var p = 1;
    while (p < v) {
      p <<= 1;
    }
    return p;
  }

  void transform(Float64List re, Float64List im) {
    final ar = _ar, ai = _ai;
    ar.fillRange(0, _m, 0);
    ai.fillRange(0, _m, 0);
    for (var k = 0; k < n; k++) {
      ar[k] = re[k] * _wr[k] - im[k] * _wi[k];
      ai[k] = re[k] * _wi[k] + im[k] * _wr[k];
    }
    AudioAnalyzer.fft(ar, ai);
    // Multiply by the chirp's spectrum, then back (an inverse FFT as a forward one on the conjugate).
    for (var k = 0; k < _m; k++) {
      final r = ar[k] * _br[k] - ai[k] * _bi[k], i = ar[k] * _bi[k] + ai[k] * _br[k];
      ar[k] = r;
      ai[k] = -i;
    }
    AudioAnalyzer.fft(ar, ai);
    for (var k = 0; k < n; k++) {
      final r = ar[k] / _m, i = -ai[k] / _m;
      re[k] = r * _wr[k] - i * _wi[k];
      im[k] = r * _wi[k] + i * _wr[k];
    }
  }
}

class _Job {
  _Job(this.key);
  final String key;
  bool cancelled = false;
  void Function()? onCancel;

  void cancel() {
    cancelled = true;
    onCancel?.call();
  }
}

class _Unsupported implements Exception {
  const _Unsupported();
}

/// Receives the one digest a chunked hash produces.
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
