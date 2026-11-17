import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';

/// A per-song audio override. The YouTube track remains the playback identity.
class ManualAudioChoice {
  const ManualAudioChoice.youtube() : track = null;
  const ManualAudioChoice.track(this.track);

  /// Null explicitly selects YouTube. No saved choice means automatic merging.
  final Track? track;
}

/// Keeps explicit audio choices separately from automatic match caches.
class ManualAudio {
  static const _key = 'smartMerge.manualAudio.v1';
  final _choices = <String, ManualAudioChoice>{};

  ManualAudioChoice? choice(String videoId) => _choices[videoId];

  void load(SharedPreferences prefs) {
    _choices.clear();
    try {
      final values = jsonDecode(prefs.getString(_key) ?? '{}') as Map<String, dynamic>;
      for (final entry in values.entries) {
        try {
          final value = entry.value;
          final track = value == null ? null : Track.fromJson((value as Map).cast<String, dynamic>());
          if (track != null && !supports(track)) continue;
          _choices[entry.key] = track == null ? const ManualAudioChoice.youtube() : ManualAudioChoice.track(track);
        } catch (_) {
          // One obsolete file must not discard the other songs' choices.
        }
      }
    } catch (e) {
      debugPrint('Manual audio choices unreadable: ${e.runtimeType}');
    }
  }

  /// Download-only providers must be represented by their playable local file.
  static bool supports(Track track) => track.path != null || track.monochromeId != null;

  /// Null restores automatic selection for this song alone.
  Future<void> set(String videoId, ManualAudioChoice? choice) async {
    if (choice?.track case final track? when !supports(track)) {
      throw ArgumentError('Audio source is not playable');
    }
    final next = {..._choices};
    if (choice == null) {
      next.remove(videoId);
    } else {
      next[videoId] = choice;
    }
    final saved = await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode({for (final entry in next.entries) entry.key: entry.value.track?.toJson()}),
    );
    if (!saved) throw StateError('Audio choice could not be saved');
    _choices
      ..clear()
      ..addAll(next);
  }
}
