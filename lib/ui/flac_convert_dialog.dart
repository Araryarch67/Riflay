import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/download_prefs.dart';
import '../services/flac_convert.dart';
import '../services/player_controller.dart';
import '../services/youtube_importer.dart';
import 'theme.dart';
import '../services/language.dart';
import 'widgets/app_dialog.dart';

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

/// Explains what "Convert to FLAC" does and picks the quality of the FLAC: the one chosen in Settings › Library & downloads › Downloads
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
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);
    final one = widget.count == 1;
    return AppDialog(
      title: Text(tr.convertToFlac),
      content: DialogBody(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(one ? tr.flacBiggerOne : tr.flacBiggerEach),
              if (widget.keepsOriginals) ...[
                const SizedBox(height: DialogGap.note),
                Text(tr.ownSongsStay, style: muted),
              ],
            ],
          ),
          DialogSection(
            label: tr.quality,
            note: Text(_quality.about),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final q in FlacQuality.values)
                  ChoiceChip(
                    label: Text(q.label),
                    selected: _quality == q,
                    onSelected: (_) => setState(() => _quality = q),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr.cancel)),
        FilledButton(onPressed: () => Navigator.of(context).pop(_quality), child: Text(tr.convert)),
      ],
    );
  }
}
