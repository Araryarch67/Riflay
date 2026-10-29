import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/download_prefs.dart';
import 'package:riflay/services/mp4_mux.dart';
import 'package:riflay/services/video_download.dart';
import 'package:riflay/services/webm_mux.dart';
import 'package:riflay/services/youtube_stream.dart';
import 'package:riflay/services/youtube_importer.dart';
import 'package:riflay/ui/download_options.dart';
import 'package:shared_preferences/shared_preferences.dart';

VideoCandidate _v(int h, VideoCodec codec, {int fps = 30, int kbps = 1000, int? size, bool? webm, String? id}) =>
    VideoCandidate(
      id: id ?? '$h-${codec.name}-$fps',
      height: h,
      codec: codec,
      fps: fps,
      kbps: kbps,
      sizeBytes: size,
      webm: webm ?? codec == VideoCodec.vp9,
    );

extension on AudioCandidate {
  AudioCandidate copyWithKbps(int k) =>
      AudioCandidate(id: id, opus: opus, kbps: k, sizeBytes: sizeBytes, lengthMs: lengthMs);
}

const _aac = AudioCandidate(id: '140', opus: false, kbps: 130, sizeBytes: 4000000);
const _opus = AudioCandidate(id: '251', opus: true, kbps: 128, sizeBytes: 3900000);

// What a typical music video serves: H.264 up to 1080p (60 fps too), VP9 up to 4K, AV1 beside them.
final _typical = VideoFormats(
  [
    _v(2160, VideoCodec.vp9, fps: 60, kbps: 18000, size: 400000000),
    _v(2160, VideoCodec.av1, fps: 60, kbps: 9000),
    _v(1440, VideoCodec.vp9, kbps: 8000, size: 150000000),
    _v(1080, VideoCodec.avc, kbps: 3000, size: 80000000),
    _v(1080, VideoCodec.avc, fps: 60, kbps: 4500, size: 120000000),
    _v(1080, VideoCodec.vp9, kbps: 2500, size: 60000000),
    _v(1080, VideoCodec.av1, kbps: 1500),
    _v(720, VideoCodec.avc, kbps: 1500, size: 40000000),
    _v(720, VideoCodec.vp9, kbps: 1000, size: 28000000),
    _v(360, VideoCodec.avc, kbps: 500, size: 14000000),
    _v(360, VideoCodec.avc, kbps: 600, size: 16000000, id: '18').copyProgressive(),
  ],
  const [_aac, _opus],
);

extension on VideoCandidate {
  VideoCandidate copyWithKbps(int k) => VideoCandidate(
    id: id,
    height: height,
    codec: codec,
    fps: fps,
    kbps: k,
    sizeBytes: sizeBytes,
    lengthMs: lengthMs,
    webm: webm,
  );

  VideoCandidate copyProgressive() => VideoCandidate(
    id: id,
    height: height,
    codec: codec,
    fps: fps,
    kbps: kbps,
    sizeBytes: sizeBytes,
    progressive: true,
  );
}

List<int> _heights(VideoFormats f, VideoContainer c, {bool ffmpeg = false}) => [
  for (final o in videoOptions(f, c, ffmpeg: ffmpeg)) o.height,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('which streams a video choice takes', () {
    test('MP4 is H.264 only, so 1080p at most; 4K is left to WebM', () {
      expect(_heights(_typical, VideoContainer.mp4), [1080, 720, 360]);
      expect(_heights(_typical, VideoContainer.webm), [2160, 1440, 1080, 720]);
    });

    test('two streams of one resolution: the higher frame rate wins, then the higher bitrate', () {
      final pick = pickVideoDownload(_typical, const DownloadChoice.video(VideoContainer.mp4), ffmpeg: false)!;
      expect(pick.video.id, '1080-avc-60');
      expect(pick.label, 'Video · MP4 · 1080p60');
      final same = VideoFormats(
        [_v(720, VideoCodec.avc, kbps: 900, id: 'low'), _v(720, VideoCodec.avc, kbps: 1400, id: 'high')],
        const [_aac],
      );
      expect(pickVideoDownload(same, const DownloadChoice.video(VideoContainer.mp4), ffmpeg: false)!.video.id, 'high');
    });

    test('MP4 takes AAC and WebM takes Opus; the "stable volume" variants are left out', () {
      final mp4 = pickVideoDownload(_typical, const DownloadChoice.video(VideoContainer.mp4), ffmpeg: false)!;
      final webm = pickVideoDownload(_typical, const DownloadChoice.video(VideoContainer.webm), ffmpeg: false)!;
      expect(mp4.audio.id, '140');
      expect(webm.audio.id, '251');
      final drc = VideoFormats(_typical.videos, const [
        AudioCandidate(id: '140-drc', opus: false, kbps: 256, processed: true),
        _aac,
      ]);
      expect(pickVideoDownload(drc, const DownloadChoice.video(VideoContainer.mp4), ffmpeg: false)!.audio.id, '140');
    });

    test('WebM needs an Opus stream; an MP4 with only Opus uses it', () {
      final aacOnly = VideoFormats(_typical.videos, const [_aac]);
      expect(_heights(aacOnly, VideoContainer.webm), isEmpty);
      expect(pickVideoDownload(aacOnly, const DownloadChoice.video(VideoContainer.webm), ffmpeg: false), isNull);
      final opusOnly = VideoFormats(_typical.videos, const [_opus]);
      expect(
        pickVideoDownload(opusOnly, const DownloadChoice.video(VideoContainer.mp4), ffmpeg: false)!.audio.opus,
        isTrue,
      );
    });

    test('the size asked for: that one, else the tallest below it, else the smallest there is', () {
      int? at(int? h, [VideoContainer c = VideoContainer.mp4]) =>
          pickVideoDownload(_typical, DownloadChoice.video(c, height: h), ffmpeg: false)?.video.height;
      expect(at(720), 720);
      expect(at(1080), 1080);
      expect(at(480), 360, reason: 'no 480p: the tallest below');
      expect(at(144), 360, reason: 'nothing that small: the smallest there is');
      expect(at(null), 1080, reason: 'Best available: the tallest');
      expect(at(null, VideoContainer.webm), 2160);
      expect(at(1080, VideoContainer.webm), 1080);
      expect(at(1200, VideoContainer.webm), 1080);
    });

    test('Recommended is 1080p, or the best below it, or the smallest when everything is taller', () {
      expect(recommendedVideoHeightOf([2160, 1440, 1080, 720]), 1080);
      expect(recommendedVideoHeightOf([2160, 1440, 720, 360]), 720);
      expect(recommendedVideoHeightOf([2160, 1440]), 1440);
      expect(recommendedVideoHeightOf(const []), isNull);
      expect(recommendedVideoChoice, const DownloadChoice.video(VideoContainer.mp4, height: 1080));
    });

    test('VP9 comes before AV1 at the same size; AV1 is only offered where nothing else is, and needs ffmpeg', () {
      // _typical has 4K VP9 and AV1: VP9 wins.
      final pick = pickVideoDownload(
        _typical,
        const DownloadChoice.video(VideoContainer.webm, height: null),
        ffmpeg: true,
      )!;
      expect(pick.video.codec, VideoCodec.vp9);
      final onlyAv1 = VideoFormats(
        [_v(1080, VideoCodec.vp9, kbps: 2500), _v(2160, VideoCodec.av1, fps: 60, kbps: 9000)],
        const [_aac, _opus],
      );
      expect(_heights(onlyAv1, VideoContainer.webm), [1080], reason: 'AV1 comes as MP4; WebM from it needs ffmpeg');
      expect(_heights(onlyAv1, VideoContainer.webm, ffmpeg: true), [2160, 1080]);
      final tall = videoOptions(onlyAv1, VideoContainer.webm, ffmpeg: true).first;
      expect(tall.label, '2160p60 · AV1 (newer devices)');
      final choice = pickVideoDownload(
        onlyAv1,
        const DownloadChoice.video(VideoContainer.webm, height: null),
        ffmpeg: true,
      )!;
      expect(choice.needsFfmpeg, isTrue);
      // MP4 never takes AV1 or VP9.
      expect(_heights(onlyAv1, VideoContainer.mp4, ffmpeg: true), isEmpty);
    });

    test('4K being WebM only is said plainly', () {
      expect(webmTallerNote(_typical, ffmpeg: false), '4K is available as WebM.');
      final small = VideoFormats([_v(1080, VideoCodec.avc), _v(1080, VideoCodec.vp9)], const [_aac, _opus]);
      expect(webmTallerNote(small, ffmpeg: false), isNull);
      final qhd = VideoFormats([_v(1080, VideoCodec.avc), _v(1440, VideoCodec.vp9)], const [_aac, _opus]);
      expect(webmTallerNote(qhd, ffmpeg: false), '1440p is available as WebM.');
    });

    test('the one-file MP4 is kept as the fallback for when the streams can\'t be combined', () {
      final p = pickProgressive(_typical)!;
      expect(p.id, '18');
      expect(p.progressive, isTrue);
      expect(pickProgressive(VideoFormats([_v(720, VideoCodec.avc)], const [_aac])), isNull);
    });

    test('a progressive stream is never offered as a choice of its own', () {
      final only = VideoFormats([_v(360, VideoCodec.avc, id: '18').copyProgressive()], const [_aac]);
      expect(_heights(only, VideoContainer.mp4), isEmpty);
    });

    test('streams are read from the player API and from yt-dlp', () {
      final a = VideoCandidate.fromPlayer({
        'itag': 299,
        'url': 'https://x/y',
        'mimeType': 'video/mp4; codecs="avc1.64002a"',
        'height': 1080,
        'fps': 60,
        'bitrate': 6000000,
        'contentLength': '12345',
      })!;
      expect(
        [a.id, a.height, a.fps, a.codec, a.kbps, a.sizeBytes, a.webm, a.progressive],
        ['299', 1080, 60, VideoCodec.avc, 6000, 12345, false, false],
      );
      final b = VideoCandidate.fromPlayer({
        'itag': 18,
        'url': 'https://x/z',
        'mimeType': 'video/mp4; codecs="avc1.42001E, mp4a.40.2"',
        'height': 360,
      })!;
      expect(b.progressive, isTrue);
      final c = VideoCandidate.fromPlayer({
        'itag': 313,
        'url': 'https://x/w',
        'mimeType': 'video/webm; codecs="vp9"',
        'height': 2160,
      })!;
      expect([c.codec, c.webm], [VideoCodec.vp9, true]);
      expect(VideoCandidate.fromPlayer({'itag': 140, 'url': 'u', 'mimeType': 'audio/mp4; codecs="mp4a.40.2"'}), isNull);
      final d = VideoCandidate.fromYtDlp({
        'format_id': '248',
        'vcodec': 'vp09.00.40.08',
        'acodec': 'none',
        'height': 1080,
        'fps': 30,
        'ext': 'webm',
        'protocol': 'https',
        'filesize': 999,
      })!;
      expect([d.codec, d.webm, d.progressive, d.sizeBytes], [VideoCodec.vp9, true, false, 999]);
      expect(VideoCandidate.fromYtDlp({'format_id': 'sb0', 'vcodec': 'none', 'height': 90}), isNull);
      expect(
        VideoCandidate.fromYtDlp({'format_id': '91', 'vcodec': 'avc1', 'height': 144, 'protocol': 'm3u8_native'}),
        isNull,
        reason: 'a playlist of segments, not a file',
      );
    });
  });

  group('sizes', () {
    test('the picture plus the sound; exact when both are known', () {
      final e = estimateVideoDownload(_typical, const DownloadChoice.video(VideoContainer.mp4), ffmpeg: false)!;
      expect(e.bytes, 120000000 + 4000000);
      expect(e.exact, isTrue);
    });

    test('worked out from the bitrates when a size is missing', () {
      final f = VideoFormats([_v(720, VideoCodec.avc, kbps: 1600)], const [_aac]);
      final e = estimateVideoDownload(f, const DownloadChoice.video(VideoContainer.mp4), ffmpeg: false)!;
      final seconds = 4000000 * 8 / (130 * 1000);
      expect(e.exact, isFalse);
      expect(e.bytes, closeTo(4000000 + seconds * 1600 * 1000 / 8, 2));
    });

    test('unknown when nothing says how long it is', () {
      final f = VideoFormats(
        [_v(720, VideoCodec.avc, kbps: 1600)],
        const [AudioCandidate(id: '140', opus: false, kbps: 130)],
      );
      expect(estimateVideoDownload(f, const DownloadChoice.video(VideoContainer.mp4), ffmpeg: false), isNull);
    });
  });

  group('the choice is remembered', () {
    Future<DownloadPrefs> load(Map<String, Object> stored) async {
      SharedPreferences.setMockInitialValues(stored);
      final p = DownloadPrefs();
      await p.load();
      return p;
    }

    test('Audio is the default; Video starts at MP4 and 1080p', () async {
      final p = await load({});
      expect(p.kind, DownloadKind.audio);
      expect(p.choice, const DownloadChoice(DownloadFormat.opus));
      expect(p.videoChoice, const DownloadChoice.video(VideoContainer.mp4, height: 1080));
    });

    test('kind, container and a size per container come back after a restart', () async {
      final p = await load({});
      await p.setKind(DownloadKind.video);
      await p.setVideoContainer(VideoContainer.webm);
      await p.setVideoHeight(VideoContainer.webm, null);
      await p.setVideoHeight(VideoContainer.mp4, 720);
      final q = DownloadPrefs();
      await q.load();
      expect(q.kind, DownloadKind.video);
      expect(q.choice, const DownloadChoice.video(VideoContainer.webm, height: null));
      expect(q.heightFor(VideoContainer.mp4), 720);
      await q.setVideoContainer(VideoContainer.mp4);
      expect(q.choice, const DownloadChoice.video(VideoContainer.mp4, height: 720));
      expect(q.audioChoice, const DownloadChoice(DownloadFormat.opus), reason: 'the audio choice is kept apart');
    });

    test('video choices compare by container and size', () {
      expect(const DownloadChoice.video(VideoContainer.mp4), const DownloadChoice.video(VideoContainer.mp4));
      expect(
        const DownloadChoice.video(VideoContainer.mp4) == const DownloadChoice.video(VideoContainer.webm),
        isFalse,
      );
      expect(
        const DownloadChoice.video(VideoContainer.mp4, height: null) == const DownloadChoice.video(VideoContainer.mp4),
        isFalse,
      );
      expect(const DownloadChoice.video(VideoContainer.mp4) == const DownloadChoice(DownloadFormat.opus), isFalse);
      expect(isRecommended(const DownloadChoice.video(VideoContainer.mp4)), isFalse);
      expect(describeChoice(const DownloadChoice.video(VideoContainer.mp4, height: 720)), 'Video · MP4 · 720p');
      expect(
        describeChoice(const DownloadChoice.video(VideoContainer.webm, height: null)),
        'Video · WebM · best available',
      );
    });

    test('a queued video download keeps its choice and its two partial files across a restart', () {
      final job =
          DownloadJob(
              videoId: 'dQw4w9WgXcQ',
              title: 'Song',
              channel: 'Artist',
              thumbnailUrl: '',
              choice: const DownloadChoice.video(VideoContainer.webm, height: null),
            )
            ..videoParts.addAll({
              'video': (itag: '313', size: 1000, ext: 'webm'),
              'sound': (itag: '251', size: 200, ext: 'webm'),
            });
      final back = YoutubeImporter.decodeQueue(YoutubeImporter.encodeQueue([job])).single;
      expect(back.choice, const DownloadChoice.video(VideoContainer.webm, height: null));
      expect(back.videoParts['video'], (itag: '313', size: 1000, ext: 'webm'));
      expect(back.videoParts['sound'], (itag: '251', size: 200, ext: 'webm'));
      final mp4 = DownloadJob(
        videoId: 'dQw4w9WgXcQ',
        title: 'Song',
        channel: 'Artist',
        thumbnailUrl: '',
        choice: const DownloadChoice.video(VideoContainer.mp4, height: 1080),
      );
      expect(YoutubeImporter.decodeQueue(YoutubeImporter.encodeQueue([mp4])).single.choice, mp4.choice);
      // Audio jobs are unchanged.
      final audio = DownloadJob(
        videoId: 'dQw4w9WgXcQ',
        title: 'Song',
        channel: 'Artist',
        thumbnailUrl: '',
        choice: const DownloadChoice(DownloadFormat.m4a, kbps: 96),
      );
      expect(YoutubeImporter.decodeQueue(YoutubeImporter.encodeQueue([audio])).single.choice, audio.choice);
      expect(jsonDecode(YoutubeImporter.encodeQueue([audio])).toString(), isNot(contains('videoParts')));
    });
  });

  group('muxing (ffmpeg makes the sources, the Dart muxers combine them)', () {
    late Directory dir;
    final haveTools = () {
      try {
        final enc = Process.runSync('ffmpeg', ['-hide_banner', '-encoders']).stdout as String;
        return enc.contains('libvpx-vp9') &&
            enc.contains('libopus') &&
            enc.contains('libx264') &&
            Process.runSync('ffprobe', ['-version']).exitCode == 0;
      } catch (_) {
        return false;
      }
    }();
    final skip = haveTools ? null : 'ffmpeg with libvpx-vp9, libopus, libx264 and ffprobe are needed';

    setUpAll(() {
      if (!haveTools) return;
      dir = Directory.systemTemp.createTempSync('riflay-mux');
      void ff(List<String> args) {
        final r = Process.runSync('ffmpeg', ['-v', 'error', '-y', ...args], workingDirectory: dir.path);
        if (r.exitCode != 0) fail('ffmpeg: ${r.stderr}');
      }

      ff([
        '-f',
        'lavfi',
        '-i',
        'testsrc=d=6:s=160x90:r=25',
        '-c:v',
        'libvpx-vp9',
        '-g',
        '50',
        '-b:v',
        '100k',
        'v.webm',
      ]);
      ff(['-f', 'lavfi', '-i', 'sine=d=6.2', '-c:a', 'libopus', '-b:a', '64k', 'a.webm']);
      final dash = ['-movflags', 'dash+frag_keyframe+empty_moov+default_base_moof'];
      ff([
        '-f',
        'lavfi',
        '-i',
        'testsrc=d=6:s=160x90:r=25',
        '-c:v',
        'libx264',
        '-g',
        '50',
        '-pix_fmt',
        'yuv420p',
        ...dash,
        'v.mp4',
      ]);
      ff([
        '-f',
        'lavfi',
        '-i',
        'sine=d=6.2',
        '-c:a',
        'aac',
        '-b:a',
        '64k',
        ...dash,
        '-frag_duration',
        '2000000',
        'a.m4a',
      ]);
    });
    tearDownAll(() {
      if (haveTools && dir.existsSync()) dir.deleteSync(recursive: true);
    });

    Map<String, dynamic> probe(String file) {
      final r = Process.runSync('ffprobe', ['-v', 'error', '-show_format', '-show_streams', '-of', 'json', file]);
      return jsonDecode(r.stdout as String) as Map<String, dynamic>;
    }

    List<String> kinds(Map<String, dynamic> info) => [
      for (final s in info['streams'] as List) (s as Map)['codec_name'] as String,
    ];

    void decodesAndSeeks(String file) {
      final all = Process.runSync('ffmpeg', ['-v', 'error', '-i', file, '-f', 'null', '-']);
      expect(all.stderr, isEmpty, reason: 'every frame and sample decodes');
      final seek = Process.runSync('ffmpeg', ['-v', 'error', '-ss', '4', '-i', file, '-t', '1', '-f', 'null', '-']);
      expect(seek.exitCode, 0);
      expect(seek.stderr, isEmpty, reason: 'seeking lands on a good frame');
    }

    final cover = File('test/fixtures/cover_square.jpg');

    test('WebM: VP9 and Opus end up in one file with the right length and the tags', () async {
      final out = '${dir.path}/out.webm';
      await WebmMux.muxFile(
        video: '${dir.path}/v.webm',
        audio: '${dir.path}/a.webm',
        out: out,
        tags: MuxTags(
          title: 'Song',
          artist: 'Artist',
          album: 'Album',
          year: 2020,
          comment: 'https://youtu.be/x',
          cover: cover.readAsBytesSync(),
        ),
      );
      final info = probe(out);
      expect(kinds(info), containsAll(['vp9', 'opus']));
      expect(double.parse((info['format'] as Map)['duration'] as String), closeTo(6.2, 0.1));
      final tags = Map<String, dynamic>.from((info['format'] as Map)['tags'] as Map)
        ..removeWhere((k, _) => k == 'encoder');
      expect(tags.map((k, v) => MapEntry(k.toUpperCase(), v)), containsPair('TITLE', 'Song'));
      expect(tags.map((k, v) => MapEntry(k.toUpperCase(), v)), containsPair('ARTIST', 'Artist'));
      decodesAndSeeks(out);
      expect(WebmMux.hasVideoTrack(out), isTrue);
      expect(WebmMux.hasVideoTrack('${dir.path}/a.webm'), isFalse, reason: 'an audio-only WebM is not a video');
      expect(isVideoFile(out), isTrue);
      expect(isVideoFile('${dir.path}/a.webm'), isFalse);
    }, skip: skip);

    test('WebM: nothing is re-encoded (the packets are the sources\' own)', () async {
      final out = '${dir.path}/copy.webm';
      await WebmMux.muxFile(video: '${dir.path}/v.webm', audio: '${dir.path}/a.webm', out: out);
      String hash(String file, String map) {
        final r = Process.runSync('ffmpeg', ['-v', 'error', '-i', file, '-map', map, '-c', 'copy', '-f', 'md5', '-']);
        return (r.stdout as String).trim();
      }

      expect(hash(out, '0:v:0'), hash('${dir.path}/v.webm', '0:v:0'));
      expect(hash(out, '0:a:0'), hash('${dir.path}/a.webm', '0:a:0'));
    }, skip: skip);

    test('WebM: two audio files or two picture files are refused, not mangled', () async {
      expect(
        () => WebmMux.muxFile(video: '${dir.path}/a.webm', audio: '${dir.path}/a.webm', out: '${dir.path}/bad.webm'),
        throwsA(isA<MuxException>()),
      );
      expect(
        () => WebmMux.muxFile(video: '${dir.path}/v.mp4', audio: '${dir.path}/a.webm', out: '${dir.path}/bad2.webm'),
        throwsA(isA<MuxException>()),
      );
    }, skip: skip);

    test('MP4: H.264 and AAC from YouTube-style DASH files end up in one MP4, with length, seeking and tags', () async {
      final out = '${dir.path}/out.mp4';
      await Mp4Mux.muxFile(
        video: '${dir.path}/v.mp4',
        audio: '${dir.path}/a.m4a',
        out: out,
        tags: MuxTags(title: 'Song', artist: 'Artist', year: 2020, cover: cover.readAsBytesSync()),
      );
      final info = probe(out);
      expect(kinds(info), containsAll(['h264', 'aac']));
      expect(double.parse((info['format'] as Map)['duration'] as String), closeTo(6.2, 0.1));
      final tags = (info['format'] as Map)['tags'] as Map;
      expect(tags['title'], 'Song');
      expect(tags['artist'], 'Artist');
      final streams = (info['streams'] as List).cast<Map>();
      final video = streams.firstWhere((s) => s['codec_name'] == 'h264');
      final audio = streams.firstWhere((s) => s['codec_name'] == 'aac');
      expect(double.parse(video['duration'] as String), closeTo(6.0, 0.1));
      expect(double.parse(audio['duration'] as String), closeTo(6.2, 0.1));
      decodesAndSeeks(out);
      expect(isVideoFile(out), isTrue);
      expect(Mp4Mux.canRead('${dir.path}/v.mp4'), isTrue);
      expect(Mp4Mux.canRead('${dir.path}/v.webm'), isFalse);
    }, skip: skip);

    test('MP4: the streams are the sources\' own', () async {
      final out = '${dir.path}/copy.mp4';
      await Mp4Mux.muxFile(video: '${dir.path}/v.mp4', audio: '${dir.path}/a.m4a', out: out);
      String hash(String file, String map) {
        final r = Process.runSync('ffmpeg', ['-v', 'error', '-i', file, '-map', map, '-c', 'copy', '-f', 'md5', '-']);
        return (r.stdout as String).trim();
      }

      expect(hash(out, '0:v:0'), hash('${dir.path}/v.mp4', '0:v:0'));
      expect(hash(out, '0:a:0'), hash('${dir.path}/a.m4a', '0:a:0'));
    }, skip: skip);

    test('MP4: a file that is not fragmented is refused (the caller then falls back)', () async {
      final plain = '${dir.path}/plain.mp4';
      final r = Process.runSync('ffmpeg', [
        '-v',
        'error',
        '-y',
        '-f',
        'lavfi',
        '-i',
        'testsrc=d=1:s=64x64:r=10',
        '-c:v',
        'libx264',
        plain,
      ]);
      expect(r.exitCode, 0);
      expect(
        () => Mp4Mux.muxFile(video: plain, audio: '${dir.path}/a.m4a', out: '${dir.path}/bad.mp4'),
        throwsA(isA<MuxException>()),
      );
    }, skip: skip);

    test('muxVideo: the built-in muxers are what runs without ffmpeg, for both containers', () async {
      final mp4 = File('${dir.path}/via.mp4.part');
      await muxVideo(
        video: File('${dir.path}/v.mp4'),
        audio: File('${dir.path}/a.m4a'),
        out: mp4,
        container: VideoContainer.mp4,
      );
      expect(kinds(probe(mp4.path)), containsAll(['h264', 'aac']));
      final webm = File('${dir.path}/via.webm.part');
      await muxVideo(
        video: File('${dir.path}/v.webm'),
        audio: File('${dir.path}/a.webm'),
        out: webm,
        container: VideoContainer.webm,
      );
      expect(kinds(probe(webm.path)), containsAll(['vp9', 'opus']));
    }, skip: skip);

    test('muxVideo with ffmpeg: faststart MP4 and WebM, tags and cover in', () async {
      final mp4 = File('${dir.path}/ff.mp4.part');
      final tags = MuxTags(title: 'Song', artist: 'Artist', cover: cover.readAsBytesSync());
      await muxVideo(
        video: File('${dir.path}/v.mp4'),
        audio: File('${dir.path}/a.m4a'),
        out: mp4,
        container: VideoContainer.mp4,
        tags: tags,
        useFfmpeg: true,
      );
      final info = probe(mp4.path);
      expect(kinds(info), containsAll(['h264', 'aac']));
      expect(((info['format'] as Map)['tags'] as Map)['title'], 'Song');
      final webm = File('${dir.path}/ff.webm.part');
      await muxVideo(
        video: File('${dir.path}/v.webm'),
        audio: File('${dir.path}/a.webm'),
        out: webm,
        container: VideoContainer.webm,
        tags: tags,
        useFfmpeg: true,
      );
      expect(kinds(probe(webm.path)), containsAll(['vp9', 'opus']));
    }, skip: skip);
  });

  group('sizes come from the listing, never from a request per stream', () {
    test('contentLength is the exact size; the length and bitrate give one when it is missing', () {
      final exact = VideoCandidate.fromPlayer({
        'itag': 137,
        'url': 'https://example.invalid/v',
        'mimeType': 'video/mp4; codecs="avc1.640028"',
        'height': 1080,
        'bitrate': 3000000,
        'contentLength': '80000000',
        'approxDurationMs': '250000',
      })!;
      expect(exact.sizeBytes, 80000000);
      final bare = VideoCandidate.fromPlayer({
        'itag': 137,
        'url': 'https://example.invalid/v',
        'mimeType': 'video/mp4; codecs="avc1.640028"',
        'height': 1080,
        'bitrate': 3000000,
        'approxDurationMs': '250000',
      })!;
      expect(bare.sizeBytes, isNull);
      expect(bare.lengthMs, 250000);
      final audio = AudioCandidate.fromPlayer({
        'itag': 140,
        'url': 'https://example.invalid/a',
        'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
        'bitrate': 128000,
        'approxDurationMs': '250000',
      })!;
      final e = estimateVideoDownload(
        VideoFormats([bare.copyWithKbps(3000)], [audio.copyWithKbps(128)]),
        const DownloadChoice.video(VideoContainer.mp4),
        ffmpeg: false,
      )!;
      expect(e.exact, isFalse);
      // 250 s at 3000 + 128 kbps.
      expect(e.bytes, 250 * (3000 + 128) * 1000 ~/ 8);
    });
  });

  group('the music video lookup', () {
    // Each step takes 100 ms; the visitor id is only paid for by whoever asks first.
    Future<(int, VideoFormats?)> run({required bool sequential, required String video}) async {
      var visitor = false;
      Future<void> warm() async {
        if (visitor) return;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        visitor = true;
      }

      final sw = Stopwatch()..start();
      final f = await YoutubeStream.lookUpMusicVideo(
        'song',
        sequential: sequential,
        warm: warm,
        findVideo: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return video;
        },
        formatsOf: (id) async {
          await warm();
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return _typical;
        },
      );
      return (sw.elapsedMilliseconds, f);
    }

    test('overlapping the steps is faster than doing them one after another', () async {
      final seq = await run(sequential: true, video: 'other');
      final par = await run(sequential: false, video: 'other');
      debugPrint('music video lookup, fakes: sequential ${seq.$1} ms, parallel ${par.$1} ms');
      expect(seq.$2, isNotNull);
      expect(par.$2, isNotNull);
      expect(seq.$1, greaterThanOrEqualTo(300));
      expect(par.$1, lessThan(seq.$1 - 50), reason: 'the visitor id is made ready while the video id is looked up');
    });

    test('a song that is its own video needs no second round', () async {
      final seq = await run(sequential: true, video: 'song');
      final par = await run(sequential: false, video: 'song');
      debugPrint('own video, fakes: sequential ${seq.$1} ms, parallel ${par.$1} ms');
      expect(par.$1, lessThan(seq.$1 - 80));
    });

    test('no music video is null, and a failed lookup is thrown', () async {
      Future<VideoFormats> never(String _) async => _typical;
      expect(await YoutubeStream.lookUpMusicVideo('s', findVideo: (_) async => null, formatsOf: never), isNull);
      expect(
        YoutubeStream.lookUpMusicVideo('s', findVideo: (_) async => throw StateError('offline'), formatsOf: never),
        throwsStateError,
      );
      expect(
        await YoutubeStream.lookUpMusicVideo(
          's',
          findVideo: (_) async => 'v',
          formatsOf: (_) async => const VideoFormats([], []),
        ),
        isNull,
        reason: 'a video with no usable picture streams offers nothing',
      );
    });
  });

  group('the download dialog', () {
    Future<Future<DownloadChoice?>> open(
      WidgetTester tester, {
      required DownloadChoice initial,
      Future<VideoFormats?>? video,
      bool ffmpeg = false,
    }) async {
      tester.view.physicalSize = const Size(600, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late BuildContext host;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              host = context;
              return const Scaffold();
            },
          ),
        ),
      );
      final result = showDialog<DownloadChoice>(
        context: host,
        builder: (_) => DownloadOptionsDialog(
          initial: initial,
          video: video,
          canRemux: ffmpeg,
          canMakeMp3: true,
          canMakeFlac: true,
          canReencode: ffmpeg,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      return result;
    }

    Finder chip(String startsWith) => find.byWidgetPredicate(
      (w) => w is ChoiceChip && w.label is Text && (w.label as Text).data!.startsWith(startsWith),
    );

    testWidgets('a song with a music video can be saved as Audio or Video; Audio stays the default', (tester) async {
      final result = await open(
        tester,
        initial: const DownloadChoice(DownloadFormat.opus),
        video: Future.value(_typical),
      );
      await tester.pump();
      expect(find.text('Audio'), findsOneWidget);
      expect(find.text('Video'), findsOneWidget);
      expect(find.text('Opus'), findsOneWidget, reason: 'the audio formats show first');
      await tester.tap(find.text('Video'));
      await tester.pump();
      expect(find.text('MP4'), findsOneWidget);
      expect(find.text('WebM'), findsOneWidget);
      expect(find.text('Opus'), findsNothing);
      await tester.tap(find.text('Download'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(await result, const DownloadChoice.video(VideoContainer.mp4, height: 1080));
    });

    testWidgets('MP4 sizes: Best available first, 1080p Recommended, sizes exact, 4K said to be WebM', (tester) async {
      await open(tester, initial: recommendedVideoChoice, video: Future.value(_typical));
      await tester.pump();
      expect(chip('Best available (1080p60)'), findsOneWidget);
      expect(chip('1080p60 · Recommended'), findsOneWidget);
      expect(chip('720p'), findsOneWidget);
      expect(chip('360p'), findsOneWidget);
      expect(chip('2160p'), findsNothing, reason: 'MP4 stops at the H.264 sizes');
      expect(find.text('4K is available as WebM.'), findsOneWidget);
      final labels = [for (final c in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip))) (c.label as Text).data!];
      expect(labels.first, startsWith('Best available'));
      expect(labels.every((l) => !l.contains('~')), isTrue, reason: 'both sizes known: no tilde');
      expect(tester.widget<ChoiceChip>(chip('1080p60 · Recommended')).selected, isTrue);
    });

    testWidgets('WebM goes up to 4K, and each container keeps its own size', (tester) async {
      final result = await open(tester, initial: recommendedVideoChoice, video: Future.value(_typical));
      await tester.pump();
      await tester.tap(chip('720p'));
      await tester.pump();
      await tester.tap(find.text('WebM'));
      await tester.pump();
      expect(chip('2160p60'), findsOneWidget);
      expect(chip('1440p'), findsOneWidget);
      expect(find.text('4K is available as WebM.'), findsNothing);
      expect(tester.widget<ChoiceChip>(chip('1080p')).selected, isTrue, reason: 'WebM still has the recommended size');
      await tester.tap(chip('2160p60'));
      await tester.pump();
      await tester.tap(find.text('Download'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(await result, const DownloadChoice.video(VideoContainer.webm, height: 2160));
    });

    testWidgets('Best available returns no height', (tester) async {
      final result = await open(tester, initial: recommendedVideoChoice, video: Future.value(_typical));
      await tester.pump();
      await tester.tap(chip('Best available'));
      await tester.pump();
      await tester.tap(find.text('Download'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(await result, const DownloadChoice.video(VideoContainer.mp4, height: null));
    });

    testWidgets('a song without a music video only offers Audio', (tester) async {
      await open(tester, initial: const DownloadChoice(DownloadFormat.opus), video: Future.value(null));
      await tester.pump();
      expect(find.text('Video'), findsNothing);
      expect(find.text('Opus'), findsOneWidget);
    });

    testWidgets('a saved Video choice falls back to Audio when the song has no video', (tester) async {
      await open(tester, initial: recommendedVideoChoice, video: Future.value(null));
      await tester.pump();
      expect(find.text('Video'), findsNothing);
      expect(find.text('Opus'), findsOneWidget);
    });

    testWidgets('a whole playlist (no song) offers Audio only', (tester) async {
      await open(tester, initial: const DownloadChoice(DownloadFormat.opus));
      expect(find.text('Video'), findsNothing);
    });

    testWidgets('chips spin while the video\'s sizes are looked up', (tester) async {
      final found = Completer<VideoFormats?>();
      await open(tester, initial: recommendedVideoChoice, video: found.future);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      found.complete(_typical);
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(chip('720p'), findsOneWidget);
    });

    testWidgets('Audio shows at once; a failed video lookup says so calmly', (tester) async {
      final video = Completer<VideoFormats?>();
      await open(tester, initial: const DownloadChoice(DownloadFormat.opus), video: video.future);
      expect(find.text('Opus'), findsOneWidget, reason: 'never blocked on the video lookup');
      expect(find.text("Couldn't look up video sizes."), findsNothing);
      video.completeError(StateError('offline'));
      await tester.pump();
      await tester.pump();
      expect(find.text("Couldn't look up video sizes."), findsOneWidget);
      expect(find.text('Opus'), findsOneWidget);
    });

    testWidgets('AV1-only sizes are marked and need ffmpeg', (tester) async {
      final f = VideoFormats([_v(1080, VideoCodec.vp9), _v(2160, VideoCodec.av1, fps: 60)], const [_aac, _opus]);
      await open(tester, initial: const DownloadChoice.video(VideoContainer.webm), video: Future.value(f));
      await tester.pump();
      expect(chip('2160p60 · AV1 (newer devices)'), findsNothing);
      await open(
        tester,
        initial: const DownloadChoice.video(VideoContainer.webm),
        video: Future.value(f),
        ffmpeg: true,
      );
      await tester.pump();
      expect(chip('2160p60 · AV1 (newer devices)'), findsOneWidget);
    });
  });
}
