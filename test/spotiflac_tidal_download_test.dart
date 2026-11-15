import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:riflay/services/spotiflac.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Opt-in: uses the user's already verified source session, copied into an
// isolated runtime. Neither credentials nor provider responses are printed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'verified Tidal downloads HELP through Riflay, remuxes FLAC and decodes the entire song',
    () async {
      SharedPreferences.setMockInitialValues({});
      final support = Directory(p.join(Platform.environment['APPDATA']!, 'dev.riflay', 'riflay', 'spotiflac'));
      final root = await Directory.systemTemp.createTemp('riflay-tidal-live-');
      Future<void> copy(Directory input, Directory output) async {
        await output.create(recursive: true);
        await for (final item in input.list(followLinks: false)) {
          final target = p.join(output.path, p.basename(item.path));
          if (item is Directory) await copy(item, Directory(target));
          if (item is File) await item.copy(target);
        }
      }

      final engine = Spotiflac(executable: File('build/spotiflac_bridge.exe').absolute.path, directory: root);
      try {
        for (final name in ['extensions', 'data']) {
          await copy(Directory(p.join(support.path, name)), Directory(p.join(root.path, name)));
        }
        await engine.load();
        final data = await engine.call('call', {
          'extension': 'tidal-web',
          'operation': 'track',
          'args': {'track': 'tidal:352392340'},
        });
        final source = Spotiflac.track('tidal-web', Map<String, dynamic>.from(data as Map))!;
        final saved = await engine.download(source, await Directory(p.join(root.path, 'downloads')).create());
        expect(saved.path, endsWith('.flac'));
        expect(await File(saved.path!).length(), greaterThan(1024 * 1024));
        final decoded = await Process.run('ffmpeg', ['-v', 'error', '-i', saved.path!, '-f', 'null', '-']);
        expect(decoded.exitCode, 0, reason: '${decoded.stderr}');
        expect('${decoded.stderr}'.trim(), isEmpty);
        expect(saved.offlineId, source.offlineId);
      } finally {
        await engine.close();
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows || !const bool.fromEnvironment('RIFLAY_TEST_TIDAL_DOWNLOAD'),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
