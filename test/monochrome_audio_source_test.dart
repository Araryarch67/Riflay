// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:riflay/services/monochrome.dart';
import 'package:riflay/services/monochrome_audio_source.dart';

class _Client extends Monochrome {
  _Client(this.answer);
  final Future<String> Function(int) answer;
  int requests = 0;
  @override
  Future<String> manifest(String id) => answer(++requests);
}

void main() {
  test('temporary failure retries; ranged reads keep the same resolved URL', () async {
    final client = _Client((attempt) async {
      if (attempt < 3) throw TimeoutException('temporary');
      return 'https://cdn.example/$attempt.flac';
    });
    final source = MonochromeAudioSource('1', client: client, retryDelays: [Duration.zero, Duration.zero]);
    final whole = await source.request();
    final body = [await for (final bytes in whole.stream) ...bytes];
    expect(utf8.decode(body), contains('/3.flac'));
    final part = await source.request(2, 8);
    expect([await for (final bytes in part.stream) ...bytes], body.sublist(2, 8));
    expect(client.requests, 3);
  });

  test('permanent failure does not retry; a later request can resolve again', () async {
    final client = _Client((attempt) async {
      if (attempt == 1) throw http.ClientException('HTTP 404');
      return 'https://cdn.example/recovered.flac';
    });
    final source = MonochromeAudioSource('1', client: client, retryDelays: [Duration.zero]);
    await expectLater(source.request(), throwsA(isA<http.ClientException>()));
    expect(client.requests, 1);
    await source.request();
    expect(client.requests, 2);
  });
}
