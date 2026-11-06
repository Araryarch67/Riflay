import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'extension_models.dart';
import 'extension_runner.dart';
import '../language.dart';

/// QuickJS (Windows, Linux, Android) or JavaScriptCore (macOS, iOS), through flutter_js.
const jsRuntimeSupported = true;

ExtensionRunner startJsExtension({
  required String dir,
  required ExtensionManifest manifest,
  required String storagePath,
  Map<String, Object?> config = const {},
}) => JsExtensionRunner(dir: dir, manifest: manifest, storagePath: storagePath, config: config);

/// Runs one extension's script in its own isolate.
///
/// SpotiFLAC's scripts call `http.get(...)` and use the answer on the next line: the host API is synchronous. Dart
/// has no blocking HTTP, so the script's isolate hands each request to this (the app's) isolate and sleeps until the
/// answer lands in a file in [_exchange]; renaming the finished file is what says it's complete. Only the script's
/// isolate ever blocks.
class JsExtensionRunner implements ExtensionRunner {
  JsExtensionRunner({
    required this.dir,
    required this.manifest,
    required this.storagePath,
    this.config = const {},
    http.Client? client,
    this.callTimeout = const Duration(seconds: 45),
  }) : _http = client ?? http.Client() {
    _ready = _boot();
  }

  final String dir;
  final ExtensionManifest manifest;
  final String storagePath;
  final Map<String, Object?> config;
  final Duration callTimeout;
  final http.Client _http;

  late final Future<SendPort> _ready;
  final _fromScript = ReceivePort();
  Isolate? _isolate;
  Directory? _exchange;
  final _calls = <int, Completer<Object?>>{};
  var _nextCall = 0;
  var _disposed = false;

  Future<SendPort> _boot() async {
    final script = await File(p.join(dir, 'index.js')).readAsString();
    final exchange = _exchange = await Directory.systemTemp.createTemp('riflay-ext-');
    final booted = Completer<SendPort>();
    _fromScript.listen((m) {
      // An uncaught error in the script's isolate: [error, stack].
      if (m is List && !booted.isCompleted) booted.completeError(ExtensionError('${manifest.displayName}: ${m.first}'));
      if (m is! Map) return;
      switch (m['t']) {
        case 'ready':
          booted.complete(m['port'] as SendPort);
        case 'bootError':
          if (!booted.isCompleted) booted.completeError(ExtensionError('${manifest.displayName}: ${m['error']}'));
        case 'http':
          _fetch(m);
        case 'log':
          debugPrint('[ext ${manifest.id}] ${m['level']}: ${m['message']}');
        case 'result':
          final reply = _calls.remove(m['id']);
          if (reply == null) return;
          final Object? json;
          try {
            json = jsonDecode(m['json'] as String? ?? 'null');
          } catch (e) {
            reply.completeError(ExtensionError(tr.extAnsweredUnreadable(manifest.displayName)));
            return;
          }
          if (json is Map && json['error'] != null) {
            reply.completeError(ExtensionError('${json['error']}'));
          } else {
            reply.complete(json is Map ? json['result'] : null);
          }
      }
    });
    _isolate = await Isolate.spawn(
      _scriptMain,
      _Boot(
        port: _fromScript.sendPort,
        script: script,
        manifest: manifest,
        storagePath: storagePath,
        exchange: exchange.path,
        config: {...manifest.defaultConfig, ...config},
      ),
      debugName: 'extension ${manifest.id}',
      onError: _fromScript.sendPort,
    );
    return booted.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw ExtensionError('${manifest.displayName} took too long to start'),
    );
  }

  /// Does one request for the script and leaves the answer where it waits for it.
  Future<void> _fetch(Map m) async {
    final file = m['file'] as String;
    Map<String, Object?> answer;
    try {
      final req = http.Request(m['method'] as String? ?? 'GET', Uri.parse(m['url'] as String))
        ..followRedirects = true
        ..headers.addAll({for (final e in (m['headers'] as Map? ?? const {}).entries) '${e.key}': '${e.value}'});
      if (m['body'] case final String body when body.isNotEmpty) req.body = body;
      final res = await http.Response.fromStream(await _http.send(req)).timeout(manifest.networkTimeout);
      answer = {
        'statusCode': res.statusCode,
        'body': utf8.decode(res.bodyBytes, allowMalformed: true),
        'headers': res.headers,
        'url': res.request?.url.toString() ?? m['url'],
      };
    } catch (e) {
      answer = {'statusCode': 0, 'body': '', 'headers': const {}, 'url': m['url'], 'error': '$e'};
    }
    try {
      final part = File('$file.part');
      await part.writeAsString(jsonEncode(answer), flush: true);
      await part.rename(file);
    } catch (e) {
      debugPrint('Extension ${manifest.id}: answer not handed over: $e');
    }
  }

  Future<Object?> _call(String fn, List<Object?> args) async {
    if (_disposed) throw ExtensionError(tr.extStopped(manifest.displayName));
    final port = await _ready;
    final id = _nextCall++;
    final reply = _calls[id] = Completer<Object?>();
    port.send({'id': id, 'fn': fn, 'args': jsonEncode(args)});
    return reply.future.timeout(
      callTimeout,
      onTimeout: () {
        _calls.remove(id);
        throw ExtensionError('${manifest.displayName} didn\'t answer in time');
      },
    );
  }

  @override
  Future<List<ExtensionSearchHit>> search(String query, {int limit = 20}) async {
    Object? result;
    try {
      result = await _call('customSearch', [
        query,
        {'limit': limit, 'offset': 0, 'filter': 'tracks'},
      ]);
    } on ExtensionError catch (e) {
      if (!e.message.startsWith('missing ')) rethrow;
      result = await _call('searchTracks', [query, limit]);
    }
    return ExtensionSearchHit.parseList(result, extensionId: manifest.id).where((h) => h.isTrack).toList();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      (await _ready.timeout(const Duration(seconds: 2))).send('stop');
      await Future<void>.delayed(const Duration(milliseconds: 200));
    } catch (_) {
      // It never started.
    }
    _isolate?.kill(priority: Isolate.immediate);
    _fromScript.close();
    for (final c in _calls.values) {
      c.completeError(ExtensionError(tr.extStopped(manifest.displayName)));
    }
    _calls.clear();
    try {
      await _exchange?.delete(recursive: true);
    } catch (_) {}
    _http.close();
  }
}

class _Boot {
  const _Boot({
    required this.port,
    required this.script,
    required this.manifest,
    required this.storagePath,
    required this.exchange,
    required this.config,
  });
  final SendPort port;
  final String script;
  final ExtensionManifest manifest;
  final String storagePath;
  final String exchange;
  final Map<String, Object?> config;
}

/// The script's isolate: the JS engine, the host API it calls, and the calls from the app.
void _scriptMain(_Boot b) {
  final calls = ReceivePort();
  final host = ExtensionHost(
    manifest: b.manifest,
    storagePath: b.storagePath,
    exchange: b.exchange,
    toApp: b.port.send,
  );
  final JavascriptRuntime js;
  try {
    js = getJavascriptRuntime(xhr: false);
    js.onMessage('riflay', (args) => host.handle(args));
    _check(js.evaluate(hostShim, sourceUrl: 'riflay-host.js'));
    _check(js.evaluate(b.script, sourceUrl: '${b.manifest.id}/index.js'));
    final registered = js.evaluate('typeof __riflayExt === "object" && __riflayExt !== null').stringResult;
    if (registered != 'true') throw const ExtensionError('it never called registerExtension');
    final init = js.evaluate('__riflayCall("initialize", ${jsonEncode(jsonEncode([b.config]))}, true)').stringResult;
    if (jsonDecode(init) case {'error': final Object error}) throw ExtensionError('initialize failed: $error');
  } catch (e) {
    b.port.send({'t': 'bootError', 'error': '$e'});
    calls.close();
    return;
  }
  b.port.send({'t': 'ready', 'port': calls.sendPort});
  calls.listen((m) {
    if (m == 'stop') {
      js.evaluate('__riflayCall("cleanup", "[]", true)');
      js.dispose();
      calls.close();
      return;
    }
    if (m is! Map) return;
    final out = js.evaluate('__riflayCall(${jsonEncode(m['fn'])}, ${jsonEncode(m['args'])}, false)');
    b.port.send({
      't': 'result',
      'id': m['id'],
      'json': out.isError ? jsonEncode({'error': out.stringResult}) : out.stringResult,
    });
  });
}

void _check(JsEvalResult r) {
  if (r.isError) throw ExtensionError(r.stringResult);
}

/// What a script's `http`, `storage`, `log` and `utils` calls reach, inside the script's isolate. Each call is
/// `{op, ...}` and answers a JSON string.
@visibleForTesting
class ExtensionHost {
  ExtensionHost({
    required this.manifest,
    required this.storagePath,
    required this.exchange,
    required this.toApp,
    this.pollLimit = const Duration(milliseconds: 8),
  });

  final ExtensionManifest manifest;
  final String storagePath;
  final String exchange;
  final void Function(Object? message) toApp;
  final Duration pollLimit;
  var _seq = 0;
  Map<String, Object?>? _storage;

  String handle(Object? args) {
    if (args is! Map) return 'null';
    try {
      return switch (args['op']) {
        'http' => _http(args),
        'storageGet' => jsonEncode(_store[args['key']]),
        'storageSet' => _storageSet('${args['key']}', args['value']),
        'storageRemove' => _storageSet('${args['key']}', null),
        'log' => _log(args),
        'sleep' => _sleep(args['ms']),
        'hash' => jsonEncode(hash('${args['algo']}', args['data'], key: args['key'])),
        _ => jsonEncode({'error': 'Riflay doesn\'t offer ${args['op']} yet'}),
      };
    } catch (e) {
      return jsonEncode({'error': '$e'});
    }
  }

  String _http(Map args) {
    final url = Uri.tryParse('${args['url']}');
    if (url == null || !manifest.allows(url)) {
      return jsonEncode({
        'statusCode': 0,
        'body': '',
        'headers': const {},
        'url': '${args['url']}',
        'error': 'blocked: ${url?.host ?? args['url']} is not in the extension\'s network permissions',
      });
    }
    final file = File(p.join(exchange, '${_seq++}.json'));
    toApp({
      't': 'http',
      'file': file.path,
      'method': '${args['method'] ?? 'GET'}'.toUpperCase(),
      'url': url.toString(),
      'headers': args['headers'] is Map ? args['headers'] : const {},
      'body': args['body'] is String ? args['body'] : null,
    });
    final deadline = DateTime.now().add(manifest.networkTimeout + const Duration(seconds: 5));
    var wait = const Duration(milliseconds: 1);
    while (!file.existsSync()) {
      if (DateTime.now().isAfter(deadline)) {
        return jsonEncode({'statusCode': 0, 'body': '', 'headers': const {}, 'url': '$url', 'error': 'timed out'});
      }
      sleep(wait);
      if (wait < pollLimit) wait *= 2;
    }
    // Windows can still hold the file a moment after the rename (an antivirus scan): try again briefly.
    for (var tries = 0; ; tries++) {
      try {
        final answer = file.readAsStringSync();
        try {
          file.deleteSync();
        } on FileSystemException {
          // Left for the folder's own clean-up.
        }
        return answer;
      } on FileSystemException {
        if (tries >= 50) rethrow;
        sleep(const Duration(milliseconds: 10));
      }
    }
  }

  Map<String, Object?> get _store {
    if (_storage case final s?) return s;
    try {
      final f = File(storagePath);
      if (f.existsSync()) {
        if (jsonDecode(f.readAsStringSync()) case final Map<String, Object?> m) return _storage = m;
      }
    } catch (_) {
      // A broken file starts afresh.
    }
    return _storage = {};
  }

  String _storageSet(String key, Object? value) {
    value == null ? _store.remove(key) : _store[key] = value;
    final f = File(storagePath);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(jsonEncode(_store));
    return 'true';
  }

  String _log(Map args) {
    toApp({'t': 'log', 'level': args['level'] ?? 'info', 'message': args['message'] ?? ''});
    return 'null';
  }

  String _sleep(Object? ms) {
    final n = ms is num ? ms.toInt().clamp(0, 10000) : 0;
    if (n > 0) sleep(Duration(milliseconds: n));
    return 'true';
  }

  /// `utils.sha256` / `md5` / `sha1` / `hmacSHA1` / `hmacSHA256`: of text, as lower-case hex; of bytes (a list of
  /// numbers, as Spotify's TOTP passes), as bytes.
  static Object hash(String algo, Object? data, {Object? key}) {
    List<int> bytesOf(Object? v) =>
        v is List ? [for (final b in v) (b as num).toInt() & 0xff] : utf8.encode('${v ?? ''}');
    final bytes = bytesOf(data);
    final digest = switch (algo) {
      'sha256' => sha256.convert(bytes),
      'sha1' => sha1.convert(bytes),
      'md5' => md5.convert(bytes),
      'hmacSHA1' => Hmac(sha1, bytesOf(key)).convert(bytes),
      'hmacSHA256' => Hmac(sha256, bytesOf(key)).convert(bytes),
      _ => throw ArgumentError('unknown hash $algo'),
    };
    return data is List ? digest.bytes : digest.toString();
  }
}

/// A user agent like a recent desktop browser.
@visibleForTesting
String randomUserAgent([Random? random]) {
  final r = random ?? Random();
  final chrome = 128 + r.nextInt(10);
  return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/$chrome.0.0.0 Safari/537.36';
}

/// The globals SpotiFLAC's scripts expect, built on one synchronous `sendMessage('riflay', json)`.
@visibleForTesting
final hostShim =
    '''
(function (g) {
  function host(op, data) {
    data = data || {};
    data.op = op;
    var r = sendMessage('riflay', JSON.stringify(data));
    if (typeof r !== 'string') return r === undefined ? null : r;
    return r === '' ? null : JSON.parse(r);
  }
  function text(v) { return v == null ? '' : (typeof v === 'string' ? v : JSON.stringify(v)); }
  function answer(r) {
    r = r || { statusCode: 0, body: '', headers: {}, error: 'no response' };
    r.status = r.statusCode;
    r.ok = r.statusCode >= 200 && r.statusCode < 300;
    r.text = function () { return r.body; };
    r.json = function () { return JSON.parse(r.body); };
    return r;
  }
  function req(method, url, body, headers) {
    return answer(host('http', { method: method, url: String(url), body: body == null ? null : text(body), headers: headers || {} }));
  }
  g.http = {
    get: function (url, headers) { return req('GET', url, null, headers); },
    post: function (url, body, headers) { return req('POST', url, body, headers); },
    put: function (url, body, headers) { return req('PUT', url, body, headers); },
    delete: function (url, headers) { return req('DELETE', url, null, headers); },
    request: function (url, options) {
      options = options || {};
      return req(options.method || 'GET', url, options.body, options.headers);
    }
  };
  // SpotiFLAC's fetch answers at once, like http.request (no promise).
  g.fetch = function (url, options) {
    options = options || {};
    return req(options.method || 'GET', url, options.body, options.headers);
  };
  g.storage = {
    get: function (key, fallback) { var v = host('storageGet', { key: String(key) }); return v == null && fallback !== undefined ? fallback : v; },
    set: function (key, value) { host('storageSet', { key: String(key), value: value === undefined ? null : value }); return true; },
    remove: function (key) { host('storageRemove', { key: String(key) }); return true; }
  };
  function logAt(level) {
    return function () {
      var parts = [];
      for (var i = 0; i < arguments.length; i++) parts.push(typeof arguments[i] === 'string' ? arguments[i] : text(arguments[i]));
      host('log', { level: level, message: parts.join(' ') });
    };
  }
  g.log = { debug: logAt('debug'), info: logAt('info'), warn: logAt('warn'), error: logAt('error') };
  var agent = ${jsonEncode(randomUserAgent())};
  function raw(v) {
    if (v == null) return null;
    if (typeof v !== 'string' && typeof v.length === 'number') return Array.prototype.slice.call(v);
    return text(v);
  }
  function hash(algo) { return function (data, key) { return host('hash', { algo: algo, data: raw(data), key: raw(key) }); }; }
  g.utils = {
    randomUserAgent: function () { return agent; },
    appUserAgent: function () { return 'Riflay'; },
    appVersion: function () { return 'riflay'; },
    sleep: function (ms) { return host('sleep', { ms: Number(ms) || 0 }) !== false; },
    isDownloadCancelled: function () { return false; },
    isRequestCancelled: function () { return false; },
    getResolutionRemainingMs: function () { return 30000; },
    sha256: hash('sha256'), sha1: hash('sha1'), md5: hash('md5'),
    hmacSHA1: hash('hmacSHA1'), hmacSHA256: hash('hmacSHA256')
  };
  function norm(s) {
    s = String(s || '').toLowerCase();
    if (s.normalize) s = s.normalize('NFKD').replace(/[\u0300-\u036f]/g, '');
    return s.replace(/[^a-z0-9\u00c0-\uffff]+/g, ' ').trim();
  }
  function similarity(a, b) {
    a = norm(a); b = norm(b);
    if (a === b) return 1;
    if (!a.length || !b.length) return 0;
    var prev = [], cur, i, j;
    for (j = 0; j <= b.length; j++) prev.push(j);
    for (i = 1; i <= a.length; i++) {
      cur = [i];
      for (j = 1; j <= b.length; j++) cur.push(Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1)));
      prev = cur;
    }
    return 1 - prev[b.length] / Math.max(a.length, b.length);
  }
  g.matching = {
    normalizeString: norm,
    compareStrings: similarity,
    compareDuration: function (a, b, tolerance) { return Math.abs(Number(a || 0) - Number(b || 0)) <= (tolerance == null ? 3000 : Number(tolerance)); }
  };
  g.gobackend = { getLocalTime: function () { return new Date().toISOString(); } };
  function missing(name) { return function () { throw new Error(name + ' is not available in Riflay yet'); }; }
  g.file = { download: missing('file.download'), downloadSegments: missing('file.downloadSegments'), delete: function () { return false; }, exists: function () { return false; } };
  g.ffmpeg = { convert: missing('ffmpeg.convert') };
  var b64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
  if (typeof g.btoa !== 'function') g.btoa = function (s) {
    s = String(s); var out = '', i = 0, a, b, c;
    while (i < s.length) {
      a = s.charCodeAt(i++); b = s.charCodeAt(i++); c = s.charCodeAt(i++);
      out += b64.charAt(a >> 2) + b64.charAt(((a & 3) << 4) | (b >> 4)) +
        (isNaN(b) ? '=' : b64.charAt(((b & 15) << 2) | (c >> 6))) + (isNaN(c) ? '=' : b64.charAt(c & 63));
    }
    return out;
  };
  if (typeof g.atob !== 'function') g.atob = function (s) {
    s = String(s).replace(/[^A-Za-z0-9+\\/]/g, ''); var out = '', i = 0, a, b, c, d;
    while (i < s.length) {
      a = b64.indexOf(s.charAt(i++)); b = b64.indexOf(s.charAt(i++)); c = b64.indexOf(s.charAt(i++)); d = b64.indexOf(s.charAt(i++));
      out += String.fromCharCode((a << 2) | (b >> 4));
      if (c >= 0 && c < 64) out += String.fromCharCode(((b & 15) << 4) | (c >> 2));
      if (d >= 0 && d < 64) out += String.fromCharCode(((c & 3) << 6) | d);
    }
    return out;
  };
  if (typeof g.URLSearchParams !== 'function') {
    var Params = function (init) {
      this._p = [];
      init = String(init || '').replace(/^\\?/, '');
      if (init) init.split('&').forEach(function (kv) {
        var i = kv.indexOf('='), k = i < 0 ? kv : kv.slice(0, i), v = i < 0 ? '' : kv.slice(i + 1);
        this._p.push([decodeURIComponent(k.replace(/\\+/g, ' ')), decodeURIComponent(v.replace(/\\+/g, ' '))]);
      }, this);
    };
    Params.prototype.get = function (k) { for (var i = 0; i < this._p.length; i++) if (this._p[i][0] === k) return this._p[i][1]; return null; };
    Params.prototype.has = function (k) { return this.get(k) !== null; };
    Params.prototype.append = function (k, v) { this._p.push([String(k), String(v)]); };
    Params.prototype.set = function (k, v) { this.delete(k); this.append(k, v); };
    Params.prototype.delete = function (k) { this._p = this._p.filter(function (e) { return e[0] !== k; }); };
    Params.prototype.forEach = function (f, t) { this._p.forEach(function (e) { f.call(t, e[1], e[0], this); }, this); };
    Params.prototype.toString = function () { return this._p.map(function (e) { return encodeURIComponent(e[0]) + '=' + encodeURIComponent(e[1]); }).join('&'); };
    g.URLSearchParams = Params;
  }
  if (typeof g.URL !== 'function') {
    var Url = function (url, base) {
      url = String(url);
      if (base && !/^[a-z][a-z0-9+.-]*:/i.test(url)) {
        var b = new Url(base);
        url = url.charAt(0) === '/' ? b.origin + url : b.origin + b.pathname.replace(/[^\\/]*\$/, '') + url;
      }
      var m = /^([a-z][a-z0-9+.-]*:)\\/\\/([^\\/?#]*)([^?#]*)(\\?[^#]*)?(#.*)?\$/i.exec(url);
      if (!m) throw new TypeError('Invalid URL: ' + url);
      this.protocol = m[1].toLowerCase(); this.host = m[2]; this.hostname = m[2].replace(/:\\d+\$/, '');
      this.port = (/:(\\d+)\$/.exec(m[2]) || [])[1] || ''; this.pathname = m[3] || '/';
      this.search = m[4] && m[4] !== '?' ? m[4] : ''; this.hash = m[5] || '';
      this.origin = this.protocol + '//' + this.host; this.searchParams = new g.URLSearchParams(this.search);
    };
    Url.prototype.toString = function () {
      var q = this.searchParams.toString();
      return this.origin + this.pathname + (q ? '?' + q : '') + this.hash;
    };
    Object.defineProperty(Url.prototype, 'href', { get: function () { return this.toString(); } });
    g.URL = Url;
  }
  g.registerExtension = function (ext) { g.__riflayExt = ext; };
  g.__riflayCall = function (name, args, optional) {
    var ext = g.__riflayExt, f = ext && ext[name];
    if (typeof f !== 'function') return JSON.stringify(optional ? { result: null } : { error: 'missing ' + name });
    try {
      var r = f.apply(ext, JSON.parse(args));
      return JSON.stringify({ result: r === undefined ? null : r });
    } catch (e) {
      return JSON.stringify({ error: String((e && e.message) || e) });
    }
  };
})(this);
''';
