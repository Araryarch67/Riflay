import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'proxy_client.dart';

const _configured = String.fromEnvironment('RIFLAY_PROXY');

/// The proxy every blocked request goes through. See `network.dart`.
final Uri webProxy = Uri.parse(_configured.isEmpty ? '${Uri.base.origin}/' : _configured);

/// Runs the app with every `http.Client()` and `http.get` in it going through [ProxyClient].
R runWithNetwork<R>(R Function() body) => http.runWithClient(body, () => ProxyClient(BrowserClient(), webProxy));

/// Whether this browser plays YouTube's Opus streams (Safari before 17 does not); AAC is asked for otherwise.
final bool playsOpus = web.HTMLAudioElement().canPlayType('audio/webm; codecs="opus"').isNotEmpty;

/// The tab's title. Some browsers (Brave) name the song in the desktop's media controls after it rather than after
/// the Media Session.
set pageTitle(String title) => web.document.title = title;
