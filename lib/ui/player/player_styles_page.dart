import 'package:flutter/material.dart';

import '../../services/appearance.dart';
import '../../services/language.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../../services/player_presets.dart';
import '../pages/layout_settings.dart' show NowPlayingSettings;
import '../pages/player_presets_page.dart' show PresetSchematic, savePresetFromCurrent;
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/live_preview.dart';
import '../widgets/top_bar_surface.dart';
import 'now_playing_page.dart';

/// Opens [PlayerStylesPage] over Now Playing (holding the player).
Future<void> openPlayerStyles(BuildContext context) async {
  if (LivePreview.of(context)) return;
  // Over the whole window, with the player's and the shell's scopes carried along for the Now Playing it draws.
  final shell = ShellScope.of(context);
  final player = PlayerScope.read(context);
  Widget scoped(Widget page) => PlayerScope(
    controller: player,
    child: ShellScope(
      compact: shell.compact,
      width: shell.width,
      history: shell.history,
      open: shell.open,
      openCollection: shell.openCollection,
      openQueue: shell.openQueue,
      openNowPlaying: shell.openNowPlaying,
      openLyrics: shell.openLyrics,
      openDownloads: shell.openDownloads,
      importFromYoutube: shell.importFromYoutube,
      addFiles: shell.addFiles,
      addFolder: shell.addFolder,
      child: page,
    ),
  );
  await Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: LayoutPrefs.dur(const Duration(milliseconds: 260)),
      reverseTransitionDuration: LayoutPrefs.dur(const Duration(milliseconds: 200)),
      pageBuilder: (_, _, _) => scoped(const PlayerStylesPage()),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 1.06, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    ),
  );
}

/// The player presets side by side, Now Playing drawn in the one in the middle: swiping tries a preset on, Set
/// keeps it, Edit keeps it and opens its settings, and Back puts the look as it was.
class PlayerStylesPage extends StatefulWidget {
  const PlayerStylesPage({super.key});

  @override
  State<PlayerStylesPage> createState() => _PlayerStylesPageState();
}

// Dark buttons on the black page: the Now Playing cards are the bright part.
final _dark = Colors.white.withValues(alpha: 0.12);
final _button = FilledButton.styleFrom(
  minimumSize: const Size.fromHeight(52),
  backgroundColor: _dark,
  foregroundColor: Colors.white,
);

class _PlayerStylesPageState extends State<PlayerStylesPage> {
  final _prefs = LayoutPrefs.instance;
  // Taken on opening, before anything is tried on.
  final Map<String, dynamic> _before = LayoutPrefs.instance.toJson();
  final NowPlayingBackground _backgroundBefore = Appearance.instance.nowPlaying;
  late final List<PlayerPreset> _presets = [...PlayerPreset.all, ...CustomPresets.instance.presets];
  late final int _start = () {
    final name = playerPresetName(_prefs);
    final at = _presets.indexWhere((p) => p.name == name);
    return at < 0 ? 0 : at;
  }();
  late var _pages = PageController(viewportFraction: 0.78, initialPage: _start);
  late int _index = _start;

  /// Whether the look on screen is the one picked here, to be kept on leaving.
  bool _keep = false;

  /// Whether a preset has been tried on since opening (nothing to restore otherwise).
  bool _tried = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Leaving any way but Set or Edit (Back, the system's back) puts the look as it was.
  void _left(bool didPop, Object? _) {
    if (didPop && !_keep && _tried) _restore();
  }

  void _restore() {
    _prefs.restoreSnapshot(_before);
    Appearance.instance.setNowPlaying(_backgroundBefore);
  }

  Future<void> _tryOn(int index) async {
    setState(() => _index = index);
    final preset = _presets[index];
    if (preset.matches(_prefs)) return;
    _tried = true;
    await preset.apply(_prefs);
  }

  void _set() {
    _keep = true;
    Navigator.of(context).pop();
  }

  /// Saves the look on screen as one of the person's own presets, which then joins the row (and stays on).
  Future<void> _save() async {
    final preset = await savePresetFromCurrent(context);
    if (preset == null || !mounted) return;
    final at = _presets.indexWhere((p) => p.name.toLowerCase() == preset.name.toLowerCase());
    setState(() {
      at < 0 ? _presets.add(preset) : _presets[at] = preset;
      _index = at < 0 ? _presets.length - 1 : at;
      // What was saved is kept: leaving doesn't put the look from before back.
      _keep = true;
      // The row is built anew (see the PageView's key) on the new card: a row already laid out doesn't lengthen.
      final old = _pages;
      _pages = PageController(viewportFraction: 0.78, initialPage: _index);
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    });
  }

  void _edit() {
    _keep = true;
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          backgroundColor: AppColors.background,
          appBar: RiflayAppBar(title: Text(tr.nowPlayingTitle)),
          body: const SingleChildScrollView(padding: EdgeInsets.fromLTRB(16, 8, 16, 32), child: NowPlayingSettings()),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final size = MediaQuery.sizeOf(context);
    // A card never taller than the screen leaves room for, nor wider than a phone.
    final cardHeight = (size.height - 220).clamp(240.0, 760.0);
    return PopScope(
      onPopInvokedWithResult: _left,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 56,
                width: double.infinity,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      left: 12,
                      child: IconButton.filled(
                        style: IconButton.styleFrom(backgroundColor: _dark, foregroundColor: Colors.white),
                        tooltip: tr.back,
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      child: IconButton.filled(
                        style: IconButton.styleFrom(backgroundColor: _dark, foregroundColor: Colors.white),
                        tooltip: tr.saveAsPreset,
                        onPressed: _save,
                        icon: const Icon(Icons.bookmark_add_outlined),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(tr.styles, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        Text(_presets[_index].name, style: text.labelMedium?.copyWith(color: colors.textSecondary)),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: SizedBox(
                    height: cardHeight,
                    child: PageView.builder(
                      key: ValueKey(_presets.length),
                      controller: _pages,
                      itemCount: _presets.length,
                      onPageChanged: _tryOn,
                      itemBuilder: (context, i) => AnimatedBuilder(
                        animation: _pages,
                        builder: (context, child) {
                          final page = _pages.hasClients && _pages.position.haveDimensions
                              ? _pages.page ?? _index.toDouble()
                              : _index.toDouble();
                          final distance = (page - i).abs().clamp(0.0, 1.0);
                          return Transform.scale(scale: 1 - distance * 0.08, child: child);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: _StyleCard(
                            preset: _presets[i],
                            live: i == _index,
                            onTap: () => _pages.animateToPage(
                              i,
                              duration: LayoutPrefs.dur(const Duration(milliseconds: 280)),
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _Dots(count: _presets.length, index: _index),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonal(style: _button, onPressed: _edit, child: Text(tr.edit)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.tonal(style: _button, onPressed: _set, child: Text(tr.setStyle)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One preset: the real Now Playing (as a still preview) for the one tried on, its drawing for the others.
class _StyleCard extends StatelessWidget {
  const _StyleCard({required this.preset, required this.live, required this.onTap});

  final PlayerPreset preset;
  final bool live;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: !live,
      selected: live,
      label: preset.name,
      child: GestureDetector(
        onTap: live ? null : onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: colors.textPrimary.withValues(alpha: 0.18)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: live
                ? const IgnorePointer(
                    child: LivePreview(canvas: Size(390, 844), child: NowPlayingPage()),
                  )
                : ColoredBox(
                    color: colors.elevated,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Transform.scale(scale: 2.2, child: PresetSchematic(preset: preset)),
                        const SizedBox(height: 72),
                        Text(preset.name, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: LayoutPrefs.dur(const Duration(milliseconds: 200)),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i == index ? colors.textPrimary : colors.textPrimary.withValues(alpha: 0.3),
            ),
          ),
      ],
    );
  }
}
