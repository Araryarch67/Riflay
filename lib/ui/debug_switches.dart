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

  /// Settings' previews ([LivePreview]) run their animations and follow the player, instead of standing still and
  /// being built afresh on each change of look.
  static bool movingPreviews = _all || const bool.fromEnvironment('RIFLAY_MOVING_PREVIEWS');

  /// The Liquid glass tab bar draws its pills with Riflay's own blur instead of liquid_glass_renderer.
  static bool noGlassRenderer = _all || const bool.fromEnvironment('RIFLAY_NO_GLASS_RENDERER');

  /// Turning a phone sideways while Now Playing shows the music video doesn't open it full screen (the button and a
  /// double tap on the video still do). Not part of `RIFLAY_NO_SHORTCUTS`, which is about rendering.
  static bool noVideoRotate = const bool.fromEnvironment('RIFLAY_NO_VIDEO_ROTATE');

  /// Draw video through Flutter textures to compare native surface rendering.
  static bool noNativeVideo = _all || const bool.fromEnvironment('RIFLAY_NO_NATIVE_VIDEO');

  /// [MarqueeText] scrolls forever and everywhere, as before: card titles without a hover, and past its loops.
  static bool endlessMarquee = _all || const bool.fromEnvironment('RIFLAY_ENDLESS_MARQUEE');

  /// The signal path on screen is read from mpv every second while paused too, as it was.
  static bool signalPathWhilePaused = _all || const bool.fromEnvironment('RIFLAY_SIGNAL_PATH_WHILE_PAUSED');

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

  /// Prints how many widgets each palette change rebuilds, and every Material theme built.
  static bool logRestyles = const bool.fromEnvironment('RIFLAY_LOG_RESTYLES');

  /// Writes [message] when [logRestyles] is on.
  static void log(String Function() message) {
    if (logRestyles) debugPrint('[restyle] ${message()}');
  }
}
