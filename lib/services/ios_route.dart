import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where iOS sends the sound now (the `riflay/route` channel, ios/Runner/AudioRoute.swift).
class AudioRoute {
  const AudioRoute({required this.name, required this.rate, required this.channels});

  /// "iPhone Speaker", "AirPods", a USB DAC's name…
  final String name;

  /// The rate the output hardware really runs at; iOS's mixer resamples everything else to it.
  final int rate;
  final int channels;

  static AudioRoute? fromMap(Object? m) {
    if (m is! Map) return null;
    final rate = (m['rate'] as num?)?.round() ?? 0;
    if (rate <= 0) return null;
    return AudioRoute(name: m['name'] as String? ?? '', rate: rate, channels: (m['channels'] as num?)?.toInt() ?? 2);
  }
}

/// Talks to the iOS audio session: the current route, and the rate to run it at.
class IosRoute {
  IosRoute({this.onChanged}) {
    if (!supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') onChanged?.call(AudioRoute.fromMap(call.arguments));
    });
  }

  static bool get supported => Platform.isIOS;

  static const _channel = MethodChannel('riflay/route');

  /// Called when the route changes (a DAC plugged in, Bluetooth gone, AirPlay chosen).
  final void Function(AudioRoute? route)? onChanged;

  Future<AudioRoute?> current() async {
    try {
      return AudioRoute.fromMap(await _channel.invokeMethod<Object>('current'));
    } catch (e) {
      debugPrint('Audio route unavailable: $e');
      return null;
    }
  }

  /// Asks iOS to run the output at [rate] (a DAC then switches to it); returns the route as it is
  /// afterwards, since iOS may keep another rate (the speaker and most Bluetooth run at 48 kHz).
  Future<AudioRoute?> prefer(int rate) async {
    try {
      return AudioRoute.fromMap(await _channel.invokeMethod<Object>('setPreferredRate', rate.toDouble()));
    } catch (e) {
      debugPrint('Preferred rate refused: $e');
      return null;
    }
  }
}

/// The sample rate stored in a FLAC / WAV / AIFF / WavPack header, so the output can be set to it
/// before the song opens it (mpv only knows once the decoder runs, after the output is open).
int? parseSourceRate(Uint8List b) {
  String tag(int at) => at + 4 <= b.length ? String.fromCharCodes(b.sublist(at, at + 4)) : '';
  int le32(int at) => b[at] | b[at + 1] << 8 | b[at + 2] << 16 | b[at + 3] << 24;
  int be32(int at) => b[at] << 24 | b[at + 1] << 16 | b[at + 2] << 8 | b[at + 3];
  if (tag(0) == 'fLaC' && b.length > 22) {
    // STREAMINFO after the 4-byte block header: 20 bits of rate at byte 10.
    return b[18] << 12 | b[19] << 4 | b[20] >> 4;
  }
  if (tag(0) == 'RIFF' && tag(8) == 'WAVE') {
    for (var at = 12; at + 8 <= b.length;) {
      final size = le32(at + 4);
      if (tag(at) == 'fmt ' && at + 20 <= b.length) return le32(at + 12);
      at += 8 + size + (size & 1);
    }
  }
  if (tag(0) == 'FORM' && (tag(8) == 'AIFF' || tag(8) == 'AIFC')) {
    for (var at = 12; at + 8 <= b.length;) {
      final size = be32(at + 4);
      if (tag(at) == 'COMM' && at + 26 <= b.length) {
        // An 80-bit extended float: 15-bit exponent at +16, then a 64-bit mantissa whose top bit is set.
        final exp = (b[at + 16] & 0x7f) << 8 | b[at + 17];
        final shift = 16383 + 31 - exp;
        return shift < 0 || shift > 31 ? null : be32(at + 18) >> shift;
      }
      at += 8 + size + (size & 1);
    }
  }
  if (tag(0) == 'wvpk' && b.length >= 32) {
    const rates = [
      6000,
      8000,
      9600,
      11025,
      12000,
      16000,
      22050,
      24000,
      32000,
      44100,
      48000,
      64000,
      88200,
      96000,
      192000,
    ];
    final i = (le32(24) >> 23) & 0xf;
    return i < rates.length ? rates[i] : null;
  }
  return null;
}

/// The rate to ask iOS for: the user's fixed output rate if there is one, else the song's own.
int? preferredRate({int? outputRate, int? songRate}) => (outputRate ?? 0) > 0 ? outputRate : songRate;
