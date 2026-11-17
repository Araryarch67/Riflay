import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/metadata.dart';
import 'package:riflay/services/smart_merge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('file quality is measured and survives library persistence', () async {
    final track = Track.fromUri(File('test/fixtures/sine.flac').absolute.uri);
    final enriched = await Metadata.enrich(track);
    expect(enriched.qualityLabel, contains('FLAC'));
    expect(enriched.qualityLabel, contains('16-bit'));
    expect(enriched.qualityLabel, contains('16 kHz'));
    expect(Track.fromJson(enriched.toJson()).qualityLabel, enriched.qualityLabel);
    expect(enriched.copyWith(title: 'Retagged').qualityLabel, enriched.qualityLabel);
  });

  test('container alone does not claim an audio codec or invent a resolution', () {
    final track = Track.fromUri(Uri.file('/music/unknown.m4a'));
    expect(track.qualityLabel, 'M4A');
    expect(Track.youtube(videoId: '1', title: 'Song', artist: 'Artist').qualityLabel, isNull);
  });

  test('FLAC named .m4a is measured as lossless and can replace YouTube audio', () async {
    final dir = await Directory.systemTemp.createTemp('riflay-codec-quality-');
    addTearDown(() => dir.delete(recursive: true));
    final file = await File('test/fixtures/sine.flac').copy('${dir.path}/recording.m4a');
    final local = await Metadata.enrich(Track.fromUri(file.uri).copyWith(title: 'Recording', artist: 'Test Artist'));
    expect(local.audioQuality, startsWith('FLAC'));
    expect(local.audioQuality, contains('16-bit / 16 kHz'));
    final youtube = Track.youtube(
      videoId: 'codec-test1',
      title: local.title,
      artist: local.artist,
      duration: local.duration,
    );
    final merge = SmartMerge(providers: [], enabled: () => true);
    expect(merge.local(youtube, [local], 1), same(local));
  });

  test('MP3 renamed .flac is measured as lossy', () async {
    final dir = await Directory.systemTemp.createTemp('riflay-codec-quality-');
    addTearDown(() => dir.delete(recursive: true));
    final file = await File('test/fixtures/sine.mp3').copy('${dir.path}/recording.flac');
    final local = await Metadata.enrich(Track.fromUri(file.uri));
    expect(local.audioQuality, startsWith('MP3'));
  });

  test('measured quality takes precedence over advertised source quality', () {
    final track = Track(
      id: 'sflx:test:1',
      uri: Uri.parse('spotiflac://test/1'),
      title: 'Song',
      artist: 'Artist',
      extensionData: const {'audio_quality': 'FLAC'},
      audioQuality: 'AAC · 256 kbps',
    );
    expect(track.qualityLabel, 'AAC · 256 kbps');
  });

  test('MP3 has a measured bitrate without a fabricated PCM depth', () async {
    final enriched = await Metadata.enrich(Track.fromUri(File('test/fixtures/sine.mp3').absolute.uri));
    expect(enriched.qualityLabel, startsWith('MP3'));
    expect(enriched.qualityLabel, contains('kbps'));
    expect(enriched.qualityLabel, isNot(contains('-bit')));
  });
}
