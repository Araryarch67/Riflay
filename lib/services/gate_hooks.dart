import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';

/// Profile builds only: `tool/release_gate.dart` drives the app through `ext.riflay.gate` over the VM service
/// (play a song, open the expanded player, the lyrics, an album, scroll, go home), so the release gate measures
/// the app as it really runs: no mouse to take over, and no test harness drawing frames of its own. Release
/// builds never register it.
class GateHooks {
  GateHooks._();

  static Future<Object?> Function(String command, Map<String, String> args)? _handler;
  static bool _registered = false;
  static int _frames = 0;

  /// [handler] answers the gate's commands (the app shell's); the latest one attached wins.
  static void attach(Future<Object?> Function(String command, Map<String, String> args) handler) {
    if (!kProfileMode) return;
    _handler = handler;
    if (_registered) return;
    _registered = true;
    SchedulerBinding.instance.addTimingsCallback((t) => _frames += t.length);
    registerExtension('ext.riflay.gate', (method, params) async {
      final command = params['command'] ?? '';
      try {
        if (command == 'frames') {
          // Frames drawn since the last ask.
          final n = _frames;
          _frames = 0;
          return ServiceExtensionResponse.result(jsonEncode({'result': n}));
        }
        final h = _handler;
        if (h == null) throw StateError('no app shell');
        return ServiceExtensionResponse.result(jsonEncode({'result': '${await h(command, params)}'}));
      } catch (e) {
        return ServiceExtensionResponse.error(ServiceExtensionResponse.extensionError, '$e');
      }
    });
  }

  static void detach(Object handler) {
    if (identical(_handler, handler)) _handler = null;
  }

  /// A mouse wheel turn of [dy] logical pixels at [at], as a person scrolls.
  static void wheel(Offset at, double dy) => GestureBinding.instance.handlePointerEvent(
    PointerScrollEvent(position: at, scrollDelta: Offset(0, dy), kind: PointerDeviceKind.mouse),
  );
}
