import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/host.dart';
import 'player_controller.dart';

/// Android: the lyrics page over the lock screen. When the screen goes off while a song plays, the app comes up over
/// the lock screen ([locked]) and shows the lyrics there until the phone is unlocked (LockScreenLyrics.kt).
abstract final class LockScreenLyrics {
  static const _channel = MethodChannel('riflay/lock_screen');
  static const _key = 'lyrics.overLockScreen';

  static bool get supported => Host.isAndroid;

  /// The setting, saved. Off until turned on: it needs a permission.
  static final enabled = ValueNotifier(false);

  /// Shown over the lock screen now.
  static final locked = ValueNotifier(false);

  static Future<void> attach(PlayerController c) async {
    if (!supported) return;
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_key) ?? false;
    enabled.addListener(() => prefs.setBool(_key, enabled.value));
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'locked':
          locked.value = true;
        case 'unlocked':
          locked.value = false;
      }
    });
    bool? sent;
    void follow() {
      final on = enabled.value && c.isPlaying;
      if (on == sent) return;
      sent = on;
      _channel.invokeMethod('setEnabled', on).ignore();
    }

    c.addListener(follow);
    enabled.addListener(follow);
    follow();
  }

  /// "Display over other apps", which bringing the app up from the background takes.
  static Future<bool> canOverlay() async => await _channel.invokeMethod<bool>('canOverlay') ?? false;

  static Future<void> askOverlay() => _channel.invokeMethod('askOverlay');

  /// The lock screen's own unlock (PIN, fingerprint…).
  static Future<void> unlock() => _channel.invokeMethod('unlock');
}
