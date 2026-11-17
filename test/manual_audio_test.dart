import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/manual_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('manual local audio survives restart independently of its filename or quality', () async {
    final source = Track.fromUri(Uri.file('/music/recording.m4a')).copyWith(audioQuality: 'FLAC · 24-bit / 48 kHz');
    await ManualAudio().set('video', ManualAudioChoice.track(source));
    final restored = ManualAudio()..load(await SharedPreferences.getInstance());
    expect(restored.choice('video')?.track?.uri, source.uri);
    expect(restored.choice('video')?.track?.audioQuality, source.audioQuality);
    expect(restored.choice('another'), isNull);
  });

  test('explicit YouTube and automatic are different and reset affects only one song', () async {
    final choices = ManualAudio();
    await choices.set('first', const ManualAudioChoice.youtube());
    await choices.set('second', const ManualAudioChoice.youtube());
    final restored = ManualAudio()..load(await SharedPreferences.getInstance());
    expect(restored.choice('first'), isNotNull);
    expect(restored.choice('first')?.track, isNull);
    await restored.set('first', null);
    final again = ManualAudio()..load(await SharedPreferences.getInstance());
    expect(again.choice('first'), isNull);
    expect(again.choice('second'), isNotNull);
  });

  test('download-only extension cannot be chosen for streaming', () async {
    final source = Track(id: 'sflx:test:1', uri: Uri.parse('spotiflac://test/1'), title: 'Song', artist: 'Artist');
    final choices = ManualAudio();
    await expectLater(choices.set('video', ManualAudioChoice.track(source)), throwsArgumentError);
    expect(choices.choice('video'), isNull);
  });

  test('a corrupt choice does not discard the other overrides', () async {
    SharedPreferences.setMockInitialValues({'smartMerge.manualAudio.v1': '{"bad":false,"good":null}'});
    final choices = ManualAudio()..load(await SharedPreferences.getInstance());
    expect(choices.choice('bad'), isNull);
    expect(choices.choice('good'), isNotNull);
  });
}
