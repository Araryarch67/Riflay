import 'package:flutter/material.dart';

import '../../services/downloaded_tools.dart';
import '../../services/language.dart';
import '../theme.dart';
import '../widgets/controls.dart' show formatBytes;
import 'sound_settings.dart' show SettingsCard, settingsMuted;

/// Settings › About › Delete executables: inspect and remove tools downloaded by Riflay.
class DownloadedToolsPage extends StatefulWidget {
  const DownloadedToolsPage({super.key, this.tools});

  final DownloadedTools? tools;

  @override
  State<DownloadedToolsPage> createState() => _DownloadedToolsPageState();
}

class _DownloadedToolsPageState extends State<DownloadedToolsPage> {
  late final _tools = widget.tools ?? DownloadedTools();
  List<DownloadedTool> _files = [];
  bool _busy = true, _failed = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final files = await _tools.scan();
      if (mounted) setState(() => _files = files);
    } catch (e) {
      debugPrint('Could not find downloaded tools: $e');
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.deleteExecutablesQuestion),
        content: Text(tr.deleteExecutablesBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr.delete)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await _tools.deleteAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.failed == 0 ? tr.executablesDeleted : tr.couldntDeleteExecutables)),
        );
      }
    } catch (e) {
      debugPrint('Could not delete downloaded tools: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.couldntDeleteExecutables)));
    }
    if (mounted) await _scan();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      title: Text(tr.downloadedTools),
      backgroundColor: AppColors.background,
      actions: [
        IconButton(tooltip: tr.refresh, onPressed: _busy ? null : _scan, icon: const Icon(Icons.refresh_rounded)),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(tr.downloadedToolsIntro, style: settingsMuted(context)),
        const SizedBox(height: 16),
        if (_busy)
          const Center(
            child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
          )
        else if (_failed) ...[
          Text(tr.couldntFindExecutables),
          TextButton(onPressed: _scan, child: Text(tr.retry)),
        ] else if (_files.isEmpty)
          SettingsCard(children: [ListTile(title: Text(tr.noDownloadedTools))])
        else
          SettingsCard(
            children: [
              for (final file in _files)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${file.name} · ${formatBytes(file.bytes)}', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      SelectableText(file.path, style: settingsMuted(context)),
                    ],
                  ),
                ),
            ],
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy || _failed || _files.isEmpty ? null : _delete,
          icon: const Icon(Icons.delete_outline_rounded),
          label: Text(tr.deleteAllExecutables),
        ),
      ],
    ),
  );
}
