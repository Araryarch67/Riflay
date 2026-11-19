import 'dart:collection';
import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/top_bar_surface.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../models/track.dart';
import '../../services/language.dart';
import '../../services/spotiflac.dart';

/// Returns to the caller after the provider has stored its grant in extension storage.
Future<bool> showSpotiflacVerification(BuildContext context, Track track, {required String provider}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final url = await Spotiflac.instance.verificationUrl(track, provider: provider);
    if (!context.mounted) return false;
    return await Navigator.of(context, rootNavigator: true).push<bool>(
          MaterialPageRoute(
            builder: (_) => SpotiflacVerificationPage(track: track, url: url, provider: provider),
          ),
        ) ??
        false;
  } catch (e) {
    debugPrint('Open source verification: ${e.runtimeType}');
    if (messenger?.mounted ?? false) {
      messenger!.showSnackBar(SnackBar(content: Text(tr.spotiflacFailed)));
    }
    return false;
  }
}

/// The provider's verification page returns its grant to this view, never to logs.
class SpotiflacVerificationPage extends StatefulWidget {
  const SpotiflacVerificationPage({super.key, required this.track, required this.url, this.provider});
  final Track track;
  final Uri url;
  final String? provider;
  @override
  State<SpotiflacVerificationPage> createState() => _SpotiflacVerificationPageState();
}

class _SpotiflacVerificationPageState extends State<SpotiflacVerificationPage> {
  bool completing = false;
  String? _lastGrant;
  Timer? _grantTimer;
  bool _readingGrant = false;

  @override
  void dispose() {
    _grantTimer?.cancel();
    super.dispose();
  }

  // WebView2 can drop a script-initiated custom-scheme redirect without a user
  // gesture. The provider exposes the same callback in fallbackUrl after Verify.
  // Read it only from that provider's HTTPS page; never from the clipboard.
  void _watchGrant(InAppWebViewController controller) {
    _grantTimer?.cancel();
    _grantTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (_readingGrant || completing || !mounted) return;
      _readingGrant = true;
      try {
        final current = await controller.getUrl();
        if (current?.scheme != 'https' || current?.host != widget.url.host) return;
        final payload = await controller.evaluateJavascript(
          source: r"""
          (function () {
            const callback = document.getElementById('fallbackUrl');
            return callback && callback.textContent ? callback.textContent.trim() : '';
          })();
        """,
        );
        if (payload is String && payload.length <= 16384) {
          final uri = Uri.tryParse(payload);
          if (uri?.scheme == 'spotiflac' &&
              uri?.host == 'session-grant' &&
              (uri?.queryParameters['grant']?.isNotEmpty ?? false)) {
            await navigate(uri);
          }
        }
      } catch (_) {
        // A navigation can invalidate the old document during polling.
      } finally {
        _readingGrant = false;
      }
    });
  }

  Future<NavigationActionPolicy> navigate(Uri? uri) async {
    if (uri?.scheme != 'spotiflac' || uri?.host != 'session-grant') return NavigationActionPolicy.ALLOW;
    final deliveredGrant = uri!.queryParameters['grant'];
    if (completing || deliveredGrant == _lastGrant) return NavigationActionPolicy.CANCEL;
    completing = true;
    try {
      final grant = deliveredGrant;
      final state = uri.queryParameters['state'];
      final provider = widget.provider ?? Spotiflac.instance.downloadProviderOf(widget.track);
      if (state != null && state != provider) throw const SpotiflacError();
      if (grant == null || grant.isEmpty) throw const SpotiflacError();
      _lastGrant = grant;
      await Spotiflac.instance.completeVerification(widget.track, grant, provider: provider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      completing = false;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.spotiflacFailed)));
    }
    return NavigationActionPolicy.CANCEL;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: RiflayAppBar(title: Text(tr.spotiflacVerify)),
    body: InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.url.toString())),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        useShouldOverrideUrlLoading: true,
        javaScriptHandlersForMainFrameOnly: true,
        javaScriptHandlersOriginAllowList: {'^${RegExp.escape(widget.url.origin)}\$'},
      ),
      initialUserScripts: UnmodifiableListView([
        UserScript(
          source: '''
            (function () {
              const bridge = { postMessage: function (payload) {
                return window.flutter_inappwebview.callHandler('riflaySessionGrant', String(payload));
              }};
              window.MornyeGrant = bridge;
              window.SpotiflacGrant = bridge;
            })();
          ''',
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: true,
        ),
      ]),
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'riflaySessionGrant',
          callback: (arguments) async {
            final current = await controller.getUrl();
            // Only the provider's HTTPS verification page may deliver a grant.
            if (current?.scheme != 'https' || current?.host != widget.url.host || arguments.length != 1) return false;
            final payload = arguments.single;
            if (payload is! String || payload.isEmpty || payload.length > 16384) return false;
            final uri = Uri.tryParse(payload);
            if (uri?.scheme == 'spotiflac') {
              await navigate(uri);
            } else if (!payload.contains(RegExp(r'\s')) && !payload.contains('://')) {
              await navigate(Uri(scheme: 'spotiflac', host: 'session-grant', queryParameters: {'grant': payload}));
            }
            return true;
          },
        );
        _watchGrant(controller);
      },
      onLoadStop: (controller, url) async {
        if (url?.scheme != 'https' || url?.host != widget.url.host) return;
        // Reinstall after document creation too: document-start ordering differs
        // between WebView2 and mobile WebViews.
        await controller.evaluateJavascript(
          source: r"""
          (function () {
            const bridge = { postMessage: function (payload) {
              return window.flutter_inappwebview.callHandler('riflaySessionGrant', String(payload));
            }};
            window.MornyeGrant = bridge;
            window.SpotiflacGrant = bridge;
          })();
        """,
        );
        _watchGrant(controller);
      },
      shouldOverrideUrlLoading: (_, action) => navigate(action.request.url),
      onLoadStart: (_, url) async {
        await navigate(url);
      },
    ),
  );
}
