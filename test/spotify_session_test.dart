import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/spotify_session.dart';

void main() {
  const cookies = 'sp_t=abc; sp_dc=secret';
  final soon = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;

  Map<String, Object?> captured({Object? anonymous = false, String client = 'ct', Object? expires, String? app}) => {
    'accessToken': 'tok',
    'expiresAt': expires ?? soon,
    'isAnonymous': anonymous,
    'clientToken': client,
    'appVersion': app ?? '1.2.3',
  };

  group('sessionFrom', () {
    test('a signed-in player makes a session', () {
      final s = SpotifyLogin.sessionFrom(captured(), cookies)!;
      expect(s.accessToken, 'tok');
      expect(s.clientToken, 'ct');
      expect(s.appVersion, '1.2.3');
      expect(s.cookies, cookies);
      expect(s.expiresAt.millisecondsSinceEpoch, soon);
      expect(s.expired, isFalse);
    });

    test('reads the JSON text readJs returns', () {
      expect(SpotifyLogin.sessionFrom(jsonEncode(captured()), cookies), isNotNull);
      expect(SpotifyLogin.sessionFrom('null', cookies), isNull);
      expect(SpotifyLogin.sessionFrom('not json', cookies), isNull);
      expect(SpotifyLogin.sessionFrom(null, cookies), isNull);
    });

    test('rejects an anonymous token', () {
      expect(SpotifyLogin.sessionFrom(captured(anonymous: true), cookies), isNull);
    });

    test('rejects a missing sp_dc', () {
      expect(SpotifyLogin.sessionFrom(captured(), 'sp_t=abc; sp_dc_other=x'), isNull);
      expect(SpotifyLogin.sessionFrom(captured(), 'sp_dc='), isNull);
      expect(SpotifyLogin.sessionFrom(captured(), ''), isNull);
    });

    test('rejects a missing client token', () {
      expect(SpotifyLogin.sessionFrom(captured(client: ''), cookies), isNull);
    });

    test('the bearer fallback (unknown anonymity) is accepted, expiry 50 minutes out', () {
      final before = DateTime.now();
      final s = SpotifyLogin.sessionFrom(captured(anonymous: null, expires: 0, app: ''), cookies)!;
      expect(s.appVersion, '');
      final left = s.expiresAt.difference(before);
      expect(left, greaterThan(const Duration(minutes: 49)));
      expect(left, lessThanOrEqualTo(const Duration(minutes: 51)));
    });
  });

  group('SpotifySession', () {
    test('survives a JSON round trip', () {
      final s = SpotifyLogin.sessionFrom(captured(), cookies)!;
      final back = SpotifySession.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.toJson(), s.toJson());
      expect(back.expiresAt, s.expiresAt);
    });

    test('expires two minutes early', () {
      SpotifySession at(Duration d) => SpotifySession(
        cookies: cookies,
        accessToken: 't',
        expiresAt: DateTime.now().add(d),
        clientToken: 'c',
        appVersion: '',
      );
      expect(at(const Duration(minutes: 5)).expired, isFalse);
      expect(at(const Duration(minutes: 1)).expired, isTrue);
      expect(at(const Duration(minutes: -5)).expired, isTrue);
    });
  });

  test('the capture script is the same in Dart and in the Linux helper', () {
    final cc = File('linux/spotify_helper/riflay_spotify.cc').readAsStringSync();
    const open = 'R"JS(';
    final start = cc.indexOf(open);
    final end = cc.indexOf(')JS";');
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    expect(cc.substring(start + open.length, end), SpotifyLogin.captureJs);
  });
}
