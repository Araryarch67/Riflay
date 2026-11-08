import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/cli_commands.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay_cli/protocol.dart';

class FakeCliPlayer implements PlayerController {
  final problems = StreamController<String>.broadcast(sync: true);
  final local = Track.fromUri(Uri.file('/music/Artist - Local.flac'));
  final remote = Track.youtube(videoId: 'abcdefghijk', title: 'Remote song', artist: 'Artist');
  final List<Track> queued = [];
  Completer<void>? pendingLoad;
  int? playedIndex;
  bool playing = false;
  bool shuffled = false;
  double level = 0.5;
  LoopMode loop = LoopMode.off;

  @override
  Stream<String> get errors => problems.stream;
  @override
  bool get showsPlaying => playing;
  @override
  bool get isBuffering => false;
  @override
  Track? get currentTrack => queued.firstOrNull;
  @override
  List<Track> get library => [local];
  @override
  List<Track> get queue => List.of(queued);
  @override
  int? get queueIndex => queued.isEmpty ? null : playedIndex ?? 0;
  @override
  List<UserPlaylist> get playlists => [
    UserPlaylist(id: 'mix', name: 'Mix', tracks: [local, remote], createdAt: 0),
  ];
  @override
  Duration get position => Duration.zero;
  @override
  Duration? get duration => const Duration(seconds: 120);
  @override
  double get volume => level;
  @override
  bool get canSetVolume => true;
  @override
  bool get shuffle => shuffled;
  @override
  LoopMode get loopMode => loop;
  @override
  bool get hasNext => queued.length > 1;
  @override
  bool get hasPrevious => false;
  @override
  bool get casting => false;
  @override
  bool get hasQueue => queued.isNotEmpty;
  @override
  bool get canPlay => true;
  @override
  List<Track> search(String query) => [local];
  @override
  Future<List<Track>> searchYoutube(String query) async => [remote];
  @override
  Future<void> playList(List<Track> tracks, int index, {String? from, bool shuffled = false}) async {
    if (pendingLoad != null) await pendingLoad!.future;
    queued
      ..clear()
      ..addAll(tracks);
    playing = true;
  }

  @override
  Future<void> play() async {
    playing = true;
  }

  @override
  Future<void> pause() async {
    playing = false;
  }

  @override
  Future<void> addToQueue(List<Track> tracks) async => queued.addAll(tracks);
  @override
  Future<void> closePlayer() async {
    queued.clear();
    playing = false;
  }

  @override
  Future<void> setVolume(double value) async {
    level = value;
  }

  @override
  Future<void> toggleShuffle() async {
    shuffled = !shuffled;
  }

  @override
  Future<void> cycleLoopMode() async {
    loop = switch (loop) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
  }

  @override
  Future<void> playQueueIndex(int index) async {
    playedIndex = index;
  }

  @override
  Future<void> removeQueueIndex(int index) async {
    queued.removeAt(index);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeCliPlayer player;
  late CliCommands commands;
  setUp(() {
    player = FakeCliPlayer();
    commands = CliCommands(player);
  });
  tearDown(() async {
    await commands.close();
    await player.problems.close();
  });
  Future<dynamic> run(String command, [Map<String, dynamic> params = const {}]) =>
      commands.execute(command, cliCommands[command]!.validate(params));

  test('remote search ids can be played and library is paginated', () async {
    final search = await run('search', {'query': 'Artist', 'source': 'youtube'});
    expect(search['items'][0]['id'], player.remote.id);
    await run('play', {'id': search['items'][0]['id']});
    expect(player.currentTrack, player.remote);
    expect((await run('library', {'offset': 1}))['items'], isEmpty);
    expect((await run('library'))['total'], 1);
  });
  test('unknown ids and invalid queue indexes fail without changing playback', () async {
    await expectLater(run('play', {'id': 'not-found'}), throwsA(isA<CliException>()));
    await expectLater(run('queue.remove', {'index': 3}), throwsA(isA<CliException>()));
    expect(player.queue, isEmpty);
    await run('volume', {'value': 30});
    expect(player.volume, 0.3, reason: 'a failed mutation does not block later commands');
  });
  test('mutations wait for loading while status remains available', () async {
    final pending = Completer<void>();
    player.pendingLoad = pending;
    final loading = run('play', {'id': player.local.id});
    final append = run('queue.add', {'id': player.remote.id});
    expect((await run('status'))['queueLength'], 0);
    pending.complete();
    await loading;
    await append;
    expect(player.queue, [player.local, player.remote]);
  });
  test('repeat and shuffle setters are idempotent; duplicate queue ids use exact indexes', () async {
    player.queued.addAll([player.local, player.local]);
    await run('repeat', {'mode': 'one'});
    await run('repeat', {'mode': 'one'});
    expect(player.loopMode, LoopMode.one);
    await run('shuffle', {'mode': 'on'});
    await run('shuffle', {'mode': 'on'});
    expect(player.shuffle, true);
    await run('queue.play', {'index': 1});
    expect(player.playedIndex, 1);
    final queue = await run('queue');
    expect(queue['items'][0]['current'], false);
    expect(queue['items'][1]['current'], true);
    await run('queue.remove', {'index': 1});
    expect(player.queue, [player.local]);
  });
  test('playlist playback, pause and stop use the app controller', () async {
    expect((await run('playlists'))['items'][0]['id'], 'mix');
    expect((await run('playlist.show', {'id': 'mix'}))['total'], 2);
    await run('playlist.play', {'id': 'mix'});
    expect(player.queue, [player.local, player.remote]);
    await run('pause');
    expect(player.showsPlaying, false);
    await run('stop');
    expect(player.queue, isEmpty);
  });
  test('status reports asynchronous playback errors and rejects an out of range seek', () async {
    player.problems.add('Could not play the song');
    expect((await run('status'))['lastError'], 'Could not play the song');
    player.queued.add(player.local);
    await expectLater(run('seek', {'seconds': 121}), throwsA(isA<CliException>()));
  });
}
