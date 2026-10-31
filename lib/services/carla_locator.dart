import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/host.dart';

/// Where the pieces of audio plugins are on this computer: the bridge shipped
/// with the app (`linux/carla_bridge`), Carla (the free plugin host the user
/// installs themselves) and the project they set up in it. The bridge looks in
/// the same places (riflay_carla.cc), so keep the two in step.
abstract final class CarlaLocator {
  /// Carla's download page. Riflay never fetches third-party programs on its own.
  static const downloadPage = 'https://github.com/falkTX/Carla/releases/latest';

  static String get _lib => Host.isWindows
      ? 'libcarla_native-plugin.dll'
      : (Host.isMacOS ? 'libcarla_native-plugin.dylib' : 'libcarla_native-plugin.so');

  /// The bridge in the app: `lib/libriflay_carla.so` (Linux), `riflay_carla.dll`
  /// next to the exe (Windows), `Contents/Frameworks/libriflay_carla.dylib` (macOS).
  static String? get bridge {
    final exe = File(Platform.resolvedExecutable).parent;
    final path = switch (Host.operatingSystem) {
      'linux' => p.join(exe.path, 'lib', 'libriflay_carla.so'),
      'windows' => p.join(exe.path, 'riflay_carla.dll'),
      'macos' => p.join(exe.parent.path, 'Frameworks', 'libriflay_carla.dylib'),
      _ => null,
    };
    return path != null && File(path).existsSync() ? path : null;
  }

  /// The app's own folder for the project, as the bridge works it out: the
  /// support folder on Windows and macOS, `~/.config/riflay` on Linux.
  static String get folder => folderFor(Host.operatingSystem, Host.environment);

  @visibleForTesting
  static String folderFor(String os, Map<String, String> env) {
    switch (os) {
      case 'windows':
        return p.windows.join(env['APPDATA'] ?? '', 'dev.riflay', 'riflay');
      case 'macos':
        return p.posix.join(env['HOME'] ?? '', 'Library', 'Application Support', 'dev.riflay.riflay');
      default:
        final config = (env['XDG_CONFIG_HOME'] ?? '').isNotEmpty ? env['XDG_CONFIG_HOME']! : '${env['HOME']}/.config';
        return p.posix.join(config, 'riflay');
    }
  }

  /// The Carla project the bridge loads.
  static String get project => p.join(folder, 'plugins.carxp');

  /// Where Carla's libraries are looked for without a search: Linux packages
  /// and macOS' Carla.app.
  static List<String> get _fixedDirs {
    final env = Host.environment;
    if (Host.isMacOS) {
      return ['/Applications/Carla.app/Contents/MacOS', '${env['HOME']}/Applications/Carla.app/Contents/MacOS'];
    }
    return const ['/usr/lib/carla', '/usr/lib64/carla', '/usr/local/lib/carla', '/usr/lib/x86_64-linux-gnu/carla'];
  }

  static String? _found;
  static DateTime? _lookedAt;

  /// The folder with Carla's libraries, or null when Carla isn't installed.
  /// Windows has no installer, only a zip to unpack anywhere, so the places
  /// people unpack it are searched; the answer is kept for a few seconds.
  static String? get dir {
    final found = _found;
    if (found != null && File(p.join(found, _lib)).existsSync()) return found;
    final at = _lookedAt;
    if (at != null && DateTime.now().difference(at) < const Duration(seconds: 5)) return null;
    _lookedAt = DateTime.now();
    _found = Host.isWindows ? findOnWindows(Host.environment) : _fixedDirs.where(_has).firstOrNull;
    final dir = _found;
    if (dir != null && Host.isWindows) _tellBridge(dir);
    return dir;
  }

  static bool _has(String dir) => File(p.join(dir, _lib)).existsSync();

  /// Looks for a folder called Carla… (the zip unpacks as `Carla-2.5.10-win64\Carla`) in the usual places.
  @visibleForTesting
  static String? findOnWindows(Map<String, String> env) {
    final home = env['USERPROFILE'] ?? '';
    final roots = <String>[
      for (final v in ['ProgramFiles', 'ProgramW6432', 'LOCALAPPDATA']) ?env[v],
      if ((env['LOCALAPPDATA'] ?? '').isNotEmpty) p.windows.join(env['LOCALAPPDATA']!, 'Programs'),
      if (home.isNotEmpty) ...[
        home,
        p.windows.join(home, 'Downloads'),
        p.windows.join(home, 'Desktop'),
        p.windows.join(home, 'Documents'),
      ],
      'C:\\',
    ];
    for (final root in roots.toSet()) {
      try {
        final top = Directory(root);
        if (!top.existsSync()) continue;
        for (final e in top.listSync(followLinks: false)) {
          if (e is! Directory || !p.basename(e.path).toLowerCase().startsWith('carla')) continue;
          for (final d in [e.path, p.windows.join(e.path, 'Carla')]) {
            if (_has(d)) return d;
          }
          // An unpacked zip in a folder of the same name.
          for (final sub in e.listSync(followLinks: false)) {
            if (sub is Directory && _has(p.windows.join(sub.path, 'Carla'))) return p.windows.join(sub.path, 'Carla');
          }
        }
      } on FileSystemException {
        // A folder we may not read: skip it.
      }
    }
    return null;
  }

  /// The bridge looks for Carla in the usual places only; for the folder found
  /// by searching, it reads `carla_dir.txt` in the app's folder.
  static void _tellBridge(String dir) {
    try {
      final file = File(p.join(folder, 'carla_dir.txt'));
      if (file.existsSync() && file.readAsStringSync().trim() == dir) return;
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('$dir\n');
    } on FileSystemException catch (e) {
      debugPrint('carla_dir.txt: $e');
    }
  }

  /// Carla's own program, to edit the project in.
  static String get executable {
    final d = dir;
    if (d == null) return 'carla';
    return Host.isWindows ? p.join(d, 'Carla.exe') : (Host.isMacOS ? p.join(d, 'Carla') : 'carla');
  }

  /// Whether Carla is installed.
  static bool get installed => dir != null;
}
