import 'dart:async';

import 'package:riflay_cli/protocol.dart';

import '../models/track.dart';
import '../platform/features.dart';
import 'listen_together/listen_together.dart';
import 'player_controller.dart';

/// Commands use the same controller as the UI, including casting and saved preferences.
class CliCommands {
  CliCommands(this.player) {
    _errors = player.errors.listen((message) => _lastError = message);
  }
  final PlayerController player;
  late final StreamSubscription<String> _errors;
  final _found = <String, Track>{};
  String? _lastError;
  Future<void> _tail = Future.value();

  Future<void> close() => _errors.cancel();

  Map<String, Object?> status() => {
    'playing': player.showsPlaying,
    'buffering': player.isBuffering,
    'track': player.currentTrack?.toJson(),
    'positionMs': player.position.inMilliseconds,
    'durationMs': player.duration?.inMilliseconds,
    'volume': (player.volume * 100).round(),
    'canSetVolume': player.canSetVolume,
    'shuffle': player.shuffle,
    'repeat': player.loopMode.name,
    'queueLength': player.queue.length,
    'hasNext': player.hasNext,
    'hasPrevious': player.hasPrevious,
    'casting': player.casting,
    'lastError': _lastError,
  };

  Future<Object?> execute(String command, Map<String, Object> params) {
    // Reads stay responsive during a remote search; mutations keep their order.
    if (!cliCommands[command]!.mutates) return _execute(command, params);
    final result = _tail.then((_) => _execute(command, params));
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Map<String, Object?> _page(List<Object?> items, Map<String, Object> params) {
    final offset = params['offset'] as int;
    final limit = params['limit'] as int;
    return {'items': items.skip(offset).take(limit).toList(), 'total': items.length, 'offset': offset, 'limit': limit};
  }

  List<Map<String, dynamic>> _tracks(List<Track> tracks) => tracks.map((t) => t.toJson()).toList();

  Track _track(String id) {
    for (final track in [
      ...player.library,
      ...player.queue,
      for (final playlist in player.playlists) ...playlist.tracks,
    ]) {
      if (track.id == id) return track;
    }
    final cached = _found.remove(id);
    if (cached != null) {
      _found[id] = cached;
      return cached;
    }
    throw const CliException(
      'track_not_found',
      'Unknown track id. Search again or use an id from library, queue or playlist.',
    );
  }

  UserPlaylist _playlist(String id) {
    for (final playlist in player.playlists) {
      if (playlist.id == id) return playlist;
    }
    throw const CliException('playlist_not_found', 'Unknown local playlist id. Run playlists first.');
  }

  Track _queueTrack(int index) {
    final queue = player.queue;
    if (index >= queue.length) {
      throw const CliException('index_out_of_range', 'Queue index is out of range. Read queue again.');
    }
    return queue[index];
  }

  void _start(Future<void> Function() action) {
    // just_audio's play Future completes only after playback stops.
    _lastError = null;
    unawaited(
      Future.sync(action).catchError((Object _) {
        _lastError = 'Playback could not start. Check the track in Riflay.';
      }),
    );
  }

  Future<Object?> _execute(String command, Map<String, Object> params) async {
    if (cliCommands[command]!.mutates && ListenTogether.of(player).role == ListenRole.guest) {
      throw const CliException(
        'room_controlled',
        'Leave the Listen together guest session before controlling playback through CLI.',
      );
    }
    switch (command) {
      case 'status':
        return status();
      case 'library':
        return _page(_tracks(player.library), params);
      case 'search':
        final query = params['query'] as String;
        final source = params['source'] as String;
        if (source == 'soundcloud' && !Features.soundcloud) {
          throw const CliException('unavailable', 'SoundCloud is disabled in this build.');
        }
        final tracks = switch (source) {
          'youtube' => await player.searchYoutube(query),
          'soundcloud' => await player.searchSoundcloud(query),
          _ => player.search(query),
        };
        // Cache all returned remote results for subsequent agent calls, bounded per app session.
        for (final track in tracks) {
          _found.remove(track.id);
          _found[track.id] = track;
          if (_found.length > 1000) _found.remove(_found.keys.first);
        }
        return {..._page(_tracks(tracks), params), 'source': source, 'query': query};
      case 'queue':
        final queue = player.queue;
        return _page([
          for (var i = 0; i < queue.length; i++)
            {'index': i, 'current': i == player.queueIndex, 'track': queue[i].toJson()},
        ], params);
      case 'playlists':
        return _page([
          for (final playlist in player.playlists)
            {'id': playlist.id, 'name': playlist.name, 'trackCount': playlist.tracks.length},
        ], params);
      case 'playlist.show':
        final playlist = _playlist(params['id'] as String);
        return {..._page(_tracks(playlist.tracks), params), 'id': playlist.id, 'name': playlist.name};
      case 'play':
        if (params['id'] case final String id) {
          final track = _track(id);
          _lastError = null;
          await player.playList([track], 0, from: 'riflay-cli');
        } else {
          if (!player.hasQueue) throw const CliException('empty_queue', 'The queue is empty. Use play ID first.');
          _start(player.play);
        }
        return {'accepted': true, 'status': status()};
      case 'toggle':
        if (!player.canPlay) throw const CliException('empty_queue', 'There is nothing to play. Use play ID first.');
        if (player.showsPlaying) {
          await player.pause();
        } else if (player.hasQueue) {
          _start(player.play);
        } else {
          _lastError = null;
          await player.playList(player.library, 0, from: 'riflay-cli');
        }
        return {'accepted': true, 'status': status()};
      case 'pause':
        await player.pause();
      case 'stop' || 'queue.clear':
        if (player.casting) {
          throw const CliException('casting_active', 'Stop casting in Riflay before clearing the queue.');
        }
        await player.closePlayer();
      case 'next':
        if (!player.hasNext) throw const CliException('end_of_queue', 'There is no next track.');
        await player.next();
      case 'previous':
        if (!player.hasQueue) throw const CliException('empty_queue', 'The queue is empty.');
        await player.previous();
      case 'seek':
        if (player.currentTrack == null) throw const CliException('empty_queue', 'There is no current track.');
        final position = Duration(milliseconds: ((params['seconds'] as num) * 1000).round());
        if (player.duration case final duration? when position > duration) {
          throw const CliException('invalid_arguments', 'Position exceeds the track duration.');
        }
        await player.seek(position);
      case 'volume':
        if (params['value'] case final num value) {
          if (!player.canSetVolume) {
            throw const CliException('unavailable', 'This output does not support volume control.');
          }
          await player.setVolume(value / 100);
        }
      case 'shuffle':
        if (!player.hasQueue) throw const CliException('empty_queue', 'The queue is empty.');
        if (player.shuffle != (params['mode'] == 'on')) await player.toggleShuffle();
      case 'repeat':
        while (player.loopMode.name != params['mode']) {
          await player.cycleLoopMode();
        }
      case 'queue.add' || 'queue.next':
        final track = _track(params['id'] as String);
        if (command == 'queue.next') {
          await player.playNext([track]);
        } else {
          await player.addToQueue([track]);
        }
      case 'queue.remove':
        final index = params['index'] as int;
        _queueTrack(index);
        await player.removeQueueIndex(index);
      case 'queue.play':
        final index = params['index'] as int;
        _queueTrack(index);
        _lastError = null;
        await player.playQueueIndex(index);
        return {'accepted': true, 'status': status()};
      case 'playlist.play':
        final playlist = _playlist(params['id'] as String);
        if (playlist.tracks.isEmpty) throw const CliException('empty_playlist', 'The playlist is empty.');
        _lastError = null;
        await player.playList(playlist.tracks, 0, from: playlist.name);
        return {'accepted': true, 'status': status()};
      default:
        throw const CliException('unknown_command', 'Unknown CLI command.');
    }
    return status();
  }
}
