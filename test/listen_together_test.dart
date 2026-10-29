import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/listen_together/lan.dart';
import 'package:riflay/services/listen_together/listen_together.dart';
import 'package:riflay/services/listen_together/protocol.dart';

const song = SharedTrack(videoId: 'abc', title: 'Song', artist: 'Artist', durationMs: 1000, artworkUrl: 'u');

void main() {
  group('protocol', () {
    test('round trips every message', () {
      final messages = <ListenMessage>[
        const Hello(name: 'Ana', guestId: 'g1'),
        const Welcome(hostName: 'Bo', guests: ['Ana'], suggestionsAllowed: true),
        const PlaybackState(track: song, playing: true, positionMs: 5, sentAtMs: 9, upNext: [song]),
        const PlaybackState(track: null, playing: false, positionMs: 0, sentAtMs: 1),
        const Ping(7),
        const Pong(pingAtMs: 7, hostAtMs: 8),
        const Suggest(song, from: 'Ana'),
        const Guests(['A', 'B']),
        const Bye(reason: 'x'),
        const Bye(),
      ];
      for (final m in messages) {
        final back = ListenMessage.decode(m.encode())!;
        expect(back.encode(), m.encode());
        expect(back.runtimeType, m.runtimeType);
      }
    });

    test('malformed input is null', () {
      for (final bad in [
        '',
        'nope',
        '[]',
        '{}',
        '{"t":"zzz"}',
        '{"t":"hello"}',
        '{"t":"ping","at":"x"}',
        '{"t":"suggest"}',
      ]) {
        expect(ListenMessage.decode(bad), isNull, reason: bad);
      }
    });

    test('positionAt', () {
      const playing = PlaybackState(track: song, playing: true, positionMs: 1000, sentAtMs: 5000);
      expect(playing.positionAt(7500), 3500);
      const paused = PlaybackState(track: song, playing: false, positionMs: 1000, sentAtMs: 5000);
      expect(paused.positionAt(9000), 1000);
    });
  });

  group('sync decisions', () {
    test('offset from a ping', () {
      // Sent at 1000, answered at 1100 (rtt 100); the host's clock read 5050 halfway: host = guest + 4000.
      expect(ListenSync.offsetOf(pingAtMs: 1000, hostAtMs: 5050, pongReceivedAtMs: 1100), 4000);
    });

    test('lowest round trip wins', () {
      final c = ClockSync();
      expect(c.offsetMs, 0);
      c.add(pingAtMs: 0, hostAtMs: 600, pongReceivedAtMs: 400); // rtt 400, offset 400
      c.add(pingAtMs: 1000, hostAtMs: 1010, pongReceivedAtMs: 1020); // rtt 20, offset 0
      c.add(pingAtMs: 2000, hostAtMs: 2500, pongReceivedAtMs: 2200); // rtt 200, offset 400
      expect(c.offsetMs, 0);
      expect(c.bestRttMs, 20);
    });

    test('target, drift, song change', () {
      const s = PlaybackState(track: song, playing: true, positionMs: 10000, sentAtMs: 50000);
      expect(ListenSync.targetMs(s, guestNowMs: 46000, offsetMs: 5000), 11000);
      expect(ListenSync.driftTooBig(10000, 10700), isFalse);
      expect(ListenSync.driftTooBig(10000, 10800), isTrue);
      expect(ListenSync.driftTooBig(10800, 10000), isTrue);
      expect(ListenSync.songDiffers('abc', song), isFalse);
      expect(ListenSync.songDiffers('x', song), isTrue);
      expect(ListenSync.songDiffers('x', null), isFalse);
    });
  });

  group('lan', () {
    test('codes avoid look-alikes', () {
      for (var i = 0; i < 200; i++) {
        expect(newLanCode(), matches(RegExp('^[$lanCodeAlphabet]{6}\$')));
      }
      expect(lanCodeAlphabet, isNot(anyOf(contains('0'), contains('O'), contains('1'), contains('I'))));
      expect(normalizeLanCode(' k7q 2xm '), 'K7Q2XM');
      expect('${lanJoinLink('K7Q2XM')}', 'riflay://listen?code=K7Q2XM');
    });

    test('beacons parse', () {
      final from = InternetAddress('192.168.1.5');
      final data = utf8.encode(LanBeacon.encode(name: 'Bo', code: 'K7Q2XM', port: 4000));
      final b = LanBeacon.parse(data, from)!;
      expect(b.name, 'Bo');
      expect('${b.socketUri}', 'ws://192.168.1.5:4000/listen/K7Q2XM');
      expect(LanBeacon.parse(utf8.encode('{"riflay":"listen","name":"x","code":"0O1I00","port":1}'), from), isNull);
      expect(LanBeacon.parse(utf8.encode('{"riflay":"other"}'), from), isNull);
      expect(LanBeacon.parse(utf8.encode('garbage'), from), isNull);
    });

    test('discovery lists and drops sessions', () async {
      final source = StreamController<LanBeacon>();
      final lists = <List<String>>[];
      final sub = LanDiscovery.find(
        source: source.stream,
        stale: const Duration(milliseconds: 300),
      ).listen((l) => lists.add([for (final f in l) f.code]));
      source.add(LanBeacon(name: 'Bo', code: 'K7Q2XM', port: 1, address: InternetAddress.loopbackIPv4));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(lists.last, ['K7Q2XM']);
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      expect(lists.last, isEmpty);
      await sub.cancel();
      await source.close();
    });

    // Multicast is not used here (it may not work in a sandbox): the guest connects to the host's address directly.
    test('host and guest talk over a loopback WebSocket', () async {
      final host = LanHostTransport(name: 'Bo');
      await host.start();
      addTearDown(host.stop);
      expect(host.code, hasLength(6));
      expect('${host.joinLink}', contains(host.code));

      final peerFuture = host.peers.first;
      final guest = await LanGuestConnection.connectTo(Uri.parse('ws://127.0.0.1:${host.port}/listen/${host.code}'));
      addTearDown(guest.close);
      final peer = await peerFuture;
      final atHost = StreamIterator(peer.incoming);
      final atGuest = StreamIterator(guest.incoming);

      guest.send(const Hello(name: 'Ana', guestId: 'g').encode());
      expect(await atHost.moveNext(), isTrue);
      expect((ListenMessage.decode(atHost.current) as Hello).name, 'Ana');

      peer.send(const Welcome(hostName: 'Bo', guests: ['Ana'], suggestionsAllowed: true).encode());
      peer.send(const PlaybackState(track: song, playing: true, positionMs: 42, sentAtMs: 1).encode());
      expect(await atGuest.moveNext(), isTrue);
      expect(ListenMessage.decode(atGuest.current), isA<Welcome>());
      expect(await atGuest.moveNext(), isTrue);
      final state = ListenMessage.decode(atGuest.current) as PlaybackState;
      expect(state.track, song);
      expect(state.positionMs, 42);

      await peer.close();
      expect(await atGuest.moveNext(), isFalse);
    });

    test('the wrong path is refused', () async {
      final host = LanHostTransport(name: 'Bo');
      await host.start();
      addTearDown(host.stop);
      await expectLater(
        LanGuestConnection.connectTo(Uri.parse('ws://127.0.0.1:${host.port}/listen/WRONG2')),
        throwsA(anything),
      );
    });

    test('connecting by code times out when nobody announces it', () async {
      await expectLater(
        LanGuestConnection.connect('ZZZZZZ', timeout: const Duration(milliseconds: 500)),
        throwsA(anything),
      );
    });
  });
}
