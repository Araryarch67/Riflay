// The media session over Riflay's own PlayerController: the system's buttons (Windows SMTC over its channel, the
// audio_service handler of Android / iOS / macOS / Linux / web) reach the controller once each, and what the
// controller does reaches the system.
import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/media_session.dart';
import 'package:riflay/services/media_session/media_session_service.dart';
import 'package:riflay/services/media_session/player_binding.dart';
import 'package:riflay/services/media_session/windows_media_controls.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A controller whose song and play state the test sets; its commands are recorded, not played.
class _Controller extends PlayerController {
  _Controller() : super();

  Track? track = _songs.first;
  bool playing = false;
  Duration at = Duration.zero;
  final calls = <String>[];

  @override
  Track? get currentTrack => track;
  @override
  bool get isPlaying => playing;
  @override
  Duration get position => at;
  @override
  Duration? get duration => const Duration(minutes: 4);
  @override
  bool get hasNext => track == _songs.first;

  @override
  Future<void> play() async {
    calls.add('play');
    playing = true;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    playing = false;
    notifyListeners();
  }

  @override
  Future<void> togglePlay() async {
    calls.add('toggle');
    playing = !playing;
    notifyListeners();
  }

  @override
  Future<void> next() async {
    calls.add('next');
    if (track == _songs.first) track = _songs.last;
    at = Duration.zero;
    notifyListeners();
  }

  @override
  Future<void> previous() async {
    calls.add('previous');
    track = _songs.first;
    at = Duration.zero;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration to) async {
    calls.add('seek ${to.inSeconds}');
    at = to;
    notifyListeners();
  }
}

final _songs = [
  Track(
    id: 'one',
    uri: Uri.parse('https://example.com/one'),
    title: 'One',
    artist: 'Band',
    album: 'Album',
    sourceUrl: 'https://music.youtube.com/watch?v=one',
    videoId: 'one',
    artworkUrl: 'https://example.com/one.jpg',
  ),
  Track(
    id: 'two',
    uri: Uri.parse('https://example.com/two'),
    title: 'Two',
    artist: 'Band',
    sourceUrl: 'https://music.youtube.com/watch?v=two',
    videoId: 'two',
    artworkUrl: 'https://example.com/two.jpg',
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(WindowsMediaControls.channelName);
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late _Controller c;
  late List<MethodCall> sent;
  late MediaSessionService session;
  late MediaSession handler;

  Future<void> pressOnWindows(Map<String, Object?> command) => messenger.handlePlatformMessage(
    WindowsMediaControls.channelName,
    const StandardMethodCodec().encodeMethodCall(MethodCall('command', command)),
    (_) {},
  );

  Map<Object?, Object?> lastState() => sent.lastWhere((m) => m.method == 'state').arguments as Map<Object?, Object?>;
  Map<Object?, Object?> lastMetadata() =>
      sent.lastWhere((m) => m.method == 'metadata').arguments as Map<Object?, Object?>;

  /// Past the window in which a second press of the same button counts as the same press.
  Future<void> nextPress() => Future<void>.delayed(const Duration(milliseconds: 400));

  setUp(() async {
    SharedPreferences.setMockInitialValues({'discord.enabled': false});
    MediaSessionService.resetForTest();
    sent = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent.add(call);
      return call.method == 'enable' ? true : null;
    });
    c = _Controller();
    // The audio_service side is the same handler the phones use, outside audio_service's platform plumbing.
    late _HandlerAdapter audio;
    audio = _HandlerAdapter((send) => handler = MediaSession.test(c, send));
    session = await MediaSessionService.start(PlayerControllerBinding(c), [
      WindowsMediaControls(channel: channel, enabled: true),
      audio,
    ]);
    await session.settled;
  });

  tearDown(() async {
    await session.dispose();
    MediaSessionService.resetForTest();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('the song and its state reach Windows and audio_service at start', () async {
    expect(lastMetadata(), containsPair('title', 'One'));
    expect(lastMetadata(), containsPair('art', 'https://example.com/one.jpg'));
    expect(lastState(), containsPair('status', 'paused'));
    expect(lastState(), containsPair('durationMs', 240000));
    expect(lastState(), containsPair('canNext', true));
    expect(handler.mediaItem.value?.title, 'One');
    expect(handler.mediaItem.value?.artUri, Uri.parse('https://example.com/one.jpg'));
    expect(handler.playbackState.value.playing, isFalse);
  });

  test('Windows buttons run on the controller and the flyout follows', () async {
    await pressOnWindows({'command': 'play'});
    await session.settled;
    expect(c.calls, ['play']);
    expect(lastState(), containsPair('status', 'playing'));
    expect(handler.playbackState.value.playing, isTrue, reason: 'every session follows, not just the one pressed');

    await pressOnWindows({'command': 'next'});
    await session.settled;
    expect(c.calls.last, 'next');
    expect(lastMetadata(), containsPair('title', 'Two'));
    expect(lastState(), containsPair('canNext', false));
    expect(handler.mediaItem.value?.title, 'Two');

    await pressOnWindows({'command': 'seek', 'positionMs': 90000});
    await session.settled;
    expect(c.calls.last, 'seek 90');
    expect(lastState(), containsPair('positionMs', 90000));
  });

  test('audio_service buttons (headset, lock screen, MPRIS) run on the controller', () async {
    await handler.play();
    await session.settled;
    await nextPress();
    await handler.skipToNext();
    await handler.skipToPrevious();
    await handler.seek(const Duration(seconds: 30));
    await session.settled;
    await nextPress();
    await handler.pause();
    await session.settled;
    await nextPress();
    await handler.stop();
    await session.settled;
    // Stop pauses, as it always has: the queue and the place in the song stay.
    expect(c.calls, ['play', 'next', 'previous', 'seek 30', 'pause', 'pause']);
    expect(lastState(), containsPair('status', 'paused'));
  });

  test('a headset click toggles through the session', () async {
    await handler.click();
    await session.settled;
    expect(c.calls, ['play']);
    await nextPress();
    await handler.click();
    await session.settled;
    expect(c.calls, ['play', 'pause']);
  });

  test('a media key seen by the window and by Windows plays or pauses once', () async {
    // The window's shortcut (home_shell) and the system's session both get the key.
    expect(MediaSessionService.route(const MediaCommand.toggle(source: MediaCommandSource.keyboard)), isTrue);
    await pressOnWindows({'command': 'play'});
    await session.settled;
    expect(c.calls, ['toggle']);
    expect(c.playing, isTrue);
  });

  test('rapid Next presses each skip, in order, a bounce does not', () async {
    await pressOnWindows({'command': 'next'});
    await pressOnWindows({'command': 'next'});
    await session.settled;
    expect(c.calls, ['next'], reason: 'the second came within the bounce window');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await pressOnWindows({'command': 'previous'});
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await pressOnWindows({'command': 'next'});
    await session.settled;
    expect(c.calls, ['next', 'previous', 'next']);
    expect(lastMetadata(), containsPair('title', 'Two'));
  });

  test('the app pausing or changing song is told to the system without a button', () async {
    await c.play();
    await session.settled;
    expect(lastState(), containsPair('status', 'playing'));
    // A Bluetooth headset is disconnected: the controller pauses (becomingNoisy) and the system follows.
    await c.pause();
    await session.settled;
    expect(lastState(), containsPair('status', 'paused'));
    expect(handler.playbackState.value.playing, isFalse);
    c.track = null;
    c.notifyListeners();
    await session.settled;
    expect(lastState(), containsPair('status', 'closed'));
    expect(handler.playbackState.value.processingState, AudioProcessingState.idle);
  });

  test('the position moving on is not sent on every tick', () async {
    await c.play();
    await session.settled;
    final before = sent.length;
    for (var s = 1; s <= 10; s++) {
      c.at = Duration(seconds: s);
      c.notifyListeners();
    }
    await session.settled;
    expect(sent.length, before);
  });

  test('swiping the app away keeps a playing song going in its notification; a paused song is put away', () async {
    await c.play();
    await session.settled;
    await nextPress();
    final calls = c.calls.length;
    await handler.onTaskRemoved();
    await session.settled;
    expect(c.calls.length, calls, reason: 'nothing is paused');
    expect(handler.playbackState.value.playing, isTrue);
    expect(handler.playbackState.value.processingState, isNot(AudioProcessingState.idle));

    await c.pause();
    await session.settled;
    await handler.onTaskRemoved();
    await session.settled;
    expect(handler.playbackState.value.processingState, AudioProcessingState.idle);
  });
}

/// audio_service's adapter with the handler made here (AudioService.init needs a platform).
class _HandlerAdapter implements MediaSessionAdapter {
  _HandlerAdapter(this._make);

  final MediaSession Function(void Function(MediaCommand)) _make;
  MediaSession? _handler;

  @override
  String get name => 'audio_service (test)';

  @override
  Future<bool> attach(void Function(MediaCommand) onCommand) async {
    _handler = _make(onCommand);
    return true;
  }

  @override
  Future<void> update(MediaSessionState state) async => _handler?.show(state);

  @override
  Future<void> detach() async {}
}
