import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import 'ytmusic_web.dart';

/// A manual delay of the picture alone, saved per song, audio source and MV.
/// Negative shows the picture earlier; positive shows it later.
class VideoTiming extends ValueNotifier<Duration> {
  VideoTiming._(this.key) : super(Duration.zero) {
    ready = () async {
      final revision = _revision;
      final prefs = await SharedPreferences.getInstance();
      if (revision == _revision) value = Duration(milliseconds: prefs.getInt(key) ?? 0);
    }();
    ready.catchError((Object e) => debugPrint('Video timing: could not read: $e'));
  }

  final String key;
  late final Future<void> ready;
  int _revision = 0;
  Future<void> _saving = Future.value();
  static final _timings = <String, VideoTiming>{};

  /// The same MV can need another correction when its audio source changes.
  static VideoTiming of(Track song, Track audio, String videoId) {
    final key =
        'video.shift.v1.${jsonEncode([song.id, audio.uri.toString(), audio.start?.inMicroseconds, audio.end?.inMicroseconds, videoId])}';
    return _timings[key] ??= VideoTiming._(key);
  }

  /// Updates playback immediately and serializes writes so rapid taps persist
  /// their final value. A failed save is reported by the controls.
  Future<void> setShift(Duration shift) {
    _revision++;
    value = shift;
    return _saving = _saving.catchError((Object _) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final saved = shift == Duration.zero ? await prefs.remove(key) : await prefs.setInt(key, shift.inMilliseconds);
      if (!saved) throw StateError('Video timing could not be saved');
    });
  }

  /// Applies the correction after the automatic timeline map, so the amount
  /// shown by the controls is in video seconds even with a different master.
  Duration? videoTimeAt(MusicVideo video, Duration audio, {Duration lyricsOffset = Duration.zero}) {
    final song = audio + lyricsOffset;
    if (song.isNegative) return null;
    final mapped = video.videoTimeAt(song);
    if (mapped == null) return null;
    final target = mapped - value;
    return target.isNegative ? null : target;
  }

  @visibleForTesting
  static void clearCache() => _timings.clear();
}
