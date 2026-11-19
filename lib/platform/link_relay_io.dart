import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/private_files.dart';

bool get _computer => Platform.isLinux || Platform.isWindows || Platform.isMacOS;

// Kept open for the process lifetime. The OS releases the lock even after a crash.
RandomAccessFile? _instanceLock;

Future<void> startDesktopRelay(
  List<String> links, {
  required void Function(String text) onLink,
  required VoidCallback onActivate,
}) async {
  if (!_computer || _instanceLock != null) return;
  RandomAccessFile? candidate;
  ServerSocket? server;
  try {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final name = kReleaseMode ? 'open-links' : 'open-links-dev';
    final endpoint = File(p.join(directory.path, name));
    if (kReleaseMode) {
      candidate = await File('${endpoint.path}.lock').open(mode: FileMode.append);
      try {
        await candidate.lock(FileLock.exclusive, 0, 1);
      } on FileSystemException {
        await candidate.close();
        // The owner may still be writing its endpoint on a simultaneous launch.
        await _relay(endpoint, links, waitForOwner: true);
        exit(0);
      }
      _instanceLock = candidate;
    } else if (links.isNotEmpty && await _relay(endpoint, links)) {
      exit(0);
    }

    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final random = Random.secure();
    final token = base64Url.encode([for (var i = 0; i < 24; i++) random.nextInt(256)]);
    server.listen((socket) => _accept(socket, token, onLink, onActivate));
    await PrivateFiles.write(endpoint, '${server.port}\n$token');
  } catch (error) {
    await server?.close();
    debugPrint('Desktop activation unavailable: $error');
  }
}

Future<bool> _relay(File endpoint, List<String> links, {bool waitForOwner = false}) async {
  final until = DateTime.now().add(const Duration(seconds: 4));
  do {
    Socket? socket;
    try {
      final [port, token] = (await endpoint.readAsString()).split('\n');
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        int.parse(port),
        timeout: const Duration(milliseconds: 300),
      );
      socket.writeln(jsonEncode([token, ...links]));
      await socket.flush();
      final reply = await _line(socket).timeout(const Duration(milliseconds: 450));
      if (reply == 'ok $token') return true;
    } catch (_) {
      // The endpoint can be absent or left behind by a previous process.
    } finally {
      socket?.destroy();
    }
    if (!waitForOwner || DateTime.now().isAfter(until)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 80));
  } while (true);
}

Future<String> _line(Socket socket) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in socket) {
    final newline = chunk.indexOf(10);
    final length = newline < 0 ? chunk.length : newline;
    if (bytes.length + length > 64 * 1024) throw const FormatException('Relay message too large');
    bytes.add(newline < 0 ? chunk : chunk.sublist(0, newline));
    if (newline >= 0) return utf8.decode(bytes.takeBytes());
  }
  throw const FormatException('Incomplete relay message');
}

Future<void> _accept(Socket socket, String token, void Function(String) onLink, VoidCallback onActivate) async {
  try {
    final message = jsonDecode(await _line(socket).timeout(const Duration(seconds: 3)));
    if (message is! List || message.isEmpty || message.first != token) return;
    socket.writeln('ok $token');
    await socket.flush();
    onActivate();
    for (final link in message.skip(1).whereType<String>()) {
      onLink(link);
    }
  } catch (error) {
    debugPrint('Desktop activation: $error');
  } finally {
    socket.destroy();
  }
}

List<String> pageLinks() => const [];
