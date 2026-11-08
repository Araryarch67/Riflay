import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay_cli/protocol.dart';
import 'package:riflay_cli/transport.dart';

void main() {
  late Directory directory;
  late File endpoint;
  late CliServer server;
  late List<String> calls;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('riflay-cli-test-');
    endpoint = File('${directory.path}/private/endpoint.json');
    calls = [];
    server = CliServer(endpoint, (command, params) async {
      calls.add(command);
      if (command == 'pause') throw const CliException('test_failure', 'Cannot pause.');
      return {'command': command, 'params': params};
    });
    await server.start();
  });
  tearDown(() async {
    await server.close();
    await directory.delete(recursive: true);
  });

  test('authenticated requests round trip and apply defaults', () async {
    final response = await cliRequest(endpoint, 'search', {'query': 'hello'});
    expect(response['ok'], true);
    expect(response['result']['params'], {'query': 'hello', 'source': 'library', 'limit': 20, 'offset': 0});
    expect(calls, ['search']);
    if (Platform.isLinux || Platform.isMacOS) {
      expect((await endpoint.parent.stat()).mode & 0x1ff, 0x1c0, reason: 'discovery directory is private (0700)');
    }
  });

  Future<Map<String, dynamic>> rawRequest(Map<String, Object?> payload) async {
    final config = jsonDecode(await endpoint.readAsString());
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, config['port'] as int);
    try {
      socket.writeln(jsonEncode(payload));
      await socket.flush();
      return jsonDecode(await readCliLine(socket, 65536)) as Map<String, dynamic>;
    } finally {
      socket.destroy();
    }
  }

  test('wrong credentials never execute a command', () async {
    final response = await rawRequest({'apiVersion': 1, 'token': 'wrong', 'command': 'stop', 'params': {}});
    expect(response['error']['code'], 'unauthorized');
    expect(calls, isEmpty);
  });

  test('unknown commands, invalid versions and bad parameters cannot mutate playback', () async {
    final config = jsonDecode(await endpoint.readAsString());
    for (final payload in [
      {'apiVersion': 2, 'command': 'stop', 'params': {}},
      {'apiVersion': 1, 'command': 'delete-everything', 'params': {}},
      {
        'apiVersion': 1,
        'command': 'volume',
        'params': {'value': 101},
      },
      {
        'apiVersion': 1,
        'command': 'queue.remove',
        'params': {'index': -1},
      },
      {
        'apiVersion': 1,
        'command': 'search',
        'params': {'query': 'hello', 'limit': 101},
      },
      {
        'apiVersion': 1,
        'command': 'pause',
        'params': {'unknown': true},
      },
    ]) {
      final response = await rawRequest({...payload, 'token': config['token']});
      expect(response['ok'], false);
    }
    expect(calls, isEmpty);
  });

  test('app failures remain structured and subsequent requests work', () async {
    final response = await cliRequest(endpoint, 'pause', {});
    expect(response['error']['code'], 'test_failure');
    expect((await cliRequest(endpoint, 'status', {}))['ok'], true);
  });

  test('closed servers remove discovery and unavailable apps give actionable errors', () async {
    await server.close();
    expect(await endpoint.exists(), false);
    await expectLater(
      cliRequest(endpoint, 'status', {}),
      throwsA(isA<CliException>().having((e) => e.code, 'code', 'not_running')),
    );
  });

  test('standalone CLI can discover commands, validate arguments and talk to the server', () async {
    // Use the standalone package's configuration; the app has native Flutter build hooks.
    Future<ProcessResult> run(List<String> args) =>
        Process.run('dart', ['bin/riflay_cli.dart', ...args], workingDirectory: 'cli');
    final schema = await run(['schema']);
    expect(schema.exitCode, 0, reason: '${schema.stderr}');
    expect(jsonDecode(schema.stdout as String)['result']['commands'], contains('queue add'));
    final invalid = await run(['volume', 'NaN']);
    expect(invalid.exitCode, 2);
    expect(jsonDecode(invalid.stdout as String)['error']['code'], 'invalid_arguments');
    final status = await run(['--endpoint', endpoint.path, 'status']);
    expect(status.exitCode, 0, reason: '${status.stdout}\n${status.stderr}');
    expect(jsonDecode(status.stdout as String)['result']['command'], 'status');
    final search = await run([
      'search',
      'artist - title',
      '--endpoint',
      endpoint.path,
      '--source=youtube',
      '--limit',
      '5',
    ]);
    expect(search.exitCode, 0);
    expect(jsonDecode(search.stdout as String)['result']['params']['query'], 'artist - title');
    final failure = await run(['pause', '--endpoint', endpoint.path]);
    expect(failure.exitCode, 5);
    final missing = await run(['status', '--endpoint', '${directory.path}/absent']);
    expect(missing.exitCode, 3);
  });
}
