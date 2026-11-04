import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/extensions/extension_runtime_io.dart';
import 'package:riflay/services/extensions/extension_store.dart';

/// The JS runtime itself, running a small SpotiFLAC-style script against a local server. Needs flutter_js's native
/// library where the test can load it (on Windows: its `windows/shared` folder on PATH); skipped without it.
void main() {
  final ready = () {
    try {
      if (Platform.isWindows) DynamicLibrary.open('quickjs_c_bridge.dll');
      if (Platform.isLinux) DynamicLibrary.open(Platform.environment['LIBQUICKJSC_TEST_PATH'] ?? 'libquickjs_c_bridge_plugin.so');
      return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }();

  late Directory dir;
  late HttpServer server;
  final asked = <String>[];

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('riflay-ext-run');
    asked.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      asked.add('${req.method} ${req.uri} ua=${req.headers.value('user-agent')}');
      req.response
        ..headers.contentType = ContentType.json
        ..write('{"collection":[{"id":7,"title":"Song","user":"Band","ms":201000}]}')
        ..close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    dir.deleteSync(recursive: true);
  });

  ExtensionManifest manifest({List<String> hosts = const ['127.0.0.1']}) => ExtensionManifest(
    id: 'demo',
    displayName: 'Demo',
    version: '1.0.0',
    types: const ['metadata_provider'],
    networkHosts: hosts,
    searchEnabled: true,
  );

  JsExtensionRunner start(String script, ExtensionManifest m) {
    File('${dir.path}/index.js').writeAsStringSync(script);
    return JsExtensionRunner(dir: dir.path, manifest: m, storagePath: '${dir.path}/data.json', config: {'region': 'id'});
  }

  final script =
      '''
var base = 'http://127.0.0.1:PORT';
var region = null;
registerExtension({
  initialize: function (config) { region = config.region; storage.set('boots', (storage.get('boots') || 0) + 1); },
  customSearch: function (query, options) {
    var params = new URLSearchParams();
    params.set('q', query);
    params.set('region', region);
    var res = http.get(base + '/search?' + params.toString(), { 'User-Agent': utils.randomUserAgent() });
    if (!res.ok) throw new Error('HTTP ' + res.statusCode);
    log.info('found', res.json().collection.length);
    return res.json().collection.map(function (t) {
      return { id: String(t.id), name: t.title, artists: t.user, duration_ms: t.ms, item_type: 'track',
               album_name: utils.md5('x') + '|' + storage.get('boots') + '|' + matching.compareStrings('Héllo', 'hello') };
    });
  }
});
''';

  test('runs a script: synchronous http, storage, utils, config, results', () async {
    final runner = start(script.replaceAll('PORT', '${server.port}'), manifest());
    addTearDown(runner.dispose);
    final hits = await runner.search('a b');
    expect(hits, hasLength(1));
    expect(hits.single.title, 'Song');
    expect(hits.single.artist, 'Band');
    expect(hits.single.duration, const Duration(milliseconds: 201000));
    expect(hits.single.album, '9dd4e461268c8034f5c8564e155c67a6|1|1');
    expect(asked.single, startsWith('GET /search?q=a%20b&region=id ua=Mozilla/5.0'));
    expect(File('${dir.path}/data.json').readAsStringSync(), '{"boots":1}');
  }, skip: !ready);

  test('a host outside the manifest\'s network permissions is blocked', () async {
    final runner = start(script.replaceAll('PORT', '${server.port}'), manifest(hosts: const ['example.com']));
    addTearDown(runner.dispose);
    await expectLater(runner.search('x'), throwsA(isA<ExtensionError>()));
    expect(asked, isEmpty);
  }, skip: !ready);

  test('a script that never registers fails to start', () async {
    final runner = start('var x = 1;', manifest());
    addTearDown(runner.dispose);
    await expectLater(
      runner.search('x'),
      throwsA(isA<ExtensionError>().having((e) => e.message, 'message', contains('registerExtension'))),
    );
  }, skip: !ready);
}
