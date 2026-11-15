import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:riflay/services/spotiflac.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Opt-in public catalogue tests. Only extension code is copied; account data,
// settings and verified sessions are never read or modified.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const live = bool.fromEnvironment('RIFLAY_TEST_SPOTIFLAC_SEARCH');
  const extensions = String.fromEnvironment('RIFLAY_SFLX_EXTENSIONS');
  const host = String.fromEnvironment('RIFLAY_SPOTIFLAC_HOST', defaultValue: 'build/spotiflac_bridge.exe');

  for (final provider in [
    'apple-music',
    'spotify-web',
    'amazon',
    'tidal-web',
    'deezer',
    'soundcloud',
    'jiosaavn',
    'ytmusic-spotiflac',
    'bugs-music',
    'genie-music',
  ]) {
    test(
      '$provider returns songs through the Dart search adapter',
      () async {
        final previousHttpOverrides = HttpOverrides.current;
        HttpOverrides.global = null;
        SharedPreferences.setMockInitialValues({});
        final root = await Directory.systemTemp.createTemp('riflay-search-');
        final engine = Spotiflac(executable: File(host).absolute.path, directory: root);
        Future<void> copy(Directory input, Directory output) async {
          await output.create(recursive: true);
          await for (final entity in input.list(followLinks: false)) {
            final target = p.join(output.path, p.basename(entity.path));
            if (entity is Directory) await copy(entity, Directory(target));
            if (entity is File) await entity.copy(target);
          }
        }

        try {
          await copy(Directory(p.join(extensions, provider)), Directory(p.join(root.path, 'extensions', provider)));
          await engine.load();
          await engine.enable(provider, true);
          final songs = await engine.search('BTS', provider: provider);
          expect(songs, isNotEmpty);
          expect(songs.every((song) => song.extensionId == provider && song.title.isNotEmpty), isTrue);
        } finally {
          HttpOverrides.global = previousHttpOverrides;
          await engine.close();
          await root.delete(recursive: true);
        }
      },
      skip: !Platform.isWindows || !live || extensions.isEmpty,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
