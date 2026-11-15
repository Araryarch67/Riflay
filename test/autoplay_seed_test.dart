import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';

Track local(String n) => Track(id: 'file:///m/$n.mp3', uri: Uri.parse('file:///m/$n.mp3'), title: n, artist: 'A');
Track yt(String id) => Track.youtube(videoId: id, title: id, artist: 'B');

void main() {
  test('a streamed current song seeds autoplay itself', () {
    final queue = [yt('a'), local('x'), yt('b')];
    expect(PlayerController.autoplaySeedIn(queue, 2), queue[2]);
  });

  test('a local song at the end of the queue seeds from the last streamed song before it', () {
    final queue = [yt('a'), yt('b'), local('x'), local('y')];
    expect(PlayerController.autoplaySeedIn(queue, 3), queue[1]);
  });

  test('an all-local queue has no streamed seed (the current song is looked up by name)', () {
    final queue = [local('x'), local('y')];
    expect(PlayerController.autoplaySeedIn(queue, 1), isNull);
    expect(PlayerController.autoplaySeedIn(const [], 0), isNull);
  });
}
