import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../platform/host.dart';
import 'language.dart';

/// Supports Matugen's old mode-first JSON, current role-first JSON, and flat
/// template output (snake_case or camelCase). No wallpaper command is executed.
class MatugenColors {
  MatugenColors(this._json);
  final Map<String, dynamic> _json;

  factory MatugenColors.parse(String text) {
    final root = jsonDecode(text);
    if (root is! Map<String, dynamic>) throw const FormatException('Expected a color object');
    final colors = MatugenColors(root);
    colors.scheme(light: false); // Reject incomplete files before replacing a working theme.
    colors.scheme(light: true);
    return colors;
  }

  ColorScheme scheme({required bool light}) {
    Map<dynamic, dynamic> roles = (_json['colors'] is Map ? _json['colors'] : _json) as Map;
    final mode = light ? 'light' : 'dark';
    if (roles[mode] is Map) {
      roles = roles[mode] as Map;
    } else if (roles['dark'] is Map) {
      roles = roles['dark'] as Map;
    } else if (roles['light'] is Map) {
      roles = roles['light'] as Map;
    }
    Color? read(String name) {
      final camel = name.replaceAllMapped(RegExp(r'_([a-z])'), (m) => m[1]!.toUpperCase());
      dynamic raw = roles[name] ?? roles[camel];
      if (raw is Map) raw = raw[mode] ?? raw['default'] ?? raw['dark'] ?? raw['light'] ?? raw;
      if (raw is Map) raw = raw['hex'] ?? raw['color'];
      if (raw is! String) return null;
      final match = RegExp(r'^#?([a-fA-F0-9]{6})$').firstMatch(raw.trim());
      return match == null ? null : Color(0xFF000000 | int.parse(match[1]!, radix: 16));
    }

    final primary = read('primary');
    final surface = read('surface') ?? read('background');
    final foreground = read('on_surface') ?? read('foreground');
    if (primary == null || surface == null || foreground == null) {
      throw const FormatException('Missing primary, surface or on_surface colors');
    }
    final brightness = foreground.computeLuminance() > surface.computeLuminance() ? Brightness.dark : Brightness.light;
    final base = ColorScheme.fromSeed(seedColor: primary, brightness: brightness);
    return base.copyWith(
      primary: primary,
      onPrimary: read('on_primary'),
      primaryContainer: read('primary_container'),
      onPrimaryContainer: read('on_primary_container'),
      secondary: read('secondary'),
      onSecondary: read('on_secondary'),
      secondaryContainer: read('secondary_container'),
      onSecondaryContainer: read('on_secondary_container'),
      tertiary: read('tertiary'),
      onTertiary: read('on_tertiary'),
      tertiaryContainer: read('tertiary_container'),
      onTertiaryContainer: read('on_tertiary_container'),
      error: read('error'),
      onError: read('on_error'),
      errorContainer: read('error_container'),
      onErrorContainer: read('on_error_container'),
      surface: surface,
      onSurface: foreground,
      onSurfaceVariant: read('on_surface_variant'),
      surfaceContainerLowest: read('surface_container_lowest'),
      surfaceContainerLow: read('surface_container_low'),
      surfaceContainer: read('surface_container'),
      surfaceContainerHigh: read('surface_container_high'),
      surfaceContainerHighest: read('surface_container_highest'),
      surfaceDim: read('surface_dim'),
      surfaceBright: read('surface_bright'),
      outline: read('outline'),
      outlineVariant: read('outline_variant'),
      inverseSurface: read('inverse_surface'),
      onInverseSurface: read('inverse_on_surface'),
      inversePrimary: read('inverse_primary'),
      shadow: read('shadow'),
      scrim: read('scrim'),
    );
  }
}

/// Polling survives atomic replacement, missing directories and late generators.
/// Only selected Matugen themes run the timer. Bad writes retain the last colors.
class MatugenTheme extends ChangeNotifier {
  MatugenTheme({List<String>? candidates}) : candidates = candidates ?? defaultPaths();
  final List<String> candidates;
  MatugenColors? colors;
  String? path;
  String? error;
  String? selectedPath;
  String? _signature;
  Future<void>? _loading;
  int _generation = 0;
  bool _disposed = false;
  Timer? _timer;

  static List<String> defaultPaths() {
    final env = Host.environment;
    final home = env['HOME'];
    if (home == null) return const [];
    final config = env['XDG_CONFIG_HOME'] ?? p.join(home, '.config');
    final cache = env['XDG_CACHE_HOME'] ?? p.join(home, '.cache');
    return [
      p.join(config, 'riflay', 'matugen.json'),
      p.join(cache, 'matugen', 'colors.json'),
      p.join(cache, 'ryoku', 'colors.json'),
    ];
  }

  Future<void> start({String? file}) async {
    final generation = ++_generation;
    await _loading;
    if (_disposed || generation != _generation) return;
    selectedPath = file;
    _signature = null;
    await reload();
    if (!_disposed && generation == _generation) _timer ??= Timer.periodic(const Duration(seconds: 2), (_) => reload());
  }

  void stop() {
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> reload() => _loading ??= _reload().whenComplete(() {
    _loading = null;
  });

  Future<void> _reload() async {
    if (_disposed) return;
    final previousError = error;
    try {
      File? file;
      for (final candidate in selectedPath == null ? candidates : [selectedPath!]) {
        final next = File(candidate);
        if (await next.exists()) {
          file = next;
          break;
        }
      }
      if (file == null) throw const FileSystemException('No generated colors found');
      final stat = await file.stat();
      if (stat.size > 128 * 1024) throw const FormatException('Color file too large');
      final signature = '${file.path}:${stat.modified.microsecondsSinceEpoch}:${stat.size}';
      if (signature == _signature) return;
      final updated = MatugenColors.parse(await file.readAsString());
      if (_disposed) return;
      colors = updated;
      path = file.path;
      error = null;
      _signature = signature;
      notifyListeners();
    } catch (_) {
      if (!_disposed) {
        error = tr.matugenInvalid;
        if (error != previousError) notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
