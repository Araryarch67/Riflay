import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/track.dart';
import 'ffmpeg.dart';
import 'metadata.dart';
import 'monochrome.dart';

/// Streams FLAC to disk, tags a private temporary file, then publishes it atomically.
class MonochromeDownload {
  static String jobId(Track t) => 'mono_${base64Url.encode(utf8.encode(t.monochromeId!)).replaceAll('=', '')}';

  static Future<Track> save(
    Track track,
    Directory directory, {
    http.Client? client,
    Monochrome? api,
    bool Function()? cancelled,
    void Function(int bytes, int? total)? progress,
    void Function()? finishing,
  }) async {
    if (track.monochromeId == null) throw const FormatException('Not a Monochrome track');
    final owned = client == null;
    final httpClient = client ?? http.Client();
    final id = track.monochromeId!;
    final parsed = MonochromeLink.parse(track.sourceUrl ?? '');
    if (parsed == null || parsed.kind != 'track' || parsed.id != id) {
      if (owned) httpClient.close();
      throw const FormatException('Invalid Monochrome download');
    }
    await directory.create(recursive: true);
    final work = await directory.createTemp('.monochrome-');
    final file = File(p.join(work.path, 'audio.flac'));
    void check() {
      if (cancelled?.call() ?? false) throw const HttpException('Download cancelled');
    }

    try {
      check();
      final nativeId = id.startsWith('tracks:track:') ? id.substring('tracks:track:'.length) : null;
      final manifest = nativeId != null
          ? '${Monochrome.tracksBase}/track/${Uri.encodeComponent(nativeId)}'
          : await (api ?? Monochrome.instance).manifest(id);
      if (manifest.trimLeft().startsWith('<')) {
        // Copy compressed FLAC packets from DASH without decoding or resampling.
        final mpd = await File(p.join(work.path, 'audio.mpd')).writeAsString(manifest);
        final process = await Process.start(await Ffmpeg.executable(), [
          '-nostdin',
          '-hide_banner',
          '-loglevel',
          'error',
          '-y',
          '-protocol_whitelist',
          'file,http,https,tcp,tls,crypto',
          '-i',
          mpd.path,
          '-map',
          '0:a:0',
          '-c:a',
          'copy',
          file.path,
        ]);
        final output = process.stdout.drain<void>();
        final errors = process.stderr.drain<void>();
        final timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
          if (cancelled?.call() ?? false) process.kill();
        });
        int code;
        try {
          code = await process.exitCode.timeout(
            const Duration(minutes: 30),
            onTimeout: () {
              process.kill();
              throw TimeoutException('Monochrome DASH download');
            },
          );
        } finally {
          timer.cancel();
        }
        await Future.wait([output, errors]);
        check();
        if (code != 0) throw const HttpException('Monochrome DASH download failed');
      } else {
        final response = await httpClient
            .send(http.Request('GET', Uri.parse(manifest)))
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) throw HttpException('Monochrome download: HTTP ${response.statusCode}');
        final total = response.contentLength;
        var received = 0;
        final sink = file.openWrite();
        try {
          await for (final bytes in response.stream.timeout(const Duration(seconds: 30))) {
            check();
            sink.add(bytes);
            received += bytes.length;
            progress?.call(received, total);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        if (total != null && total != received) throw const HttpException('Incomplete Monochrome download');
      }
      check();
      final reader = await file.open();
      List<int> signature;
      try {
        signature = await reader.read(4);
      } finally {
        await reader.close();
      }
      if (ascii.decode(signature, allowInvalid: true) != 'fLaC') {
        throw const FormatException('Monochrome did not return FLAC');
      }
      finishing?.call();
      Uint8List? cover;
      if (track.artworkUrl case final url?) {
        try {
          final response = await httpClient
              .send(http.Request('GET', Uri.parse(url)))
              .timeout(const Duration(seconds: 10));
          if (response.statusCode == 200) {
            final bytes = BytesBuilder();
            await for (final chunk in response.stream.timeout(const Duration(seconds: 10))) {
              if (bytes.length + chunk.length > 10 * 1024 * 1024) break;
              bytes.add(chunk);
            }
            cover = bytes.takeBytes();
          }
        } catch (_) {
          /* The audio remains usable without artwork. */
        }
      }
      check();
      final edit = TagEdit(
        title: track.title,
        artist: track.artist,
        album: track.album,
        trackNumber: track.trackNumber,
        discNumber: track.discNumber,
      )..comment = track.sourceUrl;
      if (cover != null &&
          cover.length >= 8 &&
          ((cover[0] == 0xff && cover[1] == 0xd8) || (cover[0] == 0x89 && cover[1] == 0x50))) {
        edit.cover = cover;
        edit.coverMime = cover[0] == 0x89 ? 'image/png' : 'image/jpeg';
      }
      await Metadata.tagFile(file.path, edit);
      check();
      final target = File(p.join(directory.path, '${jobId(track)}.flac'));
      if (await target.exists()) throw const FileSystemException('Monochrome download already exists');
      final saved = await file.rename(target.path);
      final uri = Uri.file(saved.path);
      return Track(
        id: uri.toString(),
        uri: uri,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: track.duration,
        tagged: true,
        addedAt: DateTime.now().millisecondsSinceEpoch,
        sourceUrl: track.sourceUrl,
      );
    } finally {
      if (owned) httpClient.close();
      await work.delete(recursive: true);
    }
  }
}
