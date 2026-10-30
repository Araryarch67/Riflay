import 'package:flutter/material.dart';

import '../../services/player_controller.dart';
import '../../services/playlist_transfer.dart';
import '../../services/spotify_account.dart';
import '../../services/spotify_import.dart';
import '../../services/spotify_library.dart';
import '../../services/spotify_session.dart';
import '../../services/ytmusic_web.dart';
import '../playlist_import.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/page_scaffold.dart';
import 'spotify_login_page.dart';

/// Builds the importer for a run. The default one writes to YouTube Music / Riflay.
typedef SpotifyImporterBuilder = SpotifyImporter Function(BuildContext context, SpotifyLibraryClient client);

/// "Spotify library": signs in to Spotify's web player and copies the chosen
/// playlists, Liked Songs and albums into YouTube Music / Riflay. Artists are left
/// out: following them needs edits to the YouTube Music account that aren't safe yet.
class SpotifyPage extends StatefulWidget {
  const SpotifyPage({super.key, this.account, this.importerFor, this.youtubeSignedIn});

  /// Defaults to [SpotifyAccount.instance].
  final SpotifyAccount? account;

  /// Defaults to [defaultImporter].
  final SpotifyImporterBuilder? importerFor;

  /// Whether YouTube Music is signed in; defaults to the player's account.
  final bool? youtubeSignedIn;

  /// An importer that saves into the player's YouTube Music account or Riflay playlists.
  static SpotifyImporter defaultImporter(BuildContext context, SpotifyLibraryClient client) {
    final c = PlayerScope.read(context);
    final yt = c.ytMusic;
    return SpotifyImporter(
      songs: client.songs,
      search: yt.searchSongs,
      videos: yt.searchVideos,
      save: (title, tracks) async {
        await saveImportedPlaylist(c, title, tracks);
      },
      canEdit: yt.canEdit,
      findAlbum: (a) async => SpotifyImporter.pickAlbum(
        a,
        await yt.searchOnly('${a.name} ${a.subtitle ?? ''}'.trim(), WebResultKind.album),
      ),
      saveAlbum: (id) async {
        final state = await yt.saveState(id);
        if (state == null) return false;
        if (!state.saved) await yt.setSaved(id, state, true);
        return true;
      },
      findArtist: (a) async => SpotifyImporter.pickArtist(a, await yt.searchOnly(a.name, WebResultKind.artist)),
      follow: (id) => yt.setFollowing(id, true),
    );
  }

  @override
  State<SpotifyPage> createState() => _SpotifyPageState();
}

enum _Tab { playlists, albums }

class _Loaded {
  List<SpotifyItem>? items;
  String? error;
  var loading = false;
}

class _SpotifyPageState extends State<SpotifyPage> {
  late final SpotifyAccount account = widget.account ?? SpotifyAccount.instance;
  final _tabs = {for (final t in _Tab.values) t: _Loaded()};
  final _selected = <String>{};
  var _tab = _Tab.playlists;
  SpotifyImporter? _importer;

  /// Bumped on every sign-out so a late answer for an old account is dropped.
  var _generation = 0;
  var _wasSignedIn = false;

  @override
  void initState() {
    super.initState();
    account.addListener(_onAccount);
    account.load();
    // Already signed in (the account outlives the page): start reading.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onAccount();
    });
  }

  @override
  void dispose() {
    account.removeListener(_onAccount);
    _importer?.dispose();
    super.dispose();
  }

  void _onAccount() {
    if (!mounted) return;
    if (_wasSignedIn && !account.isSignedIn) {
      _generation++;
      for (final t in _tabs.values) {
        t
          ..items = null
          ..error = null
          ..loading = false;
      }
      _selected.clear();
      _importer?.dispose();
      _importer = null;
    }
    _wasSignedIn = account.isSignedIn;
    setState(() {});
    if (account.isSignedIn && _importer == null) _ensureLoaded(_tab);
  }

  bool get _youtubeSignedIn => widget.youtubeSignedIn ?? PlayerScope.read(context).ytMusic.canEdit;

  Future<void> _ensureLoaded(_Tab tab) async {
    final state = _tabs[tab]!;
    if (state.items != null || state.loading) return;
    final generation = _generation;
    setState(() {
      state
        ..loading = true
        ..error = null;
    });
    try {
      final client = account.client;
      final items = await switch (tab) {
        _Tab.playlists => client.playlists(),
        _Tab.albums => client.albums(),
      };
      if (!mounted || generation != _generation) return;
      setState(() {
        state
          ..items = items
          ..loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      if (e is! SpotifySignedOut) debugPrint('Spotify library: $e');
      setState(() {
        state
          ..loading = false
          ..error = switch (e) {
            PlaylistTransferError(:final message) => message,
            SpotifySignedOut() => SpotifySignedOut.message,
            _ => 'Couldn\'t read your Spotify library right now. Try again later.',
          };
      });
    }
  }

  Future<void> _signIn() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!SpotifyLogin.canSignIn) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            SpotifyLogin.signsInWithHelper
                ? 'Signing in needs WebKitGTK (webkit2gtk-4.1). Install it and restart Riflay.'
                : 'Signing in to Spotify isn\'t available here.',
          ),
        ),
      );
      return;
    }
    if (SpotifyLogin.signsInWithHelper) {
      await account.signInWithWindow();
    } else {
      final session = await Navigator.of(context)
          .push<SpotifySession>(MaterialPageRoute(builder: (_) => const SpotifyLoginPage()));
      if (session != null) await account.connect(session);
    }
  }

  void _selectTab(_Tab tab) {
    setState(() => _tab = tab);
    _ensureLoaded(tab);
  }

  void _start(List<SpotifyItem> items) {
    if (items.isEmpty) return;
    final importer = (widget.importerFor ?? SpotifyPage.defaultImporter)(context, account.client);
    setState(() => _importer = importer);
    importer.addListener(_onImporter);
    importer.run(items);
  }

  void _onImporter() {
    final importer = _importer;
    if (importer == null || !mounted) return;
    final uris = [
      for (final r in importer.results)
        if (r.ok) r.item.uri,
    ];
    if (uris.any((u) => account.importedAt(u) == null)) account.markImported(uris);
    if (!importer.running && importer.signedOut) {
      // The account already signed itself out and says why.
      account.signOut(reason: SpotifySignedOut.message);
      return;
    }
    setState(() {});
  }

  void _finish() {
    setState(() {
      _importer?.dispose();
      _importer = null;
      _selected.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pad = ShellScope.of(context).compact ? 16.0 : 24.0;
    return ListenableBuilder(
      listenable: account,
      builder: (context, _) {
        final importer = _importer;
        final Widget body;
        if (!account.isSignedIn) {
          body = _scaffold(pad, [_signedOut(context)]);
        } else if (importer != null) {
          body = _scaffold(pad, [_ImportPanel(importer: importer, onDone: _finish, pad: pad)]);
        } else {
          body = Column(
            children: [
              Expanded(child: _scaffold(pad, _picker(context, pad))),
              _bottomBar(context, pad),
            ],
          );
        }
        return body;
      },
    );
  }

  Widget _scaffold(double pad, List<Widget> slivers) {
    final text = Theme.of(context).textTheme;
    return PageScaffold(
      title: 'Spotify',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 16),
            child: Row(
              children: [
                Flexible(
                  child: Text('Spotify', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
        ),
        ...slivers,
      ],
    );
  }

  // ── Signed out ──────────────────────────────────────────────────────────

  Widget _signedOut(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: AppColors.textSecondary);
    final pad = ShellScope.of(context).compact ? 16.0 : 24.0;
    return SliverToBoxAdapter(
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Copy your Spotify playlists, Liked Songs and albums into Riflay.', style: text.bodyLarge),
                const SizedBox(height: 8),
                Text('Riflay only reads your library. It never changes your Spotify account.', style: muted),
                const SizedBox(height: 24),
                if (account.busy)
                  const SizedBox(height: 52, child: Center(child: CircularProgressIndicator()))
                else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: _signIn,
                      child: const Text('Sign in with Spotify'),
                    ),
                  ),
                if (account.error != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(account.error!, style: muted)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Picker ──────────────────────────────────────────────────────────────

  List<SpotifyItem> get _items => _tabs[_tab]!.items ?? const [];

  List<SpotifyItem> get _chosen => [
    for (final i in _items)
      if (_selected.contains(i.uri)) i,
  ];

  List<Widget> _picker(BuildContext context, double pad) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.textSecondary);
    final state = _tabs[_tab]!;
    final youtube = _youtubeSignedIn;
    final note = youtube ? 'Playlists go to your YouTube Music library.' : 'Playlists become Riflay playlists.';
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  account.name == null ? 'Signed in to Spotify' : 'Signed in as ${account.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                ),
              ),
              TextButton(onPressed: () => account.signOut(), child: const Text('Sign out')),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad, 4, pad, 8),
          child: SegmentedButton<_Tab>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _Tab.playlists, label: Text('Playlists')),
              ButtonSegment(value: _Tab.albums, label: Text('Albums')),
            ],
            selected: {_tab},
            onSelectionChanged: (v) => _selectTab(v.first),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, 8),
          child: Text(note, style: muted),
        ),
      ),
      if (state.loading || (state.items == null && state.error == null))
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else if (state.error != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: pad, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(state.error!, style: text.bodyMedium?.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                TextButton(onPressed: () => _ensureLoaded(_tab), child: const Text('Try again')),
              ],
            ),
          ),
        )
      else if (state.items!.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: pad, vertical: 16),
            child: Text('Nothing here yet.', style: muted),
          ),
        )
      else
        SliverList.builder(itemCount: state.items!.length, itemBuilder: (context, i) => _row(state.items![i], pad)),
    ];
  }

  Widget _row(SpotifyItem item, double pad) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.textSecondary);
    final imported = account.importedAt(item.uri);
    final subtitle = [
      if (item.subtitle != null && item.subtitle!.isNotEmpty) item.subtitle!,
      if (item.kind != SpotifyItemKind.artist && item.kind != SpotifyItemKind.album && (item.count ?? 0) > 0)
        '${item.count} songs',
    ].join(' · ');
    return CheckboxListTile(
      key: ValueKey(item.uri),
      value: _selected.contains(item.uri),
      onChanged: (v) => setState(() => v == true ? _selected.add(item.uri) : _selected.remove(item.uri)),
      contentPadding: EdgeInsets.symmetric(horizontal: pad),
      controlAffinity: ListTileControlAffinity.trailing,
      secondary: _Cover(item),
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty && imported == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitle.isNotEmpty) Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                if (imported != null) Text('Imported', style: muted?.copyWith(color: AppColors.accent)),
              ],
            ),
    );
  }

  Widget _bottomBar(BuildContext context, double pad) {
    final chosen = _chosen;
    final state = _tabs[_tab]!;
    final all = state.items ?? const <SpotifyItem>[];
    final ready = state.error == null;
    return Material(
      color: AppColors.elevated,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad, 12, pad, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton.tonal(
                onPressed: ready && all.isNotEmpty ? () => _start(all) : null,
                child: const Text('Import all'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: ready && chosen.isNotEmpty ? () => _start(chosen) : null,
                child: Text(chosen.isEmpty ? 'Import' : 'Import ${chosen.length}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover(this.item);

  final SpotifyItem item;

  @override
  Widget build(BuildContext context) {
    final circle = item.kind == SpotifyItemKind.artist;
    final icon = switch (item.kind) {
      SpotifyItemKind.artist => Icons.person_outline_rounded,
      SpotifyItemKind.liked => Icons.favorite_rounded,
      SpotifyItemKind.album => Icons.album_outlined,
      SpotifyItemKind.playlist => Icons.queue_music_rounded,
    };
    Widget fallback() => ColoredBox(
      color: AppColors.tile,
      child: Center(child: Icon(icon, color: AppColors.textSecondary)),
    );
    final url = item.imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(circle ? 24 : 4),
      child: SizedBox(
        width: 48,
        height: 48,
        child: url == null || url.isEmpty
            ? fallback()
            : Image.network(url, fit: BoxFit.cover, cacheWidth: 96, errorBuilder: (_, _, _) => fallback()),
      ),
    );
  }
}

// ── The run and its summary ───────────────────────────────────────────────

class _ImportPanel extends StatelessWidget {
  const _ImportPanel({required this.importer, required this.onDone, required this.pad});

  final SpotifyImporter importer;
  final VoidCallback onDone;
  final double pad;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: ListenableBuilder(
              listenable: importer,
              builder: (context, _) => importer.running ? _progress(context) : _summary(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _progress(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: AppColors.textSecondary);
    final item = importer.current;
    final finding = importer.matchTotal > 0 && item?.kind != SpotifyItemKind.artist;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item == null ? 'Importing' : '${importer.positionLabel} · ${item.name}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          importer.cancelled
              ? 'Stopping…'
              : finding
              ? 'Finding songs in YouTube Music: ${importer.matched} of ${importer.matchTotal}'
              : item?.kind == SpotifyItemKind.artist
              ? 'Finding the artist in YouTube Music…'
              : 'Reading the songs…',
          style: muted,
        ),
        const SizedBox(height: 16),
        LinearProgressIndicator(value: finding ? importer.matched / importer.matchTotal : null),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: importer.cancelled ? null : importer.cancel, child: const Text('Cancel')),
        ),
      ],
    );
  }

  Widget _summary(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.textSecondary);
    final withMissing = [
      for (final r in importer.results)
        if (r.missing.isNotEmpty) r,
    ];
    final planned = importer.cancelled ? importer.results.length : importer.count;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Imported ${importer.succeeded} of $planned',
          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (importer.cancelled) ...[const SizedBox(height: 4), Text('You stopped the import.', style: muted)],
        const SizedBox(height: 16),
        for (final r in importer.results)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  r.ok ? Icons.check_rounded : Icons.remove_rounded,
                  size: 18,
                  color: r.ok ? AppColors.accent : AppColors.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(r.line, style: text.bodyMedium)),
              ],
            ),
          ),
        if (withMissing.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final r in withMissing)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text(
                  '${r.item.name}: ${r.missing.length} ${r.missing.length == 1 ? 'song' : 'songs'} not found',
                  style: text.bodyMedium,
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final s in r.missing)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text('$s', maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 24),
        FilledButton(onPressed: onDone, child: const Text('Done')),
      ],
    );
  }
}
