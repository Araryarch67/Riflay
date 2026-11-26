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

/// The menu at the right edge of a search field.
class SearchSourceButton extends StatefulWidget {
  const SearchSourceButton({super.key, this.onSelected, this.color});
  final ValueChanged<SearchSource>? onSelected;
  final Color? color;

  @override
  State<SearchSourceButton> createState() => _SearchSourceButtonState();
}

class _SearchSourceButtonState extends State<SearchSourceButton> {
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

  PopupMenuItem<(SearchSource, String?)> _item(
    BuildContext context, {
    required String id,
    required (SearchSource, String?) value,
    required String label,
    required bool selected,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = selected ? colors.onSecondaryContainer : colors.onSurface;
    final icon = switch (value.$1) {
      SearchSource.youtubeMusic => Icons.play_circle_outline_rounded,
      SearchSource.soundcloud => Icons.cloud_outlined,
      SearchSource.monochrome => Icons.graphic_eq_rounded,
      SearchSource.extensions => Icons.extension_outlined,
    };
    return PopupMenuItem(
      key: ValueKey('search-source-$id'),
      value: value,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Semantics(
        selected: selected,
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? colors.secondaryContainer : Colors.transparent,
            borderRadius: searchSurfaceCorners(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: selected ? foreground : colors.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(color: foreground),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(width: 18, child: selected ? Icon(Icons.check_rounded, size: 18, color: foreground) : null),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: SearchSource.current,
    builder: (context, source, _) {
      final available = SearchSource.available;
      final colors = Theme.of(context).colorScheme;
      // In the phone's bottom bar there is no room under the button: the menu was pushed back up over it and the
      // search field. There it opens above.
      final box = context.findRenderObject() as RenderBox?;
      final top = box != null && box.hasSize ? box.localToGlobal(Offset.zero).dy : 0.0;
      final above = top > MediaQuery.sizeOf(context).height / 2;
      final items =
          available.where((s) => s != SearchSource.extensions).length + Spotiflac.instance.searchProviders.length;
      final ink = widget.color ?? colors.onSurfaceVariant;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 24, child: VerticalDivider(width: 1, color: ink.withValues(alpha: 0.45))),
          PopupMenuButton<(SearchSource, String?)>(
            key: const ValueKey('search-source-menu'),
            tooltip: '${tr.topicSources} · ${source.label}',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 224, maxWidth: 264),
            color: colors.surfaceContainerHigh,
            surfaceTintColor: Colors.transparent,
            shadowColor: colors.shadow,
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: searchSurfaceCorners(20)),
            clipBehavior: Clip.antiAlias,
            menuPadding: const EdgeInsets.symmetric(vertical: 6),
            position: above ? PopupMenuPosition.over : PopupMenuPosition.under,
            // The menu's own height (48 a row, 6 above and below) and a gap: its foot just over the button.
            offset: above ? Offset(0, -(items * 48.0 + 12 + 8)) : Offset.zero,
            icon: Icon(Icons.inventory_2_outlined, color: ink),
            onSelected: (choice) async {
              final (service, pluginId) = choice;
              if (pluginId != null) {
                if (!Spotiflac.instance.searchProviders.any((p) => p['id'] == pluginId)) return;
                await Spotiflac.instance.choose(pluginId);
              }
              if (!mounted || !SearchSource.available.contains(service)) return;
              final select = widget.onSelected;
              if (select == null) {
                service.choose();
              } else {
                select(service);
              }
            },
            itemBuilder: (context) => [
              for (final service in available.where((s) => s != SearchSource.extensions))
                _item(
                  context,
                  id: service.name,
                  value: (service, null),
                  selected: service == source,
                  label: service.label,
                ),
              for (final plugin in Spotiflac.instance.searchProviders)
                _item(
                  context,
                  id: 'extension-${plugin['id']}',
                  value: (SearchSource.extensions, plugin['id'] as String),
                  selected: source == SearchSource.extensions && Spotiflac.instance.selected == plugin['id'],
                  label: Spotiflac.instance.nameOf(plugin['id']),
                ),
            ],
          ),
        ],
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
