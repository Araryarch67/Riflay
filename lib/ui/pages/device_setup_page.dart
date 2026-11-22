import 'package:flutter/material.dart';

import '../../platform/features.dart';
import '../../services/device_setup.dart';
import '../../services/player_presets.dart';
import '../../services/language.dart';
import '../../services/layout_prefs.dart';
import '../theme.dart';
import '../../services/player_controller.dart';
import '../playlist_import.dart';
import 'youtube_music_page.dart';
import '../widgets/title_bar.dart';
import 'player_presets_page.dart' show PresetSchematic;

/// Opens the setup page over the app: on the first start of a computer ([DeviceSetup.due]), and from Settings ›
/// Performance & power. The pick applies on Continue; "Keep my settings" leaves everything as it was.
Future<void> showDeviceSetup(BuildContext context) => Navigator.of(
  context,
  rootNavigator: true,
).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const DeviceSetupPage()));

/// What this computer is, and the three performance modes with what a playing song costs in each, the one
/// [DeviceSetup.recommend] gives picked to start with.
class DeviceSetupPage extends StatefulWidget {
  const DeviceSetupPage({super.key, this.specs});

  /// Read from the computer when null (tests pass their own).
  final Future<DeviceSpecs>? specs;

  @override
  State<DeviceSetupPage> createState() => _DeviceSetupPageState();
}

class _DeviceSetupPageState extends State<DeviceSetupPage> {
  late final Future<DeviceSpecs> _specs = widget.specs ?? DeviceSetup.read();
  PerformanceMode? _picked;
  bool _showPerformance = false;

  void _update(VoidCallback change) => setState(change);

  /// After the welcome: the look, then the performance mode.
  bool _showLook = false;

  /// What the look step picked (null: as it is). Applied with the rest on Continue, kept on "Keep my settings".
  DesktopLayout? _layout;
  PlayerPreset? _preset;

  Future<void> _finish(PerformanceMode? mode) async {
    if (mode != null) {
      if (_layout case final layout?) await LayoutPrefs.instance.applyDesktopLayout(layout);
      if (_preset case final preset? when !preset.matches(LayoutPrefs.instance)) {
        await preset.apply(LayoutPrefs.instance);
      }
      await LayoutPrefs.instance.setPerformance(mode);
    }
    await DeviceSetup.instance.done();
    if (mounted) Navigator.of(context).pop();
  }

  static String _percent(double v) => v < 0.1 ? '0.1' : v.toStringAsFixed(v < 1 ? 2 : 1);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: AppColors.textSecondary);
    final player = context.getInheritedWidgetOfExactType<PlayerScope>()?.notifier;
    final page = SafeArea(
      child: _showLook && !_showPerformance
          ? _look(context)
          : !_showPerformance && player != null
          ? Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(tr.setupWelcome, style: text.headlineMedium),
                      const SizedBox(height: 24),
                      Card.filled(
                        child: ListenableBuilder(
                          listenable: player.ytMusic,
                          builder: (context, _) => ListTile(
                            leading: const Icon(Icons.account_circle_outlined),
                            title: Text(player.ytMusic.isSignedIn ? 'YouTube Music' : tr.signInToYt),
                            subtitle: Text(player.ytMusic.isSignedIn ? tr.connected : tr.ytSignInPrompt),
                            trailing: Icon(player.ytMusic.isSignedIn ? Icons.check : Icons.chevron_right),
                            onTap: player.ytMusic.isSignedIn || player.ytMusic.connecting
                                ? null
                                : () => signInToYoutubeMusic(context, fullscreen: true),
                          ),
                        ),
                      ),
                      Card.filled(
                        child: ListTile(
                          leading: const Icon(Icons.playlist_add_rounded),
                          title: Text(tr.importPlaylist),
                          subtitle: Text(tr.setupImportHint),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => askToImportPlaylist(context, offerOpen: false),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: FilledButton.icon(
                          onPressed: () => setState(() => _showLook = true),
                          icon: const Icon(Icons.arrow_forward),
                          label: Text(tr.deviceSetupContinue),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : FutureBuilder<DeviceSpecs>(
              future: _specs,
              builder: (context, snap) {
                final specs = snap.data;
                if (specs == null) return const Center(child: CircularProgressIndicator());
                final recommended = DeviceSetup.recommend(specs);
                final picked = _picked ?? recommended;
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(tr.deviceSetupTitle, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 12),
                          Text(tr.deviceSetupIntro, style: muted),
                          const SizedBox(height: 24),
                          _Specs(specs),
                          const SizedBox(height: 24),
                          Text(tr.performance, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          for (final mode in PerformanceMode.values)
                            _ModeTile(
                              mode: mode,
                              cost: _percent(DeviceSetup.share(mode, specs)),
                              recommended: mode == recommended,
                              selected: mode == picked,
                              onTap: () => setState(() => _picked = mode),
                            ),
                          const SizedBox(height: 24),
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TextButton(onPressed: () => _finish(null), child: Text(tr.deviceSetupKeep)),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.inverse,
                                  foregroundColor: AppColors.onInverse,
                                ),
                                onPressed: () => _finish(picked),
                                child: Text(tr.deviceSetupContinue),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
    return Scaffold(
      backgroundColor: AppColors.background,
      // Opened over the whole app, it covers the desktop layout's own title bar: the window keeps one to drag,
      // minimize and close it by.
      body: titleBarInShell.value
          ? Column(
              children: [
                const AppTitleBar(),
                Expanded(child: page),
              ],
            )
          : page,
    );
  }
}

extension on _DeviceSetupPageState {
  /// The layout (desktop) and the player preset, each a row of cards with a drawing of it.
  Widget _look(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: AppColors.textSecondary);
    final prefs = LayoutPrefs.instance;
    final layout = _layout ?? prefs.desktopLayout;
    final presets = [...PlayerPreset.all, ...CustomPresets.instance.presets];
    final preset = _preset ?? presets.where((p) => p.name == playerPresetName(prefs)).firstOrNull;
    Widget heading(String label) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(label, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr.setupLookTitle, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Text(tr.setupLookIntro, style: muted),
              if (Features.desktopLayout) ...[
                heading(tr.layoutLabel),
                Row(
                  children: [
                    for (final (i, option) in DesktopLayout.values.indexed) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(
                        child: _LookCard(
                          selected: option == layout,
                          title: option.label,
                          note: option == DesktopLayout.rail ? tr.setupLayoutRailNote : tr.setupLayoutClassicNote,
                          picture: _LayoutSketch(option),
                          onTap: () => _update(() => _layout = option),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              heading(tr.playerStyle),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final option in presets)
                    SizedBox(
                      width: 196,
                      child: _LookCard(
                        selected: option.name == preset?.name,
                        title: option.name,
                        note: presetNote(option),
                        picture: PresetSchematic(preset: option),
                        onTap: () => _update(() => _preset = option),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  TextButton(onPressed: () => _update(() => _showLook = false), child: Text(tr.back)),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => _update(() => _showPerformance = true),
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(tr.deviceSetupContinue),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A choice of the look step: a drawing over its name and a line about it, outlined when picked.
class _LookCard extends StatelessWidget {
  const _LookCard({
    required this.selected,
    required this.title,
    required this.note,
    required this.picture,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String note;
  final Widget picture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.elevated : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: LayoutPrefs.corner(10),
          side: BorderSide(color: selected ? AppColors.textPrimary : AppColors.divider, width: selected ? 1.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 96,
                  child: Center(
                    child: FittedBox(fit: BoxFit.scaleDown, child: picture),
                  ),
                ),
                const SizedBox(height: 10),
                Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A desktop window in plain boxes: Classic's wide library beside the page, or Rail's slim bar with the player
/// along the foot.
class _LayoutSketch extends StatelessWidget {
  const _LayoutSketch(this.layout);

  final DesktopLayout layout;

  @override
  Widget build(BuildContext context) {
    final soft = AppColors.textPrimary.withValues(alpha: 0.18);
    final strong = AppColors.textPrimary.withValues(alpha: 0.4);
    Widget box({double? width, double? height, Color? color, double r = 3}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: color ?? soft, borderRadius: BorderRadius.circular(r)),
    );
    final rail = layout == DesktopLayout.rail;
    return SizedBox(
      width: 160,
      height: 96,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: soft),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: rail
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    box(width: 10, color: strong),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: box()),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              box(width: 28, height: 10, color: strong),
                              const Spacer(),
                              box(width: 20, height: 10),
                              const Spacer(),
                              box(width: 22, height: 10, color: strong),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: box(width: 60, height: 7, color: strong)),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          box(width: 36),
                          const SizedBox(width: 5),
                          Expanded(child: box()),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    box(height: 12, color: strong),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The processor, its threads, the memory and whether it is a laptop: what the pick is made from.
class _Specs extends StatelessWidget {
  const _Specs(this.specs);
  final DeviceSpecs specs;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    final gb = specs.memoryGb;
    final battery = specs.battery;
    Widget row(IconData icon, String label) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: style)),
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.elevated, borderRadius: LayoutPrefs.corner(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          children: [
            if (specs.cpu case final cpu?) row(Icons.memory_rounded, cpu),
            row(Icons.account_tree_outlined, tr.deviceSetupThreads(specs.threads)),
            if (gb != null) row(Icons.storage_rounded, tr.deviceSetupMemory('$gb')),
            if (battery != null)
              battery
                  ? row(Icons.laptop_rounded, tr.deviceSetupLaptop)
                  : row(Icons.desktop_windows_outlined, tr.deviceSetupDesktop),
          ],
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.mode,
    required this.cost,
    required this.recommended,
    required this.selected,
    required this.onTap,
  });

  final PerformanceMode mode;
  final String cost;
  final bool recommended;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: selected ? AppColors.elevated : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: LayoutPrefs.corner(12),
          side: BorderSide(color: selected ? AppColors.textPrimary : AppColors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(mode.label, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          if (recommended)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppColors.inverse,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                child: Text(
                                  tr.deviceSetupRecommended,
                                  style: text.labelSmall?.copyWith(color: AppColors.onInverse),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(mode.note, style: muted),
                      Text(tr.deviceSetupCost(cost), style: muted),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
