import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/track_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _local = Track(
  id: 'local-recent',
  uri: Uri.file('/music/recent.flac'),
  title: 'Local recent',
  artist: 'Artist',
  tagged: true,
);
final _remote = Track.youtube(videoId: 'abcdefghijk', title: 'Remote recent', artist: 'Artist');

Future<PlayerController> _load() async {
  final player = PlayerController();
  await player.load();
  return player;
}

class _CurrentRecentPlayer extends PlayerController {
  Track? current;
  @override
  Track? get currentTrack => current;
  @override
  bool get isPlaying => current != null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'library.v1': jsonEncode([_local.toJson()]),
      'recent.v1': [_remote.id, _local.id],
      'recent.remote.v1': jsonEncode([_remote.toJson()]),
    });
  });

  test('removing a remote recent persists across reload and leaves the local library and playlists intact', () async {
    final player = await _load();
    final playlist = player.createPlaylist('Mix', tracks: [_local, _remote]);
    expect(player.recentlyPlayed.map((t) => t.id), [_remote.id, _local.id]);
    await player.removeFromRecentlyPlayed(_remote);
    expect(player.recentlyPlayed.map((t) => t.id), [_local.id]);
    expect(player.library.map((t) => t.id), [_local.id]);
    expect(player.playlists.single.tracks.map((t) => t.id), [_local.id, _remote.id]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('recent.v1'), [_local.id]);
    expect(jsonDecode(prefs.getString('recent.remote.v1')!), isEmpty);
    final reloaded = await _load();
    expect(reloaded.recentlyPlayed.map((t) => t.id), [_local.id]);
    expect(reloaded.playlists.single.id, playlist.id);
    player.dispose();
    reloaded.dispose();
  });

  test('removing the last recent leaves an empty list and repeated removal is harmless', () async {
    final player = await _load();
    await player.removeFromRecentlyPlayed(_local);
    await player.removeFromRecentlyPlayed(_remote);
    await player.removeFromRecentlyPlayed(_remote);
    expect(player.recentlyPlayed, isEmpty);
    expect(player.library.single.id, _local.id);
    expect((await SharedPreferences.getInstance()).getStringList('recent.v1'), isEmpty);
    player.dispose();
  });

  test('removing the current song survives player notifications and it returns only on a later playback', () async {
    final player = _CurrentRecentPlayer();
    await player.load();
    player.current = _remote;
    await player.removeFromRecentlyPlayed(_remote);
    // A real sequence-state update: buffering, repeat and play-state notifications call the same recorder.
    await player.player.setLoopMode(LoopMode.one);
    await Future<void>.delayed(Duration.zero);
    expect(player.recentlyPlayed.map((t) => t.id), [_local.id]);
    player.current = _local;
    await player.player.setLoopMode(LoopMode.off);
    await Future<void>.delayed(Duration.zero);
    player.current = _remote;
    await player.player.setLoopMode(LoopMode.one);
    await Future<void>.delayed(Duration.zero);
    expect(player.recentlyPlayed.first.id, _remote.id, reason: 'playing it again is a new recent');
    await player.flushSaves();
    player.dispose();
  });

  testWidgets('a recent track has a removal action in its menu, which disappears after removal', (tester) async {
    final player = await tester.runAsync(_load);
    await tester.pumpWidget(
      PlayerScope(
        controller: player!,
        child: MaterialApp(
          home: ShellScope(
            compact: true,
            width: 400,
            open: (_, {location}) {},
            openCollection: (_) {},
            openQueue: () {},
            openNowPlaying: () {},
            openLyrics: () {},
            openDownloads: () {},
            importFromYoutube: ({url}) {},
            addFiles: () {},
            addFolder: null,
            child: Scaffold(body: TrackMenuButton(track: _local)),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('More options for Local recent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from Recently played'));
    await tester.pumpAndSettle();
    expect(player.recentlyPlayed.map((t) => t.id), [_remote.id]);
    await tester.tap(find.byTooltip('More options for Local recent'));
    await tester.pumpAndSettle();
    expect(find.text('Remove from Recently played'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    player.dispose();
  });
}
