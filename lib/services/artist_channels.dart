import '../models/track.dart';
import 'youtube_music_account.dart';
import 'ytmusic_web.dart' show WebResultKind;

/// YouTube Music artist channels (`UC…`) found by name, for an artist known only by name (a song by several
/// artists, a downloaded song). Only an artist of exactly that name counts, so another one is never opened.
/// Asked once per name for the app's run.
abstract final class ArtistChannels {
  static final _found = <String, Future<String?>>{};
  static final _pictures = <String, Future<Track?>>{};

  /// The artist's own photo from their YouTube Music page, as a picture-only track for a page's header (the
  /// way playlist covers are drawn); null when none is found (offline, or no artist of exactly that name).
  static Future<Track?> picture(YoutubeMusicAccount account, String name, {String? channelId}) =>
      _pictures[channelId ?? name.trim().toLowerCase()] ??= () async {
        try {
          final id = channelId ?? await find(account, name);
          final url = id == null ? null : (await account.artistInfo(id))?.thumbnailUrl;
          if (url == null) return null;
          return Track.youtube(videoId: 'artist-$id', title: name, artist: name, artworkUrl: url);
        } catch (_) {
          _pictures.remove(channelId ?? name.trim().toLowerCase());
          return null;
        }
      }();

  static Future<String?> find(YoutubeMusicAccount account, String name) =>
      _found[name.trim().toLowerCase()] ??= () async {
        try {
          final matches = await account.searchOnly(name, WebResultKind.artist);
          final same = matches.where((a) => a.title.trim().toLowerCase() == name.trim().toLowerCase());
          final id = same.firstOrNull?.browseId;
          return id != null && id.startsWith('UC') ? id : null;
        } catch (_) {
          // Offline, or YouTube Music didn't answer: ask again next time.
          _found.remove(name.trim().toLowerCase());
          return null;
        }
      }();
}
