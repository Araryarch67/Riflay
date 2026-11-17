import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:riflay/platform/network.dart';
import 'package:riflay/services/network_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('proxy settings persist and domain rules include only the intended subdomains', () async {
    final config = NetworkSettings();
    await config.save(enabled: true, address: 'http://127.0.0.1:7890/', bypass: '*.example.com, media.test');
    final restored = NetworkSettings();
    await restored.load();
    expect(restored.route(Uri.parse('https://music.youtube.com')), 'PROXY 127.0.0.1:7890');
    for (final host in [
      'example.com',
      'cdn.example.com',
      'media.test',
      'localhost',
      '127.0.0.2',
      '192.168.1.8',
      '10.0.0.1',
      '172.20.1.4',
      '[::1]',
      'speaker.local',
    ]) {
      expect(restored.route(Uri.parse('http://$host/song')), 'DIRECT', reason: host);
    }
    expect(restored.route(Uri.parse('https://badexample.com')), startsWith('PROXY'));
    expect(restored.extractorArguments(Uri.parse('https://youtube.com')), ['--proxy', 'http://127.0.0.1:7890']);
    await restored.save(enabled: false, address: restored.address, bypass: restored.bypass);
    expect(restored.route(Uri.parse('https://music.youtube.com')), 'DIRECT');
  });

  test('invalid or authenticated URLs cannot become a proxy directive', () {
    for (final address in [
      'socks5://127.0.0.1:1080',
      'http://user:password@proxy.test:80',
      'http://proxy.test',
      'http://proxy.test:99999',
      'http://proxy.test:8080/path',
      'garbage',
    ]) {
      expect(NetworkSettings.parseAddress(address), isNull, reason: address);
    }
    expect(NetworkSettings.parseBypass('https://example.com/path'), isNull);
  });

  test('actual app HTTP connections use the configured proxy and bypass local devices', () async {
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final direct = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxied = <Uri>[];
    proxy.listen((request) async {
      proxied.add(request.uri);
      request.response.write('proxied');
      await request.response.close();
    });
    direct.listen((request) async {
      request.response.write('local');
      await request.response.close();
    });
    final settings = NetworkSettings.instance;
    final previous = (settings.enabled, settings.address, settings.bypass);
    try {
      await settings.save(enabled: true, address: 'http://127.0.0.1:${proxy.port}', bypass: '');
      await runWithNetwork(() async {
        final client = HttpClient();
        try {
          final request = await client.getUrl(Uri.parse('http://origin.invalid/song'));
          expect(await (await request.close()).transform(const SystemEncoding().decoder).join(), 'proxied');
          final local = await client.getUrl(Uri.parse('http://127.0.0.1:${direct.port}/song'));
          expect(await (await local.close()).transform(const SystemEncoding().decoder).join(), 'local');
        } finally {
          client.close(force: true);
        }
      });
      expect(proxied.map((uri) => uri.host), ['origin.invalid']);
    } finally {
      await settings.save(enabled: previous.$1, address: previous.$2, bypass: previous.$3);
      await proxy.close(force: true);
      await direct.close(force: true);
    }
  });
}
