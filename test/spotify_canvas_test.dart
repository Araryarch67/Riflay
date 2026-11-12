import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/spotify_canvas.dart';
import 'package:riflay/services/spotify_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:riflay/services/spotify_account.dart';

import 'spotify_import_test.dart' show FakeLibrary;

class _Account extends SpotifyAccount {
  @override
  bool get isSignedIn => true;
  @override
  Future<void> load() async {}
}

class _Canvas extends FakeLibrary {
  int searches = 0;
  @override
  Future<String?> findTrack(String title, String artist, {Duration? duration}) async {
    searches++;
    return title == 'luther' ? 'spotify:track:abc' : null;
  }

  @override
  Future<Uri?> canvasUrl(String trackUri) async =>
      trackUri == 'spotify:track:abc' ? Uri.parse('https://canvaz.scdn.co/upload/x.cnvs.mp4') : null;
}

void main() {
  test('the web player\'s search answer is read wherever it puts its tracks, and the same song picked', () {
    final answer = {
      'data': {
        'searchV2': {
          'topResultsV2': {
            'itemsV2': [
              {
                'item': {
                  'data': {
                    'uri': 'spotify:track:live',
                    'name': 'luther (Live)',
                    'artists': {
                      'items': [
                        {
                          'profile': {'name': 'Cover Band'},
                        },
                      ],
                    },
                    'duration': {'totalMilliseconds': 177000},
                  },
                },
              },
              {
                'item': {
                  'data': {
                    'uri': 'spotify:track:abc',
                    'name': 'luther (with SZA)',
                    'artists': {
                      'items': [
                        {
                          'profile': {'name': 'Kendrick Lamar'},
                        },
                        {
                          'profile': {'name': 'SZA'},
                        },
                      ],
                    },
                    'duration': {'totalMilliseconds': 177598},
                  },
                },
              },
            ],
          },
        },
      },
    };
    final found = SpotifyLibraryClient.tracksIn(answer);
    expect(found.map((t) => t.uri), ['spotify:track:live', 'spotify:track:abc']);
    expect(
      SpotifyLibraryClient.bestTrack(found, 'luther', 'Kendrick Lamar, SZA', duration: const Duration(seconds: 178)),
      'spotify:track:abc',
      reason: 'another artist\'s song of the same name is passed over',
    );
    expect(SpotifyLibraryClient.bestTrack(found, 'Not Like Us', 'Kendrick Lamar'), isNull);
  });

  test('a Canvas video is used; a still image or nothing is not', () {
    Map<String, Object?> canvas(Map<String, Object?> c) => {
      'data': {
        'trackUnion': {'__typename': 'Track', 'canvas': c},
      },
    };
    expect(
      SpotifyLibraryClient.canvasIn(
        canvas({'url': 'https://canvaz.scdn.co/upload/x.cnvs.mp4', 'type': 'VIDEO_LOOPING'}),
      ),
      Uri.parse('https://canvaz.scdn.co/upload/x.cnvs.mp4'),
    );
    expect(SpotifyLibraryClient.canvasIn(canvas({'url': 'https://i.scdn.co/x.jpg', 'type': 'IMAGE'})), isNull);
    expect(SpotifyLibraryClient.canvasIn(canvas({})), isNull);
    expect(
      SpotifyLibraryClient.canvasIn({
        'data': {'trackUnion': null},
      }),
      isNull,
    );
  });

  test('looked up once per song, only when turned on and signed in', () async {
    SharedPreferences.setMockInitialValues({});
    final spotify = _Canvas();
    final account = _Account();
    final c = SpotifyCanvas(account: account, client: () => spotify);
    final song = Track.youtube(videoId: 'v1', title: 'luther', artist: 'Kendrick Lamar, SZA');
    c.lookUp(song);
    await Future<void>.delayed(Duration.zero);
    expect(spotify.searches, 0, reason: 'off until turned on');
    await c.setEnabled(true);
    var done = 0;
    c.lookUp(song, done: () => done++);
    c.lookUp(song);
    for (var i = 0; i < 20 && done == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(c.of(song), Uri.parse('https://canvaz.scdn.co/upload/x.cnvs.mp4'));
    expect(spotify.searches, 1);
    final none = Track.youtube(videoId: 'v2', title: 'Other', artist: 'Someone');
    c.lookUp(none, done: () => done++);
    for (var i = 0; i < 20 && done < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(c.of(none), isNull);
    expect(c.knows(none), isTrue);
  });
}
