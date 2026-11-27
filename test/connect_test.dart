import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:riflay/services/connect/connect_channel.dart';
import 'package:riflay/services/connect/connect_controller.dart';
import 'package:riflay/services/connect/connect_host.dart';
import 'package:riflay/services/connect/connect_protocol.dart';
import 'package:riflay/services/connect/connect_store.dart';
import 'package:riflay/services/listen_together/internet.dart';
import 'package:riflay/services/listen_together/protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connect_support.dart';

void main() {
  group('encryption', () {
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    final other = Uint8List.fromList(List.generate(32, (i) => 255 - i));
    const topic = 'riflay/c1/abc/c';

    test('a message opens with the key and topic it was made for', () {
      final data = ConnectChannel.encode(key, topic, {'t': 'play', 'n': 1});
      expect(ConnectChannel.decode(key, topic, data), {'t': 'play', 'n': 1});
    });

    test('a message made with another key is rejected', () {
      final data = ConnectChannel.encode(other, topic, {'t': 'play', 'n': 1});
      expect(ConnectChannel.decode(key, topic, data), isNull);
    });

    test('a changed byte, another topic, junk and a stale message are rejected', () {
      final data = ConnectChannel.encode(key, topic, {'t': 'play', 'n': 1});
      final changed = Uint8List.fromList(data)..[20] ^= 1;
      expect(ConnectChannel.decode(key, topic, changed), isNull);
      expect(ConnectChannel.decode(key, 'riflay/c1/abc/h', data), isNull, reason: 'replayed on the other direction');
      expect(ConnectChannel.decode(key, topic, Uint8List(5)), isNull);
      expect(ConnectChannel.decode(key, topic, Uint8List.fromList(List.filled(60, 7))), isNull);
      final old = ConnectChannel.encode(key, topic, {'t': 'play'}, nowMs: 1000);
      expect(ConnectChannel.decode(key, topic, old, nowMs: 1000 + 3 * 60 * 1000), isNull);
    });

    test('the same message never encrypts the same way twice (random nonce)', () {
      final a = ConnectChannel.encode(key, topic, {'t': 'play'});
      final b = ConnectChannel.encode(key, topic, {'t': 'play'});
      expect(a, isNot(b));
      expect(a.sublist(0, 12), isNot(b.sublist(0, 12)));
    });

    test('nothing readable is left in what the broker carries', () {
      final data = ConnectChannel.encode(key, topic, {'t': 'state', 'title': 'Secret Title'});
      expect(latin1.decode(data, allowInvalid: true), isNot(contains('Secret')));
    });
  });

  group('topics', () {
    test('come from the code, the same every time', () {
      final a = ConnectKeys.pairing('ABCDEFGHJK'), b = ConnectKeys.pairing('ABCDEFGHJK');
      expect(a.room, b.room);
      expect(a.pairingFromControllers, b.pairingFromControllers);
      expect(a.key, b.key);
      expect(ConnectKeys.pairing('ABCDEFGHJL').room, isNot(a.room));
    });

    test('are random-looking and give nothing of the code away', () {
      final keys = ConnectKeys.pairing('ABCDEFGHJK');
      expect(keys.room, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(keys.pairingFrom('abcdefghijkl'), 'riflay/c1/${keys.room}/g/abcdefghijkl');
      expect(keys.pairingTo('abcdefghijkl'), 'riflay/c1/${keys.room}/t/abcdefghijkl');
      for (final topic in [keys.toHost, keys.toController, keys.pairingFromControllers]) {
        expect(topic.toUpperCase(), isNot(contains('ABCDEFGHJK')));
      }
    });

    test('Listen together and Connect never share a room or a key for the same code', () {
      final listen = InternetRoomKeys.of('ABCDEFGHJK'), connect = ConnectKeys.pairing('ABCDEFGHJK');
      expect(connect.room, isNot(listen.room));
      expect(connect.key, isNot(listen.key));
    });

    test('a pair secret makes its own room and key; each direction has its own topic', () {
      final s1 = newConnectSecret(Random(1)), s2 = newConnectSecret(Random(2));
      final a = ConnectKeys.paired(s1), b = ConnectKeys.paired(s2);
      expect(a.room, isNot(b.room));
      expect(a.key, isNot(b.key));
      expect(a.toHost, isNot(a.toController));
      expect(newConnectSecret(), hasLength(connectSecretLength));
    });

    test('only a well-formed peer id is read off a pairing topic', () {
      final keys = ConnectKeys.pairing('ABCDEFGHJK');
      expect(keys.pairingPeerOf(keys.pairingFrom('abcdefghijkl')), 'abcdefghijkl');
      expect(keys.pairingPeerOf(keys.pairingTo('abcdefghijkl')), isNull);
      expect(keys.pairingPeerOf('${keys.pairingFromControllers.replaceAll('+', '')}../x'), isNull);
    });
  });

  group('pairing key agreement', () {
    test('both sides get the same key, bound to the code', () {
      final a = ConnectPairingKey.generate(), b = ConnectPairingKey.generate();
      final ka = a.agree(b.publicKey, 'ABCDEFGHJK'), kb = b.agree(a.publicKey, 'ABCDEFGHJK');
      expect(ka, kb);
      expect(ka, hasLength(32));
      expect(a.agree(b.publicKey, 'ABCDEFGHJL'), isNot(ka));
    });

    test('a point that is not on the curve is refused', () {
      final a = ConnectPairingKey.generate();
      final bad = Uint8List.fromList(a.publicKey)..[40] ^= 1;
      expect(a.agree(bad, 'ABCDEFGHJK'), isNull);
      expect(a.agree(Uint8List(65), 'ABCDEFGHJK'), isNull);
      expect(a.agree(Uint8List(10), 'ABCDEFGHJK'), isNull);
    });
  });

  test('retries wait longer each time, up to a minute', () {
    final waits = [for (var i = 0; i < 10; i++) connectBackoff(i).inSeconds];
    expect(waits.first, 2);
    expect(waits, orderedEquals([...waits]..sort()));
    expect(waits.last, 60);
  });

  group('codes and names', () {
    test('a pairing link and a typed code both give the code; other text gives none', () {
      expect(connectCodeFrom('riflay://connect?code=ABCDEFGHJK'), 'ABCDEFGHJK');
      expect(connectCodeFrom('abcde-fghjk'), 'ABCDEFGHJK');
      expect(connectCodeFrom(connectPairingLink('ABCDEFGHJK').toString()), 'ABCDEFGHJK');
      expect(connectCodeFrom('riflay://listen?code=ABCDEFGHJK'), isNull, reason: 'a Listen together link is not ours');
      expect(connectCodeFrom('K7Q2XM'), isNull, reason: 'a Wi-Fi code is not a Connect code');
      expect(connectCodeFrom('https://example.com'), isNull);
    });

    test('a name from another device is plain and short', () {
      expect(cleanConnectName('  Ana\u202e\n '), 'Ana');
      expect(cleanConnectName(''), 'Riflay');
      expect(cleanConnectName(5), 'Riflay');
      expect(cleanConnectName('x' * 100), hasLength(32));
    });
  });

  group('protocol', () {
    test('commands round-trip, and bad values are refused', () {
      for (final c in <ConnectCommand>[
        const ConnectPlay(),
        const ConnectPause(),
        const ConnectNext(),
        const ConnectPrevious(),
        const ConnectSeek(1500),
        const ConnectVolume(0.4),
        const ConnectShuffle(true),
        const ConnectSetRepeat(ConnectRepeat.one),
        const ConnectAdd(SharedTrack(videoId: 'abcdefghijk', title: 't', artist: 'a')),
      ]) {
        expect(ConnectCommand.fromJson(c.toJson())?.toJson(), c.toJson());
      }
      expect(ConnectCommand.fromJson({'t': 'seek', 'ms': -1}), isNull);
      expect(ConnectCommand.fromJson({'t': 'vol', 'v': 1.5}), isNull);
      expect(ConnectCommand.fromJson({'t': 'repeat', 'mode': 'forever'}), isNull);
      expect(ConnectCommand.fromJson({'t': 'rm -rf'}), isNull);
      expect(
        ConnectCommand.fromJson({
          't': 'add',
          'track': {'videoId': '../../etc', 'title': 't', 'artist': 'a'},
        }),
        isNull,
      );
    });

    test('the position keeps counting while it plays, and stops at the end', () {
      const s = ConnectState(
        playing: true,
        positionMs: 1000,
        durationMs: 5000,
        volume: 0.5,
        shuffle: false,
        repeat: ConnectRepeat.off,
        queue: [],
        queueIndex: null,
        atMs: 0,
      );
      expect(s.positionAt(2500, 2000), const Duration(milliseconds: 1500));
      expect(s.positionAt(99999, 2000), const Duration(milliseconds: 5000));
    });
  });

  group('commands reach the PlayerController', () {
    late FakeConnectPlayer p;
    setUp(() {
      p = FakeConnectPlayer();
      p.queued.addAll([p.remote, p.local]);
    });

    test('play, pause, next, previous, seek, volume', () async {
      await applyConnectCommand(p, const ConnectPlay());
      await applyConnectCommand(p, const ConnectNext());
      await applyConnectCommand(p, const ConnectPrevious());
      await applyConnectCommand(p, const ConnectSeek(30000));
      await applyConnectCommand(p, const ConnectVolume(0.25));
      await applyConnectCommand(p, const ConnectPause());
      expect(p.calls, ['play', 'next', 'previous', 'seek 30000', 'volume 0.25', 'pause']);
    });

    test('a seek past the end stops at the end', () async {
      await applyConnectCommand(p, const ConnectSeek(999999));
      expect(p.calls, ['seek 200000']);
    });

    test('shuffle toggles only when it differs; repeat cycles to the mode', () async {
      await applyConnectCommand(p, const ConnectShuffle(false));
      expect(p.calls, isEmpty);
      await applyConnectCommand(p, const ConnectShuffle(true));
      expect(p.shuffled, isTrue);
      await applyConnectCommand(p, const ConnectSetRepeat(ConnectRepeat.one));
      expect(p.loop, LoopMode.one);
      await applyConnectCommand(p, const ConnectSetRepeat(ConnectRepeat.off));
      expect(p.loop, LoopMode.off);
    });

    test('add puts a YouTube song at the end of the queue', () async {
      await applyConnectCommand(p, const ConnectAdd(SharedTrack(videoId: 'zzzzzzzzzzz', title: 'New', artist: 'Them')));
      expect(p.calls, ['add zzzzzzzzzzz']);
      expect(p.queued.last.title, 'New');
    });

    test('an output without volume control is left alone; an empty queue is not started or skipped', () async {
      p.volumeAllowed = false;
      await applyConnectCommand(p, const ConnectVolume(0.1));
      p.queued.clear();
      await applyConnectCommand(p, const ConnectPlay());
      await applyConnectCommand(p, const ConnectNext());
      await applyConnectCommand(p, const ConnectSeek(1000));
      expect(p.calls, isEmpty);
    });

    test('the state sent out has no file path, folder or local id', () {
      p.queued
        ..clear()
        ..addAll([p.local, p.remote]);
      final json = jsonEncode(connectSnapshot(p).toJson());
      expect(json, contains('Remote song'));
      expect(json, isNot(contains('Secret Folder')));
      expect(json, isNot(contains('/home')));
      expect(json, isNot(contains('file:')));
      expect(json, isNot(contains(p.local.id)));
    });
  });

  group('pairing, control and revoking', () {
    late FakeBroker broker;
    late FakeConnectPlayer player;
    late ConnectHost host;
    late ConnectController controller;
    late ConnectStore hostStore, controllerStore;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      broker = FakeBroker();
      player = FakeConnectPlayer();
      player.queued.add(player.remote);
      final prefs = await SharedPreferences.getInstance();
      hostStore = ConnectStore(prefs);
      controllerStore = ConnectStore(prefs);
      host = ConnectHost(
        player,
        openStore: () async => hostStore,
        opener: broker.open,
        deviceName: 'Windows',
        stateDelay: const Duration(milliseconds: 10),
        backoff: (_) => const Duration(milliseconds: 20),
      );
      controller = ConnectController(
        openStore: () async => controllerStore,
        opener: broker.open,
        deviceName: 'Android 7QK2',
        backoff: (_) => const Duration(milliseconds: 20),
        hostSilence: const Duration(seconds: 5),
      );
      await host.load();
      await controller.load();
    });

    tearDown(() async {
      controller.dispose();
      host.dispose();
    });

    Future<void> pairAndConnect() async {
      await host.beginPairing();
      await until(() => broker.links.isNotEmpty && host.pairingCode != null);
      final pairing = controller.pair(host.pairingCode!);
      await until(() => host.pending != null);
      await host.approve();
      await pairing;
      await until(() => controller.state == ConnectLinkState.connected);
    }

    test('the desktop does nothing to playback until it is asked, and never without a confirmed pairing', () async {
      await host.beginPairing();
      await until(() => host.pairingCode != null);
      final pairing = controller.pair(host.pairingCode!);
      await until(() => host.pending != null);
      expect(host.pending!.name, 'Android 7QK2');
      expect(player.calls, isEmpty);
      expect(controller.hosts, isEmpty, reason: 'nothing is granted before the owner confirms');
      host.deny();
      await expectLater(
        pairing,
        throwsA(isA<ConnectPairException>().having((e) => e.problem, 'problem', ConnectPairProblem.denied)),
      );
      expect(host.controllers, isEmpty);
      expect(host.pairingCode, isNull, reason: 'a refused code is spent');
    });

    test('confirming pairs: the controller gets a state and its commands play, pause and so on', () async {
      await pairAndConnect();
      expect(controller.active!.name, 'Windows');
      expect(host.controllers.single.name, 'Android 7QK2');
      expect(controller.remote!.track!.title, 'Remote song');
      expect(controller.remote!.playing, isFalse);

      expect(controller.play(), isTrue);
      await until(() => player.calls.contains('play'));
      await until(() => controller.remote!.playing);
      controller.seek(const Duration(seconds: 42));
      controller.setVolume(0.3);
      controller.setShuffle(true);
      await until(() => player.calls.contains('shuffle'));
      expect(player.calls, containsAll(['play', 'seek 42000', 'volume 0.3', 'shuffle']));
      await until(() => controller.remote!.shuffle);
    });

    test('the pairing code works once: after a pairing the desktop no longer listens for it', () async {
      await pairAndConnect();
      expect(host.pairingCode, isNull);
      expect(host.pending, isNull);
    });

    test('the broker only ever carries encrypted bytes, and none of the long-lived secret', () async {
      await pairAndConnect();
      final secret = host.controllers.single.secret;
      for (final (topic, data) in broker.seen) {
        expect(topic, startsWith('riflay/c1/'));
        final text = latin1.decode(data, allowInvalid: true);
        expect(text, isNot(contains('Remote song')));
        expect(text, isNot(contains('Android')));
        expect(latin1.decode(data, allowInvalid: true), isNot(contains(latin1.decode(secret, allowInvalid: true))));
      }
    });

    test('a message made with the wrong key, or replayed, changes nothing', () async {
      await pairAndConnect();
      final keys = ConnectKeys.paired(host.controllers.single.secret);
      final stranger = broker.connect();
      final wrong = ConnectKeys.paired(newConnectSecret());
      stranger.publish(keys.toHost, ConnectChannel.encode(wrong.key, keys.toHost, {'t': 'play', 'n': 9999999999999}));
      stranger.publish(keys.toHost, Uint8List.fromList(List.filled(80, 3)));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(player.calls, isEmpty);

      // The same command again, as an eavesdropper would resend it, is applied once.
      final replay = ConnectChannel.encode(keys.key, keys.toHost, {'t': 'pause', 'n': 4000000000000000});
      stranger.publish(keys.toHost, replay);
      stranger.publish(keys.toHost, replay);
      await until(() => player.calls.contains('pause'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(player.calls.where((c) => c == 'pause'), hasLength(1));
    });

    test('revoking tells the controller, which forgets the pairing, and later commands do nothing', () async {
      await pairAndConnect();
      final secret = host.controllers.single.secret;
      await host.revoke(host.controllers.single.id);
      await until(() => controller.hosts.isEmpty);
      expect(controller.state, ConnectLinkState.disconnected);
      expect(host.controllers, isEmpty);
      expect((await SharedPreferences.getInstance()).getString('connect_controllers'), '[]');

      final keys = ConnectKeys.paired(secret);
      broker.connect().publish(
        keys.toHost,
        ConnectChannel.encode(keys.key, keys.toHost, {'t': 'play', 'n': 5000000000000000}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(player.calls, isEmpty);
    });

    test('losing the connection shows "not connected", retries, and the desktop keeps playing', () async {
      await pairAndConnect();
      await player.play();
      final seen = <ConnectLinkState>[];
      controller.addListener(() => seen.add(controller.state));
      broker.dropAll();
      await until(() => seen.contains(ConnectLinkState.disconnected));
      expect(controller.send(const ConnectPause()), isFalse, reason: 'refused while down, not pretended');
      expect(player.playing, isTrue, reason: 'playback does not depend on the controller');
      await until(() => controller.state == ConnectLinkState.connected, limit: const Duration(seconds: 5));
      expect(controller.remote!.playing, isTrue);
    });

    test('a desktop that goes quiet is shown as not connected', () async {
      controller.dispose();
      controller = ConnectController(
        openStore: () async => controllerStore,
        opener: broker.open,
        deviceName: 'Android 7QK2',
        backoff: (_) => const Duration(seconds: 30),
        hostSilence: const Duration(milliseconds: 200),
      );
      await controller.load();
      await pairAndConnect();
      await host.setEnabled(false);
      await until(() => controller.state == ConnectLinkState.disconnected);
      expect(player.calls, isEmpty);
    });

    test('pairing survives a restart: the lists come back from storage', () async {
      await pairAndConnect();
      expect(hostStore.controllers.single.name, 'Android 7QK2');
      expect(controllerStore.hosts.single.name, 'Windows');
      expect(hostStore.controllers.single.secret, controllerStore.hosts.single.secret);
    });

    test('a wrong or foreign code is refused before anything is sent', () async {
      await expectLater(
        controller.pair('K7Q2XM'),
        throwsA(isA<ConnectPairException>().having((e) => e.problem, 'problem', ConnectPairProblem.badCode)),
      );
      expect(broker.seen, isEmpty);
    });
  });
}
