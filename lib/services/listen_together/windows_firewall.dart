import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Windows Firewall and Riflay, for Listen Together on the same Wi-Fi. The first time Riflay listens on the network
/// Windows asks whether to let it; refused (often by a slip), it keeps a rule blocking Riflay and never asks again,
/// and friends can't find or join the session. This tells that rule is there, and asks again: with an
/// administrator's permission (Windows' own prompt) it removes the blocking rules and allows Riflay in.
abstract final class WindowsFirewall {
  static const ruleName = 'Riflay (Listen Together)';

  /// Whether this build can be asked about at all.
  static bool get supported => !kIsWeb && Platform.isWindows;

  /// Single-quoted for PowerShell.
  static String _quoted(String s) => "'${s.replaceAll("'", "''")}'";

  /// PowerShell that prints how many enabled rules block [exe] from being reached. Read with the cmdlets' own
  /// property names, which a Windows in another language doesn't translate (netsh's output it does).
  @visibleForTesting
  static String checkScript(String exe) =>
      '\$p = ${_quoted(exe)}; '
      '@(Get-NetFirewallApplicationFilter | Where-Object { \$_.Program -ieq \$p } | Get-NetFirewallRule | '
      "Where-Object { \$_.Enabled -eq 'True' -and \$_.Direction -eq 'Inbound' -and \$_.Action -eq 'Block' }).Count";

  /// PowerShell, run as an administrator, that removes the rules blocking [exe] and lets it in on every network
  /// (a home Wi-Fi is often set as public), replacing an earlier rule of ours rather than adding one each time.
  @visibleForTesting
  static String allowScript(String exe) =>
      '\$p = ${_quoted(exe)}; '
      'Get-NetFirewallApplicationFilter | Where-Object { \$_.Program -ieq \$p } | Get-NetFirewallRule | '
      "Where-Object { \$_.Action -eq 'Block' } | Remove-NetFirewallRule; "
      'Get-NetFirewallRule -DisplayName ${_quoted(ruleName)} -ErrorAction SilentlyContinue | Remove-NetFirewallRule; '
      'New-NetFirewallRule -DisplayName ${_quoted(ruleName)} -Direction Inbound -Program \$p -Action Allow '
      '-Profile Any | Out-Null';

  /// [script] for `powershell -EncodedCommand`: UTF-16LE, base64. Nothing in a path needs quoting through two
  /// shells that way.
  @visibleForTesting
  static String encoded(String script) => base64.encode([
    for (final unit in script.codeUnits) ...[unit & 0xff, unit >> 8],
  ]);

  static Future<ProcessResult> _powershell(String script) =>
      Process.run('powershell', ['-NoProfile', '-NonInteractive', '-EncodedCommand', encoded(script)]);

  /// Whether the firewall blocks Riflay from being reached (false when it can't tell, or off Windows).
  static Future<bool> blocks() async {
    if (!supported) return false;
    try {
      final r = await _powershell(checkScript(Platform.resolvedExecutable));
      return (int.tryParse('${r.stdout}'.trim()) ?? 0) > 0;
    } catch (e) {
      debugPrint('Firewall: no answer: $e');
      return false;
    }
  }

  /// Asks Windows again, with its administrator prompt, and lets Riflay in; true once nothing blocks it any more.
  /// False when the prompt was declined.
  static Future<bool> allow() async {
    if (!supported) return true;
    try {
      // Start-Process -Verb RunAs shows Windows' prompt; declined, it fails and so does this.
      final elevate =
          "Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList '-NoProfile','-EncodedCommand',"
          "'${encoded(allowScript(Platform.resolvedExecutable))}'";
      final r = await _powershell(elevate);
      if (r.exitCode != 0) return false;
      return !await blocks();
    } catch (e) {
      debugPrint('Firewall: not changed: $e');
      return false;
    }
  }
}
