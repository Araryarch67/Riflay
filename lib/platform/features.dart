import 'host.dart';

/// What this build of Riflay can offer, so screens ask for a feature by name instead of checking the platform.
///
/// Everything is on in the native builds. The web build streams YouTube Music signed out through the proxy
/// (`network.dart`) and has none of what needs the device itself: files, the mpv sound engine, a Google or Spotify
/// session, the local network or other apps. Hide a control whose feature is off; never leave it dead.
abstract final class Features {
  /// Music folders, adding songs and folders, the tag editor, duplicates, converting to FLAC.
  static bool get localLibrary => !Host.isWeb;

  /// Your own lyrics from an .lrc or .txt file (kept as a file on the device).
  static bool get userLyrics => !Host.isWeb;

  /// Saving songs and videos for offline listening.
  static bool get downloads => !Host.isWeb;

  /// Signing in to YouTube Music (liked songs, playlists, history).
  static bool get youtubeSignIn => !Host.isWeb;

  /// Spotify sign-in and import, and importing playlists from other services.
  static bool get playlistImport => !Host.isWeb;

  /// Playing on a TV or speaker (DLNA, AirPlay).
  static bool get casting => !Host.isWeb;

  /// Listen together (LAN and internet rooms).
  static bool get listenTogether => !Host.isWeb;

  /// Discord Rich Presence.
  static bool get discord => !Host.isWeb;

  /// Video mode: a song's music video on Now Playing.
  static bool get videoMode => !Host.isWeb;

  /// The mini player, which shrinks the app's own window.
  static bool get miniPlayer => !Host.isWeb;

  /// The listening history, Stats and the monthly Wrap (kept in a file on the device).
  static bool get listeningHistory => !Host.isWeb;
}
