import 'dart:convert';
import 'dart:io';

import 'package:riflay_cli/protocol.dart';
import 'package:riflay_cli/transport.dart';

Future<void> main(List<String> args) async {
  var pretty = false;
  try {
    if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
      stdout.writeln(
        'riflay-cli — control the running desktop Riflay app\n'
        'Usage: riflay-cli COMMAND [ARG] [--option VALUE]\n'
        'Output: JSON by default. Use schema for machine-readable command discovery.\n'
        'Global options: --endpoint PATH, --timeout SECONDS (1–600), --pretty, --json\n',
      );
      for (final entry in cliCommands.entries) {
        stdout.writeln('  ${entry.key.replaceAll('.', ' ').padRight(17)} ${entry.value.description}');
      }
      stdout.writeln(
        '  schema            Describe all commands and parameters (works offline).\n'
        '\nExamples:\n  riflay-cli search "Nujabes" --source youtube\n'
        '  riflay-cli play "yt:VIDEO_ID"\n  riflay-cli volume 40\n  riflay-cli queue --limit 20\n'
        '\nExit codes: 0 success, 2 arguments, 3 app unavailable, 4 transport error, 5 app command error.',
      );
      return;
    }
    var endpoint = defaultCliEndpoint();
    var timeout = const Duration(seconds: 60);
    final words = <String>[];
    final options = <String, String>{};
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--pretty') {
        pretty = true;
      } else if (arg == '--json') {
        // JSON is also the default, so agents never need to scrape text.
      } else if (arg.startsWith('--')) {
        final split = arg.indexOf('=');
        final key = split < 0 ? arg.substring(2) : arg.substring(2, split);
        final String value;
        if (split >= 0) {
          value = arg.substring(split + 1);
        } else {
          if (++i >= args.length || args[i].startsWith('--')) {
            throw CliException('invalid_arguments', 'Missing value for --$key.');
          }
          value = args[i];
        }
        if (key == 'endpoint') {
          endpoint = value;
        } else if (key == 'timeout') {
          final seconds = int.tryParse(value);
          if (seconds == null || seconds < 1 || seconds > 600) {
            throw const CliException('invalid_arguments', '--timeout must be 1–600 seconds.');
          }
          timeout = Duration(seconds: seconds);
        } else {
          if (options.containsKey(key)) throw CliException('invalid_arguments', 'Duplicate option --$key.');
          options[key] = value;
        }
      } else {
        words.add(arg);
      }
    }
    if (words.length == 1 && words.single == 'schema' && options.isEmpty) {
      _print(cliSuccess(cliSchema()), pretty);
      return;
    }
    if (words.isEmpty) throw const CliException('invalid_arguments', 'Missing command. Run riflay-cli --help.');
    var command = words.removeAt(0);
    if (words.isNotEmpty && cliCommands.containsKey('$command.${words.first}')) {
      command = '$command.${words.removeAt(0)}';
    }
    final spec = cliCommands[command];
    if (spec == null) throw CliException('invalid_arguments', 'Unknown command: $command. Run riflay-cli schema.');
    if (words.isNotEmpty) {
      if (words.length != 1 || spec.positional == null || options.containsKey(spec.positional)) {
        throw const CliException('invalid_arguments', 'Unexpected arguments. Quote multiword queries and ids.');
      }
      options[spec.positional!] = words.single;
    }
    final params = spec.validate(options);
    final response = await cliRequest(File(endpoint), command, params, timeout: timeout);
    _print(response, pretty);
    if (response['ok'] != true) exitCode = 5;
  } on CliException catch (e) {
    _print(cliFailure(e), pretty);
    exitCode = switch (e.code) {
      'invalid_arguments' => 2,
      'not_running' => 3,
      _ => 4,
    };
  } catch (_) {
    _print(cliFailure(const CliException('cli_failed', 'Could not complete the CLI request.')), pretty);
    exitCode = 4;
  }
}

void _print(Object response, bool pretty) =>
    stdout.writeln((pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder()).convert(response));
