import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/listen_together/internet.dart';
import 'package:riflay/services/listen_together/lan.dart';
import 'package:riflay/services/listen_together/listen_together.dart';
import 'package:riflay/services/listen_together/protocol.dart';
import 'package:riflay/services/listen_together/transport.dart';

/// The real-broker test talks to public servers, so it only runs when asked:
/// `RIFLAY_NETWORK_TESTS=1 flutter test test/listen_internet_test.dart`.
void main() {
  group('codes', () {
    test('a new code is 10 characters from the alphabet and starts with its broker', () {
      for (var broker = 0; broker < internetBrokers.length; broker++) {
        for (var i = 0; i < 50; i++) {
          final code = newInternetCode(broker);
          expect(code, hasLength(10));
          expect(code.split('').every(lanCodeAlphabet.contains), isTrue);
          expect(brokerForCode(code), same(internetBrokers[broker]));
        }
      }
    });

    test('the other nine characters are random', () {
      final codes = {for (var i = 0; i < 100; i++) newInternetCode(0)};
      expect(codes.length, 100);
    });

    test('formatted as ABCDE-FGHJK', () {
      expect(formatInternetCode('ABCDEFGHJK'), 'ABCDE-FGHJK');
      expect(formatInternetCode('K7Q2XM'), 'K7Q2XM');
    });

    test('normalizing forgives case, spaces and the hyphen', () {
      expect(normalizeCode('abcde-fghjk'), 'ABCDEFGHJK');
      expect(normalizeCode('  ABCDE FGHJK '), 'ABCDEFGHJK');
      expect(normalizeCode('abcdefghjk'), 'ABCDEFGHJK');
      expect(normalizeCode('k7q2xm'), 'K7Q2XM');
      expect(normalizeCode('K7Q-2XM'), 'K7Q2XM');
    });

    test('anything else is not a code', () {
      expect(normalizeCode(''), isNull);
      expect(normalizeCode('ABCDE'), isNull);
      expect(normalizeCode('ABCDEFG'), isNull);
      expect(normalizeCode('ABCDEFGHJKL'), isNull);
      expect(normalizeCode('ABCDE-FGHJ0'), isNull); // 0 is not in the alphabet
      expect(normalizeCode('K7Q2X1'), isNull);
      // A broker index nobody has: the last alphabet character.
      expect(normalizeCode('${lanCodeAlphabet[31]}BCDEFGHJK'), isNull);
    });

    test('the broker comes from the first character', () {
      expect(brokerForCode('${lanCodeAlphabet[0]}BCDEFGHJK'), same(internetBrokers[0]));
      expect(brokerForCode('${lanCodeAlphabet[1]}BCDEFGHJK'), same(internetBrokers[1]));
      expect(brokerForCode('K7Q2XM'), isNull);
    });

    test('the session picks its kind from the code', () {
      expect(ListenTogether.modeForCode('abcde-fghjk'), ListenMode.internet);
      expect(ListenTogether.modeForCode('k7q2xm'), ListenMode.wifi);
      expect(ListenTogether.modeForCode('nope'), isNull);
      expect(ListenTogether.internetAvailable, isTrue);
    });

    test('the join link names the code and the internet', () {
      final link = internetJoinLink('ABCDEFGHJK');
      expect('$link', 'riflay://listen?code=ABCDEFGHJK&via=internet');
    });
  });

  group('keys and topics', () {
    test('the same code gives the same room and key, another code another', () {
      final a = InternetRoomKeys.of('ABCDEFGHJK'), again = InternetRoomKeys.of('ABCDEFGHJK');
      final b = InternetRoomKeys.of('ABCDEFGHJL');
      expect(a.room, again.room);
      expect(a.key, again.key);
      expect(a.room, isNot(b.room));
      expect(a.key, isNot(b.key));
      expect(a.room, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(a.key, hasLength(32));
    });

    test('the topic does not reveal the key', () {
      final k = InternetRoomKeys.of('ABCDEFGHJK');
      expect(k.presenceTopic, 'riflay/l1/${k.room}/p');
      expect(k.toGuestTopic('abc123abc123'), 'riflay/l1/${k.room}/t/abc123abc123');
      expect(k.fromGuestTopic('abc123abc123'), 'riflay/l1/${k.room}/g/abc123abc123');
      expect(k.fromGuestsFilter, 'riflay/l1/${k.room}/g/+');
      expect(k.guestOf(k.fromGuestTopic('abc123abc123')), 'abc123abc123');
      expect(k.guestOf(k.toGuestTopic('abc123abc123')), isNull);
      expect(k.guestOf('${k.fromGuestsFilter}x'), isNull);
    });
  });

  group('encryption', () {
    final keys = InternetRoomKeys.of('ABCDEFGHJK');
    final topic = keys.presenceTopic;

    test('round trip', () {
      final bytes = InternetCrypto.encrypt(keys.key, topic, const Ping(42).encode(), id: 'abc123abc123');
      final back = InternetCrypto.decrypt(keys.key, topic, bytes)!;
      expect(back.message, const Ping(42).encode());
      expect(back.id, 'abc123abc123');
      expect(InternetCrypto.decrypt(keys.key, topic, InternetCrypto.encrypt(keys.key, topic, 'x'))!.id, isNull);
    });

    test('every payload is different and has no readable text', () {
      final a = InternetCrypto.encrypt(keys.key, topic, 'hello'), b = InternetCrypto.encrypt(keys.key, topic, 'hello');
      expect(a, isNot(b));
      expect(String.fromCharCodes(a), isNot(contains('hello')));
      expect(a.length, greaterThan(12 + 16));
    });

    test('tampered payloads are rejected', () {
      final bytes = InternetCrypto.encrypt(keys.key, topic, 'hello');
      for (final at in [0, 11, 12, bytes.length ~/ 2, bytes.length - 1]) {
        final bad = Uint8List.fromList(bytes)..[at] ^= 1;
        expect(InternetCrypto.decrypt(keys.key, topic, bad), isNull, reason: 'byte $at');
      }
      expect(InternetCrypto.decrypt(keys.key, topic, Uint8List.sublistView(bytes, 0, bytes.length - 1)), isNull);
      expect(InternetCrypto.decrypt(keys.key, topic, Uint8List(0)), isNull);
      expect(InternetCrypto.decrypt(keys.key, topic, Uint8List.fromList(List.filled(40, 7))), isNull);
    });

    test('the wrong key is rejected', () {
      final other = InternetRoomKeys.of('ABCDEFGHJL');
      final bytes = InternetCrypto.encrypt(keys.key, topic, 'hello');
      expect(InternetCrypto.decrypt(other.key, topic, bytes), isNull);
    });

    test('a payload moved to another topic is rejected', () {
      final bytes = InternetCrypto.encrypt(keys.key, topic, 'hello');
      expect(InternetCrypto.decrypt(keys.key, keys.toGuestTopic('abc123abc123'), bytes), isNull);
    });

    test('stale and future payloads are rejected', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      const minute = 60 * 1000;
      Uint8List made(int ts) => InternetCrypto.encrypt(keys.key, topic, 'hello', nowMs: ts);
      expect(InternetCrypto.decrypt(keys.key, topic, made(now - minute), nowMs: now), isNotNull);
      expect(InternetCrypto.decrypt(keys.key, topic, made(now + minute), nowMs: now), isNotNull);
      expect(InternetCrypto.decrypt(keys.key, topic, made(now - 2 * minute - 1000), nowMs: now), isNull);
      expect(InternetCrypto.decrypt(keys.key, topic, made(now + 2 * minute + 1000), nowMs: now), isNull);
    });

    test('a deterministic random source gives a deterministic nonce', () {
      final a = InternetCrypto.encrypt(keys.key, topic, 'x', nowMs: 1, random: Random(1));
      final b = InternetCrypto.encrypt(keys.key, topic, 'x', nowMs: 1, random: Random(1));
      expect(a, b);
    });
  });

  group('no host', () {
    test(
      'a guest for a code nobody hosts is told so, calmly',
      () async {
        // Never used by anyone: the first character picks the first broker.
        final code = newInternetCode(0);
        await expectLater(
          InternetGuestConnection.connect(code, timeout: const Duration(seconds: 6)),
          throwsA(
            isA<InternetException>().having(
              (e) => e.message,
              'message',
              anyOf(
                'Couldn\'t find that session. Check the code.',
                'Couldn\'t reach the listening servers. Check your internet connection and try again.',
              ),
            ),
          ),
        );
      },
      skip: Platform.environment['RIFLAY_NETWORK_TESTS'] != '1' ? 'needs the internet: RIFLAY_NETWORK_TESTS=1' : false,
    );
  });

  group('through a public broker', () {
    test('host and guest talk, the room closes behind the host', () async {
      final host = InternetHostTransport();
      await host.start();
      addTearDown(host.stop);
      final code = host.code;
      expect(code, matches(RegExp(r'^[A-Z2-9]{5}-[A-Z2-9]{5}$')));
      expect('${host.joinLink}', contains('via=internet'));

      final peers = <ListenPeer>[];
      host.peers.listen(peers.add);
      final guest = await InternetGuestConnection.connect(normalizeCode(code)!);
      final fromGuest = <String>[], fromHost = <String>[];
      var guestEnded = false;
      guest.incoming.listen(fromHost.add, onDone: () => guestEnded = true);

      guest.send(const Ping(1).encode());
      await _until(() => peers.isNotEmpty);
      peers.first.incoming.listen(fromGuest.add);
      await _until(() => fromGuest.isNotEmpty);
      expect(ListenMessage.decode(fromGuest.first), isA<Ping>());

      peers.first.send(const Pong(pingAtMs: 1, hostAtMs: 2).encode());
      await _until(() => fromHost.isNotEmpty);
      expect(ListenMessage.decode(fromHost.first), isA<Pong>());

      // A second guest is another peer.
      final second = await InternetGuestConnection.connect(normalizeCode(code)!);
      second.send(const Ping(2).encode());
      await _until(() => peers.length == 2);
      expect(peers[0].id, isNot(peers[1].id));
      await second.close();

      // The host stops: the retained presence is cleared and the guest hears it.
      await host.stop();
      await _until(() => guestEnded);
      await expectLater(
        InternetGuestConnection.connect(normalizeCode(code)!, timeout: const Duration(seconds: 4)),
        throwsA(isA<InternetRoomNotFound>()),
      );
      await guest.close();
    }, timeout: const Timeout(Duration(seconds: 60)));
  }, skip: Platform.environment['RIFLAY_NETWORK_TESTS'] != '1' ? 'needs the internet: RIFLAY_NETWORK_TESTS=1' : false);
}

Future<void> _until(bool Function() done, {Duration timeout = const Duration(seconds: 15)}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('condition not met');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
