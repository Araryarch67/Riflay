import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/spoken_word.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SpokenWord w;
  const total = Duration(hours: 5);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    w = SpokenWord();
    await w.load();
  });

  test('only a marked track is a book; unmarking drops its data', () async {
    expect(w.isBook('a'), isFalse);
    await w.savePosition('a', const Duration(minutes: 10), total);
    expect(w.resumeAt('a'), isNull);
    await w.setBook('a', true);
    await w.savePosition('a', const Duration(minutes: 10), total);
    expect(w.resumeAt('a'), const Duration(minutes: 10));
    await w.setBook('a', false);
    expect(w.resumeAt('a'), isNull);
  });

  test('a book that has barely started or is nearly over starts from the top', () async {
    await w.setBook('a', true);
    await w.savePosition('a', const Duration(seconds: 3), total);
    expect(w.resumeAt('a'), isNull);
    await w.savePosition('a', const Duration(minutes: 30), total);
    await w.savePosition('a', total - const Duration(seconds: 5), total);
    expect(w.resumeAt('a'), isNull);
  });

  test('speed is per book and kept within the tempo limits', () async {
    await w.setBook('a', true);
    await w.setBook('b', true);
    await w.setTempo('a', 1.5);
    await w.setTempo('b', 9);
    expect(w.tempoOf('a'), 1.5);
    expect(w.tempoOf('b'), 2.0);
    expect(w.tempoOf('unmarked'), 1);
  });

  test('bookmarks stay in book order, keep their note and can be removed', () async {
    await w.setBook('a', true);
    await w.addBookmark('a', const Duration(minutes: 20), ' later ');
    await w.addBookmark('a', const Duration(minutes: 5), 'early');
    final marks = w.bookmarks('a');
    expect([for (final m in marks) m.at.inMinutes], [5, 20]);
    expect(marks.last.note, 'later');
    await w.removeBookmark('a', marks.first);
    expect(w.bookmarks('a').length, 1);
    await w.addBookmark('nope', Duration.zero, 'x');
    expect(w.bookmarks('nope'), isEmpty);
  });

  test('everything survives a restart', () async {
    await w.setBook('a', true);
    await w.savePosition('a', const Duration(minutes: 42), total);
    await w.setTempo('a', 1.25);
    await w.addBookmark('a', const Duration(minutes: 7), 'harbour');
    final again = SpokenWord();
    await again.load();
    expect(again.resumeAt('a'), const Duration(minutes: 42));
    expect(again.tempoOf('a'), 1.25);
    expect(again.bookmarks('a').single.note, 'harbour');
  });

  test('an unreadable save leaves no books instead of failing', () async {
    SharedPreferences.setMockInitialValues({'spoken.books': 'not json'});
    final x = SpokenWord();
    await x.load();
    expect(x.isBook('a'), isFalse);
  });
}
