import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../platform/host.dart';
import 'layout_prefs.dart';

/// Independent budgets: Flutter's decoded image LRU does not bound Skia's GPU
/// textures, blur masks or other cached drawing resources.
abstract final class RenderingMemory {
  /// Decoded covers that are kept after leaving the screen.
  static int get decodedImageBytes => switch (LayoutPrefs.instance.performance) {
    PerformanceMode.heavy => 24 << 20,
    PerformanceMode.balanced => 14 << 20,
    PerformanceMode.lightweight => 6 << 20,
  };
  static const maxImageCount = 40;
  static int get gpuCacheBytes => switch (LayoutPrefs.instance.performance) {
    PerformanceMode.heavy => 56 << 20,
    PerformanceMode.balanced => 32 << 20,
    PerformanceMode.lightweight => 12 << 20,
  };

  /// Bounds each visible cover too. Flutter's image cache only limits evictable images.
  static int get artworkSide => switch (LayoutPrefs.instance.performance) {
    PerformanceMode.heavy => 1536,
    PerformanceMode.balanced => 1024,
    PerformanceMode.lightweight => 512,
  };

  static Future<void> configure() async {
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSizeBytes = decodedImageBytes;
    cache.maximumSize = maxImageCount;
    await _gpuCache(gpuCacheBytes);
  }

  /// Nothing is drawn while the window is hidden: decoded images that aren't on
  /// screen are dropped, and a zero budget makes Skia purge its cached textures.
  static Future<void> release() async {
    PaintingBinding.instance.imageCache.clear();
    await _gpuCache(0);
  }

  static Future<void> restore() => _gpuCache(gpuCacheBytes);

  /// The mini player: only its own cover and controls are drawn. The pages' decoded images go (they come back from
  /// the disk cache when the full window does), Skia's cache is emptied, and the mini player keeps [miniGpuCacheBytes].
  static const miniGpuCacheBytes = 16 << 20;
  static Future<void> mini() async {
    PaintingBinding.instance.imageCache.clear();
    await _gpuCache(0);
    await _gpuCache(gpuCacheBytes < miniGpuCacheBytes ? gpuCacheBytes : miniGpuCacheBytes);
  }

  static Future<void> _gpuCache(int bytes) async {
    if (!Host.isWindows && !Host.isLinux) return;
    try {
      // Skia otherwise sizes this cache at 48 bytes per physical window pixel:
      // ~380 MiB for a 4K window. A user-set limit also survives window resizes.
      // This limits evictable cached resources, not active render targets or all
      // process/GPU memory. It changes neither resolution nor visual effects.
      await SystemChannels.skia.invokeMethod<void>('Skia.setResourceCacheMaxBytes', bytes);
    } on MissingPluginException {
      // A different renderer can omit this Skia-specific channel.
    } on PlatformException catch (e) {
      debugPrint('GPU cache budget unavailable: ${e.code}');
    }
  }
}
