import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/engine_end.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the process ends with its engine unless switched off, and only Android is told', () async {
    expect(EngineEnd.exits, isTrue);
    const channel = MethodChannel('riflay/engine_end');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
    );
    await EngineEnd.start();
    await EngineEnd.start(keep: true);
    expect(calls, isEmpty, reason: 'these tests run on a computer');
  });
}
