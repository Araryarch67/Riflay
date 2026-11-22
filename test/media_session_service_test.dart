import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/media_session/media_session_service.dart';
import 'package:riflay/services/media_session/windows_media_controls.dart';

/// A player that records the commands it gets and reports the state the test sets.
class _FakePlayer extends ChangeNotifier implements MediaSessionPlayer {
  MediaSessionState state = const MediaSessionState();
  final calls = <String>[];
  final jumps = StreamController<void>.broadcast();
  final arts = <String, Uri?>{};
  int artLookups = 0;

  /// Commands wait for this when set (a slow song change).
  Completer<void>? gate;
  bool failNext = false;

  void set(MediaSessionState s) {
    state = s;
    notifyListeners();
  }

  @override
  MediaSessionState snapshot() => state;

  @override
  Stream<void> get discontinuities => jumps.stream;

  @override
  Future<Uri?> artworkFor(MediaTrackInfo track) async {
    artLookups++;
    return arts[track.id];
  }

  Future<void> _run(String name, [void Function()? effect]) async {
    calls.add(name);
    if (gate case final g?) await g.future;
    if (failNext && name == 'next') {
      failNext = false;
      throw StateError('no next');
    }
    effect?.call();
  }

  MediaSessionState _with({bool? playing, Duration? position}) => MediaSessionState(
    track: state.track,
    playing: playing ?? state.playing,
    processing: state.processing,
    position: position ?? state.position,
    speed: state.speed,
    canNext: state.canNext,
    canPrevious: state.canPrevious,
  );

  @override
  Future<void> play() => _run('play', () => set(_with(playing: true)));
  @override
  Future<void> pause() => _run('pause', () => set(_with(playing: false)));
  @override
  Future<void> togglePlayPause() => _run('toggle', () => set(_with(playing: !state.playing)));
  @override
  Future<void> next() => _run('next');
  @override
  Future<void> previous() => _run('previous');
  @override
  Future<void> stop() => _run('stop', () => set(_with(playing: false)));
  @override
  Future<void> seek(Duration position) => _run('seek ${position.inMilliseconds}', () => set(_with(position: position)));
}

/// An adapter that records what it is told, and lets the test press its buttons.
class _FakeAdapter implements MediaSessionAdapter {
  _FakeAdapter({this.available = true, this.name = 'fake'});

  final bool available;
  @override
  final String name;
  void Function(MediaCommand)? press;
  final updates = <MediaSessionState>[];
  int attaches = 0;
  bool detached = false;
  bool throwOnUpdate = false;

  /// Updates wait for this when set (a slow platform channel).
  Completer<void>? gate;

  @override
  Future<bool> attach(void Function(MediaCommand) onCommand) async {
    attaches++;
    if (!available) return false;
    press = onCommand;
    return true;
  }

  @override
  Future<void> update(MediaSessionState state) async {
    if (gate case final g?) await g.future;
    if (throwOnUpdate) throw StateError('channel gone');
    updates.add(state);
  }

  @override
  Future<void> detach() async => detached = true;
}

const _song = MediaTrackInfo(id: 'a', title: 'Song', artist: 'Artist', duration: Duration(minutes: 3));
const _other = MediaTrackInfo(id: 'b', title: 'Other', artist: 'Artist', duration: Duration(minutes: 2));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MediaCommandRouter', () {
    late List<MediaCommand> ran;
    late Duration now;
    MediaCommandRouter router({Future<void> Function(MediaCommand)? run}) => MediaCommandRouter(
      run ??
          (c) async {
            ran.add(c);
          },
      clock: () => now,
    );

    setUp(() {
      ran = [];
      now = Duration.zero;
    });

    test('one key seen by the window and by the system runs once', () async {
      final r = router();
      expect(r.add(const MediaCommand.toggle(source: MediaCommandSource.keyboard)), isTrue);
      now += const Duration(milliseconds: 40);
      // The system turns the same key into Pause.
      expect(r.add(const MediaCommand.pause()), isFalse);
      await r.idle;
      expect(ran.map((c) => c.kind), [MediaCommandKind.togglePlayPause]);
    });

    test('a bounce from one route runs once, a second press runs again', () async {
      final r = router();
      expect(r.add(const MediaCommand.next()), isTrue);
      now += const Duration(milliseconds: 30);
      expect(r.add(const MediaCommand.next()), isFalse, reason: 'a headset repeating itself');
      now += const Duration(milliseconds: 200);
      expect(r.add(const MediaCommand.next()), isTrue, reason: 'rapid presses each skip');
      await r.idle;
      expect(ran.length, 2);
    });

    test('different buttons are never duplicates of each other', () async {
      final r = router();
      r.add(const MediaCommand.next());
      r.add(const MediaCommand.previous(source: MediaCommandSource.keyboard));
      r.add(const MediaCommand.toggle(source: MediaCommandSource.app));
      await r.idle;
      expect(ran.map((c) => c.kind), [
        MediaCommandKind.next,
        MediaCommandKind.previous,
        MediaCommandKind.togglePlayPause,
      ]);
    });

    test('commands run one at a time, in order', () async {
      var running = 0;
      var most = 0;
      final r = router(
        run: (c) async {
          running++;
          most = most > running ? most : running;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          ran.add(c);
          running--;
        },
      );
      for (var i = 0; i < 3; i++) {
        now += const Duration(milliseconds: 150);
        r.add(const MediaCommand.next());
      }
      now += const Duration(milliseconds: 150);
      r.add(const MediaCommand.previous());
      await r.idle;
      expect(most, 1);
      expect(ran.map((c) => c.kind), [...List.filled(3, MediaCommandKind.next), MediaCommandKind.previous]);
    });

    test('pending seeks and pending play / pause collapse to the last', () async {
      final gate = Completer<void>();
      final r = router(
        run: (c) async {
          ran.add(c);
          if (ran.length == 1) await gate.future;
        },
      );
      r.add(const MediaCommand.next());
      r.add(const MediaCommand.seek(Duration(seconds: 10)));
      r.add(const MediaCommand.seek(Duration(seconds: 20)));
      r.add(const MediaCommand.seek(Duration(seconds: 30)));
      r.add(const MediaCommand.play());
      now += const Duration(milliseconds: 200);
      r.add(const MediaCommand.pause());
      expect(r.pending, 2);
      gate.complete();
      await r.idle;
      expect(ran.map((c) => '${c.kind.name}${c.position?.inSeconds ?? ''}'), ['next', 'seek30', 'pause']);
    });

    test('a failing command does not stop the ones after it', () async {
      final r = router(
        run: (c) async {
          ran.add(c);
          if (c.kind == MediaCommandKind.next) throw StateError('end of queue');
        },
      );
      r.add(const MediaCommand.next());
      r.add(const MediaCommand.play());
      await r.idle;
      expect(ran.map((c) => c.kind), [MediaCommandKind.next, MediaCommandKind.play]);
    });

    test('a held key cannot pile up commands', () async {
      final gate = Completer<void>();
      final r = MediaCommandRouter(
        (c) async {
          ran.add(c);
          await gate.future;
        },
        maxPending: 3,
        clock: () => now,
      );
      var accepted = 0;
      for (var i = 0; i < 10; i++) {
        now += const Duration(milliseconds: 100);
        if (r.add(const MediaCommand.next())) accepted++;
      }
      expect(accepted, 4, reason: 'one running and three waiting');
      gate.complete();
      await r.idle;
    });

    test('a closed router takes nothing', () async {
      final r = router()..close();
      expect(r.add(const MediaCommand.play()), isFalse);
      await r.idle;
      expect(ran, isEmpty);
    });

    test('a seek without a position is ignored', () {
      expect(router().add(const MediaCommand(MediaCommandKind.seek)), isFalse);
    });
  });

  group('MediaSessionService', () {
    late _FakePlayer player;
    late _FakeAdapter adapter;
    late MediaSessionService session;

    setUp(() async {
      MediaSessionService.resetForTest();
      player = _FakePlayer()..state = const MediaSessionState(track: _song, canNext: true, canPrevious: true);
      adapter = _FakeAdapter();
      session = await MediaSessionService.start(player, [adapter, _FakeAdapter(available: false, name: 'absent')]);
    });

    tearDown(() async {
      await session.dispose();
      MediaSessionService.resetForTest();
    });

    test('publishes the song at start, only on adapters that started', () async {
      await session.settled;
      expect(session.adapters, ['fake']);
      expect(adapter.updates.single.track, _song);
    });

    test('there is one session: a second start gets the first', () async {
      final again = await MediaSessionService.start(_FakePlayer(), [_FakeAdapter()]);
      expect(again, same(session));
      expect(adapter.attaches, 1);
    });

    test('two starts at once make one session', () async {
      await session.dispose();
      MediaSessionService.resetForTest();
      final a = _FakeAdapter();
      final both = await Future.wait([
        MediaSessionService.start(player, [a]),
        MediaSessionService.start(player, [a]),
      ]);
      expect(both[0], same(both[1]));
      expect(a.attaches, 1);
      session = both[0];
    });

    test('every system button reaches the player', () async {
      final press = adapter.press!;
      press(const MediaCommand.play());
      await session.settled;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      press(const MediaCommand.next());
      press(const MediaCommand.previous());
      press(const MediaCommand.seek(Duration(seconds: 42)));
      await session.settled;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      press(const MediaCommand.pause());
      await session.settled;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      press(const MediaCommand.stop());
      await session.settled;
      expect(player.calls, ['play', 'next', 'previous', 'seek 42000', 'pause', 'stop']);
    });

    test('a seek past either end is kept to the song', () async {
      MediaSessionService.route(const MediaCommand.seek(Duration(minutes: 9)));
      await session.settled;
      MediaSessionService.route(const MediaCommand.seek(Duration(seconds: -3)));
      await session.settled;
      expect(player.calls, ['seek 180000', 'seek 0']);
    });

    test('the player playing is told to the system, both ways', () async {
      await session.settled;
      adapter.press!(const MediaCommand.play());
      await session.settled;
      expect(adapter.updates.last.playing, isTrue);
      // Paused in the app (not by the system): the system follows.
      player.set(const MediaSessionState(track: _song, playing: false, position: Duration(seconds: 5), canNext: true));
      await session.settled;
      expect(adapter.updates.last.playing, isFalse);
      expect(adapter.updates.last.position, const Duration(seconds: 5));
    });

    test('a position moving on its own is not sent; a seek is', () async {
      await session.settled;
      final before = adapter.updates.length;
      for (var s = 1; s < 5; s++) {
        player.set(
          MediaSessionState(
            track: _song,
            playing: false,
            position: Duration(seconds: s),
            canNext: true,
            canPrevious: true,
          ),
        );
      }
      await session.settled;
      expect(adapter.updates.length, before, reason: 'the system extrapolates the position');
      player.jumps.add(null);
      await Future<void>.delayed(Duration.zero);
      await session.settled;
      expect(adapter.updates.length, before + 1);
      expect(adapter.updates.last.position, const Duration(seconds: 4));
    });

    test('a new song is sent, then its cover once found', () async {
      player.arts['b'] = Uri.file('/covers/b.jpg');
      player.set(const MediaSessionState(track: _other));
      await Future<void>.delayed(Duration.zero);
      await session.settled;
      expect(adapter.updates.map((s) => s.track?.id), containsAllInOrder(['a', 'b']));
      expect(adapter.updates.last.track?.artUri, Uri.file('/covers/b.jpg'));
      // Found once per song.
      final lookups = player.artLookups;
      player.jumps.add(null);
      await Future<void>.delayed(Duration.zero);
      await session.settled;
      expect(player.artLookups, lookups);
    });

    test('a song with a cover URL is not looked up', () async {
      final lookups = player.artLookups;
      player.set(MediaSessionState(track: _other.withArt(Uri.parse('https://example.com/b.jpg'))));
      await session.settled;
      expect(player.artLookups, lookups);
      expect(adapter.updates.last.track?.artUri, Uri.parse('https://example.com/b.jpg'));
    });

    test('a command that changes nothing still tells the system the truth', () async {
      await session.settled;
      final before = adapter.updates.length;
      player.failNext = true;
      adapter.press!(const MediaCommand.next());
      await session.settled;
      // Failed: nothing published, nothing broken.
      adapter.press!(const MediaCommand.play());
      await session.settled;
      expect(player.calls, ['next', 'play']);
      expect(adapter.updates.length, greaterThan(before));
    });

    test('updates to an adapter never overlap, and the latest wins', () async {
      await session.settled;
      adapter.gate = Completer<void>();
      player.set(const MediaSessionState(track: _song, playing: true));
      player.set(const MediaSessionState(track: _other, playing: true));
      player.set(const MediaSessionState(track: _other, playing: false));
      final before = adapter.updates.length;
      adapter.gate!.complete();
      await session.settled;
      final sent = adapter.updates.skip(before).toList();
      expect(sent.first.track, _song);
      expect(sent.last.track?.id, 'b');
      expect(sent.last.playing, isFalse);
      expect(sent.length, lessThanOrEqualTo(2));
    });

    test('an adapter that fails does not stop the others', () async {
      await session.dispose();
      MediaSessionService.resetForTest();
      final broken = _FakeAdapter(name: 'broken')..throwOnUpdate = true;
      final good = _FakeAdapter(name: 'good');
      session = await MediaSessionService.start(player, [broken, good]);
      player.set(const MediaSessionState(track: _other, playing: true));
      await session.settled;
      expect(good.updates.last.track?.id, 'b');
    });

    test('coming back to the foreground sends the state again', () async {
      await session.settled;
      final before = adapter.updates.length;
      session.handleLifecycle(AppLifecycleState.paused);
      await session.settled;
      expect(adapter.updates.length, before);
      session.handleLifecycle(AppLifecycleState.resumed);
      await session.settled;
      expect(adapter.updates.length, before + 1);
    });

    test('a disposed session takes no commands and lets the adapters go', () async {
      await session.dispose();
      expect(adapter.detached, isTrue);
      expect(MediaSessionService.instance, isNull);
      expect(MediaSessionService.route(const MediaCommand.play()), isFalse);
      adapter.press!(const MediaCommand.play());
      await Future<void>.delayed(Duration.zero);
      expect(player.calls, isEmpty);
    });
  });

  group('WindowsMediaControls', () {
    const channel = MethodChannel(WindowsMediaControls.channelName);
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'enable' ? true : null;
      });
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('reads the runner\'s buttons', () {
      expect(WindowsMediaControls.parseCommand({'command': 'play'})?.kind, MediaCommandKind.play);
      expect(WindowsMediaControls.parseCommand({'command': 'pause'})?.kind, MediaCommandKind.pause);
      expect(WindowsMediaControls.parseCommand({'command': 'stop'})?.kind, MediaCommandKind.stop);
      expect(WindowsMediaControls.parseCommand({'command': 'next'})?.kind, MediaCommandKind.next);
      expect(WindowsMediaControls.parseCommand({'command': 'previous'})?.kind, MediaCommandKind.previous);
      final seek = WindowsMediaControls.parseCommand({'command': 'seek', 'positionMs': 61500});
      expect(seek?.position, const Duration(milliseconds: 61500));
      expect(seek?.source, MediaCommandSource.system);
      expect(WindowsMediaControls.parseCommand({'command': 'seek'}), isNull);
      expect(WindowsMediaControls.parseCommand({'command': 'record'}), isNull);
      expect(WindowsMediaControls.parseCommand('play'), isNull);
    });

    test('tells the flyout the song, the cover file and the state', () {
      final s = MediaSessionState(
        track: _song.withArt(Uri.file(r'C:\cache\cover.img', windows: true)),
        playing: true,
        position: const Duration(seconds: 12),
        speed: 1.25,
        canNext: true,
        canPrevious: true,
      );
      expect(WindowsMediaControls.metadataOf(s), {
        'id': 'a',
        'title': 'Song',
        'artist': 'Artist',
        'album': '',
        'art': r'C:\cache\cover.img',
      });
      expect(WindowsMediaControls.stateOf(s), {
        'status': 'playing',
        'positionMs': 12000,
        'durationMs': 180000,
        'rate': 1.25,
        'canNext': true,
        'canPrevious': true,
      });
      expect(WindowsMediaControls.stateOf(MediaSessionState.empty)['status'], 'closed');
      expect(
        WindowsMediaControls.stateOf(
          const MediaSessionState(track: _song, processing: MediaProcessing.completed),
        )['status'],
        'stopped',
      );
      expect(WindowsMediaControls.stateOf(const MediaSessionState(track: _song))['status'], 'paused');
    });

    test('a remote cover is passed as its URL', () {
      final s = MediaSessionState(track: _song.withArt(Uri.parse('https://i.ytimg.com/vi/x/hq.jpg')));
      expect(WindowsMediaControls.metadataOf(s)['art'], 'https://i.ytimg.com/vi/x/hq.jpg');
    });

    test('sends only what changed', () async {
      final controls = WindowsMediaControls(channel: channel, enabled: true);
      expect(await controls.attach((_) {}), isTrue);
      const s = MediaSessionState(track: _song);
      await controls.update(s);
      await controls.update(s);
      await controls.update(const MediaSessionState(track: _song, playing: true));
      expect(calls.map((c) => c.method), ['enable', 'metadata', 'state', 'state']);
    });

    test('the runner\'s buttons come to the session', () async {
      final got = <MediaCommand>[];
      final controls = WindowsMediaControls(channel: channel, enabled: true);
      await controls.attach(got.add);
      await messenger.handlePlatformMessage(
        WindowsMediaControls.channelName,
        const StandardMethodCodec().encodeMethodCall(const MethodCall('command', {'command': 'next'})),
        (_) {},
      );
      expect(got.single.kind, MediaCommandKind.next);
      await controls.detach();
      expect(calls.last.method, 'disable');
    });

    test('off Windows, or with an old runner, there is no session', () async {
      expect(await WindowsMediaControls(channel: channel, enabled: false).attach((_) {}), isFalse);
      messenger.setMockMethodCallHandler(channel, null);
      expect(await WindowsMediaControls(channel: channel, enabled: true).attach((_) {}), isFalse);
    });
  });
}
