import 'package:flutter/material.dart';

import '../services/download_prefs.dart';
import '../services/youtube_importer.dart';
import '../services/youtube_stream.dart';
import 'theme.dart';
import 'widgets/controls.dart' show formatBytes;

/// The format and quality to download with. Without [force] this follows
/// Settings and only asks when "Ask every time" is on; "Download as…"
/// forces the question. Null means the person backed out.
///
/// With a [videoId] the dialog shows what each choice would weigh (formats are looked up ahead, so they
/// are usually there as it opens). Without one (a whole playlist) it shows no sizes.
Future<DownloadChoice?> chooseDownload(BuildContext context, {bool force = false, String? videoId}) async {
  final prefs = DownloadPrefs.instance;
  await prefs.load();
  if (!force && !prefs.askEveryTime) return prefs.choice;
  if (!context.mounted) return null;
  return showDialog<DownloadChoice>(
    context: context,
    useRootNavigator: true,
    builder: (_) => DownloadOptionsDialog(
      initial: prefs.choice,
      candidates: videoId == null ? null : YoutubeStream.downloadCandidates(videoId),
    ),
  );
}

/// Pick a format and quality for one download.
class DownloadOptionsDialog extends StatefulWidget {
  const DownloadOptionsDialog({
    super.key,
    required this.initial,
    this.candidates,
    this.canMakeMp3,
    this.canMakeFlac,
    this.canReencode,
  });

  final DownloadChoice initial;

  /// What the song offers, for the sizes; null shows none. A failed lookup shows none too.
  final Future<List<AudioCandidate>>? candidates;

  /// Whether this device can make MP3 / FLAC / lower bitrates; null asks [YoutubeImporter].
  final bool? canMakeMp3;
  final bool? canMakeFlac;
  final bool? canReencode;

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

  List<AudioCandidate>? _found;
  late bool _loading = widget.candidates != null;

  bool get _canMp3 => widget.canMakeMp3 ?? YoutubeImporter.canMakeMp3;
  bool get _canFlac => widget.canMakeFlac ?? YoutubeImporter.canMakeFlac;
  bool get _canReencode => widget.canReencode ?? YoutubeImporter.canReencode;

  @override
  void initState() {
    super.initState();
    widget.candidates?.then(
      (found) {
        if (mounted) {
          setState(() {
            _found = found;
            _loading = false;
          });
        }
      },
      onError: (Object e) {
        debugPrint('download sizes unavailable: $e');
        if (mounted) setState(() => _loading = false);
      },
    );
  }

  /// "~4.2 MB" for [c], or null when not known (yet).
  String? _size(DownloadChoice c) {
    final found = _found;
    if (found == null) return null;
    final bytes = estimateDownloadBytes(found, c, canReencode: _canReencode);
    return bytes == null ? null : '~${formatBytes(bytes)}';
  }

  /// A chip's label: the name, then its size or, while the lookup runs, a small spinner.
  Widget _chipLabel(String name, DownloadChoice c) {
    final size = _size(c);
    if (size != null) return Text('$name · $size');
    if (!_loading) return Text(name);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name),
        const SizedBox(width: 8),
        const SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 2)),
      ],
    );
  }

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
                      if (switch (f) {
                        DownloadFormat.flac => _canFlac || _format == f,
                        DownloadFormat.mp3 => _canMp3 || _format == f,
                        _ => true,
                      })
                        RadioListTile<DownloadFormat>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: f,
                          title: Row(
                            children: [
                              Flexible(child: Text(f.label)),
                              if (f == recommendedChoice.format) ...[
                                const SizedBox(width: 8),
                                Text(
                                  'Recommended',
                                  style: muted?.copyWith(color: AppColors.accent, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ],
                          ),
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
                        label: _chipLabel(q.label, DownloadChoice(DownloadFormat.flac, flac: q)),
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
                        label: _chipLabel(bitrateLabelFor(_format, k), DownloadChoice(_format, kbps: k)),
                        selected: _kbps[_format] == k,
                        onSelected: (_) => setState(() => _kbps[_format] = k),
                      ),
                  ],
                ),
                if (_kbps[_format] != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _canReencode
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
