import '../services/language.dart';

import 'package:path/path.dart' as p;

/// A single playable audio file in the library.
class Track {
  /// Measured file/stream quality takes precedence over catalogue information.
  String? get qualityLabel {
    if (audioQuality != null && audioQuality!.isNotEmpty) return audioQuality;
    if (extensionQualityLabel case final label?) return label;
    final file = path;
    if (file == null) return null;
    final ext = p.extension(file).replaceFirst('.', '').toLowerCase();
    return audioExtensions.contains(ext) ? (ext == 'opus' ? 'Opus' : ext.toUpperCase()) : null;
  }

  /// Quality advertised by the extension's catalogue, not a measured playback format.
  /// Do not infer it from the provider's selected download preference.
  String? get extensionQualityLabel {
    if (extensionId == null) return null;
    final data = extensionData;
    final raw = (data?['audio_quality'] ?? data?['audioQuality'] ?? data?['codec'] ?? '').toString().trim();
    if (raw.isEmpty) return null;
    final quality = raw.toUpperCase();
    if (extensionId == 'tidal-web') {
      if (quality == 'HI_RES_LOSSLESS' || quality == '24BIT') return 'FLAC 24-bit';
      if (quality == 'LOSSLESS' || quality == '16BIT/44.1KHZ') return 'FLAC 16-bit / 44.1 kHz';
      if (quality == 'HIGH' || quality == '320KBPS') return 'AAC 320 kbps';
      if (quality == 'LOW' || quality == '96KBPS') return 'AAC 96 kbps';
      if (quality == 'HI_RES' || quality == 'MQA') return 'MQA';
    }
    return switch (quality) {
      'FLAC' => 'FLAC',
      'ALAC' => 'ALAC',
      'WAV' => 'WAV',
      'AAC' ||
      'AAC_320' ||
      'AAC_256' ||
      'AAC_128' => quality.replaceFirst('_', ' ') + (quality.contains('_') ? ' kbps' : ''),
      'MP3' || 'MP3_320' || 'MP3_128' => quality.replaceFirst('_', ' ') + (quality.contains('_') ? ' kbps' : ''),
      'OPUS' => 'Opus',
      'VORBIS' => 'Vorbis',
      _ => null,
    };
  }

  const Track({
    required this.id,
    required this.uri,
    required this.title,
    required this.artist,
    this.album,
    this.duration,
    this.trackNumber,
    this.discNumber,
    this.start,
    this.end,
    this.addedAt = 0,
    this.tagged = false,
    this.sourceUrl,
    this.videoId,
    this.artworkUrl,
    this.artistId,
    this.extensionData,
    this.downloadYoutubeId,
    this.audioQuality,
  });

  /// A YouTube / YouTube Music song that streams instead of playing from disk.
  factory Track.youtube({
    required String videoId,
    required String title,
    required String artist,
    Duration? duration,
    String? artworkUrl,
    String? artistId,
  }) => Track(
    id: 'yt:$videoId',
    uri: Uri.parse('https://music.youtube.com/watch?v=$videoId'),
    title: title,
    artist: artist,
    duration: duration,
    tagged: true,
    sourceUrl: 'https://music.youtube.com/watch?v=$videoId',
    videoId: videoId,
    artworkUrl: artworkUrl ?? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
    artistId: artistId,
  );

  /// A SoundCloud track that streams. [permalink] is its page (`soundcloud.com/<user>/<track>`), kept for sharing;
  /// playback needs only [trackId] (see `SoundcloudClient.playlistFor`). [userId] is the uploader's, for their page.
  factory Track.soundcloud({
    required String trackId,
    required String title,
    required String artist,
    String? permalink,
    Duration? duration,
    String? artworkUrl,
    String? userId,
  }) => Track(
    id: '$soundcloudPrefix$trackId',
    uri: Uri.parse(permalink ?? 'https://api.soundcloud.com/tracks/$trackId'),
    title: title,
    artist: artist,
    duration: duration,
    tagged: true,
    sourceUrl: permalink,
    artworkUrl: artworkUrl,
    artistId: userId,
  );

  /// [id]'s prefix for a SoundCloud track; the rest is SoundCloud's numeric track id.
  static const soundcloudPrefix = 'sc:';

  /// A Spotify track that streams from the signed-in Premium account (see `SpotifyBridge`). [trackId] is
  /// Spotify's own (the end of `spotify:track:…`); its page is kept for sharing.
  factory Track.spotify({
    required String trackId,
    required String title,
    required String artist,
    String? album,
    Duration? duration,
    String? artworkUrl,
  }) => Track(
    id: '$spotifyPrefix$trackId',
    uri: Uri.parse('https://open.spotify.com/track/$trackId'),
    title: title,
    artist: artist,
    album: album,
    duration: duration,
    tagged: true,
    sourceUrl: 'https://open.spotify.com/track/$trackId',
    artworkUrl: artworkUrl,
  );

  /// [id]'s prefix for a Spotify track; the rest is Spotify's track id.
  static const spotifyPrefix = 'sp:';

  /// Builds a track from a file URI, guessing title/artist from the
  /// "Artist - Title.ext" filename convention until real tags are read.
  factory Track.fromUri(Uri uri, {String? displayName}) {
    // pathSegments are already percent-decoded.
    final name = displayName ?? (uri.pathSegments.isEmpty ? uri.toString() : uri.pathSegments.last);
    final base = p.basenameWithoutExtension(name).replaceAll('_', ' ').trim();
    final parts = base.split(' - ');
    final hasArtist = parts.length >= 2;
    return Track(
      id: uri.toString(),
      uri: uri,
      title: hasArtist ? parts.sublist(1).join(' - ').trim() : base,
      artist: hasArtist ? parts.first.trim() : unknownArtist,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    id: json['id'] as String,
    uri: Uri.parse(json['uri'] as String),
    title: json['title'] as String,
    artist: json['artist'] as String,
    album: json['album'] as String?,
    // Older versions could save a length of 0 (see PlayerController._correctDuration): unknown, not 0:00.
    duration: switch (json['durationMs']) {
      final int ms when ms > 0 => Duration(milliseconds: ms),
      _ => null,
    },
    trackNumber: json['trackNumber'] as int?,
    discNumber: json['discNumber'] as int?,
    start: json['startMs'] == null ? null : Duration(milliseconds: json['startMs'] as int),
    end: json['endMs'] == null ? null : Duration(milliseconds: json['endMs'] as int),
    addedAt: json['addedAt'] as int? ?? 0,
    tagged: json['tagged'] as bool? ?? false,
    sourceUrl: json['sourceUrl'] as String?,
    videoId: json['videoId'] as String?,
    artworkUrl: json['artworkUrl'] as String?,
    artistId: json['artistId'] as String?,
    downloadYoutubeId: json['downloadYoutubeId'] as String?,
    audioQuality: json['audioQuality'] as String?,
    extensionData: json['extensionData'] is Map ? Map<String, dynamic>.from(json['extensionData']) : null,
  );

  static const unknownArtist = 'Unknown artist';

  /// The artists in one artist line, "Kobo Kanaeru, Takanashi Kiara" → both: split at commas and semicolons (how
  /// YouTube Music and most taggers join them), each once, in order. Empty for no artist.
  static List<String> splitArtists(String line) {
    if (line == unknownArtist) return const [];
    final out = <String>[];
    for (final part in line.split(RegExp(r'[,;]'))) {
      final name = part.trim();
      if (name.isNotEmpty && !out.contains(name)) out.add(name);
    }
    return out;
  }

  /// Each artist of this song (see [splitArtists]).
  List<String> get artists => splitArtists(artist);

  final String id;

  /// Format and source quality read from the file header or the selected stream.
  final String? audioQuality;
  final Uri uri;
  final String title;
  final String artist;
  final String? album;
  final Duration? duration;
  final int? trackNumber;
  final int? discNumber;

  /// Where this song begins and ends inside a longer file (cue sheet tracks).
  final Duration? start;
  final Duration? end;
  final int addedAt;

  /// Whether embedded tags have been read (so we don't re-scan every launch).
  final bool tagged;

  /// Page the audio was downloaded from (YouTube imports); null for local files.
  final String? sourceUrl;

  /// Set for streamed YouTube songs (not downloaded); playback resolves the audio on demand.
  final String? videoId;

  /// YouTube song fulfilled by a download from another provider. Does not make a local file remote.
  final String? downloadYoutubeId;

  /// Cover art fetched over the network (streamed songs have no file to read it from).
  final String? artworkUrl;

  /// The YouTube Music artist channel (`UC…`) of a streamed song, or the SoundCloud uploader's user id of a
  /// SoundCloud track, when known.
  final String? artistId;
  final Map<String, dynamic>? extensionData;
  String? get extensionId => uri.scheme == 'spotiflac' ? uri.host : null;

  /// A YouTube Music song that streams (it has a [videoId]). SoundCloud tracks stream too but aren't this:
  /// everything YouTube-only (radio, likes, downloads, the music video) keys off it. See [streams].
  bool get isRemote => videoId != null;

  /// SoundCloud's track id, for a SoundCloud track.
  String? get soundcloudId => id.startsWith(soundcloudPrefix) ? id.substring(soundcloudPrefix.length) : null;

  /// Spotify's track id, for a Spotify track.
  String? get spotifyId => id.startsWith(spotifyPrefix) ? id.substring(spotifyPrefix.length) : null;

  /// Played over the internet from a music service (YouTube Music or SoundCloud), not from a file here.
  String? get monochromeId => id.startsWith('monochrome:') ? id.substring('monochrome:'.length) : null;

  /// Stable service key shared by a stream and its downloaded file.
  String? get offlineId {
    if (extensionId != null) return id;
    if (monochromeId != null) return id;
    if (youtubeId != null) return youtubeId;
    return downloadSourceId;
  }

  /// Provider identity retained alongside a YouTube-origin download association.
  String? get downloadSourceId {
    final url = Uri.tryParse(sourceUrl ?? '');
    if (url?.scheme == 'spotiflac' && url!.pathSegments.length == 1) {
      return 'sflx:${url.host}:${Uri.encodeComponent(url.pathSegments.single)}';
    }
    if (url != null &&
        const {'monochrome.st', 'monochrome.tf'}.contains(url.host) &&
        url.pathSegments.length == 2 &&
        url.pathSegments.first == 'track') {
      return 'monochrome:${url.pathSegments.last}';
    }
    return null;
  }

  bool get streams =>
      isRemote || soundcloudId != null || monochromeId != null || extensionId != null || spotifyId != null;

  /// Where this song comes from, for the mark beside it.
  TrackSource get source => extensionId != null
      ? TrackSource.extension
      : monochromeId != null
      ? TrackSource.monochrome
      : soundcloudId != null
      ? TrackSource.soundcloud
      : spotifyId != null
      ? TrackSource.spotify
      : isRemote
      ? TrackSource.youtubeMusic
      : TrackSource.device;

  /// The YouTube video this song is: a streamed song's own id, or the one a download remembers in
  /// [sourceUrl]. Null for a file that never came from YouTube, which a YouTube Music playlist can't hold.
  String? get youtubeId => videoId ?? downloadYoutubeId ?? youtubeVideoIdOf(sourceUrl);

  /// This song as YouTube Music streams it (for a YouTube Music playlist), or null without a [youtubeId].
  Track? get onYoutube => isRemote
      ? this
      : switch (youtubeId) {
          final id? => Track.youtube(videoId: id, title: title, artist: artist, duration: duration, artistId: artistId),
          null => null,
        };

  /// A file on this device downloaded by Riflay from YouTube (it remembers the video in [sourceUrl]).
  bool get isDownload => sourceUrl != null && path != null && !isRemote;

  /// One song out of a whole-album file, described by a cue sheet.
  bool get isCueTrack => start != null;

  /// Local filesystem path, when the URI points at one (not Android content URIs).
  String? get path => uri.scheme == 'file' ? uri.toFilePath() : null;

  /// Groups tracks of the same album together, even across differently-tagged artists.
  String? get albumKey => album == null ? null : '${album!.toLowerCase()}|${artist.toLowerCase()}';

  Track copyWith({
    Uri? uri,
    String? title,
    String? artist,
    String? album,
    Duration? duration,
    int? trackNumber,
    int? discNumber,
    bool? tagged,
    String? downloadYoutubeId,
    String? audioQuality,
  }) => Track(
    id: id,
    uri: uri ?? this.uri,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    album: album ?? this.album,
    duration: duration ?? this.duration,
    trackNumber: trackNumber ?? this.trackNumber,
    discNumber: discNumber ?? this.discNumber,
    start: start,
    end: end,
    addedAt: addedAt,
    tagged: tagged ?? this.tagged,
    sourceUrl: sourceUrl,
    videoId: videoId,
    artworkUrl: artworkUrl,
    artistId: artistId,
    downloadYoutubeId: downloadYoutubeId ?? this.downloadYoutubeId,
    audioQuality: audioQuality ?? this.audioQuality,
    extensionData: extensionData,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'uri': uri.toString(),
    'title': title,
    'artist': artist,
    'album': album,
    'durationMs': duration?.inMilliseconds,
    'trackNumber': trackNumber,
    'discNumber': discNumber,
    'startMs': start?.inMilliseconds,
    'endMs': end?.inMilliseconds,
    'addedAt': addedAt,
    'tagged': tagged,
    'sourceUrl': sourceUrl,
    'videoId': videoId,
    if (downloadYoutubeId != null) 'downloadYoutubeId': downloadYoutubeId,
    if (audioQuality != null) 'audioQuality': audioQuality,
    'artworkUrl': artworkUrl,
    if (artistId != null) 'artistId': artistId,
    if (extensionData != null) 'extensionData': extensionData,
  };

  /// Everything libmpv / FFmpeg decodes. DSD (dsf/dff) plays as high-rate PCM.
  static const audioExtensions = {
    'mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'oga', 'opus', 'webm', 'wma', 'aiff', 'aif', 'aifc', 'alac', //
    'wv', 'ape', 'tta', 'mka', 'caf', 'w64', 'dsf', 'dff', 'mpc', 'm4b',
  };

  static bool isAudioPath(String path) {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    return audioExtensions.contains(ext);
  }
}

/// Where a song comes from.
enum TrackSource { device, youtubeMusic, soundcloud, monochrome, extension, spotify }

/// Album order: disc, then track number, title as a tiebreak for untagged files.
int compareAlbumOrder(Track a, Track b) {
  final byDisc = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
  if (byDisc != 0) return byDisc;
  final byNumber = (a.trackNumber ?? 1 << 20).compareTo(b.trackNumber ?? 1 << 20);
  return byNumber != 0 ? byNumber : a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

/// A group of tracks shown as a card / page (album, artist or the whole library).
class Collection {
  const Collection({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.tracks,
    this.id,
    this.picture,
    this.coverKey,
    this.artistVideos = const [],
  });

  final CollectionKind kind;

  /// The Riflay playlist's id (kind [CollectionKind.playlist]).
  final String? id;
  final String title;
  final String subtitle;
  final List<Track> tracks;

  /// Confirmed videos from the artist's provider, separate from the song list.
  final List<Track> artistVideos;

  /// A picture of its own (an artist's photo), drawn instead of its first song's cover.
  final Track? picture;

  /// Where a cover the person picked lives (see `PlaylistCovers`); null for collections that can't have one.
  final String? coverKey;

  Track? get cover => picture ?? (tracks.isEmpty ? null : tracks.first);

  Collection withTracks(List<Track> ordered) => Collection(
    kind: kind,
    title: title,
    subtitle: subtitle,
    tracks: ordered,
    id: id,
    picture: picture,
    coverKey: coverKey,
    artistVideos: artistVideos,
  );

  /// The same, with [p] as its picture.
  Collection withPicture(Track p) => Collection(
    kind: kind,
    title: title,
    subtitle: subtitle,
    tracks: tracks,
    id: id,
    picture: p,
    coverKey: coverKey,
    artistVideos: artistVideos,
  );
}

/// Splits songs by their available credits. Missing credits stay in the general song list.
({List<Track> solo, List<Track> collaborations}) artistSongSections(String artist, Iterable<Track> tracks) {
  final who = artist.trim().toLowerCase();
  final solo = <Track>[];
  final collaborations = <Track>[];
  for (final track in tracks) {
    final names = track.artists.map((name) => name.toLowerCase()).toSet();
    if (!names.contains(who)) continue;
    (names.length == 1 ? solo : collaborations).add(track);
  }
  return (solo: solo, collaborations: collaborations);
}

/// [Collection.id] of YouTube Music's "Liked music".
const likedMusicId = 'LM';

enum CollectionKind {
  allSongs,
  playlist,
  album,
  youtube,
  remote,

  /// A profile on a streaming service (a SoundCloud uploader's page), shown like a playlist of their tracks.
  remoteArtist,

  /// A built-in list worked out from the library and the listening history (Most played…); not editable.
  smart,

  /// A playback session's radio snapshot, outside the saved library playlists.
  radio,

  /// A music folder the person added (Library › Local): the songs under it. [Collection.id] is its path.
  folder,
  artist;

  String get label => switch (this) {
    allSongs => tr.playlist,
    playlist => tr.playlist,
    album => tr.album,
    youtube => tr.playlist,
    remote => tr.playlist,
    remoteArtist => tr.artist,
    smart => tr.playlist,
    radio => tr.temporaryRadio,
    folder => tr.folder,
    artist => tr.artist,
  };
}

/// A playlist made in Riflay, kept on this device. It can mix songs from
/// the library (play offline) and YouTube Music songs (stream online).
class UserPlaylist {
  const UserPlaylist({required this.id, required this.name, required this.tracks, required this.createdAt});

  factory UserPlaylist.fromJson(Map<String, dynamic> j) => UserPlaylist(
    id: j['id'] as String,
    name: j['name'] as String,
    tracks: [for (final t in j['tracks'] as List) Track.fromJson((t as Map).cast())],
    createdAt: j['createdAt'] as int? ?? 0,
  );

  final String id;
  final String name;
  final List<Track> tracks;
  final int createdAt;

  UserPlaylist copyWith({String? name, List<Track>? tracks}) =>
      UserPlaylist(id: id, name: name ?? this.name, tracks: tracks ?? this.tracks, createdAt: createdAt);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'tracks': [for (final t in tracks) t.toJson()],
    'createdAt': createdAt,
  };
}

/// The video id in a YouTube link: `watch?v=<id>` or `youtu.be/<id>`.
String? youtubeVideoIdOf(String? url) {
  final u = url == null ? null : Uri.tryParse(url);
  if (u == null) return null;
  return u.queryParameters['v'] ?? (u.host.endsWith('youtu.be') ? u.pathSegments.firstOrNull : null);
}
