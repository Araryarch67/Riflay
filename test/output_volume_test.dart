import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('each output keeps its own volume: turned down for a DAC, back up on the speaker once it is unplugged', () async {
    SharedPreferences.setMockInitialValues({'library.v1': '[]', 'discord.enabled': false, 'volume.v1': 1.0});
    final c = PlayerController();
    addTearDown(c.dispose);
    await c.load();
    expect(c.volume, 1);

    // The DAC: an IEM on it is loud, so the app's volume goes down.
    await c.audio.setDevice('usb-dac');
    await c.setVolume(0.3);
    expect(c.volume, 0.3);

    // Pulled out: the default output gets the level it had, not the IEM's.
    await c.audio.setDevice('auto');
    await Future<void>.delayed(Duration.zero);
    expect(c.volume, 1);

    // Plugged back in: the IEM's level returns.
    await c.audio.setDevice('usb-dac');
    await Future<void>.delayed(Duration.zero);
    expect(c.volume, 0.3);

    await Future<void>.delayed(const Duration(milliseconds: 600)); // the debounced save
    final kept = jsonDecode((await SharedPreferences.getInstance()).getString('volume.byOutput.v1')!) as Map;
    expect(kept['usb-dac'], 0.3);
    expect(kept['auto'], 1.0);
  });
}
