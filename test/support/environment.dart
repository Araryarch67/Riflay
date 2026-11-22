import 'dart:io';

import 'package:media_kit/media_kit.dart';

/// What the computer running the tests has: libmpv, and commands on the PATH. Tests that need one skip without it
/// (with the reason), instead of failing on a machine set up for other work.

/// Loads libmpv once; false where it isn't installed (a Windows machine without libmpv-2.dll on the PATH).
bool get hasLibmpv => _libmpv ??= () {
  try {
    MediaKit.ensureInitialized();
    return true;
  } catch (_) {
    return false;
  }
}();
bool? _libmpv;

/// Whether [name] runs ([args], `--version` by default).
bool hasCommand(String name, [List<String> args = const ['--version']]) => _commands[name] ??= () {
  try {
    return Process.runSync(name, args).exitCode == 0;
  } catch (_) {
    return false;
  }
}();
final _commands = <String, bool>{};

/// The reason to give [skip] when [hasLibmpv] is false, else false (run).
Object get needsLibmpv => hasLibmpv ? false : 'libmpv is not installed here';

/// The reason to give [skip] when [hasCommand] is false for [name], else false (run).
Object needs(String name) => hasCommand(name) ? false : '$name is not on the PATH here';
