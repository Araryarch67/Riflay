import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Computers: `riflay <link>` while Riflay already runs gives the link to that copy instead of opening a
// second window. The running copy listens on a loopback port and writes it, with a random token, to
// `<app support dir>/open-links`; the new process sends `token\nlink…` there and quits. Without the token
// (another user, a web page knocking on local ports) nothing is read. Phones have their own way in.

bool get _computer => Platform.isLinux || Platform.isWindows || Platform.isMacOS;

Future<File> _portFile() async => File(p.join((await getApplicationSupportDirectory()).path, 'open-links'));

Future<void> handOffToRunningCopy(List<String> links) async {
  if (!_computer || links.isEmpty) return;
  try {
    final file = await _portFile();
    if (!file.existsSync()) return;
    final [port, token, ...] = (await file.readAsString()).split('\n');
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      int.parse(port),
      timeout: const Duration(milliseconds: 500),
    );
    socket.write([token, ...links].join('\n'));
    await socket.flush();
    await socket.close();
    exit(0);
  } catch (e) {
    // No copy running (a port file left from a crash), or it didn't answer: this one opens the link.
    debugPrint('Open links: no running copy ($e)');
  }
}

Future<void> listenForHandOffs(void Function(String text) onLink) async {
  if (!_computer) return;
  try {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final random = Random.secure();
    final token = base64Url.encode([for (var i = 0; i < 24; i++) random.nextInt(256)]);
    await (await _portFile()).writeAsString('${server.port}\n$token');
    server.listen((socket) async {
      try {
        final text = await utf8.decoder
            .bind(socket)
            .fold('', (all, part) => all.length > 64 * 1024 ? all : all + part)
            .timeout(const Duration(seconds: 5));
        final [given, ...links] = text.split('\n');
        if (given == token) links.forEach(onLink);
      } catch (e) {
        debugPrint('Open links: $e');
      } finally {
        socket.destroy();
      }
    });
  } catch (e) {
    debugPrint('Open links: not listening ($e)');
  }
}

/// Only the web page has an address to read.
List<String> pageLinks() => const [];
