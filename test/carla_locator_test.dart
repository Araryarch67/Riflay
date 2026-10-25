import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/audio_engine.dart';
import 'package:riflay/services/carla_locator.dart';

void main() {
  test('the project lives in the app folder of each system, where the bridge reads it', () {
    expect(
      CarlaLocator.folderFor('windows', {'APPDATA': r'C:\Users\Ana\AppData\Roaming'}),
      r'C:\Users\Ana\AppData\Roaming\dev.riflay\riflay',
    );
    expect(
      CarlaLocator.folderFor('macos', {'HOME': '/Users/ana'}),
      '/Users/ana/Library/Application Support/dev.riflay.riflay',
    );
    expect(CarlaLocator.folderFor('linux', {'HOME': '/home/ana'}), '/home/ana/.config/riflay');
    expect(CarlaLocator.folderFor('linux', {'HOME': '/home/ana', 'XDG_CONFIG_HOME': '/x'}), '/x/riflay');
  });

  test('a Windows path to the bridge survives the filter graph', () {
    // mpv's lavfi parses the graph, then ladspa parses its options: two levels of escaping.
    expect(
      AudioEngine.graphPath(r'C:\Program Files\Riflay\riflay_carla.dll'),
      r'C\\:/Program Files/Riflay/riflay_carla.dll',
    );
  });
}
