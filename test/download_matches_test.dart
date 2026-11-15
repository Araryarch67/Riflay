import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/download_matches.dart';
import 'package:riflay/services/monochrome.dart';
import 'package:riflay/services/spotiflac.dart';
import 'package:riflay/services/library_views.dart';
import 'package:riflay/services/youtube_importer.dart';

void main() {
  final origin = Track.youtube(
    videoId: 'abcdefghijk',
    title: 'First Love',
    artist: 'Kobo Kanaeru',
    duration: const Duration(seconds: 235),
  );
  final match = Spotiflac.track('tidal-web', {
    'id': 'tidal:1',
    'name': 'First Love',
    'artists': 'Kobo Kanaeru',
    'duration_ms': 235000,
  })!;
  test('matching prefers the same artist, recording version and duration', () {
    final remix = Track.youtube(
      videoId: 'bbbbbbbbbbb',
      title: 'First Love Remix',
      artist: origin.artist,
      duration: origin.duration,
    );
    final cover = Track.youtube(
      videoId: 'ccccccccccc',
      title: origin.title,
      artist: 'Another artist',
      duration: origin.duration,
    );
    final preview = match.copyWith(duration: const Duration(seconds: 30));
    expect(DownloadMatches.rank(origin, [remix, cover, preview, match]).first, same(match));
    expect(DownloadMatches.score(origin, remix), lessThan(.5));
  });
  test('provider and YouTube IDs both resolve to a local file after persistence', () {
    final uri = Uri.file('/music/song.flac');
    final saved = Track(
      id: uri.toString(),
      uri: uri,
      title: match.title,
      artist: match.artist,
      sourceUrl: match.uri.toString(),
      downloadYoutubeId: origin.videoId,
    );
    final restored = Track.fromJson(saved.toJson());
    expect(restored.streams, isFalse);
    expect(restored.youtubeId, origin.videoId);
    expect(restored.copyWith(title: 'Changed').downloadYoutubeId, origin.videoId);
    final views = LibraryViews([restored], 1);
    expect(views.downloads[origin.offlineId], same(restored));
    expect(views.downloads[match.offlineId], same(restored));
  });
  test('cross-source jobs preserve the origin and reject a tampered queue key', () {
    final job = DownloadJob(
      videoId: origin.videoId!,
      title: match.title,
      channel: match.artist,
      thumbnailUrl: '',
      extensionTrack: match,
      youtubeOrigin: origin,
      extensionQuality: 'LOSSLESS',
    );
    final restored = DownloadJob.fromJson(job.toJson())!;
    expect(restored.youtubeOrigin?.videoId, origin.videoId);
    expect(restored.extensionTrack?.id, match.id);
    expect(restored.extensionQuality, 'LOSSLESS');
    final altered = job.toJson()!..['videoId'] = 'bbbbbbbbbbb';
    expect(DownloadJob.fromJson(altered), isNull);
    final mono = Monochrome.track({
      'trackId': '165781419838844928',
      'title': 'Song',
      'artistNames': ['Artist'],
    }, native: true)!;
    final monoJob = DownloadJob(
      videoId: origin.videoId!,
      title: mono.title,
      channel: mono.artist,
      thumbnailUrl: '',
      monochromeTrack: mono,
      youtubeOrigin: origin,
    );
    expect(DownloadJob.fromJson(monoJob.toJson())?.youtubeOrigin?.id, origin.id);
  });
}
