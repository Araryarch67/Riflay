import 'dart:io';

import 'package:riflay_cli/transport.dart';

import '../services/cli_commands.dart';
import '../services/player_controller.dart';
import '../services/private_files.dart';

class DesktopCli {
  static CliServer? _server;
  static CliCommands? _commands;

  static Future<void> start(PlayerController player) async {
    if (!(Platform.isLinux || Platform.isMacOS || Platform.isWindows) ||
        _server != null ||
        const bool.fromEnvironment('RIFLAY_NO_CLI')) {
      return;
    }
    final commands = CliCommands(player);
    final directory = await PrivateFiles.dir();
    final server = CliServer(File('${directory.path}/cli/endpoint.json'), commands.execute);
    try {
      await server.start();
      _commands = commands;
      _server = server;
    } catch (_) {
      await commands.close();
      rethrow;
    }
  }

  static Future<void> close() async {
    await _server?.close();
    await _commands?.close();
    _server = null;
    _commands = null;
  }
}
