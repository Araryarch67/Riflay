// StreamAudioSource/Response are just_audio's documented way to feed custom byte streams;
// they are flagged experimental but stable across 0.9-0.10.
// ignore_for_file: experimental_member_use

import 'dart:convert';

import 'package:just_audio/just_audio.dart';

import 'soundcloud.dart';

/// Plays a SoundCloud track: just_audio's loopback server hands mpv the track's HLS playlist, looked up when mpv
/// asks for it (SoundCloud signs the playlist's address for a few minutes only, so a queued song can't carry it).
/// mpv then reads the segments from SoundCloud itself, seeking included. The playlist goes out as HLS by its type:
/// FFmpeg takes an `#EXTM3U` from an address without `.m3u8` only with that type.
class SoundcloudAudioSource extends StreamAudioSource {
  SoundcloudAudioSource(this.trackId, {SoundcloudClient? client, super.tag})
    : client = client ?? SoundcloudClient.instance;

  final String trackId;
  final SoundcloudClient client;

  static const hlsType = 'application/vnd.apple.mpegurl';

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final bytes = utf8.encode(await client.playlistFor(trackId));
    final from = (start ?? 0).clamp(0, bytes.length);
    final to = (end ?? bytes.length).clamp(from, bytes.length);
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: to - from,
      offset: from,
      contentType: hlsType,
      stream: Stream.value(bytes.sublist(from, to)),
    );
  }
}
