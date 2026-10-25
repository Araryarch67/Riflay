// FFmpeg fetched on first use (no ffmpeg on PATH): downloaded, checked against
// its published checksum, run, and used by the tag editor on a Matroska file
// (MP3, Ogg, WAV and the rest are written in Dart: lib/services/tag_writer.dart).
//
// Downloads about 40 MB into the app's data folder; run it with a throwaway
// one and with ffmpeg off the PATH:
//   flutter test integration_test/zz_ffmpeg_download_test.dart -d windows   (or -d linux)
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/ffmpeg.dart';
import 'package:riflay/services/metadata.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ffmpeg is fetched when first needed, and edits a Matroska file\'s tags', (tester) async {
    await Ffmpeg.probe();
    if (Ffmpeg.installed) {
      markTestSkipped('ffmpeg is already here (on PATH or downloaded before)');
      return;
    }
    expect(Ffmpeg.available, isTrue, reason: 'offered for download on this OS');
    expect(Metadata.canEditTags(Track.fromUri(Uri.file('/music/song.mka'))), isTrue, reason: 'MKA tags are editable');

    final notices = <String>[];
    Ffmpeg.onDownload = notices.add;
    final exe = await tester.runAsync(Ffmpeg.executable);
    expect(notices, hasLength(1), reason: 'the user hears about the download once');
    expect(Ffmpeg.installed, isTrue);
    expect(File(exe!).existsSync(), isTrue);

    final dir = Directory.systemTemp.createTempSync('om-ffmpeg');
    addTearDown(() => dir.deleteSync(recursive: true));
    final mka = '${dir.path}${Platform.pathSeparator}song.mka';
    final made = await tester.runAsync(
      () => Process.run(exe, [
        '-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', 'sine=f=440:d=2', //
        '-c:a', 'flac', '-metadata', 'title=Before', mka,
      ]),
    );
    expect(made!.exitCode, 0, reason: '${made.stderr}');

    final track = Track.fromUri(Uri.file(mka));
    await tester.runAsync(() => Metadata.writeTags(track, TagEdit(title: 'After', artist: 'Riflay')));
    final tags = readMetadata(File(mka));
    expect(tags.title, 'After');
    expect(tags.artist, 'Riflay');
  });
}
