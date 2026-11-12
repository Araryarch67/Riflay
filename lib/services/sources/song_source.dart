import 'package:http/http.dart' as http;

import '../../models/track.dart';

/// An optional place search's "All" also looks for songs (Settings › Accounts & services › Music sources), each
/// one where artists share their own music. A song's `uri` is the file or stream mpv plays, so nothing has to
/// resolve it later.
abstract class SongSource {
  SongSource({this.client});

  /// Tests answer for the service.
  final http.Client? client;

  /// The service's name, as shown on the shelf and in errors.
  String get name;

  /// Ids of songs from here start with this.
  String get prefix;

  /// False when this build can't reach the service (Jamendo without a client id): its switch is hidden.
  bool get available => true;

  /// Up to [limit] songs matching [query]. Throws when the service can't be reached or refuses, so a failure is
  /// told apart from no matches.
  Future<List<Track>> search(String query, {int limit = 12});

  Future<http.Response> get(Uri url) async {
    final response = await (client?.get ?? http.get)(
      url,
      headers: const {'Accept': 'application/json', 'User-Agent': 'Riflay'},
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw http.ClientException('$name search: HTTP ${response.statusCode}', url);
    }
    return response;
  }

  /// [value] when it is a web address mpv or the cover loader can open.
  static String? webUrl(Object? value) {
    final uri = value is String ? Uri.tryParse(value) : null;
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty
        ? uri.toString()
        : null;
  }

  static String? text(Object? value) => value is String && value.trim().isNotEmpty ? value.trim() : null;
}
