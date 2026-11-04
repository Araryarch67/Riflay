import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../platform/host.dart';

/// Independent budgets: Flutter's decoded image LRU does not bound Skia's GPU
/// textures, blur masks or other cached drawing resources.
abstract final class RenderingMemory {
  static const decodedImageBytes = 40 << 20;
  static const maxImageCount = 40;
  static const gpuCacheBytes = 96 << 20;

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
