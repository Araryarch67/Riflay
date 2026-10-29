import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/youtube_stream.dart';
import 'package:riflay/services/ytmusic_web.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Needs the internet: `RIFLAY_NETWORK_TESTS=1 flutter test test/video_lookup_network_test.dart`. Prints how long the
/// Video sizes of the download picker take to be known, cold and then again. (A plain `test`, no widget binding:
/// the binding answers every request with 400.)
void main() {
  test(
    'music video sizes: cold and warm lookup times',
    () async {
      SharedPreferences.setMockInitialValues({});
      final web = YtMusicWeb.anonymous();
      YoutubeStream.musicVideoIdLookup = (id) async => (await web.musicVideo(id))?.videoId;
      addTearDown(() => YoutubeStream.musicVideoIdLookup = null);
      for (final id in ['dQw4w9WgXcQ', 'kJQP7kiw5Fk']) {
        for (final label in ['cold', 'warm']) {
          final sw = Stopwatch()..start();
          final f = await YoutubeStream.musicVideoFormats(id);
          stdout.writeln('AFTER $id $label ${sw.elapsedMilliseconds} ms (${f?.videos.length} video streams)');
          expect(f, isNotNull);
          expect(f!.videos.any((v) => v.sizeBytes != null), isTrue, reason: 'contentLength is in the listing');
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: Platform.environment['RIFLAY_NETWORK_TESTS'] != '1' ? 'needs the internet: RIFLAY_NETWORK_TESTS=1' : false,
  );
}
