import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../platform/host.dart';

/// Android's Direct USB output (`DirectUsb.kt`): mpv writes the decoded song into a pipe and libusbdac streams it to
/// the USB DAC itself, bit-perfect on any phone, including those whose maker leaves out Android 14's bit-perfect
/// mixer. A format the DAC can't take plays through Android as usual. This side turns it on and off, tells it
/// when playback pauses, plays or seeks, and shows what it reports.
class DirectUsbOutput extends ChangeNotifier {
  DirectUsbOutput({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('riflay/direct_usb');

  final MethodChannel _channel;

  /// Android only: everywhere else Riflay already reaches the DAC directly.
  static bool get supported => Host.isAndroid;

  /// The pipe mpv writes to while it runs; null when off.
  String? fifo;

  /// USB audio devices plugged in, and whether Riflay may use them.
  List<({String name, bool permission})> devices = const [];

  /// Where the song goes: `direct` (to the DAC, untouched), `fallback` (through Android) or `none`.
  String route = 'none';
  String? routeFormat;
  String? streamFormat;
  int underruns = 0;
  String? error;
  List<String> log = const [];

  bool get running => fifo != null;

  /// A DAC is plugged in.
  bool get hasDac => devices.isNotEmpty;

  /// Plugged in, but Android hasn't let Riflay use it yet.
  bool get needsPermission => devices.any((d) => !d.permission);

  Future<void> init() async {
    if (!supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') read(call.arguments);
    });
    try {
      read(await _channel.invokeMethod<Object?>('state'));
    } catch (e) {
      debugPrint('Direct USB state: $e');
    }
  }

  /// Takes in a state map from `DirectUsb.kt`.
  @visibleForTesting
  void read(Object? state) {
    if (state is! Map) return;
    fifo = state['running'] == true ? state['fifo'] as String? : null;
    devices = [
      for (final d in (state['devices'] as List? ?? const []))
        (name: (d as Map)['name'] as String? ?? 'USB DAC', permission: d['permission'] == true),
    ];
    route = state['route'] as String? ?? 'none';
    routeFormat = state['routeFormat'] as String?;
    streamFormat = state['streamFormat'] as String?;
    underruns = state['underruns'] as int? ?? 0;
    error = state['error'] as String?;
    log = [for (final l in (state['log'] as List? ?? const [])) '$l'];
    notifyListeners();
  }

  /// Starts (the pipe is ready for mpv when this returns) or stops it.
  Future<void> enable(bool on) async {
    if (!supported) return;
    try {
      fifo = await _channel.invokeMethod<String>('enable', on);
    } catch (e) {
      debugPrint('Direct USB enable: $e');
      fifo = null;
    }
    notifyListeners();
  }

  Future<void> _call(String method, [Object? args]) async {
    if (!running) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (e) {
      debugPrint('Direct USB $method: $e');
    }
  }

  Future<void> play() => _call('play');
  Future<void> pause() => _call('pause');

  /// After a seek or a jump to another song: what was queued for the DAC is dropped.
  Future<void> flush() => _call('flush');

  /// The song's own bit depth, so a 24-bit song in mpv's 32-bit container goes out as 24-bit.
  Future<void> sourceBits(int? bits) => _call('sourceBits', bits);

  Future<void> requestPermission() => _call('requestPermission');
}
