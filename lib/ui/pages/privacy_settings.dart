import 'package:flutter/material.dart';

import '../../platform/features.dart';
import '../../services/play_history.dart';
import '../../services/wrap_notifications.dart';
import '../navigation.dart';
import '../shell_scope.dart';
import 'listening_stats_page.dart';
import '../../services/language.dart';
import 'sound_settings.dart' show SettingsCard, settingsMuted;

/// Settings › Library & downloads › Listening history & Wrap: the listening history kept on this device.
class PrivacySettings extends StatefulWidget {
  const PrivacySettings({super.key, this.history});

  /// The app's history by default.
  final PlayHistory? history;

  @override
  State<PrivacySettings> createState() => _PrivacySettingsState();
}

class _PrivacySettingsState extends State<PrivacySettings> {
  bool _wrapNotes = true;

  PlayHistory get _history => widget.history ?? PlayHistory.instance;

  @override
  void initState() {
    super.initState();
    WrapNotifier.isEnabled().then((v) {
      if (mounted) setState(() => _wrapNotes = v);
    }, onError: (Object _) {});
  }

  Future<void> _clear() async {
    final messenger = ScaffoldMessenger.of(context);
    final n = _history.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.clearHistoryQuestion),
        content: Text(tr.clearHistoryBody(n)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr.clear)),
        ],
      ),
    );
    if (ok != true) return;
    await _history.clear();
    messenger.showSnackBar(SnackBar(content: Text(tr.historyCleared)));
  }

  @override
  Widget build(BuildContext context) {
    final muted = settingsMuted(context);
    return ListenableBuilder(
      listenable: _history,
      builder: (context, _) => SettingsCard(
        children: [
          SwitchListTile(
            title: Text(tr.keepHistory),
            subtitle: Text(tr.keepHistorySubtitle, style: muted),
            value: _history.enabled,
            onChanged: _history.setEnabled,
          ),
          if (Features.systemNotifications)
            SwitchListTile(
              title: Text(tr.wrapNotification),
              subtitle: Text(tr.wrapNotificationSubtitle, style: muted),
              value: _wrapNotes,
              onChanged: (v) {
                setState(() => _wrapNotes = v);
                WrapNotifier.instance.setEnabled(v, _history).ignore();
              },
            ),
          ListTile(
            leading: const Icon(Icons.insights_rounded),
            title: Text(tr.yourListeningStats),
            subtitle: Text(tr.yourListeningStatsSubtitle, style: muted),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => ShellScope.of(context).open(const ListeningStatsPage(), location: Locations.stats),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded),
            title: Text(tr.clearHistory),
            subtitle: Text(_history.isEmpty ? tr.nothingSavedYet : tr.playsSaved(_history.length), style: muted),
            trailing: TextButton(onPressed: _history.isEmpty ? null : _clear, child: Text(tr.clear)),
          ),
        ],
      ),
    );
  }
}
