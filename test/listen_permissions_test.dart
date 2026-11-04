import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/listen_together/listen_together.dart';
import 'package:riflay/services/listen_together/protocol.dart';
import 'package:riflay/services/listen_together/transport.dart';

class TestPlayer extends PlayerController {
  final song = Track.youtube(
    videoId: 'current',
    title: 'Current',
    artist: 'Artist',
    duration: const Duration(minutes: 10),
  );
  final requested = <Track>[];
  final seeks = <Duration>[];
  @override
  Track get currentTrack => song;
  @override
  List<Track> get queue => [song, ...requested];

  /// What [queueAfter] was told to queue after, each time.
  final afters = <Set<String>>[];
  @override
  Future<void> queueAfter(List<Track> tracks, {required Set<String> after}) async {
    afters.add({...after});
    requested.addAll(tracks);
  }

  @override
  Future<void> seek(Duration to) async {
    seeks.add(to);
  }
}

class TestPeer implements ListenPeer {
  final frames = StreamController<String>.broadcast(sync: true);
  final sent = <ListenMessage>[];
  @override
  String get id => 'peer';
  @override
  Stream<String> get incoming => frames.stream;
  @override
  void send(String message) => sent.add(ListenMessage.decode(message)!);
  @override
  Future<void> close() async {
    await frames.close();
  }
}

class TestHost implements ListenHostTransport {
  final connections = StreamController<ListenPeer>.broadcast(sync: true);
  @override
  String get code => 'K7Q2XM';
  @override
  Uri get joinLink => Uri.parse('riflay://listen?code=$code');
  @override
  Stream<ListenPeer> get peers => connections.stream;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {
    await connections.close();
  }
}

class TestGuest implements ListenGuestConnection {
  final frames = StreamController<String>.broadcast(sync: true);
  final sent = <ListenMessage>[];
  @override
  Stream<String> get incoming => frames.stream;
  @override
  void send(String message) {
    final decoded = ListenMessage.decode(message)!;
    sent.add(decoded);
    if (decoded is Hello) {
      frames.add(const Welcome(hostName: 'Host', guests: ['Guest'], suggestionsAllowed: true).encode());
      // Hosts send the initial state right after Welcome, before join() resumes.
      frames.add(
        const PlaybackState(
          track: SharedTrack(videoId: 'current', title: 'Current', artist: 'Artist'),
          playing: false,
          positionMs: 0,
          sentAtMs: 0,
        ).encode(),
      );
    }
  }

  @override
  Future<void> close() async {
    await frames.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('host enforces suggestions and seek permissions on incoming messages', () async {
    final player = TestPlayer();
    final transport = TestHost();
    final session = ListenTogether(player, hostTransport: (_, _) => transport);
    await session.host(mode: ListenMode.wifi, name: 'Host');
    final peer = TestPeer();
    transport.connections.add(peer);
    const suggestion = Suggest(
      SharedTrack(videoId: 'next', title: 'Next', artist: 'Artist'),
      from: 'Spoofed',
    );
    // A connected peer must identify itself before requesting anything.
    peer.frames.add(suggestion.encode());
    expect(player.requested, isEmpty);
    peer.frames.add(const Hello(name: 'Guest', guestId: 'guest').encode());
    expect(peer.sent.whereType<Welcome>().last.seekingAllowed, isFalse);
    peer.frames.add(suggestion.encode());
    expect(player.requested.single.videoId, 'next');
    await session.setSuggestionsAllowed(false);
    peer.frames.add(suggestion.encode());
    expect(player.requested, hasLength(1));
    peer.frames.add(const SeekRequest(480000, videoId: 'current').encode());
    expect(player.seeks, isEmpty);
    await session.setSeekingAllowed(true);
    expect(peer.sent.whereType<Welcome>().last.seekingAllowed, isTrue);
    expect(peer.sent.whereType<Welcome>().last.suggestionsAllowed, isFalse);
    peer.frames.add(const SeekRequest(480000, videoId: 'current').encode());
    expect(player.seeks, [const Duration(minutes: 8)]);
    peer.frames.add(const SeekRequest(480000, videoId: 'previous-song').encode());
    peer.frames.add(const SeekRequest(900000, videoId: 'current').encode());
    peer.frames.add('{"t":"seek","pos":-1,"videoId":"current"}');
    expect(player.seeks, hasLength(1));
    await session.setSeekingAllowed(false);
    peer.frames.add(const SeekRequest(0, videoId: 'current').encode());
    expect(player.seeks, hasLength(1));
    await session.leave();
    session.dispose();
  });

  test('guest sends next-song and seek requests and receives live permission changes', () async {
    final player = TestPlayer();
    final connection = TestGuest();
    final session = ListenTogether(player, guestConnection: (_, _) async => connection);
    await session.join(code: 'K7Q2XM', name: 'Guest');
    await Future<void>.delayed(Duration.zero);
    expect(session.hostTrack?.videoId, 'current', reason: 'initial state must survive the welcome handshake');
    expect(session.role, ListenRole.guest);
    await session.suggest(Track.youtube(videoId: 'next', title: 'Next', artist: 'Artist'));
    expect(connection.sent.whereType<Suggest>().single.track.videoId, 'next');
    expect(session.requestSeek(const Duration(minutes: 8)), isTrue);
    expect(connection.sent.whereType<SeekRequest>(), isEmpty);
    connection.frames.add(
      const Welcome(hostName: 'Host', guests: ['Guest'], suggestionsAllowed: false, seekingAllowed: true).encode(),
    );
    expect(session.suggestionsAllowed, isFalse);
    expect(session.seekingAllowed, isTrue);
    await session.suggest(player.song);
    expect(connection.sent.whereType<Suggest>(), hasLength(1));
    session.requestSeek(const Duration(minutes: 8));
    final seek = connection.sent.whereType<SeekRequest>().single;
    expect(seek.positionMs, 480000);
    expect(seek.videoId, 'current');
    connection.frames.add(const Welcome(hostName: 'Host', guests: [], suggestionsAllowed: true).encode());
    session.requestSeek(const Duration(seconds: 2));
    expect(connection.sent.whereType<SeekRequest>(), hasLength(1));
    await session.leave();
    expect(session.requestSeek(const Duration(seconds: 2)), isFalse);
    session.dispose();
  });

  test('songs friends add go into the host\'s queue in the order they came', () async {
    final player = TestPlayer();
    final transport = TestHost();
    final session = ListenTogether(player, hostTransport: (_, _) => transport);
    await session.host(mode: ListenMode.wifi, name: 'Host');
    final ana = TestPeer(), budi = TestPeer();
    for (final (peer, name) in [(ana, 'Ana'), (budi, 'Budi')]) {
      transport.connections.add(peer);
      peer.frames.add(Hello(name: name, guestId: name).encode());
    }
    expect(session.listeners, ['Ana', 'Budi'], reason: 'the host sees who joined, by name');
    ana.frames.add(
      const Suggest(
        SharedTrack(videoId: 'a', title: 'A', artist: 'X'),
        from: 'Ana',
      ).encode(),
    );
    budi.frames.add(
      const Suggest(
        SharedTrack(videoId: 'b', title: 'B', artist: 'X'),
        from: 'Budi',
      ).encode(),
    );
    expect(player.requested.map((t) => t.videoId), ['a', 'b']);
    expect(player.afters.first, isEmpty, reason: 'the first goes right after the current song');
    expect(player.afters.last, contains(player.requested.first.id), reason: 'the second goes after the first');
    await session.leave();
    session.dispose();
  });

  test('a guest picking a song adds it to the host\'s queue and stays in the session', () async {
    final player = TestPlayer();
    final connection = TestGuest();
    final session = ListenTogether(player, guestConnection: (_, _) async => connection);
    ListenTogether.use(player, session);
    await session.join(code: 'K7Q2XM', name: 'Guest');
    await Future<void>.delayed(Duration.zero);
    final events = <String>[];
    final sub = session.events.listen(events.add);
    await player.playList([Track.youtube(videoId: 'mine', title: 'Mine', artist: 'Artist')], 0);
    await Future<void>.delayed(Duration.zero);
    expect(connection.sent.whereType<Suggest>().single.track.videoId, 'mine');
    expect(session.role, ListenRole.guest, reason: 'picking a song no longer leaves the session');
    expect(events, ['Added Mine to Host\'s queue']);
    // The host turned adding songs off: nothing is sent, and the guest is told why.
    connection.frames.add(const Welcome(hostName: 'Host', guests: ['Guest'], suggestionsAllowed: false).encode());
    await player.playList([Track.youtube(videoId: 'other', title: 'Other', artist: 'Artist')], 0);
    await Future<void>.delayed(Duration.zero);
    expect(connection.sent.whereType<Suggest>(), hasLength(1));
    expect(events.last, 'Host isn\'t taking songs right now.');
    await sub.cancel();
    await session.leave();
    session.dispose();
  });

  test('old hosts deny guest seeks by default; invalid requests are discarded', () {
    final legacy = ListenMessage.decode('{"t":"welcome","name":"Host","guests":[],"suggest":true}') as Welcome;
    expect(legacy.seekingAllowed, isFalse);
    for (final pos in ['-1', '1.5', '"480000"', 'null']) {
      expect(ListenMessage.decode('{"t":"seek","pos":$pos,"videoId":"current"}'), isNull);
    }
    const request = SeekRequest(480000, videoId: 'current');
    expect(ListenMessage.decode(request.encode())!.encode(), request.encode());
  });
}
