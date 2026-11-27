import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
/// Styles are the phone player's looks: in a wide window (the desktop's player) it opens nothing.
Future<void> openPlayerStyles(BuildContext context) async {
  if (LivePreview.of(context) || !ShellScope.of(context).compact) return;
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

  /// Each preset's real Now Playing, pictured: the cards beside the one tried on show it instead of a drawing.
  /// Only one look can be live at a time (the layout is the app's own), so each is put on once, out of sight, and
  /// pictured.
  final _shots = <String, ui.Image>{};
  final _live = GlobalKey();

  /// While each look is put on to be pictured, the middle card stays the look as it was. A swipe stops the
  /// picturing: what is tried on then is the person's.
  ui.Image? _freeze;
  bool _warming = true;
  int _warmRun = 0;
  Future<void>? _warmStep;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _warm());
  }

  @override
  void dispose() {
    _pages.dispose();
    for (final image in _shots.values) {
      image.dispose();
    }
    super.dispose();
  }

  /// The live card as it looks now, once its covers have had time to come in.
  Future<ui.Image?> _picture() async {
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await WidgetsBinding.instance.endOfFrame;
    final boundary = _live.currentContext?.findRenderObject();
    if (!mounted || boundary is! RenderRepaintBoundary) return null;
    return boundary.toImage(pixelRatio: MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0));
  }

  void _keepShot(String name, ui.Image? image) {
    if (image == null) return;
    if (!mounted) return image.dispose();
    _shots.remove(name)?.dispose();
    _shots[name] = image;
  }

  Future<void> _warm() async {
    final run = _warmRun;
    final here = _presets[_start].name;
    _keepShot(here, await _picture());
    if (!mounted || run != _warmRun) return;
    setState(() => _freeze = _shots[here]);
    var changed = false;
    for (final preset in _presets) {
      if (preset.name == here || preset.matches(_prefs)) continue;
      changed = true;
      await (_warmStep = preset.apply(_prefs));
      final shot = await _picture();
      if (!mounted || run != _warmRun) return shot?.dispose();
      _keepShot(preset.name, shot);
    }
    if (changed) _restore();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    setState(() {
      _freeze = null;
      _warming = false;
    });
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
    if (_warming) {
      _warmRun++;
      await _warmStep;
      if (!mounted) return;
      _warming = false;
      _freeze = null;
      // The picturing may have left another look on: Back has to put the one from before back.
      _tried = true;
    }
    setState(() => _index = index);
    final preset = _presets[index];
    if (preset.matches(_prefs)) return;
    _tried = true;
    await preset.apply(_prefs);
    final shot = await _picture();
    // Still the one on screen: a newer swipe pictures its own.
    if (mounted && _index == index) setState(() => _keepShot(preset.name, shot));
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
                            liveKey: _live,
                            shot: i == _index ? _freeze : _shots[_presets[i].name],
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

/// One preset: the real Now Playing (as a still preview) for the one tried on, its picture for the others, and
/// its drawing only while it has not been pictured yet.
class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.preset,
    required this.live,
    required this.liveKey,
    required this.shot,
    required this.onTap,
  });

  final PlayerPreset preset;
  final bool live;
  final GlobalKey liveKey;

  /// Over the live card: the look it is frozen on while the others are pictured.
  final ui.Image? shot;
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
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      RepaintBoundary(
                        key: liveKey,
                        child: const IgnorePointer(
                          child: LivePreview(canvas: Size(390, 844), child: NowPlayingPage()),
                        ),
                      ),
                      if (shot case final image?) RawImage(image: image, fit: BoxFit.cover),
                    ],
                  )
                : shot != null
                ? RawImage(image: shot, fit: BoxFit.cover)
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
