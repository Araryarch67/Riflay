import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/platform/host.dart';
import 'package:riflay/services/rendering_memory.dart';

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
    expect(PaintingBinding.instance.imageCache.maximumSizeBytes, 40 << 20);
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
    expect(PaintingBinding.instance.imageCache.maximumSizeBytes, 40 << 20);
  });
}
