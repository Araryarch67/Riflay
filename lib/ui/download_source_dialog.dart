import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/download_matches.dart';
import '../services/language.dart';
import '../services/monochrome.dart';
import '../services/player_controller.dart';
import '../services/sources/music_sources.dart';
import '../services/spotiflac.dart';
import 'download_options.dart';
import 'widgets/app_dialog.dart';
import 'widgets/controls.dart' show Artwork, formatDuration;

/// Chooses an audio provider for a single YouTube song. The default provider
/// retains its existing format dialog and preferences.
Future<bool> downloadFromSource(
  BuildContext context,
  PlayerController player,
  Track origin, {
  bool force = false,
}) async {
  await Future.wait([MusicSources.instance.load(), Spotiflac.instance.load()]);
  if (!context.mounted) return false;
  final providers = Spotiflac.instance.searchProviders
      .where((provider) => provider['has_download_provider'] == true)
      .toList();
  if (!MusicSources.instance.monochrome && providers.isEmpty) {
    final choice = await chooseDownload(context, force: force, videoId: origin.videoId, track: origin);
    if (choice == null) return false;
    return player.youtube.enqueueTracks([origin], choice: choice) > 0;
  }
  final source = await showDialog<String>(
    context: context,
    builder: (context) => AppDialog(
      title: tr.downloadSource,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: const Text('YouTube Music'), onTap: () => Navigator.pop(context, 'youtube')),
          if (MusicSources.instance.monochrome)
            ListTile(title: const Text('Monochrome'), onTap: () => Navigator.pop(context, 'monochrome')),
          for (final provider in providers)
            ListTile(
              title: Text(Spotiflac.instance.nameOf(provider['id'])),
              onTap: () => Navigator.pop(context, provider['id']),
            ),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.cancel))],
    ),
  );
  if (source == null || !context.mounted) return false;
  if (source == 'youtube') {
    final choice = await chooseDownload(context, force: force, videoId: origin.videoId, track: origin);
    if (choice == null) return false;
    return player.youtube.enqueueTracks([origin], choice: choice) > 0;
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
          DropdownButtonFormField<String>(
            initialValue: quality,
            decoration: InputDecoration(labelText: tr.spotiflacQuality),
            items: [
              for (final option in qualityOptions)
                DropdownMenuItem(
                  value: option['id'].toString(),
                  child: Text((option['label'] ?? option['id']).toString()),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => quality = value);
            },
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
            : () => Navigator.pop(context, (track: selected!, quality: widget.source == 'monochrome' ? null : quality)),
        child: Text(tr.download),
      ),
    ],
  );
}
