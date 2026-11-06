import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Serializes discovery, downloads and cleanup of Riflay's downloaded command-line tools.
/// A cleanup waits for a download to finish, and a later lookup cannot reuse a file being removed.
abstract final class ExecutableStore {
  static Future<void> _pending = Future<void>.value();

  static Future<Directory> directory() async => Directory(p.join((await getApplicationSupportDirectory()).path, 'bin'));

  static Future<T> run<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
