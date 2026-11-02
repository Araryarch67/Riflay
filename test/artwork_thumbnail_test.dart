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

  test('native thumbnails preserve aspect ratio, crop resolution and colour', () async {
    for (final (width, height) in [(1200, 600), (600, 1200)]) {
      final name = 'native-$width-$height';
      final track = _song(dir, name, cover: false);
      final source = img.Image(width: width, height: height);
      img.fill(source, color: img.ColorRgb8(220, 40, 60));
      File('${dir.path}/$name.png').writeAsBytesSync(img.encodePng(source));
      final result = img.decodeJpg((await Metadata.thumbnail(track))!)!;
      expect([result.width, result.height], width > height ? [512, 256] : [256, 512]);
      final pixel = result.getPixel(result.width ~/ 2, result.height ~/ 2);
      expect(pixel.r, closeTo(220, 5));
      expect(pixel.g, closeTo(40, 5));
      expect(pixel.b, closeTo(60, 5));
    }
  });

  test('a small animated cover is passed through with all animation frames', () async {
    final track = _song(dir, 'animated', cover: false);
    final source = img.Image(width: 120, height: 120);
    source.addFrame(img.Image(width: 120, height: 120));
    final bytes = Uint8List.fromList(img.encodeGif(source));
    // Use a supported sidecar name; the decoder identifies the encoded format.
    File('${dir.path}/animated.png').writeAsBytesSync(bytes);
    final result = await Metadata.thumbnail(track);
    expect(result, bytes);
    expect(img.decodeGif(result!)!.numFrames, 2);
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

  test('a burst of covers bounds concurrent decodes and retains thumbnail quality', () async {
    final tracks = [for (var i = 0; i < 12; i++) _song(dir, 'burst$i')];
    Metadata.peakThumbnailDecodes = 0;
    final made = Metadata.thumbnailsMade;
    final results = await Future.wait(tracks.map(Metadata.thumbnail));
    expect(Metadata.peakThumbnailDecodes, 2);
    expect(Metadata.thumbnailDecodesInFlight, 0);
    expect(Metadata.thumbnailsMade - made, tracks.length);
    for (final result in results) {
      final image = img.decodeJpg(result!)!;
      expect([image.width, image.height], [Metadata.thumbnailSide, Metadata.thumbnailSide]);
    }
  });

  test('queued thumbnails whose views left are skipped and can be requested again', () async {
    final tracks = [for (var i = 0; i < 8; i++) _song(dir, 'cancel$i')];
    await Future.wait(tracks.map(Metadata.artwork));
    final requests = [for (final _ in tracks) ArtworkRequest()];
    final made = Metadata.thumbnailsMade;
    final futures = [for (var i = 0; i < tracks.length; i++) Metadata.thumbnail(tracks[i], request: requests[i])];
    for (final request in requests.take(6)) {
      request.cancel();
    }
    final results = await Future.wait(futures);
    expect(results.take(6), everyElement(isNull));
    expect(results.skip(6), everyElement(isNotNull));
    expect(Metadata.thumbnailsMade - made, 2);
    expect(Metadata.hasCachedThumbnail(tracks.first), isFalse);
    expect(await Metadata.thumbnail(tracks.first), isNotNull);
  });

  test('deduplicated thumbnails retain requests from other views', () async {
    final track = _song(dir, 'shared-thumb');
    final gone = ArtworkRequest(), staying = ArtworkRequest();
    final made = Metadata.thumbnailsMade;
    final a = Metadata.thumbnail(track, request: gone);
    final b = Metadata.thumbnail(track, request: staying);
    gone.cancel();
    final results = await Future.wait([a, b]);
    expect(results, everyElement(isNotNull));
    expect(results[0], same(results[1]));
    expect(Metadata.thumbnailsMade - made, 1);
  });

  test('an unscoped caller keeps shared artwork alive after a view leaves', () async {
    final track = _song(dir, 'unscoped');
    final gone = ArtworkRequest();
    final a = Metadata.thumbnail(track, request: gone);
    final b = Metadata.thumbnail(track);
    gone.cancel();
    expect(await Future.wait([a, b]), everyElement(isNotNull));
  });
}
