import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The poster being made, kept on the device as it changes, so closing the editor by accident loses nothing: the
/// editor's state as JSON, with the photo and its cut-out beside it as files (the app's own folder, never shared).
abstract final class PosterDraft {
  @visibleForTesting
  static Directory? dirOverride;

  static Future<Directory> _dir() async =>
      dirOverride ?? Directory(p.join((await getApplicationSupportDirectory()).path, 'poster-draft'));

  /// The draft: its state, and the photo and cut-out when it has them; null when there is none (or it can't be read).
  static Future<({Map<String, dynamic> state, Uint8List? photo, Uint8List? cutout})?> load() async {
    try {
      final dir = await _dir();
      final file = File(p.join(dir.path, 'draft.json'));
      if (!await file.exists()) return null;
      final state = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      Future<Uint8List?> read(String name) async {
        final f = File(p.join(dir.path, name));
        return await f.exists() ? f.readAsBytes() : null;
      }

      return (state: state, photo: await read('photo.bin'), cutout: await read('cutout.png'));
    } catch (e) {
      debugPrint('Poster draft unreadable: $e');
      return null;
    }
  }

  static Uint8List? _savedPhoto, _savedCutout;

  /// Keeps [state] (and the pictures, written again only when they changed).
  static Future<void> save(Map<String, dynamic> state, {Uint8List? photo, Uint8List? cutout}) async {
    try {
      final dir = await _dir();
      await dir.create(recursive: true);
      Future<void> picture(String name, Uint8List? bytes, Uint8List? saved) async {
        final f = File(p.join(dir.path, name));
        if (bytes == null) {
          if (await f.exists()) await f.delete();
        } else if (!identical(bytes, saved) || !await f.exists()) {
          await f.writeAsBytes(bytes, flush: true);
        }
      }

      await picture('photo.bin', photo, _savedPhoto);
      await picture('cutout.png', cutout, _savedCutout);
      _savedPhoto = photo;
      _savedCutout = cutout;
      // Aside and renamed: a save cut short never leaves half a draft.
      final part = File(p.join(dir.path, 'draft.json.part'));
      await part.writeAsString(jsonEncode(state), flush: true);
      await part.rename(p.join(dir.path, 'draft.json'));
    } catch (e) {
      debugPrint('Poster draft not saved: $e');
    }
  }

  static Future<void> clear() async {
    _savedPhoto = _savedCutout = null;
    try {
      final dir = await _dir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('Poster draft not cleared: $e');
    }
  }
}
