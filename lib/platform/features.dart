import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart' show WidgetsBinding;

import '../app_version.dart';
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
  /// A browser controls its own forward proxy; native app requests can configure one.
  static bool get networkProxy => !Host.isWeb;

  /// On-demand release checks and native Android APK updates. Nightly is a separate app from the stable
  /// release, so it must not offer the stable build as an update; install the next nightly instead.
  static bool get appUpdates => !Host.isWeb && !isNightly;

  /// FFmpeg and yt-dlp can be downloaded into Riflay's own tool folder on desktop.
  static bool get downloadedTools => Host.isLinux || Host.isWindows || Host.isMacOS;

  /// Music folders, adding songs and folders, the tag editor, duplicates, converting to FLAC.
  static bool get localLibrary => !Host.isWeb;

  /// Local lossless matches and merged streams use the native audio source proxy.
  static bool get smartMerge => !Host.isWeb;

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

  /// Import a playlist file with filesystem paths on desktop.
  static bool get playlistFileImport => Host.isWindows || Host.isLinux || Host.isMacOS;

  /// Playing on a TV or speaker (DLNA, AirPlay).
  static bool get casting => !Host.isWeb;

  /// Listen together (internet rooms everywhere; see [listenOnLan]).
  static bool get listenTogether => true;

  /// Listen together on the same Wi-Fi: finding and hosting sessions takes the local network's sockets, which a
  /// browser doesn't have. The web build meets over the internet (a secure WebSocket to the broker).
  static bool get listenOnLan => !Host.isWeb;

  static bool get discord => !Host.isWeb;

  /// Video mode: a song's music video on Now Playing.
  static bool get videoMode => !Host.isWeb;

  /// Decoded audio analysis for experimental player decorations: mpv's filters natively, Web Audio in a browser.
  static bool get audioVisualizer => !Host.isWeb || WebAudio.available;

  /// The mini player, which shrinks the app's own window: only where the app has one to shrink (not a phone or
  /// tablet, where the window manager isn't there and the switch left the app stuck in a mini state).
  static bool get miniPlayer => Host.isWindows || Host.isLinux || Host.isMacOS;

  /// Settings of the phone layout alone (its tab bar, the bar above it, the phone player's cover, quality badge and
  /// volume row): shown on phones and tablets, and in a browser. A computer's window made narrow uses the phone
  /// layout too, with their defaults; its Settings don't list them.
  static bool get phoneLayout => _mobile || Host.isWeb;

  /// Settings of the desktop layout alone (the player bar along the window's foot): computers, tablets (wide, they
  /// use it) and browsers; never a phone, which keeps the phone layout even turned sideways.
  static bool get desktopLayout => !_mobile || _tablet;

  // The platform the layout follows (the shell's own check, which tests can set).
  static bool get _mobile =>
      defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  static bool get _tablet {
    // The binding's: the screen the app (or a test) lays out on.
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return false;
    final view = views.first;
    return (view.physicalSize / view.devicePixelRatio).shortestSide >= 600;
  }

  /// The mini player keeps off the taskbar (it stays on top, in Alt+Tab and behind the tray icon). Windows takes
  /// the button away; Linux sets the window's skip-taskbar hint. Not macOS: window_manager does it there by
  /// turning the whole app into an accessory, which also takes away its menu bar.
  static bool get miniPlayerOffTaskbar => Host.isWindows || Host.isLinux;

  /// The listening history, Stats and the monthly Wrap (kept in a file on the device, in the browser's local
  /// storage on the web).
  static bool get listeningHistory => !Host.isWeb || WebStorage.available;

  /// System notifications (downloads, the monthly Wrap). A browser's would need a permission prompt and a page
  /// that stays open.
  static bool get systemNotifications => !Host.isWeb;

  /// Last.fm and ListenBrainz (their sign-ins and queue are kept in files; the proxy doesn't carry their hosts).
  static bool get scrobbling => !Host.isWeb;

  /// SoundCloud as a second place to search and stream from. Its songs play through just_audio's loopback server
  /// (see `SoundcloudAudioSource`), which a browser doesn't have, and api-v2 sends no CORS headers.
  /// `RIFLAY_NO_SOUNDCLOUD` leaves it out everywhere.
  static bool get soundcloud => !Host.isWeb && !const bool.fromEnvironment('RIFLAY_NO_SOUNDCLOUD');

  /// Backup & restore (reads and writes the app's own files, then restarts it).
  static bool get backup => !Host.isWeb;
}
