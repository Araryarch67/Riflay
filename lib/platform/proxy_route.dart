/// How the web build reaches the services a browser may not call itself, shared by the app (`ProxyClient`) and
/// the proxy server (`tool/web_proxy`). Plain Dart with no imports, so the server can use this file as it is.
///
/// A request for `https://music.youtube.com/youtubei/v1/search?x=1` goes to
/// `<proxy>/fetch/music.youtube.com/youtubei/v1/search?x=1`. Only the hosts and paths below are forwarded: the
/// proxy is not an open relay.
library;

/// Where forwarded requests start on the proxy.
const proxyFetchPrefix = '/fetch/';

/// Where a song's audio starts on the proxy: `<proxy>/audio/<videoId>`, with `?aac=1` for browsers without Opus.
/// The proxy looks the stream up itself and serves it with Range, since an `<audio>` element needs a URL before
/// anything could be resolved.
const proxyAudioPrefix = '/audio/';

final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

/// Whether [id] looks like a YouTube video id.
bool isVideoId(String id) => _videoId.hasMatch(id);

/// The proxy URL that plays [videoId]'s audio.
Uri audioOnProxy(String videoId, Uri proxy, {bool aac = false}) {
  final base = proxy.path.endsWith('/') ? proxy.path.substring(0, proxy.path.length - 1) : proxy.path;
  return proxy.replace(path: '$base$proxyAudioPrefix$videoId', query: aac ? 'aac=1' : null);
}

/// Request headers a browser will not let a page set. The app sends them as `x-riflay-<name>` and the proxy puts
/// them back under their own name.
const renamedRequestHeaders = {'user-agent', 'origin', 'referer', 'cookie'};

/// The prefix of a renamed request header.
const renamedHeaderPrefix = 'x-riflay-';

/// Request headers passed on to the service as they are (lower case); anything else is dropped.
const forwardedRequestHeaders = {
  'accept',
  'accept-language',
  'content-type',
  'range',
  'if-range',
  'x-api-key',
  'x-goog-visitor-id',
  'x-youtube-client-name',
  'x-youtube-client-version',
  'x-origin',
};

/// Response headers passed back to the browser; cookies and the service's own CORS rules stay behind.
const forwardedResponseHeaders = {
  'content-type',
  'content-length',
  'content-range',
  'accept-ranges',
  'cache-control',
  'expires',
  'last-modified',
  'etag',
};

/// The kind of service a host is, which decides what the proxy lets through.
enum ProxiedService {
  /// YouTube and YouTube Music's InnerTube API (and the watch page and oEmbed `youtube_stream` / `ytmusic_web` read).
  youtube,

  /// YouTube's audio and video streams: GET only, with Range.
  media,

  /// Covers and avatars: GET only.
  image,

  /// Lyrics and their translation.
  lyrics,
}

const _exactHosts = {
  'music.youtube.com': ProxiedService.youtube,
  'www.youtube.com': ProxiedService.youtube,
  'i.ytimg.com': ProxiedService.image,
  'lh3.googleusercontent.com': ProxiedService.image,
  'yt3.ggpht.com': ProxiedService.image,
  'yt3.googleusercontent.com': ProxiedService.image,
  'lrclib.net': ProxiedService.lyrics,
  'api.betterlyrics.org': ProxiedService.lyrics,
  'unison.betterlyrics.org': ProxiedService.lyrics,
  'music.163.com': ProxiedService.lyrics,
  'lyrics.kugou.com': ProxiedService.lyrics,
  'c.y.qq.com': ProxiedService.lyrics,
  'apic-desktop.musixmatch.com': ProxiedService.lyrics,
  'genius.com': ProxiedService.lyrics,
  'api.megalobiz.com': ProxiedService.lyrics,
  'api.lyrics.ovh': ProxiedService.lyrics,
  'translate.googleapis.com': ProxiedService.lyrics,
};

/// The service [host] belongs to, or null when the proxy does not forward to it.
ProxiedService? serviceOf(String host) {
  host = host.toLowerCase();
  if (_exactHosts[host] case final s?) return s;
  if (host.endsWith('.googlevideo.com')) return ProxiedService.media;
  return null;
}

/// Whether the proxy forwards [method] to `https://<host><path>`.
bool isForwarded(String method, String host, String path) {
  final service = serviceOf(host);
  return switch (service) {
    null => false,
    ProxiedService.youtube =>
      (method == 'POST' && path.startsWith('/youtubei/v1/')) ||
          (method == 'GET' && (path == '/watch' || path == '/oembed')),
    ProxiedService.media => (method == 'GET' || method == 'HEAD') && path == '/videoplayback',
    ProxiedService.image => method == 'GET' || method == 'HEAD',
    ProxiedService.lyrics => method == 'GET' || method == 'POST',
  };
}

/// [target] as a request to the proxy at [proxy], or null when the proxy would not forward it.
Uri? toProxy(Uri target, Uri proxy, {String method = 'GET'}) {
  if (target.scheme != 'https' || target.hasPort && target.port != 443) return null;
  final path = target.path.isEmpty ? '/' : target.path;
  if (!isForwarded(method, target.host, path)) return null;
  final base = proxy.path.endsWith('/') ? proxy.path.substring(0, proxy.path.length - 1) : proxy.path;
  return proxy.replace(path: '$base$proxyFetchPrefix${target.host}$path', query: target.hasQuery ? target.query : null);
}

/// The service URL a proxy request for [path] (after the proxy's own path, starting with [proxyFetchPrefix]) and
/// [query] stands for, or null when it is not one the proxy forwards.
Uri? fromProxy(String method, String path, String query) {
  if (!path.startsWith(proxyFetchPrefix)) return null;
  final rest = path.substring(proxyFetchPrefix.length);
  final slash = rest.indexOf('/');
  final host = slash < 0 ? rest : rest.substring(0, slash);
  final targetPath = slash < 0 ? '/' : rest.substring(slash);
  if (host.isEmpty || host.contains(':') || host.contains('@')) return null;
  if (!isForwarded(method, host, targetPath)) return null;
  return Uri(scheme: 'https', host: host, path: targetPath, query: query.isEmpty ? null : query);
}
