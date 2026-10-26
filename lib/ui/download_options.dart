import 'package:flutter/material.dart';

import '../services/download_prefs.dart';
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
  late var _quality = widget.initial.quality;

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
              Text('Quality', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              RadioGroup<DownloadQuality>(
                groupValue: _quality,
                onChanged: (v) => setState(() => _quality = v ?? _quality),
                child: Column(
                  children: [
                    for (final q in DownloadQuality.values)
                      RadioListTile<DownloadQuality>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: q,
                        title: Text(q.label),
                        subtitle: Text(q.about, style: muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.inverse, foregroundColor: AppColors.onInverse),
          onPressed: () => Navigator.of(context).pop(DownloadChoice(_format, _quality)),
          child: const Text('Download'),
        ),
      ],
    );
  }
}
