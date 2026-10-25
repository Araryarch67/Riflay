import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/audio_engine.dart';

String? label(
  String codec, {
  String container = '',
  String inFormat = '',
  int rate = 0,
  int? bits,
  int? kbps,
  int? dop,
}) => SignalPath.qualityLabel(
  codec: codec,
  container: container,
  inFormat: inFormat,
  inRate: rate,
  sourceBits: bits,
  bitrate: kbps == null ? null : kbps * 1000,
  dopBitRate: dop,
);

void main() {
  test('lossless shows bit depth and rate', () {
    expect(label('flac', inFormat: 's32', rate: 96000, bits: 24), 'FLAC · 24-bit / 96 kHz');
    expect(label('flac', inFormat: 's16', rate: 44100), 'FLAC · 16-bit / 44.1 kHz');
    expect(label('alac', inFormat: 's32p', rate: 192000, bits: 24), 'ALAC · 24-bit / 192 kHz');
    expect(label('pcm_s24le', container: 'wav', inFormat: 's32', rate: 48000, bits: 24), 'WAV · 24-bit / 48 kHz');
    expect(label('pcm_s16be', container: 'aiff', inFormat: 's16', rate: 44100), 'AIFF · 16-bit / 44.1 kHz');
    expect(label('wavpack', inFormat: 's16p', rate: 44100), 'WavPack · 16-bit / 44.1 kHz');
    expect(label('ape', inFormat: 's16', rate: 44100), 'APE · 16-bit / 44.1 kHz');
  });

  test('lossless leaves out what is unknown', () {
    expect(label('flac', rate: 96000), 'FLAC · 96 kHz');
    expect(label('flac', inFormat: 's16'), 'FLAC · 16-bit');
    expect(label('flac'), 'FLAC');
  });

  test('lossy shows the bitrate', () {
    expect(label('opus', kbps: 160), 'Opus · 160 kbps');
    expect(label('mp3float', kbps: 320), 'MP3 · 320 kbps');
    expect(label('aac', kbps: 256), 'AAC · 256 kbps');
    expect(label('vorbis', kbps: 192), 'Vorbis · 192 kbps');
    expect(label('opus'), 'Opus');
    expect(label('opus', kbps: 0), 'Opus');
  });

  test('DSD is named by its rate', () {
    expect(label('dsd_lsbf_planar', rate: 352800), 'DSD64');
    expect(label('dsd_msbf', rate: 705600), 'DSD128');
    expect(label('pcm_s24le', rate: 176400, dop: 2822400), 'DSD64');
    expect(label('pcm_s24le', rate: 352800, dop: 5644800), 'DSD128');
  });

  test('nothing known gives no label', () {
    expect(label(''), isNull);
  });
}
