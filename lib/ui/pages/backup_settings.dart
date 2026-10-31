import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../platform/host.dart';
import '../../services/backup.dart';
import 'sound_settings.dart' show SettingTile, SettingsCard, settingsMuted;

/// Settings › Library & downloads › Backup & restore: settings, playlists and history in one file.
class BackupSettings extends StatefulWidget {
  const BackupSettings({super.key});

  @override
  State<BackupSettings> createState() => _BackupSettingsState();
}

class _BackupSettingsState extends State<BackupSettings> {
  bool _busy = false;

  void _say(String m) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final text = await Backup.create();
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save a backup',
        fileName: Backup.fileName(),
        bytes: utf8.encode(text),
        mimeType: 'application/json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (saved != null && mounted) _say('Backup saved');
    } catch (e) {
      debugPrint('Backup: $e');
      if (mounted) _say('Couldn\'t save the backup.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final BackupSummary backup;
    try {
      final file = (await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        dialogTitle: 'Choose a Riflay backup',
      )).firstOrNull;
      if (file == null) return;
      backup = Backup.read(utf8.decode(await file.readAsBytes(), allowMalformed: true));
    } on FormatException catch (e) {
      final newer = e.message == 'Made by a newer Riflay';
      if (mounted) _say(newer ? 'This backup needs a newer Riflay.' : 'That file isn\'t a Riflay backup.');
      return;
    } catch (e) {
      debugPrint('Backup: $e');
      if (mounted) _say('Couldn\'t read that file.');
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Text(
          '${_made(backup.created)}It has ${_n(backup.playlists, 'playlist')}, ${_n(backup.plays, 'play')} of '
          'listening history and ${_n(backup.lyrics, 'lyrics file')}. They replace the settings, playlists and '
          'history on this device. Your sign-ins stay.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await Backup.restore(backup);
    } catch (e) {
      debugPrint('Restore: $e');
      if (mounted) {
        setState(() => _busy = false);
        _say('Couldn\'t restore the backup.');
      }
      return;
    }
    if (!mounted) return;
    // Every part of the app read its settings at start; a fresh start reads the restored ones (and nothing still
    // running writes the old ones back over them).
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Backup restored'),
        content: Text(
          Host.isIOS
              ? 'Close Riflay from the app switcher and open it again to finish.'
              : 'Riflay closes now. Open it again to finish.',
        ),
        actions: [FilledButton(onPressed: Host.isIOS ? null : () => exit(0), child: const Text('Close Riflay'))],
      ),
    );
  }

  static String _n(int n, String what) => '$n ${n == 1 ? what : '${what}s'}';

  static String _made(DateTime? at) {
    if (at == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Made on ${at.year}-${two(at.month)}-${two(at.day)}. ';
  }

  @override
  Widget build(BuildContext context) {
    final muted = settingsMuted(context);
    return SettingsCard(
      children: [
        SettingTile(
          icon: Icons.save_alt_rounded,
          title: const Text('Save a backup'),
          subtitle: Text(
            'Your settings, playlists, listening history and your own lyrics, in one file. Sign-ins are left out.',
            style: muted,
          ),
          control: FilledButton.tonal(onPressed: _busy ? null : _save, child: const Text('Save')),
        ),
        SettingTile(
          icon: Icons.settings_backup_restore_rounded,
          title: const Text('Restore a backup'),
          subtitle: Text('Bring them back on this device or a new one.', style: muted),
          control: TextButton(onPressed: _busy ? null : _restore, child: const Text('Restore')),
        ),
      ],
    );
  }
}
