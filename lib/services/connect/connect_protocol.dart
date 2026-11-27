import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import '../../models/track.dart';
import '../listen_together/protocol.dart' show SharedTrack;

/// Riflay Connect: a controller (any Riflay) sends commands to a desktop, which plays from its own files and
/// streams and answers with its state. No audio, and nothing that names a file or an account, ever travels.
///
/// Every message is one JSON object with a `t` (type). Unknown types are ignored so later versions can add some.
const connectProtocolVersion = 1;

/// Queue entries in a [ConnectState]: a long queue is cut so the message stays small for a public broker.
const connectQueueLimit = 50;

enum ConnectRepeat { off, all, one }

/// A song as a controller sees it. [ref] is only a label to tell queue rows apart: a hash, never the local path
/// or id the desktop uses.
class ConnectTrack {
  const ConnectTrack({required this.ref, required this.title, required this.artist, this.durationMs, this.artworkUrl});

  final String ref;
  final String title;
  final String artist;
  final int? durationMs;

  /// An https address only: a local cover is a file on the desktop and stays there.
  final String? artworkUrl;

  static ConnectTrack of(Track t) {
    final art = t.artworkUrl;
    return ConnectTrack(
      ref: connectRef(t.id),
      title: _clip(t.title, 200),
      artist: _clip(t.artist, 200),
      durationMs: t.duration?.inMilliseconds,
      artworkUrl: art != null && art.startsWith('https://') ? art : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'ref': ref,
    'title': title,
    'artist': artist,
    'durationMs': ?durationMs,
    'artworkUrl': ?artworkUrl,
  };

  static ConnectTrack? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final ref = json['ref'], title = json['title'], artist = json['artist'], ms = json['durationMs'];
    final art = json['artworkUrl'];
    if (ref is! String || title is! String || artist is! String) return null;
    return ConnectTrack(
      ref: ref,
      title: title,
      artist: artist,
      durationMs: ms is int ? ms : null,
      // Whatever the other side says, only a web address is ever loaded.
      artworkUrl: art is String && art.startsWith('https://') ? art : null,
    );
  }
}

/// 16 hex characters from the id: enough to tell rows apart, and no way back to a path.
String connectRef(String id) =>
    crypto.sha256.convert(utf8.encode('riflay-connect-ref/$id')).toString().substring(0, 16);

String _clip(String s, int max) => s.length <= max ? s : s.substring(0, max);

/// What the desktop reports. [atMs] is the desktop's clock when it was made.
class ConnectState {
  const ConnectState({
    required this.playing,
    required this.positionMs,
    required this.volume,
    required this.shuffle,
    required this.repeat,
    required this.queue,
    required this.queueIndex,
    required this.atMs,
    this.track,
    this.durationMs,
    this.canSetVolume = true,
  });

  final bool playing;
  final ConnectTrack? track;
  final int positionMs;
  final int? durationMs;
  final double volume;
  final bool canSetVolume;
  final bool shuffle;
  final ConnectRepeat repeat;
  final List<ConnectTrack> queue;
  final int? queueIndex;
  final int atMs;

  /// Where the song is at [nowMs] on the receiver's clock, given the state arrived at [receivedAtMs]: counted on
  /// from the report while it plays, so the position moves between messages.
  Duration positionAt(int nowMs, int receivedAtMs) {
    final ms = positionMs + (playing ? nowMs - receivedAtMs : 0);
    final end = durationMs;
    return Duration(milliseconds: end == null ? ms : ms.clamp(0, end));
  }

  Map<String, dynamic> toJson() => {
    't': 'state',
    'playing': playing,
    'track': track?.toJson(),
    'pos': positionMs,
    'dur': durationMs,
    'vol': volume,
    'canVol': canSetVolume,
    'shuffle': shuffle,
    'repeat': repeat.name,
    'queue': [for (final t in queue.take(connectQueueLimit)) t.toJson()],
    'idx': queueIndex,
    'at': atMs,
  };

  static ConnectState? fromJson(Map<String, dynamic> j) {
    final playing = j['playing'], pos = j['pos'], vol = j['vol'], shuffle = j['shuffle'], at = j['at'];
    if (playing is! bool || pos is! int || vol is! num || shuffle is! bool || at is! int) return null;
    final queue = j['queue'];
    return ConnectState(
      playing: playing,
      track: ConnectTrack.fromJson(j['track']),
      positionMs: pos,
      durationMs: j['dur'] is int ? j['dur'] as int : null,
      volume: vol.toDouble().clamp(0.0, 1.0),
      canSetVolume: j['canVol'] != false,
      shuffle: shuffle,
      repeat: ConnectRepeat.values.firstWhere((r) => r.name == j['repeat'], orElse: () => ConnectRepeat.off),
      queue: queue is List ? [for (final t in queue.take(connectQueueLimit)) ?ConnectTrack.fromJson(t)] : const [],
      queueIndex: j['idx'] is int ? j['idx'] as int : null,
      atMs: at,
    );
  }
}

/// What a controller asks for. Every command is applied through the desktop's `PlayerController`.
sealed class ConnectCommand {
  const ConnectCommand();

  Map<String, dynamic> toJson();

  /// Null for anything that isn't a command we know, or has a value out of range.
  static ConnectCommand? fromJson(Map<String, dynamic> j) {
    switch (j['t']) {
      case 'sync':
        return const ConnectSync();
      case 'play':
        return const ConnectPlay();
      case 'pause':
        return const ConnectPause();
      case 'next':
        return const ConnectNext();
      case 'prev':
        return const ConnectPrevious();
      case 'seek':
        final ms = j['ms'];
        return ms is int && ms >= 0 ? ConnectSeek(ms) : null;
      case 'vol':
        final v = j['v'];
        return v is num && v >= 0 && v <= 1 ? ConnectVolume(v.toDouble()) : null;
      case 'shuffle':
        final on = j['on'];
        return on is bool ? ConnectShuffle(on) : null;
      case 'repeat':
        final mode = ConnectRepeat.values.where((r) => r.name == j['mode']);
        return mode.isEmpty ? null : ConnectSetRepeat(mode.first);
      case 'add':
        final track = SharedTrack.fromJson(j['track']);
        // A YouTube id is 11 characters; anything else is not something to put in a queue.
        return track != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(track.videoId) ? ConnectAdd(track) : null;
      default:
        return null;
    }
  }
}

/// "Tell me the state": the first thing a controller sends, and its keep-alive.
class ConnectSync extends ConnectCommand {
  const ConnectSync();
  @override
  Map<String, dynamic> toJson() => {'t': 'sync'};
}

class ConnectPlay extends ConnectCommand {
  const ConnectPlay();
  @override
  Map<String, dynamic> toJson() => {'t': 'play'};
}

class ConnectPause extends ConnectCommand {
  const ConnectPause();
  @override
  Map<String, dynamic> toJson() => {'t': 'pause'};
}

class ConnectNext extends ConnectCommand {
  const ConnectNext();
  @override
  Map<String, dynamic> toJson() => {'t': 'next'};
}

class ConnectPrevious extends ConnectCommand {
  const ConnectPrevious();
  @override
  Map<String, dynamic> toJson() => {'t': 'prev'};
}

class ConnectSeek extends ConnectCommand {
  const ConnectSeek(this.ms);
  final int ms;
  @override
  Map<String, dynamic> toJson() => {'t': 'seek', 'ms': ms};
}

class ConnectVolume extends ConnectCommand {
  const ConnectVolume(this.level);

  /// 0 to 1.
  final double level;
  @override
  Map<String, dynamic> toJson() => {'t': 'vol', 'v': level};
}

class ConnectShuffle extends ConnectCommand {
  const ConnectShuffle(this.on);
  final bool on;
  @override
  Map<String, dynamic> toJson() => {'t': 'shuffle', 'on': on};
}

class ConnectSetRepeat extends ConnectCommand {
  const ConnectSetRepeat(this.mode);
  final ConnectRepeat mode;
  @override
  Map<String, dynamic> toJson() => {'t': 'repeat', 'mode': mode.name};
}

/// Only a YouTube song can be added from another device: a song from someone's own files exists on that device
/// only, and sharing collections is a later stage.
class ConnectAdd extends ConnectCommand {
  const ConnectAdd(this.track);
  final SharedTrack track;
  @override
  Map<String, dynamic> toJson() => {'t': 'add', 'track': track.toJson()};
}
