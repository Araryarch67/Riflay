import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../platform/host.dart';
import '../../services/backup.dart';
import '../../services/language.dart';
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
        dialogTitle: tr.saveABackup,
        fileName: Backup.fileName(),
        bytes: utf8.encode(text),
        mimeType: 'application/json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (saved != null && mounted) _say(tr.backupSaved);
    } catch (e) {
      debugPrint('Backup: $e');
      if (mounted) _say(tr.couldntSaveBackup);
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
        dialogTitle: tr.chooseBackup,
      )).firstOrNull;
      if (file == null) return;
      backup = Backup.read(utf8.decode(await file.readAsBytes(), allowMalformed: true));
    } on FormatException catch (e) {
      final newer = e.message == 'Made by a newer Riflay';
      if (mounted) _say(newer ? tr.backupNeedsNewer : tr.notABackup);
      return;
    } catch (e) {
      debugPrint('Backup: $e');
      if (mounted) _say(tr.couldntReadFile);
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.restoreBackupQuestion),
        content: Text(tr.restoreBackupBody(backup.playlists, backup.plays, backup.lyrics, _made(backup.created))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr.restore)),
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
        _say(tr.couldntRestoreBackup);
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
        title: Text(tr.backupRestored),
        content: Text(Host.isIOS ? tr.backupRestoredIos : tr.backupRestoredDesktop),
        actions: [FilledButton(onPressed: Host.isIOS ? null : () => exit(0), child: Text(tr.closeRiflay))],
      ),
    );
  }

  static String _made(DateTime? at) {
    if (at == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${tr.madeOn('${at.year}-${two(at.month)}-${two(at.day)}')} ';
  }

  @override
  Widget build(BuildContext context) {
    final muted = settingsMuted(context);
    return SettingsCard(
      children: [
        SettingTile(
          icon: Icons.save_alt_rounded,
          title: Text(tr.saveABackup),
          subtitle: Text(tr.saveABackupSubtitle, style: muted),
          control: FilledButton.tonal(onPressed: _busy ? null : _save, child: Text(tr.save)),
        ),
        SettingTile(
          icon: Icons.settings_backup_restore_rounded,
          title: Text(tr.restoreABackup),
          subtitle: Text(tr.restoreABackupSubtitle, style: muted),
          control: TextButton(onPressed: _busy ? null : _restore, child: Text(tr.restore)),
        ),
      ],
    );
  }
}
