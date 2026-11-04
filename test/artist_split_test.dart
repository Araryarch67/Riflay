import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';

void main() {
  test('an artist line splits at commas and semicolons, each name once', () {
    expect(Track.splitArtists('Kobo Kanaeru, Takanashi Kiara'), ['Kobo Kanaeru', 'Takanashi Kiara']);
    expect(Track.splitArtists('A; B ,A'), ['A', 'B']);
    expect(Track.splitArtists('Solo'), ['Solo']);
    expect(Track.splitArtists(Track.unknownArtist), isEmpty);
    expect(Track.splitArtists(''), isEmpty);
  });
}
