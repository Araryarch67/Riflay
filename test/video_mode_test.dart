import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/video_mode.dart';
import 'package:riflay/services/youtube_stream.dart';
import 'package:riflay/services/ytmusic_web.dart';
import 'package:riflay/ui/pages/listen_together_page.dart' show BetaBadge;
import 'package:riflay/ui/widgets/video_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A `next` response with one queue row, as YouTube Music sends it.
Map<String, dynamic> _next(Map<String, dynamic> row) => {
  'contents': {
    'singleColumnMusicWatchNextResultsRenderer': {
      'playlistPanelRenderer': {
        'contents': [row],
      },
    },
  },
};

Map<String, dynamic> _row(String id, String type) => {
  'playlistPanelVideoRenderer': {
    'videoId': id,
    'navigationEndpoint': {
      'watchEndpoint': {
        'videoId': id,
        'watchEndpointMusicSupportedConfigs': {
          'watchEndpointMusicConfig': {'musicVideoType': type},
        },
      },
    },
  },
};

void main() {
  group('which songs have a video', () {
    test('a song that is a video plays its own picture, on the same timeline', () {
      final v = YtMusicWeb.parseMusicVideo(_next(_row('omv', 'MUSIC_VIDEO_TYPE_OMV')), 'omv');
      expect(v?.videoId, 'omv');
      expect(v?.videoTimeAt(const Duration(seconds: 42)), const Duration(seconds: 42));
      expect(YtMusicWeb.parseMusicVideo(_next(_row('ugc', 'MUSIC_VIDEO_TYPE_UGC')), 'ugc')?.videoId, 'ugc');
    });

    test('a song with only its cover has no video', () {
      expect(YtMusicWeb.parseMusicVideo(_next(_row('atv', 'MUSIC_VIDEO_TYPE_ATV')), 'atv'), isNull);
      // Another song's row says nothing about this one.
      expect(YtMusicWeb.parseMusicVideo(_next(_row('other', 'MUSIC_VIDEO_TYPE_OMV')), 'atv'), isNull);
      expect(YtMusicWeb.parseMusicVideo(const {}, 'atv'), isNull);
    });

    test('a song paired with its video follows the parts both share', () {
      final v = YtMusicWeb.parseMusicVideo(
        _next({
          'playlistPanelVideoWrapperRenderer': {
            'primaryRenderer': _row('atv', 'MUSIC_VIDEO_TYPE_ATV'),
            'counterpart': [
              {
                'counterpartRenderer': _row('omv', 'MUSIC_VIDEO_TYPE_OMV'),
                'segmentMap': {
                  'segment': [
                    {
                      'primaryVideoStartTimeMilliseconds': '0',
                      'counterpartVideoStartTimeMilliseconds': '15000',
                      'durationMilliseconds': '180000',
                    },
                  ],
                },
              },
            ],
          },
        }),
        'atv',
      );
      expect(v?.videoId, 'omv');
      // The video has a 15-second intro the song doesn't.
      expect(v?.videoTimeAt(Duration.zero), const Duration(seconds: 15));
      expect(v?.videoTimeAt(const Duration(seconds: 60)), const Duration(seconds: 75));
      // Past the shared part: the video has nothing for it.
      expect(v?.videoTimeAt(const Duration(minutes: 3, seconds: 10)), isNull);
    });
  });

  group('picking the video stream', () {
    Map<String, dynamic> f(int itag, String mime, int? height) => {
      'itag': itag,
      'mimeType': mime,
      'height': ?height,
      'url': 'https://example.invalid/$itag',
    };
    final formats = [
      f(137, 'video/mp4; codecs="avc1.640028"', 1080),
      f(247, 'video/webm; codecs="vp9"', 720),
      f(136, 'video/mp4; codecs="avc1.4D401F"', 720),
      f(398, 'video/mp4; codecs="av01.0.05M.08"', 720),
      f(244, 'video/webm; codecs="vp9"', 480),
      f(251, 'audio/webm; codecs="opus"', null),
    ];

    test('the tallest stream allowed, H.264 before VP9 before AV1', () {
      expect(YoutubeStream.pickVideo(formats, maxHeight: 720)?['itag'], 136);
      expect(YoutubeStream.pickVideo(formats, maxHeight: 480)?['itag'], 244);
      expect(YoutubeStream.pickVideo(formats.where((x) => x['itag'] != 136).toList(), maxHeight: 720)?['itag'], 247);
    });

    test('never audio, a stream without a URL, or nothing short enough', () {
      expect(YoutubeStream.pickVideo([formats.last], maxHeight: 720), isNull);
      expect(YoutubeStream.pickVideo([formats[2]..remove('url')], maxHeight: 720), isNull);
      expect(YoutubeStream.pickVideo([formats.first], maxHeight: 480), isNull);
    });
  });

  test('a seek learns how far ahead to aim', () {
    // It landed 900 ms behind: aim that much further ahead next time.
    expect(
      VideoMode.nextLead(const Duration(milliseconds: 600), const Duration(milliseconds: -900)),
      const Duration(milliseconds: 1500),
    );
    expect(
      VideoMode.nextLead(const Duration(milliseconds: 600), const Duration(milliseconds: 200)),
      const Duration(milliseconds: 400),
    );
    expect(
      VideoMode.nextLead(const Duration(milliseconds: 200), const Duration(seconds: 1)),
      const Duration(milliseconds: 150),
    );
    expect(VideoMode.nextLead(const Duration(seconds: 3), const Duration(seconds: -5)), const Duration(seconds: 4));
  });

  test('a small gap closes by speed, gently', () {
    expect(VideoMode.catchUpRate(const Duration(milliseconds: 30)), 1);
    expect(VideoMode.catchUpRate(const Duration(milliseconds: -300)), closeTo(1.1, 1e-9)); // behind: faster
    expect(VideoMode.catchUpRate(const Duration(milliseconds: 300)), closeTo(0.9, 1e-9)); // ahead: slower
    expect(VideoMode.catchUpRate(const Duration(seconds: -5)), 1.25);
  });

  test('a sound-only mpv build keeps the switch hidden', () {
    expect(VideoMode.decodesVideo('aac,alac,flac,mp3,opus,vorbis,wavpack'), isFalse);
    expect(VideoMode.decodesVideo('aac (AAC), h264 (H.264 / AVC), vp9 (Google VP9)'), isTrue);
  });

  testWidgets('the Song / Video switch shows only for a song with a video, marked Beta', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = PlayerController();
    final song = Track.youtube(videoId: 'withvideo', title: 'S', artist: 'A');
    final plain = Track.youtube(videoId: 'novideo', title: 'P', artist: 'A');
    VideoMode.instance
      ..debugSetFound('withvideo', const MusicVideo(videoId: 'withvideo'))
      ..debugSetFound('novideo', null);
    Widget app(Track track) => MaterialApp(
      home: PlayerScope(
        controller: controller,
        child: Scaffold(
          body: Column(
            children: [
              VideoModeSwitch(track: track),
              SizedBox.square(
                dimension: 200,
                child: TrackVisual(track: track, cover: const Text('cover')),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pumpWidget(app(plain));
    expect(find.text('Video'), findsNothing);
    expect(find.byType(BetaBadge), findsNothing);

    await tester.pumpWidget(app(song));
    expect(find.text('Song'), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);
    expect(find.byType(BetaBadge), findsOneWidget);
    expect(VideoMode.instance.on, isFalse);

    await tester.tap(find.text('Video'));
    await tester.pump();
    expect(VideoMode.instance.on, isTrue);
    // Nothing is playing here, so no video loads: the cover stays.
    expect(find.text('cover'), findsOneWidget);

    // Going to the background turns it back into Song.
    VideoMode.instance.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump();
    expect(VideoMode.instance.on, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
