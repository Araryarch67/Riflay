import 'dart:convert';

import '../../models/track.dart';
import 'song_source.dart';

/// Audius (audius.co): artists upload their own songs. Its public API needs no account or key, only an app name.
/// A song plays from `/v1/tracks/<id>/stream`, which redirects to the node holding the file (MP3, 320 kbps); mpv
/// follows the redirect and seeks with range requests. Songs the artist gated (paid, followers only), deleted ones
/// and those of deactivated accounts are left out.
class Audius extends SongSource {
  Audius({super.client});

  static final instance = Audius();
  static const host = 'api.audius.co';
  static const appName = 'Riflay';

  @override
  String get name => 'Audius';

  @override
  String get prefix => 'audius:';

  @override
  Future<List<Track>> search(String query, {int limit = 12}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final n = limit.clamp(1, 50);
    // Ask for more: some of the matches can't be streamed.
    final url = Uri.https(host, '/v1/tracks/search', {'query': q, 'limit': '${n * 2}', 'app_name': appName});
    final data = jsonDecode((await get(url)).body);
    final items = data is Map && data['data'] is List ? data['data'] as List : const [];
    return [for (final item in items.whereType<Map>()) ?parse(item)].take(n).toList();
  }

  Track? parse(Map item) {
    final id = '${item['id'] ?? ''}';
    final title = SongSource.text(item['title']);
    final user = item['user'] is Map ? item['user'] as Map : const {};
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(id) ||
        title == null ||
        item['is_streamable'] != true ||
        item['is_delete'] == true ||
        item['is_stream_gated'] == true ||
        user['is_deactivated'] == true) {
      return null;
    }
    final seconds = item['duration'];
    final artwork = item['artwork'] is Map ? item['artwork'] as Map : const {};
    return Track(
      id: '$prefix$id',
      uri: Uri.https(host, '/v1/tracks/$id/stream', {'app_name': appName}),
      title: title,
      artist: SongSource.text(user['name']) ?? SongSource.text(user['handle']) ?? Track.unknownArtist,
      duration: seconds is num && seconds > 0 ? Duration(milliseconds: (seconds * 1000).round()) : null,
      artworkUrl: SongSource.webUrl(artwork['480x480']) ?? SongSource.webUrl(artwork['1000x1000']),
      tagged: true,
    );
  }
}
