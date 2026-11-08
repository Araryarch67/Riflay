import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/track.dart';
import '../../../services/language.dart';
import '../../../services/player_controller.dart';
import '../../../services/soundcloud.dart';
import '../../shell_scope.dart';
import '../../soundcloud_pages.dart';
import '../../theme.dart';
import '../../widgets/controls.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/shelf.dart';
import '../../widgets/track_row.dart';
import 'search_parts.dart';

/// Where Search looks online: YouTube Music (the default) or SoundCloud, one at a time. The library is always
/// searched too.
enum SearchSource {
  youtubeMusic,
  soundcloud;

  String get label => switch (this) {
    youtubeMusic => tr.sourceYoutubeMusic,
    soundcloud => tr.sourceSoundcloud,
  };

  static const _key = 'search.source.v1';

  /// The source in use, shared by the switch (the desktop top bar, the phone's search page) and the search page.
  static final current = ValueNotifier<SearchSource>(youtubeMusic);

  static bool _loaded = false;

  /// Reads the choice last made, once (YouTube Music until one is; an older saved "both" is YouTube Music).
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final saved = (await SharedPreferences.getInstance()).getString(_key);
    current.value = values.where((s) => s.name == saved).firstOrNull ?? youtubeMusic;
  }

  /// Makes this the source, and remembers it.
  void choose() {
    current.value = this;
    SharedPreferences.getInstance().then((p) => p.setString(_key, name)).ignore();
  }

  @visibleForTesting
  static void reset() {
    _loaded = false;
    current.value = youtubeMusic;
  }
}

/// The switch between YouTube Music and SoundCloud: a pill with both marks, the source in use filled. A tap
/// switches to the other one. On computers it sits in the top bar beside the search box; on phones beside the
/// search page's title.
class SearchSourceToggle extends StatefulWidget {
  const SearchSourceToggle({super.key, this.height = 40});

  final double height;

  @override
  State<SearchSourceToggle> createState() => _SearchSourceToggleState();
}

class _SearchSourceToggleState extends State<SearchSourceToggle> {
  @override
  void initState() {
    super.initState();
    SearchSource.load().ignore();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: SearchSource.current,
    builder: (context, source, _) {
      final colors = AppColors.of(context);
      final next = source == SearchSource.youtubeMusic ? SearchSource.soundcloud : SearchSource.youtubeMusic;
      Widget half(SearchSource s, TrackSource service) {
        final on = s == source;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: widget.height + 4,
          height: widget.height - 8,
          decoration: BoxDecoration(
            color: on ? colors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(widget.height),
          ),
          alignment: Alignment.center,
          child: SourceMark(
            online: true,
            source: service,
            size: 18,
            tooltip: false,
            color: on ? colors.onAccent : colors.textSecondary,
          ),
        );
      }

      return Tooltip(
        message: tr.searchOnSource(next.label),
        child: Semantics(
          button: true,
          toggled: source == SearchSource.soundcloud,
          label: tr.searchOnSource(source.label),
          child: Material(
            color: colors.tile,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: next.choose,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    half(SearchSource.youtubeMusic, TrackSource.youtubeMusic),
                    half(SearchSource.soundcloud, TrackSource.soundcloud),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// The first SoundCloud tracks for the query: under YouTube Music's with both sources, on their own (as Songs, above
/// SoundCloud's artists and playlists) with SoundCloud alone.
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
