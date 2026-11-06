import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../platform/host.dart';

/// The Bluetooth headphones (or speaker) playing now, and what Android sends them.
@immutable
class BluetoothOutput {
  const BluetoothOutput({this.name, this.codec, this.rate, this.bits, this.ldacKbps, this.needsPermission = false});

  /// The headphones' name, e.g. "WH-1000XM4".
  final String? name;

  /// "LDAC", "aptX HD", "AAC", "SBC"…; null when the phone keeps it to itself.
  final String? codec;
  final int? rate;
  final int? bits;

  /// LDAC's bitrate (990, 660 or 330 kbps); 0 when it adapts to the connection.
  final int? ldacKbps;

  /// Reading the codec waits on the Nearby devices permission.
  final bool needsPermission;

  /// "LDAC 990 kbps · 96 kHz / 24-bit".
  String? get label {
    final c = codec;
    if (c == null) return null;
    final kbps = switch (ldacKbps) {
      null => '',
      0 => ' (adaptive)',
      final k => ' $k kbps',
    };
    final format = [
      if (rate case final r?) '${r % 1000 == 0 ? r ~/ 1000 : (r / 1000).toStringAsFixed(1)} kHz',
      if (bits case final b?) '$b-bit',
    ].join(' / ');
    return '$c$kbps${format.isEmpty ? '' : ' · $format'}';
  }

  /// From what the Android side read (`BluetoothCodec.kt`): Android's codec number and its bit masks.
  @visibleForTesting
  static BluetoothOutput fromAndroid(Map<Object?, Object?> m) {
    final type = (m['codec'] as num?)?.toInt();
    final specific = (m['specific1'] as num?)?.toInt();
    return BluetoothOutput(
      name: m['name'] as String?,
      needsPermission: m['permission'] == false,
      codec: switch (type) {
        null => null,
        0 => 'SBC',
        1 => 'AAC',
        2 => 'aptX',
        3 => 'aptX HD',
        4 => 'LDAC',
        5 => 'LC3',
        6 => 'Opus',
        // Vendors' own (aptX Adaptive, LHDC, Samsung's) have numbers of their own.
        final n => 'Codec $n',
      },
      rate: _highest((m['rate'] as num?)?.toInt(), const {
        0x01: 44100,
        0x02: 48000,
        0x04: 88200,
        0x08: 96000,
        0x10: 176400,
        0x20: 192000,
      }),
      bits: _highest((m['bits'] as num?)?.toInt(), const {0x01: 16, 0x02: 24, 0x04: 32}),
      ldacKbps: type != 4
          ? null
          : switch (specific) {
              1000 => 990,
              1001 => 660,
              1002 => 330,
              1003 => 0,
              _ => null,
            },
    );
  }

  static int? _highest(int? mask, Map<int, int> values) {
    if (mask == null || mask == 0) return null;
    int? found;
    for (final MapEntry(:key, :value) in values.entries) {
      if (mask & key != 0) found = value;
    }
    return found;
  }
}

/// Reads [BluetoothOutput] on Android; null elsewhere, and when the sound isn't going to Bluetooth.
abstract final class BluetoothCodecs {
  static const _channel = MethodChannel('riflay/bluetooth');

  static ({DateTime at, BluetoothOutput? output})? _last;

  /// What plays through Bluetooth now. Read at most every few seconds: Signal path and Detail stats ask every second.
  static Future<BluetoothOutput?> read() async {
    if (!Host.isAndroid) return null;
    final last = _last;
    if (last != null && DateTime.now().difference(last.at) < const Duration(seconds: 4)) return last.output;
    BluetoothOutput? output;
    try {
      final m = await _channel.invokeMapMethod<Object?, Object?>('codec');
      output = m == null ? null : BluetoothOutput.fromAndroid(m);
    } catch (e) {
      debugPrint('Bluetooth codec: $e');
    }
    _last = (at: DateTime.now(), output: output);
    return output;
  }

  /// Asks for the Nearby devices permission; true once it is given.
  static Future<bool> allow() async {
    try {
      final ok = await _channel.invokeMethod<bool>('allow') ?? false;
      _last = null;
      return ok;
    } catch (e) {
      debugPrint('Bluetooth permission: $e');
      return false;
    }
  }
}
