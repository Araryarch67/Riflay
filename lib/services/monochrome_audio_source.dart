// ignore_for_file: experimental_member_use
import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;

import 'monochrome.dart';

/// Resolves expiring HiFi manifests only when the queued song is requested.
class MonochromeAudioSource extends StreamAudioSource {
  MonochromeAudioSource(
    this.trackId, {
    Monochrome? client,
    super.tag,
    this.retryDelays = const [Duration(milliseconds: 300), Duration(seconds: 1)],
    this.resolveTimeout = const Duration(seconds: 10),
  }) : client = client ?? Monochrome.instance;
  final String trackId;
  final Monochrome client;
  final List<Duration> retryDelays;
  final Duration resolveTimeout;
  Future<String>? _manifest;

  Future<String> _resolve() async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await client.manifest(trackId).timeout(resolveTimeout);
      } catch (error) {
        final transient =
            error is SocketException ||
            error is TimeoutException ||
            error is HttpException ||
            error is http.ClientException ||
            error is FormatException;
        final permanent =
            error is http.ClientException && RegExp(r'HTTP (400|401|403|404|410)\b').hasMatch(error.message);
        if (!transient || permanent || attempt >= retryDelays.length) rethrow;
        await Future<void>.delayed(retryDelays[attempt]);
      }
    }
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    // All proxy byte-range requests must see one immutable manifest. A player
    // retry constructs a fresh source and resolves a fresh expiring URL.
    final manifest = await (_manifest ??= _resolve().catchError((Object error) {
      _manifest = null;
      throw error;
    }));
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
