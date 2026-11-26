import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/library_store.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('riflay-library-test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('an unreadable song is left out, the rest load, and the file is kept aside first', () {
    final file = File('${dir.path}/library.json');
    final text = jsonEncode([
      {'id': 'a', 'uri': 'file:///a.flac', 'title': 'A', 'artist': 'X'},
      {'id': 7},
    ]);
    file.writeAsStringSync(text);
    final tracks = LibraryStore.readFile(file);
    expect(tracks.map((t) => t.id), ['a']);
    expect(File('${file.path}.unreadable').readAsStringSync(), text);
  });

  test('a readable library leaves nothing aside', () {
    final file = File('${dir.path}/library.json')..writeAsStringSync('[]');
    expect(LibraryStore.readFile(file), isEmpty);
    expect(File('${file.path}.unreadable').existsSync(), isFalse);
  });
}
