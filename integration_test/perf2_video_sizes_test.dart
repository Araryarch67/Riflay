// Extra perf 5 (needs the network, opt-in): time from asking for a music
// video's formats (what opening "Download as…" with Video selected does) until
// a size can be shown. Run: RIFLAY_NETWORK_TESTS=1 tool/perf_extra.sh video
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:riflay/services/download_prefs.dart';
import 'package:riflay/services/video_download.dart';
import 'package:riflay/services/youtube_stream.dart';

import 'perf2_common.dart';

const _videoId = 'dQw4w9WgXcQ'; // a public music video

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final enabled = Platform.environment['RIFLAY_NETWORK_TESTS'] == '1';

  testWidgets('video download size lookup', (tester) async {
    final perf = Perf2('video');
    final sw = Stopwatch()..start();
    final formats = await YoutubeStream.videoFormats(_videoId);
    final listed = sw.elapsedMilliseconds;
    final est = estimateVideoDownload(formats, const DownloadChoice.video(VideoContainer.mp4), ffmpeg: true);
    final sized = sw.elapsedMilliseconds;
    perf.report('cold lookup', {
      'formatsListedMs': listed,
      'sizeShownMs': sized,
      'videoStreams': formats.videos.length,
      'estimateBytes': est?.bytes ?? -1,
      'exact': est?.exact ?? false,
    });
    sw
      ..reset()
      ..start();
    final again = await YoutubeStream.videoFormats(_videoId);
    estimateVideoDownload(again, const DownloadChoice.video(VideoContainer.mp4), ffmpeg: true);
    perf.report('cached lookup', {'sizeShownMs': sw.elapsedMilliseconds});
    perf.budget('sizeShownMs', sized, budgetVideoSizesMs);
    perf.save();
  }, skip: !enabled);
}
