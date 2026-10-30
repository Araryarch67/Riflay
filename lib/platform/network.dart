/// The network as the app sees it. Native builds call every service directly. The web build sends the ones a
/// browser may not call (YouTube Music, its streams, lyrics) through Riflay's proxy, whose address comes from
/// `--dart-define=RIFLAY_PROXY=<url>` (the page's own address when unset, for a proxy that also serves the app).
library;

import 'proxy_route.dart';

export 'network_io.dart' if (dart.library.js_interop) 'network_web.dart';

import 'network_io.dart' if (dart.library.js_interop) 'network_web.dart' show playsOpus, webProxy;

/// [url] as the app should fetch it: through the proxy on the web when the proxy forwards it, else unchanged.
Uri routed(Uri url) {
  final proxy = webProxy;
  return proxy == null ? url : toProxy(url, proxy) ?? url;
}

/// Where the web build plays [videoId] from: the proxy's audio endpoint, which looks the stream up when the
/// browser first asks for bytes. Null in native builds, which stream through `YoutubeAudioSource`.
Uri? webAudioUri(String videoId) {
  final proxy = webProxy;
  return proxy == null ? null : audioOnProxy(videoId, proxy, aac: !playsOpus);
}
