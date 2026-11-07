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
    // Balanced, the default mode: 24 MiB of decoded covers.
    expect(PaintingBinding.instance.imageCache.maximumSizeBytes, 24 << 20);
    if (!Host.isLinux && !Host.isWindows) {
      expect(calls, isEmpty);
      return;
    }
    expect(calls, hasLength(1));
    expect(calls.single.method, 'Skia.setResourceCacheMaxBytes');
    expect(calls.single.arguments, 96 << 20);
  });

  test('renderers without the Skia channel still start normally', () async {
    messenger.setMockMethodCallHandler(SystemChannels.skia, (_) async => throw MissingPluginException());
    await RenderingMemory.configure();
    expect(PaintingBinding.instance.imageCache.maximumSizeBytes, 24 << 20);
  });

  test('the decoded image budget follows the performance mode', () async {
    addTearDown(() => LayoutPrefs.instance.setPerformance(PerformanceMode.balanced));
    SharedPreferences.setMockInitialValues({});
    final budgets = {
      for (final mode in PerformanceMode.values)
        mode: await LayoutPrefs.instance.setPerformance(mode).then((_) => RenderingMemory.decodedImageBytes),
    };
    expect(budgets, {
      PerformanceMode.lightweight: 16 << 20,
      PerformanceMode.balanced: 24 << 20,
      PerformanceMode.heavy: 40 << 20,
    });
  });
}
