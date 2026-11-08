import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' show Video;

import '../models/track.dart';
import '../platform/features.dart';
import '../services/download_prefs.dart';
import '../services/player_controller.dart';
import '../services/soundcloud.dart';
import '../services/youtube_importer.dart';
import '../services/youtube_links.dart';
import 'download_options.dart';
import 'theme.dart';
import 'widgets/controls.dart';
import 'widgets/skeleton.dart';
import '../services/language.dart';

/// Opens the "paste a YouTube (or SoundCloud) link" flow: bottom sheet on phones, dialog elsewhere.
/// Resolves to true when something was queued.
Future<bool> showYoutubeImport(BuildContext context, {required bool compact, String? initialUrl}) async {
  final controller = PlayerScope.read(context);
  final body = PlayerScope(
    controller: controller,
    child: _ImportForm(initialUrl: initialUrl),
  );
  final queued = compact
      ? await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: AppColors.elevated,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
          builder: (context) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
            child: body,
          ),
        )
      : await showDialog<bool>(
          context: context,
          builder: (context) => Dialog(
            // Scrolls on short windows instead of overflowing.
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(child: body),
            ),
          ),
        );
  return queued ?? false;
}

class _ImportForm extends StatefulWidget {
  const _ImportForm({this.initialUrl});

  final String? initialUrl;

  @override
  State<_ImportForm> createState() => _ImportFormState();
}

class _ImportFormState extends State<_ImportForm> {
  final _url = TextEditingController();
  YoutubePreview? _preview;

  /// A SoundCloud link's track or tracks: they stream, so they are played or saved, not downloaded.
  SoundcloudPage? _soundcloud;
  String? _error;
  bool _loading = false;
  int _lookup = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null) {
      _url.text = widget.initialUrl!;
      _resolve();
    } else {
      _pasteIfYoutube();
    }
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  /// Saves a step: if the clipboard already holds a YouTube link, use it.
  Future<void> _pasteIfYoutube() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (!mounted || text == null || _url.text.isNotEmpty || !_looksLikeLink(text)) return;
    _url.text = text;
    _resolve();
  }

  static bool _looksLikeLink(String text) =>
      YoutubeLinks.looksLikeLink(text) || (Features.soundcloud && SoundcloudLink.looksLikeLink(text));

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (text == null || text.isEmpty) return;
    _url.text = text;
    _resolve();
  }

  Future<void> _resolve() async {
    final text = _url.text.trim();
    final lookup = ++_lookup;
    if (text.isEmpty) {
      setState(() {
        _preview = _error = null;
        _soundcloud = null;
      });
      return;
    }
    if (Features.soundcloud) {
      if (SoundcloudLink.parse(text) case final link?) return _resolveSoundcloud(link, lookup);
    }
    // The paste field also takes a bare video id; clipboard auto-detect never does.
    final link = YoutubeLinks.parse(text, allowBareId: true);
    // An album page has no video list youtube_explode_dart can read.
    if (link == null || link is AlbumLink) {
      setState(() {
        _preview = null;
        _soundcloud = null;
        _error = Features.soundcloud ? tr.pasteYtOrScLink : tr.pasteYtLink;
      });
      return;
    }
    setState(() {
      _loading = true;
      _soundcloud = null;
      _error = null;
    });
    try {
      final preview = await PlayerScope.read(context).youtube.resolve(link.canonicalUrl);
      if (!mounted || lookup != _lookup) return;
      setState(() => _preview = preview);
    } catch (e) {
      if (!mounted || lookup != _lookup) return;
      setState(() {
        _preview = null;
        _error = tr.linkLoadFailed;
      });
    } finally {
      if (mounted && lookup == _lookup) setState(() => _loading = false);
    }
  }

  Future<void> _resolveSoundcloud(SoundcloudLink link, int lookup) async {
    setState(() {
      _loading = true;
      _preview = null;
      _error = null;
    });
    try {
      final page = await PlayerScope.read(context).soundcloud.resolve(link);
      if (!mounted || lookup != _lookup) return;
      setState(() {
        _soundcloud = page.tracks.isEmpty ? null : page;
        if (page.tracks.isEmpty) _error = tr.soundcloudUnplayable;
      });
    } catch (e) {
      debugPrint('SoundCloud link failed: $e');
      if (!mounted || lookup != _lookup) return;
      setState(() {
        _soundcloud = null;
        _error = e is SoundcloudUnplayable ? tr.soundcloudUnplayable : tr.linkLoadFailed;
      });
    } finally {
      if (mounted && lookup == _lookup) setState(() => _loading = false);
    }
  }

  Future<void> _playSoundcloud(SoundcloudPage page) async {
    final c = PlayerScope.read(context);
    Navigator.of(context).pop(true);
    await c.playList(page.tracks, 0, from: page.title);
  }

  Future<void> _saveSoundcloud(SoundcloudPage page) async {
    final c = PlayerScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);
    await c.saveToLibrary(page.tracks);
    messenger.showSnackBar(SnackBar(content: Text(tr.savedToLibrary)));
  }

  void _saveSoundcloudPlaylist(SoundcloudPage page) {
    final c = PlayerScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);
    c.createPlaylist(page.title, tracks: page.tracks);
    messenger.showSnackBar(SnackBar(content: Text(tr.createdPlaylistWith(page.title, page.tracks.length))));
  }

  Future<void> _download() async {
    final videos = switch (_preview) {
      VideoPreview(:final video) => [video],
      PlaylistPreview(:final videos) => videos,
      null => <Video>[],
    };
    final youtube = PlayerScope.read(context).youtube;
    // One video: its sizes are looked up while the dialog is open.
    final choice = await chooseDownload(context, videoId: videos.length == 1 ? videos.single.id.value : null);
    if (choice == null || !mounted) return;
    final queued = youtube.enqueue(videos, choice: choice);
    Navigator.of(context).pop(queued > 0);
  }

  /// A SoundCloud link's note and its two buttons: save to the library, play now.
  Widget _soundcloudActions(BuildContext context, SoundcloudPage page, BoxConstraints constraints) {
    final text = Theme.of(context).textTheme;
    final note = Text(tr.soundcloudImportNote, style: text.bodySmall?.copyWith(color: AppColors.textMuted));
    final buttons = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        if (page.kind == SoundcloudKind.playlist)
          OutlinedButton(
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
            onPressed: () => _saveSoundcloudPlaylist(page),
            child: Text(tr.saveAsPlaylist),
          ),
        OutlinedButton(
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
          onPressed: () => _saveSoundcloud(page),
          child: Text(tr.saveCountToLibrary(page.tracks.length)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.inverse,
            foregroundColor: AppColors.onInverse,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            textStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          onPressed: () => _playSoundcloud(page),
          child: Text(tr.play),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        note,
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerRight, child: buttons),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final preview = _preview;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr.importFromYouTube, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(tr.importFromYtBody, style: text.bodyMedium?.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          TextField(
            controller: _url,
            autofocus: widget.initialUrl == null,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _resolve(),
            onChanged: (v) {
              if (_looksLikeLink(v)) _resolve();
            },
            decoration: InputDecoration(
              hintText: 'https://youtube.com/watch?v=…',
              filled: true,
              fillColor: AppColors.hover,
              prefixIcon: const Icon(Icons.link_rounded),
              suffixIcon: TextButton(onPressed: _paste, child: Text(tr.paste)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: _loading
                ? const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: SkeletonList(count: 3))
                : _error != null
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!, style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
                  )
                : _soundcloud != null
                ? _SoundcloudCard(page: _soundcloud!)
                : preview == null
                ? const SizedBox(width: double.infinity)
                : _PreviewCard(preview: preview),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            // Narrow windows: the note goes above the button instead of squeezing it.
            builder: (context, constraints) {
              if (_soundcloud case final page? when !_loading) return _soundcloudActions(context, page, constraints);
              final note = Text(tr.bestQualityNote, style: text.bodySmall?.copyWith(color: AppColors.textMuted));
              final button = FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.inverse,
                  foregroundColor: AppColors.onInverse,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  textStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                onPressed: preview == null || _loading ? null : _download,
                child: Text(switch (preview) {
                  PlaylistPreview(:final videos) => tr.downloadCount('${videos.length}'),
                  _ => tr.download,
                }),
              );
              return constraints.maxWidth < 360
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [note, const SizedBox(height: 12), button],
                    )
                  : Row(
                      children: [
                        Expanded(child: note),
                        const SizedBox(width: 16),
                        button,
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatefulWidget {
  const _PreviewCard({required this.preview});

  final YoutubePreview preview;

  @override
  State<_PreviewCard> createState() => _PreviewCardState();
}

class _PreviewCardState extends State<_PreviewCard> {
  late final Future<String?> _sizeLine = _loadSizeLine();

  /// Exact size for one video (yt-dlp resolves it, which also primes the
  /// download); a duration-based estimate for playlists.
  Future<String?> _loadSizeLine() async {
    switch (widget.preview) {
      case VideoPreview(:final video):
        final peek = await PlayerScope.read(context).youtube.peekAudio(video.id.value);
        if (peek == null) return null;
        return [
          peek.quality,
          if (peek.size case final size?) peek.approx ? tr.aboutSize(formatBytes(size)) : formatBytes(size),
        ].join(' • ');
      case PlaylistPreview(:final videos):
        final seconds = videos.fold(0, (sum, v) => sum + (v.duration?.inSeconds ?? 0));
        if (seconds == 0) return null;
        final prefs = DownloadPrefs.instance;
        await prefs.load();
        final choice = prefs.choice;
        final bytes = choice.format.lossless
            ? estimateFlacBytes(Duration(seconds: seconds), choice.flac, compressed: YoutubeImporter.canReencode)
            // ~130 kbps Opus/AAC is what YouTube serves for most music; a lower bitrate is about what it says.
            : seconds * (choice.kbps ?? 130) * 1000 / 8;
        return tr.aboutSizeTotal(formatBytes(bytes));
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final text = Theme.of(context).textTheme;
    final (thumb, title, subtitle) = switch (preview) {
      VideoPreview(:final video) => (
        video.thumbnails.mediumResUrl,
        video.title,
        [video.author, if (video.duration != null) formatDuration(video.duration)].join(' • '),
      ),
      PlaylistPreview(:final playlist, :final videos) => (
        videos.firstOrNull?.thumbnails.mediumResUrl,
        playlist.title,
        tr.ytPlaylistLine(videos.length, playlist.author),
      ),
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.hover, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 112,
              height: 63,
              child: thumb == null
                  ? ColoredBox(color: AppColors.elevated)
                  : Image.network(
                      thumb,
                      cacheWidth: (112 * MediaQuery.devicePixelRatioOf(context)).round(),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ColoredBox(color: AppColors.elevated),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
                FutureBuilder<String?>(
                  future: _sizeLine,
                  builder: (context, snap) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      snap.connectionState == ConnectionState.done ? (snap.data ?? '') : tr.checkingSize,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A SoundCloud link's track, or its playlist / profile, before it is played or saved.
class _SoundcloudCard extends StatelessWidget {
  const _SoundcloudCard({required this.page});

  final SoundcloudPage page;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final one = page.isPlaylist ? null : page.tracks.single;
    final subtitle = one != null
        ? [one.artist, if (one.duration != null) formatDuration(one.duration)].join(' • ')
        : tr.soundcloudLine(page.tracks.length, page.subtitle);
    final art = page.artworkUrl;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.hover, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox.square(
              dimension: 63,
              child: art == null
                  ? ColoredBox(color: AppColors.elevated)
                  : Image.network(
                      art,
                      cacheWidth: (63 * MediaQuery.devicePixelRatioOf(context)).round(),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ColoredBox(color: AppColors.elevated),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  page.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const SourceMark(online: true, source: TrackSource.soundcloud, size: 14),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
