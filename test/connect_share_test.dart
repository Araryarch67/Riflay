import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/connect/connect_channel.dart';
import 'package:riflay/services/connect/connect_controller.dart';
import 'package:riflay/services/connect/connect_host.dart';
import 'package:riflay/services/connect/connect_share.dart';
import 'package:riflay/services/connect/connect_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connect_support.dart';

Track song(int i, {String title = 'Song', String folder = '/home/ana/Music/Secret Folder'}) => Track(
  id: '$folder/$i.flac',
  uri: Uri.file('$folder/$i.flac'),
  title: '$title $i',
  artist: 'Artist ${i % 3}',
  album: 'Album',
);

ShareCollection album(String name, List<Track> tracks) =>
    shareOf(ShareKind.album, name, name, tracks, artist: 'Someone', year: 1999);

/// Runs an owner's replies through a viewer, the way the pair room would, answering the viewer's requests too.
void sync(ShareOwner owner, ShareViewer viewer, {List<Map<String, dynamic>>? first}) {
  final queue = [...first ?? owner.indexMessages()];
  while (queue.isNotEmpty) {
    for (final request in viewer.handle(queue.removeAt(0))) {
      queue.addAll(owner.answer(request));
    }
  }
}

void main() {
  group('versions and conflicts', () {
    test('the same content keeps its number, changed content goes up, a first sight starts at 1', () {
      var stamps = nextStamps({}, {'a': 'x'});
      expect(stamps['a']!.version, 1);
      stamps = nextStamps(stamps, {'a': 'x', 'b': 'y'});
      expect((stamps['a']!.version, stamps['b']!.version), (1, 1));
      stamps = nextStamps(stamps, {'a': 'z'});
      expect(stamps['a']!.version, 2);
    });

    test('a collection shared again after a change never reuses a number a viewer may hold', () {
      var stamps = nextStamps({}, {'a': 'x'});
      stamps = nextStamps(stamps, {}); // stopped sharing: remembered, not forgotten
      stamps = nextStamps(stamps, {'a': 'changed'});
      expect(stamps['a']!.version, 2);
    });

    test('the owner numbers a change, and says nothing when nothing changed', () {
      final tracks = [song(1), song(2)];
      var source = [album('A', tracks)];
      final a = album('A', tracks);
      final owner = ShareOwner(source: () => source, selected: {a.id}, clock: () => 1000);
      expect(owner.refresh(), isTrue);
      expect(owner.shared().single.entry.version, 1);
      expect(owner.refresh(), isFalse);
      source = [
        album('A', [...tracks, song(3)]),
      ];
      expect(owner.refresh(), isTrue);
      expect(owner.shared().single.entry.version, 2);
      expect(owner.shared().single.entry.count, 3);
    });

    test('the viewer follows the owner: a new version is fetched again, an old index is ignored', () {
      var source = [
        album('A', [song(1)]),
      ];
      final id = source.single.id;
      var now = 1000;
      final owner = ShareOwner(source: () => source, selected: {id}, clock: () => now);
      final viewer = ShareViewer();
      sync(owner, viewer);
      expect(viewer.request(id), hasLength(1));
      sync(owner, viewer, first: owner.collectionMessages(id));
      expect(viewer.loaded(id)!.tracks, hasLength(1));
      expect(viewer.loaded(id)!.entry.version, 1);

      final oldIndex = owner.indexMessages();
      now = 2000;
      source = [
        album('A', [song(1), song(2)]),
      ];
      sync(owner, viewer);
      expect(viewer.loaded(id)!.tracks, hasLength(2), reason: 'a collection already held is refreshed on its own');
      expect(viewer.loaded(id)!.entry.version, 2);

      // The index of version 1 arrives late: it must not roll the viewer back.
      for (final m in oldIndex) {
        expect(viewer.handle(m), isEmpty);
      }
      expect(viewer.entries.single.version, 2);
    });

    test('whatever version the owner names wins, even a lower one', () {
      final c = album('A', [song(1)]);
      final viewer = ShareViewer();
      Map<String, dynamic> index(int rev, int v) => {
        't': 'shr.idx',
        'rev': rev,
        'seq': 0,
        'of': 1,
        'items': [c.entry.withVersion(v).toJson()],
      };
      Map<String, dynamic> col(int v, String title) => {
        't': 'shr.col',
        'id': c.id,
        'v': v,
        'seq': 0,
        'of': 1,
        'tracks': [ShareTrack(title, 'x').toJson()],
      };
      viewer.handle(index(1, 5));
      viewer.request(c.id);
      viewer.handle(col(5, 'five'));
      // The owner starts over (reinstalled): version 1, newer index.
      expect(viewer.handle(index(2, 1)), [
        {'t': 'shr.get', 'id': c.id},
      ]);
      viewer.handle(col(1, 'one'));
      expect(viewer.loaded(c.id)!.tracks.single.title, 'one');
    });

    test('songs of a version the index no longer names are dropped', () {
      final c = album('A', [song(1)]);
      final viewer = ShareViewer()
        ..handle({
          't': 'shr.idx',
          'rev': 1,
          'seq': 0,
          'of': 1,
          'items': [c.entry.withVersion(2).toJson()],
        });
      viewer.request(c.id);
      viewer.handle({
        't': 'shr.col',
        'id': c.id,
        'v': 1,
        'seq': 0,
        'of': 1,
        'tracks': [const ShareTrack('old', 'x').toJson()],
      });
      expect(viewer.loaded(c.id), isNull);
    });

    test('sharing can be taken back at any time: the viewer loses the collection', () {
      final a = album('A', [song(1)]), b = album('B', [song(2)]);
      final owner = ShareOwner(source: () => [a, b], selected: {a.id, b.id}, clock: () => 1);
      final viewer = ShareViewer();
      sync(owner, viewer);
      expect(viewer.entries, hasLength(2));
      sync(owner, viewer, first: owner.collectionMessages(a.id));
      viewer.request(a.id);
      owner.selected.remove(a.id);
      sync(owner, viewer);
      expect(viewer.entries.map((e) => e.id), [b.id]);
      expect(viewer.loaded(a.id), isNull);
      owner.selected.clear();
      sync(owner, viewer);
      expect(viewer.entries, isEmpty);
    });

    test('the owner serves only what is picked, and answers nothing but reads', () {
      final a = album('A', [song(1)]), b = album('B', [song(2)]);
      final owner = ShareOwner(source: () => [a, b], selected: {a.id}, clock: () => 1);
      expect(owner.answer({'t': 'shr.get', 'id': b.id}), isEmpty, reason: 'not picked');
      expect(owner.answer({'t': 'shr.get', 'id': a.id}), isNotEmpty);
      for (final t in ['shr.idx', 'shr.col', 'shr.set', 'play', 'shr.select']) {
        expect(owner.answer({'t': t, 'id': a.id, 'items': []}), isEmpty);
      }
      expect(owner.selected, {a.id});
    });
  });

  group('what is sent', () {
    test('no path, folder, file name or local id is in anything the owner sends', () {
      final tracks = [for (var i = 0; i < 5; i++) song(i)];
      final playlist = shareOf(ShareKind.playlist, 'pl-secret-id', 'Mix', tracks);
      final albumC = album('Album', tracks);
      final artist = shareOf(ShareKind.artist, 'artist', 'Artist 0', tracks);
      final owner = ShareOwner(
        source: () => [playlist, albumC, artist],
        selected: {playlist.id, albumC.id, artist.id},
        clock: () => 1,
      );
      final all = [...owner.indexMessages(), for (final c in owner.shared()) ...owner.collectionMessages(c.id)];
      final json = jsonEncode(all);
      for (final secret in ['Secret Folder', '/home', 'ana', '.flac', 'file:', 'pl-secret-id', tracks.first.id]) {
        expect(json, isNot(contains(secret)), reason: secret);
      }
      expect(json, contains('Song 1'));
      // Only these keys exist anywhere in what is sent.
      final keys = <String>{};
      void collect(Object? o) {
        if (o is Map) {
          for (final e in o.entries) {
            keys.add(e.key as String);
            collect(e.value);
          }
        } else if (o is List) {
          o.forEach(collect);
        }
      }

      collect(all);
      expect(keys, {'t', 'rev', 'seq', 'of', 'items', 'id', 'k', 'n', 'a', 'y', 'c', 'v', 'tracks'});
    });

    test('what arrives is cleaned: control characters go, sizes are held', () {
      final viewer = ShareViewer();
      viewer.handle({
        't': 'shr.idx',
        'rev': 1,
        'seq': 0,
        'of': 1,
        'items': [
          {'id': 'x', 'k': 'album', 'n': 'Na\u0000me202E${'z' * 500}', 'c': 99999999, 'v': 1},
          {'id': 'y', 'k': 'bogus', 'n': 'Bad', 'c': 1, 'v': 1},
          {'id': 'z', 'k': 'album', 'n': 'Bad', 'c': -1, 'v': 1},
          'junk',
        ],
      });
      expect(viewer.entries, hasLength(1));
      expect(viewer.entries.single.name, startsWith('Name'));
      expect(viewer.entries.single.name.length, lessThanOrEqualTo(200));
      expect(viewer.entries.single.count, shareMaxTracks);
    });
  });

  group('big collections', () {
    test('chunks stay under the size limit and keep every item in order', () {
      final items = [
        for (var i = 0; i < 1000; i++) {'t': 'Title number $i', 'a': 'Artist'},
      ];
      final chunks = shareChunks(items, maxBytes: 2000);
      expect(chunks.length, greaterThan(10));
      for (final c in chunks) {
        expect(utf8.encode(jsonEncode(c)).length, lessThanOrEqualTo(2000));
      }
      expect([for (final c in chunks) ...c], items);
      expect(shareChunks([]), [<Map<String, dynamic>>[]], reason: 'empty still says "nothing"');
    });

    test('a 5000-song collection travels as encrypted messages that are all under the message limit', () {
      final tracks = [for (var i = 0; i < 5000; i++) song(i, title: 'A fairly long song title to be realistic')];
      final c = album('Big', tracks);
      final owner = ShareOwner(source: () => [c], selected: {c.id}, clock: () => 1);
      final key = ConnectKeys.paired(newConnectSecret());
      final messages = owner.collectionMessages(c.id);
      expect(messages.length, greaterThan(5));
      for (final m in messages) {
        final data = ConnectChannel.encode(key.key, key.toController, m);
        expect(data.length, lessThanOrEqualTo(shareMessageLimit));
      }
      final viewer = ShareViewer();
      sync(owner, viewer);
      // Chunks may arrive in any order, and one twice.
      final shuffled = [...messages.reversed, messages.first];
      viewer.request(c.id);
      for (final m in shuffled) {
        viewer.handle(m);
      }
      final got = viewer.loaded(c.id)!;
      expect(got.tracks, hasLength(5000));
      expect(got.tracks.first.title, startsWith('A fairly long'));
      expect(got.tracks.last.title, tracks.last.title);
    });

    test('a thousand collections go out in pieces as well', () {
      final all = [
        for (var i = 0; i < 1500; i++) album('Album number $i', [song(i)]),
      ];
      final owner = ShareOwner(source: () => all, selected: {for (final c in all) c.id}, clock: () => 1);
      final messages = owner.indexMessages();
      expect(messages.length, greaterThan(1));
      final viewer = ShareViewer();
      sync(owner, viewer);
      expect(viewer.entries, hasLength(1500));
    });

    test('an announced size that is out of bounds is refused', () {
      final viewer = ShareViewer();
      expect(viewer.handle({'t': 'shr.idx', 'rev': 1, 'seq': 0, 'of': shareMaxChunks + 1, 'items': []}), isEmpty);
      expect(viewer.listed, isFalse);
      viewer.handle({'t': 'shr.idx', 'rev': 1, 'seq': 3, 'of': 2, 'items': []});
      expect(viewer.listed, isFalse);
    });
  });

  group('between two devices', () {
    late ShareCollection a;
    late ConnectShare owner, viewer;
    late List<String> wire;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      a = album('A', [song(1), song(2)]);
      wire = [];
      owner = ConnectShare(
        source: () => [
          a,
          album('B', [song(3)]),
        ],
        openStore: () async => ConnectStore(prefs),
        refreshEvery: const Duration(milliseconds: 10),
      );
      viewer = ConnectShare(source: () => const [], openStore: () async => ConnectStore(prefs));
      // The two ends wired to each other, as a pair room would.
      owner.attach('v', 'Viewer', (m) {
        wire.add(m['t'] as String);
        viewer.handle('o', m);
      });
      viewer.attach('o', 'Owner', (m) {
        wire.add(m['t'] as String);
        owner.handle('v', m);
      });
      await owner.load();
    });

    tearDown(() {
      owner.dispose();
      viewer.dispose();
    });

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 40));

    test('nothing is shared until it is picked', () async {
      owner.heard('v');
      viewer.heard('o');
      await settle();
      expect(viewer.viewerOf('o')!.entries, isEmpty);
      expect(owner.selected, isEmpty);
    });

    test('picking shares it, opening it brings the songs, taking it back removes it', () async {
      viewer.heard('o');
      await settle();
      await owner.setShared(a.id, true);
      await settle();
      final v = viewer.viewerOf('o')!;
      expect(v.entries.map((e) => e.name), ['A']);
      viewer.open('o', a.id);
      await settle();
      expect(v.loaded(a.id)!.tracks.map((t) => t.title), ['Song 1', 'Song 2']);

      await owner.setShared(a.id, false);
      await settle();
      expect(v.entries, isEmpty);
      expect(v.loaded(a.id), isNull);
    });

    test('a viewer sending an index or songs changes nothing on the owner', () async {
      await owner.setShared(a.id, true);
      owner.heard('v');
      viewer.heard('o');
      await settle();
      await owner.handle('v', {
        't': 'shr.idx',
        'rev': 99,
        'seq': 0,
        'of': 1,
        'items': [a.entry.toJson()],
      });
      await owner.handle('v', {'t': 'shr.get', 'id': 'not-shared'});
      expect(owner.selected, {a.id});
      expect(wire.where((t) => t == 'shr.col'), isEmpty);
    });

    test('a change on the owner arrives with a new version, without the viewer asking', () async {
      var extra = 0;
      final changing = ConnectShare(
        source: () => [
          album('A', [song(1), for (var i = 0; i < extra; i++) song(10 + i)]),
        ],
        openStore: () async => ConnectStore(await SharedPreferences.getInstance()),
        refreshEvery: const Duration(milliseconds: 10),
      );
      final seeing = ConnectShare(
        source: () => const [],
        openStore: () async => ConnectStore(await SharedPreferences.getInstance()),
      );
      final id = album('A', [song(1)]).id;
      changing.attach('v', 'V', (m) => seeing.handle('o', m));
      seeing.attach('o', 'O', (m) => changing.handle('v', m));
      await changing.setShared(id, true);
      seeing.heard('o');
      await settle();
      seeing.open('o', id);
      await settle();
      final v = seeing.viewerOf('o')!;
      expect(v.loaded(id)!.tracks, hasLength(1));
      extra = 2;
      await changing.setShared(id, true); // already picked: nothing, the change is found on its own
      changing.detach('v');
      changing.attach('v', 'V', (m) => seeing.handle('o', m));
      seeing.requestList('o');
      await settle();
      expect(v.loaded(id)!.tracks, hasLength(3));
      expect(v.loaded(id)!.entry.version, 2);
      changing.dispose();
      seeing.dispose();
    });

    test('only a local copy can be changed; it stays when the owner stops sharing', () async {
      viewer.heard('o');
      await owner.setShared(a.id, true);
      await settle();
      viewer.open('o', a.id);
      await settle();
      await viewer.saveCopy(viewer.viewerOf('o')!.loaded(a.id)!);
      final copy = viewer.copies.single;
      expect(copy.id, isNot(a.id));
      await viewer.renameCopy(copy.id, 'My A');
      expect(viewer.copies.single.entry.name, 'My A');
      await owner.setShared(a.id, false);
      await settle();
      expect(viewer.viewerOf('o')!.entries, isEmpty);
      expect(viewer.copies.single.tracks, hasLength(2));
      await viewer.removeCopy(copy.id);
      expect(viewer.copies, isEmpty);
    });

    test('what is picked and the copies are still there after a restart', () async {
      await owner.setShared(a.id, true);
      await viewer.saveCopy(a);
      final prefs = await SharedPreferences.getInstance();
      final again = ConnectShare(source: () => [a], openStore: () async => ConnectStore(prefs));
      await again.load();
      expect(again.selected, {a.id});
      expect(again.copies.single.tracks, hasLength(2));
      again.dispose();
    });
  });

  group('over the encrypted pair room', () {
    test('a paired desktop shares a playlist; the controller sees titles only, through the broker', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final broker = FakeBroker();
      final player = FakeConnectPlayer();
      final playlist = shareOf(ShareKind.playlist, 'p1', 'Road trip', [song(1), song(2)]);
      final hostShare = ConnectShare(source: () => [playlist], openStore: () async => ConnectStore(prefs));
      final controllerShare = ConnectShare(source: () => const [], openStore: () async => ConnectStore(prefs));
      final host = ConnectHost(
        player,
        share: hostShare,
        openStore: () async => ConnectStore(prefs),
        opener: broker.open,
        deviceName: 'Windows',
        stateDelay: const Duration(milliseconds: 10),
        backoff: (_) => const Duration(milliseconds: 20),
      );
      final controller = ConnectController(
        openStore: () async => ConnectStore(prefs),
        opener: broker.open,
        deviceName: 'Android 7QK2',
        backoff: (_) => const Duration(milliseconds: 20),
        hostSilence: const Duration(seconds: 5),
      )..share = controllerShare;
      addTearDown(() {
        controller.dispose();
        host.dispose();
        hostShare.dispose();
        controllerShare.dispose();
      });
      await host.load();
      await controller.load();
      await hostShare.load();
      await host.beginPairing();
      await until(() => broker.links.isNotEmpty && host.pairingCode != null);
      final pairing = controller.pair(host.pairingCode!);
      await until(() => host.pending != null);
      await host.approve();
      await pairing;
      await until(() => controller.state == ConnectLinkState.connected);

      await until(() => controllerShare.viewerOf(controller.active!.id)?.listed ?? false);
      expect(controllerShare.viewerOf(controller.active!.id)!.entries, isEmpty, reason: 'nothing picked yet');

      await hostShare.setShared(playlist.id, true);
      final id = controller.active!.id;
      await until(() => controllerShare.viewerOf(id)!.entries.length == 1);
      controllerShare.open(id, playlist.id);
      await until(() => controllerShare.viewerOf(id)!.loaded(playlist.id) != null);
      expect(controllerShare.viewerOf(id)!.loaded(playlist.id)!.tracks.map((t) => t.title), ['Song 1', 'Song 2']);

      // The broker only ever carried ciphertext, and what was decrypted holds no path.
      final seen = broker.seen.map((e) => latin1.decode(e.$2, allowInvalid: true)).join();
      expect(seen, isNot(contains('Road trip')));
      expect(seen, isNot(contains('Secret Folder')));

      // Pairing removed on the desktop: the controller can't keep looking.
      await host.revoke(host.controllers.single.id);
      await until(() => controller.hosts.isEmpty);
      expect(controllerShare.viewerOf(id), isNull);
    });
  });
}
