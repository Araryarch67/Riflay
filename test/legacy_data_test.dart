import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:riflay/services/legacy_data.dart';

void main() {
  test('The old app\'s folder sits beside Riflay\'s', () {
    expect(
      LegacyData.oldSupportPath('/home/me/.local/share/dev.riflay.riflay', windows: false),
      '/home/me/.local/share/dev.openmusic.openmusic',
    );
    expect(
      LegacyData.oldSupportPath(r'C:\Users\Me\AppData\Roaming\dev.riflay\riflay', windows: true),
      r'C:\Users\Me\AppData\Roaming\dev.openmusic\openmusic',
    );
  });

  test('saved paths move with their folder, however they are written', () {
    const from = '/home/me/Documents/OpenMusic', to = '/home/me/Documents/Riflay';
    final settings = jsonEncode({
      'flutter.audio.v1': jsonEncode({'impulsePath': '$from/room.wav'}),
    });
    final moved = LegacyData.repoint(settings, from, to, windows: false);
    expect((jsonDecode(jsonDecode(moved)['flutter.audio.v1'] as String) as Map)['impulsePath'], '$to/room.wav');

    final id = Uri.file('$from/YouTube/My Song.m4a').toString();
    expect(
      LegacyData.repoint('{"id":"$id"}', from, to, windows: false),
      contains(Uri.file('$to/YouTube/My Song.m4a').toString()),
    );
    expect(
      LegacyData.repoint('"/home/me/Documents/OpenMusicOld/a.flac"', from, to, windows: false),
      '"/home/me/Documents/OpenMusicOld/a.flac"',
      reason: 'only what is inside the folder',
    );

    const wFrom = r'C:\Users\Me Too\Documents\OpenMusic', wTo = r'C:\Users\Me Too\Documents\Riflay';
    final wSettings = jsonEncode({
      'flutter.audio.v1': jsonEncode({'impulsePath': '$wFrom\\YouTube\\a.m4a'}),
      'path': '$wFrom\\YouTube\\a.m4a',
      'id': Uri.file('$wFrom\\YouTube\\a.m4a', windows: true).toString(),
    });
    final w = jsonDecode(LegacyData.repoint(wSettings, wFrom, wTo, windows: true)) as Map;
    expect((jsonDecode(w['flutter.audio.v1'] as String) as Map)['impulsePath'], '$wTo\\YouTube\\a.m4a');
    expect(w['path'], '$wTo\\YouTube\\a.m4a');
    expect(w['id'], Uri.file('$wTo\\YouTube\\a.m4a', windows: true).toString());
  });

  group('bringing the files over', () {
    late Directory root, old, support, oldDownloads, downloads;
    setUp(() {
      root = Directory.systemTemp.createTempSync('om-data');
      old = Directory(p.join(root.path, 'share', 'dev.openmusic.openmusic'))..createSync(recursive: true);
      support = Directory(p.join(root.path, 'share', 'dev.riflay.riflay'));
      oldDownloads = Directory(p.join(root.path, 'Documents', 'OpenMusic', 'YouTube'))..createSync(recursive: true);
      downloads = Directory(p.join(root.path, 'Documents', 'Riflay'));
    });
    tearDown(() => root.deleteSync(recursive: true));

    Future<void> run() =>
        LegacyData.bringOverFrom(old, support, oldDownloads: oldDownloads.parent, downloads: downloads);

    test('settings, library, sign-in and downloads come along, once', () async {
      final song = File(p.join(oldDownloads.path, 'Song.m4a'))..writeAsStringSync('audio');
      File(p.join(old.path, 'shared_preferences.json')).writeAsStringSync(
        jsonEncode({
          'flutter.audio.v1': jsonEncode({'impulsePath': p.join(old.path, 'impulse-1.wav')}),
        }),
      );
      File(p.join(old.path, 'impulse-1.wav')).writeAsStringSync('ir');
      File(p.join(old.path, 'library.json')).writeAsStringSync(
        jsonEncode([
          {'id': Uri.file(song.path).toString(), 'uri': Uri.file(song.path).toString()},
        ]),
      );
      final session = File(p.join(old.path, 'youtube_music_account.json'))..writeAsStringSync('{"cookie":"x"}');
      await Process.run('chmod', ['600', session.path]);
      File(p.join(old.path, 'bin', 'yt-dlp'))
        ..createSync(recursive: true)
        ..writeAsStringSync('tool');

      await run();

      final prefs = jsonDecode(File(p.join(support.path, 'shared_preferences.json')).readAsStringSync()) as Map;
      expect(
        (jsonDecode(prefs['flutter.audio.v1'] as String) as Map)['impulsePath'],
        p.join(support.path, 'impulse-1.wav'),
      );
      expect(File(p.join(support.path, 'impulse-1.wav')).readAsStringSync(), 'ir');
      final moved = p.join(downloads.path, 'YouTube', 'Song.m4a');
      expect(File(moved).readAsStringSync(), 'audio', reason: 'Documents/OpenMusic is now Documents/Riflay');
      expect(oldDownloads.parent.existsSync(), isFalse);
      expect(File(p.join(support.path, 'library.json')).readAsStringSync(), contains(Uri.file(moved).toString()));
      expect(File(p.join(support.path, 'bin', 'yt-dlp')).readAsStringSync(), 'tool');
      final copied = File(p.join(support.path, 'youtube_music_account.json'));
      expect(copied.readAsStringSync(), '{"cookie":"x"}');
      if (!Platform.isWindows) expect(copied.statSync().modeString(), 'rw-------', reason: 'the sign-in stays private');
      expect(old.existsSync(), isTrue, reason: 'the old app\'s own copy is left alone');

      // A second start changes nothing, even after Riflay saved new settings.
      File(p.join(support.path, 'shared_preferences.json')).writeAsStringSync('{"new":true}');
      await run();
      expect(File(p.join(support.path, 'shared_preferences.json')).readAsStringSync(), '{"new":true}');
    });

    test('a Riflay that already has its own data keeps it', () async {
      File(p.join(old.path, 'shared_preferences.json')).writeAsStringSync('{"old":true}');
      support.createSync(recursive: true);
      File(p.join(support.path, 'shared_preferences.json')).writeAsStringSync('{"mine":true}');
      await run();
      expect(File(p.join(support.path, 'shared_preferences.json')).readAsStringSync(), '{"mine":true}');
      expect(oldDownloads.existsSync(), isTrue, reason: 'nothing moved either');
    });
  });
}
