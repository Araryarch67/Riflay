import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../platform/host.dart';

/// Independent budgets: Flutter's decoded image LRU does not bound Skia's GPU
/// textures, blur masks or other cached drawing resources.
abstract final class RenderingMemory {
  static const decodedImageBytes = 40 << 20;
  static const gpuCacheBytes = 96 << 20;

  static Future<void> configure() async {
    PaintingBinding.instance.imageCache.maximumSizeBytes = decodedImageBytes;
    if (!Host.isWindows && !Host.isLinux) return;
    try {
      // Skia otherwise sizes this cache at 48 bytes per physical window pixel:
      // ~380 MiB for a 4K window. A user-set limit also survives window resizes.
      // This limits evictable cached resources, not active render targets or all
      // process/GPU memory. It changes neither resolution nor visual effects.
      await SystemChannels.skia.invokeMethod<void>('Skia.setResourceCacheMaxBytes', gpuCacheBytes);
    } on MissingPluginException {
      // A different renderer can omit this Skia-specific channel.
    } on PlatformException catch (e) {
      debugPrint('GPU cache budget unavailable: ${e.code}');
    }
  }
}
