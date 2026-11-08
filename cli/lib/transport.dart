import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'protocol.dart';

/// One authenticated JSON line per connection, bound only to loopback.
class CliServer {
  CliServer(this.endpoint, this.execute);
  final File endpoint;
  final Future<Object?> Function(String command, Map<String, Object> params) execute;
  ServerSocket? _server;
  RandomAccessFile? _lock;
  final _clients = <Socket>{};
  late String _token;

  Future<void> start() async {
    await endpoint.parent.create(recursive: true);
    if (!Platform.isWindows) {
      final result = await Process.run('chmod', ['700', endpoint.parent.path]);
      if (result.exitCode != 0) throw const CliException('permissions', 'Cannot secure the CLI directory.');
    }
    final lock = await File('${endpoint.path}.lock').open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
    } catch (_) {
      await lock.close();
      throw const CliException('already_running', 'Another Riflay CLI server is running.');
    }
    _lock = lock;
    try {
      final random = Random.secure();
      _token = base64Url.encode(List.generate(32, (_) => random.nextInt(256)));
      final server = _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final part = File('${endpoint.path}.$pid.part');
      try {
        await part.writeAsString(
          jsonEncode({'apiVersion': cliApiVersion, 'port': server.port, 'token': _token}),
          flush: true,
        );
        await part.rename(endpoint.path);
      } finally {
        if (await part.exists()) await part.delete();
      }
      server.listen((socket) {
        if (_clients.length >= 16) {
          socket.destroy();
          return;
        }
        _clients.add(socket);
        // A client may disconnect while a command is still running.
        unawaited(_serve(socket).catchError((Object _) {}));
      });
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<void> _serve(Socket socket) async {
    try {
      final line = await readCliLine(socket, 65536).timeout(const Duration(seconds: 5));
      final raw = jsonDecode(line);
      if (raw is! Map<String, dynamic> || raw['token'] != _token) {
        throw const CliException('unauthorized', 'Invalid CLI credentials.');
      }
      if (raw['apiVersion'] != cliApiVersion) {
        throw const CliException('version_mismatch', 'CLI and app protocol versions differ.');
      }
      final command = raw['command'];
      final spec = cliCommands[command];
      if (spec == null) throw const CliException('unknown_command', 'Unknown CLI command.');
      final params = raw['params'];
      if (params is! Map<String, dynamic>) throw const CliException('invalid_arguments', 'params must be an object.');
      final result = await execute(command as String, spec.validate(params));
      socket.writeln(jsonEncode(cliSuccess(result)));
    } on CliException catch (e) {
      socket.writeln(jsonEncode(cliFailure(e)));
    } on FormatException {
      socket.writeln(jsonEncode(cliFailure(const CliException('invalid_request', 'Expected a JSON request.'))));
    } on TimeoutException {
      socket.writeln(jsonEncode(cliFailure(const CliException('timeout', 'Timed out reading the CLI request.'))));
    } catch (_) {
      socket.writeln(
        jsonEncode(cliFailure(const CliException('command_failed', 'The command failed. Check Riflay and try again.'))),
      );
    } finally {
      try {
        await socket.flush();
        await socket.close();
      } catch (_) {
        // A disconnected client cannot receive a reply.
      } finally {
        socket.destroy();
      }
      _clients.remove(socket);
    }
  }

  Future<void> close() async {
    await _server?.close();
    _server = null;
    for (final socket in _clients.toList()) {
      socket.destroy();
    }
    _clients.clear();
    if (_lock != null) {
      // Do not remove another process's discovery file.
      try {
        final raw = jsonDecode(await endpoint.readAsString());
        if (raw['token'] == _token) await endpoint.delete();
      } catch (_) {}
      await _lock!.close();
      _lock = null;
    }
  }
}

Future<String> readCliLine(Stream<List<int>> stream, int maxBytes) async {
  final bytes = <int>[];
  await for (final chunk in stream) {
    final end = chunk.indexOf(10);
    final part = end < 0 ? chunk : chunk.sublist(0, end);
    if (bytes.length + part.length > maxBytes) {
      throw const CliException('request_too_large', 'CLI message exceeds the size limit.');
    }
    bytes.addAll(part);
    if (end >= 0) return utf8.decode(bytes);
  }
  throw const CliException('connection_closed', 'Connection closed before a complete response.');
}

Future<Map<String, dynamic>> cliRequest(
  File endpoint,
  String command,
  Map<String, Object> params, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  late Map<String, dynamic> config;
  try {
    config = (jsonDecode(await endpoint.readAsString()) as Map).cast<String, dynamic>();
    if (config['apiVersion'] != cliApiVersion) {
      throw const CliException('version_mismatch', 'Update riflay-cli to match the app.');
    }
    if (config['port'] is! int || config['port'] < 1 || config['port'] > 65535 || config['token'] is! String) {
      throw const FormatException();
    }
  } on CliException {
    rethrow;
  } catch (_) {
    throw const CliException(
      'not_running',
      'Open the desktop Riflay app with CLI support first, or pass --endpoint PATH.',
    );
  }
  Socket? socket;
  try {
    socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      config['port'] as int,
      timeout: const Duration(seconds: 2),
    );
    socket.writeln(
      jsonEncode({'apiVersion': cliApiVersion, 'token': config['token'], 'command': command, 'params': params}),
    );
    await socket.flush();
    final response = jsonDecode(await readCliLine(socket, 4 * 1024 * 1024).timeout(timeout));
    if (response is! Map<String, dynamic> || response['apiVersion'] != cliApiVersion || response['ok'] is! bool) {
      throw const CliException('invalid_response', 'Invalid response from Riflay.');
    }
    return response;
  } on SocketException {
    throw const CliException('not_running', 'Cannot reach Riflay. Open the app and try again.');
  } on TimeoutException {
    throw const CliException(
      'timeout',
      'No reply from Riflay. The command may still complete; read status before retrying.',
    );
  } on FormatException {
    throw const CliException('invalid_response', 'Invalid JSON response from Riflay.');
  } finally {
    socket?.destroy();
  }
}

String defaultCliEndpoint() {
  final env = Platform.environment;
  if (env['RIFLAY_CLI_ENDPOINT'] case final String path when path.isNotEmpty) return path;
  final home = env[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ?? '';
  final sep = Platform.pathSeparator;
  final base = Platform.isWindows
      ? '${env['APPDATA'] ?? '$home${sep}AppData${sep}Roaming'}${sep}dev.riflay${sep}riflay'
      : Platform.isMacOS
      ? '$home/Library/Application Support/dev.riflay.riflay'
      : '${env['XDG_DATA_HOME']?.isNotEmpty == true ? env['XDG_DATA_HOME'] : '$home/.local/share'}/dev.riflay.riflay';
  return '$base${sep}cli${sep}endpoint.json';
}
