import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/appearance.dart';
import '../../services/color_tools.dart';
import '../../services/system_fonts.dart';
import '../theme.dart';
import '../widgets/color_picker.dart';
import '../widgets/menus.dart';
import 'listen_together_page.dart' show BetaBadge;
import 'sound_settings.dart';

/// Settings › Appearance: theme (including Dynamic, which follows the playing
/// song's cover), light / dark mode, accent, cover-art colours and their
/// strength, high contrast, text size, font, frosted glass and window opacity.
class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final look = Appearance.instance;
    final muted = settingsMuted(context);
    return ListenableBuilder(
      listenable: look,
      builder: (context, _) => SettingsCard(
        children: [
          ListTile(leading: const Icon(Icons.dark_mode_outlined), title: const Text('Theme')),
          // The whole width, not under the tile's icon: two or more cards a row even on a phone.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: LayoutBuilder(
              builder: (context, c) {
                const gap = 10.0;
                final columns = ((c.maxWidth + gap) / (_ThemeCard.minWidth + gap)).floor().clamp(2, 8);
                final width = ((c.maxWidth - gap * (columns - 1)) / columns).floorToDouble();
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final t in ThemeChoice.values) _ThemeCard(choice: t, selected: look.theme == t, width: width),
                  ],
                );
              },
            ),
          ),
          if (look.theme == ThemeChoice.dynamic)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Colours come from the cover of what\'s playing', style: muted),
            ),
          if (look.theme == ThemeChoice.custom) ...[
            ListTile(
              leading: const Icon(Icons.format_color_fill_rounded),
              title: const Text('Background colour'),
              subtitle: Text('Panels, cards and menus are worked out from it', style: muted),
              trailing: _ColorButton(
                color: look.customBackground,
                label: 'Background colour',
                onTap: () async {
                  final c = await showColorPicker(context, title: 'Background colour', initial: look.customBackground);
                  if (c != null) look.setCustomBackground(c);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.text_fields_rounded),
              title: const Text('Text colour'),
              subtitle: Text(
                look.customText == null
                    ? 'Chosen to suit the background'
                    : 'Lightened or darkened where it would be hard to read',
                style: muted,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (look.customText != null)
                    TextButton(onPressed: () => look.setCustomText(null), child: const Text('Automatic')),
                  _ColorButton(
                    color: look.palette.textPrimary,
                    label: 'Text colour',
                    onTap: () async {
                      final c = await showColorPicker(context, title: 'Text colour', initial: look.palette.textPrimary);
                      if (c != null) look.setCustomText(c);
                    },
                  ),
                ],
              ),
            ),
          ],
          if (look.theme != ThemeChoice.custom)
            SettingTile(
              icon: Icons.brightness_6_outlined,
              title: const Text('Mode'),
              subtitle: Text('Light or dark, for every theme', style: muted),
              control: OptionPicker<ThemeBrightness>(
                value: look.brightness,
                onChanged: look.setBrightness,
                options: [for (final v in ThemeBrightness.values) (v, v.label)],
              ),
            ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Accent colour'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [for (final a in AccentChoice.values) _Swatch(choice: a, selected: look.accent == a)],
              ),
            ),
          ),
          if (look.theme != ThemeChoice.dynamic)
            SettingTile(
              icon: Icons.format_color_fill_rounded,
              title: const Text('Colours from cover art'),
              subtitle: Text(switch (look.coverMode) {
                CoverColorMode.off => 'Colours stay as the theme has them',
                CoverColorMode.player => 'Tint the player and pages with the colour of what\'s playing',
                CoverColorMode.app => 'The whole app takes the colour of what\'s playing',
              }, style: muted),
              control: OptionPicker<CoverColorMode>(
                value: look.coverMode,
                onChanged: look.setCoverMode,
                options: [for (final v in CoverColorMode.values) (v, v.label)],
              ),
            ),
          if (look.followsCover)
            _SliderTile(
              icon: Icons.opacity_rounded,
              title: 'Colour strength',
              subtitle: 'How much of the cover\'s colour shows in backgrounds and panels',
              value: look.coverStrength,
              min: 0,
              max: 1,
              label: (v) => v < 0.34 ? 'Subtle' : (v < 0.67 ? 'Medium' : 'Strong'),
              onChanged: look.setCoverStrength,
            ),
          SwitchListTile(
            secondary: const Icon(Icons.contrast_rounded),
            title: const Text('High contrast'),
            subtitle: Text('Brighter text and clearer edges, easier to read', style: muted),
            value: look.highContrast,
            onChanged: look.setHighContrast,
          ),
          SettingTile(
            icon: Icons.format_size_rounded,
            title: const Text('Text size'),
            subtitle: Text(
              'Body text, in pixels; titles and labels grow with it. ${Appearance.defaultTextSize.round()} px is the default',
              style: muted,
            ),
            control: _Stepper(
              value: look.textSize.round(),
              min: Appearance.minTextSize.round(),
              max: Appearance.maxTextSize.round(),
              unit: 'px',
              onChanged: (v) => look.setTextSize(v.toDouble()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.font_download_outlined),
            title: const Text('Font'),
            subtitle: Text(
              look.fontFamily ?? '${AppFont.ownName} (Riflay\'s own)',
              style: muted,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Open the fonts folder (put .ttf or .otf files here)',
                  onPressed: () async {
                    final dir = await SystemFonts.appFontsDir();
                    await dir.create(recursive: true);
                    await launchUrl(Uri.directory(dir.path));
                  },
                  icon: const Icon(Icons.folder_open_rounded),
                ),
                TextButton(onPressed: () => _pickFont(context), child: const Text('Change')),
              ],
            ),
          ),
          SettingTile(
            icon: Icons.wallpaper_rounded,
            title: const Text('Now playing background'),
            subtitle: Text('Behind the cover on the full player (phones)', style: muted),
            control: OptionPicker<NowPlayingBackground>(
              value: look.nowPlaying,
              onChanged: look.setNowPlaying,
              options: [for (final v in NowPlayingBackground.values) (v, v.label)],
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.blur_on_rounded),
            title: const Text('Frosted glass'),
            subtitle: Text('See-through, blurred mini player and tab bar. Uses a little more GPU', style: muted),
            value: look.glass,
            onChanged: look.setGlass,
          ),
          if (look.glass)
            _SliderTile(
              icon: Icons.lens_blur_rounded,
              title: 'Blur strength',
              value: look.blur,
              min: 4,
              max: 48,
              label: (v) => v.round().toString(),
              onChanged: look.setBlur,
            ),
          if (Appearance.hasWindowOpacity)
            _SliderTile(
              icon: Icons.opacity_rounded,
              title: 'Window opacity',
              subtitle: Platform.isAndroid ? 'Below 100% your wallpaper shows through' : 'Below 100% the desktop shows through, blurred where the system can (Windows 11, macOS, Hyprland, KDE)',
              value: look.windowOpacity,
              min: 0.5,
              max: 1,
              label: (v) => '${(v * 100).round()}%',
              onChanged: look.setWindowOpacity,
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextButton(onPressed: look.reset, child: const Text('Reset to default')),
            ),
          ),
        ],
      ),
    );
  }
}

/// The app's own typeface, the default.
abstract final class AppFont {
  static const ownName = 'Figtree';
}

Future<void> _pickFont(BuildContext context) async {
  final picked = await showDialog<(FontFamilyFiles?,)>(context: context, builder: (_) => const _FontDialog());
  if (picked == null) return;
  final ok = await Appearance.instance.setFont(picked.$1);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Couldn\'t load ${picked.$1?.family}.')));
  }
}

/// Every font family in the device's font folders, searchable; Riflay's own first.
class _FontDialog extends StatefulWidget {
  const _FontDialog();

  @override
  State<_FontDialog> createState() => _FontDialogState();
}

class _FontDialogState extends State<_FontDialog> {
  late final Future<List<FontFamilyFiles>> _fonts = SystemFonts.scan();
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = Appearance.instance.fontFamily;
    final muted = settingsMuted(context);
    Widget row(String title, String subtitle, bool selected, VoidCallback onTap) => ListTile(
      dense: true,
      title: Text(title),
      subtitle: Text(subtitle, style: muted),
      trailing: selected ? Icon(Icons.check_rounded, color: AppColors.accent) : null,
      onTap: onTap,
    );
    return AlertDialog(
      title: const Text('Font'),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: 440,
        height: 460,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                controller: _query,
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Search fonts on this device',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<FontFamilyFiles>>(
                future: _fonts,
                builder: (context, snap) {
                  final q = _query.text.trim().toLowerCase();
                  final fonts = [
                    for (final f in snap.data ?? const <FontFamilyFiles>[])
                      if (q.isEmpty || f.family.toLowerCase().contains(q)) f,
                  ];
                  return ListView(
                    children: [
                      if (q.isEmpty || AppFont.ownName.toLowerCase().contains(q))
                        row(
                          AppFont.ownName,
                          'Riflay\'s own font',
                          current == null,
                          () => Navigator.pop(context, (null,)),
                        ),
                      if (snap.connectionState != ConnectionState.done)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else
                        for (final f in fonts)
                          row(
                            f.family,
                            f.files.length == 1 ? '1 file' : '${f.files.length} files (weights and styles)',
                            current == f.family,
                            () => Navigator.pop(context, (f,)),
                          ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}

/// A theme, previewed in its own colours: a panel with a card, two lines of text and its accent.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.choice, required this.selected, required this.width});

  final ThemeChoice choice;
  final bool selected;
  final double width;

  /// Narrowest a card gets; the grid fits as many as this allows, at least two.
  static const minWidth = 132.0;

  @override
  Widget build(BuildContext context) {
    final p = Appearance.instance.paletteOf(choice);
    final dynamicTheme = choice == ThemeChoice.dynamic;
    final text = Theme.of(context).textTheme;
    Widget line(double width, Color color) => Container(
      width: width,
      height: 6,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: dynamicTheme ? 'Dynamic theme, follows the song that is playing' : '${choice.label} theme',
      child: InkWell(
        onTap: () => Appearance.instance.setTheme(choice),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: width,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? AppColors.accent : AppColors.border, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 64,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: p.background, borderRadius: BorderRadius.circular(8)),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: p.panel, borderRadius: BorderRadius.circular(6)),
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(color: p.elevated, borderRadius: BorderRadius.circular(4)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [line(40, p.textPrimary), const SizedBox(height: 4), line(26, p.textMuted)],
                        ),
                      ),
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        choice.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelMedium?.copyWith(
                          color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (dynamicTheme) ...[const SizedBox(width: 4), const BetaBadge()],
                    if (selected) Icon(Icons.check_circle_rounded, size: 16, color: AppColors.accent),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.choice, required this.selected});

  final AccentChoice choice;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    // "Theme" shows the current theme's own accent.
    final look = Appearance.instance;
    final palette = look.basePalette;
    final color = switch (choice) {
      AccentChoice.theme => palette.accent,
      AccentChoice.custom => look.customAccent,
      _ => choice.color,
    };
    final onColor = switch (choice) {
      AccentChoice.theme => palette.onAccent,
      AccentChoice.custom => onColorFor(look.customAccent),
      _ => choice.onColor,
    };
    return _swatch(context, color, onColor);
  }

  Widget _swatch(BuildContext context, Color color, Color onColor) => Tooltip(
    message: choice.label,
    child: Semantics(
      button: true,
      selected: selected,
      label: '${choice.label} accent',
      child: InkResponse(
        onTap: () async {
          if (choice != AccentChoice.custom) return Appearance.instance.setAccent(choice);
          final c = await showColorPicker(context, title: 'Accent colour', initial: Appearance.instance.customAccent);
          if (c != null) Appearance.instance.setCustomAccent(c);
        },
        radius: 22,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: selected ? AppColors.textPrimary : Colors.transparent, width: 2),
          ),
          child: selected
              ? Icon(Icons.check_rounded, size: 18, color: onColor)
              : choice == AccentChoice.theme
              ? Icon(Icons.auto_awesome_rounded, size: 14, color: onColor)
              : choice == AccentChoice.custom
              ? Icon(Icons.colorize_rounded, size: 16, color: onColor)
              : null,
        ),
      ),
    ),
  );
}

/// A round colour chip that opens the picker.
class _ColorButton extends StatelessWidget {
  const _ColorButton({required this.color, required this.label, required this.onTap});

  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: InkResponse(
      onTap: onTap,
      radius: 22,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.textSecondary, width: 2),
        ),
      ),
    ),
  );
}

/// − value + : one step per press, disabled at either end.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final String unit;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final style = IconButton.styleFrom(
      backgroundColor: AppColors.tile,
      fixedSize: const Size(32, 32),
      minimumSize: const Size(32, 32),
      padding: EdgeInsets.zero,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Smaller',
          style: style,
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_rounded, size: 18),
        ),
        SizedBox(
          width: 56,
          child: Text(
            '$value $unit',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          tooltip: 'Larger',
          style: style,
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_rounded, size: 18),
        ),
      ],
    );
  }
}

/// A slider that previews while dragging and saves when let go, so a drag
/// doesn't restyle the whole app on every frame.
class _SliderTile extends StatefulWidget {
  const _SliderTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final double value;
  final double min;
  final double max;
  final String Function(double) label;
  final ValueChanged<double> onChanged;

  @override
  State<_SliderTile> createState() => _SliderTileState();
}

class _SliderTileState extends State<_SliderTile> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final v = _dragging ?? widget.value;
    final muted = settingsMuted(context);
    return ListTile(
      leading: Icon(widget.icon),
      title: Row(
        children: [
          Expanded(child: Text(widget.title)),
          Text(widget.label(v), style: muted),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.subtitle != null) Text(widget.subtitle!, style: muted),
          Slider(
            value: v,
            min: widget.min,
            max: widget.max,
            onChanged: (x) => setState(() => _dragging = x),
            onChangeEnd: (x) {
              setState(() => _dragging = null);
              widget.onChanged(x);
            },
          ),
        ],
      ),
    );
  }
}
