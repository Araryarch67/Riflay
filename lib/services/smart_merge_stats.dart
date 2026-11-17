import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Today's Smart merge, for Settings › Music sources: how many songs played in lossless, how many from YouTube
/// Music (no match, or not ready yet), how many a source held back with its request limit, and how many opened
/// from the songs kept on disk without asking the service. Each song counts once a day in each; a song that began
/// from YouTube and moved over counts in both.
class SmartMergeStats extends ChangeNotifier {
  SmartMergeStats._();

  static final instance = SmartMergeStats._();

  static const _key = 'smartMerge.stats.v1';

  /// Songs a day keeps per kind: plenty for a day's listening, and the saved list stays small.
  static const _most = 2000;

  String _day = _today();
  final _lossless = <String>{};
  final _youtube = <String>{};
  final _limited = <String>{};
  final _kept = <String>{};
  Future<void>? _loading;

  int get lossless => _lossless.length;
  int get youtube => _youtube.length;
  int get limited => _limited.length;
  int get kept => _kept.length;

  static String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> load() => _loading ??= () async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['day'] != _today()) return;
      Iterable<String> ids(String k) => (j[k] as List? ?? const []).whereType<String>();
      _lossless.addAll(ids('lossless'));
      _youtube.addAll(ids('youtube'));
      _limited.addAll(ids('limited'));
      _kept.addAll(ids('kept'));
      notifyListeners();
    } catch (e) {
      debugPrint('Smart merge stats unreadable: ${e.runtimeType}');
    }
  }();

  void playedLossless(String videoId) => _add(_lossless, videoId);
  void playedYoutube(String videoId) => _add(_youtube, videoId);
  void heldBack(String videoId) => _add(_limited, videoId);
  void openedKept(String videoId) => _add(_kept, videoId);

  void _add(Set<String> kind, String videoId) {
    unawaited(load());
    final day = _today();
    if (day != _day) {
      _day = day;
      _lossless.clear();
      _youtube.clear();
      _limited.clear();
      _kept.clear();
    }
    if (kind.length >= _most || !kind.add(videoId)) return;
    notifyListeners();
    unawaited(_write());
  }

  Future<void> _write() async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        _key,
        jsonEncode({
          'day': _day,
          'lossless': _lossless.toList(),
          'youtube': _youtube.toList(),
          'limited': _limited.toList(),
          'kept': _kept.toList(),
        }),
      );
    } catch (e) {
      debugPrint('Smart merge stats not saved: ${e.runtimeType}');
    }
  }

  @visibleForTesting
  void reset() {
    _loading = null;
    _day = _today();
    _lossless.clear();
    _youtube.clear();
    _limited.clear();
    _kept.clear();
  }
}
