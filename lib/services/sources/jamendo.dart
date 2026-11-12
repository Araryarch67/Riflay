import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/track.dart';
import '../../platform/host.dart';
import 'song_source.dart';

/// Jamendo (jamendo.com): independent artists releasing under Creative Commons licenses. Its API wants a client id,
/// free from devportal.jamendo.com, given to the build as `--dart-define=RIFLAY_JAMENDO_CLIENT_ID=…` (or, for a
/// run from source, the `RIFLAY_JAMENDO_CLIENT_ID` environment variable). Without one the source is hidden.
/// A song streams from the `audio` address the API returns (MP3, VBR around 200 kbps).
class Jamendo extends SongSource {
  Jamendo({super.client, this.clientIdOverride});

  static final instance = Jamendo();
  static const host = 'api.jamendo.com';
  static const _defined = String.fromEnvironment('RIFLAY_JAMENDO_CLIENT_ID');

  /// Tests give their own id instead of the build's.
  final String? clientIdOverride;

  String get clientId {
    if (clientIdOverride case final id?) return id;
    if (_defined.isNotEmpty) return _defined;
    return Host.environment['RIFLAY_JAMENDO_CLIENT_ID']?.trim() ?? '';
  }

  @override
  String get name => 'Jamendo';

  @override
  String get prefix => 'jamendo:';

  @override
  bool get available => clientId.isNotEmpty;

  @override
  Future<List<Track>> search(String query, {int limit = 12}) async {
    final q = query.trim();
    if (q.isEmpty || !available) return const [];
    final n = limit.clamp(1, 50);
    final url = Uri.https(host, '/v3.0/tracks/', {
      'client_id': clientId,
      'format': 'json',
      'limit': '$n',
      'search': q,
      'audioformat': 'mp32',
    });
    final data = jsonDecode((await get(url)).body);
    final headers = data is Map && data['headers'] is Map ? data['headers'] as Map : const {};
    if (headers['status'] != 'success') {
      throw http.ClientException('Jamendo search: ${headers['error_message'] ?? 'failed'}', url);
    }
    final items = data['results'] is List ? data['results'] as List : const [];
    return [for (final item in items.whereType<Map>()) ?parse(item)].take(n).toList();
  }

  Track? parse(Map item) {
    final id = '${item['id'] ?? ''}';
    final title = SongSource.text(item['name']);
    final audio = SongSource.webUrl(item['audio']);
    if (!RegExp(r'^\d+$').hasMatch(id) || title == null || audio == null) return null;
    final seconds = item['duration'];
    final duration = seconds is num ? seconds : num.tryParse('$seconds');
    return Track(
      id: '$prefix$id',
      uri: Uri.parse(audio),
      title: title,
      artist: SongSource.text(item['artist_name']) ?? Track.unknownArtist,
      album: SongSource.text(item['album_name']),
      duration: duration != null && duration > 0 ? Duration(seconds: duration.round()) : null,
      artworkUrl: SongSource.webUrl(item['image']) ?? SongSource.webUrl(item['album_image']),
      tagged: true,
    );
  }
}
