import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show HSLColor;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/home_widget.dart';
import 'package:riflay/services/language.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A player whose song, play state and shuffle the test sets, and tells its listeners as the real one does.
class _Player extends PlayerController {
  Track? track;
  bool playing = false;
  bool shuffled = false;
  int shuffles = 0;
  int playbackToggles = 0;
  String? quality;

  @override
  Track? get currentTrack => track;
  @override
  String? qualityOf(Track track) => quality;
  @override
  bool get showsPlaying => playing;
  @override
  bool get shuffle => shuffled;
  @override
  Duration get position => const Duration(seconds: 30);
  @override
  Duration? get duration => const Duration(minutes: 2);
  @override
  Future<void> toggleShuffle() async {
    shuffles++;
    shuffled = !shuffled;
    notifyListeners();
  }

  @override
  Future<void> togglePlay() async {
    playbackToggles++;
    playing = !playing;
    notifyListeners();
  }

  void change() => notifyListeners();
}

final _song = Track(id: 'song', uri: Uri.parse('file:///song.flac'), title: 'Song', artist: 'Artist');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('riflay/home_widget');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late _Player player;
  late HomeWidget widget;
  late List<Map<Object?, Object?>> sent;
  late List<Map<Object?, Object?>> lyrics;
  late ValueNotifier<String?> line;
  late ValueNotifier<String?> next;
  late int pendingPlaybackToggles;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sent = [];
    lyrics = [];
    line = ValueNotifier(null);
    next = ValueNotifier(null);
    pendingPlaybackToggles = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'update') sent.add(call.arguments as Map<Object?, Object?>);
      if (call.method == 'lyric') lyrics.add(call.arguments as Map<Object?, Object?>);
      if (call.method == 'takePlaybackToggles') {
        final count = pendingPlaybackToggles;
        pendingPlaybackToggles = 0;
        return count;
      }
      return null;
    });
    player = _Player();
    widget = HomeWidget(
      player,
      channel: channel,
      coverFile: (t) async => '/cache/${t.id}.img',
      accent: (_) async => const Color(0xFF3366CC),
      lyric: line,
      lyricNext: next,
    )..attach();
  });

  test('the line being sung and the next go together, on their own, and stay in the next full update', () async {
    player
      ..track = _song
      ..change();
    await pumpEventQueue();
    final count = sent.length;
    line.value = 'Not, not R.I.P.';
    next.value = 'Get up, get up';
    await pumpEventQueue();
    expect(lyrics, [
      {'lyric': 'Not, not R.I.P.', 'said': null, 'next': 'Get up, get up'},
    ], reason: 'one send for both lines');
    expect(sent, hasLength(count), reason: 'a line alone does not redraw the widget');
    player
      ..playing = true
      ..change();
    expect(sent.last['lyric'], 'Not, not R.I.P.');
    expect(sent.last['next'], 'Get up, get up');
    line.value = null;
    await pumpEventQueue();
    expect(lyrics.last['lyric'], isNull);
  });

  test('the format is sent short, as the mini window shows it, once it is known', () {
    player
      ..track = _song
      ..change();
    expect(sent.last['quality'], isNull);
    player
      ..quality = 'FLAC · 24-bit / 96 kHz'
      ..change();
    expect(sent.last['quality'], 'FLAC 24/96');
  });

  test('repeat is sent as the player has it', () {
    player
      ..track = _song
      ..change();
    expect(sent.last['loop'], 'off');
  });

  tearDown(() {
    widget.detach();
    messenger.setMockMethodCallHandler(channel, null);
    player.dispose();
  });

  test('with nothing playing it says so, with no cover or colours of a song', () {
    expect(sent, hasLength(1));
    expect(sent.single['hasTrack'], isFalse);
    expect(sent.single['title'], tr.nothingPlaying);
    expect(sent.single['quality'], isNull);
    expect(sent.single['colors'], isNull);
    expect(sent.single['cover'], isNull);
  });

  test('sends the song when it changes, then once more with its cover and colours', () async {
    player
      ..track = _song
      ..playing = true
      ..change();
    expect(sent.last['title'], 'Song');
    expect(sent.last['artist'], 'Artist');
    expect(sent.last['playing'], isTrue);
    expect(sent.last['position'], 30000);
    expect(sent.last['duration'], 120000);
    // Not signed in to YouTube Music, and a file besides: no like button.
    expect(sent.last['liked'], isNull);
    await pumpEventQueue();
    expect(sent.last['cover'], '/cache/song.img');
    expect(sent.last['colors'], HomeWidgetColors.from(const Color(0xFF3366CC)).toMap());
  });

  test('is not sent again when nothing it shows changed', () async {
    player
      ..track = _song
      ..change();
    await pumpEventQueue();
    final count = sent.length;
    player
      ..change()
      ..change();
    expect(sent, hasLength(count));
    player
      ..playing = true
      ..change();
    expect(sent, hasLength(count + 1));
    expect(sent.last['playing'], isTrue);
  });

  test('a cover that arrives after the song changed again is dropped', () async {
    player
      ..track = _song
      ..change();
    player
      ..track = Track(id: 'other', uri: Uri.parse('file:///other.flac'), title: 'Other', artist: 'Someone')
      ..change();
    await pumpEventQueue();
    expect(sent.last['title'], 'Other');
    expect(sent.last['cover'], '/cache/other.img');
    expect(sent.where((s) => s['title'] == 'Other' && s['cover'] == '/cache/song.img'), isEmpty);
  });

  test('shuffle pressed on the widget shuffles, and the widget is told', () async {
    player
      ..track = _song
      ..change();
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('shuffle')),
      (_) {},
    );
    expect(player.shuffles, 1);
    expect(sent.last['shuffle'], isTrue);
  });

  test('a pending widget tap is drained on attach and a later tap toggles the actual player', () async {
    player
      ..track = _song
      ..playing = true
      ..change();
    await pumpEventQueue();
    widget.detach();
    pendingPlaybackToggles = 1;
    widget.attach();
    await pumpEventQueue();
    expect(player.playbackToggles, 1);
    expect(sent.last['playing'], isFalse);

    pendingPlaybackToggles = 1;
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('playbackActionAvailable')),
      (_) {},
    );
    await pumpEventQueue();
    expect(player.playbackToggles, 2);
    expect(sent.last['playing'], isTrue);
  });

  test('white text and the accent read on the card, and play / pause on its accent button, whatever the cover', () {
    // WCAG's contrast ratio; 4.5 is its bar for body text.
    double contrast(Color a, Color b) {
      final (x, y) = (a.computeLuminance(), b.computeLuminance());
      return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
    }

    const white = Color(0xFFFFFFFF);
    const covers = [Color(0xFFFFF4C2), Color(0xFF0A0A0A), Color(0xFFE53935), Color(0xFF808080), Color(0xFF1A237E)];
    for (final cover in covers) {
      final c = HomeWidgetColors.from(cover);
      expect(contrast(c.surface, white), greaterThanOrEqualTo(4.5), reason: '$cover');
      expect(contrast(c.accent, c.onAccent), greaterThanOrEqualTo(4.5), reason: '$cover');
      expect(contrast(c.accent, c.surface), greaterThanOrEqualTo(4.5), reason: 'the line being sung reads: $cover');
    }
  });

  test('a grey cover keeps a grey accent', () {
    final c = HomeWidgetColors.from(const Color(0xFF808080));
    expect(HSLColor.fromColor(c.accent).saturation, lessThan(0.12));
  });
}
