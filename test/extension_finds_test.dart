import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/extensions/extension_finds.dart';

void main() {
  test('remembers which extension found a song played from its results, the latest 64', () {
    final kyapi = Track.youtube(videoId: '5hWjMfWoFHk', title: 'Kyapi', artist: 'Houshou Marine');
    expect(ExtensionFinds.of(kyapi), isNull, reason: 'found any other way');
    ExtensionFinds.remember(kyapi, 'Apple Music');
    expect(ExtensionFinds.of(kyapi), 'Apple Music');
    for (var i = 0; i < 64; i++) {
      ExtensionFinds.remember(Track.youtube(videoId: 'v$i', title: '$i', artist: ''), 'Deezer');
    }
    expect(ExtensionFinds.of(kyapi), isNull, reason: 'only the latest are kept');
  });
}
