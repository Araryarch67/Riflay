import 'package:flutter/material.dart';

import '../../../models/track.dart';
import '../../../services/language.dart';
import '../../../services/player_controller.dart';
import '../../../services/spotiflac.dart';
import '../../shell_scope.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/track_row.dart';
import 'search_parts.dart';

/// The selected Monochrome source: full song rows with playback and download controls.
class MonochromeSection extends StatelessWidget {
  const MonochromeSection({super.key, required this.future, this.source, this.onRetry, this.onVerify});
  final Future<List<Track>>? future;
  final String? source;
  final VoidCallback? onRetry;
  final VoidCallback? onVerify;

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
        final error = loading ? null : snap.error;
        final needsVerification = error is SpotiflacError && error.verificationRequired && onVerify != null;
        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(child: SectionTitle(label)),
            if (loading)
              SearchSpinner(pad: pad)
            else if (error != null || tracks.isEmpty) ...[
              SearchNote(error != null ? tr.sourceUnavailable(label) : tr.noSourceResults(label), pad: pad),
              if (onRetry != null || needsVerification)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: pad),
                    child: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (needsVerification)
                          FilledButton.tonalIcon(
                            onPressed: onVerify,
                            icon: const Icon(Icons.verified_user_outlined),
                            label: Text(tr.spotiflacVerify),
                          ),
                        if (onRetry != null)
                          TextButton.icon(
                            onPressed: onRetry,
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(tr.retry),
                          ),
                      ],
                    ),
                  ),
                ),
            ] else
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: shell.compact ? 12 : 16),
                sliver: SliverList.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, i) => TrackRow(
                    track: tracks[i],
                    onTap: () => playSearchHit(PlayerScope.read(context), tracks[i], from: label),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
