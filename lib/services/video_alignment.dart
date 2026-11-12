import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pcm_decoder.dart';
import 'youtube_stream.dart';

/// How a music video's timeline sits against its song's: video time = song time × [rate] + [offset].
class VideoAlign {
  const VideoAlign({required this.offset, this.rate = 1});

  final Duration offset;
  final double rate;

  /// Close enough to the song's own timeline that the follower's 40 ms keeps them together anyway.
  bool get none => offset.inMilliseconds.abs() < 60 && (rate - 1).abs() < 0.0005;

  Map<String, Object> toJson() => {'o': offset.inMilliseconds, 'r': rate};
  static VideoAlign fromJson(Map<String, dynamic> j) => VideoAlign(
    offset: Duration(milliseconds: (j['o'] as num).toInt()),
    rate: (j['r'] as num).toDouble(),
  );

  @override
  String toString() => '${offset.inMilliseconds} ms × $rate';
}

/// Lines a music video up with its song by their sound. A video found without YouTube Music's map of the parts (no
/// account, or found by search) is often another edit or master: measured, one ran 1.1 s off the song, and slipped
/// another 60 ms every 20 s. Both soundtracks' first minute is decoded small (8 kHz mono, with mpv, so phones do it
/// too), reduced to where sounds start, and slid against each other in four windows. Only an answer the windows
/// agree on (one straight line within 60 ms) is taken: two unrelated songs give a peak as tall, but somewhere else
/// in each window. Off with `RIFLAY_NO_MV_ALIGN`.
abstract final class VideoAlignment {
  static const enabled = !bool.fromEnvironment('RIFLAY_NO_MV_ALIGN');

  static const _rate = 8000;
  static const _hop = 80; // 10 ms
  static const _decoded = Duration(seconds: 75);
  static const _window = 2000; // 20 s of 10 ms steps
  static const _maxLag = 300; // ±3 s
  static const _starts = [400, 2000, 3600, 5200];

  static const _key = 'videoAlign.v1';
  static Map<String, dynamic>? _saved;
  static final _measuring = <String, Future<VideoAlign?>>{};

  /// [videoId]'s timeline against [songId]'s; null when it can't be told (then the video plays on the song's own).
  /// Measured once per pair and kept.
  static Future<VideoAlign?> of(String songId, String videoId) {
    final key = '$songId:$videoId';
    return _measuring[key] ??= () async {
      final saved = _saved ??= await _load();
      if (saved.containsKey(key)) {
        final v = saved[key];
        return v is Map<String, dynamic> ? VideoAlign.fromJson(v) : null;
      }
      VideoAlign? found;
      try {
        found = await _measure(songId, videoId);
      } catch (e) {
        debugPrint('Video alignment of $videoId to $songId: $e');
        _measuring.remove(key); // a network hiccup: try again next time
        return null;
      }
      debugPrint('Video alignment of $videoId to $songId: ${found ?? 'unclear'}');
      saved[key] = found?.toJson();
      while (saved.length > 300) {
        saved.remove(saved.keys.first);
      }
      try {
        await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(saved));
      } catch (_) {}
      return found;
    }();
  }

  static Future<Map<String, dynamic>> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw != null) return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {}
    return {};
  }

  static Future<VideoAlign?> _measure(String songId, String videoId) async {
    if (!MpvPcm.supported) return null;
    final songs = await Future.wait([_onsetsOf(songId), _onsetsOf(videoId)]);
    return Isolate.run(() => align(songs[0], songs[1]));
  }

  /// The first [_decoded] of [videoId]'s sound, as [onsets].
  static Future<Float64List> _onsetsOf(String videoId) async {
    final audio = await YoutubeStream.resolve(videoId);
    final pcm = await MpvPcm.decode(PcmInput.file(audio.url.toString()), end: _decoded, rate: _rate, bits: 16);
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in pcm.data) {
      bytes.add(chunk);
    }
    await pcm.cancel();
    final samples = bytes.takeBytes().buffer.asInt16List();
    final mono = Float64List(samples.length ~/ pcm.channels);
    for (var i = 0; i < mono.length; i++) {
      var sum = 0;
      for (var ch = 0; ch < pcm.channels; ch++) {
        sum += samples[i * pcm.channels + ch];
      }
      mono[i] = sum / pcm.channels;
    }
    return onsets(mono);
  }

  /// Where sounds start, every 10 ms of 8 kHz [samples]: how much louder each step is than the last (never quieter),
  /// scaled to a mean of 0 and a deviation of 1.
  @visibleForTesting
  static Float64List onsets(Float64List samples) {
    final steps = samples.length ~/ _hop;
    if (steps < 2) return Float64List(0);
    final level = Float64List(steps);
    for (var s = 0; s < steps; s++) {
      var sum = 0.0;
      for (var i = s * _hop; i < (s + 1) * _hop; i++) {
        sum += samples[i] * samples[i];
      }
      level[s] = math.log(math.sqrt(sum / _hop) + 1);
    }
    final rise = Float64List(steps - 1);
    for (var s = 1; s < steps; s++) {
      rise[s - 1] = math.max(0, level[s] - level[s - 1]);
    }
    var mean = 0.0;
    for (final v in rise) {
      mean += v;
    }
    mean /= rise.length;
    var variance = 0.0;
    for (final v in rise) {
      variance += (v - mean) * (v - mean);
    }
    final deviation = math.sqrt(variance / rise.length) + 1e-9;
    for (var i = 0; i < rise.length; i++) {
      rise[i] = (rise[i] - mean) / deviation;
    }
    return rise;
  }

  /// The video's timeline against the song's, from both [onsets]; null unless the windows agree.
  @visibleForTesting
  static VideoAlign? align(Float64List song, Float64List video) {
    final points = <(double, double)>[]; // (song time, lag) in 10 ms steps
    for (final start in _starts) {
      if (start - _maxLag < 0 || start + _window + _maxLag > video.length || start + _window > song.length) continue;
      var best = double.negativeInfinity, bestLag = 0;
      for (var lag = -_maxLag; lag <= _maxLag; lag++) {
        var dot = 0.0;
        for (var i = 0; i < _window; i++) {
          dot += song[start + i] * video[start + lag + i];
        }
        if (dot > best) {
          best = dot;
          bestLag = lag;
        }
      }
      points.add((start + _window / 2, bestLag.toDouble()));
    }
    // One straight line through all, or all but one, within 60 ms; then the slope is the speed difference.
    for (var drop = -1; drop < points.length; drop++) {
      final kept = [
        for (var i = 0; i < points.length; i++)
          if (i != drop) points[i],
      ];
      if (kept.length < 3) continue;
      final (a, b) = _line(kept);
      if (b.abs() > 0.01) continue;
      if (kept.every((p) => (p.$2 - (a + b * p.$1)).abs() <= 6)) {
        return VideoAlign(
          offset: Duration(milliseconds: (a * 10).round()),
          rate: 1 + b,
        );
      }
    }
    return null;
  }

  /// Least squares: lag = a + b × time.
  static (double, double) _line(List<(double, double)> points) {
    final n = points.length;
    var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
    for (final (x, y) in points) {
      sx += x;
      sy += y;
      sxx += x * x;
      sxy += x * y;
    }
    final b = (n * sxy - sx * sy) / (n * sxx - sx * sx);
    return ((sy - b * sx) / n, b);
  }
}
