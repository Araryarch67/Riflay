import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/platform/host.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/rendering_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late int oldImageBudget;

  setUp(() => oldImageBudget = PaintingBinding.instance.imageCache.maximumSizeBytes);
  tearDown(() {
    PaintingBinding.instance.imageCache.maximumSizeBytes = oldImageBudget;
    messenger.setMockMethodCallHandler(SystemChannels.skia, null);
  });

  test('decoded images and GPU resources receive independent cache budgets', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(SystemChannels.skia, (call) async {
      calls.add(call);
      return true;
    });
    await RenderingMemory.configure();
    expect(PaintingBinding.instance.imageCache.maximumSizeBytes, 14 << 20);
    if (!Host.isLinux && !Host.isWindows) {
      expect(calls, isEmpty);
      return;
    }
    expect(calls, hasLength(1));
    expect(calls.single.method, 'Skia.setResourceCacheMaxBytes');
    expect(calls.single.arguments, 32 << 20);
  });

  test('renderers without the Skia channel still start normally', () async {
    messenger.setMockMethodCallHandler(SystemChannels.skia, (_) async => throw MissingPluginException());
    await RenderingMemory.configure();
    expect(PaintingBinding.instance.imageCache.maximumSizeBytes, 14 << 20);
  });

  test('decoded and individual image budgets follow the performance mode', () async {
    addTearDown(() => LayoutPrefs.instance.setPerformance(PerformanceMode.balanced));
    SharedPreferences.setMockInitialValues({});
    final budgets = {
      for (final mode in PerformanceMode.values)
        mode: await LayoutPrefs.instance
            .setPerformance(mode)
            .then(
              (_) => (RenderingMemory.decodedImageBytes, RenderingMemory.artworkSide, RenderingMemory.gpuCacheBytes),
            ),
    };
    expect(budgets, {
      PerformanceMode.lightweight: (6 << 20, 512, 12 << 20),
      PerformanceMode.balanced: (14 << 20, 1024, 32 << 20),
      PerformanceMode.heavy: (24 << 20, 1536, 56 << 20),
    });
  });
}
