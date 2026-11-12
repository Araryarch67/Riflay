import 'package:flutter/material.dart';

import '../../../models/track.dart';
import '../../../services/language.dart';
import '../../../services/player_controller.dart';
import '../../../services/sources/internet_archive.dart';
import '../../../services/sources/radio_paradise.dart';
import '../../shell_scope.dart';
import '../../theme.dart';
import '../../widgets/controls.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/track_row.dart';
import 'remote_results.dart' show libraryShelf;

/// Search's "All": recordings on the Internet Archive with FLAC files, as a shelf. Nothing while it loads or when
/// there are none; a line when the archive can't be reached.
class ArchiveResults extends StatelessWidget {
  const ArchiveResults({super.key, required this.future});

  final Future<List<ArchiveItem>> future;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: future,
    builder: (context, snap) {
      final items = snap.data;
      if (items == null || items.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
      return libraryShelf(tr.fromInternetArchive, [
        for (final item in items)
          MediaCard(
            track: item.cover,
            title: item.title,
            subtitle: [if (item.creator.isNotEmpty) item.creator, if (item.year case final y?) '$y'].join(' · '),
            // No service mark: the mark is YouTube Music's or SoundCloud's, and this is neither.
            online: false,
            onTap: () => ShellScope.of(context).open(ArchiveItemPage(item: item)),
          ),
      ]);
    },
  );
}

/// The search page before anything is typed: Radio Paradise's channels in FLAC, each with what plays on it now.
class RadioParadiseShelf extends StatefulWidget {
  const RadioParadiseShelf({super.key});

  @override
  State<RadioParadiseShelf> createState() => _RadioParadiseShelfState();
}

class _RadioParadiseShelfState extends State<RadioParadiseShelf> {
  late final _now = Future.wait([for (final ch in RadioParadise.channels) RadioParadise.nowPlaying(ch)]);

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _now,
    builder: (context, snap) {
      final now = snap.data;
      return libraryShelf(tr.radioParadiseFlac, [
        for (final (i, ch) in RadioParadise.channels.indexed)
          () {
            final song = now?[i];
            // The channel's own cover: there before the song on air is known, and steady as songs change.
            final track = ch.track;
            return MediaCard(
              track: track,
              title: ch.name,
              subtitle: song == null ? 'FLAC · 44.1 kHz' : tr.onAir('${song.artist} – ${song.title}'),
              online: false,
              onTap: () => PlayerScope.read(context).playList([track], 0, from: 'Radio Paradise').ignore(),
            );
          }(),
      ]);
    },
  );
}

/// One Internet Archive recording: its FLAC songs, to play from any of them.
class ArchiveItemPage extends StatefulWidget {
  const ArchiveItemPage({super.key, required this.item});

  final ArchiveItem item;

  @override
  State<ArchiveItemPage> createState() => _ArchiveItemPageState();
}

class _ArchiveItemPageState extends State<ArchiveItemPage> {
  late final Future<List<Track>> _tracks = InternetArchive.instance.tracks(widget.item);

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: AppColors.textSecondary);
    final pad = ShellScope.of(context).compact ? 16.0 : 24.0;
    return PageScaffold(
      title: item.title,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 16),
            child: Text(
              [
                if (item.creator.isNotEmpty) item.creator,
                if (item.year case final y?) '$y',
                'Internet Archive',
              ].join(' · '),
              style: muted,
            ),
          ),
        ),
        FutureBuilder(
          future: _tracks,
          builder: (context, snap) {
            if (snap.hasError) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: pad),
                  child: Text(tr.archiveCouldntLoad('${snap.error}'), style: muted),
                ),
              );
            }
            final tracks = snap.data;
            if (tracks == null) {
              return const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }
            if (tracks.isEmpty) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: pad),
                  child: Text(tr.archiveNoFlac, style: muted),
                ),
              );
            }
            void play(int i) => PlayerScope.read(context).playList(tracks, i, from: item.title).ignore();
            return SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(pad, 0, pad, 12),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FilledButton.icon(
                        onPressed: () => play(0),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(tr.play),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: pad - 12),
                  sliver: SliverList.builder(
                    itemCount: tracks.length,
                    itemBuilder: (context, i) =>
                        TrackRow(track: tracks[i], index: i + 1, showAlbum: false, onTap: () => play(i)),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
