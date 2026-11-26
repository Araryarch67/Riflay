import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import '../platform/background.dart';
import 'private_files.dart';

/// The library on disk.
///
/// It has a file of its own, read and written in a background isolate: as a SharedPreferences value it was
/// rewritten (and encoded on the UI isolate) with every other setting saved, tens of milliseconds each time
/// with a big library. Preferences only remember that it moved ([_movedKey]), so a fresh
/// (or test) set of preferences still means an empty library.
abstract final class LibraryStore {
  static const _legacyKey = 'library.v1';
  static const _movedKey = 'library.file.v1';
  static const _name = 'library.json';

  @visibleForTesting
  static List<Track> readFile(File file) => _read(file);

  static Future<File?> _file() async {
    try {
      return await PrivateFiles.file(_name);
    } catch (_) {
      return null; // no app folder (widget tests): preferences hold it
    }
  }

  static Future<List<Track>> load(SharedPreferences prefs) async {
    final legacy = prefs.getString(_legacyKey);
    if (legacy != null) {
      final tracks = await inBackground(() => _decode(legacy));
      // Moved the first time; the old value goes once the file is safely written.
      if (await _writeFile(tracks)) {
        await prefs.setBool(_movedKey, true);
        await prefs.remove(_legacyKey);
      }
      return tracks;
    }
    if (prefs.getBool(_movedKey) != true) return [];
    final file = await _file();
    if (file == null) return [];
    try {
      return await inBackground(() => file.existsSync() ? _read(file) : <Track>[]);
    } catch (e) {
      debugPrint('Library file unreadable, starting empty: $e');
      return [];
    }
  }

  static Future<void>? _saving;
  static List<Track>? _next;
  static SharedPreferences? _prefs;

  /// Saves [tracks] (the list is copied). Saves overlapping one running are
  /// folded into one more, with the newest list.
  static Future<void> save(SharedPreferences prefs, List<Track> tracks) {
    _prefs = prefs;
    _next = List.of(tracks);
    return _saving ??= _drain();
  }

  static Future<void> _drain() async {
    try {
      for (var tracks = _next; tracks != null; tracks = _next) {
        _next = null;
        final prefs = _prefs!;
        if (await _writeFile(tracks)) {
          if (prefs.getBool(_movedKey) != true) await prefs.setBool(_movedKey, true);
          if (prefs.containsKey(_legacyKey)) await prefs.remove(_legacyKey);
        } else {
          await prefs.setString(_legacyKey, jsonEncode([for (final t in tracks) t.toJson()]));
        }
      }
    } finally {
      _saving = null;
    }
  }

  static Future<bool> _writeFile(List<Track> tracks) async {
    final file = await _file();
    if (file == null) return false;
    try {
      await inBackground(() => PrivateFiles.writeSync(file, jsonEncode([for (final t in tracks) t.toJson()])));
      return true;
    } catch (e) {
      debugPrint('Saving the library failed: $e');
      return false;
    }
  }

  /// The songs in [file]. Any it can't read are left out, and the file is first copied aside
  /// (`library.json.unreadable`): the next save would write over them.
  static List<Track> _read(File file) {
    final json = file.readAsStringSync();
    try {
      return _decode(json);
    } catch (_) {
      file.copySync('${file.path}.unreadable');
      final tracks = <Track>[];
      for (final j in jsonDecode(json) as List) {
        try {
          tracks.add(Track.fromJson((j as Map).cast<String, dynamic>()));
        } catch (e) {
          debugPrint('Library: left out an unreadable song: $e');
        }
      }
      return tracks;
    }
  }

  static List<Track> _decode(String json) => [
    for (final j in jsonDecode(json) as List) Track.fromJson((j as Map).cast<String, dynamic>()),
  ];
}
