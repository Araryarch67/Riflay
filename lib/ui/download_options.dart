import 'package:flutter/material.dart';

import '../services/download_prefs.dart';
import '../services/youtube_importer.dart';
import 'theme.dart';

/// The format and quality to download with. Without [force] this follows
/// Settings and only asks when "Ask every time" is on; "Download as…" forces
/// the question. Null means the person backed out.
Future<DownloadChoice?> chooseDownload(BuildContext context, {bool force = false}) async {
  final prefs = DownloadPrefs.instance;
  await prefs.load();
  if (!force && !prefs.askEveryTime) return prefs.choice;
  if (!context.mounted) return null;
  return showDialog<DownloadChoice>(
    context: context,
    useRootNavigator: true,
    builder: (_) => DownloadOptionsDialog(initial: prefs.choice),
  );
}

/// Pick a format and quality for one download.
class DownloadOptionsDialog extends StatefulWidget {
  const DownloadOptionsDialog({super.key, required this.initial});

  final DownloadChoice initial;

  @override
  State<DownloadOptionsDialog> createState() => _DownloadOptionsDialogState();
}

class _DownloadOptionsDialogState extends State<DownloadOptionsDialog> {
  late var _format = widget.initial.format;
  late var _flac = widget.initial.flac;
  // Each format keeps its own bitrate while switching around in the dialog.
  late final _kbps = {
    for (final f in DownloadFormat.values.where((f) => !f.lossless)) f: DownloadPrefs.instance.kbpsFor(f),
    if (!widget.initial.format.lossless) widget.initial.format: widget.initial.kbps,
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.textSecondary);
    return AlertDialog(
      backgroundColor: AppColors.elevated,
      title: const Text('Download as'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Format', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              RadioGroup<DownloadFormat>(
                groupValue: _format,
                onChanged: (v) => setState(() => _format = v ?? _format),
                child: Column(
                  children: [
                    for (final f in DownloadFormat.values)
                      if (!f.lossless || YoutubeImporter.canMakeFlac || _format.lossless)
                        RadioListTile<DownloadFormat>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: f,
                          title: Text(f.label),
                          subtitle: Text(f.about, style: muted),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _format.lossless ? 'Bit depth and sample rate' : 'Bitrate',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (_format.lossless) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final q in FlacQuality.values)
                      ChoiceChip(
                        label: Text(q.label),
                        selected: _flac == q,
                        onSelected: (_) => setState(() => _flac = q),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_flac.about, style: muted),
              ] else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final k in _format.bitrates)
                      ChoiceChip(
                        label: Text(bitrateLabel(k)),
                        selected: _kbps[_format] == k,
                        onSelected: (_) => setState(() => _kbps[_format] = k),
                      ),
                  ],
                ),
                if (_kbps[_format] != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    YoutubeImporter.canReencode
                        ? 'Smaller files, with a little less full sound.'
                        : 'Smaller files, with a little less full sound. Uses the closest version YouTube offers.',
                    style: muted,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.inverse, foregroundColor: AppColors.onInverse),
          onPressed: () => Navigator.of(context).pop(DownloadChoice(_format, kbps: _kbps[_format], flac: _flac)),
          child: const Text('Download'),
        ),
      ],
    );
  }
}
