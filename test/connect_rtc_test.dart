import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/connect/connect_protocol.dart' show connectRef;
import 'package:riflay/services/connect/connect_rtc.dart';
import 'package:riflay/services/connect/connect_share.dart' show ShareTrack;
import 'package:riflay/services/connect/connect_stream.dart';

/// Two ends of an in-memory data channel.
class _End implements RtcLink {
  final _in = StreamController<RtcData>.broadcast();
  final _closed = Completer<void>();
  late _End peer;
  var _open = true;

  @override
  Stream<RtcData> get messages => _in.stream;
  @override
  Future<void> get closed => _closed.future;
  @override
  bool get isOpen => _open;
  @override
  void sendText(String text) => Future.microtask(() => peer._in.add(RtcData.text(text)));
  @override
  Future<void> sendBinary(Uint8List bytes) async => Future.microtask(() => peer._in.add(RtcData.binary(bytes)));
  @override
  Future<void> close() async {
    for (final e in [this, peer]) {
      e._open = false;
      if (!e._closed.isCompleted) e._closed.complete();
    }
  }
}

(_End, _End) _pair() {
  final a = _End(), b = _End();
  a.peer = b;
  b.peer = a;
  return (a, b);
}

Future<Uint8List> _read(Stream<List<int>> s) async => Uint8List.fromList([for (final c in await s.toList()) ...c]);

void main() {
  late Directory dir;
  late Track mine, notMine;
  late List<int> bytes;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('riflay_rtc');
    bytes = List.generate(40000, (i) => i % 251);
    File('${dir.path}/mine.flac').writeAsBytesSync(bytes);
    File('${dir.path}/other.flac').writeAsBytesSync([9, 9, 9]);
    mine = Track.fromUri(Uri.file('${dir.path}/mine.flac'));
    notMine = Track.fromUri(Uri.file('${dir.path}/other.flac'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<RtcRangeClient> serve(ConnectOwnership own) async {
    final (c, o) = _pair();
    RtcRangeServer(o, ownership: own, library: () => [mine, notMine]);
    return RtcRangeClient(c);
  }

  test('the owner streams a marked file, and exactly the range asked for', () async {
    final own = ConnectOwnership({});
    await own.mark([mine], true);
    final client = await serve(own);
    final all = await client.fetch(connectRef(mine.id), 0, null);
    expect((all.sourceLength, all.contentType), (40000, 'audio/flac'));
    expect(await _read(all.stream), bytes);
    final part = await client.fetch(connectRef(mine.id), 100, 20100);
    expect(await _read(part.stream), bytes.sublist(100, 20100));
  });

  test('a file that is not marked is refused, however it is asked for', () async {
    final own = ConnectOwnership({});
    await own.mark([mine], true);
    final client = await serve(own);
    await expectLater(client.fetch(connectRef(notMine.id), 0, null), throwsA(isA<RtcRangeRefused>()));
    await expectLater(client.fetch('0123456789abcdef', 0, null), throwsA(isA<RtcRangeRefused>()));
    // A path is not a name for a song.
    await expectLater(client.fetch(notMine.path!, 0, null), throwsA(isA<RtcRangeRefused>()));
    // Nothing marked at all: nothing is served.
    final none = await serve(ConnectOwnership({}));
    await expectLater(none.fetch(connectRef(mine.id), 0, null), throwsA(isA<RtcRangeRefused>()));
  });

  group('signaling between two devices', () {
    final pending = <String, (_End, _End)>{};

    // A made-up WebRTC: the offer names a pair of in-memory ends, the answer says "got it".
    Future<RtcLink> opener({
      required bool offerer,
      required ConnectIceConfig ice,
      required void Function(Map<String, dynamic>) send,
      required Stream<Map<String, dynamic>> incoming,
      required Duration timeout,
    }) async {
      if (offerer) {
        final tok = '${pending.length}', ends = _pair();
        pending[tok] = ends;
        send({'k': 'offer', 'tok': tok});
        await incoming.firstWhere((d) => d['k'] == 'answer').timeout(timeout);
        return ends.$1;
      }
      final offer = await incoming.firstWhere((d) => d['k'] == 'offer');
      send({'k': 'answer'});
      return pending[offer['tok']]!.$2;
    }

    late ConnectRtc controller, owner;

    setUp(() async {
      pending.clear();
      final own = ConnectOwnership({});
      await own.mark([mine], true);
      controller = ConnectRtc(opener: opener, ownership: ConnectOwnership({}), library: () => []);
      owner = ConnectRtc(opener: opener, ownership: own, library: () => [mine, notMine]);
      controller.attach('owner', (m) => owner.handle('controller', m));
      owner.attach('controller', (m) => controller.handle('owner', m));
    });

    test('a shared song plays from its owner over the direct connection', () async {
      final source = controller.sourceFor('owner', connectRef(mine.id));
      final r = await source.request(0, 1000);
      expect((r.sourceLength, r.contentLength, r.offset), (40000, 1000, 0));
      expect(await _read(r.stream), bytes.sublist(0, 1000));
    });

    test('with no way to reach the owner it fails with a reason, not silence', () async {
      final lonely = ConnectRtc(opener: opener, ownership: ConnectOwnership({}), library: () => []);
      await expectLater(lonely.client('owner'), throwsA(isA<ConnectRouteException>()));
      final broken = ConnectRtc(
        opener: ({required offerer, required ice, required send, required incoming, required timeout}) async =>
            throw StateError('no route'),
        ownership: ConnectOwnership({}),
        library: () => [],
      )..attach('owner', (_) {});
      await expectLater(
        broken.client('owner'),
        throwsA(isA<ConnectRouteException>().having((e) => e.failure, 'failure', ConnectRouteFailure.noRoute)),
      );
    });

    test('a signal from a device that is not paired right now starts nothing', () async {
      var opened = 0;
      final hub = ConnectRtc(
        opener: ({required offerer, required ice, required send, required incoming, required timeout}) async {
          opened++;
          throw StateError('x');
        },
        ownership: ConnectOwnership({}),
        library: () => [],
      );
      hub.handle('stranger', {
        't': 'rtc.sig',
        'sid': 's1',
        'd': {'k': 'offer'},
      });
      await Future<void>.delayed(Duration.zero);
      expect(opened, 0);
    });
  });

  test('a shared song is a queue entry that names the owner and the song, not a file', () {
    final t = connectTrackOf('peer1', const ShareTrack('Song', 'Ana', ref: '0123456789abcdef'));
    expect(connectTrackParts(t), (peerId: 'peer1', ref: '0123456789abcdef'));
    expect(t.path, isNull);
    expect(connectIsOwnFile(t), isFalse, reason: 'a received song can never be streamed onwards');
    expect(connectTrackParts(mine), isNull);
  });
}
