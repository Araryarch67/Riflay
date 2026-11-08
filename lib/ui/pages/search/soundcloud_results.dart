import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/track.dart';
import '../../../services/language.dart';
import '../../../services/player_controller.dart';
import '../../shell_scope.dart';
import '../../theme.dart';
import '../../widgets/controls.dart';
import '../../widgets/menus.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/track_row.dart';
import 'search_parts.dart';

/// Where Search looks online: YouTube Music, SoundCloud or both. The library is always searched too.
enum SearchSource {
  youtubeMusic,
  soundcloud,
  both;

  bool get youtube => this != soundcloud;
  bool get usesSoundcloud => this != youtubeMusic;

  String get label => switch (this) {
    youtubeMusic => tr.sourceYoutubeMusic,
    soundcloud => tr.sourceSoundcloud,
    both => tr.sourceBoth,
  };

  static const _key = 'search.source.v1';

  /// The choice last made (YouTube Music until one is).
  static Future<SearchSource> load() async {
    final saved = (await SharedPreferences.getInstance()).getString(_key);
    return values.where((s) => s.name == saved).firstOrNull ?? youtubeMusic;
  }

  Future<void> save() async => (await SharedPreferences.getInstance()).setString(_key, name);
}

/// Picks [SearchSource]: a small button showing the current choice's mark, beside Songs / Videos (no row of its
/// own, so the results start as high as before), opening a menu of the three.
class SearchSourceChoice extends StatelessWidget {
  const SearchSourceChoice({super.key, required this.value, required this.onChanged});

  final SearchSource value;
  final ValueChanged<SearchSource> onChanged;

  static Widget mark(SearchSource s, {double size = 18}) => switch (s) {
    SearchSource.youtubeMusic => SourceMark(online: true, source: TrackSource.youtubeMusic, size: size),
    SearchSource.soundcloud => SourceMark(online: true, source: TrackSource.soundcloud, size: size),
    SearchSource.both => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SourceMark(online: true, source: TrackSource.youtubeMusic, size: size),
        const SizedBox(width: 2),
        SourceMark(online: true, source: TrackSource.soundcloud, size: size),
      ],
    ),
  };

  @override
  Widget build(BuildContext context) => PopupMenuButton<SearchSource>(
    tooltip: tr.searchSourceTooltip,
    initialValue: value,
    onSelected: onChanged,
    itemBuilder: (_) => [
      for (final s in SearchSource.values)
        PopupMenuItem(
          value: s,
          child: MenuRow(leading: mark(s, size: 20), title: Text(s.label)),
        ),
    ],
    child: _button(context),
  );

  Widget _button(BuildContext context) {
    final colors = AppColors.of(context);
    // Phones: the mark alone, small enough to stay beside Songs / Videos on a 320 px screen.
    final compact = ShellScope.of(context).compact;
    return Container(
      height: 40,
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 12),
      decoration: BoxDecoration(
        border: Border.all(color: colors.textMuted.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          mark(value, size: compact && value == SearchSource.both ? 14 : 18),
          if (!compact) ...[
            const SizedBox(width: 8),
            Text(value.label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down_rounded, size: 20, color: colors.textSecondary),
          ],
        ],
      ),
    );
  }
}

/// "All" with both sources: the first SoundCloud tracks under YouTube Music's.
class SoundcloudSection extends StatelessWidget {
  const SoundcloudSection({super.key, required this.future, this.count = 5});

  final Future<List<Track>>? future;
  final int count;

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
            SliverToBoxAdapter(child: SectionTitle(tr.onSoundcloud)),
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
