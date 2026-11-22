import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/video_mode.dart';
import 'package:riflay/services/youtube_stream.dart';
import 'package:riflay/services/ytmusic_web.dart';
import 'package:riflay/ui/widgets/video_mode.dart';
import 'package:riflay/ui/widgets/video_quality.dart';
import 'package:riflay/services/layout_prefs.dart';
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

    test('a taller stream wins over the codec, but AV1 only with nothing else', () {
      final tall = [
        ...formats,
        f(313, 'video/webm; codecs="vp9"', 2160),
        f(401, 'video/mp4; codecs="av01.0.12M.08"', 4320),
      ];
      expect(
        YoutubeStream.pickVideo(tall, maxHeight: 4320)?['itag'],
        313,
        reason: '4K VP9 over 1080p H.264 and 8K AV1',
      );
      expect(
        YoutubeStream.pickVideo([f(401, 'video/mp4; codecs="av01.0.12M.08"', 2160)], maxHeight: 2160)?['itag'],
        401,
      );
    });

    test('the quality menu lists each height the video has once, tallest first', () {
      expect(YoutubeStream.videoHeights(formats), [1080, 720, 480]);
      expect(YoutubeStream.videoHeights([formats.last]), isEmpty, reason: 'sound only');
    });

    test('a picked height gives the tallest stream up to it, or the shortest when all are taller', () {
      expect(VideoMode.heightFor(1080, const [1080, 720, 480]), 1080);
      expect(VideoMode.heightFor(900, const [1080, 720, 480]), 720);
      expect(VideoMode.heightFor(240, const [1080, 720, 480]), 480);
      expect(VideoMode.heightFor(720, const []), isNull);
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
    expect(VideoMode.catchUpRate(const Duration(seconds: -5)), 1.4);
    expect(VideoMode.catchUpRate(const Duration(seconds: 5)), 0.7);
  });

  test('the video stays at the audio and timeline rate after correcting drift', () {
    const rate = 1.5 * 0.98;
    expect(VideoMode.catchUpRate(Duration.zero, baseRate: rate), rate);
    expect(VideoMode.catchUpRate(const Duration(milliseconds: -300), baseRate: rate), closeTo(rate + 0.1, 1e-9));
    expect(VideoMode.catchUpRate(const Duration(milliseconds: 300), baseRate: rate), closeTo(rate - 0.1, 1e-9));
  });

  test('a sound-only mpv build keeps the switch hidden', () {
    expect(VideoMode.decodesVideo('aac,alac,flac,mp3,opus,vorbis,wavpack'), isFalse);
    expect(VideoMode.decodesVideo('aac (AAC), h264 (H.264 / AVC), vp9 (Google VP9)'), isTrue);
    expect(VideoMode.decodesVideo('aac (AAC), h264_mediacodec (H.264 Android MediaCodec decoder)'), isTrue);
    // media_kit_video refuses to make a video output without h264.
    expect(VideoMode.decodesVideo('aac (AAC), vp9 (Google VP9), libdav1d (AV1)'), isFalse);
  });

  testWidgets('the Song / Video switch shows only for a song with a video, without a Beta badge', (tester) async {
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
    expect(find.byTooltip('Video'), findsNothing);
    expect(find.text('Beta'), findsNothing);

    VideoMode.instance.setOn(false);
    await tester.pumpWidget(app(song));
    expect(find.byTooltip('Song'), findsOneWidget);
    expect(find.byTooltip('Video'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
    expect(VideoMode.instance.on, isFalse);

    await tester.tap(find.byTooltip('Video'));
    await tester.pump();
    expect(VideoMode.instance.on, isTrue);
    expect(find.byTooltip('Adjust video timing'), findsOneWidget);
    await tester.tap(find.byTooltip('Adjust video timing'));
    await tester.pumpAndSettle();
    expect(find.text('Earlier'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    await tester.tap(find.text('Earlier'));
    await tester.pump();
    expect(find.text('0.5 s earlier'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pump();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    // Nothing is playing here, so no video loads: the cover stays.
    expect(find.text('cover'), findsOneWidget);

    // Going to the background keeps the choice (the video only pauses there).
    VideoMode.instance.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump();
    expect(VideoMode.instance.on, isTrue);
    VideoMode.instance.didChangeAppLifecycleState(AppLifecycleState.resumed);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  test('a view on screen stops asking for the video while the app is away, and asks again when back', () {
    final mode = VideoMode.instance;
    final wasOn = mode.on;
    mode.setOn(true);
    mode.addView();
    addTearDown(() {
      mode.didChangeAppLifecycleState(AppLifecycleState.resumed);
      mode.removeView();
      mode.setOn(wasOn);
    });
    expect(mode.debugForeground, isTrue);
    // Screen off / another app in front: the views stay mounted, but the video (decoder, buffers) is let go.
    mode.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(mode.debugForeground, isFalse);
    mode.didChangeAppLifecycleState(AppLifecycleState.hidden);
    expect(mode.debugForeground, isFalse);
    // A pulled-down shade (inactive) keeps it.
    mode.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(mode.debugForeground, isTrue);
    mode.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(mode.debugForeground, isTrue);
  });

  test('a stalling video comes down a step at a time, and back up no higher than the most allowed', () {
    expect(VideoMode.stepDown(1440), 1080);
    expect(VideoMode.stepDown(1080), 720);
    expect(VideoMode.stepDown(800), 720, reason: 'an odd height steps to the next one under it');
    expect(VideoMode.stepDown(360), isNull, reason: 'nothing under the bottom step');
    expect(VideoMode.stepUp(480, 1080), 720);
    expect(VideoMode.stepUp(720, 1080), 1080);
    expect(VideoMode.stepUp(1080, 1080), isNull);
  });

  testWidgets('the quality menu lists Auto and the video heights, and a pick is kept as the default', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await LayoutPrefs.instance.load();
    final mode = VideoMode.instance;
    Widget app() => const MaterialApp(
      home: Scaffold(body: Center(child: VideoQualityButton())),
    );

    mode.debugSetStream(const [], 0);
    await tester.pumpWidget(app());
    expect(find.byTooltip('Video quality'), findsNothing, reason: 'no streamed video: no menu');

    mode.debugSetStream(const [1080, 720, 480, 360, 144], 720);
    await tester.pump();
    await tester.tap(find.byTooltip('Video quality'));
    await tester.pumpAndSettle();
    expect(find.text('Auto (720p)'), findsOneWidget);
    for (final label in ['1080p HD', '720p HD', '480p', '360p', '144p']) {
      expect(find.text(label), findsOneWidget);
    }
    Icon? check(int height) => tester
        .widgetList<Icon>(
          find.descendant(of: find.byKey(ValueKey('video-quality-$height')), matching: find.byType(Icon)),
        )
        .firstOrNull;
    expect(check(0)?.icon, Icons.check_rounded, reason: 'Auto is the default');
    expect(check(480), isNull);

    await tester.tap(find.text('480p'));
    await tester.pumpAndSettle();
    expect(LayoutPrefs.instance.videoQuality, 480);
    expect(VideoMode.fixedQuality, 480);
    await tester.tap(find.byTooltip('Video quality'));
    await tester.pumpAndSettle();
    expect(check(480)?.icon, Icons.check_rounded);
    expect(check(0), isNull);

    await tester.tap(find.text('Auto (720p)'));
    await tester.pumpAndSettle();
    expect(LayoutPrefs.instance.videoQuality, 0);
    expect(VideoMode.fixedQuality, isNull);
    mode.debugSetStream(const [], 0);
    await tester.pumpWidget(const SizedBox());
  });
}
