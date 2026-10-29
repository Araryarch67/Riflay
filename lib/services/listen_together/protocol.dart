import 'dart:convert';

import '../../models/track.dart';

/// Listen together: one person (the host) plays, everyone else (guests)
/// follows. The host is the only source of truth; guests never change the
/// shared playback themselves, they only ask ([Suggest]) when the host allows it.
///
/// Every message is one JSON object with a `t` (type) field, sent over a
/// [ListenTransport] (same Wi-Fi, or the internet through a relay). Unknown
/// types are ignored, so newer versions can add messages.
const listenProtocolVersion = 1;

/// A YouTube song as the host plays it. Only YouTube songs can be shared:
/// a song from someone's own files exists on their device only.
class SharedTrack {
  const SharedTrack({
    required this.videoId,
    required this.title,
    required this.artist,
    this.durationMs,
    this.artworkUrl,
  });

  final String videoId;
  final String title;
  final String artist;
  final int? durationMs;
  final String? artworkUrl;

  /// Null when [track] is not a YouTube song.
  static SharedTrack? of(Track track) => switch (track.videoId) {
    final id? => SharedTrack(
      videoId: id,
      title: track.title,
      artist: track.artist,
      durationMs: track.duration?.inMilliseconds,
      artworkUrl: track.artworkUrl,
    ),
    null => null,
  };

  Track toTrack() => Track.youtube(
    videoId: videoId,
    title: title,
    artist: artist,
    duration: durationMs == null ? null : Duration(milliseconds: durationMs!),
    artworkUrl: artworkUrl,
  );

  Map<String, dynamic> toJson() => {
    'videoId': videoId,
    'title': title,
    'artist': artist,
    'durationMs': ?durationMs,
    'artworkUrl': ?artworkUrl,
  };

  static SharedTrack? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['videoId'], title = json['title'], artist = json['artist'];
    if (id is! String || title is! String || artist is! String) return null;
    return SharedTrack(
      videoId: id,
      title: title,
      artist: artist,
      durationMs: json['durationMs'] as int?,
      artworkUrl: json['artworkUrl'] as String?,
    );
  }

  @override
  bool operator ==(Object other) => other is SharedTrack && other.videoId == videoId;

  @override
  int get hashCode => videoId.hashCode;
}

sealed class ListenMessage {
  const ListenMessage();

  String get type;
  Map<String, dynamic> body();

  String encode() => jsonEncode({'t': type, ...body()});

  /// Null for anything malformed or of an unknown type.
  static ListenMessage? decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, dynamic>) return null;
    try {
      return switch (json['t']) {
        'hello' => Hello(name: json['name'] as String, version: json['v'] as int, guestId: json['id'] as String),
        'welcome' => Welcome(
          hostName: json['name'] as String,
          guests: [for (final g in json['guests'] as List) g as String],
          suggestionsAllowed: json['suggest'] as bool,
        ),
        'state' => PlaybackState(
          track: SharedTrack.fromJson(json['track']),
          playing: json['playing'] as bool,
          positionMs: json['pos'] as int,
          sentAtMs: json['at'] as int,
          upNext: [for (final t in json['next'] as List? ?? const []) ?SharedTrack.fromJson(t)],
        ),
        'ping' => Ping(json['at'] as int),
        'pong' => Pong(pingAtMs: json['ping'] as int, hostAtMs: json['at'] as int),
        'suggest' => switch (SharedTrack.fromJson(json['track'])) {
          final track? => Suggest(track, from: json['from'] as String),
          null => null,
        },
        'guests' => Guests([for (final g in json['guests'] as List) g as String]),
        'bye' => Bye(reason: json['reason'] as String?),
        _ => null,
      };
    } on TypeError {
      return null;
    }
  }
}

/// Guest → host, first message: who is joining.
class Hello extends ListenMessage {
  const Hello({required this.name, required this.guestId, this.version = listenProtocolVersion});

  /// Shown to the host and other guests ("Ana joined").
  final String name;

  /// Random per guest app install; lets the host tell two guests of the same name apart.
  final String guestId;
  final int version;

  @override
  String get type => 'hello';

  @override
  Map<String, dynamic> body() => {'name': name, 'id': guestId, 'v': version};
}

/// Host → one guest, reply to [Hello].
class Welcome extends ListenMessage {
  const Welcome({required this.hostName, required this.guests, required this.suggestionsAllowed});

  final String hostName;
  final List<String> guests;
  final bool suggestionsAllowed;

  @override
  String get type => 'welcome';

  @override
  Map<String, dynamic> body() => {'name': hostName, 'guests': guests, 'suggest': suggestionsAllowed};
}

/// Host → everyone: what is playing and where. Sent on every change (song,
/// play/pause, seek) and every few seconds besides, so a guest that joins or
/// drifts catches up.
class PlaybackState extends ListenMessage {
  const PlaybackState({
    required this.track,
    required this.playing,
    required this.positionMs,
    required this.sentAtMs,
    this.upNext = const [],
  });

  /// Null when the host plays nothing shareable (nothing, or a song from their own files).
  final SharedTrack? track;
  final bool playing;

  /// The host's position when the message was made, at [sentAtMs] on the host's clock.
  final int positionMs;
  final int sentAtMs;

  /// The next few YouTube songs in the host's queue, for the guests' "Up next".
  final List<SharedTrack> upNext;

  /// Where the host is at [hostNowMs] (host clock), assuming it kept playing.
  int positionAt(int hostNowMs) => playing ? positionMs + (hostNowMs - sentAtMs) : positionMs;

  @override
  String get type => 'state';

  @override
  Map<String, dynamic> body() => {
    'track': track?.toJson(),
    'playing': playing,
    'pos': positionMs,
    'at': sentAtMs,
    'next': [for (final t in upNext) t.toJson()],
  };
}

/// Guest → host, to learn the clock offset; the host answers [Pong] at once.
class Ping extends ListenMessage {
  const Ping(this.atMs);

  /// The guest's clock when sent.
  final int atMs;

  @override
  String get type => 'ping';

  @override
  Map<String, dynamic> body() => {'at': atMs};
}

class Pong extends ListenMessage {
  const Pong({required this.pingAtMs, required this.hostAtMs});

  final int pingAtMs;
  final int hostAtMs;

  @override
  String get type => 'pong';

  @override
  Map<String, dynamic> body() => {'ping': pingAtMs, 'at': hostAtMs};
}

/// Guest → host: "play this next". Only when [Welcome.suggestionsAllowed].
class Suggest extends ListenMessage {
  const Suggest(this.track, {required this.from});

  final SharedTrack track;
  final String from;

  @override
  String get type => 'suggest';

  @override
  Map<String, dynamic> body() => {'track': track.toJson(), 'from': from};
}

/// Host → everyone: who is listening now.
class Guests extends ListenMessage {
  const Guests(this.names);

  final List<String> names;

  @override
  String get type => 'guests';

  @override
  Map<String, dynamic> body() => {'guests': names};
}

/// Either way: leaving. From the host it ends the session for everyone.
class Bye extends ListenMessage {
  const Bye({this.reason});

  final String? reason;

  @override
  String get type => 'bye';

  @override
  Map<String, dynamic> body() => {'reason': ?reason};
}
