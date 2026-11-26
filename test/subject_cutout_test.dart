import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:riflay/services/subject_cutout.dart';

void main() {
  const side = SubjectCutout.side;

  test('the raw output is stretched to 0–1, and a flat one is nothing', () {
    expect(SubjectCutout.maskOf([2, 4, 6]), [0, 0.5, 1]);
    expect(SubjectCutout.maskOf([3, 3]), [0, 0]);
  });

  test('pixels go in channels first, normalised as U²-Net was trained', () {
    final white = img.Image(width: side, height: side)..clear(img.ColorRgb8(255, 255, 255));
    final input = SubjectCutout.inputOf(white);
    expect(input.length, 3 * side * side);
    expect(input[0], closeTo((1 - 0.485) / 0.229, 1e-4));
    expect(input[side * side], closeTo((1 - 0.456) / 0.224, 1e-4));
    expect(input[2 * side * side], closeTo((1 - 0.406) / 0.225, 1e-4));
  });

  test('the mask becomes the photo\'s opacity at the photo\'s own size: the subject stays, the rest goes', () {
    final photo = img.Image(width: 640, height: 480)..clear(img.ColorRgb8(10, 20, 30));
    // Left half subject, right half background.
    final mask = SubjectCutout.maskOf([
      for (var y = 0; y < side; y++)
        for (var x = 0; x < side; x++) x < side / 2 ? 1.0 : 0.0,
    ]);
    final out = img.decodePng(SubjectCutout.applyMask(photo, mask))!;
    expect((out.width, out.height), (640, 480));
    expect(out.getPixel(10, 240).a, 255);
    expect(out.getPixel(630, 240).a, 0);
    expect(out.getPixel(10, 240).r, 10, reason: 'the photo itself is unchanged');
  });
}
