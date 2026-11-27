import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/connect/connect_channel.dart';
import 'package:riflay/services/player_controller.dart';

/// An in-memory MQTT broker: delivers a publish to every link subscribed to a matching topic (`+` matches one
/// level), the way the real ones do, so Connect's two sides can talk without the network.
class FakeBroker {
  final links = <FakeLink>[];

  /// Every publish, as the broker saw it: what a curious operator would read.
  final seen = <(String, Uint8List)>[];

  FakeLink connect() {
    final link = FakeLink(this);
    links.add(link);
    return link;
  }

  Future<ConnectLink> open(Object? _) async => connect();

  /// The connection to every client dies.
  void dropAll() {
    for (final l in links.toList()) {
      l.kill();
    }
  }

  static bool matches(String filter, String topic) {
    final f = filter.split('/'), t = topic.split('/');
    if (f.length != t.length) return false;
    for (var i = 0; i < f.length; i++) {
      if (f[i] != '+' && f[i] != t[i]) return false;
    }
    return true;
  }
}

class FakeLink implements ConnectLink {
  FakeLink(this._broker);

  final FakeBroker _broker;
  final _filters = <String>{};
  final _in = StreamController<(String, Uint8List)>.broadcast(sync: true);
  final _down = Completer<void>();
  var _up = true;

  @override
  Stream<(String, Uint8List)> get messages => _in.stream;
  @override
  Future<void> get down => _down.future;
  @override
  bool get isUp => _up;
  @override
  void subscribe(String topic) => _filters.add(topic);

  @override
  void publish(String topic, Uint8List data) {
    if (!_up) return;
    _broker.seen.add((topic, data));
    for (final l in _broker.links.toList()) {
      if (l._up && l._filters.any((f) => FakeBroker.matches(f, topic))) l._in.add((topic, data));
    }
  }

  void kill() {
    if (!_up) return;
    _up = false;
    _broker.links.remove(this);
    if (!_down.isCompleted) _down.complete();
  }

  @override
  Future<void> close() async => kill();
}

/// A player that records what it was asked, standing in for the real [PlayerController].
class FakeConnectPlayer implements PlayerController {
  final _notifier = ChangeNotifier();
  final calls = <String>[];
  final local = Track.fromUri(Uri.file('/home/ana/Music/Secret Folder/Song.flac'));
  final remote = Track.youtube(videoId: 'abcdefghijk', title: 'Remote song', artist: 'Artist');
  final List<Track> queued = [];
  bool playing = false;
  bool shuffled = false;
  double level = 0.5;
  LoopMode loop = LoopMode.off;
  Duration? length = const Duration(seconds: 200);
  Duration at = const Duration(seconds: 10);
  bool volumeAllowed = true;

  void changed() => _notifier.notifyListeners();

  @override
  void addListener(VoidCallback listener) => _notifier.addListener(listener);
  @override
  void removeListener(VoidCallback listener) => _notifier.removeListener(listener);
  @override
  bool get hasListeners => _notifier.hasListeners;

  @override
  bool get showsPlaying => playing;
  @override
  Track? get currentTrack => queued.firstOrNull;
  @override
  List<Track> get queue => List.of(queued);
  @override
  int? get queueIndex => queued.isEmpty ? null : 0;
  @override
  Duration get position => at;
  @override
  Duration? get duration => length;
  @override
  double get volume => level;
  @override
  bool get canSetVolume => volumeAllowed;
  @override
  bool get shuffle => shuffled;
  @override
  LoopMode get loopMode => loop;
  @override
  bool get hasQueue => queued.isNotEmpty;
  @override
  bool get hasNext => queued.length > 1;

  @override
  Future<void> play() async {
    calls.add('play');
    playing = true;
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    playing = false;
  }

  @override
  Future<void> next() async => calls.add('next');
  @override
  Future<void> previous() async => calls.add('previous');
  @override
  Future<void> seek(Duration to) async {
    calls.add('seek ${to.inMilliseconds}');
    at = to;
  }

  @override
  Future<void> setVolume(double v) async {
    calls.add('volume $v');
    level = v;
  }

  @override
  Future<void> toggleShuffle() async {
    calls.add('shuffle');
    shuffled = !shuffled;
  }

  @override
  Future<void> cycleLoopMode() async {
    calls.add('cycle');
    loop = switch (loop) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
  }

  @override
  Future<void> addToQueue(List<Track> tracks) async {
    calls.add('add ${tracks.map((t) => t.videoId).join(',')}');
    queued.addAll(tracks);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Waits, in short steps, until [test] holds.
Future<void> until(bool Function() test, {Duration limit = const Duration(seconds: 3)}) async {
  final end = DateTime.now().add(limit);
  while (!test()) {
    if (DateTime.now().isAfter(end)) fail('condition never held');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
