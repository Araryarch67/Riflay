import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/duplicate_finder.dart';

DuplicateItem item(
  String path, {
  String title = 'Song',
  String artist = 'Artist',
  String? album,
  int seconds = 200,
  int? bytes,
  bool riflay = false,
  bool tagged = true,
  int? trackNumber,
  int addedAt = 1,
}) {
  final uri = Uri.file(path);
  return DuplicateItem(
    track: Track(
      id: uri.toString(),
      uri: uri,
      title: title,
      artist: artist,
      album: album,
      duration: Duration(seconds: seconds),
      trackNumber: trackNumber,
      tagged: tagged,
      addedAt: addedAt,
      sourceUrl: riflay ? 'https://music.youtube.com/watch?v=abc' : null,
    ),
    bytes: bytes,
    madeByRiflay: riflay,
  );
}

void main() {
  group('normalizing', () {
    test('upload noise, accents, case and punctuation do not matter', () {
      expect(normalizeTitle('Café del Mar (Official Video)'), normalizeTitle('cafe del mar'));
      expect(normalizeTitle('Song [Lyrics]'), 'song');
      expect(normalizeTitle('Song - Official Audio'), 'song');
      expect(normalizeTitle("Don't Stop!"), normalizeTitle('Dont Stop'));
      expect(normalizeTitle('Song (feat. Someone)'), 'song');
      expect(normalizeTitle('Song ft. Someone Else'), 'song');
    });

    test('different recordings stay different', () {
      expect(normalizeTitle('Song (Live)'), isNot(normalizeTitle('Song')));
      expect(normalizeTitle('Song (Remix)'), isNot(normalizeTitle('Song')));
      expect(normalizeTitle('Song (Acoustic)'), isNot(normalizeTitle('Song')));
    });

    test('a title that repeats the artist matches the plain title', () {
      expect(normalizeTitle('Artist - Song', artist: 'Artist'), normalizeTitle('Song'));
    });

    test('artists: topic channels, vevo, features and pairs', () {
      expect(normalizeArtist('Artist - Topic'), 'artist');
      expect(normalizeArtist('ArtistVEVO'), 'artist');
      expect(normalizeArtist('Artist feat. Other'), 'artist');
      expect(normalizeArtist('Artist & Other'), 'artist');
      expect(normalizeArtist('ÁRTIST'), 'artist');
    });
  });

  group('grouping', () {
    test('same song in different formats is one group, any file name', () {
      final groups = findDuplicates([
        item('/m/a.flac', bytes: 30000000),
        item('/m/b.mp3', title: 'SONG (Official Video)', bytes: 5000000, seconds: 201),
        item('/m/other.mp3', title: 'Different'),
      ]);
      expect(groups, hasLength(1));
      expect(groups.single.items, hasLength(2));
    });

    test('lengths more than 2 seconds apart are different recordings', () {
      expect(findDuplicates([item('/m/a.mp3'), item('/m/b.mp3', seconds: 203)]), isEmpty);
      expect(findDuplicates([item('/m/a.mp3'), item('/m/b.mp3', seconds: 202)]), hasLength(1));
    });

    test('different artists are not duplicates', () {
      expect(findDuplicates([item('/m/a.mp3'), item('/m/b.mp3', artist: 'Someone Else')]), isEmpty);
    });

    test('a YouTube download and a local file of the same song group together', () {
      final groups = findDuplicates([
        item('/dl/Song.opus', artist: 'Artist - Topic', riflay: true, bytes: 3000000),
        item('/m/Song.mp3', bytes: 6000000),
      ]);
      expect(groups, hasLength(1));
    });

    test('album can be required to match when both copies name one', () {
      final a = item('/m/a.mp3', album: 'Album One');
      final b = item('/m/b.mp3', album: 'Greatest Hits');
      expect(findDuplicates([a, b]), hasLength(1));
      expect(findDuplicates([a, b], matchAlbum: true), isEmpty);
      expect(findDuplicates([a, item('/m/c.mp3')], matchAlbum: true), hasLength(1)); // one has no album
    });

    test('a long-titled song without an artist joins the one artist that fits, a short one does not', () {
      final long = [
        item('/m/a.mp3', title: 'A Long Song Title'),
        item('/m/b.mp3', title: 'A Long Song Title', artist: Track.unknownArtist),
      ];
      expect(findDuplicates(long), hasLength(1));
      final short = [item('/m/a.mp3', title: 'Intro'), item('/m/b.mp3', title: 'Intro', artist: Track.unknownArtist)];
      expect(findDuplicates(short), isEmpty);
    });

    test('an artist-less file does not join two different artists together', () {
      final groups = findDuplicates([
        item('/m/a.mp3', title: 'A Long Song Title', artist: 'First'),
        item('/m/b.mp3', title: 'A Long Song Title', artist: 'Second'),
        item('/m/c.mp3', title: 'A Long Song Title', artist: Track.unknownArtist),
      ]);
      expect(groups, isEmpty);
    });

    test('cue slices, streamed songs and songs with no length are not compared', () {
      final cue = Track(
        id: '${Uri.file('/m/x.flac')}#cue1',
        uri: Uri.file('/m/x.flac'),
        title: 'Song',
        artist: 'Artist',
        start: Duration.zero,
        duration: const Duration(seconds: 200),
      );
      final yt = Track.youtube(videoId: 'abc', title: 'Song', artist: 'Artist', duration: const Duration(seconds: 200));
      expect(canCompare(cue), isFalse);
      expect(canCompare(yt), isFalse);
      expect(canCompare(item('/m/a.mp3').track), isTrue);
      expect(findDuplicates([DuplicateItem(track: cue, bytes: 1, madeByRiflay: false), item('/m/a.mp3')]), isEmpty);
    });
  });

  group('best to keep', () {
    test('lossless beats a higher-bitrate lossy file', () {
      final flac = item('/m/a.flac', bytes: 20000000);
      final mp3 = item('/m/a.mp3', bytes: 8000000); // 320 kbps
      expect(compareQuality(flac, mp3), lessThan(0));
      expect(findDuplicates([mp3, flac]).single.best.path, '/m/a.flac');
    });

    test('higher bitrate beats lower, and a codec counts for what it is', () {
      final mp3_320 = item('/m/a.mp3', bytes: 8000000);
      final mp3_128 = item('/m/b.mp3', bytes: 3200000);
      expect(compareQuality(mp3_320, mp3_128), lessThan(0));
      // Opus at 128 kbps (~MP3 192) beats MP3 at 128.
      final opus = item('/m/c.opus', bytes: 3200000);
      expect(compareQuality(opus, mp3_128), lessThan(0));
    });

    test('equal sound: fuller tags win, then your own file over a download', () {
      final bare = item('/m/a.mp3', bytes: 6400000, tagged: false);
      final full = item('/m/b.mp3', bytes: 6400000, album: 'Album', trackNumber: 3);
      expect(compareQuality(full, bare), lessThan(0));
      final mine = item('/m/c.mp3', bytes: 6400000);
      final download = item('/dl/c.mp3', bytes: 6400000, riflay: true);
      expect(compareQuality(mine, download), lessThan(0));
    });

    test('the choice does not depend on the order given', () {
      final all = [
        item('/m/a.mp3', bytes: 3200000),
        item('/m/b.flac', bytes: 25000000),
        item('/m/c.mp3', bytes: 8000000),
      ];
      final fwd = findDuplicates(all).single.items.map((i) => i.path).toList();
      final rev = findDuplicates(all.reversed).single.items.map((i) => i.path).toList();
      expect(fwd, rev);
      expect(fwd.first, '/m/b.flac');
    });

    test('bitrate comes from size and length', () {
      expect(item('/m/a.mp3', bytes: 8000000, seconds: 200).kbps, 320);
    });
  });

  group('removal safety', () {
    DuplicateGroup group(List<DuplicateItem> items) => DuplicateGroup(items);

    test('the kept copy is never removed or deleted', () {
      final flac = item('/m/a.flac', bytes: 20000000);
      final mp3 = item('/m/a.mp3', bytes: 8000000);
      final g = group([flac, mp3]);
      final plan = planRemoval([RemovalChoice(g, flac.track.id)], deleteFiles: true, library: [flac.track, mp3.track]);
      expect(plan.removeFromLibrary.map((t) => t.id), [mp3.track.id]);
      expect(plan.filesToDelete.map((i) => i.path), ['/m/a.mp3']);
      expect(plan.bytesFreed, 8000000);
      expect(plan.keptInstead[mp3.track.id]!.id, flac.track.id);
    });

    test('without the delete option no file is touched', () {
      final a = item('/m/a.flac', bytes: 1);
      final b = item('/m/a.mp3', bytes: 1);
      final plan = planRemoval(
        [
          RemovalChoice(group([a, b]), a.track.id),
        ],
        deleteFiles: false,
        library: [a.track, b.track],
      );
      expect(plan.filesToDelete, isEmpty);
      expect(plan.bytesFreed, 0);
      expect(plan.removeFromLibrary, hasLength(1));
    });

    test('a keep id that is not in the group removes nothing', () {
      final a = item('/m/a.flac');
      final b = item('/m/a.mp3');
      final plan = planRemoval(
        [
          RemovalChoice(group([a, b]), 'nope'),
        ],
        deleteFiles: true,
        library: [a.track, b.track],
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.filesToDelete, isEmpty);
    });

    test('a file another library song still plays from is not deleted', () {
      final a = item('/m/a.flac');
      final b = item('/m/a.mp3', bytes: 10);
      final sharing = Track(
        id: '${Uri.file('/m/a.mp3')}#cue1',
        uri: Uri.file('/m/a.mp3'),
        title: 'Slice',
        artist: 'Artist',
        start: Duration.zero,
      ); // another song of the library plays from the same file
      final plan = planRemoval(
        [
          RemovalChoice(group([a, b]), a.track.id),
        ],
        deleteFiles: true,
        library: [a.track, b.track, sharing],
      );
      expect(plan.removeFromLibrary, hasLength(1));
      expect(plan.filesToDelete, isEmpty);
      expect(plan.skippedFiles, 1);
    });

    test('a file shared with the kept copy is never deleted', () {
      final a = item('/m/same.flac');
      final b = item('/m/same.flac');
      // Two entries for one path can't have two ids; make the second differ in id only.
      final twin = DuplicateItem(
        track: Track(
          id: 'twin',
          uri: Uri.file('/m/same.flac'),
          title: 'Song',
          artist: 'Artist',
          duration: const Duration(seconds: 200),
        ),
        bytes: 5,
        madeByRiflay: false,
      );
      final plan = planRemoval(
        [
          RemovalChoice(group([a, twin]), a.track.id),
        ],
        deleteFiles: true,
        library: [a.track, twin.track],
      );
      expect(plan.filesToDelete, isEmpty);
      expect(b.path, a.path);
    });

    test('a group the person keeps whole is left out of the choices', () {
      final plan = planRemoval(const [], deleteFiles: true, library: const []);
      expect(plan.isEmpty, isTrue);
    });

    test('downloads and own files are counted apart', () {
      final keep = item('/m/a.flac');
      final own = item('/m/a.mp3', bytes: 4);
      final dl = item('/dl/a.opus', bytes: 2, riflay: true);
      final plan = planRemoval(
        [
          RemovalChoice(group([keep, own, dl]), keep.track.id),
        ],
        deleteFiles: true,
        library: [keep.track, own.track, dl.track],
      );
      expect(plan.ownFilesToDelete, 1);
      expect(plan.downloadsToDelete, 1);
      expect(plan.bytesFreed, 6);
    });

    test('a song kept in one group is not removed through another', () {
      final a = item('/m/a.flac');
      final b = item('/m/a.mp3');
      final c = item('/m/a.ogg');
      final plan = planRemoval(
        [
          RemovalChoice(group([a, b]), a.track.id),
          RemovalChoice(group([b, c]), b.track.id),
        ],
        deleteFiles: true,
        library: [a.track, b.track, c.track],
      );
      expect(plan.removeFromLibrary.map((t) => t.id), [c.track.id]);
    });
  });
}
