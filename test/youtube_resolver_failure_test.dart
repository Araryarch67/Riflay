import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riflay/services/youtube_stream.dart';

void main() {
  test('an unavailable stream reports one awaited failure without an uncaught duplicate', () async {
    final unhandled = <Object>[];
    final complete = Completer<void>();
    await http.runWithClient(
      () async {
        runZonedGuarded(() async {
          try {
            await YoutubeStream.resolve('unavailable-test');
            fail('an unavailable stream must fail');
          } on StateError catch (_) {}
          await Future<void>.delayed(const Duration(milliseconds: 20));
          complete.complete();
        }, (error, stack) => unhandled.add(error));
        await complete.future;
      },
      () => MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.url.path.contains('visitor_id')
                ? {
                    'responseContext': {'visitorData': 'test-visitor'},
                  }
                : {
                    'playabilityStatus': {'status': 'ERROR', 'reason': 'This station is not broadcasting.'},
                  },
          ),
          200,
        ),
      ),
    );
    expect(unhandled, isEmpty);
  });
}
