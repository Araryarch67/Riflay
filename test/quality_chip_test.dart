import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/audio_engine.dart';
import 'package:riflay/ui/widgets/signal_path.dart';

SignalPath _path(String codec, {String format = 's16', int rate = 44100, int? bitrate, int? sourceBits}) => SignalPath(
  codec: codec,
  container: codec,
  inFormat: format,
  inRate: rate,
  inChannels: 2,
  outFormat: 'float',
  outRate: rate,
  outChannels: 2,
  output: 'null',
  device: 'test',
  filters: const [],
  volume: 100,
  leveling: false,
  bitrate: bitrate,
  sourceBits: sourceBits,
);

void main() {
  test('the mini player names a song\'s format in a few characters', () {
    expect(shortQuality(_path('flac', format: 's32', sourceBits: 24)), 'FLAC 24/44.1');
    expect(shortQuality(_path('flac', format: 's16', rate: 48000)), 'FLAC 16/48');
    expect(shortQuality(_path('alac', format: 's32', rate: 96000, sourceBits: 24)), 'ALAC 24/96');
    expect(shortQuality(_path('flac', format: 'float', rate: 88200)), 'FLAC 88.2 kHz', reason: 'float hides the bits');
    expect(shortQuality(_path('aac', format: 'floatp', bitrate: 256000)), 'AAC 256 kbps');
    expect(shortQuality(_path('opus', format: 'floatp', rate: 48000)), 'Opus', reason: 'no bitrate read yet');
  });
}
