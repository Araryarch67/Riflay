import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/lookup_process.dart';
import 'package:riflay/services/ytdlp.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  setUp(() async {
    support = await Directory.systemTemp.createTemp('riflay-cookies-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => support.path,
    );
  });
  tearDown(() async {
    YtDlp.accountCookies = null;
    YtDlp.processes = LookupProcessRunner();
    await support.delete(recursive: true);
  });

  test('the account\'s cookie header becomes a Netscape cookie file for youtube.com', () {
    final file = YtDlp.netscapeCookies('SID=abc; __Secure-3PAPISID=x/y=z;bad; HSID=1', now: DateTime.utc(2026));
    final lines = file.trim().split('\n');
    expect(lines.first, '# Netscape HTTP Cookie File');
    expect(lines, hasLength(4));
    expect(lines[2].split('\t'), ['.youtube.com', 'TRUE', '/', 'TRUE', '1767312000', '__Secure-3PAPISID', 'x/y=z']);
  });

  test('tells a sign-in wall from other failures', () {
    expect(
      YtDlp.needsSignIn('ERROR: [youtube] abc: Sign in to confirm your age. This video may be inappropriate'),
      isTrue,
    );
    expect(YtDlp.needsSignIn("ERROR: [youtube] abc: Sign in to confirm you're not a bot. Use --cookies"), isTrue);
    expect(YtDlp.needsSignIn('ERROR: [youtube] abc: Video unavailable'), isFalse);
  });

  group('downloads', () {
    final calls = <List<String>>[];
    String? cookieFile;
    setUp(() {
      calls.clear();
      YtDlp.processes = LookupProcessRunner(
        execute: (exe, args) async {
          calls.add(args);
          final at = args.indexOf('--cookies');
          if (at < 0) return ProcessResult(1, 1, '', 'ERROR: [youtube] abc: Sign in to confirm your age.');
          cookieFile = args[at + 1];
          expect(File(cookieFile!).readAsStringSync(), contains('\tSID\tabc'));
          if (!Platform.isWindows) expect(File(cookieFile!).statSync().modeString(), 'rw-------');
          return ProcessResult(1, 0, '{"formats": []}', '');
        },
      );
    });

    test('an age-restricted song is asked for again with the account, and the file is removed', () async {
      YtDlp.accountCookies = () => 'SID=abc';
      final formats = await YtDlp.listAllFormatsWith('yt-dlp', 'abc');
      expect(formats.audio, isEmpty);
      expect(calls, hasLength(2));
      expect(calls.first, isNot(contains('--cookies')));
      expect(File(cookieFile!).existsSync(), isFalse);
    });

    test('signed out, the error says to sign in, and nothing is retried', () async {
      await expectLater(
        YtDlp.listAllFormatsWith('yt-dlp', 'abc'),
        throwsA(predicate((e) => '$e'.contains('YouTube Music'))),
      );
      expect(calls, hasLength(1));
    });
  });
}
