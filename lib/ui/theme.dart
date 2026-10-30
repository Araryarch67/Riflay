import 'dart:io';

import 'package:flutter/material.dart';

import '../services/appearance.dart';
import '../services/layout_prefs.dart';
import 'debug_switches.dart';

/// Colour tokens of the theme picked in Settings › Look & feel › Appearance ([ThemeChoice]).
abstract final class AppColors {
  static AppPalette get _p => _themeOverride ?? Appearance.instance.palette;

  /// Set while [buildAppTheme] runs for a palette that is not the one in use (see [appThemeNow]).
  static AppPalette? _themeOverride;

  /// The colours for a widget that should be rebuilt when they change (and only then).
  static AppColorsView of(BuildContext context) =>
      (context.dependOnInheritedWidgetOfExactType<AppColorsScope>()?.colors) ?? AppColorsScope.current();

  /// Whether the theme is light (dark text on light surfaces).
  static bool get light => _p.light;

  /// Window and panel backgrounds; see-through when the window opacity
  /// setting is below 100%.
  static Color get background => _p.background.withValues(alpha: Appearance.instance.windowOpacity);
  static Color get panel => _p.panel.withValues(alpha: Appearance.instance.windowOpacity);

  /// [background] and [panel] without the window's opacity.
  static Color get solidBackground => _p.background;
  static Color get elevated => _p.elevated;
  static Color get hover => _p.hover;

  /// Popup menus and pickers.
  static Color get menu => _p.menu;
  static Color get textPrimary => _p.textPrimary;
  static Color get textSecondary => _p.textSecondary;
  static Color get textMuted => _p.textMuted;

  /// A faint fill over any surface (search box, cards on hover).
  static Color get tile => _p.textPrimary.withValues(alpha: 0.08);

  /// Hairline borders and dividers.
  static Color get border => _p.textPrimary.withValues(alpha: Appearance.instance.highContrast ? 0.28 : 0.10);
  static Color get divider => _p.textPrimary.withValues(alpha: Appearance.instance.highContrast ? 0.18 : 0.06);

  /// The strongest contrast: a filled button or the phone's search box (white on dark themes).
  static Color get inverse => _p.textPrimary;
  static Color get onInverse => _p.light ? _p.panel : _p.background;

  static Color get accent => _p.accent;
  static Color get onAccent => _p.onAccent;

  /// A cover's colour as a page header wash: strong on dark themes, soft on light ones
  /// (where the text over it is dark).
  static double get washStrength => _p.light ? 0.4 : 1;

  /// [color] darkened toward the theme's background by [amount] (lightened on light themes).
  static Color sink(Color color, double amount) => Color.lerp(color, _p.background, _p.light ? 0.75 : amount)!;
}

/// The colours as one snapshot, read through a context ([AppColors.of]) so the widget rebuilds when they change
/// and only then. The static [AppColors] getters give the same values to code that has no context.
@immutable
class AppColorsView {
  const AppColorsView(this.palette, this.windowOpacity, this.highContrast);

  final AppPalette palette;
  final double windowOpacity;
  final bool highContrast;

  bool get light => palette.light;
  Color get background => palette.background.withValues(alpha: windowOpacity);
  Color get panel => palette.panel.withValues(alpha: windowOpacity);
  Color get solidBackground => palette.background;
  Color get elevated => palette.elevated;
  Color get hover => palette.hover;
  Color get menu => palette.menu;
  Color get textPrimary => palette.textPrimary;
  Color get textSecondary => palette.textSecondary;
  Color get textMuted => palette.textMuted;
  Color get tile => palette.textPrimary.withValues(alpha: 0.08);
  Color get border => palette.textPrimary.withValues(alpha: highContrast ? 0.28 : 0.10);
  Color get divider => palette.textPrimary.withValues(alpha: highContrast ? 0.18 : 0.06);
  Color get inverse => palette.textPrimary;
  Color get onInverse => palette.light ? palette.panel : palette.background;
  Color get accent => palette.accent;
  Color get onAccent => palette.onAccent;

  @override
  bool operator ==(Object other) =>
      other is AppColorsView &&
      other.palette == palette &&
      other.windowOpacity == windowOpacity &&
      other.highContrast == highContrast;

  @override
  int get hashCode => Object.hash(palette, windowOpacity, highContrast);
}

/// Hands [AppColorsView] down the tree. Widgets that read it through [AppColors.of] are rebuilt when the
/// colours change, nothing else is.
class AppColorsScope extends InheritedWidget {
  const AppColorsScope({super.key, required this.colors, required super.child});

  final AppColorsView colors;

  /// The colours now in use, from [Appearance].
  static AppColorsView current() {
    final a = Appearance.instance;
    return AppColorsView(a.palette, a.windowOpacity, a.highContrast);
  }

  @override
  bool updateShouldNotify(AppColorsScope old) => old.colors != colors;
}

/// Marks a widget that [restyleTree] has no use for. Implement [ColorFreeSubtree] on a widget whose whole subtree
/// shows no colour read statically (anything coloured inside follows [AppColors.of] or [Theme] instead), or
/// [ColorFreeSelf] on one whose own `build` reads none while its children may.
abstract interface class ColorFreeSubtree {}

abstract interface class ColorFreeSelf {}

/// Marks a subtree that reads no colour, neither through [AppColors] nor statically: a palette change skips it
/// (see [restyleTree]). Wrap pure artwork or lists of pictures.
class ColorFree extends StatelessWidget implements ColorFreeSubtree {
  const ColorFree({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Rebuilds what may read [AppColors] statically after a palette change. Only widgets that run a `build`
/// (stateless, stateful, builders) can have a colour in their output; render objects, inherited and proxy
/// widgets hold the same configuration and gain nothing from a rebuild, so they are left alone, as is
/// anything under a [ColorFree]. Widgets that read colours through a context are rebuilt by the framework.
/// Returns how many elements were marked.
int restyleTree(Element root) {
  var marked = 0;
  // Every skip below can be turned off at once, to find a widget that is skipped but shows a colour.
  final all = DebugSwitches.restyleAll;
  void visit(Element e, Type? parent, Type? grand) {
    final w = e.widget;
    if (!all && w is ColorFreeSubtree) return;
    final t = w.runtimeType;
    if ((e is StatelessElement || e is StatefulElement) && (all || w is! ColorFreeSelf && !_frameworkOnly(t))) {
      // The Builder inside every InkWell (Focus > Semantics > MouseRegion > Builder) runs no Riflay code.
      if (all || !(identical(t, Builder) && identical(parent, MouseRegion) && identical(grand, Semantics))) {
        e.markNeedsBuild();
        marked++;
      }
    }
    e.visitChildren((c) => visit(c, t, parent));
  }

  root.visitChildren((c) => visit(c, null, null));
  DebugSwitches.log(() => 'rebuilt $marked widgets${all ? ' (RIFLAY_RESTYLE_ALL)' : ''}');
  return marked;
}

/// Widgets of Flutter itself that take their colours from [Theme]/[DefaultTextStyle]/[IconTheme] (which the
/// framework updates by dependency) and run no Riflay code: a colour handed to them in a constructor comes
/// from a parent's `build`, and that parent is rebuilt. Rebuilding them again is the bulk of a whole-tree sweep.
const _frameworkWidgets = {
  'Material',
  'InkWell',
  'InkResponse',
  'Ink',
  'Text',
  'Icon',
  'IconButton',
  'Focus',
  'GestureDetector',
  'RawGestureDetector',
  'Actions',
  'DefaultTextStyle',
  'AnimatedDefaultTextStyle',
  'DefaultSelectionStyle',
  'IconTheme',
  'Theme',
  'AnimatedTheme',
  'CupertinoTheme',
  'Tooltip',
  'RawTooltip',
  'ListTile',
  'Scaffold',
  'AppBar',
  'TextButton',
  'FilledButton',
  'ElevatedButton',
  'OutlinedButton',
  'MouseRegion',
  'Semantics',
  'FocusTraversalGroup',
  'Scrollable',
  'Scrollbar',
  'Switch',
  'Slider',
  'Checkbox',
  'Radio',
  'TextField',
  'EditableText',
  'Container',
  'OverlayPortal',
  'AnimatedSwitcher',
  'KeyedSubtree',
  'SlideTransition',
  'ScaleTransition',
  'FadeTransition',
  'RotationTransition',
  'SizeTransition',
  'AnimatedPhysicalModel',
  'AutomaticKeepAlive',
  'TickerMode',
  'Shortcuts',
  'RestorationScope',
  'RawChip',
  'FilterChip',
  'Chip',
  'ActionChip',
  'ChoiceChip',
  'InputChip',
  'PopupMenuButton',
  'Card',
  'Divider',
  'Dialog',
  'AlertDialog',
  'SwitchListTile',
  'CheckboxListTile',
  'RadioListTile',
  'ExpansionTile',
  'CircleAvatar',
  'Image',
  'SelectionArea',
  'AnimatedContainer',
  'AnimatedScale',
  'AnimatedSlide',
  'AnimatedOpacity',
  'AnimatedPadding',
  'AnimatedAlign',
  'AnimatedSize',
  'Hero',
  'Visibility',
  'ListView',
  'GridView',
  'CustomScrollView',
  'SingleChildScrollView',
  'ScrollConfiguration',
  'Overlay',
  'Navigator',
  'SafeArea',
  'Title',
  '_InkResponseStateWidget',
  '_ParentInkResponseProvider',
  '_ShapeBorderPaint',
  '_MaterialInterior',
  '_SelectableIconButton',
  '_IconButtonM3',
  '_SelectionKeepAlive',
  '_OverlayEntryWidget',
  '_OutlinedButtonWithIconChild',
  '_FilledButtonWithIconChild',
  '_TextButtonWithIconChild',
  '_ElevatedButtonWithIconChild',
};
final _frameworkTypes = <Type, bool>{};
bool _frameworkOnly(Type t) => _frameworkTypes[t] ??= _frameworkWidgets.contains(t.toString().split('<').first);

/// What [buildAppTheme] was last asked for, so a repeat (a palette that comes back, a restyle that changed
/// nothing a theme reads) is answered without building [ThemeData] again.
@immutable
class _ThemeKey {
  const _ThemeKey(this.palette, this.opacity, this.highContrast, this.wholeApp, this.font, this.corners, this.motion);

  final AppPalette palette;
  final double opacity;
  final bool highContrast;
  final bool wholeApp;
  final String? font;
  final CornerStyle corners;
  final Motion motion;

  @override
  bool operator ==(Object other) =>
      other is _ThemeKey &&
      other.palette == palette &&
      other.opacity == opacity &&
      other.highContrast == highContrast &&
      other.wholeApp == wholeApp &&
      other.font == font &&
      other.corners == corners &&
      other.motion == motion;

  @override
  int get hashCode => Object.hash(palette, opacity, highContrast, wholeApp, font, corners, motion);
}

final _themes = <_ThemeKey, ThemeData>{};

/// How many themes were built and how many answered from the cache (for tests).
({int built, int cached}) get themeCacheStats => (built: _themesBuilt, cached: _themesCached);
int _themesBuilt = 0;
int _themesCached = 0;

/// The app's theme for the colours, font and layout settings now in use, built once per combination.
/// [desktopFrame]: the window paints the background, so pages are see-through.
ThemeData appThemeNow({bool desktopFrame = false}) {
  final a = Appearance.instance;
  final l = LayoutPrefs.instance;
  final palette = _themePalette(a);
  final key = _ThemeKey(
    palette,
    a.windowOpacity,
    a.highContrast,
    a.followsCover,
    a.fontFamily,
    l.corners,
    LayoutPrefs.effectiveMotion,
  );
  final hit = _themes.remove(key);
  if (hit != null) {
    _themes[key] = hit; // most recent last
    _themesCached++;
    return desktopFrame ? _transparent(hit) : hit;
  }
  _themesBuilt++;
  DebugSwitches.log(() => 'theme #$_themesBuilt built${a.fading ? ' at fade step ${a.fadeStep}' : ''}');
  AppColors._themeOverride = palette;
  final ThemeData built;
  try {
    built = l.themed(buildAppTheme(fontFamily: a.fontFamily));
  } finally {
    AppColors._themeOverride = null;
  }
  // A fade passes through a dozen colours it never returns to: keep a few.
  if (_themes.length >= 8) _themes.remove(_themes.keys.first);
  _themes[key] = built;
  return desktopFrame ? _transparent(built) : built;
}

// Changing the theme rebuilds everything that asks Theme.of (every ink well, button and tile), far more than the
// widgets that follow AppColors. While the Dynamic theme (or the "Whole app" wash) eases, the theme therefore
// moves every third step and the colours the app reads itself every step; text and Material surfaces differ by
// a few shades between two steps, so the ease looks the same.
AppPalette? _heldPalette;
int _heldStep = 0;
const _themeEvery = 3;

AppPalette _themePalette(Appearance a) {
  final now = a.palette;
  if (!a.fading || DebugSwitches.themeEveryStep) {
    _heldPalette = null;
    return now;
  }
  final held = _heldPalette;
  if (held == null || held.light != now.light || a.fadeStep - _heldStep >= _themeEvery) {
    _heldPalette = now;
    _heldStep = a.fadeStep;
    return now;
  }
  return held;
}

final _transparentOf = Expando<ThemeData>('transparent theme');
ThemeData _transparent(ThemeData t) => _transparentOf[t] ??= t.copyWith(scaffoldBackgroundColor: Colors.transparent);

bool get _desktop => Platform.isLinux || Platform.isWindows || Platform.isMacOS;

ThemeData buildAppTheme({String? fontFamily}) {
  final brightness = AppColors.light ? Brightness.light : Brightness.dark;
  final base = ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: brightness,
      primary: AppColors.accent,
      onPrimary: AppColors.onAccent,
      surface: AppColors.panel,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
    ),
    scaffoldBackgroundColor: AppColors.background,
    splashFactory: InkSparkle.splashFactory,
    // Riflay's own typeface is bundled (assets/fonts); a font picked in Settings comes from the device.
    fontFamily: fontFamily ?? 'Figtree',
  );
  final wholeApp = Appearance.instance.followsCover;
  final text = base.textTheme.apply(bodyColor: AppColors.textPrimary, displayColor: AppColors.textPrimary);
  return base.copyWith(
    textTheme: text,
    iconTheme: IconThemeData(color: AppColors.textSecondary),
    appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      // Whole-app cover colours: sliders take the cover's accent too.
      activeTrackColor: wholeApp ? AppColors.accent : AppColors.textPrimary,
      inactiveTrackColor: AppColors.textPrimary.withValues(alpha: 0.3),
      thumbColor: wholeApp ? AppColors.accent : AppColors.textPrimary,
      overlayColor: (wholeApp ? AppColors.accent : AppColors.textPrimary).withValues(alpha: 0.12),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6, elevation: 0),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      trackShape: const RoundedRectSliderTrackShape(),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.hover,
      selectedColor: AppColors.textPrimary,
      // Material 3 ignores secondaryLabelStyle: the selected (inverse) chip needs
      // its label from a state colour, or the text vanishes.
      labelStyle: text.labelLarge?.copyWith(
        color: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.onInverse : AppColors.textPrimary,
        ),
      ),
      side: BorderSide.none,
      shape: const StadiumBorder(),
      showCheckmark: false,
    ),
    // Menus: a dark rounded card with a hairline border (see widgets/menus.dart).
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.menu,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: Colors.black,
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    // A small card floating over the bottom of the page: centred and
    // narrow on desktop, inset from the edges on phones.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      width: _desktop ? 440 : null,
      insetPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      backgroundColor: AppColors.hover,
      elevation: 8,
      contentTextStyle: text.bodyMedium?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w500),
      actionTextColor: AppColors.accent,
      closeIconColor: AppColors.textSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: AppColors.hover, borderRadius: BorderRadius.circular(4)),
      textStyle: text.bodySmall,
    ),
    dividerTheme: DividerThemeData(color: AppColors.hover, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(iconColor: AppColors.textSecondary),
    dialogTheme: wholeApp
        ? DialogThemeData(backgroundColor: AppColors.menu, surfaceTintColor: Colors.transparent)
        : null,
    textSelectionTheme: wholeApp
        ? TextSelectionThemeData(
            cursorColor: AppColors.accent,
            selectionColor: AppColors.accent.withValues(alpha: 0.35),
            selectionHandleColor: AppColors.accent,
          )
        : null,
    progressIndicatorTheme: wholeApp ? ProgressIndicatorThemeData(color: AppColors.accent) : null,
  );
}
