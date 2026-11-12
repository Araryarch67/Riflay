import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/download_prefs.dart';
import 'package:riflay/services/folder_watch.dart';
import 'package:riflay/services/mv_sidecar.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/video_download.dart';
import 'package:riflay/services/video_mode.dart';
import 'package:riflay/services/youtube_importer.dart';
import 'package:riflay/services/ytmusic_web.dart';
import 'package:riflay/ui/debug_switches.dart';
import 'package:riflay/ui/player/more_sheet.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/track_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

VideoCandidate _v(int h, VideoCodec codec, {int fps = 30, bool progressive = false}) => VideoCandidate(
  id: '$h-${codec.name}-$fps',
  height: h,
  codec: codec,
  fps: fps,
  webm: codec == VideoCodec.vp9,
  progressive: progressive,
);

const _aac = AudioCandidate(id: '140', opus: false, kbps: 130);
const _opus = AudioCandidate(id: '251', opus: true, kbps: 128);

final _typical = VideoFormats(
  [
    _v(2160, VideoCodec.vp9),
    _v(2160, VideoCodec.av1),
    _v(1080, VideoCodec.avc),
    _v(1080, VideoCodec.vp9),
    _v(720, VideoCodec.avc),
    _v(360, VideoCodec.avc, progressive: true),
  ],
  const [_aac, _opus],
);

const _withVideo = 'mvyes_song1', _noVideo = 'mvnot_song1';

Widget _app(PlayerController controller, Widget body) => MaterialApp(
  home: PlayerScope(
    controller: controller,
    child: ShellScope(
      compact: false,
      width: 800,
      open: (_, {location}) {},
      openCollection: (_) {},
      openQueue: () {},
      openNowPlaying: () {},
      openLyrics: () {},
      openDownloads: () {},
      importFromYoutube: () {},
      addFiles: () {},
      addFolder: null,
      child: Scaffold(body: body),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Read once outside any widget test: a first read inside one would stay tied to that test's clock.
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await DownloadPrefs.instance.load();
  });

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('riflay-mv-'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('the files beside the song', () {
    test('the map of the song in the video round-trips', () {
      const paired = MusicVideo(
        videoId: 'omv',
        segments: [
          VideoSegment(songStart: Duration.zero, videoStart: Duration(seconds: 15), length: Duration(minutes: 3)),
        ],
      );
      final back = MvSidecar.decode(MvSidecar.encode(paired))!;
      expect(back.videoId, 'omv');
      expect(back.videoTimeAt(const Duration(seconds: 60)), const Duration(seconds: 75));
      expect(back.videoTimeAt(const Duration(minutes: 4)), isNull);

      final measured = const MusicVideo(videoId: 'found').shifted(const Duration(milliseconds: 1100), 1.003);
      final again = MvSidecar.decode(MvSidecar.encode(measured))!;
      expect(again.offset, const Duration(milliseconds: 1100));
      expect(again.rate, 1.003);
      expect(again.segments, isEmpty);
    });

    test('unreadable text is no map', () {
      expect(MvSidecar.decode('not json'), isNull);
      expect(MvSidecar.decode('{"videoId": 3}'), isNull);
      expect(MvSidecar.decode('{"videoId": "v", "segments": [[1, 2]]}'), isNull);
    });

    test('a song has its video only when the file is there; deleting removes all of it', () async {
      final song = p.join(dir.path, 'abcdefghijk.opus');
      File(song).writeAsBytesSync(const [1]);
      expect(MvSidecar.of(song), isNull);

      MvSidecar.videoFile(song, 'mp4').writeAsBytesSync(const [1, 2, 3]);
      await MvSidecar.write(song, const MusicVideo(videoId: 'omv', offset: Duration(seconds: 2)));
      final found = MvSidecar.of(song)!;
      expect(found.file.path, p.join(dir.path, 'abcdefghijk.mv.mp4'));
      expect(found.video.videoId, 'omv');
      expect(found.video.offset, const Duration(seconds: 2));
      expect(MvSidecar.bytesOf(song), 3);
      // Asked again: the same answer, not another read.
      expect(identical(MvSidecar.of(song)!.video, found.video), isTrue);

      expect(await MvSidecar.delete(song), 0);
      expect(MvSidecar.of(song), isNull);
      expect(dir.listSync().map((f) => p.basename(f.path)), ['abcdefghijk.opus']);
    });

    test('a video with no readable map plays on the song\'s own timeline', () {
      final song = p.join(dir.path, 'abcdefghijk.m4a');
      MvSidecar.videoFile(song, 'webm').writeAsBytesSync(const [1]);
      final found = MvSidecar.of(song)!;
      expect(found.video.videoId, 'abcdefghijk');
      expect(found.video.videoTimeAt(const Duration(seconds: 9)), const Duration(seconds: 9));
    });

    test('RIFLAY_NO_LOCAL_MV: as if there were none', () {
      final song = p.join(dir.path, 'abcdefghijk.opus');
      MvSidecar.videoFile(song, 'mp4').writeAsBytesSync(const [1]);
      DebugSwitches.noLocalMv = true;
      addTearDown(() => DebugSwitches.noLocalMv = false);
      expect(MvSidecar.of(song), isNull);
    });

    test('a folder scan does not take the video for a song', () {
      expect(isIgnoredPath('/music/abcdefghijk.mv.webm'), isTrue);
      expect(isIgnoredPath('/music/abcdefghijk.mv.mp4'), isTrue);
      expect(isIgnoredPath('/music/abcdefghijk.webm'), isFalse);
      expect(MvSidecar.isSidecar('/music/abcdefghijk.mv.json'), isTrue);
      expect(MvSidecar.isSidecar('/music/abcdefghijk.opus'), isFalse);
    });
  });

  group('which picture is saved', () {
    test('Settings\' default: H.264 as MP4, 1080p at most', () {
      final pick = pickMusicVideoPicture(_typical, recommendedVideoChoice)!;
      expect(pick.id, '1080-avc-30');
      expect(pick.ext, 'mp4');
    });

    test('WebM takes VP9, never an AV1 that would need converting', () {
      final pick = pickMusicVideoPicture(_typical, const DownloadChoice.video(VideoContainer.webm, height: null))!;
      expect(pick.codec, VideoCodec.vp9);
      expect(pick.height, 2160);
      expect(pick.ext, 'webm');
    });

    test('a container the video does not have falls back to the other one', () {
      final h264Only = VideoFormats([_v(720, VideoCodec.avc), _v(1080, VideoCodec.av1)], const [_aac, _opus]);
      final pick = pickMusicVideoPicture(h264Only, const DownloadChoice.video(VideoContainer.webm))!;
      expect(pick.id, '720-avc-30');
    });

    test('nothing that can be kept as it is: no video', () {
      final av1Only = VideoFormats(
        [_v(1080, VideoCodec.av1), _v(360, VideoCodec.avc, progressive: true)],
        const [_aac],
      );
      expect(pickMusicVideoPicture(av1Only, recommendedVideoChoice), isNull);
    });

    test('an audio choice still saves the default picture', () {
      expect(pickMusicVideoPicture(_typical, const DownloadChoice(DownloadFormat.flac))!.ext, 'mp4');
    });
  });

  group('the queue', () {
    test('"with MV" and its partial file survive a restart; a plain download stays plain', () {
      final withMv = DownloadJob(
        videoId: 'aaaaaaaaaaa',
        title: 'S',
        channel: 'A',
        thumbnailUrl: '',
        knownNames: true,
        withVideo: true,
      )..videoParts['mv'] = (itag: '137', size: 1000, ext: 'mp4');
      final plain = DownloadJob(videoId: 'bbbbbbbbbbb', title: 'P', channel: 'A', thumbnailUrl: '', knownNames: true);
      final back = YoutubeImporter.decodeQueue(YoutubeImporter.encodeQueue([withMv, plain]));
      expect(back[0].withVideo, isTrue);
      expect(back[0].videoParts['mv'], (itag: '137', size: 1000, ext: 'mp4'));
      expect(back[1].withVideo, isFalse);
    });
  });

  group('playing and deleting', () {
    test('Video mode plays the saved file, on the saved timeline; deleting the song deletes it', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = PlayerController();
      final songFile = File(p.join(dir.path, 'ccccccccccc.opus'))..writeAsBytesSync(const [1]);
      final plainFile = File(p.join(dir.path, 'ddddddddddd.opus'))..writeAsBytesSync(const [1]);
      Track download(File f) => Track(
        id: Uri.file(f.path).toString(),
        uri: Uri.file(f.path),
        title: 'S',
        artist: 'A',
        sourceUrl: 'https://www.youtube.com/watch?v=${p.basenameWithoutExtension(f.path)}',
      );
      final song = download(songFile), plain = download(plainFile);
      MvSidecar.videoFile(songFile.path, 'mp4').writeAsBytesSync(const [1, 2]);
      await MvSidecar.write(songFile.path, const MusicVideo(videoId: 'theomvid123', offset: Duration(seconds: 3)));

      final mode = VideoMode.instance
        ..follow(controller)
        ..debugSetFound('unrelated-mv', null);
      expect(mode.localVideoOf(song)?.path, p.join(dir.path, 'ccccccccccc.mv.mp4'));
      expect(mode.videoOf(song)?.videoId, 'theomvid123');
      expect(mode.videoOf(song)?.videoTimeAt(Duration.zero), const Duration(seconds: 3));
      // A download without one has no video offline.
      expect(mode.localVideoOf(plain), isNull);
      expect(mode.videoOf(plain), isNull);

      await controller.deleteDownloads([song]);
      expect(songFile.existsSync(), isFalse);
      expect(dir.listSync().map((f) => p.basename(f.path)), ['ddddddddddd.opus']);
      expect(mode.videoOf(song), isNull);
    });
  });

  group('"Download with MV"', () {
    late PlayerController controller;
    final song = Track.youtube(videoId: _withVideo, title: 'With video', artist: 'A');
    final plain = Track.youtube(videoId: _noVideo, title: 'Plain', artist: 'A');

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      controller = PlayerController();
      VideoMode.debugLookUp = (id) async => id == _withVideo ? const MusicVideo(videoId: 'theomvid123') : null;
      VideoMode.instance
        ..follow(controller)
        ..debugSetFound(_withVideo, const MusicVideo(videoId: 'theomvid123'))
        ..debugSetFound(_noVideo, null);
      DownloadPrefs.instance.askEveryTime = false;
    });
    tearDown(() {
      VideoMode.debugLookUp = null;
      DownloadPrefs.instance.askEveryTime = true;
    });

    /// Waits for the tap's download to reach the queue and stops it there, before anything is fetched: the job
    /// as it was queued. (The settings were read outside the test's clock, so a turn of the real one passes first.)
    Future<DownloadJob?> queued(WidgetTester tester, Track track) async {
      DownloadJob? job;
      void stop() {
        final found = controller.youtube.jobFor(track.videoId!);
        if (found == null || job != null) return;
        job = found;
        controller.youtube.cancel(found);
      }

      controller.youtube.addListener(stop);
      await tester.pumpAndSettle();
      for (var i = 0; i < 5 && job == null; i++) {
        await tester.runAsync(() async {});
        await tester.pump();
      }
      controller.youtube.removeListener(stop);
      // The queue's save timer.
      await tester.pump(const Duration(seconds: 1));
      return job;
    }

    test('is offered only for a streamed song with a music video', () {
      expect(TrackMenuButton.offersMvDownload(controller, song), isTrue);
      expect(TrackMenuButton.offersMvDownload(controller, plain), isFalse);
      final file = Track(id: 'f', uri: Uri.file('/music/f.flac'), title: 'F', artist: 'A');
      expect(TrackMenuButton.offersMvDownload(controller, file), isFalse);
    });

    testWidgets('the song menu has it for a song with a video, and queues the song with its video', (tester) async {
      await tester.pumpWidget(_app(controller, TrackMenuButton(track: song)));
      await tester.tap(find.byType(PopupMenuButton<void>));
      await tester.pumpAndSettle();
      expect(find.text('Download for offline'), findsOneWidget);
      expect(find.text('Download with MV'), findsOneWidget);

      await tester.tap(find.text('Download with MV'));
      expect((await queued(tester, song))?.withVideo, isTrue);
    });

    testWidgets('a plain download stays audio only', (tester) async {
      await tester.pumpWidget(_app(controller, TrackMenuButton(track: song)));
      await tester.tap(find.byType(PopupMenuButton<void>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download for offline'));
      expect((await queued(tester, song))?.withVideo, isFalse);
    });

    testWidgets('a song without a video has no such entry', (tester) async {
      await tester.pumpWidget(_app(controller, TrackMenuButton(track: plain)));
      await tester.tap(find.byType(PopupMenuButton<void>));
      await tester.pumpAndSettle();
      expect(find.text('Download for offline'), findsOneWidget);
      expect(find.text('Download with MV'), findsNothing);
    });

    testWidgets('the entry appears once the lookup says the song has a video', (tester) async {
      const late = 'mvlate_song';
      final asked = Track.youtube(videoId: late, title: 'Late', artist: 'A');
      VideoMode.debugLookUp = (id) async => const MusicVideo(videoId: 'theomvid123');
      addTearDown(() => VideoMode.instance.debugSetFound(late, null));
      await tester.pumpWidget(_app(controller, TrackMenuButton(track: asked)));
      await tester.tap(find.byType(PopupMenuButton<void>));
      await tester.pumpAndSettle();
      expect(find.text('Download with MV'), findsOneWidget);
    });

    testWidgets('the phone\'s More sheet has it only for a song with a video', (tester) async {
      Widget sheet(Track track) => _app(
        controller,
        Builder(
          builder: (context) => PlayerMoreSheet(track: track, player: context),
        ),
      );
      await tester.pumpWidget(sheet(song));
      await tester.pumpAndSettle();
      expect(find.text('Download with MV'), findsOneWidget);
      await tester.pumpWidget(sheet(plain));
      await tester.pumpAndSettle();
      expect(find.text('Download with MV'), findsNothing);
    });
  });
}
