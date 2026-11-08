import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riflay/services/app_updates.dart';

Map<String, dynamic> releaseJson({String version = '1.10.0', List<int> data = const [1, 2, 3, 4]}) => {
  'tag_name': 'v$version',
  'html_url': '${AppRelease.repository}/releases/tag/v$version',
  'draft': false,
  'prerelease': false,
  'assets': [
    for (final suffix in ['-arm64', '-arm32', '-x86_64', ''])
      <String, dynamic>{
        'name': 'Riflay-android$suffix.apk',
        'state': 'uploaded',
        'size': data.length,
        'digest': 'sha256:${sha256.convert(data)}',
        'browser_download_url': '${AppRelease.repository}/releases/download/v$version/Riflay-android$suffix.apk',
      },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('riflay/updates');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'info') {
        return {
          'version': '1.9.9',
          'abis': ['x86_64', 'arm64-v8a'],
        };
      }
      return true;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('version comparison handles numeric components, downgrade and prerelease', () {
    final release = AppRelease.parse(releaseJson());
    expect(release.newerThan('1.9.9'), isTrue);
    expect(release.newerThan('1.10.0'), isFalse);
    expect(release.newerThan('1.10.0+100'), isFalse);
    expect(release.newerThan('1.10.0-beta.1'), isTrue);
    expect(release.newerThan('2.0.0'), isFalse);
  });

  test('a release candidate is never offered, and its stable version is offered to it', () {
    // v1.3.0-rc1 is published as a pre-release, with an rc tag: not a stable release.
    final rc = {...releaseJson(), 'tag_name': 'v1.3.0-rc1', 'prerelease': true};
    expect(() => AppRelease.parse(rc), throwsFormatException);
    expect(() => AppRelease.parse({...rc, 'prerelease': false}), throwsFormatException);
    // Someone on 1.3.0-rc1: the last stable 1.2.19 is older; 1.3.0 is newer.
    expect(AppRelease('1.2.19', Uri(), const []).newerThan('1.3.0-rc1'), isFalse);
    expect(AppRelease('1.3.0', Uri(), const []).newerThan('1.3.0-rc1'), isTrue);
  });

  test('ABI selection follows Android preference and falls back to universal', () {
    final release = AppRelease.parse(releaseJson());
    expect(release.androidAsset(['arm64-v8a', 'armeabi-v7a'])!.name, 'Riflay-android-arm64.apk');
    expect(release.androidAsset(['armeabi-v7a'])!.name, 'Riflay-android-arm32.apk');
    expect(release.androidAsset(['x86_64', 'arm64-v8a'])!.name, 'Riflay-android-x86_64.apk');
    expect(release.androidAsset(['unknown'])!.name, 'Riflay-android.apk');
  });

  test('untrusted URLs, missing checksums and unavailable assets cannot be downloaded', () {
    final json = releaseJson();
    final assets = json['assets'] as List;
    assets[0]['browser_download_url'] = 'https://example.org/Riflay-android-arm64.apk';
    assets[1]['digest'] = null;
    assets[2]['state'] = 'new';
    assets[3]['size'] = 1024 * 1024 * 1024;
    final release = AppRelease.parse(json);
    expect(release.assets, isEmpty);
    expect(release.androidAsset(['arm64-v8a']), isNull);
    for (final change in [
      {'draft': true},
      {'prerelease': true},
      {'tag_name': 'v1.10.0/../../oops'},
      {'html_url': 'https://example.org/releases'},
    ]) {
      expect(() => AppRelease.parse({...releaseJson(), ...change}), throwsFormatException);
    }
  });

  test('release check reads the installed version and selects the device APK', () async {
    final updates = AppUpdates(
      android: true,
      client: MockClient((request) async {
        expect(request.url.host, 'api.github.com');
        return http.Response(jsonEncode(releaseJson()), 200);
      }),
    );
    addTearDown(updates.dispose);
    final release = await updates.check();
    expect(updates.installedVersion, '1.9.9');
    expect(updates.assetFor(release)!.name, 'Riflay-android-x86_64.apk');
  });

  test('HTTP failure does not report that the app is up to date', () async {
    final updates = AppUpdates(android: false, client: MockClient((_) async => http.Response('', 403)));
    addTearDown(updates.dispose);
    await expectLater(updates.check(), throwsStateError);
  });

  for (final corrupt in [false, true]) {
    test(
      'APK download ${corrupt ? 'rejects corruption and removes partial files' : 'checks size and SHA-256'}',
      () async {
        final folder = Directory.systemTemp.createTempSync('riflay-update-test-');
        addTearDown(() => folder.deleteSync(recursive: true));
        final updates = AppUpdates(
          android: true,
          cacheDirectory: () async => folder,
          client: MockClient((_) async => http.Response.bytes(corrupt ? [4, 3, 2, 1] : [1, 2, 3, 4], 200)),
        );
        addTearDown(updates.dispose);
        final release = AppRelease.parse(releaseJson());
        final progress = <double>[];
        if (corrupt) {
          await expectLater(updates.download(release, progress.add), throwsFormatException);
          expect(Directory('${folder.path}/app-updates').listSync(), isEmpty);
        } else {
          final path = await updates.download(release, progress.add);
          expect(File(path).readAsBytesSync(), [1, 2, 3, 4]);
          expect(progress.last, 1);
          expect(File('$path.part').existsSync(), isFalse);
        }
      },
    );
  }

  test('an installed update leaves no APK behind: the next start deletes it', () async {
    final temp = Directory.systemTemp.createTempSync('riflay-updates-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final folder = Directory('${temp.path}/app-updates')..createSync();
    File('${folder.path}/riflay-1.2.1.apk').writeAsBytesSync([1, 2, 3]);
    File('${folder.path}/riflay-1.2.2.apk.part').writeAsBytesSync([1]);
    final other = File('${folder.path}/notes.txt')..writeAsStringSync('kept');
    final updates = AppUpdates(android: true, cacheDirectory: () async => temp);
    addTearDown(updates.dispose);
    expect(await updates.cleanUp(), 2);
    expect(folder.listSync().map((f) => f.path), [other.path]);
    expect(await AppUpdates(android: false, cacheDirectory: () async => temp).cleanUp(), 0);
  });
}
