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

  /// Prints how many widgets each palette change rebuilds, and every Material theme built.
  static bool logRestyles = const bool.fromEnvironment('RIFLAY_LOG_RESTYLES');

  /// Writes [message] when [logRestyles] is on.
  static void log(String Function() message) {
    if (logRestyles) debugPrint('[restyle] ${message()}');
  }
}
