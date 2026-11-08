/// Shared by the standalone executable and the app; no Flutter dependencies.
library;

const cliApiVersion = 1;

class CliException implements Exception {
  const CliException(this.code, this.message);
  final String code;
  final String message;
  Map<String, Object> toJson() => {'code': code, 'message': message};
  @override
  String toString() => message;
}

class CliParameter {
  const CliParameter(this.type, {this.required = false, this.values, this.min, this.max, this.fallback});
  final String type;
  final bool required;
  final List<String>? values;
  final num? min;
  final num? max;
  final Object? fallback;

  Object parse(String name, Object raw) {
    final Object? value = switch (type) {
      'integer' => raw is int ? raw : (raw is String ? int.tryParse(raw) : null),
      'number' => raw is num ? raw : (raw is String ? num.tryParse(raw) : null),
      _ => raw is String && raw.trim().isNotEmpty ? raw : null,
    };
    if (value == null ||
        (value is num && (!value.isFinite || (min != null && value < min!) || (max != null && value > max!))) ||
        (values != null && !values!.contains(value))) {
      throw CliException(
        'invalid_arguments',
        'Invalid $name. Expected $type${values == null ? '' : ' (${values!.join(', ')})'}'
            '${min == null ? '' : ', minimum $min'}${max == null ? '' : ', maximum $max'}.',
      );
    }
    if (value is String && value.length > 4096) throw CliException('invalid_arguments', '$name is too long.');
    return value;
  }

  Map<String, Object?> toJson() => {
    'type': type,
    'required': required,
    if (values != null) 'enum': values,
    if (min != null) 'minimum': min,
    if (max != null) 'maximum': max,
    if (fallback != null) 'default': fallback,
  };
}

class CliCommand {
  const CliCommand(this.description, {this.positional, this.mutates = false, this.parameters = const {}});
  final String description;
  final String? positional;
  final bool mutates;
  final Map<String, CliParameter> parameters;

  Map<String, Object> validate(Map<String, dynamic> input) {
    for (final key in input.keys) {
      if (!parameters.containsKey(key)) throw CliException('invalid_arguments', 'Unknown parameter: $key.');
    }
    return {
      for (final entry in parameters.entries)
        if (input[entry.key] case final value?)
          entry.key: entry.value.parse(entry.key, value)
        else if (entry.value.required)
          entry.key: throw CliException('invalid_arguments', 'Missing ${entry.key}.')
        else
          entry.key: ?entry.value.fallback,
    };
  }

  Map<String, Object?> toJson() => {
    'description': description,
    'mutates': mutates,
    if (positional != null) 'positional': positional,
    'parameters': parameters.map((key, value) => MapEntry(key, value.toJson())),
  };
}

const _id = CliParameter('string', required: true);
const _index = CliParameter('integer', required: true, min: 0);
const _limit = CliParameter('integer', min: 1, max: 100, fallback: 20);
const _offset = CliParameter('integer', min: 0, max: 1000000, fallback: 0);

const cliCommands = <String, CliCommand>{
  'status': CliCommand('Read playback, current track, position, volume and latest playback error.'),
  'search': CliCommand(
    'Find tracks; use returned ids with play or queue add. Remote results are cached for this app session.',
    positional: 'query',
    parameters: {
      'query': CliParameter('string', required: true),
      'source': CliParameter('string', values: ['library', 'youtube', 'soundcloud'], fallback: 'library'),
      'limit': _limit,
      'offset': _offset,
    },
  ),
  'library': CliCommand('List library tracks.', parameters: {'limit': _limit, 'offset': _offset}),
  'play': CliCommand(
    'Play a track id (replaces queue), or resume the current queue when omitted. Playback starts asynchronously; read status for errors.',
    positional: 'id',
    mutates: true,
    parameters: {'id': CliParameter('string')},
  ),
  'pause': CliCommand('Pause playback.', mutates: true),
  'toggle': CliCommand('Toggle playback.', mutates: true),
  'stop': CliCommand('Stop playback and clear the queue.', mutates: true),
  'next': CliCommand('Skip to the next track.', mutates: true),
  'previous': CliCommand('Previous track, or restart after three seconds.', mutates: true),
  'seek': CliCommand(
    'Seek to an absolute position in seconds.',
    positional: 'seconds',
    mutates: true,
    parameters: {'seconds': CliParameter('number', required: true, min: 0, max: 604800)},
  ),
  'volume': CliCommand(
    'Read volume, or set it to 0–100.',
    positional: 'value',
    mutates: true,
    parameters: {'value': CliParameter('number', min: 0, max: 100)},
  ),
  'shuffle': CliCommand(
    'Set shuffle explicitly.',
    positional: 'mode',
    mutates: true,
    parameters: {
      'mode': CliParameter('string', required: true, values: ['on', 'off']),
    },
  ),
  'repeat': CliCommand(
    'Set repeat explicitly.',
    positional: 'mode',
    mutates: true,
    parameters: {
      'mode': CliParameter('string', required: true, values: ['off', 'all', 'one']),
    },
  ),
  'queue': CliCommand(
    'List the queue in play order; indexes are zero-based.',
    parameters: {'limit': _limit, 'offset': _offset},
  ),
  'queue.add': CliCommand(
    'Append a track id. Starts playback when the queue is empty.',
    positional: 'id',
    mutates: true,
    parameters: {'id': _id},
  ),
  'queue.next': CliCommand(
    'Insert a track id after the current song.',
    positional: 'id',
    mutates: true,
    parameters: {'id': _id},
  ),
  'queue.remove': CliCommand(
    'Remove a zero-based queue index.',
    positional: 'index',
    mutates: true,
    parameters: {'index': _index},
  ),
  'queue.play': CliCommand(
    'Play a zero-based queue index.',
    positional: 'index',
    mutates: true,
    parameters: {'index': _index},
  ),
  'queue.clear': CliCommand('Stop playback and clear the queue.', mutates: true),
  'playlists': CliCommand('List local playlists.', parameters: {'limit': _limit, 'offset': _offset}),
  'playlist.show': CliCommand(
    'List tracks in a local playlist.',
    positional: 'id',
    parameters: {'id': _id, 'limit': _limit, 'offset': _offset},
  ),
  'playlist.play': CliCommand(
    'Replace the queue with a local playlist and start playback.',
    positional: 'id',
    mutates: true,
    parameters: {'id': _id},
  ),
};

Map<String, Object?> cliSchema() => {
  'apiVersion': cliApiVersion,
  'name': 'riflay-cli',
  'output': {
    'success': {'ok': true, 'result': 'command result'},
    'failure': {
      'ok': false,
      'error': {'code': 'string', 'message': 'string'},
    },
  },
  'commands': cliCommands.map((key, value) => MapEntry(key.replaceAll('.', ' '), value.toJson())),
};

Map<String, Object?> cliSuccess(Object? result) => {'apiVersion': cliApiVersion, 'ok': true, 'result': result};
Map<String, Object?> cliFailure(CliException error) => {
  'apiVersion': cliApiVersion,
  'ok': false,
  'error': error.toJson(),
};
