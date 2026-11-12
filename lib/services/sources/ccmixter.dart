import 'dart:convert';

import '../../models/track.dart';
import 'song_source.dart';

/// ccMixter (ccmixter.org): originals and remixes under Creative Commons licenses, uploaded by the people who
/// made them. Its query API needs no account or key. An upload carries several files: the full mix in FLAC when
/// there is one, else its MP3. Sample packs, a cappellas and stems are left out: they are parts of songs.
class CcMixter extends SongSource {
  CcMixter({super.client});

  static final instance = CcMixter();
  static const host = 'ccmixter.org';

  @override
  String get name => 'ccMixter';

  @override
  String get prefix => 'ccmixter:';

  static const _parts = {'sample', 'samples', 'stem', 'stems', 'acappella', 'a_cappella'};

  @override
  Future<List<Track>> search(String query, {int limit = 12}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final n = limit.clamp(1, 50);
    final url = Uri.https(host, '/api/query', {'f': 'json', 'search': q, 'limit': '${n * 2}'});
    final data = jsonDecode((await get(url)).body);
    final items = data is List ? data : const [];
    return [for (final item in items.whereType<Map>()) ?parse(item)].take(n).toList();
  }

  Track? parse(Map item) {
    final id = '${item['upload_id'] ?? ''}';
    final title = SongSource.text(item['upload_name'])?.replaceFirst(RegExp(r'[,;]+$'), '');
    if (!RegExp(r'^\d+$').hasMatch(id) || title == null || title.isEmpty) return null;
    final tags = '${item['upload_tags'] ?? ''}'.toLowerCase().split(',');
    if (tags.any(_parts.contains)) return null;
    final files = (item['files'] as List? ?? const []).whereType<Map>().toList();
    Map? pick(String ext) {
      for (final f in files) {
        final info = f['file_format_info'] is Map ? f['file_format_info'] as Map : const {};
        // The full mix is the file named after its format ("flac", "mp3"); stems carry their part's name.
        final nick = '${f['file_nicname'] ?? ''}'.toLowerCase();
        if (info['media-type'] == 'audio' && info['default-ext'] == ext && nick == ext) return f;
      }
      return null;
    }

    final file = pick('flac') ?? pick('mp3');
    final url = SongSource.webUrl(file?['download_url']);
    if (file == null || url == null) return null;
    final info = file['file_format_info'] as Map;
    return Track(
      id: '$prefix$id',
      uri: Uri.parse(url),
      title: title,
      artist: SongSource.text(item['user_real_name']) ?? SongSource.text(item['user_name']) ?? Track.unknownArtist,
      duration: parseLength('${info['ps'] ?? ''}'),
      tagged: true,
    );
  }

  /// "2:03" or "1:02:03".
  static Duration? parseLength(String s) {
    if (!RegExp(r'^\d+(:\d{1,2}){1,2}$').hasMatch(s)) return null;
    final seconds = s.split(':').map(int.parse).fold(0, (a, b) => a * 60 + b);
    return seconds > 0 ? Duration(seconds: seconds) : null;
  }
}
