import 'package:flutter/foundation.dart';

/// Switches that turn Riflay's rendering shortcuts off, one at a time, to tell whether a bug comes from one of
/// them: a colour that stays stale after a theme change, a card that doesn't update, a page that shows up blank
/// for a frame. They are off in normal builds and cost nothing then.
///
/// Turn one on at launch, or all of them with `RIFLAY_NO_SHORTCUTS`:
///
///     flutter run --dart-define=RIFLAY_RESTYLE_ALL=true
///     flutter run --dart-define=RIFLAY_NO_SHORTCUTS=true --dart-define=RIFLAY_LOG_RESTYLES=true
///
/// Tests may set them directly (and put them back in `tearDown`).
abstract final class DebugSwitches {
  static const _all = bool.fromEnvironment('RIFLAY_NO_SHORTCUTS');

  /// [restyleTree] rebuilds every widget on a palette change, ignoring [ColorFreeSubtree] and [ColorFreeSelf].
  /// A stale colour that this fixes comes from a widget marked colour-free that reads [AppColors] statically.
  static bool restyleAll = _all || const bool.fromEnvironment('RIFLAY_RESTYLE_ALL');

  /// The Material theme follows every step of a colour fade, not every third one (see `appThemeNow`).
  static bool themeEveryStep = _all || const bool.fromEnvironment('RIFLAY_THEME_EVERY_STEP');

  /// [MediaCard] builds afresh every time instead of keeping what it built.
  static bool noCardCache = _all || const bool.fromEnvironment('RIFLAY_NO_CARD_CACHE');

  /// [FirstFrameGate] shows its child at once, in the app's first frame too.
  static bool noFirstFrameGate = _all || const bool.fromEnvironment('RIFLAY_NO_FIRST_FRAME_GATE');

  /// No tray icon on computers: closing the window quits, as it did before the tray, and Settings leaves out
  /// Close to tray. Not part of `RIFLAY_NO_SHORTCUTS`, which is about rendering.
  static bool noTray = const bool.fromEnvironment('RIFLAY_NO_TRAY');

  /// The phone's Liquid glass tab bar never shrinks to one row on scroll. Not part of `RIFLAY_NO_SHORTCUTS`, which
  /// is about rendering.
  static bool noTabBarCollapse = const bool.fromEnvironment('RIFLAY_NO_TAB_BAR_COLLAPSE');

  /// The Liquid glass tab bar shrinks on a scroll with no song in the player too (two round buttons, nothing between).
  static bool tabBarCollapseIdle = _all || const bool.fromEnvironment('RIFLAY_TAB_BAR_COLLAPSE_IDLE');

  /// Settings' previews ([LivePreview]) run their animations and follow the player, instead of standing still and
  /// being built afresh on each change of look.
  static bool movingPreviews = _all || const bool.fromEnvironment('RIFLAY_MOVING_PREVIEWS');

  /// The Liquid glass tab bar draws its pills with Riflay's own blur instead of liquid_glass_renderer.
  static bool noGlassRenderer = _all || const bool.fromEnvironment('RIFLAY_NO_GLASS_RENDERER');

  /// A phone page's top bar fills in with a solid colour on scroll with the Liquid glass tab bar too, not as glass.
  static bool noGlassTopBar = _all || const bool.fromEnvironment('RIFLAY_NO_GLASS_TOP_BAR');

  /// Home's Artists shelf, Library's artists and Search's open the library's artist page for every artist, as
  /// before, also for one whose songs
  /// were downloaded from YouTube Music (see `openHomeArtist`). Not part of `RIFLAY_NO_SHORTCUTS`, which is about
  /// rendering.
  static bool localHomeArtists = const bool.fromEnvironment('RIFLAY_LOCAL_HOME_ARTISTS');

  /// Turning a phone sideways while Now Playing shows the music video doesn't open it full screen (the button and a
  /// double tap on the video still do). Not part of `RIFLAY_NO_SHORTCUTS`, which is about rendering.
  static bool noVideoRotate = const bool.fromEnvironment('RIFLAY_NO_VIDEO_ROTATE');

  /// Draw video through Flutter textures to compare native surface rendering.
  static bool noNativeVideo = _all || const bool.fromEnvironment('RIFLAY_NO_NATIVE_VIDEO');

  /// [MarqueeText] scrolls forever and everywhere, as before: card titles without a hover, and past its loops.
  static bool endlessMarquee = _all || const bool.fromEnvironment('RIFLAY_ENDLESS_MARQUEE');

  /// The signal path on screen is read from mpv every second while paused too, as it was.
  static bool signalPathWhilePaused = _all || const bool.fromEnvironment('RIFLAY_SIGNAL_PATH_WHILE_PAUSED');

  /// The visualizer's meter goes into mpv's audio graph at once on every change, even when it is already there.
  static bool meterEverySync = _all || const bool.fromEnvironment('RIFLAY_METER_EVERY_SYNC');

  /// A music video holds still while another window has the focus (and is let go after 20 s), as it did.
  static bool videoHoldsBehind = _all || const bool.fromEnvironment('RIFLAY_VIDEO_HOLDS_BEHIND');

  /// Balanced's visualizer measures 24 bands over 1024-point windows, 25 times a second, as Heavy does.
  static bool fullVisualizer = _all || const bool.fromEnvironment('RIFLAY_FULL_VISUALIZER');

  /// The quality badge redraws at every read of the signal path (each second), as before, even when it shows the same.
  static bool signalPathEveryRead = _all || const bool.fromEnvironment('RIFLAY_SIGNAL_PATH_EVERY_READ');

  /// Views on [UiBeat] each count their own beats instead of sharing one count, as before: views at the same
  /// rate draw in separate frames.
  static bool unalignedBeats = _all || const bool.fromEnvironment('RIFLAY_UNALIGNED_BEATS');

  /// Lightweight's seek bar moves 2-4 times a second, as before, not once a second.
  static bool quickLightweightSeekBar = _all || const bool.fromEnvironment('RIFLAY_QUICK_LIGHTWEIGHT_SEEK_BAR');

  /// The seek bar's position stays on [UiBeat] while paused, as before.
  static bool beatWhilePaused = _all || const bool.fromEnvironment('RIFLAY_BEAT_WHILE_PAUSED');

  /// Decorations, the visualizer and marquees keep moving, and the seek bar at its speed, while another window has
  /// the focus, as before.
  static bool moveUnfocused = _all || const bool.fromEnvironment('RIFLAY_MOVE_UNFOCUSED');

  /// Balanced on a computer moves its decorations and visualizer at 20 fps, as before, instead of 5 and 10
  /// (`LayoutPrefs.frugal`).
  static bool fullBalanced = _all || const bool.fromEnvironment('RIFLAY_FULL_BALANCED');

  /// The visualizer measures its bands with `astats` (an RMS worked out on every sample, ~3x the CPU), as before,
  /// instead of `aspectralstats` (one FFT a window).
  static bool astatsVisualizer = _all || const bool.fromEnvironment('RIFLAY_ASTATS_VISUALIZER');

  /// Synced lyrics show a scrollbar on computers, as before: each line's scroll showed it and faded it out again.
  static bool lyricsScrollbar = _all || const bool.fromEnvironment('RIFLAY_LYRICS_SCROLLBAR');

  /// Decorations and the visualizer keep moving while the music video shows, as before.
  static bool motionWithVideo = _all || const bool.fromEnvironment('RIFLAY_MOTION_WITH_VIDEO');

  /// Video mode streams a song's music video even when "Download with MV" saved it beside the song. Not part of
  /// `RIFLAY_NO_SHORTCUTS`, which is about rendering.
  static bool noLocalMv = const bool.fromEnvironment('RIFLAY_NO_LOCAL_MV');

  /// Virtual speakers mix a 5.1 / 7.1 song (a Dolby Atmos bed) down to two speakers first, as before, instead of
  /// placing each channel in a 7.1 room, and Surround upmix does nothing. Not part of `RIFLAY_NO_SHORTCUTS`, which
  /// is about rendering.
  static bool stereoVirtualSpeakers = const bool.fromEnvironment('RIFLAY_STEREO_VIRTUAL_SPEAKERS');

  /// AutoEQ's list of headphones is downloaded every time the picker opens, not kept for 30 days. Not part of
  /// `RIFLAY_NO_SHORTCUTS`, which is about rendering.
  static bool autoEqFresh = const bool.fromEnvironment('RIFLAY_AUTOEQ_FRESH');

  /// Lyrics' Pronunciation is Google's for every script, as before, not Riflay's own for Korean, kana, Cyrillic and
  /// Greek, nor tidied of scholarly marks. Not part of `RIFLAY_NO_SHORTCUTS`, which is about rendering.
  static bool googleRomanization = const bool.fromEnvironment('RIFLAY_GOOGLE_ROMANIZATION');

  /// The phone's bottom bar only takes taps: sliding a finger along it doesn't switch tabs. Not part of
  /// `RIFLAY_NO_SHORTCUTS`, which is about rendering.
  static bool noTabSwipe = const bool.fromEnvironment('RIFLAY_NO_TAB_SWIPE');

  /// Prints how many widgets each palette change rebuilds, and every Material theme built.
  static bool logRestyles = const bool.fromEnvironment('RIFLAY_LOG_RESTYLES');

  /// Writes [message] when [logRestyles] is on.
  static void log(String Function() message) {
    if (logRestyles) debugPrint('[restyle] ${message()}');
  }
}
