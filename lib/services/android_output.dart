import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../platform/host.dart';

/// Whether the phone has spatial audio (Android 12L+), and whether it is on now.
enum AndroidSpatial { unsupported, off, on }

/// What Android's own audio side runs at, for Detail stats' Output (read by `AndroidOutput.kt`).
@immutable
class AndroidOutput {
  const AndroidOutput({
    this.mixerRate,
    this.framesPerBuffer,
    this.lowLatency = false,
    this.pro = false,
    this.spatial = AndroidSpatial.unsupported,
    this.volume,
    this.maxVolume,
    this.deviceBits,
  });

  /// The system mixer's rate (what every app is resampled to), e.g. 48000.
  final int? mixerRate;

  /// The mixer's buffer, in frames.
  final int? framesPerBuffer;

  /// The phone offers low-latency audio, and pro audio (round trip under 20 ms).
  final bool lowLatency;
  final bool pro;
  final AndroidSpatial spatial;

  /// Media volume in the phone's own steps (some phones have 150).
  final int? volume;
  final int? maxVolume;

  /// Bit depth the device playing takes: the mixer format set for a USB DAC, else the best it lists.
  final int? deviceBits;

  /// The mixer's buffer in milliseconds.
  double? get bufferMs => switch ((framesPerBuffer, mixerRate)) {
    (final f?, final r?) when r > 0 => f * 1000 / r,
    _ => null,
  };

  @visibleForTesting
  static AndroidOutput fromMap(Map<Object?, Object?> m) => AndroidOutput(
    mixerRate: (m['mixerRate'] as num?)?.toInt(),
    framesPerBuffer: (m['framesPerBuffer'] as num?)?.toInt(),
    lowLatency: m['lowLatency'] == true,
    pro: m['pro'] == true,
    spatial: AndroidSpatial.values.asNameMap()[m['spatial']] ?? AndroidSpatial.unsupported,
    volume: (m['volume'] as num?)?.toInt(),
    maxVolume: (m['maxVolume'] as num?)?.toInt(),
    deviceBits: (m['deviceBits'] as num?)?.toInt(),
  );

  static const _channel = MethodChannel('riflay/android_output');

  /// Tests stand in for the phone.
  @visibleForTesting
  static Future<AndroidOutput?> Function()? readOverride;

  /// Null off Android, or when the phone won't say.
  static Future<AndroidOutput?> read() async {
    if (readOverride case final read?) return read();
    if (!Host.isAndroid) return null;
    try {
      final m = await _channel.invokeMapMethod<Object?, Object?>('read');
      return m == null ? null : fromMap(m);
    } catch (e) {
      debugPrint('Reading Android output: $e');
      return null;
    }
  }
}
