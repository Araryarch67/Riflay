import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/download_matches.dart';
import '../services/download_prefs.dart';
import '../services/language.dart';
import '../services/monochrome.dart';
import '../services/player_controller.dart';
import '../services/sources/music_sources.dart';
import '../services/spotiflac.dart';
import 'download_options.dart';
import 'widgets/app_dialog.dart';
import 'widgets/controls.dart' show Artwork, formatDuration;
import 'widgets/menus.dart';

/// Metadata-only catalogues need an explicit audio provider, kept with the job
/// so retries and browser verification continue using that same provider.
Future<bool> downloadExtensionTracks(
  BuildContext context,
  PlayerController player,
  List<Track> tracks, {
  Spotiflac? runtime,
}) async {
  final engine = runtime ?? Spotiflac.instance;
  try {
    await engine.load();
    await DownloadPrefs.instance.load();
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.spotiflacFailed)));
    return false;
  }
  if (!context.mounted) return false;
  final providers = engine.downloadProviders;
  bool ownDownloader(Track track) => providers.any((provider) => provider['id'] == track.extensionId);
  if (tracks.every(ownDownloader)) {
    return player.youtube.enqueueTracks(tracks) > 0;
  }
  if (providers.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.spotiflacNeedsDownloader)));
    return false;
  }
  final provider = DownloadPrefs.instance.catalogueDownloader ?? providers.first['id'] as String;
  if (!providers.any((entry) => entry['id'] == provider)) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.sourceUnavailable(engine.nameOf(provider)))));
    return false;
  }
  final direct = tracks.where(ownDownloader).toList();
  final metadata = tracks.where((track) => !ownDownloader(track)).toList();
  final options = engine.plugin(provider)?['quality_options'];
  final added =
      player.youtube.enqueueTracks(direct) +
      player.youtube.enqueueTracks(
        metadata,
        extensionDownloader: provider,
        extensionQuality: options is List && options.isNotEmpty ? engine.qualityOf(provider) : null,
      );
  return added > 0;
}

/// Chooses an audio provider for a single YouTube song. The default provider
/// retains its existing format dialog and preferences.
Future<bool> downloadFromSource(
  BuildContext context,
  PlayerController player,
  Track origin, {
  bool force = false,
}) async {
  await DownloadPrefs.instance.load();
  if (!context.mounted) return false;
  final source = DownloadPrefs.instance.source;
  if (source == 'youtube') {
    final choice = await chooseDownload(context, force: force, videoId: origin.videoId, track: origin);
    if (choice == null) return false;
    return player.youtube.enqueueTracks([origin], choice: choice) > 0;
  }
  if (source == 'monochrome') {
    await MusicSources.instance.load();
  } else {
    await Spotiflac.instance.load();
  }
  if (!context.mounted) return false;
  final available = source == 'monochrome'
      ? MusicSources.instance.monochrome
      : Spotiflac.instance.searchProviders.any((p) => p['id'] == source && p['has_download_provider'] == true);
  if (!available) {
    final name = source == 'monochrome' ? 'Monochrome' : Spotiflac.instance.nameOf(source);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.sourceUnavailable(name))));
    return false;
  }
  final match = await showDialog<({Track track, String? quality})>(
    context: context,
    builder: (_) => _MatchDialog(origin: origin, source: source),
  );
  if (match == null) return false;
  return player.youtube.enqueueTracks([match.track], youtubeOrigin: origin, extensionQuality: match.quality) > 0;
}

class _MatchDialog extends StatefulWidget {
  const _MatchDialog({required this.origin, required this.source});
  final Track origin;
  final String source;
  @override
  State<_MatchDialog> createState() => _MatchDialogState();
}

class _MatchDialogState extends State<_MatchDialog> {
  late final query = TextEditingController(text: '${widget.origin.title} ${widget.origin.artist}');
  List<Track> matches = [];
  Track? selected;
  late String quality = Spotiflac.instance.qualityOf(widget.source);
  List<Map> get qualityOptions =>
      (Spotiflac.instance.plugin(widget.source)?['quality_options'] as List? ?? []).whereType<Map>().toList();
  bool loading = true, failed = false;
  int run = 0;
  @override
  void initState() {
    super.initState();
    search();
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> search() async {
    final request = ++run;
    setState(() {
      loading = true;
      failed = false;
      selected = null;
      matches = [];
    });
    try {
      final found = widget.source == 'monochrome'
          ? await Monochrome.instance.search(query.text.trim(), limit: 30)
          : await Spotiflac.instance.search(query.text.trim(), provider: widget.source);
      if (!mounted || request != run) return;
      setState(() {
        matches = DownloadMatches.rank(widget.origin, found);
        loading = false;
      });
    } catch (_) {
      if (mounted && request == run) {
        setState(() {
          failed = true;
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: tr.downloadMatchTitle(
      widget.source == 'monochrome' ? 'Monochrome' : Spotiflac.instance.nameOf(widget.source),
    ),
    width: 560,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.origin.title, style: Theme.of(context).textTheme.titleMedium),
        Text(tr.downloadMatchReview),
        const SizedBox(height: 12),
        TextField(
          controller: query,
          onSubmitted: (_) => search(),
          decoration: InputDecoration(
            labelText: tr.navSearch,
            suffixIcon: IconButton(
              tooltip: tr.navSearch,
              onPressed: loading ? null : search,
              icon: const Icon(Icons.search),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (widget.source != 'monochrome' && qualityOptions.isNotEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr.spotiflacQuality),
            trailing: OptionPicker<String>(
              value: quality,
              options: [
                for (final option in qualityOptions)
                  (option['id'].toString(), (option['label'] ?? option['id']).toString()),
              ],
              onChanged: (value) => setState(() => quality = value),
            ),
          ),
        if (loading) const LinearProgressIndicator(),
        if (failed) Text(tr.downloadMatchFailed),
        if (!loading && !failed && matches.isEmpty) Text(tr.downloadMatchEmpty),
        for (final match in matches)
          ListTile(
            leading: Artwork(track: match, size: 44),
            title: Text(match.title),
            subtitle: Text(
              [
                match.artist,
                ?match.album,
                if (match.duration != null) formatDuration(match.duration),
                ?match.extensionQualityLabel,
                if (match.monochromeId != null) 'FLAC',
              ].join(' · '),
            ),
            trailing: Icon(selected?.id == match.id ? Icons.radio_button_checked : Icons.radio_button_unchecked),
            selected: selected?.id == match.id,
            onTap: () => setState(() => selected = match),
          ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.cancel)),
      FilledButton(
        onPressed: selected == null || loading
            ? null
            : () => Navigator.pop(context, (
                track: selected!,
                quality: widget.source == 'monochrome' || qualityOptions.isEmpty ? null : quality,
              )),
        child: Text(tr.download),
      ),
    ],
  );
}
