import 'host.dart';
import 'web_audio.dart';
import 'web_storage.dart';

/// What this build of Riflay can offer, so screens ask for a feature by name instead of checking the platform.
///
/// Everything is on in the native builds. The web build streams YouTube Music signed out through the proxy
/// (`network.dart`), with the equalizer and visualizer in Web Audio, the history in local storage and Listen together
/// over a WebSocket. It has none of what needs the device itself: files, the mpv sound engine, a Google or Spotify
/// session, the local network or other apps. Hide a control whose feature is off; never leave it dead.
abstract final class Features {
  /// On-demand release checks and native Android APK updates.
  static bool get appUpdates => !Host.isWeb;

  /// FFmpeg and yt-dlp can be downloaded into Riflay's own tool folder on desktop.
  static bool get downloadedTools => Host.isLinux || Host.isWindows || Host.isMacOS;

  /// Music folders, adding songs and folders, the tag editor, duplicates, converting to FLAC.
  static bool get localLibrary => !Host.isWeb;

  /// Your own lyrics from an .lrc or .txt file (kept as a file on the device).
  static bool get userLyrics => !Host.isWeb;

  /// Saving songs and videos for offline listening.
  static bool get downloads => !Host.isWeb;

  /// Saving a YouTube song's audio as a file through the browser's downloads (the web build's stand-in for
  /// [downloads]: the file is the user's to keep, not part of Riflay's library).
  static bool get saveToDevice => Host.isWeb;

  /// Signing in to YouTube Music (liked songs, playlists, history).
  static bool get youtubeSignIn => !Host.isWeb;

  /// Spotify sign-in and import, and importing playlists from other services.
  static bool get playlistImport => !Host.isWeb;

  /// Playing on a TV or speaker (DLNA, AirPlay).
  static bool get casting => !Host.isWeb;

  /// Listen together (internet rooms everywhere; see [listenOnLan]).
  static bool get listenTogether => true;

  /// Listen together on the same Wi-Fi: finding and hosting sessions takes the local network's sockets, which a
  /// browser doesn't have. The web build meets over the internet (a secure WebSocket to the broker).
  static bool get listenOnLan => !Host.isWeb;

  /// Discord Rich Presence.
  static bool get discord => !Host.isWeb;

  /// Video mode: a song's music video on Now Playing.
  static bool get videoMode => !Host.isWeb;

  /// Decoded audio analysis for experimental player decorations: mpv's filters natively, Web Audio in a browser.
  static bool get audioVisualizer => !Host.isWeb || WebAudio.available;

  /// The mini player, which shrinks the app's own window.
  static bool get miniPlayer => !Host.isWeb;

  /// The listening history, Stats and the monthly Wrap (kept in a file on the device, in the browser's local
  /// storage on the web).
  static bool get listeningHistory => !Host.isWeb || WebStorage.available;

  /// System notifications (downloads, the monthly Wrap). A browser's would need a permission prompt and a page
  /// that stays open.
  static bool get systemNotifications => !Host.isWeb;

  /// Last.fm and ListenBrainz (their sign-ins and queue are kept in files; the proxy doesn't carry their hosts).
  static bool get scrobbling => !Host.isWeb;

  /// SpotiFLAC extensions (their scripts run in an embedded JavaScript engine, which the web build doesn't have).
  static bool get extensions => !Host.isWeb;

  /// SoundCloud as a second place to search and stream from. Its songs play through just_audio's loopback server
  /// (see `SoundcloudAudioSource`), which a browser doesn't have, and api-v2 sends no CORS headers.
  /// `RIFLAY_NO_SOUNDCLOUD` leaves it out everywhere.
  static bool get soundcloud => !Host.isWeb && !const bool.fromEnvironment('RIFLAY_NO_SOUNDCLOUD');

  /// Backup & restore (reads and writes the app's own files, then restarts it).
  static bool get backup => !Host.isWeb;
}
