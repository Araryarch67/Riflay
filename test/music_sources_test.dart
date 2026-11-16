import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/sources/music_sources.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MusicSources.instance.reset();
  });

  test('every optional source is on until turned off, and stays as set', () async {
    final s = MusicSources.instance;
    await s.load();
    expect((s.soundcloud, s.monochrome, s.smartMerge), (true, true, true));
    await s.setSoundcloud(false);
    await s.setMonochrome(false);
    s.reset();
    await s.load();
    expect((s.soundcloud, s.monochrome, s.smartMerge), (false, false, true));
  });
}
