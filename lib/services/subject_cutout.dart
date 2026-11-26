import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import '../platform/background.dart';

/// The person (or the main subject) of a photo, cut out from everything behind them, on this device: U²-Net-p
/// (Apache-2.0, `assets/models/u2netp.onnx`, from rembg's releases) through ONNX Runtime. The same free model on every
/// platform; the photo never leaves the device.
abstract final class SubjectCutout {
  static const _model = 'assets/models/u2netp.onnx';

  /// The model's square input.
  static const side = 320;

  /// Photos are worked on at most this long on their longer side: a phone's 12 MP photo took seconds and hundreds of
  /// megabytes for a poster shown at 1080 wide.
  static const maxSide = 2048;

  /// [photo] (any format `package:image` reads) as a PNG with only its subject left, the rest see-through, at the
  /// photo's own proportions; null when it can't be read.
  static Future<Uint8List?> cutout(Uint8List photo) async {
    final model = (await rootBundle.load(_model)).buffer.asUint8List();
    return inBackground(() => _cutout(model, photo));
  }

  static Uint8List? _cutout(Uint8List model, Uint8List photo) {
    var source = img.decodeImage(photo);
    if (source == null) return null;
    source = img.bakeOrientation(source);
    if (math.max(source.width, source.height) > maxSide) {
      source = source.width >= source.height
          ? img.copyResize(source, width: maxSide, interpolation: img.Interpolation.average)
          : img.copyResize(source, height: maxSide, interpolation: img.Interpolation.average);
    }
    final small = img.copyResize(source, width: side, height: side, interpolation: img.Interpolation.average);
    OrtEnv.instance.init();
    final session = OrtSession.fromBuffer(model, OrtSessionOptions());
    final input = OrtValueTensor.createTensorWithDataList(inputOf(small), [1, 3, side, side]);
    final options = OrtRunOptions();
    try {
      final outputs = session.run(options, {session.inputNames.first: input});
      // d0, the finest of U²-Net's seven side outputs: [1][1][side][side].
      final first = outputs.first?.value as List;
      final rows = (first[0] as List)[0] as List;
      final mask = maskOf([for (final row in rows) ...(row as List).cast<double>()]);
      for (final o in outputs) {
        o?.release();
      }
      return applyMask(source, mask);
    } finally {
      input.release();
      options.release();
      session.release();
      OrtEnv.instance.release();
    }
  }

  /// [image] (side × side) as the model reads it: channels first, each scaled to 0–1 and normalised with ImageNet's
  /// mean and spread, as U²-Net was trained.
  @visibleForTesting
  static Float32List inputOf(img.Image image) {
    const mean = [0.485, 0.456, 0.406], spread = [0.229, 0.224, 0.225];
    final plane = side * side;
    final out = Float32List(3 * plane);
    for (final px in image) {
      final i = px.y * side + px.x;
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

  /// [source] with [mask] (side × side, 0–1) as its opacity, stretched smoothly over the photo, as a PNG.
  @visibleForTesting
  static Uint8List applyMask(img.Image source, Float32List mask) {
    final out = source.convert(numChannels: 4);
    final sx = side / out.width, sy = side / out.height;
    for (final px in out) {
      px.a = (_sample(mask, (px.x + 0.5) * sx - 0.5, (px.y + 0.5) * sy - 0.5) * 255).round().clamp(0, 255);
    }
    return img.encodePng(out);
  }

  /// [mask] at a point between its cells, bilinear.
  static double _sample(Float32List mask, double x, double y) {
    final x0 = x.floor().clamp(0, side - 1), y0 = y.floor().clamp(0, side - 1);
    final x1 = math.min(x0 + 1, side - 1), y1 = math.min(y0 + 1, side - 1);
    final fx = (x - x0).clamp(0.0, 1.0), fy = (y - y0).clamp(0.0, 1.0);
    final top = mask[y0 * side + x0] * (1 - fx) + mask[y0 * side + x1] * fx;
    final bottom = mask[y1 * side + x0] * (1 - fx) + mask[y1 * side + x1] * fx;
    return top * (1 - fy) + bottom * fy;
  }
}
