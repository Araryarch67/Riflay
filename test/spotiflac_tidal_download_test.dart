import 'dart:io';
import 'dart:async';

import 'package:riflay/services/youtube_importer.dart';
import 'package:riflay/services/download_prefs.dart';
import 'package:riflay/services/ytmusic_web.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/library_views.dart';

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
      final previousHttpOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
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
        final results = await YtMusicWeb.anonymous().search('HELP!! Kobo Kanaeru');
        final hit = results.songs.firstWhere(
          (song) => song.title.toUpperCase().contains('HELP') && song.artist.toLowerCase().contains('kobo'),
        );
        final origin = Track.youtube(
          videoId: hit.videoId,
          title: hit.title,
          artist: hit.artist,
          duration: hit.duration,
        );
        final folder = await Directory(p.join(root.path, 'downloads')).create();
        await DownloadPrefs.instance.load();
        await DownloadPrefs.instance.setFolder(folder.path);
        final ready = Completer<Track>();
        final importer = YoutubeImporter(
          extensionRuntime: engine,
          onTrackReady: (track) async {
            ready.complete(track);
          },
        );
        importer.addListener(() {
          for (final job in importer.jobs) {
            if (job.status == DownloadStatus.failed && !ready.isCompleted) {
              ready.completeError(StateError(job.error ?? 'Download failed'));
            }
          }
        });
        late Track saved;
        try {
          expect(importer.enqueueTracks([source], youtubeOrigin: origin, extensionQuality: 'LOSSLESS'), 1);
          saved = await ready.future.timeout(const Duration(minutes: 4));
        } finally {
          await Future<void>.delayed(Duration.zero);
          importer.dispose();
        }
        expect(saved.youtubeId, origin.videoId);
        final restored = Track.fromJson(saved.toJson());
        final views = LibraryViews([restored], 1);
        expect(views.downloads[origin.offlineId]?.id, restored.id);
        expect(views.downloads[source.offlineId]?.id, restored.id);
        expect(saved.path, endsWith('.flac'));
        expect(await File(saved.path!).length(), greaterThan(1024 * 1024));
        final decoded = await Process.run('ffmpeg', ['-v', 'error', '-i', saved.path!, '-f', 'null', '-']);
        expect(decoded.exitCode, 0, reason: '${decoded.stderr}');
        expect('${decoded.stderr}'.trim(), isEmpty);
        expect(saved.streams, isFalse);
      } finally {
        HttpOverrides.global = previousHttpOverrides;
        await engine.close();
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows || !const bool.fromEnvironment('RIFLAY_TEST_TIDAL_DOWNLOAD'),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
