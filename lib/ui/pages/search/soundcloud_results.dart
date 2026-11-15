import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/track.dart';
import '../../../platform/features.dart';
import '../../../services/language.dart';
import '../../../services/player_controller.dart';
import '../../../services/soundcloud.dart';
import '../../../services/sources/music_sources.dart';
import '../../../services/spotiflac.dart';
import '../../shell_scope.dart';
import '../../soundcloud_pages.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/shelf.dart';
import '../../widgets/track_row.dart';
import 'search_parts.dart';

/// Where Search looks online: YouTube Music (the default), SoundCloud or Monochrome. The library is always
/// searched too.
enum SearchSource {
  youtubeMusic,
  soundcloud,
  monochrome,
  extensions;

  String get label => switch (this) {
    youtubeMusic => tr.sourceYoutubeMusic,
    soundcloud => tr.sourceSoundcloud,
    monochrome => tr.sourceMonochrome,
    extensions => Spotiflac.instance.selectedName,
  };

  String get command => switch (this) {
    youtubeMusic => ':yt',
    soundcloud => ':sc',
    monochrome => ':mc',
    extensions => '',
  };

  static ({SearchSource source, String query})? readCommand(String text) {
    final match = RegExp(r'^\s*:(yt|sc|mc)(?:\s+|$)', caseSensitive: false).firstMatch(text);
    if (match == null) return null;
    final source = switch (match[1]!.toLowerCase()) {
      'sc' => soundcloud,
      'mc' => monochrome,
      _ => youtubeMusic,
    };
    return (source: source, query: text.substring(match.end));
  }

  static List<SearchSource> commandSuggestions(String text) {
    final typed = text.trimLeft().toLowerCase();
    if (!RegExp(r'^:[a-z]*$').hasMatch(typed)) return const [];
    return available.where((s) => s != extensions && s.command.startsWith(typed)).toList();
  }

  static const _key = 'search.source.v1';

  /// The source in use, shared by Search's filters and results.
  static final current = ValueNotifier<SearchSource>(youtubeMusic);

  static bool _loaded = false;
  static List<SearchSource> get available => [
    youtubeMusic,
    if (Features.soundcloud && MusicSources.instance.soundcloud) soundcloud,
    if (MusicSources.instance.monochrome) monochrome,
    if (Spotiflac.instance.searchProviders.isNotEmpty) extensions,
  ];

  static void ensureAvailable() {
    if (!available.contains(current.value)) youtubeMusic.choose();
  }

  /// Reads the choice last made, once (YouTube Music until one is; an older saved "both" is YouTube Music).
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    await MusicSources.instance.load();
    await Spotiflac.instance.load();
    final saved = (await SharedPreferences.getInstance()).getString(_key);
    final source = values.where((s) => s.name == saved).firstOrNull ?? youtubeMusic;
    current.value = available.contains(source) ? source : youtubeMusic;
  }

  /// Makes this the source, and remembers it.
  void choose() {
    if (!available.contains(this)) return;
    current.value = this;
    SharedPreferences.getInstance().then((p) => p.setString(_key, name)).ignore();
  }

  @visibleForTesting
  static void reset() {
    _loaded = false;
    current.value = youtubeMusic;
  }
}

/// Named filters below the search field, limited to the services enabled in Settings.
class SearchSourceFilters extends StatefulWidget {
  const SearchSourceFilters({super.key, this.onSelected});
  final ValueChanged<SearchSource>? onSelected;

  @override
  State<SearchSourceFilters> createState() => _SearchSourceFiltersState();
}

class _SearchSourceFiltersState extends State<SearchSourceFilters> {
  @override
  void initState() {
    super.initState();
    SearchSource.load().ignore();
    MusicSources.instance.addListener(_sourcesChanged);
    Spotiflac.instance.addListener(_sourcesChanged);
  }

  void _sourcesChanged() {
    SearchSource.ensureAvailable();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    MusicSources.instance.removeListener(_sourcesChanged);
    Spotiflac.instance.removeListener(_sourcesChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: SearchSource.current,
    builder: (context, source, _) {
      final available = SearchSource.available;
      if (available.length < 2) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: SearchChips(
          children: [
            for (final service in available.where((s) => s != SearchSource.extensions))
              ChoiceChip(
                key: ValueKey('search-source-${service.name}'),
                label: Text(service.label),
                selected: service == source,
                onSelected: (_) {
                  final select = widget.onSelected;
                  if (select == null) {
                    service.choose();
                  } else {
                    select(service);
                  }
                },
              ),
            for (final plugin in Spotiflac.instance.searchProviders)
              ChoiceChip(
                key: ValueKey('search-source-extension-${plugin['id']}'),
                label: Text(Spotiflac.instance.nameOf(plugin['id'])),
                selected: source == SearchSource.extensions && Spotiflac.instance.selected == plugin['id'],
                onSelected: (_) async {
                  await Spotiflac.instance.choose(plugin['id']);
                  if (!mounted) return;
                  final select = widget.onSelected;
                  if (select != null) {
                    select(SearchSource.extensions);
                  } else {
                    SearchSource.extensions.choose();
                  }
                },
              ),
          ],
        ),
      );
    },
  );
}

/// The first SoundCloud tracks for the query, above its artist and playlist shelves when SoundCloud is selected.
class SoundcloudSection extends StatelessWidget {
  const SoundcloudSection({super.key, required this.future, this.count = 5, this.title});

  final Future<List<Track>>? future;
  final int count;

  /// The heading; "On SoundCloud" when null.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    final shell = ShellScope.of(context);
    final pad = shell.compact ? 16.0 : 24.0;
    return FutureBuilder<List<Track>>(
      future: future,
      builder: (context, snap) {
        final loading = future == null || snap.connectionState != ConnectionState.done;
        final tracks = snap.data ?? const <Track>[];
        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(child: SectionTitle(title ?? tr.onSoundcloud)),
            if (loading)
              SearchSpinner(pad: pad)
            else if (snap.hasError || tracks.isEmpty)
              SearchNote(snap.hasError ? tr.soundcloudSearchFailed : tr.noSoundcloudResults, pad: pad)
            else
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: shell.compact ? 12 : 16),
                sliver: SliverList.builder(
                  itemCount: tracks.length.clamp(0, count),
                  itemBuilder: (context, i) => maybeFade(
                    i,
                    TrackRow(
                      track: tracks[i],
                      showAlbum: false,
                      onTap: () => c.playList(tracks, i, from: tr.soundcloudSearchSource),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// SoundCloud's artists and playlists for the query, as shelves of cards.
class SoundcloudShelves extends StatelessWidget {
  const SoundcloudShelves({super.key, required this.future});

  final Future<({List<SoundcloudCollection> playlists, List<SoundcloudCollection> users})>? future;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: future,
    builder: (context, snap) {
      final r = snap.data;
      if (r == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
      return SliverMainAxisGroup(
        slivers: [
          if (r.users.isNotEmpty)
            SliverToBoxAdapter(
              child: Shelf(
                title: tr.soundcloudArtists,
                cards: [for (final u in r.users) SoundcloudCard(collection: u)],
              ),
            ),
          if (r.playlists.isNotEmpty)
            SliverToBoxAdapter(
              child: Shelf(
                title: tr.soundcloudPlaylists,
                cards: [for (final p in r.playlists) SoundcloudCard(collection: p)],
              ),
            ),
        ],
      );
    },
  );
}
