/// What a YouTube link points at, read without touching the network.
///
/// youtube_explode_dart's own parsers miss `shorts/<id>?si=…` and accept any
/// 11-character word as a video id, so Riflay reads links itself.
sealed class YoutubeLink {
  const YoutubeLink();

  /// A plain link the rest of the app (and youtube_explode_dart) understands.
  String get canonicalUrl;
}

/// One video. [startAt] is the `t=` / `start=` offset, when the link has one.
class VideoLink extends YoutubeLink {
  const VideoLink(this.videoId, {this.startAt});

  final String videoId;
  final Duration? startAt;

  @override
  String get canonicalUrl => 'https://www.youtube.com/watch?v=$videoId';

  @override
  bool operator ==(Object other) =>
      other is VideoLink && other.runtimeType == runtimeType && other.videoId == videoId && other.startAt == startAt;

  @override
  int get hashCode => Object.hash(runtimeType, videoId, startAt);

  @override
  String toString() => '$runtimeType($videoId${startAt == null ? '' : ', startAt: $startAt'})';
}

/// A video opened from inside a playlist (`watch?v=…&list=…`). Counts as a video.
class VideoInPlaylistLink extends VideoLink {
  const VideoInPlaylistLink(super.videoId, this.playlistId, {super.startAt});

  final String playlistId;

  @override
  bool operator ==(Object other) => super == other && other is VideoInPlaylistLink && other.playlistId == playlistId;

  @override
  int get hashCode => Object.hash(super.hashCode, playlistId);

  @override
  String toString() => 'VideoInPlaylistLink($videoId, $playlistId)';
}

/// A whole playlist (`playlist?list=…`).
class PlaylistLink extends YoutubeLink {
  const PlaylistLink(this.playlistId);

  final String playlistId;

  @override
  String get canonicalUrl => 'https://www.youtube.com/playlist?list=$playlistId';

  @override
  bool operator ==(Object other) => other is PlaylistLink && other.playlistId == playlistId;

  @override
  int get hashCode => playlistId.hashCode;

  @override
  String toString() => 'PlaylistLink($playlistId)';
}

abstract final class YoutubeLinks {
  static final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

  // PL user playlists, OLAK5uy_ album playlists, RD mixes, UU uploads, LL likes, FL favourites, OL/UL/LP music ones.
  static final _playlistId = RegExp(r'^(?:OLAK5uy_[A-Za-z0-9_-]{10,}|(?:PL|FL|UU|LL|OL|UL|LP|RD)[A-Za-z0-9_-]{10,})$');

  /// A YouTube host (optionally with a scheme) and everything after it up to the next space.
  /// Not preceded by word characters, dots, `@`, `/` or `=`, so `notyoutube.com`, `a@youtube.com`
  /// and `example.com/?u=youtube.com/…` are left alone.
  static final _candidate = RegExp(
    r'(?<![\w.@/=%-])(?:https?://)?(?:(?:www|m|music|mobile|gaming)\.)?'
    r'(?:youtube\.com|youtube-nocookie\.com|youtu\.be)(?![\w@-]|\.\w)(?:[/?#]\S*)?',
    caseSensitive: false,
  );

  static final _trailingPunctuation = RegExp(r'''[.,;:!?)\]}>"'*]+$''');
  static final _scheme = RegExp(r'^https?://', caseSensitive: false);
  static final _clock = RegExp(r'^(?:(\d+):)?(\d+):(\d+)$');
  static final _units = RegExp(r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s?)?$', caseSensitive: false);

  /// The first YouTube link in [text], which may be a whole shared message.
  /// A bare 11-character id or playlist id counts only with [allowBareId] (the paste field).
  static YoutubeLink? parse(String text, {bool allowBareId = false}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    if (allowBareId) {
      if (_videoId.hasMatch(trimmed)) return VideoLink(trimmed);
      if (_playlistId.hasMatch(trimmed)) return PlaylistLink(trimmed);
    }
    for (final m in _candidate.allMatches(trimmed)) {
      final link = _parseCandidate(m.group(0)!.replaceFirst(_trailingPunctuation, ''));
      if (link != null) return link;
    }
    return null;
  }

  /// Whether [text] holds a YouTube link. Bare ids don't count, so ordinary words are never taken for one.
  static bool looksLikeLink(String text) => parse(text) != null;

  static YoutubeLink? _parseCandidate(String candidate) {
    final uri = Uri.tryParse('https://${candidate.replaceFirst(_scheme, '')}');
    if (uri == null || uri.host.isEmpty) return null;
    final host = uri.host.toLowerCase();
    final segments = [
      for (final s in uri.pathSegments)
        if (s.isNotEmpty) s,
    ];
    final query = uri.queryParameters;
    final start = _startAt(query['t'] ?? query['start'] ?? _fragmentStart(uri.fragment));

    if (host == 'youtu.be') {
      if (segments.isEmpty || !_videoId.hasMatch(segments.first)) return null;
      return _video(segments.first, query['list'], start);
    }

    switch (segments.isEmpty ? '' : segments.first.toLowerCase()) {
      case 'watch':
        final id = query['v'] ?? (segments.length > 1 ? segments[1] : null);
        if (id != null && _videoId.hasMatch(id)) return _video(id, query['list'], start);
        // Only a list: treat like a playlist link.
        return _playlist(query['list']);
      case 'shorts' || 'live' || 'embed' || 'v' || 'e':
        final id = segments.length > 1 ? segments[1] : null;
        // embed/videoseries?list=… (the word happens to be 11 characters long)
        if (id == 'videoseries') return _playlist(query['list']);
        return id != null && _videoId.hasMatch(id) ? _video(id, query['list'], start) : null;
      case 'playlist':
        return _playlist(query['list']);
      case 'attribution_link':
        final inner = query['u'];
        if (inner == null || !inner.startsWith('/')) return null;
        return _parseCandidate('https://www.youtube.com$inner');
    }
    return null;
  }

  static YoutubeLink _video(String id, String? list, Duration? start) {
    if (list != null && _playlistId.hasMatch(list)) return VideoInPlaylistLink(id, list, startAt: start);
    return VideoLink(id, startAt: start);
  }

  static YoutubeLink? _playlist(String? list) => list != null && _playlistId.hasMatch(list) ? PlaylistLink(list) : null;

  static String? _fragmentStart(String fragment) => fragment.startsWith('t=') ? fragment.substring(2) : null;

  /// `90`, `90s`, `1m30s`, `1h2m3s` or `1:30`; null when it is missing, zero or not a time.
  static Duration? _startAt(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    int n(String? s) => s == null ? 0 : int.parse(s);
    final clock = _clock.firstMatch(raw);
    final units = _units.firstMatch(raw);
    final Duration d;
    if (clock != null) {
      d = Duration(hours: n(clock.group(1)), minutes: n(clock.group(2)), seconds: n(clock.group(3)));
    } else if (units != null) {
      d = Duration(hours: n(units.group(1)), minutes: n(units.group(2)), seconds: n(units.group(3)));
    } else {
      return null;
    }
    return d > Duration.zero ? d : null;
  }
}
