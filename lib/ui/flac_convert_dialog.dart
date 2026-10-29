import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/download_prefs.dart';
import '../services/flac_convert.dart';
import '../services/player_controller.dart';
import '../services/youtube_importer.dart';
import 'theme.dart';

/// Asks how to make [tracks] FLAC, then converts them; the result comes as a SnackBar. Songs that can't be converted
/// are left out. Does nothing when none can.
Future<void> showFlacConvert(BuildContext context, PlayerController c, List<Track> tracks) async {
  final songs = tracks.where(FlacConvert.available).toList();
  if (songs.isEmpty) return;
  final prefs = DownloadPrefs.instance;
  await prefs.load();
  final downloads = (await YoutubeImporter.downloadsDir()).path;
  if (!context.mounted) return;
  final quality = await showDialog<FlacQuality>(
    context: context,
    useRootNavigator: true,
    builder: (_) => FlacConvertDialog(
      initial: prefs.flac,
      count: songs.length,
      keepsOriginals: songs.any((t) => !FlacConvert.replacesOriginal(t, downloads)),
    ),
  );
  if (quality == null) return;
  await FlacConvert.convertAll(c, songs, quality);
}

/// Explains what "Convert to FLAC" does and picks the quality of the FLAC: the one chosen in Settings › Downloads
/// to start with.
class FlacConvertDialog extends StatefulWidget {
  /// Creates the dialog for [count] songs.
  const FlacConvertDialog({super.key, required this.initial, required this.count, required this.keepsOriginals});

  /// The quality chosen when the dialog opens.
  final FlacQuality initial;

  /// How many songs will be converted.
  final int count;

  /// Whether some of the songs are files the person added, which stay as they are next to their FLAC.
  final bool keepsOriginals;

  @override
  State<FlacConvertDialog> createState() => _FlacConvertDialogState();
}

class _FlacConvertDialogState extends State<FlacConvertDialog> {
  late var _quality = widget.initial;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.textSecondary);
    final one = widget.count == 1;
    return AlertDialog(
      title: const Text('Convert to FLAC (Beta)'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${one ? 'The FLAC file' : 'Each FLAC file'} will be bigger than the original. The sound stays the '
                'same: FLAC can\'t bring back what the original already lost.',
              ),
              if (widget.keepsOriginals) ...[
                const SizedBox(height: 8),
                Text('Songs you added yourself stay as they are, next to their FLAC.', style: muted),
              ],
              const SizedBox(height: 16),
              Text('Quality', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final q in FlacQuality.values)
                    ChoiceChip(
                      label: Text(q.label),
                      selected: _quality == q,
                      onSelected: (_) => setState(() => _quality = q),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(_quality.about, style: muted),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.inverse, foregroundColor: AppColors.onInverse),
          onPressed: () => Navigator.of(context).pop(_quality),
          child: const Text('Convert'),
        ),
      ],
    );
  }
}
