import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../platform/host.dart';
import '../platform/native_calls.dart';
import 'player_controller.dart';
import 'power_policy.dart';

/// Keeps the device awake while it matters: the phone's CPU and Wi-Fi while
/// music plays with the screen off, the computer's idle suspend while music
/// plays, and the screen when the user asks for it. What to hold is decided in
/// `power_policy.dart`; this watches the player from the outside and applies it.
class StayAwake extends ChangeNotifier with WidgetsBindingObserver {
  StayAwake._(this._c, {PowerBackend? backend}) : _backend = backend ?? PowerBackend.forThisPlatform();

  static StayAwake? _instance;

  /// Null until [start]; the settings page treats that as "no controls".
  static StayAwake? get instance => _instance;

  static Future<StayAwake> start(PlayerController c, {PowerBackend? backend}) async {
    final s = _instance = StayAwake._(c, backend: backend);
    await s._load();
    WidgetsBinding.instance.addObserver(s);
    c.addListener(s._update);
    s._update();
    return s;
  }

  final PlayerController _c;
  final PowerBackend _backend;

  static const _screenKey = 'power.screen.v1';
  static const _sleepKey = 'power.preventSleep.v1';
  static const _askedKey = 'power.batteryAsked.v1';

  KeepScreenOn _screen = KeepScreenOn.off;
  bool _preventSleep = true;
  bool _foreground = true;
  bool _asked = false;
  PowerLocks _held = const PowerLocks();

  KeepScreenOn get screen => _screen;

  /// "Don't let the computer sleep while music plays" (computers only).
  bool get preventSleep => _preventSleep;

  /// The battery sheet was already offered once.
  bool get batteryAsked => _asked;

  PowerLocks get held => _held;

  static bool get isPhone => Host.isAndroid || Host.isIOS;
  static bool get isDesktop => Host.isLinux || Host.isWindows || Host.isMacOS;

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final i = p.getInt(_screenKey) ?? 0;
      _screen = KeepScreenOn.values[i.clamp(0, KeepScreenOn.values.length - 1)];
      _preventSleep = p.getBool(_sleepKey) ?? true;
      _asked = p.getBool(_askedKey) ?? false;
    } catch (e) {
      debugPrint('Power settings unavailable: $e');
    }
  }

  Future<void> setScreen(KeepScreenOn v) async {
    _screen = v;
    notifyListeners();
    _update();
    (await SharedPreferences.getInstance()).setInt(_screenKey, v.index);
  }

  Future<void> setPreventSleep(bool v) async {
    _preventSleep = v;
    notifyListeners();
    _update();
    (await SharedPreferences.getInstance()).setBool(_sleepKey, v);
  }

  Future<void> markBatteryAsked() async {
    _asked = true;
    (await SharedPreferences.getInstance()).setBool(_askedKey, true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    if (fg == _foreground) return;
    _foreground = fg;
    _update();
  }

  PowerFacts get facts {
    final t = _c.currentTrack;
    return PowerFacts(
      screen: _screen,
      preventSleep: _preventSleep,
      playing: _c.isPlaying,
      foreground: _foreground,
      phone: isPhone,
      desktop: isDesktop,
      streaming: t != null && !_c.isOffline(t),
    );
  }

  bool _busy = false;
  bool _again = false;

  void _update() {
    // Applies one change at a time; a burst of player events ends in the last answer.
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    () async {
      try {
        do {
          _again = false;
          final want = decideLocks(facts);
          if (want != _held) {
            await _backend.apply(_held, want);
            _held = want;
          }
        } while (_again);
      } finally {
        _busy = false;
      }
    }();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.removeListener(_update);
    _backend.apply(_held, const PowerLocks());
    _held = const PowerLocks();
    if (identical(_instance, this)) _instance = null;
    super.dispose();
  }
}

/// Applies a change of locks on one platform.
abstract class PowerBackend {
  Future<void> apply(PowerLocks from, PowerLocks to);

  factory PowerBackend.forThisPlatform() {
    if (Host.isAndroid) return _AndroidBackend();
    if (Host.isLinux) return _DesktopBackend(LinuxIdleInhibitor());
    if (Host.isWindows) return _DesktopBackend(WindowsPowerRequest());
    if (Host.isMacOS) return _DesktopBackend(MacAssertion());
    return _DesktopBackend(null);
  }
}

Future<void> _screenLock(bool on) async {
  try {
    await WakelockPlus.toggle(enable: on);
  } catch (e) {
    debugPrint('Keep screen on unavailable: $e');
  }
}

class _AndroidBackend implements PowerBackend {
  static const _channel = MethodChannel('riflay/power');

  @override
  Future<void> apply(PowerLocks from, PowerLocks to) async {
    if (from.screen != to.screen) await _screenLock(to.screen);
    if (from.cpu != to.cpu || from.wifi != to.wifi) {
      try {
        await _channel.invokeMethod('hold', {'cpu': to.cpu, 'wifi': to.wifi});
      } catch (e) {
        debugPrint('Power locks unavailable: $e');
      }
    }
  }
}

/// Computers and iOS: the screen lock plus, on computers, the idle-suspend lock.
class _DesktopBackend implements PowerBackend {
  _DesktopBackend(this._idle);
  final IdleInhibitor? _idle;

  @override
  Future<void> apply(PowerLocks from, PowerLocks to) async {
    if (from.screen != to.screen) await _screenLock(to.screen);
    if (from.systemSleep != to.systemSleep) {
      try {
        if (to.systemSleep) {
          await _idle?.acquire();
        } else {
          await _idle?.release();
        }
      } catch (e) {
        debugPrint('Sleep lock unavailable: $e');
      }
    }
  }
}

/// Stops the computer suspending when idle; the screen may still turn off.
abstract class IdleInhibitor {
  Future<void> acquire();
  Future<void> release();
}

/// systemd-logind: an "idle" inhibitor is held for as long as the returned file descriptor stays open.
class LinuxIdleInhibitor implements IdleInhibitor {
  DBusClient? _bus;
  ResourceHandle? _fd;

  @override
  Future<void> acquire() async {
    if (_fd != null) return;
    final bus = _bus ??= DBusClient.system();
    final reply = await bus.callMethod(
      destination: 'org.freedesktop.login1',
      path: DBusObjectPath('/org/freedesktop/login1'),
      interface: 'org.freedesktop.login1.Manager',
      name: 'Inhibit',
      values: [DBusString('idle'), DBusString('Riflay'), DBusString('Playing music'), DBusString('block')],
      replySignature: DBusSignature('h'),
    );
    _fd = (reply.returnValues.first as DBusUnixFd).handle;
  }

  @override
  Future<void> release() async {
    final fd = _fd;
    _fd = null;
    fd?.toFile().closeSync();
    await _bus?.close();
    _bus = null;
  }
}

/// Android's battery optimisation: whether Riflay is exempt, and the way to ask.
class BatteryExemption {
  static const _channel = MethodChannel('riflay/power');

  static bool get supported => Host.isAndroid;

  /// True when the system already lets Riflay run in the background freely.
  static Future<bool> isExempt() async {
    if (!supported) return true;
    try {
      return await _channel.invokeMethod<bool>('isExempt') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Shows the system's one-tap "Allow Riflay to run in the background?" dialog.
  static Future<void> request() async {
    try {
      await _channel.invokeMethod('request');
    } catch (e) {
      debugPrint('Battery request unavailable: $e');
    }
  }

  /// The phone brand's own battery page where one is known, else Riflay's app details.
  static Future<void> openBatterySettings() async {
    try {
      await _channel.invokeMethod('openBatterySettings');
    } catch (e) {
      debugPrint('Battery settings unavailable: $e');
    }
  }

  /// The maker, lower case ("xiaomi", "samsung"...).
  static Future<String> brand() async {
    if (!supported) return '';
    try {
      return await _channel.invokeMethod<String>('brand') ?? '';
    } catch (_) {
      return '';
    }
  }

  /// True for makers whose phones close background music apps on their own.
  static bool isAggressive(String brand) => const {
    'xiaomi',
    'redmi',
    'poco',
    'oppo',
    'realme',
    'oneplus',
    'vivo',
    'iqoo',
    'samsung',
    'huawei',
    'honor',
    'infinix',
    'tecno',
    'itel',
  }.contains(brand);
}
