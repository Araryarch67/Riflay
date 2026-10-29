// Play, pause, next, previous, seek, shuffle, repeat and "play this song" against the real libmpv
// (silent), with crossfade off and on, with the sleep timer, and in the middle of a fade: every
// control must act on the player the user hears. Run it in a headless Weston, never on the real
// desktop, with a throwaway XDG_DATA_HOME.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer, Player;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every control acts on the player that is heard', (tester) async {
    JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
    final dir = Directory.systemTemp.createTempSync('om-controls');
    final songs = <Track>[];
    for (final (i, hz) in [440, 660, 880, 990].indexed) {
      final f = '${dir.path}/${'abcd'[i]}.wav';
      final r = await Process.run('ffmpeg', [
        '-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'sine=frequency=$hz:duration=16:sample_rate=44100', f, //
      ]);
      expect(r.exitCode, 0);
      songs.add(
        Track(
          id: Uri.file(f).toString(),
          uri: Uri.file(f),
          title: 'abcd'[i],
          artist: 'Tester',
          album: 'Album ${'abcd'[i]}',
          trackNumber: 1,
          duration: const Duration(seconds: 16),
        ),
      );
    }
    SharedPreferences.setMockInitialValues({});
    final c = PlayerController();
    Future<void> silent(void Function(Player) next, Player p) async {
      await (p.platform as NativePlayer).setProperty('ao', 'null');
      next(p);
    }

    final apply = JustAudioMediaKit.onPlayerCreated!;
    JustAudioMediaKit.onPlayerCreated = (p) => silent(apply, p);
    final applySecondary = JustAudioMediaKit.onSecondaryCreated!;
    // A test can ask for something to happen the moment the crossfade's second player is made.
    Future<void> Function()? onTail;
    JustAudioMediaKit.onSecondaryCreated = (p) {
      final hook = onTail;
      onTail = null;
      if (hook != null) unawaited(hook());
      unawaited(silent(applySecondary, p));
    };
    await tester.runAsync(c.load);
    final problems = <String>[];
    final errors = c.errors.listen((e) => problems.add('playback error: $e'));

    Future<void> wait(int ms) => tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    Future<bool> until(bool Function() ok, {int seconds = 20}) async {
      for (var i = 0; i < seconds * 20; i++) {
        if (ok()) return true;
        await wait(50);
      }
      return ok();
    }

    Future<String?> prop(String name, {bool secondary = false}) =>
        tester.runAsync<String?>(() => c.audio.debugProperty(name, secondary: secondary));
    Future<double> vol({bool secondary = false}) async =>
        double.tryParse(await prop('volume', secondary: secondary) ?? '') ?? -1;
    // What mpv itself says: the sound is going (not paused) on the main player.
    Future<bool> mpvPlaying() async => (await prop('pause')) == 'no';
    Future<bool> tailPlaying() async => (await prop('pause', secondary: true)) == 'no';
    void log(String s) => debugPrint('CTRL $s');

    Future<void> start({int at = 0}) async {
      await tester.runAsync(() => c.playList(songs, at, from: 'Test'));
      expect(await until(() => c.isPlaying && c.duration != null), isTrue, reason: 'playing');
    }

    // Starts a song three seconds in and waits for its fade to the next one; returns which song it was. A fade is
    // dropped, for good for that song, when the two clocks can't be kept in step (as on a busy machine), so the
    // next song is tried too.
    Future<int> fadeStarts() async {
      for (final i in [0, 1, 2]) {
        await tester.runAsync(() => c.playList(songs, i, from: 'Test'));
        expect(await until(() => c.isPlaying && c.duration != null), isTrue, reason: 'playing');
        await tester.runAsync(() => c.seek(const Duration(seconds: 3)));
        if (await until(() => c.crossfading, seconds: 14)) return i;
      }
      return -1;
    }

    Future<void> basics(String mode) async {
      await start();
      expect(c.currentTrack?.title, 'a', reason: '$mode: starts at a');
      log('pause prop=${await prop('pause')} ${c.isPlaying} ${c.position}');
      await wait(500);
      log(
        'pause prop=${await prop('pause')} ${c.isPlaying} ${c.position} core-idle=${await prop('core-idle')} pos=${await prop('time-pos')}',
      );
      expect(await mpvPlaying(), isTrue, reason: '$mode: mpv plays');
      // pause / play
      await tester.runAsync(c.pause);
      await wait(300);
      expect(c.isPlaying, isFalse, reason: '$mode: pause');
      expect(await mpvPlaying(), isFalse, reason: '$mode: mpv paused');
      await tester.runAsync(c.play);
      await wait(300);
      expect(c.isPlaying, isTrue, reason: '$mode: play');
      expect(await mpvPlaying(), isTrue, reason: '$mode: mpv plays again');
      // togglePlay
      await tester.runAsync(c.togglePlay);
      await wait(300);
      expect(c.isPlaying, isFalse, reason: '$mode: toggle pauses');
      await tester.runAsync(c.togglePlay);
      await wait(300);
      expect(c.isPlaying, isTrue, reason: '$mode: toggle plays');
      // next / previous
      await tester.runAsync(c.next);
      await wait(600);
      expect(c.currentTrack?.title, 'b', reason: '$mode: next');
      expect(c.isPlaying, isTrue, reason: '$mode: still playing after next');
      await tester.runAsync(c.previous); // within 3 s: back to a
      await wait(600);
      expect(c.currentTrack?.title, 'a', reason: '$mode: previous');
      expect(c.isPlaying, isTrue);
      // pause then next stays paused? (the app's rule: next keeps the state)
      await tester.runAsync(c.pause);
      await wait(200);
      await tester.runAsync(c.next);
      await wait(400);
      expect(c.currentTrack?.title, 'b', reason: '$mode: next while paused');
      await tester.runAsync(c.play);
      await wait(400);
      expect(c.isPlaying, isTrue);
      expect(await mpvPlaying(), isTrue, reason: '$mode: play after paused next');
      // seek
      await tester.runAsync(() => c.seek(const Duration(seconds: 5)));
      await wait(400);
      expect(c.position.inSeconds, inInclusiveRange(5, 6), reason: '$mode: seek');
      // play a song from the queue
      await tester.runAsync(() => c.playQueueItem(songs[2]));
      await wait(500);
      expect(c.currentTrack?.title, 'c', reason: '$mode: queue item');
      expect(c.isPlaying, isTrue);
      // queue next
      await tester.runAsync(() => c.playNext([songs[0]]));
      await wait(300);
      expect(c.upNext.first.title, 'a', reason: '$mode: play next');
      await tester.runAsync(c.next);
      await wait(500);
      expect(c.currentTrack?.title, 'a', reason: '$mode: next plays the queued song');
      // shuffle
      await tester.runAsync(c.toggleShuffle);
      await wait(600);
      expect(c.currentTrack?.title, 'a', reason: '$mode: shuffle keeps the song');
      expect(c.isPlaying, isTrue, reason: '$mode: shuffle keeps playing');
      await tester.runAsync(c.toggleShuffle);
      await wait(600);
      expect(c.isPlaying, isTrue);
      // repeat
      await tester.runAsync(c.cycleLoopMode); // all
      await tester.runAsync(c.cycleLoopMode); // one
      await tester.runAsync(c.cycleLoopMode); // off
      expect(c.loopMode, LoopMode.off);
      // pause, then let a different song start via playList
      await tester.runAsync(c.pause);
      await start(at: 1);
      expect(c.currentTrack?.title, 'b', reason: '$mode: new list plays');
    }

    log('--- crossfade off');
    await basics('off');

    log('--- crossfade on');
    await tester.runAsync(() async {
      await c.audio.setCrossfade(true);
      await c.audio.setCrossfadeSeconds(4);
    });
    await basics('on');

    // ── A pause, skip or seek while the second player is still loading must not end crossfade for good ──
    for (final (name, interrupt) in <(String, Future<void> Function())>[
      ('pause', () => c.pause()),
      ('next', () => c.next()),
      ('seek', () => c.seek(const Duration(seconds: 1))),
    ]) {
      log('--- $name while the tail loads');
      await start();
      // The moment the second player is made, the user acts (it is still loading its song).
      onTail = interrupt;
      await tester.runAsync(() => c.seek(const Duration(seconds: 3)));
      expect(await until(() => onTail == null, seconds: 12), isTrue, reason: '$name: the second player was made');
      await wait(1500);
      if (!c.isPlaying) {
        await tester.runAsync(c.play);
        await wait(300);
      }
      // Back to a song that has a next one, well before its fade. (A fade is dropped, for good for that song, when
      // two clocks can't be kept in step, as on a machine that is busy: so the next song is tried too.)
      final faded = await fadeStarts() != -1;
      expect(faded, isTrue, reason: '$name: crossfade still works after being interrupted while the tail loads');
      expect(await until(() => !c.crossfading, seconds: 8), isTrue);
      await wait(300);
      expect(await vol(), closeTo(100, 0.01));
    }

    // ── With the tail alive: pause, play, next ─────────────────────────────
    Future<void> toTail() async {
      await start();
      await tester.runAsync(() => c.seek(const Duration(seconds: 4)));
      // Wait for a tail (second player) to exist and be playing.
      expect(await until(() => false, seconds: 0), isFalse);
      for (var i = 0; i < 100; i++) {
        await wait(100);
        if ((await prop('time-pos', secondary: true)) != null && (await tailPlaying())) break;
      }
    }

    log('--- pause with a tail');
    await toTail();
    expect(await prop('pause', secondary: true), isNotNull, reason: 'a tail exists');
    await tester.runAsync(c.pause);
    await wait(500);
    expect(c.isPlaying, isFalse);
    expect(await prop('pause', secondary: true), isNull, reason: 'pause drops the tail');
    expect(await vol(), closeTo(100, 0.01));
    await tester.runAsync(c.play);
    await wait(500);
    expect(c.isPlaying, isTrue);
    expect(await mpvPlaying(), isTrue);

    log('--- next with a tail');
    await toTail();
    await tester.runAsync(c.next);
    await wait(600);
    expect(c.currentTrack?.title, 'b');
    expect(await prop('pause', secondary: true), isNull, reason: 'next drops the tail');
    expect(c.isPlaying, isTrue);
    expect(await mpvPlaying(), isTrue);
    expect(await vol(), closeTo(100, 0.01));

    // ── Pause in the middle of a fade, then play ───────────────────────────
    log('--- pause in a fade');
    final f1 = await fadeStarts();
    expect(f1, isNot(-1), reason: 'a fade starts');
    await wait(1000);
    expect(c.currentTrack?.title, songs[f1 + 1].title);
    await tester.runAsync(c.pause);
    await wait(500);
    expect(c.isPlaying, isFalse);
    expect(c.crossfading, isFalse);
    expect(await prop('pause', secondary: true), isNull, reason: 'the tail is gone');
    expect(await mpvPlaying(), isFalse);
    expect(await vol(), closeTo(100, 0.01), reason: 'full volume for b after the fade was cut');
    await tester.runAsync(c.play);
    await wait(1500);
    expect(c.isPlaying, isTrue);
    expect(await mpvPlaying(), isTrue);
    expect(c.currentTrack?.title, songs[f1 + 1].title);

    // ── After a fade completes: controls still act on the main player ─────
    log('--- after a fade');
    final f2 = await fadeStarts();
    expect(f2, isNot(-1), reason: 'a fade starts');
    expect(await until(() => !c.crossfading, seconds: 8), isTrue);
    expect(c.currentTrack?.title, songs[f2 + 1].title);
    await wait(500);
    await tester.runAsync(c.pause);
    await wait(400);
    expect(c.isPlaying, isFalse);
    expect(await mpvPlaying(), isFalse, reason: 'pause pauses the main player after a fade');
    expect(await prop('pause', secondary: true), isNull);
    await tester.runAsync(c.play);
    await wait(400);
    expect(c.isPlaying, isTrue);
    await tester.runAsync(c.next);
    await wait(500);
    expect(c.currentTrack?.title, songs[f2 + 2].title);
    expect(await vol(), closeTo(100, 0.01));

    // ── Sleep timer: after it fired, play works at full volume ─────────────
    log('--- sleep timer');
    await start();
    c.sleep.start(const Duration(seconds: 2));
    expect(await until(() => !c.isPlaying, seconds: 8), isTrue, reason: 'timer paused');
    await wait(800);
    expect(await vol(), closeTo(100, 0.01), reason: 'volume restored');
    await tester.runAsync(c.play);
    await wait(500);
    expect(c.isPlaying, isTrue);
    expect(await vol(), closeTo(100, 0.01));
    expect(await mpvPlaying(), isTrue);
    // user presses play right after the timer paused (inside the restore delay)
    c.sleep.start(const Duration(seconds: 1));
    expect(await until(() => !c.isPlaying, seconds: 8), isTrue);
    await tester.runAsync(c.play);
    await wait(1200);
    expect(c.isPlaying, isTrue);
    expect(await vol(), closeTo(100, 0.01), reason: 'volume back even when play came at once');

    // Sleep timer started while a fade runs.
    expect(await fadeStarts(), isNot(-1), reason: 'a fade starts');
    c.sleep.start(const Duration(seconds: 1));
    expect(await until(() => !c.isPlaying, seconds: 8), isTrue);
    await wait(900);
    expect(c.crossfading, isFalse);
    await tester.runAsync(c.play);
    await wait(600);
    expect(await vol(), closeTo(100, 0.01), reason: 'after sleep + fade');

    // End of song mode, then play
    await start();
    await tester.runAsync(() => c.seek(const Duration(seconds: 12)));
    c.sleep.startEndOfSong();
    expect(await until(() => !c.isPlaying, seconds: 8), isTrue, reason: 'end of this song pauses');
    log('end of song paused on ${c.currentTrack?.title}');
    await wait(800);
    await tester.runAsync(c.play);
    await wait(500);
    expect(c.isPlaying, isTrue);
    expect(await vol(), closeTo(100, 0.01));

    // ── A downloaded music video plays as sound (`vid=no`) ─────────────────
    log('--- video file');
    final mp4 = '${dir.path}/clip.mp4';
    final mk = await Process.run('ffmpeg', [
      '-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc=size=160x90:rate=10:duration=6', //
      '-f', 'lavfi', '-i', 'sine=frequency=500:duration=6', '-c:v', 'mpeg4', '-c:a', 'aac', '-shortest', mp4,
    ]);
    expect(mk.exitCode, 0, reason: '${mk.stderr}');
    final clip = Track.fromUri(Uri.file(mp4));
    await tester.runAsync(() => c.playList([clip, songs[0]], 0, from: 'Test'));
    expect(await until(() => c.isPlaying && c.duration != null), isTrue, reason: 'the video file plays');
    expect(c.duration!.inSeconds, inInclusiveRange(5, 7));
    expect(await prop('vid'), 'no');
    await tester.runAsync(c.pause);
    await wait(300);
    expect(await mpvPlaying(), isFalse);
    await tester.runAsync(c.play);
    await wait(500);
    expect(await mpvPlaying(), isTrue);
    await tester.runAsync(() => c.seek(const Duration(seconds: 5)));
    expect(await until(() => c.currentTrack?.title == 'a', seconds: 8), isTrue, reason: 'it ends into the next song');
    expect(c.isPlaying, isTrue);

    // ── The end of the queue, then Play starts it again ────────────────────
    log('--- end of queue');
    await tester.runAsync(() => c.audio.setCrossfade(false));
    await tester.runAsync(() => c.playList([songs[0]], 0, from: 'Test'));
    expect(await until(() => c.isPlaying && c.duration != null), isTrue);
    await tester.runAsync(() => c.seek(const Duration(seconds: 14)));
    expect(
      await until(() => c.player.processingState == ProcessingState.completed, seconds: 6),
      isTrue,
      reason: 'ends',
    );
    log('end state: ${c.player.processingState} playing=${c.player.playing}');
    // The media keys' Play (and the system's) is play(), not togglePlay(): it starts the queue over as well.
    await tester.runAsync(c.play);
    await wait(1000);
    log(
      'after play: ${c.player.processingState} playing=${c.player.playing} pos=${c.position} pause=${await prop('pause')} idle=${await prop('idle-active')}',
    );
    expect(
      await until(
        () => c.player.processingState != ProcessingState.completed && c.position < const Duration(seconds: 3),
      ),
      isTrue,
      reason: 'play() at the end of the queue starts it over',
    );
    expect(await mpvPlaying(), isTrue, reason: 'and it is heard');
    await tester.runAsync(() => c.seek(const Duration(seconds: 14)));
    expect(await until(() => c.player.processingState == ProcessingState.completed, seconds: 6), isTrue);
    await tester.runAsync(c.togglePlay);
    expect(await until(() => c.isPlaying && c.position < const Duration(seconds: 3)), isTrue, reason: 'restarts');
    await wait(1000);
    // Once it plays again, the button is Pause again: it pauses, it does not start the song over.
    final at = c.position;
    expect(c.player.processingState, isNot(ProcessingState.completed), reason: 'playing again is not "completed"');
    await tester.runAsync(c.togglePlay);
    await wait(500);
    expect(c.isPlaying, isFalse, reason: 'pause pauses a song that was started again from the end');
    expect(c.position, greaterThanOrEqualTo(at), reason: 'and does not start it over');
    await tester.runAsync(c.play);
    await wait(300);
    await tester.runAsync(() => c.audio.setCrossfade(true));

    // ── Several skips in a row, with a tail, and a pause while it is being made ──
    log('--- rapid skips');
    await start();
    await tester.runAsync(() => c.seek(const Duration(seconds: 2)));
    for (var i = 0; i < 100; i++) {
      await wait(50);
      if (await prop('time-pos', secondary: true) != null || c.crossfading) break;
    }
    await tester.runAsync(c.next);
    await tester.runAsync(c.next);
    await tester.runAsync(c.previous);
    await wait(900);
    expect(c.isPlaying, isTrue);
    expect(await mpvPlaying(), isTrue);
    expect(await vol(), closeTo(100, 0.01));
    expect(c.crossfading, isFalse);

    log('--- pause while the tail is made');
    await start();
    await tester.runAsync(() => c.seek(const Duration(seconds: 3)));
    for (var i = 0; i < 100; i++) {
      await wait(20);
      if (await prop('time-pos', secondary: true) != null) break;
    }
    await tester.runAsync(c.pause);
    await wait(1500);
    expect(c.isPlaying, isFalse);
    expect(await prop('pause', secondary: true), isNull, reason: 'no tail left behind');
    await tester.runAsync(c.play);
    await wait(500);
    expect(await mpvPlaying(), isTrue);

    // ── A lower volume stays through a fade and the sleep timer ────────────
    log('--- volume 0.5');
    await tester.runAsync(() => c.setVolume(0.5));
    await start();
    await wait(300);
    final before = await vol();
    expect(await fadeStarts(), isNot(-1), reason: 'a fade starts');
    expect(await until(() => !c.crossfading, seconds: 8), isTrue);
    await wait(300);
    expect(await vol(), closeTo(before, 0.01), reason: 'the level after a fade is the one before');
    c.sleep.start(const Duration(seconds: 1));
    expect(await until(() => !c.isPlaying, seconds: 8), isTrue);
    await wait(800);
    expect(await vol(), closeTo(before, 0.01), reason: 'and after the sleep timer');
    expect(c.volume, 0.5);
    await tester.runAsync(() => c.setVolume(1));

    // ── Repeat one: next and previous still move ───────────────────────────
    log('--- repeat one');
    await start();
    await tester.runAsync(c.cycleLoopMode);
    await tester.runAsync(c.cycleLoopMode);
    expect(c.loopMode, LoopMode.one);
    await tester.runAsync(c.next);
    await wait(500);
    expect(c.currentTrack?.title, 'b', reason: 'next in repeat one');
    await tester.runAsync(c.previous);
    await wait(500);
    expect(c.currentTrack?.title, 'a', reason: 'previous in repeat one');
    await tester.runAsync(c.cycleLoopMode);
    expect(c.loopMode, LoopMode.off);

    // ── A Listen Together guest: the host decides the next song, so no early jump to it ──
    log('--- guest');
    c.holdAutoplay = true;
    await start();
    await tester.runAsync(() => c.seek(const Duration(seconds: 3)));
    var fadedAsGuest = false;
    while (c.position < const Duration(seconds: 14) && c.currentTrack?.title == 'a') {
      await wait(100);
      fadedAsGuest |= c.crossfading;
    }
    expect(fadedAsGuest, isFalse, reason: 'a guest does not crossfade (the queue would move ahead of the host)');
    expect(c.currentTrack?.title, 'a', reason: 'the song plays to its end, the host moves it on');
    c.holdAutoplay = false;

    // Listen Together guest ends: holdAutoplay
    c.holdAutoplay = true;
    c.holdAutoplay = false;

    await errors.cancel();
    expect(problems, isEmpty);
  });
}
