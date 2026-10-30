import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart' show HSLColor;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'beta_features.dart';
import 'color_tools.dart';
import 'cover_palette.dart';
import 'layout_prefs.dart';
import 'system_fonts.dart';

/// Every colour of one theme: surfaces from the window down to hover, text, and the theme's own accent.
class AppPalette {
  const AppPalette({
    required this.background,
    required this.panel,
    required this.elevated,
    required this.hover,
    required this.menu,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.onAccent,
    this.light = false,
  });

  /// The window, behind the panels.
  final Color background;
  final Color panel;

  /// Cards and settings groups.
  final Color elevated;
  final Color hover;
  final Color menu;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color onAccent;

  /// Dark text on light surfaces.
  final bool light;

  @override
  bool operator ==(Object other) =>
      other is AppPalette &&
      other.background == background &&
      other.panel == panel &&
      other.elevated == elevated &&
      other.hover == hover &&
      other.menu == menu &&
      other.textPrimary == textPrimary &&
      other.textSecondary == textSecondary &&
      other.textMuted == textMuted &&
      other.accent == accent &&
      other.onAccent == onAccent &&
      other.light == light;

  @override
  int get hashCode => Object.hash(
    background,
    panel,
    elevated,
    hover,
    menu,
    textPrimary,
    textSecondary,
    textMuted,
    accent,
    onAccent,
    light,
  );

  /// A whole palette from one background colour, and optionally a text colour: panels, cards, hover and
  /// menus step away from the background, and the text greys are kept readable (4.5:1 on the lightest
  /// surface) on dark and light backgrounds alike.
  factory AppPalette.derive(Color background, {Color? text, Color? accent}) {
    const white = Color(0xFFFFFFFF), black = Color(0xFF000000);
    final light = text != null
        ? text.computeLuminance() < background.computeLuminance()
        : contrastRatio(black, background) > contrastRatio(white, background);
    Color mix(Color to, double t) => Color.lerp(background, to, t)!;
    final panel = light ? mix(white, 0.55) : mix(white, 0.04);
    final elevated = light ? mix(white, 0.3) : mix(white, 0.08);
    final hover = light ? mix(black, 0.06) : mix(white, 0.14);
    final menu = light ? mix(white, 0.4) : mix(white, 0.11);
    // The surface text has to read on: the one furthest from the text.
    final worst = hover;
    final primary = ensureContrast(text ?? (light ? mix(black, 0.88) : mix(white, 0.94)), worst, 4.5, !light);
    final secondary = ensureContrast(Color.lerp(primary, panel, 0.35)!, worst, 4.5, !light);
    final muted = ensureContrast(Color.lerp(primary, panel, 0.55)!, worst, 3, !light);
    final acc = ensureContrast(accent ?? (light ? const Color(0xFF0B7F6D) : const Color(0xFF2EE6C5)), panel, 4.5);
    return AppPalette(
      background: background,
      panel: panel,
      elevated: elevated,
      hover: hover,
      menu: menu,
      textPrimary: primary,
      textSecondary: secondary,
      textMuted: muted,
      accent: acc,
      onAccent: onColorFor(acc),
      light: light,
    );
  }

  /// Colour by colour from [a] to [b] ([t] 0 to 1). Text is not re-checked: see [withReadableText].
  static AppPalette lerp(AppPalette a, AppPalette b, double t) {
    if (t <= 0) return a;
    if (t >= 1) return b;
    Color mix(Color x, Color y) => Color.lerp(x, y, t)!;
    return AppPalette(
      background: mix(a.background, b.background),
      panel: mix(a.panel, b.panel),
      elevated: mix(a.elevated, b.elevated),
      hover: mix(a.hover, b.hover),
      menu: mix(a.menu, b.menu),
      textPrimary: mix(a.textPrimary, b.textPrimary),
      textSecondary: mix(a.textSecondary, b.textSecondary),
      textMuted: mix(a.textMuted, b.textMuted),
      accent: mix(a.accent, b.accent),
      onAccent: mix(a.onAccent, b.onAccent),
      light: t < 0.5 ? a.light : b.light,
    );
  }

  /// This palette with text moved just far enough to read on every surface: primary and secondary at
  /// [text]:1, muted at [muted]:1, and the accent at [accent]:1; [onAccent] follows the accent.
  AppPalette withReadableText({double text = 4.5, double muted = 3, double accent = 4.5}) {
    // The surface text reads worst on: the lightest on dark themes, the darkest on light ones.
    final surfaces = [background, panel, elevated, hover, menu]
      ..sort((a, b) => a.computeLuminance().compareTo(b.computeLuminance()));
    final worst = light ? surfaces.first : surfaces.last;
    Color fix(Color c, double min) => ensureContrast(c, worst, min, !light);
    final acc = fix(this.accent, accent);
    var on = acc == this.accent ? onAccent : onColorFor(acc);
    if (contrastRatio(on, acc) < 4.5) {
      const white = Color(0xFFFFFFFF), black = Color(0xFF000000);
      on = contrastRatio(black, acc) >= contrastRatio(white, acc) ? black : white;
    }
    return AppPalette(
      background: background,
      panel: panel,
      elevated: elevated,
      hover: hover,
      menu: menu,
      textPrimary: fix(textPrimary, text),
      textSecondary: fix(textSecondary, text),
      textMuted: fix(textMuted, muted),
      accent: acc,
      onAccent: on,
      light: light,
    );
  }

  /// This palette for "High contrast": primary and secondary text at 7:1, muted text and the accent at 4.5:1.
  AppPalette withHighContrast() => withReadableText(text: 7, muted: 4.5, accent: 4.5);

  /// This palette washed with [cover] ([amount] 0 to 1 of the full wash), for "Colours from what's playing:
  /// Whole app". Surfaces move toward the cover's hue, the accent becomes the cover's colour, and text is
  /// nudged to stay readable (4.5:1, or what the theme itself had when that was lower).
  AppPalette tinted(Color cover, double amount, [double? accentAmount]) {
    if (amount <= 0) return this;
    final hsl = HSLColor.fromColor(cover);
    // On light themes the wash is a pale version of the cover, so surfaces stay light.
    final wash = light ? hsl.withLightness(0.78).toColor() : cover;
    final u = amount;
    final k = light ? 1.3 : 1.0;
    Color mix(Color base, double f) => Color.lerp(base, wash, (f * k * u).clamp(0.0, 0.5))!;
    final bg = mix(background, 0.12);
    final pn = mix(panel, 0.18);
    final el = mix(elevated, 0.24);
    final ho = mix(hover, 0.3);
    final mn = mix(menu, 0.22);
    // Text has to read on every surface: check the one furthest from it (the lightest on dark themes).
    final surfaces = [bg, pn, el, ho, mn];
    surfaces.sort((a, b) => a.computeLuminance().compareTo(b.computeLuminance()));
    final worst = light ? surfaces.first : surfaces.last;
    final baseSurfaces = [background, panel, elevated, hover, menu]
      ..sort((a, b) => a.computeLuminance().compareTo(b.computeLuminance()));
    final baseWorst = light ? baseSurfaces.first : baseSurfaces.last;
    Color text(Color base) {
      final had = contrastRatio(base, baseWorst);
      return ensureContrast(base, worst, had < 4.5 ? had : 4.5, !light);
    }

    // A grey cover keeps the theme's own accent: a grey accent would be a step backwards.
    final colourful = hsl.saturation >= 0.1;
    final lifted = colourful ? ensureContrast(cover, worst, 4.5, !light) : accent;
    final acc = Color.lerp(accent, lifted, (accentAmount ?? u).clamp(0.0, 1.0))!;
    return AppPalette(
      background: bg,
      panel: pn,
      elevated: el,
      hover: ho,
      menu: mn,
      textPrimary: text(textPrimary),
      textSecondary: text(textSecondary),
      textMuted: text(textMuted),
      accent: acc,
      onAccent: onColorFor(acc),
      light: light,
    );
  }
}

/// The colour schemes in Settings › Look & feel › Appearance, from their authors' palettes.
enum ThemeChoice {
  standard(
    'Default',
    AppPalette(
      background: Color(0xFF000000),
      panel: Color(0xFF121212),
      elevated: Color(0xFF1C1C1C),
      hover: Color(0xFF2A2A2A),
      menu: Color(0xFF242424),
      textPrimary: Color(0xFFFFFFFF),
      textSecondary: Color(0xFFA7A7A7),
      textMuted: Color(0xFF6E6E6E),
      accent: Color(0xFF2EE6C5),
      onAccent: Color(0xFF00201B),
    ),
  ),

  /// Follows the playing song's cover; this is only the calm stand-in for when nothing plays.
  dynamic('Dynamic', neutralDarkPalette),
  monochrome(
    'Monochrome',
    AppPalette(
      background: Color(0xFF000000),
      panel: Color(0xFF0E0E0E),
      elevated: Color(0xFF191919),
      hover: Color(0xFF262626),
      menu: Color(0xFF1F1F1F),
      textPrimary: Color(0xFFF2F2F2),
      textSecondary: Color(0xFF9E9E9E),
      textMuted: Color(0xFF616161),
      accent: Color(0xFFF2F2F2),
      onAccent: Color(0xFF000000),
    ),
  ),
  catppuccinMocha(
    'Catppuccin Mocha',
    AppPalette(
      background: Color(0xFF11111B), // crust
      panel: Color(0xFF1E1E2E), // base
      elevated: Color(0xFF313244), // surface0
      hover: Color(0xFF45475A), // surface1
      menu: Color(0xFF181825), // mantle
      textPrimary: Color(0xFFCDD6F4), // text
      textSecondary: Color(0xFFA6ADC8), // subtext0
      textMuted: Color(0xFF7F849C), // overlay1
      accent: Color(0xFFCBA6F7), // mauve
      onAccent: Color(0xFF11111B),
    ),
  ),
  catppuccinMacchiato(
    'Catppuccin Macchiato',
    AppPalette(
      background: Color(0xFF181926), // crust
      panel: Color(0xFF24273A), // base
      elevated: Color(0xFF363A4F), // surface0
      hover: Color(0xFF494D64), // surface1
      menu: Color(0xFF1E2030), // mantle
      textPrimary: Color(0xFFCAD3F5), // text
      textSecondary: Color(0xFFA5ADCB), // subtext0
      textMuted: Color(0xFF8087A2), // overlay1
      accent: Color(0xFFC6A0F6), // mauve
      onAccent: Color(0xFF181926),
    ),
  ),
  catppuccinFrappe(
    'Catppuccin Frappé',
    AppPalette(
      background: Color(0xFF232634), // crust
      panel: Color(0xFF303446), // base
      elevated: Color(0xFF414559), // surface0
      hover: Color(0xFF51576D), // surface1
      menu: Color(0xFF292C3C), // mantle
      textPrimary: Color(0xFFC6D0F5), // text
      textSecondary: Color(0xFFA5ADCE), // subtext0
      textMuted: Color(0xFF838BA7), // overlay1
      accent: Color(0xFFCA9EE6), // mauve
      onAccent: Color(0xFF232634),
    ),
  ),
  catppuccinLatte(
    'Catppuccin Latte',
    AppPalette(
      background: Color(0xFFDCE0E8), // crust
      panel: Color(0xFFEFF1F5), // base
      elevated: Color(0xFFE6E9EF), // mantle
      hover: Color(0xFFCCD0DA), // surface0
      menu: Color(0xFFE6E9EF),
      textPrimary: Color(0xFF4C4F69), // text
      textSecondary: Color(0xFF6C6F85), // subtext0
      textMuted: Color(0xFF8C8FA1), // overlay1
      accent: Color(0xFF8839EF), // mauve
      onAccent: Color(0xFFEFF1F5),
      light: true,
    ),
  ),
  everblush(
    'Everblush',
    AppPalette(
      background: Color(0xFF0F1517),
      panel: Color(0xFF141B1E), // background
      elevated: Color(0xFF1E2528),
      hover: Color(0xFF2D3437), // color8
      menu: Color(0xFF232A2D), // color0
      textPrimary: Color(0xFFDADADA), // foreground
      textSecondary: Color(0xFFB3B9B8), // color7
      textMuted: Color(0xFF6B7275),
      accent: Color(0xFF8CCF7E), // green
      onAccent: Color(0xFF141B1E),
    ),
  ),
  everforestDark(
    'Everforest Dark',
    AppPalette(
      background: Color(0xFF232A2E), // bg_dim
      panel: Color(0xFF2D353B), // bg0
      elevated: Color(0xFF343F44), // bg1
      hover: Color(0xFF475258), // bg3
      menu: Color(0xFF3D484D), // bg2
      textPrimary: Color(0xFFD3C6AA), // fg
      textSecondary: Color(0xFF9DA9A0), // grey2
      textMuted: Color(0xFF7A8478), // grey0
      accent: Color(0xFFA7C080), // green
      onAccent: Color(0xFF2D353B),
    ),
  ),
  everforestLight(
    'Everforest Light',
    AppPalette(
      background: Color(0xFFEFEBD4), // bg_dim
      panel: Color(0xFFFDF6E3), // bg0
      elevated: Color(0xFFF4F0D9), // bg1
      hover: Color(0xFFE6E2CC), // bg3
      menu: Color(0xFFF4F0D9),
      textPrimary: Color(0xFF5C6A72), // fg
      textSecondary: Color(0xFF829181), // grey2
      textMuted: Color(0xFFA6B0A0), // grey0
      accent: Color(0xFF8DA101), // green
      onAccent: Color(0xFFFDF6E3),
      light: true,
    ),
  ),
  nord(
    'Nord',
    AppPalette(
      background: Color(0xFF242933),
      panel: Color(0xFF2E3440), // nord0
      elevated: Color(0xFF3B4252), // nord1
      hover: Color(0xFF4C566A), // nord3
      menu: Color(0xFF434C5E), // nord2
      textPrimary: Color(0xFFECEFF4), // nord6
      textSecondary: Color(0xFFD8DEE9), // nord4
      textMuted: Color(0xFF8790A3),
      accent: Color(0xFF88C0D0), // nord8
      onAccent: Color(0xFF2E3440),
    ),
  ),
  gruvbox(
    'Gruvbox',
    AppPalette(
      background: Color(0xFF1D2021), // bg0_h
      panel: Color(0xFF282828), // bg0
      elevated: Color(0xFF32302F), // bg0_s
      hover: Color(0xFF504945), // bg2
      menu: Color(0xFF3C3836), // bg1
      textPrimary: Color(0xFFEBDBB2), // fg
      textSecondary: Color(0xFFBDAE93), // fg3
      textMuted: Color(0xFF928374), // gray
      accent: Color(0xFFFE8019), // orange
      onAccent: Color(0xFF282828),
    ),
  ),
  tokyoNight(
    'Tokyo Night',
    AppPalette(
      background: Color(0xFF16161E),
      panel: Color(0xFF1A1B26), // bg
      elevated: Color(0xFF24283B), // bg_highlight
      hover: Color(0xFF292E42),
      menu: Color(0xFF1F2335),
      textPrimary: Color(0xFFC0CAF5), // fg
      textSecondary: Color(0xFFA9B1D6), // fg_dark
      textMuted: Color(0xFF565F89), // comment
      accent: Color(0xFF7AA2F7), // blue
      onAccent: Color(0xFF16161E),
    ),
  ),
  dracula(
    'Dracula',
    AppPalette(
      background: Color(0xFF191A21),
      panel: Color(0xFF282A36), // background
      elevated: Color(0xFF343746),
      hover: Color(0xFF44475A), // current line
      menu: Color(0xFF21222C),
      textPrimary: Color(0xFFF8F8F2), // foreground
      textSecondary: Color(0xFFBFC2D3),
      textMuted: Color(0xFF6272A4), // comment
      accent: Color(0xFFBD93F9), // purple
      onAccent: Color(0xFF282A36),
    ),
  ),
  rosePine(
    'Rosé Pine',
    AppPalette(
      background: Color(0xFF12101A),
      panel: Color(0xFF191724), // base
      elevated: Color(0xFF1F1D2E), // surface
      hover: Color(0xFF26233A), // overlay
      menu: Color(0xFF1F1D2E),
      textPrimary: Color(0xFFE0DEF4), // text
      textSecondary: Color(0xFF908CAA), // subtle
      textMuted: Color(0xFF6E6A86), // muted
      accent: Color(0xFFEBBCBA), // rose
      onAccent: Color(0xFF191724),
    ),
  ),

  /// Your own: a background colour (and optionally a text colour); [Appearance.palette] derives the rest.
  custom(
    'Custom',
    AppPalette(
      background: Color(0xFF14161B),
      panel: Color(0xFF1A1D23),
      elevated: Color(0xFF21242B),
      hover: Color(0xFF2B2F37),
      menu: Color(0xFF262A31),
      textPrimary: Color(0xFFEFF0F2),
      textSecondary: Color(0xFFA9ACB3),
      textMuted: Color(0xFF7C8089),
      accent: Color(0xFF2EE6C5),
      onAccent: Color(0xFF00201B),
    ),
  );

  const ThemeChoice(this.label, this.palette);
  final String label;

  /// The theme as its author drew it (dark or light as that theme naturally is).
  final AppPalette palette;

  /// This theme in the requested brightness: its own sibling or official counterpart where one exists
  /// (Catppuccin Latte, Everforest, Gruvbox Light, Rosé Pine Dawn, Tokyo Night Day), otherwise a palette
  /// derived from its hue that keeps its accent. [custom] is never flipped: it keeps its own background.
  AppPalette paletteIn({required bool light}) {
    if (palette.light == light || this == custom) return palette;
    final sibling = switch (this) {
      catppuccinMocha || catppuccinMacchiato || catppuccinFrappe => catppuccinLatte.palette,
      catppuccinLatte => catppuccinMocha.palette,
      everforestDark => everforestLight.palette,
      everforestLight => everforestDark.palette,
      standard => _defaultLight,
      gruvbox => _gruvboxLight,
      rosePine => _rosePineDawn,
      tokyoNight => _tokyoNightDay,
      _ => null,
    };
    if (sibling != null) return sibling;
    final hsl = HSLColor.fromColor(palette.panel);
    final bg = hsl.withSaturation(hsl.saturation.clamp(0.0, 0.25)).withLightness(light ? 0.94 : 0.1).toColor();
    return AppPalette.derive(bg, accent: palette.accent);
  }
}

const _defaultLight = AppPalette(
  background: Color(0xFFF1F1F1),
  panel: Color(0xFFFFFFFF),
  elevated: Color(0xFFF5F5F5),
  hover: Color(0xFFE6E6E6),
  menu: Color(0xFFFFFFFF),
  textPrimary: Color(0xFF121212),
  textSecondary: Color(0xFF4F4F4F),
  textMuted: Color(0xFF6B6B6B),
  accent: Color(0xFF0B7F6D),
  onAccent: Color(0xFFFFFFFF),
  light: true,
);

// Official light counterparts, each with its text moved to read (see [AppPalette.withReadableText]).
final _gruvboxLight = const AppPalette(
  background: Color(0xFFF9F5D7), // bg0_h
  panel: Color(0xFFFBF1C7), // bg0
  elevated: Color(0xFFF2E5BC), // bg0_s
  hover: Color(0xFFD5C4A1), // bg2
  menu: Color(0xFFEBDBB2), // bg1
  textPrimary: Color(0xFF3C3836), // fg
  textSecondary: Color(0xFF665C54), // fg3
  textMuted: Color(0xFF7C6F64), // fg4
  accent: Color(0xFFAF3A03), // orange
  onAccent: Color(0xFFFBF1C7),
  light: true,
).withReadableText();

final _rosePineDawn = const AppPalette(
  background: Color(0xFFF2E9E1), // overlay
  panel: Color(0xFFFAF4ED), // base
  elevated: Color(0xFFFFFAF3), // surface
  hover: Color(0xFFDFDAD9), // highlight med
  menu: Color(0xFFFFFAF3),
  textPrimary: Color(0xFF575279), // text
  textSecondary: Color(0xFF797593), // subtle
  textMuted: Color(0xFF9893A5), // muted
  accent: Color(0xFFD7827E), // rose
  onAccent: Color(0xFFFAF4ED),
  light: true,
).withReadableText();

final _tokyoNightDay = const AppPalette(
  background: Color(0xFFD0D5E3), // bg_dark
  panel: Color(0xFFE1E2E7), // bg
  elevated: Color(0xFFE9EAEF),
  hover: Color(0xFFC4C8DA), // bg_highlight
  menu: Color(0xFFE9EAEF),
  textPrimary: Color(0xFF3760BF), // fg
  textSecondary: Color(0xFF6172B0), // fg_dark
  textMuted: Color(0xFF848CB5), // comment
  accent: Color(0xFF2E7DE9), // blue
  onAccent: Color(0xFFE1E2E7),
  light: true,
).withReadableText();

/// Whether the app is drawn dark or light.
enum ThemeBrightness {
  dark('Dark'),
  light('Light'),
  system('Match system');

  const ThemeBrightness(this.label);
  final String label;
}

/// Accent colours to pick from in Settings › Look & feel › Appearance.
enum AccentChoice {
  /// The theme's own accent (mauve for Catppuccin, green for Everforest...).
  theme('Theme', Color(0x00000000), Color(0x00000000)),
  teal('Teal', Color(0xFF2EE6C5), Color(0xFF00201B)),
  green('Green', Color(0xFF1ED760), Color(0xFF00210B)),
  blue('Blue', Color(0xFF4C9AFF), Color(0xFF001B3D)),
  violet('Violet', Color(0xFFB18CFF), Color(0xFF1E0D45)),
  pink('Pink', Color(0xFFFF6FAE), Color(0xFF3D0020)),
  orange('Orange', Color(0xFFFF9F43), Color(0xFF3A1A00)),
  white('White', Color(0xFFFFFFFF), Color(0xFF000000)),

  /// A colour of your own ([Appearance.customAccent]).
  custom('Custom…', Color(0x00000000), Color(0x00000000));

  const AccentChoice(this.label, this.color, this.onColor);
  final String label;
  final Color color;
  final Color onColor;
}

/// Where the colour of the playing song's cover shows up.
enum CoverColorMode {
  off('Off'),
  player('Player only'),
  app('Whole app');

  const CoverColorMode(this.label);
  final String label;
}

/// What fills the phone's Now Playing page behind the cover.
enum NowPlayingBackground {
  color('Cover colour'),
  blurredCover('Blurred cover'),
  black('Black');

  const NowPlayingBackground(this.label);
  final String label;
}

/// Steps a 0 to 1 value over [time] on the frame clock, calling [onStep] about a dozen times (each one
/// restyles the whole app, so not every frame) and [onDone] when it arrives.
class _Fade {
  _Fade(this.time, {required this.onStep, this.onDone});

  final Duration time;
  final VoidCallback onStep;
  final VoidCallback? onDone;
  double t = 1;
  bool running = false;
  Duration? _start;
  int _last = -1;
  int _run = 0;

  /// [t] with easing.
  double get eased => Curves.easeInOut.transform(t);

  void start() {
    t = 0;
    _start = null;
    _last = -1;
    if (running) return;
    running = true;
    final run = ++_run;
    SchedulerBinding.instance.scheduleFrameCallback((now) => _frame(now, run));
  }

  /// Arrives straight away; no further steps.
  void stop() {
    _run++;
    running = false;
    t = 1;
  }

  void _frame(Duration now, int run) {
    if (run != _run) return;
    _start ??= now;
    t = ((now - _start!).inMicroseconds / time.inMicroseconds).clamp(0.0, 1.0);
    final step = (t * 12).floor();
    final done = t >= 1;
    if (done) {
      running = false;
      onDone?.call();
    }
    if (step != _last || done) {
      _last = step;
      onStep();
    }
    if (!done) SchedulerBinding.instance.scheduleFrameCallback((now) => _frame(now, run));
  }
}

/// How the app looks: accent, cover colours, frosted glass, window
/// transparency and text size. One instance for the whole app ([instance]),
/// loaded before the first frame so nothing flashes.
class Appearance extends ChangeNotifier {
  Appearance._();

  static final instance = Appearance._();

  static const _key = 'appearance.v1';

  ThemeChoice theme = ThemeChoice.standard;

  AccentChoice accent = AccentChoice.theme;

  /// The accent picked with "Custom…".
  Color customAccent = const Color(0xFF4C9AFF);

  /// The custom theme: a background colour, and a text colour (null: worked out from the background).
  Color customBackground = const Color(0xFF14161B);
  Color? customText;

  /// Dark, light, or whatever the system is set to. A custom theme keeps its own background colour in any
  /// of them: brightness does not flip a colour you chose.
  ThemeBrightness brightness = ThemeBrightness.dark;

  /// Whether the app is light right now ([brightness], with "Match system" resolved).
  bool get isLight => switch (brightness) {
    ThemeBrightness.dark => false,
    ThemeBrightness.light => true,
    ThemeBrightness.system => PlatformDispatcher.instance.platformBrightness == Brightness.light,
  };

  /// Call when the system switches between light and dark.
  void platformBrightnessChanged() {
    if (brightness != ThemeBrightness.system) return;
    _palette = null;
    notifyListeners();
  }

  /// Stronger text and accent colours (7:1 for the main text), and clearer borders.
  bool highContrast = false;

  /// The theme as picked, before any wash from the playing song.
  AppPalette get basePalette => paletteOf(theme);

  /// The palette a theme card previews: [t] in the brightness now in use. Dynamic shows the playing song's
  /// colours (a calm grey when nothing plays); custom is worked out from its colours.
  AppPalette paletteOf(ThemeChoice t) => switch (t) {
    ThemeChoice.custom => AppPalette.derive(customBackground, text: customText, accent: _pickedAccent),
    ThemeChoice.dynamic => t == theme ? _dynamicPalette() : _targetPalette(),
    _ => t.paletteIn(light: isLight),
  };

  // The Dynamic theme eases from the palette on screen to the one for the new song.
  CoverColors? _dynTarget;
  AppPalette? _dynFrom;
  late final _dynFade = _Fade(const Duration(milliseconds: 600), onStep: _fadeStep, onDone: () => _dynFrom = null);

  /// Whether a colour ease is under way, and how many steps it has taken (for [appThemeNow]).
  bool get fading => _dynFade.running || _washFade.running;
  int fadeStep = 0;

  void _fadeStep() {
    fadeStep++;
    final shown = _palette;
    _palette = null;
    // Every notification restyles the whole app: a step that lands on the colours already shown (two similar
    // covers, or the first and last steps of the ease) costs nothing. Except the last one: the theme may still be
    // a step or two behind (see appThemeNow), and catches up on it.
    if (shown != null && palette == shown && fading) {
      _palette = shown;
      return;
    }
    notifyListeners();
  }

  // The palette for the cover being faded to: worked out once, not at every step of the ease.
  CoverColors? _toCover;
  bool? _toLight;
  double? _toStrength;
  AppPalette? _toPalette;

  AppPalette _targetPalette() {
    final light = isLight;
    if (_toPalette == null || _toCover != _dynTarget || _toLight != light || _toStrength != coverStrength) {
      _toCover = _dynTarget;
      _toLight = light;
      _toStrength = coverStrength;
      _toPalette = paletteFromCover(_dynTarget, light: light, strength: coverStrength);
    }
    return _toPalette!;
  }

  AppPalette _dynamicPalette() {
    final to = _targetPalette();
    final from = _dynFrom;
    if (from == null || !_dynFade.running || from.light != to.light) return to;
    // Text is checked again at every step: halfway between two readable palettes may not be.
    return AppPalette.lerp(from, to, _dynFade.eased).withReadableText();
  }

  /// The colours of the song now playing (null: nothing plays, or it has no artwork). With the Dynamic
  /// theme the palette eases to them over about 600 ms, in a dozen steps; with reduced motion it jumps.
  void setCoverColors(CoverColors? c) {
    if (c == _dynTarget) return;
    if (theme != ThemeChoice.dynamic) {
      _dynTarget = c;
      return;
    }
    final shown = _dynamicPalette();
    _dynTarget = c;
    if (LayoutPrefs.effectiveMotion != Motion.full) {
      _dynFrom = null;
      _dynFade.stop();
      _palette = null;
      notifyListeners();
      return;
    }
    _dynFrom = shown;
    _dynFade.start();
  }

  /// The colours the Dynamic theme is heading for.
  CoverColors? get coverColorsNow => _dynTarget;

  /// Whether the whole app follows the playing song: the Dynamic theme, or "Whole app" cover colours.
  bool get followsCover => theme == ThemeChoice.dynamic || coverMode == CoverColorMode.app;

  Color? get _pickedAccent => switch (accent) {
    AccentChoice.theme => null,
    AccentChoice.custom => customAccent,
    _ => accent.color,
  };

  AppPalette? _palette;

  /// Every colour in use: [basePalette], the accent picked, and in [CoverColorMode.app] the wash of the
  /// playing song's cover. Cached until something changes.
  AppPalette get palette => _palette ??= _buildPalette();

  AppPalette _buildPalette() {
    var p = basePalette;
    final picked = _pickedAccent;
    if (picked != null && theme != ThemeChoice.custom) {
      final on = accent == AccentChoice.custom ? onColorFor(picked) : accent.onColor;
      p = AppPalette(
        background: p.background,
        panel: p.panel,
        elevated: p.elevated,
        hover: p.hover,
        menu: p.menu,
        textPrimary: p.textPrimary,
        textSecondary: p.textSecondary,
        textMuted: p.textMuted,
        accent: picked,
        onAccent: on,
        light: p.light,
      );
    }
    final c = _washColor;
    // Dynamic already is the cover's colours: a wash on top would tint twice.
    if (theme != ThemeChoice.dynamic && coverMode == CoverColorMode.app && c != null) {
      p = p.tinted(c, _washAmount * (0.25 + 0.75 * coverStrength), _washAmount);
    }
    return highContrast ? p.withHighContrast() : p;
  }

  /// The accent in use: the theme's own, or the one picked.
  Color get accentColor => palette.accent;
  Color get onAccentColor => palette.onAccent;

  /// Where the colour of the playing song's cover shows up.
  CoverColorMode coverMode = CoverColorMode.player;

  /// How strongly "Whole app" tints (0 subtle, 1 strong).
  double coverStrength = 0.5;

  /// Whether the player and pages are tinted with the cover's colour.
  bool get coverColors => coverMode != CoverColorMode.off;

  // The wash of "Whole app" animates between songs: from -> to over [washTime], easing in and out.
  // A null colour is "no song / no colour", which fades the wash out.
  Color? _washFrom;
  Color? _washTo;
  Color? _lastTarget;
  static const washTime = Duration(milliseconds: 500);
  late final _washFade = _Fade(washTime, onStep: _fadeStep, onDone: () => _washFrom = null);

  /// The colour the wash is at right now, and how much of it applies (0 to 1).
  Color? get _washColor =>
      _washFrom != null && _washTo != null ? Color.lerp(_washFrom, _washTo, _washFade.eased) : (_washTo ?? _washFrom);
  double get _washAmount => _washFrom == null && _washTo == null
      ? 0
      : _washFrom == null
      ? _washFade.eased
      : _washTo == null
      ? 1 - _washFade.eased
      : 1;

  /// The cover colour of the song now playing, or null when nothing is (or it has no artwork). Fades to
  /// it over about half a second; the tree is only restyled in a dozen steps rather than every frame.
  void setCoverTint(Color? color) {
    if (color == _lastTarget) return;
    _lastTarget = color;
    if (coverMode != CoverColorMode.app) {
      // Not shown: just remember it, so switching on later doesn't fade from nothing.
      _washFrom = null;
      _washTo = color;
      _washFade.t = 1;
      return;
    }
    _washFrom = _washColor == null || _washAmount < 0.01 ? null : _washColor;
    _washTo = color;
    if (_washFrom == null && _washTo == null) return;
    _washFade.start();
  }

  NowPlayingBackground nowPlaying = NowPlayingBackground.color;

  /// Frosted, see-through player bar, mini player and tab bar.
  bool glass = false;

  /// Blur radius of the frosted panels.
  double blur = 24;

  /// How opaque the window's background is (1 = solid). Below 1 the desktop
  /// shows through, and a compositor that blurs windows (Hyprland, KDE) blurs it.
  double windowOpacity = 1;

  /// Body text size in pixels (Material's default is 14); everything else scales with it.
  double textSize = defaultTextSize;

  static const defaultTextSize = 14.0;
  static const minTextSize = 11.0;
  static const maxTextSize = 20.0;

  double get textScale => textSize / defaultTextSize;

  /// A font from the device's font folders ([SystemFonts]); null is Riflay's own (Figtree).
  String? fontFamily;
  List<String> _fontFiles = const [];

  /// Whether the window itself can be see-through. Linux (its window always has an alpha channel), and
  /// Windows, macOS and Android (their runners switch it on, see [applyWindow]). Not iOS: apps can't
  /// see the wallpaper there.
  static bool get hasWindowOpacity => Platform.isLinux || Platform.isWindows || Platform.isMacOS || Platform.isAndroid;

  static const _window = MethodChannel('riflay/window');
  bool? _seeThrough;

  /// Tells the runner whether the window should show what is behind it (opacity below 100%). Opaque
  /// windows are cheaper, so Windows, macOS and Android only turn it on then; on Android that restarts
  /// the screen once (the music and the app's state carry on). Linux needs nothing.
  Future<void> applyWindow() async {
    if (!hasWindowOpacity || Platform.isLinux) return;
    final on = windowOpacity < 1;
    if (on == _seeThrough) return;
    _seeThrough = on;
    try {
      await _window.invokeMethod('setSeeThrough', on);
    } catch (e) {
      debugPrint('See-through window not switched: $e');
    }
  }

  Future<void> load() async {
    try {
      await BetaFeatures.instance.load();
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      theme = ThemeChoice.values.asNameMap()[j['theme']] ?? theme;
      // Saves from before the mode existed: a light theme (Latte) stays light.
      brightness =
          ThemeBrightness.values.asNameMap()[j['brightness']] ??
          (theme.palette.light ? ThemeBrightness.light : ThemeBrightness.dark);
      highContrast = j['highContrast'] as bool? ?? false;
      accent = AccentChoice.values.asNameMap()[j['accent']] ?? accent;
      // Saved by older versions as on/off: on was "Player only".
      coverMode =
          CoverColorMode.values.asNameMap()[j['coverMode']] ??
          ((j['coverColors'] as bool? ?? true) ? CoverColorMode.player : CoverColorMode.off);
      coverStrength = (j['coverStrength'] as num?)?.toDouble().clamp(0, 1) ?? coverStrength;
      customAccent = Color(j['customAccent'] as int? ?? customAccent.toARGB32());
      customBackground = Color(j['customBackground'] as int? ?? customBackground.toARGB32());
      final text = j['customText'] as int?;
      customText = text == null ? null : Color(text);
      _palette = null;
      nowPlaying = NowPlayingBackground.values.asNameMap()[j['nowPlaying']] ?? nowPlaying;
      glass = j['glass'] as bool? ?? glass;
      blur = (j['blur'] as num?)?.toDouble().clamp(4, 48) ?? blur;
      windowOpacity = hasWindowOpacity ? (j['windowOpacity'] as num?)?.toDouble().clamp(0.5, 1) ?? 1 : 1;
      final size =
          (j['textSize'] as num?)?.toDouble() ??
          // Saved by older versions as a scale (0.9 "Small" ... 1.3 "Largest").
          ((j['textScale'] as num?)?.toDouble() ?? 1) * defaultTextSize;
      textSize = size.roundToDouble().clamp(minTextSize, maxTextSize);
      final family = j['fontFamily'] as String?;
      final files = (j['fontFiles'] as List?)?.cast<String>() ?? const [];
      // The saved files, not a rescan: fast, and a font that's gone falls back to the default.
      if (family != null && await SystemFonts.load(family, files)) {
        fontFamily = family;
        _fontFiles = files;
      }
    } catch (e) {
      debugPrint('Appearance settings unreadable, using defaults: $e');
    }
  }

  Future<void> _set(VoidCallback change) async {
    change();
    _palette = null;
    notifyListeners();
    unawaited(applyWindow());
    await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode({
        'theme': theme.name,
        'accent': accent.name,
        'brightness': brightness.name,
        'highContrast': highContrast,
        'coverColors': coverColors,
        'coverMode': coverMode.name,
        'coverStrength': coverStrength,
        'customAccent': customAccent.toARGB32(),
        'customBackground': customBackground.toARGB32(),
        'customText': customText?.toARGB32(),
        'nowPlaying': nowPlaying.name,
        'glass': glass,
        'blur': blur,
        'windowOpacity': windowOpacity,
        'textSize': textSize,
        'fontFamily': fontFamily,
        'fontFiles': _fontFiles,
      }),
    );
  }

  /// A new theme brings its own accent; another can be picked after.
  Future<void> setTheme(ThemeChoice v) => _set(() {
    theme = v;
    accent = AccentChoice.theme;
    // Unless following the system, a theme comes in its own brightness (Latte: light). Dynamic and custom
    // have none of their own, so they keep the one in use.
    if (brightness != ThemeBrightness.system && v != ThemeChoice.dynamic && v != ThemeChoice.custom) {
      brightness = v.palette.light ? ThemeBrightness.light : ThemeBrightness.dark;
    }
    _dynFrom = null;
    _dynFade.stop();
  });
  Future<void> setBrightness(ThemeBrightness v) => _set(() => brightness = v);
  Future<void> setHighContrast(bool v) => _set(() => highContrast = v);
  Future<void> setAccent(AccentChoice v) => _set(() => accent = v);
  Future<void> setCoverMode(CoverColorMode v) => _set(() {
    coverMode = v;
    // Switching "Whole app" on fades the playing song's colour in from the theme's own.
    final target = _lastTarget;
    _lastTarget = null;
    _washFrom = null;
    _washTo = null;
    _washFade.stop();
    setCoverTint(target);
  });
  Future<void> setCoverStrength(double v) => _set(() => coverStrength = v.clamp(0, 1));

  /// Picks a colour of your own as the accent.
  Future<void> setCustomAccent(Color v) => _set(() {
    customAccent = v;
    accent = AccentChoice.custom;
  });

  /// The custom theme's background; also switches to it.
  Future<void> setCustomBackground(Color v) => _set(() {
    customBackground = v;
    theme = ThemeChoice.custom;
  });

  /// The custom theme's text colour; null works it out from the background.
  Future<void> setCustomText(Color? v) => _set(() {
    customText = v;
    theme = ThemeChoice.custom;
  });

  /// Everything on this page back to how a fresh install looks.
  Future<void> reset() async {
    await setFont(null);
    await _set(() {
      theme = ThemeChoice.standard;
      accent = AccentChoice.theme;
      customAccent = const Color(0xFF4C9AFF);
      customBackground = const Color(0xFF14161B);
      customText = null;
      coverMode = CoverColorMode.player;
      coverStrength = 0.5;
      nowPlaying = NowPlayingBackground.color;
      glass = false;
      blur = 24;
      windowOpacity = 1;
      textSize = defaultTextSize;
      brightness = ThemeBrightness.dark;
      highContrast = false;
      _washFrom = null;
      _washTo = null;
      _washFade.stop();
      _dynFrom = null;
      _dynFade.stop();
    });
  }

  Future<void> setNowPlaying(NowPlayingBackground v) => _set(() => nowPlaying = v);
  Future<void> setGlass(bool v) => _set(() => glass = v);
  Future<void> setBlur(double v) => _set(() => blur = v);
  Future<void> setWindowOpacity(double v) => _set(() => windowOpacity = v);

  /// Draws the app in [font] (null: back to Riflay's own). False when its files couldn't be loaded.
  Future<bool> setFont(FontFamilyFiles? font) async {
    if (font != null && !await SystemFonts.load(font.family, font.files)) return false;
    await _set(() {
      fontFamily = font?.family;
      _fontFiles = font?.files ?? const [];
    });
    return true;
  }

  Future<void> setTextSize(double v) => _set(() => textSize = v.roundToDouble().clamp(minTextSize, maxTextSize));
}
