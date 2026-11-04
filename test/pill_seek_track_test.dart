import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/ui/widgets/wavy_seek_track.dart';

void main() {
  const rect = Rect.fromLTWH(0, 10, 300, 16);

  test('the pills are round only at their outer ends, square where they face the thumb', () {
    final (played, rest) = PillSeekTrack.segments(rect, 100, 16);
    expect(played, isNotNull);
    expect(rest, isNotNull);

    // The elapsed pill: far left fully round (half the track height), the end facing the thumb square.
    expect(played!.tlRadius, const Radius.circular(8));
    expect(played.blRadius, const Radius.circular(8));
    expect(played.trRadius, Radius.zero);
    expect(played.brRadius, Radius.zero);

    // The rest: far right fully round, the end facing the thumb square.
    expect(rest!.trRadius, const Radius.circular(8));
    expect(rest.brRadius, const Radius.circular(8));
    expect(rest.tlRadius, Radius.zero);
    expect(rest.blRadius, Radius.zero);

    // A gap on each side of the thumb bar, and the pills span the track's ends.
    expect(played.left, 0);
    expect(rest.right, 300);
    expect(100 - played.right, greaterThan(4));
    expect(rest.left - 100, greaterThan(4));
  });

  test('near the start or the end of the song one part is too short and is left out, never negative', () {
    final (none, all) = PillSeekTrack.segments(rect, 0, 16);
    expect(none, isNull);
    expect(all, isNotNull);
    expect(all!.width, greaterThan(0));
    expect(all.tlRadius, Radius.zero);

    final (all2, none2) = PillSeekTrack.segments(rect, 300, 16);
    expect(none2, isNull);
    expect(all2!.width, greaterThan(0));
    expect(all2.trRadius, Radius.zero);

    // A very short elapsed part keeps its shape and a positive width.
    final (short, _) = PillSeekTrack.segments(rect, 10, 16);
    if (short != null) expect(short.width, greaterThan(0));
    for (final x in [-20.0, 0.0, 3.0, 9.0, 14.0, 150.0, 292.0, 299.0, 300.0, 340.0]) {
      final (a, b) = PillSeekTrack.segments(rect, x, 16);
      for (final r in [a, b]) {
        if (r != null) expect(r.width, greaterThan(0), reason: 'thumb at $x');
      }
    }
  });
}
