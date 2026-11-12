import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/track.dart';

/// One of Radio Paradise's channels.
@immutable
class RadioParadiseChannel {
  const RadioParadiseChannel(this.number, this.name, this.stream);

  /// The channel's number in Radio Paradise's API.
  final int number;
  final String name;

  /// Its FLAC stream's path on `stream.radioparadise.com`.
  final String stream;

  Track get track => trackWith();

  /// The channel as a song to play, with [artworkUrl] (the cover of what plays now) when known.
  Track trackWith({String? artworkUrl}) => Track(
    id: '${RadioParadise.prefix}$stream',
    uri: Uri.https('stream.radioparadise.com', '/$stream'),
    title: 'Radio Paradise · $name',
    artist: 'Radio Paradise',
    // No album: the four channels would share one cover (covers are remembered by album).
    sourceUrl: 'https://radioparadise.com',
    artworkUrl: artworkUrl,
  );
}

/// What a channel plays now.
typedef RadioParadiseSong = ({String artist, String title, String? album, String? cover});

/// Radio Paradise (radioparadise.com): listener-supported, commercial-free radio that streams every channel in
/// FLAC (CD quality, 16-bit / 44.1 kHz) for anyone, from its own servers. Its public API says what is playing.
abstract final class RadioParadise {
  /// Ids of its channels start with this.
  static const prefix = 'rp:';

  static const channels = [
    RadioParadiseChannel(0, 'Main Mix', 'flac'),
    RadioParadiseChannel(1, 'Mellow Mix', 'mellow-flac'),
    RadioParadiseChannel(2, 'Rock Mix', 'rock-flac'),
    RadioParadiseChannel(3, 'Global Mix', 'global-flac'),
  ];

  /// The song on [channel] now, or null when the API doesn't answer.
  static Future<RadioParadiseSong?> nowPlaying(RadioParadiseChannel channel, {http.Client? client}) async {
    try {
      final url = Uri.https('api.radioparadise.com', '/api/now_playing', {'chan': '${channel.number}'});
      final r = await (client?.get ?? http.get)(url).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      return parseNowPlaying(r.body);
    } catch (e) {
      debugPrint('Radio Paradise now playing: $e');
      return null;
    }
  }

  @visibleForTesting
  static RadioParadiseSong? parseNowPlaying(String body) {
    final j = jsonDecode(body) as Map;
    final title = '${j['title'] ?? ''}'.trim();
    if (title.isEmpty) return null;
    return (
      artist: '${j['artist'] ?? ''}'.trim(),
      title: title,
      album: (j['album'] as String?)?.trim(),
      cover: (j['cover_med'] ?? j['cover']) as String?,
    );
  }
}
