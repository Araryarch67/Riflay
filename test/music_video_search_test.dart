import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/ytmusic_web.dart';

void main() {
  const title = 'A Horny Money World ～伝説の夜～ - A Horny Money World 〜legendary night〜';
  const song = WebTrack(
    videoId: 'NSLYAT7sjAA',
    title: title,
    artist: 'Houshou Marine',
    duration: Duration(seconds: 197),
  );
  WebTrack video(String id, String t, String by, int s) => WebTrack(
    videoId: id,
    title: t,
    artist: by,
    duration: Duration(seconds: s),
  );

  test('takes the official video: same title, the artist, nearly the same length', () {
    // What YouTube Music's video search gave for this song, which it pairs with no video signed out.
    final found = [
      video('2_opjVlYhi4', title, 'Houshou Marine', 195),
      video('R0lS5kgTVTU', '『A Horny Money World ~伝説の夜~💋』Kpop Demon Hunters [4K QUALITY]', 'Hyper Verse • MMD', 198),
      video('L-7okZZnc6k', '【歌ってみた】A Horny Money World ~伝説の夜~ covered by 御莉姫', 'ORIHIME', 196),
    ];
    expect(YtMusicWeb.matchMusicVideo(song, found), '2_opjVlYhi4');
  });

  test('leaves covers, uploads by others and a different length alone', () {
    expect(YtMusicWeb.matchMusicVideo(song, [video('a', title, 'Some Fan', 197)]), isNull, reason: 'not the artist');
    expect(YtMusicWeb.matchMusicVideo(song, [video('b', '$title (cover)', 'Houshou Marine', 197)]), isNull);
    expect(
      YtMusicWeb.matchMusicVideo(song, [video('c', title, 'Houshou Marine', 231)]),
      isNull,
      reason: 'a longer cut would run out of time with the sound',
    );
    expect(YtMusicWeb.matchMusicVideo(song, [video('NSLYAT7sjAA', title, 'Houshou Marine', 197)]), isNull);
  });

  test('a song by several artists matches a video by any of them, case and spaces aside', () {
    const duet = WebTrack(videoId: 's', title: 'Song  Title', artist: 'Ann, Bo', duration: Duration(seconds: 200));
    expect(YtMusicWeb.matchMusicVideo(duet, [video('v', 'song title', 'Bo - Topic', 202)]), 'v');
  });

  test("the same main title with a typo after the dash, and the artist's own channel under another name", () {
    const suki = WebTrack(
      videoId: 'Vgipg_bXYwg',
      title: 'スキスキDieスキ超Ayeシテル - Suki-Suki Diesuki Cho AyeShiteru',
      artist: 'Houshou Marine',
      duration: Duration(seconds: 275),
    );
    expect(
      YtMusicWeb.matchMusicVideo(suki, [
        video('il5hYhatDC4', '【Full Dance】振付師が スキスキdieスキ超Ayeシテル / 宝鐘マリン 踊ってみた【hololive】', 'わた公式 / wata', 275),
        video('aI769CgHfLc', 'スキスキDieスキ超Ayeシテル - Suki-Suki Diesuki Cho Ayeiteru', 'Houshou Marine', 275),
      ]),
      'aI769CgHfLc',
    );
    const ahoy = WebTrack(
      videoId: 'g',
      title: 'Ahoy!! 我ら宝鐘海賊団☆',
      artist: '宝鐘マリン',
      artistId: 'UCmarine',
      duration: Duration(seconds: 308),
    );
    final official = WebTrack(
      videoId: 'full',
      title: 'Ahoy!! 我ら宝鐘海賊団☆ - Ahoy!! We are Houshou Pirates',
      artist: 'Houshou Marine',
      artistId: 'UCmarine',
      duration: const Duration(seconds: 307),
    );
    expect(YtMusicWeb.matchMusicVideo(ahoy, [official]), 'full', reason: 'her own channel, under its English name');
    expect(
      YtMusicWeb.matchMusicVideo(ahoy, [
        video('risu', 'Ahoy!! 我ら宝鐘海賊団☆ (Risu ver) - Ayunda Risu', 'Suspicious Platypus', 308),
      ]),
      isNull,
      reason: "another singer, on someone else's channel",
    );
    expect(
      YtMusicWeb.matchMusicVideo(ahoy, [
        WebTrack(
          videoId: 'short',
          title: official.title,
          artist: 'Houshou Marine',
          artistId: 'UCmarine',
          duration: const Duration(seconds: 111),
        ),
      ]),
      isNull,
      reason: 'a short cut would leave the picture far behind the sound',
    );
  });
}
