import 'package:flutter/material.dart';

import '../../../services/extensions/extension_finds.dart';
import '../../../services/extensions/extension_store.dart';
import '../../../services/player_controller.dart';
import '../../../services/playlist_transfer.dart';
import '../../shell_scope.dart';
import '../../theme.dart';
import '../../widgets/controls.dart';
import '../../widgets/page_scaffold.dart';
import 'search_parts.dart';

/// One enabled extension's answer to a search; never fails (a failure is [error]).
typedef ExtensionSearch = ({InstalledExtension ext, Future<({List<ExtensionSearchHit> hits, String? error})> result});

/// Asks every enabled, searching extension for [query] at once. Made when the search goes out, not in a build.
List<ExtensionSearch> startExtensionSearches(String query, {ExtensionStore? store, int limit = 6}) {
  final s = store ?? ExtensionStore.instance;
  return [
    for (final e in s.searchers)
      (
        ext: e,
        result: s
            .search(e.id, query, limit: limit)
            .then<({List<ExtensionSearchHit> hits, String? error})>(
              (hits) => (hits: hits.take(limit).toList(), error: null),
              onError: (Object err) => (hits: const <ExtensionSearchHit>[], error: '$err'),
            ),
      ),
  ];
}

/// Finds [hit] in YouTube Music (its song search, then videos) and plays it.
Future<void> playExtensionHit(BuildContext context, ExtensionSearchHit hit, String from) async {
  final c = PlayerScope.read(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final match = await PlaylistTransfer.match(
      [hit.foreign],
      c.ytMusic.searchSongs,
      videos: c.ytMusic.searchVideos,
      parallel: 1,
    );
    if (match.found.isEmpty) {
      messenger?.showSnackBar(SnackBar(content: Text('Couldn\'t find ${hit.foreign} on YouTube Music')));
      return;
    }
    ExtensionFinds.remember(match.found.first, from);
    await c.playList(match.found, 0, from: from);
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('Couldn\'t play ${hit.title}')));
  }
}

/// "From Apple Music", "From SoundCloud"…: each enabled extension's songs, as it answers.
class ExtensionResults extends StatelessWidget {
  const ExtensionResults({super.key, required this.searches});

  final List<ExtensionSearch> searches;

  @override
  Widget build(BuildContext context) {
    final pad = ShellScope.of(context).compact ? 16.0 : 24.0;
    return SliverMainAxisGroup(
      slivers: [for (final s in searches) _ExtensionSection(search: s, pad: pad)],
    );
  }
}

class _ExtensionSection extends StatelessWidget {
  const _ExtensionSection({required this.search, required this.pad});

  final ExtensionSearch search;
  final double pad;

  @override
  Widget build(BuildContext context) {
    final name = search.ext.manifest.displayName;
    return FutureBuilder(
      future: search.result,
      builder: (context, snap) {
        final title = SliverToBoxAdapter(child: SectionTitle('From $name'));
        if (snap.connectionState != ConnectionState.done) {
          return SliverMainAxisGroup(
            slivers: [
              title,
              SearchSpinner(pad: pad),
            ],
          );
        }
        final (:hits, :error) = snap.data!;
        if (hits.isEmpty) {
          // An extension with nothing to say stays out of the way; a failing one says so in a line.
          if (error == null) return const SliverToBoxAdapter();
          return SliverMainAxisGroup(
            slivers: [
              title,
              SearchNote('$name couldn\'t search: $error', pad: pad),
            ],
          );
        }
        return SliverMainAxisGroup(
          slivers: [
            title,
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: pad - 12),
              sliver: SliverList.builder(
                itemCount: hits.length,
                itemBuilder: (context, i) => maybeFade(i, _HitRow(hit: hits[i], from: name)),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HitRow extends StatelessWidget {
  const _HitRow({required this.hit, required this.from});

  final ExtensionSearchHit hit;
  final String from;

  static String _length(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => ListTile(
    leading: SizedBox.square(dimension: 44, child: Artwork(track: hit.previewTrack, radius: 4)),
    title: Text(hit.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      [if (hit.artist.isNotEmpty) hit.artist, if (hit.album case final a? when a.isNotEmpty) a].join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: AppColors.textSecondary),
    ),
    trailing: hit.duration == null
        ? null
        : Text(_length(hit.duration!), style: TextStyle(color: AppColors.textSecondary)),
    onTap: () => playExtensionHit(context, hit, from),
  );
}
