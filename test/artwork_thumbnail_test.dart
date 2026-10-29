import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/metadata.dart';

Track _song(Directory dir, String name, {bool cover = true, int side = 800}) {
  final file = File('${dir.path}/$name.mp3')..writeAsBytesSync([0, 1, 2, 3]);
  if (cover) {
    File('${dir.path}/$name.jpg').writeAsBytesSync(img.encodeJpg(img.Image(width: side, height: side)));
  }
  return Track.fromUri(Uri.file(file.path));
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('thumb'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a cover is cut down once; the next ask is a cache hit', () async {
    final track = _song(dir, 'a');
    final made = Metadata.thumbnailsMade;
    final first = await Metadata.thumbnail(track);
    expect(first, isNotNull);
    final decoded = img.decodeImage(first!)!;
    expect(decoded.width, Metadata.thumbnailSide);
    expect(first.length, lessThan((await Metadata.artwork(track))!.length));
    expect(Metadata.thumbnailsMade, made + 1);

    expect(Metadata.hasCachedThumbnail(track), isTrue);
    expect(Metadata.cachedThumbnail(track), same(first));
    final again = await Metadata.thumbnail(track);
    expect(again, same(first));
    expect(Metadata.thumbnailsMade, made + 1, reason: 'no second decode');
  });

  test('a cover that is already small is used as it is', () async {
    final track = _song(dir, 'small', side: 120);
    final full = await Metadata.artwork(track);
    expect(await Metadata.thumbnail(track), equals(full));
  });

  test('covers whose widgets are gone are not read', () async {
    final tracks = [for (var i = 0; i < 12; i++) _song(dir, 'q$i', cover: false)];
    final requests = [for (final _ in tracks) ArtworkRequest()];
    final read = Metadata.coversRead;
    final futures = [for (var i = 0; i < tracks.length; i++) Metadata.artwork(tracks[i], request: requests[i])];
    // The list scrolled on: all but the last two are off screen.
    for (var i = 0; i < tracks.length - 2; i++) {
      requests[i].cancel();
    }
    final results = await Future.wait<Uint8List?>(futures);
    expect(results, everyElement(isNull));
    expect(Metadata.coversRead - read, 2);
    // A cancelled cover is not remembered as "has none": asking again reads it.
    expect(Metadata.hasCachedArtwork(tracks.first), isFalse);
    await Metadata.artwork(tracks.first);
    expect(Metadata.coversRead - read, 3);
  });

  test('a cover still wanted by another widget is read', () async {
    final track = _song(dir, 'shared', cover: false);
    final gone = ArtworkRequest(), staying = ArtworkRequest();
    final read = Metadata.coversRead;
    final a = Metadata.artwork(track, request: gone);
    final b = Metadata.artwork(track, request: staying);
    gone.cancel();
    await Future.wait([a, b]);
    expect(Metadata.coversRead - read, 1);
  });
}
