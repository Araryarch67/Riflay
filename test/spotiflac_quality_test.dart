import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/spotiflac.dart';

void main() {
  test('verification errors remain recognizable in both host error envelopes and provider results', () {
    expect(SpotiflacError.fromProvider('Download failed: VERIFY_REQUIRED').verificationRequired, isTrue);
    expect(SpotiflacError.fromProvider({'error_type': 'verification_required'}).verificationRequired, isTrue);
    expect(SpotiflacError.fromProvider('Connection closed').verificationRequired, isFalse);
  });
  Track song(String provider, Map<String, dynamic> quality) =>
      Spotiflac.track(provider, {'id': '1', 'name': 'Song', ...quality})!;

  test('Tidal catalogue quality is displayed before downloading', () {
    expect(song('tidal-web', {'audio_quality': '24bit'}).extensionQualityLabel, 'FLAC 24-bit');
    expect(song('tidal-web', {'audio_quality': '16bit/44.1kHz'}).extensionQualityLabel, 'FLAC 16-bit / 44.1 kHz');
    expect(song('tidal-web', {'audio_quality': '320kbps'}).extensionQualityLabel, 'AAC 320 kbps');
    expect(song('tidal-web', {'audio_quality': 'MQA'}).extensionQualityLabel, 'MQA');
  });
  test('other extensions use explicit formats without assuming lossless means FLAC', () {
    expect(song('other', {'audio_quality': 'ALAC'}).extensionQualityLabel, 'ALAC');
    expect(song('other', {'audio_quality': 'AAC_320'}).extensionQualityLabel, 'AAC 320 kbps');
    expect(song('other', {'audio_quality': 'LOSSLESS'}).extensionQualityLabel, isNull);
    expect(song('other', {}).extensionQualityLabel, isNull);
    expect(song('other', {'audio_quality': 'unknown'}).extensionQualityLabel, isNull);
  });
  test('catalogue quality survives saved search track serialization', () {
    final track = song('tidal-web', {'audio_quality': '24bit'});
    expect(Track.fromJson(track.toJson()).extensionQualityLabel, track.extensionQualityLabel);
  });
}
