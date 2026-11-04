import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:riflay/services/extensions/extension_store.dart';

/// A `.sflx`: a ZIP of [files].
List<int> sflx(Map<String, String> files) {
  final a = Archive();
  for (final e in files.entries) {
    final bytes = utf8.encode(e.value);
    a.addFile(ArchiveFile(e.key, bytes.length, bytes));
  }
  return ZipEncoder().encode(a);
}

String manifest(String id, String version, {bool search = true}) => jsonEncode({
  'name': id,
  'displayName': id.toUpperCase(),
  'version': version,
  'type': ['metadata_provider'],
  'permissions': {
    'network': ['example.com'],
  },
  'searchBehavior': {'enabled': search},
});

class FakeRunner implements ExtensionRunner {
  FakeRunner(this.id, this.log);
  final String id;
  final List<String> log;
  var fail = false;

  @override
  Future<List<ExtensionSearchHit>> search(String query, {int limit = 20}) async {
    log.add('search $id $query');
    if (fail) throw const ExtensionError('boom');
    return [ExtensionSearchHit(id: '1', title: query, artist: 'Artist', extensionId: id)];
  }

  @override
  Future<void> dispose() async => log.add('dispose $id');
}

void main() {
  late Directory root;
  late Map<String, List<int>> served;
  late List<String> fetched;
  late List<String> log;
  late Map<String, FakeRunner> runners;

  const repo = 'https://repo.example/registry.json';

  String registry(List<(String, String, List<int>)> packages) => jsonEncode({
    'version': 1,
    'extensions': [
      for (final (id, version, bytes) in packages)
        {
          'id': id,
          'display_name': id.toUpperCase(),
          'version': version,
          'download_url': 'https://repo.example/$id-$version.sflx',
          'sha256': ExtensionStore.sha256Hex(bytes),
        },
    ],
  });

  ExtensionStore store() => ExtensionStore(
    root: () async => root,
    client: MockClient((req) async {
      fetched.add(req.url.toString());
      final body = served[req.url.toString()];
      return body == null ? http.Response('missing', 404) : http.Response.bytes(body, 200);
    }),
    runnerFor: (ext, storagePath) {
      expect(storagePath, endsWith('${ext.id}.json'));
      return runners[ext.id] = FakeRunner(ext.id, log);
    },
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('riflay-ext-store');
    served = {};
    fetched = [];
    log = [];
    runners = {};
  });
  tearDown(() => root.deleteSync(recursive: true));

  final v1 = sflx({'manifest.json': manifest('demo', '1.0.0'), 'index.js': 'registerExtension({});'});
  final v2 = sflx({'manifest.json': manifest('demo', '1.1.0'), 'index.js': 'registerExtension({v: 2});'});

  test('repositories: added, read, kept across restarts, removed', () async {
    served[repo] = utf8.encode(registry([('demo', '1.0.0', v1)]));
    final s = store();
    await s.addRepository('  $repo  ');
    await s.addRepository(repo);
    expect(s.repositories, [repo]);
    expect(s.stateOf(repo).error, isNull);
    expect(s.available.single.id, 'demo');

    final again = store();
    await again.load();
    expect(again.repositories, [repo]);
    expect(again.available, isEmpty, reason: 'read again only when refreshed');
    await again.refresh();
    expect(again.available.single.version, '1.0.0');

    await again.removeRepository(repo);
    expect(again.repositories, isEmpty);
    expect(again.available, isEmpty);
    expect((await SharedPreferences.getInstance()).getStringList(ExtensionStore.reposKey), isEmpty);
  });

  test('a bad address is refused; an unreadable repository says why and keeps what it had', () async {
    final s = store();
    expect(() => s.addRepository('not a url'), throwsFormatException);
    expect(() => s.addRepository('file:///c:/registry.json'), throwsFormatException);

    served[repo] = utf8.encode(registry([('demo', '1.0.0', v1)]));
    await s.addRepository(repo);
    served[repo] = utf8.encode('<html>not json</html>');
    await s.refresh(repo);
    expect(s.stateOf(repo).error, contains('isn\'t JSON'));
    expect(s.available.single.id, 'demo', reason: 'the last good read stays');

    served.remove(repo);
    await s.refresh(repo);
    expect(s.stateOf(repo).error, contains('404'));
  });

  test('install, search, disable, enable, update, uninstall', () async {
    served[repo] = utf8.encode(registry([('demo', '1.0.0', v1)]));
    served['https://repo.example/demo-1.0.0.sflx'] = v1;
    final s = store();
    await s.addRepository(repo);

    await s.install(s.available.single);
    final installed = s.installedOf('demo')!;
    expect(installed.enabled, isTrue);
    expect(installed.manifest.version, '1.0.0');
    expect(File('${root.path}/demo/index.js').readAsStringSync(), 'registerExtension({});');
    expect(s.searchers.map((e) => e.id), ['demo']);
    expect(s.updateFor('demo'), isNull);

    expect((await s.search('demo', 'hello')).single.title, 'hello');
    expect(log, ['search demo hello']);

    // Off stops its script; searching it then does nothing.
    await s.setEnabled('demo', false);
    expect(log.last, 'dispose demo');
    expect(s.searchers, isEmpty);
    expect(await s.search('demo', 'again'), isEmpty);

    // Kept across restarts, off.
    final again = store();
    await again.load();
    expect(again.installedOf('demo')!.enabled, isFalse);
    await again.setEnabled('demo', true);
    expect((await SharedPreferences.getInstance()).getStringList(ExtensionStore.enabledKey), ['demo']);

    // A newer version in the repository is an update; installing it replaces the files.
    served[repo] = utf8.encode(registry([('demo', '1.1.0', v2)]));
    served['https://repo.example/demo-1.1.0.sflx'] = v2;
    await again.addRepository(repo);
    expect(again.updateFor('demo')!.version, '1.1.0');
    await again.search('demo', 'warm');
    await again.install(again.updateFor('demo')!);
    expect(log.last, 'dispose demo', reason: 'the old script stops before its files are replaced');
    expect(again.installedOf('demo')!.manifest.version, '1.1.0');
    expect(File('${root.path}/demo/index.js').readAsStringSync(), 'registerExtension({v: 2});');
    expect(again.updateFor('demo'), isNull);

    File('${root.path}/.data/demo.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{}');
    await again.uninstall('demo');
    expect(again.installedOf('demo'), isNull);
    expect(Directory('${root.path}/demo').existsSync(), isFalse);
    expect(File('${root.path}/.data/demo.json').existsSync(), isFalse);
    expect(again.available.single.id, 'demo', reason: 'still offered by its repository');
  });

  test('a failing extension is stopped, so the next search starts it afresh', () async {
    final s = store();
    await s.installPackage(v1);
    await s.reload();
    await s.setEnabled('demo', true);
    await s.search('demo', 'one');
    runners['demo']!.fail = true;
    await expectLater(s.search('demo', 'two'), throwsA(isA<ExtensionError>()));
    expect(log.last, 'dispose demo');
    runners.clear();
    await s.search('demo', 'three');
    expect(runners, contains('demo'), reason: 'a new runner');
  });

  test('downloads that don\'t check out are refused and install nothing', () async {
    final s = store();
    final wrongHash = RegistryEntry(
      id: 'demo',
      displayName: 'Demo',
      version: '1.0.0',
      downloadUrl: Uri.parse('https://repo.example/demo.sflx'),
      sha256: ExtensionStore.sha256Hex(v2),
    );
    served['https://repo.example/demo.sflx'] = v1;
    await expectLater(s.install(wrongHash), throwsA(isA<FormatException>()));

    await expectLater(s.installPackage(utf8.encode('not a zip')), throwsA(isA<FormatException>()));
    await expectLater(
      s.installPackage(sflx({'manifest.json': manifest('demo', '1')})),
      throwsA(isA<FormatException>()),
      reason: 'no index.js',
    );
    await expectLater(
      s.installPackage(v1, expectedId: 'other'),
      throwsA(isA<FormatException>()),
      reason: 'a package that is a different extension than listed',
    );
    expect(s.installed, isEmpty);
    expect(Directory('${root.path}/demo').existsSync(), isFalse);
  });

  test('only the package\'s own top-level files are unpacked', () async {
    final s = store();
    final ext = await s.installPackage(
      sflx({
        'manifest.json': manifest('demo', '1.0.0'),
        'index.js': '',
        'LICENSE': 'GPL',
        '../evil.js': 'x',
        'sub/dir.js': 'x',
      }),
    );
    expect(Directory(ext.dir).listSync().map((f) => f.uri.pathSegments.last).toSet(), {
      'manifest.json',
      'index.js',
      'LICENSE',
    });
    expect(File('${root.path}/evil.js').existsSync(), isFalse);
  });

  test('a folder whose manifest names another extension is ignored on load', () async {
    Directory('${root.path}/imposter').createSync(recursive: true);
    File('${root.path}/imposter/manifest.json').writeAsStringSync(manifest('demo', '1'));
    File('${root.path}/imposter/index.js').writeAsStringSync('');
    final s = store();
    await s.load();
    expect(s.installed, isEmpty);
  });
}
