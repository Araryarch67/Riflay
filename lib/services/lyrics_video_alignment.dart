import 'lyrics.dart';

/// Uses shared lyric lines to place a local recording on the YouTube song's
/// timeline. The existing song-to-MV map is applied afterwards, preserving
/// video-only intros and scenes.
abstract final class LyricsVideoAlignment {
  /// YouTube song time minus local audio time, or null for ambiguous lyrics.
  /// Repeated lines cannot identify which chorus is being sung, so only unique
  /// lines count. Enough lines must agree across a substantial part of the song.
  static Duration? offset(Lyrics audio, Lyrics song) {
    if (audio.otherVersion || song.otherVersion) return null;
    Map<String, Duration> unique(Lyrics lyrics) {
      final times = <String, Duration>{};
      final repeated = <String>{};
      for (final line in lyrics.lines) {
        final text = LyricsService.norm(line.text);
        if (text.runes.length < 4) continue;
        if (times.containsKey(text)) repeated.add(text);
        times[text] = line.time;
      }
      for (final text in repeated) {
        times.remove(text);
      }
      return times;
    }

    final local = unique(audio), remote = unique(song);
    final pairs = [
      for (final entry in local.entries)
        if (remote[entry.key] case final time?) (entry.value, time),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    if (pairs.length < 4 || pairs.length < local.length * 0.6 || pairs.length < remote.length * 0.6) return null;
    final offsets = [for (final p in pairs) (p.$2 - p.$1).inMilliseconds]..sort();
    final median = offsets[offsets.length ~/ 2];
    if (median.abs() > 30000) return null;
    final agreed = pairs.where((p) => ((p.$2 - p.$1).inMilliseconds - median).abs() <= 250).toList();
    if (agreed.length < 4 || agreed.length < pairs.length * 0.8) return null;
    if (agreed.last.$1 - agreed.first.$1 < const Duration(seconds: 20)) return null;
    for (var i = 1; i < agreed.length; i++) {
      if (agreed[i].$2 <= agreed[i - 1].$2) return null;
    }
    return Duration(milliseconds: median);
  }
}
