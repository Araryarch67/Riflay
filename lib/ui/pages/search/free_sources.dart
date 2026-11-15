import 'package:flutter/material.dart';

import '../../../models/track.dart';
import '../../../services/language.dart';
import '../../../services/player_controller.dart';
import '../../shell_scope.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/track_row.dart';
import 'search_parts.dart';

/// The selected Monochrome source: full song rows with playback and download controls.
class MonochromeSection extends StatelessWidget {
  const MonochromeSection({super.key, required this.future, this.source});
  final Future<List<Track>>? future;
  final String? source;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final pad = shell.compact ? 16.0 : 24.0;
    final label = source ?? tr.sourceMonochrome;
    return FutureBuilder<List<Track>>(
      future: future,
      builder: (context, snap) {
        final loading = future == null || snap.connectionState != ConnectionState.done;
        final tracks = loading ? const <Track>[] : snap.data ?? const <Track>[];
        if (snap.hasError) debugPrint('Monochrome search: ${snap.error}');
        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(child: SectionTitle(label)),
            if (loading)
              SearchSpinner(pad: pad)
            else if (snap.hasError || tracks.isEmpty)
              SearchNote(snap.hasError ? tr.sourceUnavailable(label) : tr.noSourceResults(label), pad: pad)
            else
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: shell.compact ? 12 : 16),
                sliver: SliverList.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, i) => TrackRow(
                    track: tracks[i],
                    onTap: () => PlayerScope.read(context).playList(tracks, i, from: label),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
