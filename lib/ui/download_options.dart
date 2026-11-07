import 'package:flutter/material.dart';

import '../services/download_prefs.dart';
import '../services/player_controller.dart';
import '../services/video_download.dart';
import '../services/youtube_importer.dart';
import '../services/youtube_stream.dart';
import 'theme.dart';
import 'widgets/app_dialog.dart';
import 'widgets/controls.dart' show formatBytes;
import 'widgets/skeleton.dart';
import '../services/language.dart';

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
      children: [Text(name), const SizedBox(width: 8), const SkeletonBox.circle(size: 12)],
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

  /// A chip for one choice in a group: its name, then a "Recommended" tag when [recommended].
  Widget _choice({
    required Widget label,
    required bool selected,
    required VoidCallback onSelected,
    bool recommended = false,
  }) => ChoiceChip(
    label: recommended
        ? Row(
            mainAxisSize: MainAxisSize.min,
            // A long video label ("2160p60 · AV1 (newer devices) · 120 MB") gives way before the tag does.
            children: [
              Flexible(child: label),
              const SizedBox(width: 8),
              DialogTag(tr.recommended, onSelected: selected),
            ],
          )
        : label,
    selected: selected,
    onSelected: (_) => onSelected(),
  );

  static Widget _chips(List<Widget> chips) => Wrap(spacing: 8, runSpacing: 8, children: chips);

  List<Widget> _videoSection() {
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
        children: [Text(name), const SizedBox(width: 8), const SkeletonBox.circle(size: 12)],
      );
    }

    final note = formats == null || _container != VideoContainer.mp4 ? null : webmTallerNote(formats, ffmpeg: _ffmpeg);
    return [
      DialogSection(
        label: tr.format,
        note: Text(_container.about),
        child: _chips([
          for (final c in containers)
            _choice(
              label: Text(c.label),
              selected: _container == c,
              recommended: c == recommendedVideoChoice.container,
              onSelected: () => setState(() => _container = c),
            ),
        ]),
      ),
      DialogSection(
        label: tr.size,
        note: note == null ? null : Text(note),
        child: _chips([
          _choice(
            label: chipLabel(
              options.isEmpty ? tr.bestAvailable : tr.bestAvailableWith(options.first.label),
              _videoSize(_container, null),
            ),
            selected: want == null,
            onSelected: () => setState(() => _heights[_container] = null),
          ),
          for (final o in options)
            _choice(
              label: chipLabel(o.label, _videoSize(_container, o.height)),
              selected: o.height == selected,
              recommended: o.height == recommended,
              onSelected: () => setState(() => _heights[_container] = o.height),
            ),
        ]),
      ),
    ];
  }

  List<Widget> _audioSection() {
    // A format this device can't make is left out, not shown greyed: unless it is the saved one.
    final formats = [
      for (final f in DownloadFormat.values)
        if (switch (f) {
          DownloadFormat.flac => _canFlac || _format == f,
          DownloadFormat.mp3 => _canMp3 || _format == f,
          _ => true,
        })
          f,
    ];
    final kbps = _kbps[_format];
    return [
      DialogSection(
        label: tr.format,
        note: Text(_format.about),
        child: _chips([
          for (final f in formats)
            _choice(
              label: Text(f.label),
              selected: _format == f,
              recommended: f == recommendedChoice.format,
              onSelected: () => setState(() => _format = f),
            ),
        ]),
      ),
      // Lossless has no bitrate: its own question (bit depth and rate) takes the place of the bitrate's.
      if (_format.lossless)
        DialogSection(
          label: tr.bitDepthSampleRate,
          note: Text(_flac.about),
          child: _chips([
            for (final q in FlacQuality.values)
              _choice(
                label: _chipLabel(q.label, DownloadChoice(DownloadFormat.flac, flac: q)),
                selected: _flac == q,
                onSelected: () => setState(() => _flac = q),
              ),
          ]),
        )
      else
        DialogSection(
          label: tr.bitrate,
          note: kbps == null ? null : Text(_canReencode ? tr.smallerFilesNote : tr.smallerFilesClosest),
          child: _chips([
            for (final k in _format.bitrates)
              _choice(
                label: _chipLabel(bitrateLabelFor(_format, k), DownloadChoice(_format, kbps: k)),
                selected: kbps == k,
                onSelected: () => setState(() => _kbps[_format] = k),
              ),
          ]),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);
    return AppDialog(
      title: tr.downloadAsTitle,
      content: DialogBody(
        children: [
          if (_showKind)
            SegmentedButton<DownloadKind>(
              showSelectedIcon: false,
              segments: [for (final k in DownloadKind.values) ButtonSegment(value: k, label: Text(k.label))],
              selected: {_kind},
              onSelectionChanged: (v) => setState(() => _kind = v.first),
            ),
          if (_videoFailed) Text(tr.couldntLookUpSizes, style: muted),
          ...(_kind == DownloadKind.video ? _videoSection() : _audioSection()),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr.cancel)),
        FilledButton(
          onPressed: _kind == DownloadKind.video
              ? (_videoLoading ? null : () => Navigator.of(context).pop(_videoChoice()))
              : () => Navigator.of(context).pop(DownloadChoice(_format, kbps: _kbps[_format], flac: _flac)),
          child: Text(tr.download),
        ),
      ],
    );
  }
}
