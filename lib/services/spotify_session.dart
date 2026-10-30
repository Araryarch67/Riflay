import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;

import '../platform/host.dart';

/// A signed-in Spotify web player session: the cookies that prove the login
/// (`sp_dc` among them) plus the token and headers the player's own requests
/// carry. The token is short-lived; the cookies are what [SpotifyLogin.refresh]
/// turns into a new one.
class SpotifySession {
  const SpotifySession({
    required this.cookies,
    required this.accessToken,
    required this.expiresAt,
    required this.clientToken,
    required this.appVersion,
  });

  /// "a=b; c=d" of the .spotify.com cookies, with `sp_dc` in it.
  final String cookies;
  final String accessToken;
  final DateTime expiresAt;
  final String clientToken;

  /// The web player's `spotify-app-version`; empty when the page never sent one.
  final String appVersion;

  /// Within two minutes of running out: time to ask for a new token.
  bool get expired => DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 2)));

  Map<String, dynamic> toJson() => {
    'cookies': cookies,
    'accessToken': accessToken,
    'expiresAt': expiresAt.millisecondsSinceEpoch,
    'clientToken': clientToken,
    'appVersion': appVersion,
  };

  factory SpotifySession.fromJson(Map<String, dynamic> j) => SpotifySession(
    cookies: j['cookies'] as String? ?? '',
    accessToken: j['accessToken'] as String? ?? '',
    expiresAt: DateTime.fromMillisecondsSinceEpoch((j['expiresAt'] as num?)?.toInt() ?? 0),
    clientToken: j['clientToken'] as String? ?? '',
    appVersion: j['appVersion'] as String? ?? '',
  );
}

/// Sign-in or token refresh failed; [message] is one sentence for the user.
class SpotifyLoginException implements Exception {
  const SpotifyLoginException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Signing in through Spotify's own web player (unofficial). The player
/// fetches its access token itself, and the secret behind that request rotates,
/// so Riflay never computes it: a script injected at document start keeps what
/// the page fetches ([captureJs]) and the sign-in reads it back ([readJs]).
///
/// Linux runs linux/spotify_helper (WebKitGTK); other platforms use the
/// flutter_inappwebview WebView (SpotifyLoginPage) and, for [refresh], a
/// headless one.
abstract final class SpotifyLogin {
  static const _name = 'riflay_spotify';
  static const _closedByUser = 3;
  static const _signedOut = 4;
  static const _origin = 'https://open.spotify.com';
  static const _timeout = Duration(seconds: 45);
  static const _anonymousGrace = Duration(seconds: 5);
  static const _unreachable = SpotifyLoginException('Couldn\'t reach Spotify. Check your internet connection.');

  /// The helper next to the app binary; null when it was not built or on other
  /// platforms.
  static final String? helperPath = () {
    if (!Host.isLinux) return null;
    final path = p.join(p.dirname(Platform.resolvedExecutable), _name);
    return File(path).existsSync() ? path : null;
  }();

  /// Whether this build can show a Spotify sign-in at all. Under `flutter test`
  /// there is no WebView plugin.
  static bool get canSignIn {
    if (Host.isLinux) return helperPath != null;
    return !Host.environment.containsKey('FLUTTER_TEST');
  }

  /// Linux signs in through the helper window; the others in a page of the app.
  static bool get signsInWithHelper => Host.isLinux;

  /// Document-start hook that records, in `window.__riflaySpotify`, the token
  /// the web player fetches and the headers of its API calls. Identical to the
  /// script in linux/spotify_helper/riflay_spotify.cc (a test checks).
  static const String captureJs = r'''(() => {
  if (window.__riflaySpotifyHooked) return;
  window.__riflaySpotifyHooked = true;
  const state = (window.__riflaySpotify = {
    accessToken: '', expiresAt: 0, isAnonymous: null, clientToken: '', appVersion: '',
  });
  const urlOf = (u) => {
    try { return new URL(String(u), location.href); } catch (_) { return null; }
  };
  const isTokenUrl = (u) => !!u && u.hostname === 'open.spotify.com' && u.pathname === '/api/token';
  const isApiUrl = (u) => !!u && (u.hostname === 'api-partner.spotify.com' || u.hostname === 'spclient.wg.spotify.com' ||
    u.hostname.endsWith('.spclient.spotify.com'));
  const onToken = (text) => {
    try {
      const j = JSON.parse(text);
      if (!j || typeof j.accessToken !== 'string' || !j.accessToken) return;
      state.accessToken = j.accessToken;
      state.expiresAt = Number(j.accessTokenExpirationTimestampMs) || Date.now() + 50 * 60000;
      state.isAnonymous = j.isAnonymous === true;
    } catch (_) {}
  };
  const onHeader = (name, value) => {
    try {
      const n = String(name).toLowerCase();
      const v = String(value);
      if (n === 'client-token') state.clientToken = v;
      else if (n === 'spotify-app-version') state.appVersion = v;
      else if (n === 'authorization') {
        const m = /^Bearer\s+(.+)$/i.exec(v);
        if (m && m[1] !== state.accessToken) {
          state.accessToken = m[1];
          state.expiresAt = Date.now() + 50 * 60000;
          state.isAnonymous = null;
        }
      }
    } catch (_) {}
  };
  const onHeaders = (h) => {
    try {
      if (!h) return;
      if (typeof h.forEach === 'function' && !Array.isArray(h)) h.forEach((v, k) => onHeader(k, v));
      else if (Array.isArray(h)) h.forEach((p) => { if (p && p.length > 1) onHeader(p[0], p[1]); });
      else Object.keys(h).forEach((k) => onHeader(k, h[k]));
    } catch (_) {}
  };
  const origFetch = window.fetch;
  if (typeof origFetch === 'function') {
    window.fetch = function (input, init) {
      let url = null;
      try {
        url = urlOf(input && typeof input === 'object' && 'url' in input ? input.url : input);
        if (isApiUrl(url)) {
          if (input && typeof input === 'object' && input.headers) onHeaders(input.headers);
          if (init && init.headers) onHeaders(init.headers);
        }
      } catch (_) {}
      const result = origFetch.apply(this, arguments);
      try {
        if (isTokenUrl(url)) {
          result.then((r) => { try { r.clone().text().then(onToken, () => {}); } catch (_) {} }, () => {});
        }
      } catch (_) {}
      return result;
    };
  }
  const proto = window.XMLHttpRequest && window.XMLHttpRequest.prototype;
  if (proto) {
    const origOpen = proto.open;
    const origSet = proto.setRequestHeader;
    proto.open = function (method, url) {
      try {
        this.__riflayUrl = urlOf(url);
        if (isTokenUrl(this.__riflayUrl)) {
          this.addEventListener('load', () => {
            try { if (this.responseType === '' || this.responseType === 'text') onToken(this.responseText); } catch (_) {}
          });
        }
      } catch (_) {}
      return origOpen.apply(this, arguments);
    };
    proto.setRequestHeader = function (name, value) {
      try { if (isApiUrl(this.__riflayUrl)) onHeader(name, value); } catch (_) {}
      return origSet.apply(this, arguments);
    };
  }
})();''';

  /// Reads what [captureJs] recorded, as JSON text.
  static const String readJs = 'JSON.stringify(window.__riflaySpotify || null)';

  /// Linux: opens the sign-in window and waits. Null when the user closed it;
  /// throws [SpotifyLoginException] when it failed.
  static Future<SpotifySession?> signInWithWindow() async {
    final proc = await Process.start(helperPath!, const []);
    final (out, err, code) = await (
      proc.stdout.transform(utf8.decoder).join(),
      proc.stderr.transform(utf8.decoder).join(),
      proc.exitCode,
    ).wait;
    if (code == _closedByUser) return null;
    final session = code == 0 ? _fromHelperOutput(out) : null;
    if (session == null) {
      debugPrint('Spotify sign-in window exited $code: ${_lastLine(err)}');
      throw const SpotifyLoginException('The Spotify sign-in window closed unexpectedly. Try again.');
    }
    return session;
  }

  /// A new token for a signed-in [cookies] jar, without a window the user sees.
  /// Null when Spotify no longer treats those cookies as signed in; throws
  /// [SpotifyLoginException] when Spotify couldn't be reached.
  static Future<SpotifySession?> refresh(String cookies) async {
    if (Host.isLinux) return _refreshWithHelper(cookies);
    return _refreshHeadless(cookies);
  }

  static Future<SpotifySession?> _refreshWithHelper(String cookies) async {
    final path = helperPath;
    if (path == null) throw _unreachable;
    final proc = await Process.start(path, const ['--refresh']);
    proc.stdin.writeln(cookies.replaceAll(RegExp(r'[\r\n]'), ' '));
    unawaited(proc.stdin.close().catchError((Object _) {}));
    final (out, err, code) = await (
      proc.stdout.transform(utf8.decoder).join(),
      proc.stderr.transform(utf8.decoder).join(),
      proc.exitCode,
    ).wait;
    if (code == _signedOut) return null;
    final session = code == 0 ? _fromHelperOutput(out) : null;
    if (session == null) {
      debugPrint('Spotify refresh exited $code: ${_lastLine(err)}');
      throw _unreachable;
    }
    return session;
  }

  static Future<SpotifySession?> _refreshHeadless(String cookies) async {
    final parsed = _parseCookies(cookies);
    if (!parsed.any((c) => c.$1 == 'sp_dc')) return null;
    HeadlessInAppWebView? view;
    try {
      final jar = CookieManager.instance();
      for (final (name, value) in parsed) {
        await jar.setCookie(
          url: WebUri(_origin),
          name: name,
          value: value,
          domain: '.spotify.com',
          path: '/',
          isSecure: true,
        );
      }
      InAppWebViewController? web;
      view = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri('$_origin/')),
        initialSettings: InAppWebViewSettings(javaScriptEnabled: true, domStorageEnabled: true),
        initialUserScripts: UnmodifiableListView([
          UserScript(
            source: captureJs,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            forMainFrameOnly: true,
          ),
        ]),
        onWebViewCreated: (controller) => web = controller,
      );
      await view.run();
      final started = DateTime.now();
      DateTime? anonymousSince;
      while (DateTime.now().difference(started) < _timeout) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final controller = web;
        if (controller == null) continue;
        final captured = _decode(await controller.evaluateJavascript(source: readJs));
        if (captured is! Map || captured['accessToken'] is! String || captured['accessToken'] == '') continue;
        if (captured['isAnonymous'] == true) {
          // The player may swap it for the real one a moment later.
          anonymousSince ??= DateTime.now();
          if (DateTime.now().difference(anonymousSince) >= _anonymousGrace) return null;
          continue;
        }
        anonymousSince = null;
        final header = (await jar.getCookies(url: WebUri(_origin))).map((c) => '${c.name}=${c.value}').join('; ');
        final session = sessionFrom(captured, header);
        if (session != null) return session;
        // A token without sp_dc is an anonymous session in disguise.
        if (!header.contains('sp_dc=')) return null;
      }
    } catch (e) {
      debugPrint('Spotify refresh failed: $e');
      throw _unreachable;
    } finally {
      await view?.dispose();
    }
    debugPrint('Spotify refresh timed out');
    throw _unreachable;
  }

  /// Builds a session from what [captureJs] recorded (a decoded map or the
  /// JSON text of [readJs]) and the cookie header, or null when the page is not
  /// a signed-in player yet: no token, an anonymous token, no client token, or
  /// no `sp_dc` cookie.
  static SpotifySession? sessionFrom(Object? captured, String cookies) {
    final data = _decode(captured);
    if (data is! Map) return null;
    final token = data['accessToken'];
    final client = data['clientToken'];
    if (token is! String || token.isEmpty || client is! String || client.isEmpty) return null;
    if (data['isAnonymous'] == true) return null;
    if (!_parseCookies(cookies).any((c) => c.$1 == 'sp_dc' && c.$2.isNotEmpty)) return null;
    final ms = (data['expiresAt'] as num?)?.toInt() ?? 0;
    // The bearer-header fallback has no expiry of its own; tokens last an hour.
    final expiresAt = ms > 0
        ? DateTime.fromMillisecondsSinceEpoch(ms)
        : DateTime.now().add(const Duration(minutes: 50));
    return SpotifySession(
      cookies: cookies,
      accessToken: token,
      expiresAt: expiresAt,
      clientToken: client,
      appVersion: data['appVersion'] as String? ?? '',
    );
  }

  /// Signing out of Riflay signs the sign-in WebView out too. Only Spotify's
  /// cookies go. A no-op where the WebView plugin is absent.
  static Future<void> clearWebViewCookies() async {
    try {
      final jar = CookieManager.instance();
      for (final host in const ['open.spotify.com', 'accounts.spotify.com']) {
        await jar.deleteCookies(url: WebUri('https://$host'), domain: '.spotify.com');
        await jar.deleteCookies(url: WebUri('https://$host'), domain: host);
      }
    } catch (_) {
      // The plugin is absent on platforms without a WebView.
    }
  }

  static Object? _decode(Object? raw) {
    if (raw is! String) return raw;
    if (raw.isEmpty || raw == 'null') return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  static SpotifySession? _fromHelperOutput(String out) {
    final line = const LineSplitter().convert(out).lastWhere((l) => l.startsWith('{'), orElse: () => '');
    final j = _decode(line);
    if (j is! Map) return null;
    return sessionFrom(j, j['cookies'] as String? ?? '');
  }

  static List<(String, String)> _parseCookies(String header) => [
    for (final part in header.split(';'))
      if (part.contains('=') && !part.trimLeft().startsWith('='))
        (part.substring(0, part.indexOf('=')).trim(), part.substring(part.indexOf('=') + 1).trim()),
  ];

  static String? _lastLine(String err) => const LineSplitter()
      .convert(err)
      .where((l) => l.trim().isNotEmpty && !l.contains('CRITICAL') && !l.contains('MESA'))
      .lastOrNull;
}
