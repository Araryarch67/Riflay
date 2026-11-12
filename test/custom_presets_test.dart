import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/player_presets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final p = LayoutPrefs.instance;
  final own = CustomPresets.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await p.reset();
    await Appearance.instance.setNowPlaying(NowPlayingBackground.color);
    own.presets = const [];
  });

  test('a saved look puts every player setting back, and is named as the one in use', () async {
    await PlayerPreset.liquidStacked.apply(p);
    await p.change(() {
      p.progressShape = ProgressBarShape.wavy;
      p.glassVolume = true;
    });
    await own.saveCurrent('  My look ');
    expect(own.presets.single.name, 'My look');
    expect(playerPresetName(p), 'My look');

    await PlayerPreset.classic.apply(p);
    expect(playerPresetName(p), 'Classic');
    await own.presets.single.apply(p);
    expect(own.presets.single.matches(p), isTrue);
    expect(p.progressShape, ProgressBarShape.wavy);
    expect(p.glassVolume, isTrue);
    expect(p.transport, PlayerTransport.pill);
    expect(Appearance.instance.nowPlaying, NowPlayingBackground.color);
  });

  test('presets persist, are renamed, replaced by name and deleted', () async {
    await own.saveCurrent('One');
    await PlayerPreset.kawaii.apply(p);
    await own.saveCurrent('Two');
    own.presets = const [];
    await own.load();
    expect([for (final x in own.presets) x.name], ['One', 'Two']);
    expect(own.presets.last.transport, PlayerTransport.plain);

    // The same name (any case) replaces it in place.
    await PlayerPreset.stacked.apply(p);
    await own.saveCurrent('one');
    expect([for (final x in own.presets) x.name], ['one', 'Two']);
    expect(own.presets.first.transport, PlayerTransport.pill);

    await own.rename(own.presets.last, 'Kawaii mine');
    await own.remove(own.presets.first);
    await own.load();
    expect([for (final x in own.presets) x.name], ['Kawaii mine']);
    expect(CustomPresets.named('KAWAII MINE')?.custom, isTrue);
    expect(CustomPresets.named('liquid kawaii'), same(PlayerPreset.liquidKawaii));
    expect(CustomPresets.isBuiltIn(' stacked '), isTrue);
  });

  test('a saved value this version does not know falls back to the default', () {
    final preset = PlayerPreset.fromJson({'name': 'Old', 'transport': 'hologram', 'timeLeft': true});
    expect(preset.transport, PlayerTransport.classic);
    expect(preset.timeLeft, isTrue);
  });
}
