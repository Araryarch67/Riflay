import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/youtube_video_search.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Video video(String id, String title, String author, Duration? duration, {bool live = false}) => Video(
  VideoId(id),
  title,
  author,
  ChannelId('UCuAXFkgsw1L7xaCfnd5JJOw'),
  null,
  null,
  null,
  '',
  duration,
  ThumbnailSet(id),
  null,
  const Engagement(0, null, null),
  live,
);

void main() {
  test('search hits become streamable songs', () {
    final tracks = YoutubeVideoSearch.toTracks([
      video('dQw4w9WgXcQ', 'Never Gonna Give You Up', 'Rick Astley', const Duration(minutes: 3, seconds: 33)),
    ]);
    expect(tracks, hasLength(1));
    final t = tracks.single;
    expect(t.videoId, 'dQw4w9WgXcQ');
    expect(t.id, 'yt:dQw4w9WgXcQ');
    expect(t.title, 'Never Gonna Give You Up');
    expect(t.artist, 'Rick Astley');
    expect(t.duration, const Duration(minutes: 3, seconds: 33));
    expect(t.artworkUrl, 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
  });

  test('live streams, Shorts and lengthless hits are left out', () {
    final tracks = YoutubeVideoSearch.toTracks([
      video('aaaaaaaaaaa', 'Lofi radio', 'Chill', null, live: true),
      video('bbbbbbbbbbb', 'Live with length', 'Chill', const Duration(hours: 1), live: true),
      video('ccccccccccc', 'A short #shorts', 'Someone', const Duration(seconds: 30)),
      video('ddddddddddd', 'Exactly a minute #short', 'Someone', const Duration(seconds: 60)),
      video('eeeeeeeeeee', 'No length', 'Someone', null),
      video('fffffffffff', 'Real video', 'Someone', const Duration(minutes: 4)),
    ]);
    expect(tracks.map((t) => t.videoId), ['fffffffffff']);
  });

  test('order is kept', () {
    final tracks = YoutubeVideoSearch.toTracks([
      for (final (i, id) in ['aaaaaaaaaa1', 'aaaaaaaaaa2', 'aaaaaaaaaa3'].indexed)
        video(id, 'Song $i', 'Artist', const Duration(minutes: 3)),
    ]);
    expect(tracks.map((t) => t.title), ['Song 0', 'Song 1', 'Song 2']);
  });

  Video withText(String id, String title, Duration d, {String description = ''}) => Video(
    VideoId(id),
    title,
    'Someone',
    ChannelId('UCuAXFkgsw1L7xaCfnd5JJOw'),
    null,
    null,
    null,
    description,
    d,
    ThumbnailSet(id),
    null,
    const Engagement(0, null, null),
    false,
  );

  test('short songs are kept; only results tagged #shorts are hidden', () {
    final tracks = YoutubeVideoSearch.toTracks([
      withText('aaaaaaaaaa1', 'A 45 second song', d45),
      withText('aaaaaaaaaa2', 'Funny cat #shorts', d45),
      withText('aaaaaaaaaa3', 'Dance', d45, description: 'follow me #Shorts #fyp'),
      withText('aaaaaaaaaa4', 'Trick #YouTubeShorts', d45),
      withText('aaaaaaaaaa5', 'Long with #shorts tag', const Duration(minutes: 3)),
      withText('aaaaaaaaaa6', 'Shorts of the year (words only)', d45),
    ]);
    expect(tracks.map((t) => t.videoId), ['aaaaaaaaaa1', 'aaaaaaaaaa5', 'aaaaaaaaaa6']);
  });
}

const d45 = Duration(seconds: 45);
