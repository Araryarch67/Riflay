// ignore_for_file: experimental_member_use
import 'dart:convert';

import 'package:just_audio/just_audio.dart';

import '../models/track.dart';
import 'spotiflac.dart';

/// The extension resolves a fresh stream URL only when the player requests it.
class SpotiflacAudioSource extends StreamAudioSource {
  SpotiflacAudioSource(this.track, {Spotiflac? engine}) : engine = engine ?? Spotiflac.instance, super(tag: track);
  final Track track;
  final Spotiflac engine;
  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final result = await engine.stream(track);
    final url = Uri.tryParse(result['url']?.toString() ?? '');
    if (url == null || !const {'https', 'http'}.contains(url.scheme) || url.host.isEmpty) throw const SpotiflacError();
    final bytes = utf8.encode('#EXTM3U\n#EXTINF:-1,\n$url\n#EXT-X-ENDLIST\n');
    final from = (start ?? 0).clamp(0, bytes.length);
    final to = (end ?? bytes.length).clamp(from, bytes.length);
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: to - from,
      offset: from,
      contentType: 'application/vnd.apple.mpegurl',
      stream: Stream.value(bytes.sublist(from, to)),
    );
  }
}
