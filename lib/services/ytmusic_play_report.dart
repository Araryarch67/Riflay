/// When a play counts for YouTube Music's history: after about 30 seconds of
/// listening, or when the song ends, whichever comes first. Once per play.
///
/// Pure: feed it what the player says and it answers whether to report now.
class PlayReportClock {
  PlayReportClock({this.threshold = const Duration(seconds: 30)});

  final Duration threshold;

  String? _id;
  Duration? _last;
  Duration _heard = Duration.zero;
  bool _reported = false;
  bool _wasEnded = false;

  /// Time listened to the current play so far.
  Duration get heard => _heard;

  /// One look at the player. Returns true exactly once per play, when it's
  /// time to report [trackId]. A jump (seek) adds nothing to the time heard.
  bool tick({required String? trackId, required Duration position, required bool playing, required bool ended}) {
    if (trackId != _id) {
      _id = trackId;
      _restart();
    }
    if (trackId == null) return false;

    if (ended) {
      // The song finished: counts even when shorter than the threshold.
      if (_wasEnded) return false;
      _wasEnded = true;
      return _report();
    }
    if (_wasEnded) {
      // Played again (repeat one): a new play.
      _wasEnded = false;
      _restart();
    }

    final last = _last;
    _last = position;
    if (last != null) {
      final step = position - last;
      if (_reported && step < const Duration(seconds: -5)) {
        _restart(); // looped back to the start without finishing
        _last = position;
      } else if (playing && step > Duration.zero && step <= const Duration(seconds: 2)) {
        _heard += step;
      }
    }
    return _heard >= threshold && _report();
  }

  bool _report() {
    if (_reported) return false;
    _reported = true;
    return true;
  }

  void _restart() {
    _last = null;
    _heard = Duration.zero;
    _reported = false;
    _wasEnded = false;
  }
}
