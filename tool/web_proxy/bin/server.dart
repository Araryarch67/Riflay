import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';

import '../src/proxy.dart';

const _usage = '''
Riflay web proxy: forwards the YouTube Music and lyrics requests a browser may not make itself.

  dart run bin/server.dart [--port 8787] [--host 0.0.0.0] [--web ../../build/web] [--allow-origin <origin>]
                           [--trust-forwarded]

  --port             Port to listen on (or the PORT environment variable). Default 8787.
  --host             Address to listen on. Default 127.0.0.1 (this computer only).
  --web              Also serve the built web app from this folder, so app and proxy share one address.
  --allow-origin     The page origin allowed to call the proxy, such as https://music.example.com. Default *.
  --trust-forwarded  Rate-limit by X-Forwarded-For (only behind your own reverse proxy).
''';

Future<void> main(List<String> args) async {
  String? option(String name) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  if (args.contains('--help') || args.contains('-h')) {
    stdout.write(_usage);
    return;
  }
  final port = int.parse(option('port') ?? Platform.environment['PORT'] ?? '8787');
  final host = option('host') ?? '127.0.0.1';
  final web = option('web');
  final trustForwarded = args.contains('--trust-forwarded');

  final proxy = proxyHandler(
    client: http.Client(),
    limiter: RateLimiter(),
    allowOrigin: option('allow-origin') ?? '*',
    clientIp: trustForwarded
        ? (r) => r.headers['x-forwarded-for']?.split(',').first.trim() ?? r.headers['x-real-ip']
        : null,
  );
  Handler handler = proxy;
  if (web != null) {
    final files = createStaticHandler(web, defaultDocument: 'index.html');
    handler = (request) => switch ('/${request.url.path}') {
      final p when p.startsWith(proxyFetchPrefix) || p.startsWith(proxyAudioPrefix) => proxy(request),
      _ => files(request),
    };
  }
  handler = const Pipeline().addMiddleware(_health).addHandler(handler);

  final server = await io.serve(handler, host, port);
  server.autoCompress = false; // streams carry their own compression; ranges must stay byte-exact
  // Containers stop with SIGTERM; Ctrl+C sends SIGINT.
  for (final signal in [ProcessSignal.sigterm, ProcessSignal.sigint]) {
    if (Platform.isWindows && signal == ProcessSignal.sigterm) continue;
    signal.watch().listen((_) async {
      await server.close(force: true);
      exit(0);
    });
  }
  stdout.writeln(
    'Riflay web proxy on http://${server.address.host}:${server.port}${web == null ? '' : ' (serving $web)'}',
  );
}

Handler _health(Handler inner) =>
    (request) => request.url.path == 'healthz' ? Response.ok('ok') : inner(request);
