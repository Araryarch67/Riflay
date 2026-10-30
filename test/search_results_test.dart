import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/library_views.dart';

void main() {
  test('search keys find the same songs as a plain scan, for many queries', () {
    final tracks = [
      for (var i = 0; i < 8000; i++)
        Track(
          id: 'id$i',
          uri: Uri.file('/x/$i.flac'),
          title: 'Perf Song $i ${['Blue', 'Night', 'Rain'][i % 3]}${i % 7 == 0 ? ' Xylo' : ''}',
          artist: 'Artist ${i % 400}',
          album: 'Album ${i ~/ 10}',
          duration: const Duration(seconds: 200),
          trackNumber: 1,
          addedAt: i,
          tagged: true,
        ),
    ];
    final v = LibraryViews(tracks, 0);
    for (final q in ['x', 'xy', 'xyl', 'xylo', 'perf', 'blue', 'artist 3', 'album 12', '7', 'zzz', 'rain x']) {
      final expected = [
        for (final t in tracks)
          if ('${t.title}\u0000${t.artist}\u0000${t.album ?? ''}'.toLowerCase().contains(q)) t,
      ];
      final got = [
        for (var i = 0; i < tracks.length; i++)
          if (v.searchKeys[i].contains(q)) tracks[i],
      ];
      expect(got, expected, reason: q);
    }
  });
}
