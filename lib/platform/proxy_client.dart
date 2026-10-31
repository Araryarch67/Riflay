import 'package:http/http.dart' as http;

import 'proxy_route.dart';

/// An HTTP client that sends what the web build may not ask for itself through Riflay's proxy (see
/// `proxy_route.dart` and `tool/web_proxy`). Requests the proxy does not forward go to [inner] unchanged.
class ProxyClient extends http.BaseClient {
  ProxyClient(this._inner, this.proxy);

  final http.Client _inner;

  /// The proxy's address, such as `http://localhost:8787/`.
  final Uri proxy;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final target = toProxy(request.url, proxy, method: request.method);
    if (target == null) return _inner.send(request);
    final out = http.Request(request.method, target)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection
      ..bodyBytes = await request.finalize().toBytes();
    request.headers.forEach((name, value) {
      final lower = name.toLowerCase();
      if (lower == 'content-length') return;
      out.headers[renamedRequestHeaders.contains(lower) ? '$renamedHeaderPrefix$lower' : lower] = value;
    });
    return _inner.send(out);
  }

  @override
  void close() => _inner.close();
}
