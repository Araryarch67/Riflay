import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/language.dart';
import '../../services/monochrome.dart';
import '../../services/player_controller.dart';
import '../../platform/features.dart';
import '../widgets/page_scaffold.dart';
import 'collection_page.dart';

/// Public Monochrome collections can be played, or copied into a Riflay playlist.
class MonochromePage extends StatefulWidget {
  const MonochromePage({super.key, required this.link});
  final MonochromeLink link;

  @override
  State<MonochromePage> createState() => _MonochromePageState();
}

class _MonochromePageState extends State<MonochromePage> {
  late Future<MonochromeCollection> _page = Monochrome.instance.resolve(widget.link);
  bool _saved = false;

  @override
  Widget build(BuildContext context) => FutureBuilder<MonochromeCollection>(
    future: _page,
    builder: (context, snap) {
      if (snap.hasError) debugPrint('Monochrome collection: ${snap.error}');
      final page = snap.data;
      if (page == null || page.tracks.isEmpty) {
        return PageScaffold(
          title: 'Monochrome',
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: snap.connectionState != ConnectionState.done
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        children: [
                          Text(snap.hasError ? tr.sourceUnavailable('Monochrome') : tr.playlistEmptyOrPrivate),
                          TextButton(
                            onPressed: () => setState(() => _page = Monochrome.instance.resolve(widget.link)),
                            child: Text(tr.retry),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        );
      }
      return CollectionPage(
        collection: Collection(
          kind: CollectionKind.album,
          title: page.title,
          subtitle: 'Monochrome',
          tracks: page.tracks,
        ),
        actions: [
          if (Features.downloads)
            OutlinedButton.icon(
              icon: const Icon(Icons.download_for_offline_outlined),
              label: Text(tr.downloadAllOffline),
              onPressed: () {
                final n = PlayerScope.read(context).youtube.enqueueTracks(page.tracks);
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(n == 0 ? tr.alreadyDownloaded : tr.downloadingSongs(n))));
              },
            ),
          OutlinedButton.icon(
            icon: const Icon(Icons.playlist_add_rounded),
            label: Text(tr.saveAsPlaylist),
            onPressed: _saved
                ? null
                : () {
                    PlayerScope.read(context).createPlaylist(page.title, tracks: page.tracks);
                    setState(() => _saved = true);
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(tr.createdPlaylistWith(page.title, page.tracks.length))));
                  },
          ),
        ],
      );
    },
  );
}
