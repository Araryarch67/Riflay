// The lyrics view: loading them, the plain (untimed) text and the messages.
part of '../lyrics_page.dart';

/// The lyrics of [track] following the song, without a header or background:
/// the lyrics page and the full-screen player both show it.
class LyricsView extends StatelessWidget {
  const LyricsView({super.key, required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) => ShaderMask(
    // Lines fade out at the edges instead of being cut off.
    blendMode: BlendMode.dstIn,
    shaderCallback: (rect) => const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
      stops: [0, 0.08, 0.92, 1],
    ).createShader(rect),
    child: _LyricsLoader(key: ValueKey(track.id), track: track),
  );
}

class _LyricsLoader extends StatefulWidget {
  const _LyricsLoader({super.key, required this.track});

  final Track track;

  @override
  State<_LyricsLoader> createState() => _LyricsLoaderState();
}

class _LyricsLoaderState extends State<_LyricsLoader> {
  late Future<Lyrics> _lyrics = LyricsService.forTrack(widget.track);

  /// Found before this page opened: shown in its first frame, with no loading bars and no fade-in.
  late Lyrics? _ready = LyricsService.loaded(widget.track);

  @override
  void initState() {
    super.initState();
    _lyricsChanged.addListener(_reload);
  }

  @override
  void dispose() {
    _lyricsChanged.removeListener(_reload);
    super.dispose();
  }

  void _reload() => setState(() {
    _ready = null;
    _lyrics = LyricsService.forTrack(widget.track);
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<Lyrics>(
    future: _lyrics,
    initialData: _ready,
    builder: (context, snap) {
      if (snap.hasError) {
        return _Message(
          tr.lyricsLoadFailed,
          action: TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.textPrimary),
            onPressed: () => setState(() => _lyrics = LyricsService.forTrack(widget.track)),
            child: Text(tr.tryAgain),
          ),
        );
      }
      final lyrics = snap.data;
      if (lyrics == null) return const _LyricsSkeleton();
      if (lyrics.instrumental) return _Message(tr.lyricsInstrumental);
      if (lyrics.isEmpty) {
        return _Message(
          tr.noLyricsFound,
          action: !Features.userLyrics
              ? null
              : TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.textPrimary),
                  onPressed: () => useMyLyricsFile(context, widget.track),
                  child: Text(tr.useMyLyricsFile),
                ),
        );
      }
      final view = lyrics.synced ? _SyncedLyrics(track: widget.track, lyrics: lyrics) : _PlainLyrics(lyrics: lyrics);
      // Already there when the page opened: no fade (and no frames for it).
      return identical(lyrics, _ready) ? view : FadeIn(child: view);
    },
  );
}

/// While lyrics load: grey bars where the lines will be, the size and alignment of the real ones, softly pulsing
/// (still when animations are off).
class _LyricsSkeleton extends StatelessWidget {
  const _LyricsSkeleton();

  /// How wide each bar is, as a share of the width: uneven, like lines of a song.
  static const widths = [0.72, 0.5, 0.86, 0.38, 0.64, 0.8, 0.46, 0.7, 0.58, 0.84, 0.42, 0.66];

  @override
  Widget build(BuildContext context) {
    final size = _lineStyle(context)?.fontSize ?? 24;
    final pad = _isCompact(context) ? 24.0 : 40.0;
    // A real line: its text (1.25 × the size) and 8 px above and below.
    final bar = size * 0.72;
    final gap = size * 1.25 - bar + 16;
    return Semantics(
      label: tr.loadingLyrics,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth - pad * 2;
            final count = box.hasBoundedHeight ? (box.maxHeight / (bar + gap)).ceil().clamp(1, 40) : 8;
            // Never scrolled: only there so the last bar can run past the bottom (where the fade hides it).
            return SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, 24 + 8, pad, 0),
                child: Column(
                  crossAxisAlignment: _centred ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < count; i++)
                      Padding(
                        padding: EdgeInsets.only(bottom: gap),
                        child: SkeletonBox(
                          width: width * _LyricsSkeleton.widths[i % _LyricsSkeleton.widths.length],
                          height: bar,
                          radius: bar / 3,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.message, {this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.textSecondary),
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    ),
  );
}

class _Source extends StatelessWidget {
  const _Source(this.lyrics);

  final Lyrics lyrics;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 32, bottom: 48),
    child: Text(
      tr.lyricsFrom(lyricsSourceLabel(lyrics.source)),
      textAlign: _textAlign,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
    ),
  );
}

class _PlainLyrics extends StatefulWidget {
  const _PlainLyrics({required this.lyrics});

  final Lyrics lyrics;

  @override
  State<_PlainLyrics> createState() => _PlainLyricsState();
}

class _PlainLyricsState extends State<_PlainLyrics> with _Extras {
  @override
  Lyrics get lyrics => widget.lyrics;

  @override
  Widget build(BuildContext context) {
    // Softer than a sung line: untimed lyrics all lit in white read as if every line were selected.
    final style = _lineStyle(context)?.copyWith(color: AppColors.textPrimary.withValues(alpha: 0.8));
    final lines = lyrics.plain!.split('\n');
    return SmoothScroll(
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.symmetric(horizontal: _isCompact(context) ? 24 : 40, vertical: 24),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              tr.lyricsUntimed,
              key: const ValueKey('lyrics-untimed'),
              textAlign: _textAlign,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ),
          if (extras == null)
            Text(lyrics.plain!, style: style, textAlign: _textAlign)
          else
            for (var i = 0; i < lines.length; i++) ...[
              Text(lines[i], style: style, textAlign: _textAlign),
              if (extraFor(i) case final extra?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    extra,
                    style: _extraStyle(context)?.copyWith(color: AppColors.textSecondary),
                    textAlign: _textAlign,
                  ),
                ),
            ],
          _Source(lyrics),
        ],
      ),
    );
  }
}
