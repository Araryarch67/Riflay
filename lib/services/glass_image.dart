import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The picture chosen as the glass background, copied into the app's own folder: the original can be moved or
/// deleted (or, on phones, sit in a picker's cache that gets cleared) and the background stays.
///
/// Each copy has a name of its own, so a new picture isn't drawn from the old one's cached image; the copies
/// before it are removed. Returns [path] itself when it can't be copied.
Future<String> keepGlassImage(String path, {Directory? into}) async {
  try {
    final dir = into ?? Directory(p.join((await getApplicationSupportDirectory()).path, 'glass'));
    if (p.isWithin(dir.path, path)) return path;
    await dir.create(recursive: true);
    final kept = p.join(dir.path, 'background-${DateTime.now().millisecondsSinceEpoch}${p.extension(path)}');
    await File(path).copy(kept);
    await for (final old in dir.list()) {
      if (old is File && old.path != kept) await old.delete().catchError((_) => old);
    }
    return kept;
  } catch (e) {
    debugPrint('Glass background not copied: $e');
    return path;
  }
}
