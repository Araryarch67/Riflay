import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:riflay/platform/windows_setup.dart';
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

Map<String, dynamic> windowsReleaseJson({List<int> data = const [1, 2, 3, 4]}) => {
  ...releaseJson(),
  'assets': [
    <String, dynamic>{
      'name': AppRelease.windowsInstallerName,
      'state': 'uploaded',
      'size': data.length,
      'digest': 'sha256:${sha256.convert(data)}',
      'browser_download_url': '${AppRelease.repository}/releases/download/v1.10.0/${AppRelease.windowsInstallerName}',
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

  test('only a minor or major release pops up; a patch release waits in Settings', () {
    final release = AppRelease.parse(releaseJson()); // 1.10.0
    expect(release.patchAbove('1.9.9'), isFalse, reason: 'a minor release pops up');
    expect(release.patchAbove('0.10.0'), isFalse, reason: 'a major release pops up');
    expect(release.patchAbove('1.10.0'), isFalse, reason: 'not newer');
    final patch = AppRelease.parse({
      ...releaseJson(),
      'tag_name': 'v1.10.3',
      'html_url': '${AppRelease.repository}/releases/tag/v1.10.3',
      'assets': const [],
    });
    expect(patch.patchAbove('1.10.0'), isTrue);
    expect(patch.patchAbove('1.10.0+104'), isTrue);
    expect(patch.patchAbove('1.10.3'), isFalse);
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

  test('only the registered Windows executable matches, even when path casing differs', () {
    const registered = r'C:\Users\User\Local Apps\Riflay\riflay.exe';
    expect(WindowsSetup.sameExecutable(registered, r'c:\users\user\Local Apps\Riflay\RIFLAY.exe'), isTrue);
    expect(WindowsSetup.sameExecutable(registered, r'C:\Users\User\scoop\apps\riflay\current\riflay.exe'), isFalse);
    expect(WindowsSetup.sameExecutable(registered, r'D:\Portable\Riflay\riflay.exe'), isFalse);
  });

  test('Windows checks the setup again before launching and quits only after setup starts', () async {
    final folder = Directory.systemTemp.createTempSync('riflay-update-windows-');
    addTearDown(() => folder.deleteSync(recursive: true));
    final actions = <String>[];
    String? location;
    final updates = AppUpdates(
      android: false,
      cacheDirectory: () async => folder,
      findWindowsInstall: () async => location,
      client: MockClient(
        (request) async => request.url.host == 'api.github.com'
            ? http.Response(jsonEncode(windowsReleaseJson()), 200)
            : http.Response.bytes([1, 2, 3, 4], 200),
      ),
      launchWindowsSetup: (file, directory) async {
        expect(directory, location);
        expect(File(file).readAsBytesSync(), [1, 2, 3, 4]);
        actions.add('setup');
      },
      quitWindows: () async => actions.add('quit'),
    );
    addTearDown(updates.dispose);
    final outsideInstaller = await updates.check();
    expect(
      updates.assetFor(outsideInstaller),
      isNull,
      reason: 'Scoop and portable builds only link to the release page',
    );
    location = r'C:\Users\User\Local Apps\Riflay';
    final release = await updates.check();
    expect(updates.assetFor(release)?.name, AppRelease.windowsInstallerName);
    final path = await updates.download(release, (_) {});
    expect(path, endsWith('.exe'));
    File(path).writeAsBytesSync([4, 3, 2, 1]);
    await expectLater(updates.install(path), throwsFormatException);
    expect(actions, isEmpty);
    File(path).writeAsBytesSync([1, 2, 3, 4]);
    expect(await updates.install(path), isTrue);
    expect(actions, ['setup', 'quit']);
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
    expect(folder.listSync().map((f) => p.normalize(f.path)), [p.normalize(other.path)]);
    expect(await AppUpdates(android: false, cacheDirectory: () async => temp).cleanUp(), 0);
  });
}
