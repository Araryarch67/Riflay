import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:riflay/services/app_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late String support, cache, temp;

  File put(String path, int bytes) => File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(List.filled(bytes, 1));

  setUp(() {
    root = Directory.systemTemp.createTempSync('appcache');
    support = p.join(root.path, 'support');
    cache = p.join(root.path, 'cache');
    temp = p.join(root.path, 'temp');
    AppCache.foldersOverride = () async => (support: support, cache: cache, temp: temp);
  });
  tearDown(() {
    AppCache.foldersOverride = null;
    root.deleteSync(recursive: true);
  });

  test('clears what is fetched again, and keeps the person\'s own things', () async {
    put(p.join(cache, 'artwork', 'a1b2.img'), 1000);
    put(p.join(cache, 'now-playing-art', 'c3.img'), 200);
    put(p.join(support, 'lyrics-cache', 'abc.json'), 300);
    put(p.join(support, 'autoeq_index.md'), 400);
    put(p.join(support, 'discover-cache.json'), 50);
    put(p.join(temp, 'shared', 'wrap.png'), 25);
    put(p.join(temp, 'riflay-stream-old', 'song-1'), 4000);
    // Not cache.
    final ownLyrics = put(p.join(support, 'my-lyrics', 'song.lrc'), 10);
    final analysis = put(p.join(support, 'audio-analysis.json'), 10);
    final library = put(p.join(support, 'library.json'), 10);
    final otherTemp = put(p.join(temp, 'someone-else', 'x'), 10);

    expect(await AppCache.size(), 5975);
    expect(await AppCache.clear(), 5975);
    expect(await AppCache.size(), 0);

    for (final f in [ownLyrics, analysis, library, otherTemp]) {
      expect(f.existsSync(), isTrue, reason: '${f.path} is not cache');
    }
    expect(Directory(p.join(cache, 'artwork')).existsSync(), isTrue, reason: 'covers are written into it this launch');
    expect(Directory(p.join(cache, 'artwork')).listSync(), isEmpty);
    expect(Directory(p.join(temp, 'riflay-stream-old')).existsSync(), isFalse, reason: 'left by a crash');
  });

  test('nothing there is nothing to clear', () async {
    expect(await AppCache.size(), 0);
    expect(await AppCache.clear(), 0);
  });
}
