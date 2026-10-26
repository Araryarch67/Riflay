import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/stay_awake.dart';

Future<bool> listed() async {
  final out = await Process.run('systemd-inhibit', ['--list', '--no-pager']);
  return (out.stdout as String).contains('Playing music');
}

/// Takes a real logind lock on this machine, so it only runs when asked:
/// `RIFLAY_SYSTEM_TESTS=1 flutter test test/linux_idle_inhibitor_test.dart`.
void main() {
  test('logind idle lock appears while held and is gone after release', () async {
    final idle = LinuxIdleInhibitor();
    try {
      await idle.acquire();
      expect(await listed(), isTrue);
    } finally {
      await idle.release();
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(await listed(), isFalse);
  }, skip:
        !Platform.isLinux ||
        !Directory('/run/systemd/system').existsSync() ||
        Platform.environment['RIFLAY_SYSTEM_TESTS'] != '1');
}
