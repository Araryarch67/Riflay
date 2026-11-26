import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/sources/music_sources.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MusicSources.instance.reset();
  });

  test('services are off until turned on, library-only Smart merge is on, and each stays as set', () async {
    final s = MusicSources.instance;
    await s.load();
    expect((s.soundcloud, s.monochrome, s.smartMerge), (false, false, true));
    await s.setSoundcloud(true);
    await s.setMonochrome(true);
    await s.setSmartMerge(false);
    s.reset();
    await s.load();
    expect((s.soundcloud, s.monochrome, s.smartMerge), (true, true, false));
  });

  test('an update turns them all off once, whatever was set before; what is set after stays', () async {
    SharedPreferences.setMockInitialValues({
      for (final v in ['v1', 'v2']) ...{
        'sources.soundcloud.$v': true,
        'sources.monochrome.$v': true,
        'sources.smartMerge.$v': true,
      },
    });
    final s = MusicSources.instance..reset();
    await s.load();
    expect((s.soundcloud, s.monochrome, s.smartMerge), (false, false, true));
    final prefs = await SharedPreferences.getInstance();
    await Future<void>.delayed(Duration.zero);
    expect(prefs.getKeys().where((k) => k.endsWith('.v1') || k.endsWith('.v2')), isEmpty, reason: 'the old choices are dropped');

    await s.setSmartMerge(false);
    s.reset();
    await s.load();
    expect((s.soundcloud, s.monochrome, s.smartMerge), (false, false, false));
  });
}
