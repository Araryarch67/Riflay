import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/backup.dart';
import 'package:riflay/services/play_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

Track song(String name) =>
    Track(id: 'file:///music/$name.mp3', uri: Uri.parse('file:///music/$name.mp3'), title: name, artist: 'Artist');

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('backup');
    Backup.dirOverride = dir;
  });
  tearDown(() {
    Backup.dirOverride = null;
    dir.deleteSync(recursive: true);
  });

  test('a backup brings settings, playlists, history and lyrics back, but never sign-ins', () async {
    SharedPreferences.setMockInitialValues({
      'playlists.v1': jsonEncode([
        {'name': 'Road trip'},
      ]),
      'volume.v1': 0.6,
      'discord.enabled': false,
      'library.folders.v1': ['/music'],
      'lyrics.betterLyricsKey': 'secret',
      'musixmatch.token': 'secret',
    });
    final history = PlayHistory(file: File('${dir.path}/h.jsonl'));
    await history.load();
    history.record(song('a'), const Duration(seconds: 40), at: DateTime.utc(2026, 10, 1));
    history.record(song('b'), const Duration(seconds: 50), at: DateTime.utc(2026, 10, 2));
    Directory('${dir.path}/my-lyrics').createSync();
    File('${dir.path}/my-lyrics/abc.lrc').writeAsStringSync('[00:01.00]hi');

    final text = await Backup.create(history: history);
    expect(text, isNot(contains('secret')));
    final summary = Backup.read(text);
    expect(summary.playlists, 1);
    expect(summary.plays, 2);
    expect(summary.lyrics, 1);

    // Another device: different settings, its own key, no history, no lyrics.
    SharedPreferences.setMockInitialValues({'volume.v1': 1.0, 'loop.v1': 'all', 'lyrics.betterLyricsKey': 'mine'});
    File('${dir.path}/my-lyrics/abc.lrc').deleteSync();
    final other = PlayHistory(file: File('${dir.path}/other.jsonl'));
    await other.load();
    await Backup.restore(summary, history: other);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('volume.v1'), 0.6);
    expect(prefs.getBool('discord.enabled'), isFalse);
    expect(prefs.getStringList('library.folders.v1'), ['/music']);
    expect(prefs.getString('loop.v1'), isNull, reason: 'a setting the backup does not name goes back to its default');
    expect(prefs.getString('lyrics.betterLyricsKey'), 'mine', reason: 'secrets of this device stay');
    expect(other.length, 2);
    expect(other.playsOf(song('b').id), 1);
    expect(PlayHistory.parse(File('${dir.path}/other.jsonl').readAsStringSync()).plays, 2);
    expect(File('${dir.path}/my-lyrics/abc.lrc').readAsStringSync(), '[00:01.00]hi');
  });

  test('a file that isn\'t a backup is refused, and lyrics never land outside their folder', () async {
    expect(() => Backup.read('{"hello":1}'), throwsFormatException);
    expect(() => Backup.read('not json'), throwsFormatException);
    expect(() => Backup.read('{"riflay_backup":99,"prefs":{}}'), throwsFormatException);

    SharedPreferences.setMockInitialValues({});
    final summary = Backup.read(
      jsonEncode({
        'riflay_backup': 1,
        'prefs': {},
        'lyrics': {'../evil.lrc': 'x', 'ok.lrc': 'y'},
      }),
    );
    await Backup.restore(summary, history: PlayHistory(file: File('${dir.path}/h.jsonl')));
    expect(File('${dir.path}/evil.lrc').existsSync(), isFalse);
    expect(File('${dir.path}/my-lyrics/ok.lrc').existsSync(), isTrue);
  });

  test('file name carries the date', () {
    expect(Backup.fileName(DateTime(2026, 3, 7)), 'riflay-backup-2026-03-07.json');
  });
}
