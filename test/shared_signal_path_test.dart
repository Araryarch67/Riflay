import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/audio_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('callers within a second share one signal path read (each is ~20 synchronous mpv calls)', () async {
    SharedPreferences.setMockInitialValues({});
    final engine = AudioEngine();
    addTearDown(engine.dispose);
    final first = engine.signalPath();
    expect(identical(engine.signalPath(), first), isTrue, reason: 'the badge and the sheet in the same second');
    expect(await first, isNull, reason: 'nothing is playing');
  });
}
