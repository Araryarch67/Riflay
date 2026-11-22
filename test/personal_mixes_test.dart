import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/youtube_music_account.dart';

void main() {
  test("Made for you takes YouTube Music's own mixes from its Home, once each", () {
    RemotePlaylist p(String id, String title) => RemotePlaylist(id: id, browseId: id, title: title, count: 0);
    final shelves = [
      RemoteShelf(
        title: 'Mixed for you',
        collections: [p('VLRDTMAK5uy_abc', 'My Supermix'), p('VLRDTMAK5uy_def', 'My Mix 1'), p('MPREb_x', 'An album')],
      ),
      RemoteShelf(title: 'Charts', collections: [p('VLPL123', 'Top 100'), p('RDTMAK5uy_abc', 'My Supermix')]),
    ];
    expect(YoutubeMusicAccount.personalMixesIn(shelves).map((m) => m.title), ['My Supermix', 'My Mix 1']);
    expect(YoutubeMusicAccount.personalMixesIn(const []), isEmpty);
  });
}
