import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/connect/connect_protocol.dart' show connectRef;
import 'package:riflay/services/connect/connect_share.dart';
import 'package:riflay/services/connect/connect_stream.dart';

void main() {
  final own = Track.fromUri(Uri.file('/home/ana/Music/Mine.flac'));
  final other = Track.fromUri(Uri.file('/home/ana/Music/Other.flac'));
  final youtube = Track.youtube(videoId: 'abcdefghijk', title: 'Remote', artist: 'X');
  final downloaded = Track(
    id: 'dl1',
    uri: Uri.file('/home/ana/Music/Bought.flac'),
    title: 'Bought',
    artist: 'X',
    sourceUrl: 'https://service.example/track/1',
  );
  final library = [own, other, youtube, downloaded];

  group('ownership filter', () {
    test('nothing is streamable until it is marked', () {
      final o = ConnectOwnership({});
      for (final t in library) {
        expect(o.canStream(t), isFalse);
        expect(o.streamable(connectRef(t.id), library), isNull);
      }
    });

    test('only the marked file is streamed; unmarked neighbours stay private', () async {
      final o = ConnectOwnership({});
      await o.mark([own], true);
      expect(o.streamable(connectRef(own.id), library), same(own));
      expect(o.streamable(connectRef(other.id), library), isNull);
      expect(o.streamable('unknown-ref', library), isNull);
    });

    test('a streamed or downloaded song is never streamable, even if marked', () async {
      final saved = <Set<String>>[];
      final o = ConnectOwnership({}, onSave: (ids) async => saved.add(ids));
      await o.mark(library, true);
      expect(saved.single, {own.id, other.id}, reason: 'only own files are ever recorded');
      expect(o.canStream(youtube), isFalse);
      expect(o.canStream(downloaded), isFalse);
      // Even a stale id in the preferences can't make one eligible.
      final stale = ConnectOwnership({youtube.id, downloaded.id});
      expect(stale.canStream(youtube), isFalse);
      expect(stale.canStream(downloaded), isFalse);
    });

    test('unmarking takes a file back', () async {
      final o = ConnectOwnership({});
      await o.mark([own, other], true);
      await o.mark([own], false);
      expect(o.canStream(own), isFalse);
      expect(o.canStream(other), isTrue);
      expect(o.markedIn(library), 1);
    });
  });

  group('route choice', () {
    Future<String?> ok(String s) async => s;
    Future<String?> no() async => null;
    Future<String?> boom() async => throw StateError('refused');

    test('LAN wins when it works, and nothing else is tried', () async {
      final tried = <ConnectRoute>[];
      final r = await connectViaBestRoute<String>({
        ConnectRoute.lan: () async {
          tried.add(ConnectRoute.lan);
          return 'lan';
        },
        ConnectRoute.stun: () async {
          tried.add(ConnectRoute.stun);
          return 'stun';
        },
      });
      expect(r.route, ConnectRoute.lan);
      expect(tried, [ConnectRoute.lan]);
    });

    test('falls back to STUN when LAN fails, whether it returns nothing or throws', () async {
      for (final lan in [no, boom]) {
        final r = await connectViaBestRoute<String>({ConnectRoute.lan: lan, ConnectRoute.stun: () => ok('stun')});
        expect(r.route, ConnectRoute.stun);
        expect(r.connection, 'stun');
      }
    });

    test('TURN is only used when the person set one up, and only after STUN', () async {
      final without = await connectViaBestRoute<String>({ConnectRoute.lan: no, ConnectRoute.stun: no});
      expect(without.ok, isFalse);
      final withTurn = await connectViaBestRoute<String>({
        ConnectRoute.lan: no,
        ConnectRoute.stun: no,
        ConnectRoute.turn: () => ok('turn'),
      });
      expect(withTurn.route, ConnectRoute.turn);
    });

    test('when nothing works it fails loudly, with a reason', () async {
      final r = await connectViaBestRoute<String>({ConnectRoute.lan: boom, ConnectRoute.stun: no});
      expect(r.ok, isFalse);
      expect(r.failure, ConnectRouteFailure.noRoute);
      expect((await connectViaBestRoute<String>({})).failure, ConnectRouteFailure.noRoute);
    });
  });

  test('ICE servers: public STUN by default, TURN only when configured', () {
    expect(const ConnectIceConfig().iceServers, [
      {'urls': ConnectIceConfig.defaultStun},
    ]);
    const cfg = ConnectIceConfig(turnUrl: 'turn:relay.example:3478', turnUser: 'u', turnPassword: 'p');
    expect(cfg.iceServers, hasLength(2));
    expect(cfg.iceServers.last['urls'], 'turn:relay.example:3478');
  });

  test('the player source asks the owner for the range it needs', () async {
    final asked = <(String, int, int?)>[];
    final source = ConnectStreamSource(
      'ref1',
      fetch: (ref, start, end) async {
        asked.add((ref, start, end));
        return ConnectRange(sourceLength: 1000, stream: Stream.value(List.filled(100, 1)), contentType: 'audio/flac');
      },
    );
    final r = await source.request(100, 200);
    expect(asked.single, ('ref1', 100, 200));
    expect((r.offset, r.contentLength, r.sourceLength), (100, 100, 1000));
    final whole = await source.request();
    expect((whole.offset, whole.contentLength), (0, 1000));
  });

  test('a shared index names, by hash, only the songs marked as the owner own', () async {
    final o = ConnectOwnership({});
    await o.mark([own], true);
    final c = shareOf(ShareKind.album, 'k', 'Album', [own, other, youtube, downloaded], ownership: o);
    expect([for (final t in c.tracks) t.ref], [connectRef(own.id), null, null, null]);
    final wire = c.toJson().toString();
    expect(wire, isNot(contains('/home/ana')), reason: 'no path in what is shared');
    final none = shareOf(ShareKind.album, 'k', 'Album', [own, other]);
    expect(none.tracks.every((t) => t.ref == null), isTrue, reason: 'default: nothing is streamable');
  });
}
