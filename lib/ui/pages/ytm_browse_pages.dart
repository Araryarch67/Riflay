import 'package:flutter/material.dart';

import '../../services/player_controller.dart';
import '../../services/youtube_music_account.dart';
import '../../services/ytmusic_web.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/page_scaffold.dart';
import 'youtube_music_page.dart';

/// "Moods & genres" and "New releases", at the top of YouTube Music's shelves.
class YtmBrowseLinks extends StatelessWidget {
  const YtmBrowseLinks({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final pad = shell.compact ? 16.0 : 24.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 16, pad, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => shell.open(const YtmMoodsPage(), location: 'ytm:moods'),
            icon: const Icon(Icons.mood_rounded),
            label: const Text('Moods & genres'),
          ),
          OutlinedButton.icon(
            onPressed: () => shell.open(const YtmNewReleasesPage(), location: 'ytm:new-releases'),
            icon: const Icon(Icons.new_releases_outlined),
            label: const Text('New releases'),
          ),
        ],
      ),
    );
  }
}

/// A page that loads once, then shows [builder]'s slivers; a calm line if it can't.
class _LoadingPage<T> extends StatefulWidget {
  const _LoadingPage({required this.title, required this.load, required this.builder});

  final String title;
  final Future<T> Function() load;
  final List<Widget> Function(BuildContext context, T data) builder;

  @override
  State<_LoadingPage<T>> createState() => _LoadingPageState<T>();
}

class _LoadingPageState<T> extends State<_LoadingPage<T>> {
  late Future<T> _future = widget.load();

  @override
  Widget build(BuildContext context) {
    final pad = ShellScope.of(context).compact ? 16.0 : 24.0;
    final text = Theme.of(context).textTheme;
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) => PageScaffold(
        title: widget.title,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 12),
              child: Text(
                widget.title,
                style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
              ),
            ),
          ),
          if (snap.hasData)
            ...widget.builder(context, snap.data as T)
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Center(
                  child: snap.hasError
                      ? Column(
                          children: [
                            const Text('Couldn\'t load this page. Check your internet connection.'),
                            TextButton(
                              onPressed: () => setState(() => _future = widget.load()),
                              child: const Text('Try again'),
                            ),
                          ],
                        )
                      : const CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// All moods and genres, as tiles.
class YtmMoodsPage extends StatelessWidget {
  const YtmMoodsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final account = PlayerScope.read(context).ytMusic;
    final shell = ShellScope.of(context);
    final pad = shell.compact ? 16.0 : 24.0;
    return _LoadingPage<List<WebMoodGroup>>(
      title: 'Moods & genres',
      load: account.moodsAndGenres,
      builder: (context, groups) => [
        for (final g in groups) ...[
          SliverToBoxAdapter(child: SectionTitle(g.title)),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 16),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
                mainAxisExtent: 52,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: g.moods.length,
              itemBuilder: (context, i) => _MoodTile(mood: g.moods[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class _MoodTile extends StatelessWidget {
  const _MoodTile({required this.mood});

  final WebMood mood;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.tile,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => ShellScope.of(context).open(YtmMoodPage(mood: mood), location: 'ytm:mood:${mood.params}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              mood.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

/// One mood or genre: its playlists, which open like any other playlist.
class YtmMoodPage extends StatelessWidget {
  const YtmMoodPage({super.key, required this.mood});

  final WebMood mood;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    return _LoadingPage<List<RemoteShelf>>(
      title: mood.title,
      load: () => c.ytMusic.moodShelves(mood.params),
      builder: (context, shelves) => [SliverList.list(children: remoteShelfWidgets(context, c, shelves))],
    );
  }
}

/// New albums, singles and music videos.
class YtmNewReleasesPage extends StatelessWidget {
  const YtmNewReleasesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    return _LoadingPage<List<RemoteShelf>>(
      title: 'New releases',
      load: c.ytMusic.newReleases,
      builder: (context, shelves) => [SliverList.list(children: remoteShelfWidgets(context, c, shelves))],
    );
  }
}

/// "Save to library" / "Remove from library" for an album or a public playlist
/// that isn't the account's own. Hidden when signed out.
class SaveToLibraryButton extends StatefulWidget {
  const SaveToLibraryButton({super.key, required this.browseId});

  final String browseId;

  @override
  State<SaveToLibraryButton> createState() => _SaveToLibraryButtonState();
}

class _SaveToLibraryButtonState extends State<SaveToLibraryButton> {
  late final YoutubeMusicAccount _account = PlayerScope.read(context).ytMusic;
  WebSaveState? _state;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _account.saveState(widget.browseId).then((s) {
      if (mounted) setState(() => _state = s);
    });
  }

  Future<void> _toggle() async {
    final state = _state;
    if (state == null || _busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final saved = !state.saved;
    setState(() => _busy = true);
    try {
      await _account.setSaved(widget.browseId, state, saved);
      if (mounted) setState(() => _state = WebSaveState(playlistId: state.playlistId, saved: saved));
      messenger.showSnackBar(SnackBar(content: Text(saved ? 'Saved to your library' : 'Removed from your library')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(YoutubeMusicAccount.describe(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (!_account.isSignedIn || state == null) return const SizedBox.shrink();
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: BorderSide(color: state.saved ? AppColors.textSecondary : AppColors.textPrimary),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 18),
      ),
      onPressed: _busy ? null : _toggle,
      child: Text(state.saved ? 'Remove from library' : 'Save to library'),
    );
  }
}
