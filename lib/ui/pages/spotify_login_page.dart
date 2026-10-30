import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../services/spotify_session.dart';
import '../theme.dart';

/// One-time Spotify sign-in in the app's own WebView. Spotify's login
/// page lands on the web player, which fetches its own access token; a script
/// injected at document start keeps it, and once a signed-in session is there
/// it is handed back with Navigator.pop.
class SpotifyLoginPage extends StatefulWidget {
  const SpotifyLoginPage({super.key});

  @override
  State<SpotifyLoginPage> createState() => _SpotifyLoginPageState();
}

class _SpotifyLoginPageState extends State<SpotifyLoginPage> {
  static final _startUrl = WebUri('https://accounts.spotify.com/login?continue=https%3A%2F%2Fopen.spotify.com%2F');

  static const _origin = 'https://open.spotify.com';

  InAppWebViewController? _web;
  bool _loading = true;
  bool _checking = false;
  bool _done = false;
  bool _onPlayer = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sign in to Spotify', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        Text(
                          _checking
                              ? 'Checking the session…'
                              : 'Spotify handles the sign-in. Riflay only reads your library.',
                          style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (_checking) const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            ),
          ),
          if (_loading) LinearProgressIndicator(minHeight: 2, backgroundColor: AppColors.panel),
          if (_error != null)
            Container(
              width: double.infinity,
              color: AppColors.elevated,
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_error!, style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
                  ),
                  TextButton(onPressed: _checking ? null : _capture, child: const Text('Try again')),
                ],
              ),
            ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: _startUrl),
              initialSettings: InAppWebViewSettings(javaScriptEnabled: true, domStorageEnabled: true),
              initialUserScripts: UnmodifiableListView([
                UserScript(
                  source: SpotifyLogin.captureJs,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  forMainFrameOnly: true,
                ),
              ]),
              onWebViewCreated: (controller) => _web = controller,
              onLoadStart: (controller, url) => setState(() => _loading = true),
              onLoadStop: (controller, url) {
                setState(() {
                  _loading = false;
                  _onPlayer = url?.host == 'open.spotify.com';
                });
                if (_onPlayer) _capture();
              },
              // "Continue with Google / Apple" opens a popup: keep it in this
              // view, the login page comes back to Spotify on its own.
              onCreateWindow: (controller, action) async {
                final url = action.request.url;
                if (url != null) await controller.loadUrl(urlRequest: URLRequest(url: url));
                return true;
              },
              onReceivedError: (controller, request, error) {
                if (request.isForMainFrame != true) return;
                debugPrint('Spotify sign-in page: ${error.description}');
                setState(() => _error = 'Couldn\'t load the sign-in page. Check your internet connection.');
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Polls the web player for its token while it is the page on screen: the
  /// player asks for it a moment after loading, and the login cookie can settle
  /// later still. Gives up with a hint after about 20 seconds.
  Future<void> _capture() async {
    if (_checking || _done) return;
    _checking = true;
    setState(() => _error = null);
    try {
      for (var attempt = 0; attempt < 40; attempt++) {
        final web = _web;
        if (web == null || !mounted || !_onPlayer) return;
        final raw = await web.evaluateJavascript(source: SpotifyLogin.readJs);
        final jar = await CookieManager.instance().getCookies(url: WebUri(_origin));
        final header = jar.map((c) => '${c.name}=${c.value}').join('; ');
        final session = SpotifyLogin.sessionFrom(raw, header);
        if (session != null) {
          _done = true;
          if (mounted) Navigator.of(context).pop(session);
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      if (mounted) {
        setState(() => _error = 'No signed-in session on this page yet. Finish signing in above, then tap Try again.');
      }
    } catch (e) {
      debugPrint('Spotify sign-in check: $e');
      if (mounted) setState(() => _error = 'Couldn\'t read the Spotify session. Try again.');
    } finally {
      _checking = false;
      if (mounted) setState(() {});
    }
  }
}
