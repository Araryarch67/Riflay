import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/listen_together/windows_firewall.dart';

void main() {
  test("the check counts enabled inbound rules blocking this program, by the cmdlets' untranslated names", () {
    final script = WindowsFirewall.checkScript(r"C:\Users\O'Neil\Riflay\riflay.exe");
    expect(script, contains(r"$p = 'C:\Users\O''Neil\Riflay\riflay.exe'"), reason: 'a quote in the path doubled');
    expect(script, contains(r"$_.Program -ieq $p"));
    expect(script, contains("\$_.Action -eq 'Block'"));
    expect(script, contains("\$_.Direction -eq 'Inbound'"));
  });

  test('allowing removes the blocking rules and puts one rule of ours in, not one more each time', () {
    final script = WindowsFirewall.allowScript(r'C:\Riflay\riflay.exe');
    expect(script, contains("\$_.Action -eq 'Block' } | Remove-NetFirewallRule"));
    expect(
      script,
      contains("Get-NetFirewallRule -DisplayName 'Riflay (Listen Together)' -ErrorAction SilentlyContinue"),
    );
    expect(script, contains("New-NetFirewallRule -DisplayName 'Riflay (Listen Together)' -Direction Inbound"));
    expect(script, contains('-Action Allow -Profile Any'));
  });

  test('a script goes to PowerShell as UTF-16LE in base64', () {
    final text = "Write-Output 'Riflay ♪'";
    final bytes = base64.decode(WindowsFirewall.encoded(text));
    expect(String.fromCharCodes([for (var i = 0; i < bytes.length; i += 2) bytes[i] | bytes[i + 1] << 8]), text);
  });

  test(
    'on Windows the check runs and answers',
    () async {
      expect(await WindowsFirewall.blocks(), isA<bool>());
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-EncodedCommand',
        WindowsFirewall.encoded(WindowsFirewall.checkScript(r'C:\nowhere\riflay.exe')),
      ]);
      expect('${r.stdout}'.trim(), '0', reason: '${r.stderr}');
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
