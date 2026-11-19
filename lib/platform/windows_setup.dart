import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Updates only the registered per-user Inno Setup installation.
abstract final class WindowsSetup {
  static const _channel = MethodChannel('riflay/window');

  static Future<String?> installedDirectory() async {
    if (!Platform.isWindows) return null;
    try {
      final directory = await _channel.invokeMethod<String>('innoInstallLocation');
      if (directory == null || !p.windows.isAbsolute(directory)) return null;
      final registered = await File(p.join(directory, 'riflay.exe')).resolveSymbolicLinks();
      final running = await File(Platform.resolvedExecutable).resolveSymbolicLinks();
      if (!sameExecutable(registered, running)) return null;
      return p.dirname(registered);
    } on Object {
      return null;
    }
  }

  /// Compare canonical Windows paths without treating case changes as different installations.
  static bool sameExecutable(String registered, String running) =>
      p.windows.normalize(registered).toLowerCase() == p.windows.normalize(running).toLowerCase();

  static Future<void> install(String installer, String directory) async {
    await Process.start(installer, [
      '/SILENT',
      '/SP-',
      '/NORESTART',
      '/NOCLOSEAPPLICATIONS',
      '/DIR=$directory',
      '/RIFLAYPID=$pid',
    ], mode: ProcessStartMode.detached);
  }
}
