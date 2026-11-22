import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:riflay/services/glass_image.dart';

void main() {
  test('the glass background is copied into the app, the copy before it removed', () async {
    final tmp = await Directory.systemTemp.createTemp('riflay-glass-');
    addTearDown(() => tmp.delete(recursive: true));
    final into = Directory(p.join(tmp.path, 'glass'));
    final first = await File(p.join(tmp.path, 'beach.jpg')).writeAsString('one');
    final kept = await keepGlassImage(first.path, into: into);
    expect(p.isWithin(into.path, kept), isTrue);
    expect(p.extension(kept), '.jpg');
    await first.delete();
    expect(await File(kept).readAsString(), 'one', reason: 'the original can go');

    await Future<void>.delayed(const Duration(milliseconds: 5));
    final second = await File(p.join(tmp.path, 'city.png')).writeAsString('two');
    final next = await keepGlassImage(second.path, into: into);
    expect(next, isNot(kept));
    expect(into.listSync().map((f) => f.path), [next]);
    // Picking the kept copy again keeps it as it is.
    expect(await keepGlassImage(next, into: into), next);
    // A file that isn't there stays its path.
    expect(await keepGlassImage(p.join(tmp.path, 'gone.jpg'), into: into), p.join(tmp.path, 'gone.jpg'));
  });
}
