// ignore_for_file: experimental_member_use
import 'dart:convert';

import 'package:just_audio/just_audio.dart';

import 'monochrome.dart';

/// Resolves expiring HiFi manifests only when the queued song is requested.
class MonochromeAudioSource extends StreamAudioSource {
  MonochromeAudioSource(this.trackId, {Monochrome? client, super.tag}) : client = client ?? Monochrome.instance;
  final String trackId;
  final Monochrome client;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final manifest = await client.manifest(trackId);
    final dash = manifest.trimLeft().startsWith('<');
    final bytes = utf8.encode(dash ? manifest : '#EXTM3U\n#EXTINF:-1,\n$manifest\n#EXT-X-ENDLIST\n');
    final from = (start ?? 0).clamp(0, bytes.length);
    final to = (end ?? bytes.length).clamp(from, bytes.length);
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: to - from,
      offset: from,
      contentType: dash ? 'application/dash+xml' : 'application/vnd.apple.mpegurl',
      stream: Stream.value(bytes.sublist(from, to)),
    );
  }
}
