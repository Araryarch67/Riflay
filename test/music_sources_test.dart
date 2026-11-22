import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/sources/music_sources.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MusicSources.instance.reset();
  });

  test('every optional source is off until turned on, and stays as set', () async {
    final s = MusicSources.instance;
    await s.load();
    expect((s.soundcloud, s.monochrome, s.smartMerge), (false, false, false));
    await s.setSoundcloud(true);
    await s.setMonochrome(true);
    s.reset();
    await s.load();
    expect((s.soundcloud, s.monochrome, s.smartMerge), (true, true, false));
  });

  test('an update turns them all off once, whatever was set before; what is set after stays', () async {
    SharedPreferences.setMockInitialValues({
      'sources.soundcloud.v1': true,
      'sources.monochrome.v1': true,
      'sources.smartMerge.v1': true,
    });
    final s = MusicSources.instance..reset();
    await s.load();
    expect((s.soundcloud, s.monochrome, s.smartMerge), (false, false, false));
    final prefs = await SharedPreferences.getInstance();
    await Future<void>.delayed(Duration.zero);
    expect(prefs.getKeys().where((k) => k.endsWith('.v1')), isEmpty, reason: 'the old choices are dropped');

    await s.setSmartMerge(true);
    s.reset();
    await s.load();
    expect((s.soundcloud, s.monochrome, s.smartMerge), (false, false, true));
  });
}
