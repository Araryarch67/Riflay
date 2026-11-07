import 'package:flutter/material.dart';

import '../models/track.dart';
import '../platform/host.dart';
import '../services/download_prefs.dart';
import '../services/layout_prefs.dart';
import '../services/player_controller.dart';
import '../services/video_download.dart';
import '../services/youtube_importer.dart';
import '../services/youtube_stream.dart';
import 'theme.dart';
import 'widgets/app_dialog.dart';
import 'widgets/controls.dart' show Artwork, formatBytes;
import 'widgets/skeleton.dart';
import '../services/language.dart';

/// The format and quality to download with. Without [force] this follows
/// Settings and only asks when "Ask every time" is on; "Download as…"
/// forces the question. Null means the person backed out.
///
/// With a [videoId] the dialog shows what each choice would weigh (formats are looked up ahead, so they
/// are usually there as it opens). Without one (a whole playlist) it shows no sizes. [track] puts the song's
/// cover, title and artist at the top.
Future<DownloadChoice?> chooseDownload(
  BuildContext context, {
  bool force = false,
  String? videoId,
  Track? track,
}) async {
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
  final folder = await _savedTo();
  if (!context.mounted) return null;
  return showDialog<DownloadChoice>(
    context: context,
    useRootNavigator: true,
    builder: (_) => DownloadOptionsDialog(
      initial: prefs.choice,
      candidates: candidates,
      video: video,
      track: track,
      folder: folder,
    ),
  );
}

/// The downloads folder, for "Saved to" on computers. Phones keep downloads in the app's own folder, which says
/// nothing to the person, so they get no line.
Future<String?> _savedTo() async {
  if (!(Host.isLinux || Host.isWindows || Host.isMacOS)) return null;
  try {
    return (await YoutubeImporter.downloadsDir()).path;
  } catch (e) {
    debugPrint('downloads folder: $e');
    return null;
  }
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
    this.track,
    this.folder,
  });

  final DownloadChoice initial;

  /// The song, shown as a card under the title; null (a whole playlist) shows none.
  final Track? track;

  /// Where the file goes, under the buttons; null shows no line.
  final String? folder;

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

  /// A tile's second line: the size, a small placeholder while it is looked up, or [fallback].
  Widget? _sizeLine(String? size, {required bool loading, String? fallback}) {
    if (size != null) return Text(size);
    if (loading) return const Center(child: SkeletonBox(width: 44, height: 10, radius: 4));
    return fallback == null ? null : Text(fallback);
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
    // Sizes come only while a lookup runs: with none (or a failed one) they never come.
    final looking = formats == null && _videoLoading;
    final note = formats == null || _container != VideoContainer.mp4 ? null : webmTallerNote(formats, ffmpeg: _ffmpeg);
    return [
      DialogSection(
        label: tr.format,
        note: Text(_container.about),
        child: ChoiceTileGrid(
          columns: 2,
          children: [
            for (final c in containers)
              ChoiceTile(
                title: c.label,
                subtitle: Text(c == VideoContainer.mp4 ? 'H.264' : 'VP9'),
                selected: _container == c,
                badge: c == recommendedVideoChoice.container ? tr.recommended : null,
                onTap: () => setState(() => _container = c),
              ),
          ],
        ),
      ),
      DialogSection(
        label: tr.size,
        note: note == null ? null : Text(note),
        child: ChoiceTileGrid(
          columns: 3,
          children: [
            ChoiceTile(
              title: options.isEmpty ? tr.bestAvailable : tr.bestAvailableWith(options.first.label),
              subtitle: _sizeLine(_videoSize(_container, null), loading: looking),
              selected: want == null,
              onTap: () => setState(() => _heights[_container] = null),
            ),
            for (final o in options)
              ChoiceTile(
                title: o.label,
                subtitle: _sizeLine(_videoSize(_container, o.height), loading: looking),
                selected: o.height == selected,
                badge: o.height == recommended ? tr.recommended : null,
                onTap: () => setState(() => _heights[_container] = o.height),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _audioSection() {
    // A format this device can't make is left out, not shown greyed: unless it is the saved one. In the order
    // people know them: the one that plays anywhere first.
    final formats = [
      for (final f in const [DownloadFormat.mp3, DownloadFormat.flac, DownloadFormat.m4a, DownloadFormat.opus])
        if (switch (f) {
          DownloadFormat.flac => _canFlac || _format == f,
          DownloadFormat.mp3 => _canMp3 || _format == f,
          _ => true,
        })
          f,
    ];
    final kbps = _kbps[_format];
    final aboutFormat = _format == recommendedChoice.format
        ? Text.rich(
            TextSpan(
              children: [
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: DialogTag(tr.recommended)),
                ),
                TextSpan(text: _format.about),
              ],
            ),
          )
        : Text(_format.about);
    return [
      DialogSection(
        label: tr.audioFormat,
        note: aboutFormat,
        child: ChoiceTileGrid(
          columns: formats.length,
          children: [
            for (final f in formats)
              ChoiceTile(
                title: f.shortLabel,
                subtitle: Text(f.kindLabel),
                selected: _format == f,
                badge: f == recommendedChoice.format ? tr.recommended : null,
                onTap: () => setState(() => _format = f),
              ),
          ],
        ),
      ),
      // Lossless has no bitrate: its own question (bit depth and rate) takes the bitrate's place, rather than a
      // row of bitrates shown greyed out.
      if (_format.lossless)
        DialogSection(
          label: tr.bitDepthSampleRate,
          note: Text(_flac.about),
          child: ChoiceTileGrid(
            columns: 3,
            children: [
              for (final q in FlacQuality.values)
                ChoiceTile(
                  title: q.label,
                  subtitle: _sizeLine(_size(DownloadChoice(DownloadFormat.flac, flac: q)), loading: _loading),
                  selected: _flac == q,
                  onTap: () => setState(() => _flac = q),
                ),
            ],
          ),
        )
      else
        DialogSection(
          label: tr.bitrateQuality,
          note: kbps == null ? null : Text(_canReencode ? tr.smallerFilesNote : tr.smallerFilesClosest),
          child: ChoiceTileGrid(
            columns: 3,
            children: [
              for (final k in _format.bitrates)
                ChoiceTile(
                  title: bitrateLabelFor(_format, k),
                  subtitle: _sizeLine(_size(DownloadChoice(_format, kbps: k)), loading: _loading),
                  selected: kbps == k,
                  onTap: () => setState(() => _kbps[_format] = k),
                ),
            ],
          ),
        ),
    ];
  }

  /// The song this is for: its cover, title and artist.
  Widget _trackCard(Track track) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.tile, borderRadius: LayoutPrefs.corner(16)),
      child: Row(
        children: [
          Artwork(track: track, size: 56, radius: LayoutPrefs.radius(10)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                if (track.artist.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);
    final track = widget.track;
    final video = _kind == DownloadKind.video;
    final folder = widget.folder;
    final button = ButtonStyle(
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 24, vertical: 16)),
      textStyle: WidgetStatePropertyAll(Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
    );
    return AppDialog(
      title: track == null ? tr.downloadAsTitle : tr.downloadTrackTitle,
      width: 520,
      onClose: () => Navigator.of(context).pop(),
      content: DialogBody(
        children: [
          if (track != null) _trackCard(track),
          if (_showKind)
            PillTabs<DownloadKind>(
              values: DownloadKind.values,
              selected: _kind,
              label: (k) => k.label,
              onSelected: (k) => setState(() => _kind = k),
            ),
          if (_videoFailed) Text(tr.couldntLookUpSizes, style: muted),
          ...(video ? _videoSection() : _audioSection()),
        ],
      ),
      actions: [
        TextButton(
          style: button.merge(
            TextButton.styleFrom(backgroundColor: AppColors.tile, foregroundColor: AppColors.textPrimary),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr.cancel),
        ),
        FilledButton(
          style: button,
          onPressed: video
              ? (_videoLoading ? null : () => Navigator.of(context).pop(_videoChoice()))
              : () => Navigator.of(context).pop(DownloadChoice(_format, kbps: _kbps[_format], flac: _flac)),
          child: Text(tr.downloadFormatAction(video ? _container.label : _format.shortLabel)),
        ),
      ],
      footer: folder == null ? null : Text(tr.savedToFolder(folder)),
    );
  }
}
