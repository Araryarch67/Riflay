import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/ui/pages/home_page.dart';

/// "Recently played" on Home must not reshuffle under the pointer (a tapped card used to jump to the front, so the
/// next tap in the same place played another song).
void main() {
  test('a song already on the shelf keeps its place when it is played', () {
    expect(SteadyOrder.order(['a', 'b', 'c'], ['b', 'a', 'c']), ['a', 'b', 'c']);
  });

  test('a newly played song goes in front, the rest stay', () {
    expect(SteadyOrder.order(['a', 'b', 'c'], ['d', 'a', 'b', 'c']), ['d', 'a', 'b', 'c']);
    expect(SteadyOrder.order(['a', 'b'], ['e', 'd', 'b', 'a']), ['e', 'd', 'a', 'b']);
  });

  test('songs that fell off the list leave the shelf', () {
    expect(SteadyOrder.order(['a', 'b', 'c'], ['d', 'a', 'b']), ['d', 'a', 'b']);
  });
}
