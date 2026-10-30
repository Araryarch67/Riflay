import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/linux_alsa.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('asound'));
  tearDown(() => root.deleteSync(recursive: true));

  void status(String pcm, String text) =>
      (File('${root.path}/card1/$pcm/sub0/status')..createSync(recursive: true)).writeAsStringSync(text);

  test('the card is handed back to PipeWire only once its playback devices are closed', () {
    status('pcm0p', 'state: RUNNING\nowner_pid   : 4242\n');
    status('pcm0c', 'state: RUNNING\n'); // a capture device being open doesn't matter
    status('pcm3p', 'closed\n');
    expect(CardReservation.playbackClosed(1, root: root.path), isFalse);
    status('pcm0p', 'closed\n');
    expect(CardReservation.playbackClosed(1, root: root.path), isTrue);
  });

  test('a card that can\'t be read counts as closed, so a release never hangs', () {
    expect(CardReservation.playbackClosed(9, root: root.path), isTrue);
  });

  test('releasing ends the reservation itself, not just the shell around it', () async {
    if (!Platform.isLinux) return;
    // A stand-in for pw-reserve: says it has the card, then holds it (a sleep with a marker to find it by).
    const marker = '313.25';
    final saved = CardReservation.reserveCommand;
    CardReservation.reserveCommand = (_) => 'sh -c "echo reserve acquired; exec sleep $marker"';
    addTearDown(() => CardReservation.reserveCommand = saved);
    Future<bool> holding() async => (await Process.run('pgrep', ['-f', 'sleep $marker'])).exitCode == 0;

    final r = await CardReservation.acquire(99);
    expect(r, isNotNull);
    expect(await holding(), isTrue);
    await r!.release();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(await holding(), isFalse, reason: 'the card must go back to PipeWire as soon as bit-perfect is off');
  });
}
