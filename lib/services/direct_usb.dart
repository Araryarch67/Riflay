import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/host.dart';
import '../platform/native_calls.dart';

/// Android's Direct USB output (`DirectUsb.kt`): mpv writes the decoded song into a pipe and libusbdac streams it to
/// the USB DAC itself, bit-perfect on any phone, including those whose maker leaves out Android 14's bit-perfect
/// mixer. A format the DAC can't take plays through Android as usual. This side turns it on and off, tells it
/// when playback pauses, plays or seeks, and shows what it reports.
///
/// It never takes the app down: when it can't start, or stops on its own, [failed] is set and the songs go back
/// through Android. Should the app still close while it starts (a crash in native code nothing can catch), the next
/// start finds [_startingKey] left behind and leaves Direct USB off ([closedWhileStarting]) instead of closing again.
/// `--dart-define=RIFLAY_NO_DIRECT_USB_GUARD=true` turns both off, so the real crash shows in logcat.
class DirectUsbOutput extends ChangeNotifier {
  DirectUsbOutput({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('riflay/direct_usb');

  final MethodChannel _channel;

  /// Android only: everywhere else Riflay already reaches the DAC directly.
  static bool get supported => Host.isAndroid;

  /// Off with `RIFLAY_NO_DIRECT_USB_GUARD`: no crash guard here or in `DirectUsb.kt`.
  static const guard = !bool.fromEnvironment('RIFLAY_NO_DIRECT_USB_GUARD');

  /// Set while Direct USB starts, cleared once a song has streamed for [_settled] or when it is turned off.
  static const _startingKey = 'directUsb.starting.v1';
  static const _settled = Duration(seconds: 20);
  Timer? _settle;

  /// It couldn't start, or stopped by itself ([error] says why): the songs play through Android.
  bool failed = false;

  /// The app closed the last time Direct USB was starting, so it was left off this time.
  bool closedWhileStarting = false;

  /// Whether the app closed the last time Direct USB was starting (and forgets it). Always false without [guard].
  static Future<bool> closedLastTime() async {
    if (!guard) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final left = prefs.getBool(_startingKey) ?? false;
      if (left) await prefs.remove(_startingKey);
      return left;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _markStarting(bool on) async {
    if (!guard) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      on ? await prefs.setBool(_startingKey, true) : await prefs.remove(_startingKey);
    } catch (e) {
      debugPrint('Direct USB start marker: $e');
    }
  }

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
    final wasRunning = running;
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
    // Stopped without being asked to (enable(false) clears the pipe before the native side reports).
    if (wasRunning && !running) failed = true;
    if (running && route != 'none') {
      _settle ??= Timer(_settled, () => _markStarting(false));
    } else if (!running) {
      _settle?.cancel();
      _settle = null;
    }
    notifyListeners();
  }

  /// Starts (the pipe is ready for mpv when this returns) or stops it. Started, [running] says whether it could.
  Future<void> enable(bool on) async {
    if (!supported) return;
    if (on) {
      failed = false;
      closedWhileStarting = false;
      // mpv writes into the pipe, and a reader that stops must not take the app with it.
      if (!ignoreBrokenPipes()) debugPrint('Direct USB: could not ignore SIGPIPE');
      await _markStarting(true);
    } else {
      // Not a failure: the native side reports it stopped.
      fifo = null;
      _settle?.cancel();
      _settle = null;
      await _markStarting(false);
    }
    try {
      fifo = await _channel.invokeMethod<String>('enable', {'on': on, 'guard': guard});
    } catch (e) {
      debugPrint('Direct USB enable: $e');
      fifo = null;
    }
    if (on && fifo == null) {
      failed = true;
      await _markStarting(false);
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

  Future<void> requestPermission() => _call('requestPermission');
}
