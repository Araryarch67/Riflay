import 'package:flutter/material.dart';

import '../../services/device_setup.dart';
import '../../services/language.dart';
import '../../services/layout_prefs.dart';
import '../theme.dart';

/// Opens the setup page over the app: on the first start of a computer ([DeviceSetup.due]), and from Settings ›
/// Power & background. The pick applies on Continue; "Keep my settings" leaves everything as it was.
Future<void> showDeviceSetup(BuildContext context) => Navigator.of(
  context,
  rootNavigator: true,
).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const DeviceSetupPage()));

/// What this computer is, and the three performance modes with what a playing song costs in each, the one that
/// fits [DeviceSetup.budget] picked to start with.
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

  Future<void> _finish(PerformanceMode? mode) async {
    if (mode != null) await LayoutPrefs.instance.setPerformance(mode);
    await DeviceSetup.instance.done();
    if (mounted) Navigator.of(context).pop();
  }

  static String _percent(double v) => v < 0.1 ? '0.1' : v.toStringAsFixed(v < 1 ? 2 : 1);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: AppColors.textSecondary);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FutureBuilder<DeviceSpecs>(
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
                      Text(tr.deviceSetupIntro(_percent(DeviceSetup.budget)), style: muted),
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
