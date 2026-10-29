import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/player_controller.dart';
import '../../services/power_policy.dart';
import '../../services/stay_awake.dart';
import '../pages/sound_settings.dart' show SettingTile, settingsMuted;
import '../theme.dart';
import 'menus.dart';

/// Settings › Sound › Playback › Power: keeping the screen on, keeping a computer awake
/// while music plays, and (Android) letting Riflay run with the screen off.
class PowerSettings {
  const PowerSettings._();

  /// The rows, to go at the end of the Playback card.
  static List<Widget> rows(BuildContext context) {
    final awake = StayAwake.instance;
    if (awake == null) return const [];
    return [
      const _PowerHeader(),
      _ScreenRow(awake),
      if (StayAwake.isDesktop) _SleepRow(awake),
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

class _PowerHeader extends StatelessWidget {
  const _PowerHeader();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
      child: Text(
        'Power',
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w700),
      ),
    ),
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
      title: const Text('Keep screen on'),
      subtitle: Text(
        Platform.isIOS || Platform.isAndroid
            ? 'Stops the screen from turning off by itself. Costs battery'
            : 'Stops the screen from turning off and locking by itself',
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
      title: const Text('Don\'t sleep while playing'),
      subtitle: Text(
        'The computer stays awake while music plays. The screen can still turn off',
        style: settingsMuted(context),
      ),
      value: awake.preventSleep,
      onChanged: awake.setPreventSleep,
    ),
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
      title: const Text('Keep playing with the screen off'),
      subtitle: Text(
        exempt == null
            ? ''
            : exempt
            ? 'On. Your phone won\'t put Riflay to sleep'
            : 'Off. Your phone may stop the music after a while',
        style: muted,
      ),
      control: Wrap(
        spacing: 8,
        children: [
          if (exempt == false) FilledButton(onPressed: BatteryExemption.request, child: const Text('Allow')),
          if (_aggressive || exempt == false)
            OutlinedButton(onPressed: BatteryExemption.openBatterySettings, child: const Text('Open battery settings')),
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
            Text('Keep the music playing', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              'Some phones stop music when the screen has been off for a while. '
              'Allowing Riflay to run in the background keeps it playing. You can change this later in Settings.',
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Allow')),
            ),
            SizedBox(
              width: double.infinity,
              child: TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
            ),
          ],
        ),
      ),
    );
  }
}
