// A line (or a few) of a song's lyrics as a card to share, drawn the way Wrap's cards are.
part of '../wrap_page.dart';

/// Opens the card maker on [lines] of [track]'s lyrics, with the line at [initial] picked.
Future<void> showLyricCard(BuildContext context, {required Track track, required List<String> lines, int initial = 0}) {
  final c = PlayerScope.read(context);
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => PlayerScope(
        controller: c,
        child: LyricCardPage(track: track, lines: lines, initial: initial),
      ),
    ),
  );
}

/// The card maker: the card as it will be saved, and the song's lines to pick from (up to [maxLines], kept in the
/// song's order).
class LyricCardPage extends StatefulWidget {
  const LyricCardPage({super.key, required this.track, required this.lines, this.initial = 0});

  final Track track;
  final List<String> lines;
  final int initial;

  static const maxLines = 4;

  @override
  State<LyricCardPage> createState() => _LyricCardPageState();
}

class _LyricCardPageState extends State<LyricCardPage> {
  final _card = GlobalKey();
  late final Set<int> _picked = {if (widget.initial >= 0 && widget.initial < widget.lines.length) widget.initial};

  List<String> get _text => [
    for (final i in _picked.toList()..sort())
      if (widget.lines[i].trim().isNotEmpty) widget.lines[i].trim(),
  ];

  String get _fileName {
    final name = '${widget.track.title} - ${_text.firstOrNull ?? ''}'.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    return 'Riflay Lyrics ${name.length > 80 ? name.substring(0, 80) : name}.png';
  }

  String get _caption => tr.lyricCardCaption(
    _text.join(' / '),
    widget.track.title,
    widget.track.artist.isEmpty ? 'Riflay' : widget.track.artist,
  );

  void _toggle(int i) => setState(() {
    if (!_picked.remove(i) && _picked.length < LyricCardPage.maxLines) _picked.add(i);
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final t = widget.track;
    return AccentBuilder(
      track: t,
      builder: (context, accent) => Scaffold(
        backgroundColor: AppColors.panel,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(tr.shareLyrics),
          leading: IconButton(
            tooltip: tr.close,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth > 760;
              final card = Center(
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: RepaintBoundary(
                    key: _card,
                    child: _LyricCard(track: t, lines: _text, accent: accent),
                  ),
                ),
              );
              final picker = _LinePicker(lines: widget.lines, picked: _picked, onToggle: _toggle);
              final buttons = Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _text.isEmpty
                        ? null
                        : () => _shareCard(
                            context,
                            () => _renderCard(_card),
                            _fileName,
                            caption: _caption,
                            subject: 'Riflay Lyrics',
                          ),
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    label: Text(tr.share),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: _text.isEmpty ? null : () => _saveCard(context, () => _renderCard(_card), _fileName),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text(tr.saveImage),
                  ),
                ],
              );
              final hint = Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text(
                  tr.lyricCardPick(LyricCardPage.maxLines),
                  style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              );
              if (wide) {
                return Row(
                  children: [
                    Expanded(
                      child: Padding(padding: const EdgeInsets.all(16), child: card),
                    ),
                    SizedBox(
                      width: 380,
                      child: Column(
                        children: [
                          hint,
                          Expanded(child: picker),
                          Padding(padding: const EdgeInsets.all(12), child: buttons),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  Expanded(
                    flex: 3,
                    child: Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: card),
                  ),
                  Padding(padding: const EdgeInsets.only(bottom: 4), child: buttons),
                  hint,
                  Expanded(flex: 2, child: picker),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The song's lines, each a tap to put on the card or take off it.
class _LinePicker extends StatelessWidget {
  const _LinePicker({required this.lines, required this.picked, required this.onToggle});

  final List<String> lines;
  final Set<int> picked;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final full = picked.length >= LyricCardPage.maxLines;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final line = lines[i].trim();
        if (line.isEmpty) return const SizedBox.shrink();
        final on = picked.contains(i);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Material(
            color: on ? AppColors.accent.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: on || !full ? () => onToggle(i) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      on ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      size: 20,
                      color: on ? AppColors.accent : AppColors.textMuted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        line,
                        style: text.bodyLarge?.copyWith(
                          fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                          color: on || !full ? AppColors.textPrimary : AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The card: Wrap's backdrop in the cover's colour, the song's cover and name, and its lines, large.
class _LyricCard extends StatelessWidget {
  const _LyricCard({required this.track, required this.lines, required this.accent});

  final Track track;
  final List<String> lines;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final base = AppColors.sink(accent, 0.55);
    final tint = Color.lerp(accent, Colors.white, 0.45)!;
    // Longer quotes come smaller, so four lines still fit.
    final words = lines.join(' ').length;
    final size = words > 150
        ? 22.0
        : words > 90
        ? 26.0
        : words > 45
        ? 30.0
        : 34.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _Backdrop(base: base, glow: accent, seed: track.id.hashCode & 3),
          ),
          Opacity(opacity: 0.28, child: FadedCover(track: track, sharp: false, darken: 0.55)),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.35)],
                stops: const [0.6, 1],
              ),
            ),
          ),
          FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 360,
              height: 640,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                child: _WrapTint(
                  tint: tint,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Brand(month: '', kind: tr.lyrics),
                      const Spacer(),
                      Icon(Icons.format_quote_rounded, size: 44, color: tint.withValues(alpha: 0.8)),
                      const SizedBox(height: 6),
                      for (final line in lines)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (r) => LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Colors.white, Color.lerp(Colors.white, tint, 0.6)!],
                            ).createShader(r),
                            child: Text(
                              line,
                              style: text.headlineSmall?.copyWith(
                                fontSize: size,
                                fontWeight: FontWeight.w900,
                                height: 1.12,
                                letterSpacing: -0.6,
                              ),
                            ),
                          ),
                        ),
                      const Spacer(),
                      Row(
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [BoxShadow(color: tint.withValues(alpha: 0.35), blurRadius: 24)],
                            ),
                            child: Artwork(track: track, size: 64, radius: 8),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                if (track.artist.isNotEmpty)
                                  Text(
                                    track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodyMedium?.copyWith(color: tint),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const _Footer(index: 0, count: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
