import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/youtube_video_search.dart';
import 'package:riflay/services/ytmusic_web.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' show YoutubeExplode;

Map<String, dynamic> _column(List<Map<String, dynamic>> runs) => {
  'musicResponsiveListItemFlexColumnRenderer': {
    'text': {'runs': runs},
  },
};

Map<String, dynamic> _thumb(String url) => {
  'musicThumbnailRenderer': {
    'thumbnail': {
      'thumbnails': [
        {'url': url, 'width': 120, 'height': 120},
      ],
    },
  },
};

Track _song(String id) => Track.youtube(videoId: id, title: id, artist: 'Artist');

void main() {
  podcastPagingTests();
  test('a podcast show row keeps its MPSP id, which opens as its episodes', () {
    final row = {
      'thumbnail': _thumb('https://i.ytimg.com/show.jpg'),
      'navigationEndpoint': {
        'browseEndpoint': {
          'browseId': 'MPSPPLabc',
          'browseEndpointContextSupportedConfigs': {
            'browseEndpointContextMusicConfig': {'pageType': 'MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE'},
          },
        },
      },
      'flexColumns': [
        _column([
          {'text': 'The Show'},
        ]),
        _column([
          {
            'text': 'Host',
            'navigationEndpoint': {
              'browseEndpoint': {'browseId': 'UChost'},
            },
          },
        ]),
      ],
    };
    final show = YtMusicWeb.podcastOf(row)!;
    expect(show.kind, WebResultKind.playlist);
    expect(show.title, 'The Show');
    expect(show.subtitle, 'Host');
    expect(show.browseId, 'MPSPPLabc');
    expect(show.thumbnailUrl, 'https://i.ytimg.com/show.jpg');
    expect(YtMusicWeb.podcastOf({...row, 'navigationEndpoint': const {}}), isNull);
  });

  test('an episode row plays its video, with the show (not the date) as who made it', () {
    final row = {
      'overlay': {
        'musicItemThumbnailOverlayRenderer': {
          'content': {
            'musicPlayButtonRenderer': {
              'playNavigationEndpoint': {
                'watchEndpoint': {'videoId': 'ep1'},
              },
            },
          },
        },
      },
      'flexColumns': [
        _column([
          {'text': ' Episode #1 '},
        ]),
        _column([
          {'text': 'Nov 11'},
          {'text': ' • '},
          {
            'text': 'The Show',
            'navigationEndpoint': {
              'browseEndpoint': {'browseId': 'MPSPPLabc'},
            },
          },
        ]),
      ],
    };
    final episode = YtMusicWeb.episodeOf(row)!;
    expect(episode.videoId, 'ep1');
    expect(episode.title, 'Episode #1');
    expect(episode.artist, 'The Show');
  });

  test("a show page's episode reads its length in words", () {
    final episode = YtMusicWeb.episodeRowOf({
      'onTap': {
        'watchEndpoint': {'videoId': 'ep2'},
      },
      'title': {
        'runs': [
          {'text': 'Episode #2'},
        ],
      },
      'playbackProgress': {
        'musicPlaybackProgressRenderer': {
          'playbackProgressText': {
            'runs': [
              {'text': ' • '},
              {'text': '2 hr 42 min'},
            ],
          },
        },
      },
    }, show: 'The Show')!;
    expect(episode.videoId, 'ep2');
    expect(episode.artist, 'The Show');
    expect(episode.duration, const Duration(hours: 2, minutes: 42));
    expect(YtMusicWeb.spokenDuration('45 min'), const Duration(minutes: 45));
    expect(YtMusicWeb.spokenDuration('1 hr'), const Duration(hours: 1));
    expect(YtMusicWeb.spokenDuration('30 sec'), const Duration(seconds: 30));
    expect(YtMusicWeb.spokenDuration('Nov 11'), isNull);
  });

  test('videos come from YouTube Music page by page, without repeats', () async {
    final asked = <String?>[];
    final search = YoutubeVideoSearch(
      client: YoutubeExplode(),
      music: (query, continuation) async {
        asked.add(continuation);
        return switch (continuation) {
          null => (tracks: [_song('a'), _song('b')], next: 'p2'),
          'p2' => (tracks: [_song('b'), _song('c')], next: null),
          _ => throw StateError('unexpected'),
        };
      },
    );
    addTearDown(search.dispose);
    expect((await search.search('q')).map((t) => t.videoId), ['a', 'b']);
    expect(search.hasMore, isTrue);
    expect((await search.more()).map((t) => t.videoId), ['c']);
    expect(search.hasMore, isFalse);
    expect(await search.more(), isEmpty);
    expect(asked, [null, 'p2']);
  });
}

Map<String, dynamic> _episode(String id) => {
  'musicMultiRowListItemRenderer': {
    'title': {
      'runs': [
        {'text': 'Episode $id'},
      ],
    },
    'onTap': {
      'watchEndpoint': {'videoId': id},
    },
  },
};

void podcastPagingTests() {
  test('a show opens on its newest page, and older episodes follow page by page', () async {
    final asked = <Map<String, dynamic>>[];
    final web = YtMusicWeb(
      cookies: '',
      visitorData: '',
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        asked.add(body);
        final page = switch (body['continuation']) {
          null => {
            'header': {
              'musicResponsiveHeaderRenderer': {
                'title': {
                  'runs': [
                    {'text': 'The Show'},
                  ],
                },
              },
            },
            'contents': {
              'musicShelfRenderer': {
                'contents': [
                  _episode('e1'),
                  _episode('e2'),
                  {
                    'continuationItemRenderer': {
                      'continuationEndpoint': {
                        'continuationCommand': {'token': 'page2'},
                      },
                    },
                  },
                ],
              },
            },
          },
          'page2' => {
            'onResponseReceivedActions': [
              {
                'appendContinuationItemsAction': {
                  'continuationItems': [_episode('e3')],
                },
              },
            ],
          },
          _ => <String, dynamic>{},
        };
        return http.Response(jsonEncode(page), 200, headers: {'content-type': 'application/json'});
      }),
    );
    final first = await web.podcastEpisodePage('MPSPPLabc');
    expect(first.episodes.map((e) => e.videoId), ['e1', 'e2']);
    expect(first.episodes.first.artist, 'The Show');
    expect(first.next, 'page2');
    final older = await web.podcastEpisodePage('MPSPPLabc', continuation: first.next, show: first.show);
    expect(older.episodes.single.videoId, 'e3');
    expect(older.episodes.single.artist, 'The Show');
    expect(older.next, isNull);
    expect(asked.last['continuation'], 'page2');
  });
}
