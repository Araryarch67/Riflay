// StreamAudioSource/Response are just_audio's documented way to feed custom byte streams;
// they are flagged experimental but stable across 0.9-0.10.
// ignore_for_file: experimental_member_use

import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

import 'spotify_bridge.dart';

/// Plays a Spotify track: the bridge's Ogg Vorbis file for it, passed on to mpv through just_audio's loopback
/// server, ranges included, so seeking works. The bridge's own address is only known once it has started and
/// signed in, which a queued song can't wait for; that happens here, when mpv asks.
class SpotifyAudioSource extends StreamAudioSource {
  SpotifyAudioSource(this.trackId, {SpotifyBridge? bridge, http.Client? client, super.tag})
    : bridge = bridge ?? SpotifyBridge.instance,
      _client = client ?? _shared;

  final String trackId;
  final SpotifyBridge bridge;
  final http.Client _client;

  static final _shared = http.Client();

  Future<http.StreamedResponse> _get(int? start, int? end) async {
    final request = http.Request('GET', await bridge.streamUri(trackId));
    // just_audio's end is exclusive; a Range header's is inclusive.
    if (start != null || end != null) {
      request.headers['range'] = 'bytes=${start ?? 0}-${end == null ? '' : end - 1}';
    }
    return _client.send(request);
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    var response = await _get(start, end);
    if (response.statusCode == 401) {
      // The bridge's session ran out and its kept credentials didn't bring it back: a new token, once.
      await response.stream.drain<void>();
      await bridge.signIn(fresh: true);
      response = await _get(start, end);
    }
    if (response.statusCode != 200 && response.statusCode != 206) {
      await response.stream.drain<void>();
      throw SpotifyBridgeError('HTTP ${response.statusCode}');
    }
    final length = response.contentLength ?? 0;
    return StreamAudioResponse(
      sourceLength: totalOf(response.headers['content-range']) ?? (start ?? 0) + length,
      contentLength: length,
      offset: start ?? 0,
      contentType: 'audio/ogg',
      stream: response.stream,
    );
  }

  /// The whole file's length in a `Content-Range: bytes a-b/total`.
  static int? totalOf(String? contentRange) {
    final total = contentRange?.split('/').lastOrNull;
    return total == null ? null : int.tryParse(total.trim());
  }
}
