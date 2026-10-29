import 'package:flutter/material.dart';

import '../../services/play_history.dart';
import '../../services/wrap_notifications.dart';
import '../navigation.dart';
import '../shell_scope.dart';
import 'listening_stats_page.dart';
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
        title: const Text('Clear listening history?'),
        content: Text(
          'This deletes $n ${n == 1 ? 'play' : 'plays'} from this device. Your library and playlists stay as they are, '
          'but your stats, Wraps and lists like Most played start over.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    await _history.clear();
    messenger.showSnackBar(const SnackBar(content: Text('Listening history cleared')));
  }

  @override
  Widget build(BuildContext context) {
    final muted = settingsMuted(context);
    return ListenableBuilder(
      listenable: _history,
      builder: (context, _) => SettingsCard(
        children: [
          SwitchListTile(
            title: const Text('Keep a listening history on this device'),
            subtitle: Text(
              'Powers Your listening stats, monthly Wraps and lists like Most played. It is never sent anywhere. '
              'Turning it off stops recording; what is saved stays until you clear it.',
              style: muted,
            ),
            value: _history.enabled,
            onChanged: _history.setEnabled,
          ),
          SwitchListTile(
            title: const Text('Monthly Wrap notification'),
            subtitle: Text('On the 1st, tell me when last month\'s Wrap is ready.', style: muted),
            value: _wrapNotes,
            onChanged: (v) {
              setState(() => _wrapNotes = v);
              WrapNotifier.instance.setEnabled(v, _history).ignore();
            },
          ),
          ListTile(
            leading: const Icon(Icons.insights_rounded),
            title: const Text('Your listening stats'),
            subtitle: Text('Top songs, artists and albums', style: muted),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => ShellScope.of(context).open(const ListeningStatsPage(), location: Locations.stats),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded),
            title: const Text('Clear listening history'),
            subtitle: Text(
              _history.isEmpty ? 'Nothing saved yet' : '${_history.length} plays saved on this device',
              style: muted,
            ),
            trailing: TextButton(onPressed: _history.isEmpty ? null : _clear, child: const Text('Clear')),
          ),
        ],
      ),
    );
  }
}
