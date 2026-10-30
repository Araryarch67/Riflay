import 'package:flutter/material.dart';

import '../services/download_prefs.dart';
import '../services/player_controller.dart';
import '../services/video_download.dart';
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
  // Looked up once, here: the dialog's builder can run again.
  final c = context.getInheritedWidgetOfExactType<PlayerScope>()?.notifier;
  if (c != null) YoutubeStream.musicVideoIdLookup ??= (id) async => (await c.ytMusic.musicVideo(id))?.videoId;
  final candidates = videoId == null ? null : YoutubeStream.downloadCandidates(videoId);
  final video = videoId == null ? null : _videoOf(context, videoId);
  // The dialog reports a failed lookup itself; until it is on screen nobody listens yet.
  candidates?.ignore();
  video?.ignore();
  return showDialog<DownloadChoice>(
    context: context,
    useRootNavigator: true,
    builder: (_) => DownloadOptionsDialog(initial: prefs.choice, candidates: candidates, video: video),
  );
}

/// What the song's music video offers, or null when it has none (then the dialog only offers Audio). One cached
/// lookup, shared with the one made ahead; a failure is thrown, for the dialog to say.
Future<VideoFormats?>? _videoOf(BuildContext context, String videoId) {
  if (YoutubeStream.musicVideoIdLookup == null) return null;
  return YoutubeStream.musicVideoFormats(videoId);
}

/// Pick a format and quality for one download.
class DownloadOptionsDialog extends StatefulWidget {
  const DownloadOptionsDialog({
    super.key,
    required this.initial,
    this.candidates,
    this.video,
    this.canRemux,
    this.canMakeMp3,
    this.canMakeFlac,
    this.canReencode,
  });

  final DownloadChoice initial;

  /// What the song offers, for the sizes; null shows none. A failed lookup shows none too.
  final Future<List<AudioCandidate>>? candidates;

  /// What the song's music video offers (null result: it has none); null here offers no video at all.
  final Future<VideoFormats?>? video;

  /// Whether ffmpeg can be used (an AV1 stream can only be saved as WebM with it); null asks [YoutubeImporter].
  final bool? canRemux;

  /// Whether this device can make MP3 / FLAC / lower bitrates; null asks [YoutubeImporter].
  final bool? canMakeMp3;
  final bool? canMakeFlac;
  final bool? canReencode;

  @override
  State<DownloadOptionsDialog> createState() => _DownloadOptionsDialogState();
}

class _DownloadOptionsDialogState extends State<DownloadOptionsDialog> {
  // Video needs a song to look up; without one (a whole playlist) a saved Video choice starts on Audio, or the
  // dialog would wait for sizes that never come.
  late var _kind = widget.video == null ? DownloadKind.audio : widget.initial.kind;
  late var _container = widget.initial.container ?? DownloadPrefs.instance.videoContainer;
  // Each container keeps its own size while switching around in the dialog; null is "Best available".
  late final _heights = {
    for (final c in VideoContainer.values) c: DownloadPrefs.instance.heightFor(c),
    if (widget.initial.container != null) widget.initial.container!: widget.initial.height,
  };
  VideoFormats? _videoFormats;
  late bool _videoLoading = widget.video != null;
  bool _videoFailed = false;

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
  bool get _ffmpeg => widget.canRemux ?? YoutubeImporter.canReencode;
  bool get _canReencode => widget.canReencode ?? YoutubeImporter.canReencode;

  @override
  void initState() {
    super.initState();
    widget.video?.then(
      (formats) {
        if (!mounted) return;
        setState(() {
          _videoFormats = formats;
          _videoLoading = false;
          if (formats == null) {
            _kind = DownloadKind.audio;
          } else if (videoOptions(formats, _container, ffmpeg: _ffmpeg).isEmpty) {
            // The saved container can't be made from this video: the other one.
            final other = VideoContainer.values.where((c) => videoOptions(formats, c, ffmpeg: _ffmpeg).isNotEmpty);
            if (other.isEmpty) {
              _kind = DownloadKind.audio;
            } else {
              _container = other.first;
            }
          }
        });
      },
      onError: (Object e) {
        debugPrint('video sizes unavailable: $e');
        if (mounted) {
          setState(() {
            _videoLoading = false;
            _videoFailed = true;
            _kind = DownloadKind.audio;
          });
        }
      },
    );
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

  /// "18.2 MB" for a video choice, "~" first when it is only worked out; null when not known (yet).
  String? _videoSize(VideoContainer c, int? height) {
    final found = _videoFormats;
    if (found == null) return null;
    final e = estimateVideoDownload(found, DownloadChoice.video(c, height: height), ffmpeg: _ffmpeg);
    return e == null ? null : '${e.exact ? '' : '~'}${formatBytes(e.bytes)}';
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

  /// The Audio / Video switch shows once the song is known to have a music video (or while that is looked up and
  /// Video was the last choice).
  bool get _showKind =>
      widget.video != null && (_videoFormats != null || (_videoLoading && widget.initial.kind == DownloadKind.video));

  DownloadChoice _videoChoice() {
    final formats = _videoFormats;
    final height = _heights[_container];
    if (height == null || formats == null) return DownloadChoice.video(_container, height: height);
    // What is selected is the resolution the saved one lands on.
    final pick = pickVideoDownload(formats, DownloadChoice.video(_container, height: height), ffmpeg: _ffmpeg);
    return DownloadChoice.video(_container, height: pick?.video.height ?? height);
  }

  List<Widget> _videoSection(TextTheme text, TextStyle? muted) {
    final formats = _videoFormats;
    final containers = formats == null
        ? VideoContainer.values
        : [
            for (final c in VideoContainer.values)
              if (videoOptions(formats, c, ffmpeg: _ffmpeg).isNotEmpty) c,
          ];
    final options = formats == null ? const <VideoOption>[] : videoOptions(formats, _container, ffmpeg: _ffmpeg);
    final recommended = recommendedVideoHeightOf([for (final o in options) o.height]);
    final want = _heights[_container];
    final selected = want == null || options.isEmpty
        ? null
        : pickVideoDownload(formats!, DownloadChoice.video(_container, height: want), ffmpeg: _ffmpeg)?.video.height;
    Widget chipLabel(String name, String? size) {
      if (size != null) return Text('$name · $size');
      // A spinner only while a lookup runs: with none (or a failed one), sizes never come.
      if (formats != null || !_videoLoading) return Text(name);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name),
          const SizedBox(width: 8),
          const SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      );
    }

    final note = formats == null || _container != VideoContainer.mp4 ? null : webmTallerNote(formats, ffmpeg: _ffmpeg);
    return [
      Text('Format', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      RadioGroup<VideoContainer>(
        groupValue: _container,
        onChanged: (v) => setState(() => _container = v ?? _container),
        child: Column(
          children: [
            for (final c in containers)
              RadioListTile<VideoContainer>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: c,
                title: Row(
                  children: [
                    Flexible(child: Text(c.label)),
                    if (c == recommendedVideoChoice.container) ...[
                      const SizedBox(width: 8),
                      Text(
                        'Recommended',
                        style: muted?.copyWith(color: AppColors.accent, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
                subtitle: Text(c.about, style: muted),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Text('Size', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          ChoiceChip(
            label: chipLabel(
              options.isEmpty ? 'Best available' : 'Best available (${options.first.label})',
              _videoSize(_container, null),
            ),
            selected: want == null,
            onSelected: (_) => setState(() => _heights[_container] = null),
          ),
          for (final o in options)
            ChoiceChip(
              label: chipLabel(
                o.height == recommended ? '${o.label} · Recommended' : o.label,
                _videoSize(_container, o.height),
              ),
              selected: o.height == selected,
              onSelected: (_) => setState(() => _heights[_container] = o.height),
            ),
        ],
      ),
      if (note != null) ...[const SizedBox(height: 8), Text(note, style: muted)],
    ];
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
              if (_showKind) ...[
                SegmentedButton<DownloadKind>(
                  showSelectedIcon: false,
                  segments: [for (final k in DownloadKind.values) ButtonSegment(value: k, label: Text(k.label))],
                  selected: {_kind},
                  onSelectionChanged: (v) => setState(() => _kind = v.first),
                ),
                const SizedBox(height: 16),
              ],
              if (_videoFailed) ...[Text("Couldn't look up video sizes.", style: muted), const SizedBox(height: 12)],
              if (_kind == DownloadKind.video)
                ..._videoSection(text, muted)
              else ...[
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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.inverse, foregroundColor: AppColors.onInverse),
          onPressed: _kind == DownloadKind.video
              ? (_videoLoading ? null : () => Navigator.of(context).pop(_videoChoice()))
              : () => Navigator.of(context).pop(DownloadChoice(_format, kbps: _kbps[_format], flac: _flac)),
          child: const Text('Download'),
        ),
      ],
    );
  }
}
