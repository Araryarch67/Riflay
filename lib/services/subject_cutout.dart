import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/background.dart';

/// A model that finds the person in a photo. The built-in one ships with the app; the others are fetched once, on
/// request, checked against their SHA-256, and kept in the app's folder. All run on the device through ONNX Runtime.
enum CutoutModel {
  /// U²-Net-p (Apache-2.0, from rembg's releases): small and quick, softer edges.
  builtIn(side: 320, mean: [0.485, 0.456, 0.406], spread: [0.229, 0.224, 0.225], stretch: true, keepsShape: false),

  /// MODNet (Apache-2.0): made for portraits, hair kept finely.
  modnet(
    side: 512,
    mean: [0.5, 0.5, 0.5],
    spread: [0.5, 0.5, 0.5],
    stretch: false,
    keepsShape: true,
    url: 'https://huggingface.co/Xenova/modnet/resolve/fa2fa546052fba4c08921230a26cc69a333fca12/onnx/model.onnx',
    sha256: '07c308cf0fc7e6e8b2065a12ed7fc07e1de8febb7dc7839d7b7f15dd66584df9',
    bytes: 25888640,
  ),

  /// BRIA's RMBG-1.4 (its own licence, for non-commercial use only: asked to be accepted before it is fetched).
  rmbg(
    side: 1024,
    mean: [0.5, 0.5, 0.5],
    spread: [1, 1, 1],
    stretch: true,
    keepsShape: false,
    url: 'https://huggingface.co/briaai/RMBG-1.4/resolve/da1d078376e6691105a5530a374a010627fc60b5/onnx/model_quantized.onnx',
    sha256: 'a6648479275dfd0ede0f3a8abc20aa5c437b394681b05e5af6d268250aaf40f3',
    bytes: 44403226,
    licence: 'https://huggingface.co/briaai/RMBG-1.4',
  );

  const CutoutModel({
    required this.side,
    required this.mean,
    required this.spread,
    required this.stretch,
    required this.keepsShape,
    this.url,
    this.sha256,
    this.bytes = 0,
    this.licence,
  });

  /// The longer side of the picture the model reads (its whole side, for a square input).
  final int side;

  /// How a pixel (0–1) is normalised for it, per channel.
  final List<double> mean, spread;

  /// Its output is relative and is stretched to 0–1 (the others give 0–1 already).
  final bool stretch;

  /// It reads the photo at its own proportions (sides a multiple of 32); the others, squeezed square.
  final bool keepsShape;

  /// Where it is fetched from, and its SHA-256 and size; null for the built-in one.
  final String? url, sha256;
  final int bytes;

  /// A licence to accept before fetching it (a page to read), or null.
  final String? licence;

  bool get downloaded => url == null || _file(this)?.existsSync() == true;
}

File? _file(CutoutModel m) =>
    SubjectCutout._dir == null ? null : File(p.join(SubjectCutout._dir!.path, '${m.name}.onnx'));

/// The person (or the main subject) of a photo, cut out from everything behind them, on this device, with the
/// [CutoutModel] picked. The photo never leaves the device.
abstract final class SubjectCutout {
  static const _builtIn = 'assets/models/u2netp.onnx';
  static const _key = 'poster.cutoutModel';

  /// The built-in model's square input (kept for its tests).
  static const side = 320;

  /// Photos are worked on at most this long on their longer side: a phone's 12 MP photo took seconds and hundreds of
  /// megabytes for a poster shown at 1080 wide.
  static const maxSide = 2048;

  static Directory? _dir;

  /// Where fetched models are kept; found once.
  static Future<void> prepare() async {
    if (_dir != null) return;
    try {
      _dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'cutout-models'));
    } catch (_) {
      // No app folder (tests): only the built-in model.
    }
  }

  /// The model picked (the built-in one until another is downloaded and picked).
  static Future<CutoutModel> picked() async {
    await prepare();
    final name = (await SharedPreferences.getInstance()).getString(_key);
    final m = CutoutModel.values.asNameMap()[name] ?? CutoutModel.builtIn;
    return m.downloaded ? m : CutoutModel.builtIn;
  }

  static Future<void> pick(CutoutModel m) async => (await SharedPreferences.getInstance()).setString(_key, m.name);

  /// Fetches [m] once, [progress] 0–1 on the way, kept only when it is whole and its SHA-256 matches.
  static Future<void> download(CutoutModel m, {void Function(double)? progress}) async {
    await prepare();
    final dir = _dir, url = m.url;
    if (dir == null || url == null) return;
    await dir.create(recursive: true);
    final target = _file(m)!;
    final part = File('${target.path}.part');
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(url))).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw HttpException('cutout model ${res.statusCode}');
      final sink = part.openWrite();
      final digest = _DigestSink();
      final hash = sha256.startChunkedConversion(digest);
      var received = 0;
      try {
        await for (final chunk in res.stream.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          hash.add(chunk);
          received += chunk.length;
          if (m.bytes > 0) progress?.call(received / m.bytes);
        }
      } finally {
        await sink.close();
        hash.close();
      }
      if (digest.value.toString() != m.sha256) throw const FormatException('cutout model checksum mismatch');
      await part.rename(target.path);
    } finally {
      client.close();
      if (part.existsSync()) await part.delete();
    }
  }

  /// [photo] (any format `package:image` reads) as a PNG with only its subject left, the rest see-through, at the
  /// photo's own proportions, with [model] (the picked one by default); null when it can't be read.
  static Future<Uint8List?> cutout(Uint8List photo, {CutoutModel? model}) async {
    final m = model ?? await picked();
    final bytes = m == CutoutModel.builtIn
        ? (await rootBundle.load(_builtIn)).buffer.asUint8List()
        : await _file(m)!.readAsBytes();
    return inBackground(() => _cutout(m, bytes, photo));
  }

  static Uint8List? _cutout(CutoutModel m, Uint8List model, Uint8List photo) {
    var source = img.decodeImage(photo);
    if (source == null) return null;
    source = img.bakeOrientation(source);
    if (math.max(source.width, source.height) > maxSide) {
      source = source.width >= source.height
          ? img.copyResize(source, width: maxSide, interpolation: img.Interpolation.average)
          : img.copyResize(source, height: maxSide, interpolation: img.Interpolation.average);
    }
    final (w, h) = inputSize(m, source.width, source.height);
    final small = img.copyResize(source, width: w, height: h, interpolation: img.Interpolation.average);
    OrtEnv.instance.init();
    final session = OrtSession.fromBuffer(model, OrtSessionOptions());
    final input = OrtValueTensor.createTensorWithDataList(inputOf(small, model: m), [1, 3, h, w]);
    final options = OrtRunOptions();
    try {
      final outputs = session.run(options, {session.inputNames.first: input});
      // The first output: [1][1][h][w] (U²-Net's finest side output; the others' only one).
      final first = outputs.first?.value as List;
      final rows = (first[0] as List)[0] as List;
      final raw = [for (final row in rows) ...(row as List).cast<double>()];
      for (final o in outputs) {
        o?.release();
      }
      final mask = m.stretch ? maskOf(raw) : Float32List.fromList([for (final v in raw) v.clamp(0.0, 1.0)]);
      return applyMask(source, mask, width: w, height: h);
    } finally {
      input.release();
      options.release();
      session.release();
      OrtEnv.instance.release();
    }
  }

  /// The picture [m] reads for a [width] × [height] photo: its square side, or the photo's proportions with the
  /// longer side at [CutoutModel.side] and both a multiple of 32.
  @visibleForTesting
  static (int, int) inputSize(CutoutModel m, int width, int height) {
    if (!m.keepsShape) return (m.side, m.side);
    int fit(double v) => math.max(32, (v / 32).round() * 32);
    return width >= height ? (m.side, fit(m.side * height / width)) : (fit(m.side * width / height), m.side);
  }

  /// [image] as [model] reads it: channels first, each scaled to 0–1 and normalised as the model was trained.
  @visibleForTesting
  static Float32List inputOf(img.Image image, {CutoutModel model = CutoutModel.builtIn}) {
    final mean = model.mean, spread = model.spread;
    final w = image.width, plane = image.width * image.height;
    final out = Float32List(3 * plane);
    for (final px in image) {
      final i = px.y * w + px.x;
      out[i] = (px.r / 255 - mean[0]) / spread[0];
      out[plane + i] = (px.g / 255 - mean[1]) / spread[1];
      out[2 * plane + i] = (px.b / 255 - mean[2]) / spread[2];
    }
    return out;
  }

  /// The model's raw output stretched to 0–1 (it is relative: the subject is wherever it is highest).
  @visibleForTesting
  static Float32List maskOf(List<double> raw) {
    var low = double.infinity, high = -double.infinity;
    for (final v in raw) {
      low = math.min(low, v);
      high = math.max(high, v);
    }
    final range = high - low;
    return Float32List.fromList([for (final v in raw) range <= 0 ? 0 : (v - low) / range]);
  }

  /// [source] with [mask] ([width] × [height], 0–1) as its opacity, stretched smoothly over the photo, as a PNG.
  @visibleForTesting
  static Uint8List applyMask(img.Image source, Float32List mask, {int width = side, int height = side}) {
    final out = source.convert(numChannels: 4);
    final sx = width / out.width, sy = height / out.height;
    for (final px in out) {
      px.a = (_sample(mask, width, height, (px.x + 0.5) * sx - 0.5, (px.y + 0.5) * sy - 0.5) * 255).round().clamp(
        0,
        255,
      );
    }
    return img.encodePng(out);
  }

  /// [mask] at a point between its cells, bilinear.
  static double _sample(Float32List mask, int w, int h, double x, double y) {
    final x0 = x.floor().clamp(0, w - 1), y0 = y.floor().clamp(0, h - 1);
    final x1 = math.min(x0 + 1, w - 1), y1 = math.min(y0 + 1, h - 1);
    final fx = (x - x0).clamp(0.0, 1.0), fy = (y - y0).clamp(0.0, 1.0);
    final top = mask[y0 * w + x0] * (1 - fx) + mask[y0 * w + x1] * fx;
    final bottom = mask[y1 * w + x0] * (1 - fx) + mask[y1 * w + x1] * fx;
    return top * (1 - fy) + bottom * fy;
  }
}

/// Receives the one digest a chunked hash produces.
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
