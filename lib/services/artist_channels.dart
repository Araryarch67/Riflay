import 'youtube_music_account.dart';
import 'ytmusic_web.dart' show WebResultKind;

/// YouTube Music artist channels (`UC…`) found by name, for an artist known only by name (a song by several
/// artists, a downloaded song). Only an artist of exactly that name counts, so another one is never opened.
/// Asked once per name for the app's run.
abstract final class ArtistChannels {
  static final _found = <String, Future<String?>>{};

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
