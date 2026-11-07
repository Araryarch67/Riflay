import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/host.dart';
import '../platform/native_calls.dart';
import 'layout_prefs.dart';

/// What the setup page reads about this computer: enough to pick a [PerformanceMode], and to show why.
@immutable
class DeviceSpecs {
  const DeviceSpecs({required this.threads, this.memoryBytes, this.battery, this.cpu});

  /// Hardware threads (logical processors): what Task Manager and `top` divide the CPU into.
  final int threads;

  /// Physical memory; null where it couldn't be read.
  final int? memoryBytes;

  /// A laptop: true; a desktop: false; null when it couldn't tell.
  final bool? battery;

  /// The processor's name ("AMD Ryzen 7 7840HS w/ Radeon 780M Graphics"); null where it couldn't be read.
  final String? cpu;

  /// Memory in whole GB, as shops and the system's About page round it (15.6 GiB usable shows as 16).
  int? get memoryGb => memoryBytes == null ? null : (memoryBytes! / (1 << 30)).round();
}

/// The first start on a computer: Riflay looks at it and picks how much it spends on looks
/// ([PerformanceMode]), so a song playing stays under [budget] of the whole CPU. Shown once, as a page
/// the person confirms (`ui/pages/device_setup_page.dart`); Settings › Power & background opens it again.
class DeviceSetup {
  DeviceSetup._();

  static final instance = DeviceSetup._();

  static const _key = 'deviceSetup.v1';

  /// The most of the whole CPU (all threads together, as Task Manager shows it) a playing song may take.
  static const budget = 0.8;

  /// What a song playing costs in each mode, in % of one thread, measured with `tool/cpu.sh` (the real app in a
  /// 2560 × 1600 window, Home and Now Playing, the default look otherwise; Heavy estimated from Balanced at 30 fps).
  /// Lightweight draws a few frames a second; Balanced moves the cover, the wave and the visualizer at 20 fps;
  /// Heavy at the display's rate. Measure again and change these when what a mode draws changes.
  static const playingCost = {
    PerformanceMode.lightweight: 8.0,
    PerformanceMode.balanced: 25.0,
    PerformanceMode.heavy: 60.0,
  };

  /// Below this much memory the lightest mode, whatever the processor: an integrated GPU takes its share of it.
  static const minMemoryGb = 8;

  bool _due = false;

  /// Whether the page should show at this start: on a computer, once, until it is answered.
  bool get due => _due;

  /// Reads whether it was answered. Only `main` calls it, so tests that build the app themselves never see the page.
  Future<void> load() async {
    if (!offered) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _due = prefs.getBool(_key) != true;
    } catch (e) {
      debugPrint('Device setup unavailable: $e');
    }
  }

  /// The page is answered (a mode picked, or left as it was): it doesn't show again by itself.
  Future<void> done() async {
    _due = false;
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, true);
    } catch (e) {
      debugPrint('Device setup not saved: $e');
    }
  }

  /// Computers only. Phones keep their look: their tab bar and player are drawn for it, and battery there is the
  /// system's business (Settings › Power & background still offers Lightweight).
  static bool get offered =>
      (Host.isLinux || Host.isWindows || Host.isMacOS) &&
      !const bool.fromEnvironment('RIFLAY_NO_DEVICE_SETUP') &&
      !Host.environment.containsKey('FLUTTER_TEST');

  /// The heaviest mode whose playing cost fits in [budget] of this computer's threads; Lightweight with little
  /// memory. 16 threads give 12.8% of one: Lightweight; Balanced needs 32 threads and Heavy 75.
  static PerformanceMode recommend(DeviceSpecs specs) {
    final gb = specs.memoryGb;
    if (gb != null && gb < minMemoryGb) return PerformanceMode.lightweight;
    final room = budget * specs.threads;
    for (final mode in [PerformanceMode.heavy, PerformanceMode.balanced]) {
      if (playingCost[mode]! <= room) return mode;
    }
    return PerformanceMode.lightweight;
  }

  /// [playingCost] of [mode] on [specs], as a share of the whole CPU (what the page shows next to each mode).
  static double share(PerformanceMode mode, DeviceSpecs specs) => playingCost[mode]! / specs.threads;

  /// Reads this computer. Every part that fails is left out; the thread count always answers.
  static Future<DeviceSpecs> read() async {
    final threads = Platform.numberOfProcessors;
    int? memory;
    bool? battery;
    String? cpu;
    try {
      if (Host.isLinux) {
        final meminfo = await File('/proc/meminfo').readAsString();
        final kb = RegExp(r'MemTotal:\s+(\d+) kB').firstMatch(meminfo)?.group(1);
        if (kb != null) memory = int.parse(kb) * 1024;
        final cpuinfo = await File('/proc/cpuinfo').readAsString();
        cpu = RegExp(r'model name\s*:\s*(.+)').firstMatch(cpuinfo)?.group(1)?.trim();
        final supplies = Directory('/sys/class/power_supply');
        if (supplies.existsSync()) {
          battery = false;
          for (final s in supplies.listSync()) {
            final type = File('${s.path}/type');
            if (type.existsSync() && type.readAsStringSync().trim() == 'Battery') battery = true;
          }
        }
      } else if (Host.isWindows) {
        memory = windowsTotalMemory();
        battery = windowsHasBattery();
        final r = await Process.run('reg', [
          'query',
          r'HKLM\HARDWARE\DESCRIPTION\System\CentralProcessor\0',
          '/v',
          'ProcessorNameString',
        ]);
        cpu = RegExp(r'REG_SZ\s+(.+)').firstMatch('${r.stdout}')?.group(1)?.trim();
      } else if (Host.isMacOS) {
        final mem = await Process.run('sysctl', ['-n', 'hw.memsize']);
        memory = int.tryParse('${mem.stdout}'.trim());
        final name = await Process.run('sysctl', ['-n', 'machdep.cpu.brand_string']);
        cpu = '${name.stdout}'.trim();
        final batt = await Process.run('pmset', ['-g', 'batt']);
        battery = '${batt.stdout}'.contains('InternalBattery');
      }
    } catch (e) {
      debugPrint('Device specs partly unread: $e');
    }
    return DeviceSpecs(threads: threads, memoryBytes: memory, battery: battery, cpu: cpu?.isEmpty ?? true ? null : cpu);
  }
}
