import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/media_session/browse_tree.dart';

class _Lib implements BrowseLibrary {
  _Lib({this.playlists = const [], this.recent = const [], this.likedTracks = const []});

  @override
  final List<Collection> playlists;
  @override
  final List<Track> recent;
  final List<Track> likedTracks;

  @override
  Future<List<Track>> liked() async => likedTracks;
}

Track _t(String id, {String? artist}) =>
    Track(id: id, uri: Uri.file('/m/song.flac'), title: 'T$id', artist: artist ?? 'A');

Collection _p(String id, List<Track> tracks) =>
    Collection(kind: CollectionKind.playlist, id: id, title: 'P$id', subtitle: '', tracks: tracks);

void main() {
  test('root lists the three folders, none playable', () async {
    final items = await BrowseTree(_Lib()).children(AudioService.browsableRootId);
    expect(items.map((i) => i.id), ['playlists', 'liked', 'recent']);
    expect(items.every((i) => i.playable == false), isTrue);
  });

  test('playlists are folders; a playlist lists its songs as playable items', () async {
    final tree = BrowseTree(
      _Lib(
        playlists: [
          _p('1', [_t('a'), _t('b')]),
        ],
      ),
    );
    final lists = await tree.children('playlists');
    expect(lists.single.id, 'playlist:1');
    expect(lists.single.playable, isFalse);
    final songs = await tree.children('playlist:1');
    expect(songs.map((i) => i.title), ['Ta', 'Tb']);
    expect(songs.every((i) => i.playable == true), isTrue);
  });

  test('liked and recent list their songs; signed out liked is empty; unknown ids are empty', () async {
    final tree = BrowseTree(_Lib(likedTracks: [_t('l')], recent: [_t('r1'), _t('r2')]));
    expect((await tree.children('liked')).length, 1);
    expect((await tree.children(BrowseTree.recentId)).length, 2);
    expect(await BrowseTree(_Lib()).children('liked'), isEmpty);
    expect(await tree.children('playlist:nope'), isEmpty);
    expect(await tree.children('garbage'), isEmpty);
  });

  test('a long list is cut to maxItems', () async {
    final tree = BrowseTree(_Lib(recent: [for (var i = 0; i < 250; i++) _t('$i')]));
    expect((await tree.children(BrowseTree.recentId)).length, BrowseTree.maxItems);
  });

  test('a picked song resolves to its list, place and title; ids with odd characters survive', () async {
    final tree = BrowseTree(
      _Lib(
        playlists: [
          _p('x:1', [_t('a'), _t('b:c#d')]),
        ],
        likedTracks: [_t('l')],
      ),
    );
    final songs = await tree.children('playlist:x:1');
    final pick = (await tree.resolve(songs[1].id))!;
    expect(pick.index, 1);
    expect(pick.tracks.length, 2);
    expect(pick.from, 'Px:1');
    expect((await tree.resolve((await tree.children('liked')).single.id))!.index, 0);
  });

  test('a song that is gone, or a malformed id, resolves to nothing', () async {
    final tree = BrowseTree(
      _Lib(
        playlists: [
          _p('1', [_t('a')]),
        ],
      ),
    );
    expect(await tree.resolve('playlist:1\u001fzzz'), isNull);
    expect(await tree.resolve('playlist:9\u001fa'), isNull);
    expect(await tree.resolve('no-separator'), isNull);
  });
}
