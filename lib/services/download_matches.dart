import '../models/track.dart';

/// Ranks candidates for review; never silently substitutes a recording.
abstract final class DownloadMatches {
  static String normalized(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\b(official|music video|lyrics?|audio|hd|4k)\b'), ' ')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();

  static Set<String> versions(String title) => RegExp(
    r'\b(live|remix|instrumental|karaoke|acoustic|remaster(?:ed)?|sped|slowed|extended|radio edit)\b',
    caseSensitive: false,
  ).allMatches(title).map((m) => m[0]!.toLowerCase()).toSet();

  static double score(Track origin, Track candidate) {
    final sourceIsrc = origin.extensionData?['isrc']?.toString();
    if (sourceIsrc != null &&
        sourceIsrc.isNotEmpty &&
        sourceIsrc.toUpperCase() == candidate.extensionData?['isrc']?.toString().toUpperCase()) {
      return 1;
    }
    final title = normalized(origin.title), other = normalized(candidate.title);
    final words = title.split(' ').toSet(), candidateWords = other.split(' ').toSet();
    final union = words.union(candidateWords);
    final titleScore = title == other
        ? 1.0
        : union.isEmpty
        ? 0.0
        : words.intersection(candidateWords).length / union.length;
    final artist = normalized(origin.artist), otherArtist = normalized(candidate.artist);
    final artistScore = artist == otherArtist
        ? 1.0
        : artist.isNotEmpty && otherArtist.isNotEmpty && (artist.contains(otherArtist) || otherArtist.contains(artist))
        ? .6
        : 0.0;
    final duration = origin.duration, candidateDuration = candidate.duration;
    final distance = duration == null || candidateDuration == null
        ? null
        : (duration - candidateDuration).inSeconds.abs();
    final durationScore = distance == null
        ? .25
        : distance <= 3
        ? 1.0
        : distance <= 10
        ? .6
        : 0.0;
    final versionMismatch =
        !versions(origin.title).containsAll(versions(candidate.title)) ||
        !versions(candidate.title).containsAll(versions(origin.title));
    return (titleScore * .55 + artistScore * .3 + durationScore * .15) * (versionMismatch ? .3 : 1);
  }

  static List<Track> rank(Track origin, List<Track> candidates) =>
      [...candidates]..sort((a, b) => score(origin, b).compareTo(score(origin, a)));
}
