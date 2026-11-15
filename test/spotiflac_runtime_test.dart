import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/library_views.dart';
import 'package:riflay/services/spotiflac.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const live = bool.fromEnvironment('RIFLAY_TEST_SPOTIFLAC');
  const packagePath = String.fromEnvironment('RIFLAY_SFLX_PACKAGE');

  test(
    'real .sflx: install, enable, search, download, decode and index offline audio',
    () async {
      SharedPreferences.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('riflay-live-sflx-');
      final engine = Spotiflac(executable: File('build/spotiflac_bridge.exe').absolute.path, directory: dir);
      try {
        await engine.load();
        await engine.install(packagePath);
        expect(engine.plugin('jiosaavn'), isNotNull);
        expect(engine.searchProviders, isEmpty, reason: 'installing does not silently enable a provider');
        await engine.enable('jiosaavn', true);
        await engine.choose('jiosaavn');
        final songs = await engine.search('Arijit Singh');
        expect(songs, isNotEmpty);
        final source = songs.first;
        expect(source.extensionId, 'jiosaavn');
        expect(source.streams, isTrue);
        expect(Track.fromJson(source.toJson()).extensionData?['id'], source.extensionData?['id']);
        final downloads = await Directory('${dir.path}/downloads').create();
        final saved = await engine.download(source, downloads);
        expect(saved.path, isNotNull);
        expect(await File(saved.path!).length(), greaterThan(1024 * 1024));
        expect(saved.streams, isFalse);
        expect(saved.offlineId, source.offlineId);
        final views = LibraryViews([source, saved], 1);
        expect(views.downloads[source.offlineId]?.id, saved.id);
        final decoded = await Process.run('ffmpeg', ['-v', 'error', '-i', saved.path!, '-f', 'null', '-']);
        expect(decoded.exitCode, 0, reason: '${decoded.stderr}');
        expect('${decoded.stderr}'.trim(), isEmpty);
        await engine.saveSettings('jiosaavn', {'lang': 'english'});
        expect((await engine.settings('jiosaavn'))['lang'], 'english');
        await engine.enable('jiosaavn', false);
        expect(engine.searchProviders, isEmpty);
        await engine.remove('jiosaavn');
        expect(engine.plugins, isEmpty);
      } finally {
        await engine.close();
        await dir.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows || !live || packagePath.isEmpty,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
