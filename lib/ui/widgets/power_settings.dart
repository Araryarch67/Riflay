import 'package:flutter/material.dart';

import '../../platform/host.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../../services/power_policy.dart';
import '../../services/stay_awake.dart';
import '../../services/system_tray.dart';
import '../pages/sound_settings.dart' show SettingTile, settingsMuted;
import '../theme.dart';
import 'menus.dart';
import '../../services/language.dart';

/// Settings › Power & background: keeping the screen on, keeping a computer awake
/// while music plays, closing to the tray (computers), and (Android) letting Riflay
/// run with the screen off.
class PowerSettings {
  const PowerSettings._();

  /// The controls shown on the dedicated Power & background page.
  static List<Widget> rows(BuildContext context) {
    final awake = StayAwake.instance;
    if (awake == null) return const [_PerformanceRow()];
    return [
      const _PerformanceRow(),
      _ScreenRow(awake),
      if (StayAwake.isDesktop) _SleepRow(awake),
      if (SystemTray.offered) const CloseToTrayRow(),
      if (BatteryExemption.supported) const BatteryTile(),
    ];
  }

  /// Called as the player changes: the first time music plays on Android, offers the battery sheet once.
  static void offerOnce(BuildContext context, PlayerController c) {
    final awake = StayAwake.instance;
    if (awake == null || !BatteryExemption.supported || awake.batteryAsked || !c.isPlaying || _offering) return;
    _offering = true;
    () async {
      try {
        if (await BatteryExemption.isExempt() || !context.mounted) {
          await awake.markBatteryAsked();
          return;
        }
        await awake.markBatteryAsked();
        if (!context.mounted) return;
        final yes = await showModalBottomSheet<bool>(
          context: context,
          backgroundColor: AppColors.elevated,
          showDragHandle: true,
          constraints: const BoxConstraints(maxWidth: 560),
          builder: (_) => const _BatterySheet(),
        );
        if (yes == true) await BatteryExemption.request();
      } finally {
        _offering = false;
      }
    }();
  }

  static bool _offering = false;
}

/// Lightweight, Balanced or Heavy: how much the app spends on looks (see [PerformanceMode]).
class _PerformanceRow extends StatelessWidget {
  const _PerformanceRow();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: LayoutPrefs.instance,
    builder: (context, _) {
      final p = LayoutPrefs.instance;
      return SettingTile(
        icon: Icons.speed_rounded,
        title: Text(tr.performance),
        subtitle: Text(p.performance.note, style: settingsMuted(context)),
        control: OptionPicker<PerformanceMode>(
          value: p.performance,
          onChanged: p.setPerformance,
          options: [for (final v in PerformanceMode.values) (v, v.label)],
        ),
      );
    },
  );
}

class _ScreenRow extends StatelessWidget {
  const _ScreenRow(this.awake);
  final StayAwake awake;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: awake,
    builder: (context, _) => SettingTile(
      icon: Icons.light_mode_outlined,
      title: Text(tr.keepScreenOn),
      subtitle: Text(
        Host.isIOS || Host.isAndroid ? tr.keepScreenOnPhone : tr.keepScreenOnDesktop,
        style: settingsMuted(context),
      ),
      control: OptionPicker<KeepScreenOn>(
        value: awake.screen,
        onChanged: awake.setScreen,
        options: [for (final v in KeepScreenOn.values) (v, v.label)],
      ),
    ),
  );
}

class _SleepRow extends StatelessWidget {
  const _SleepRow(this.awake);
  final StayAwake awake;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: awake,
    builder: (context, _) => SwitchListTile(
      secondary: const Icon(Icons.bedtime_off_outlined),
      title: Text(tr.dontSleepWhilePlaying),
      subtitle: Text(tr.dontSleepSubtitle, style: settingsMuted(context)),
      value: awake.preventSleep,
      onChanged: awake.setPreventSleep,
    ),
  );
}

/// Computers: whether closing the window hides Riflay in the tray (see [SystemTray]).
class CloseToTrayRow extends StatelessWidget {
  const CloseToTrayRow({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([CloseToTray.instance, SystemTray.available]),
    builder: (context, _) {
      // A desktop that shows no tray icons: the window has to close for real, so the switch can't help.
      final noTray = SystemTray.available.value == false;
      return SwitchListTile(
        secondary: const Icon(Icons.move_to_inbox_outlined),
        title: Text(tr.closeToTray),
        subtitle: Text(noTray ? tr.noTrayIcons : tr.closeToTraySubtitle, style: settingsMuted(context)),
        value: CloseToTray.instance.enabled && !noTray,
        onChanged: noTray ? null : CloseToTray.instance.setEnabled,
      );
    },
  );
}

/// Android: whether Riflay may keep playing with the screen off, with the one button to allow it.
class BatteryTile extends StatefulWidget {
  const BatteryTile({super.key});

  @override
  State<BatteryTile> createState() => _BatteryTileState();
}

class _BatteryTileState extends State<BatteryTile> with WidgetsBindingObserver {
  bool? _exempt;
  bool _aggressive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    BatteryExemption.brand().then((b) {
      if (mounted) setState(() => _aggressive = BatteryExemption.isAggressive(b));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the system's dialog or the maker's page: show what was chosen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final e = await BatteryExemption.isExempt();
    if (mounted) setState(() => _exempt = e);
  }

  @override
  Widget build(BuildContext context) {
    final exempt = _exempt;
    final muted = settingsMuted(context);
    return SettingTile(
      icon: Icons.battery_charging_full_rounded,
      title: Text(tr.keepPlayingScreenOff),
      subtitle: Text(
        exempt == null
            ? ''
            : exempt
            ? tr.batteryExemptOn
            : tr.batteryExemptOff,
        style: muted,
      ),
      control: Wrap(
        spacing: 8,
        children: [
          if (exempt == false) FilledButton(onPressed: BatteryExemption.request, child: Text(tr.allow)),
          if (_aggressive || exempt == false)
            OutlinedButton(onPressed: BatteryExemption.openBatterySettings, child: Text(tr.openBatterySettings)),
        ],
      ),
    );
  }
}

class _BatterySheet extends StatelessWidget {
  const _BatterySheet();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr.keepMusicPlaying, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(tr.keepMusicPlayingBody, style: text.bodyMedium?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr.allow)),
            ),
            SizedBox(
              width: double.infinity,
              child: TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr.notNow)),
            ),
          ],
        ),
      ),
    );
  }
}
