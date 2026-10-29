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
    _lyrics = LyricsService.forTrack(widget.track);
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<Lyrics>(
    future: _lyrics,
    builder: (context, snap) {
      if (snap.hasError) {
        return _Message(
          'Couldn\'t load lyrics. Check your internet connection.',
          action: TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => setState(() => _lyrics = LyricsService.forTrack(widget.track)),
            child: const Text('Try again'),
          ),
        );
      }
      final lyrics = snap.data;
      if (lyrics == null) return const Center(child: CircularProgressIndicator(color: Colors.white));
      if (lyrics.instrumental) return const _Message('This song is instrumental. Enjoy the music.');
      if (lyrics.isEmpty) {
        return _Message(
          'No lyrics found for this song.',
          action: TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => useMyLyricsFile(context, widget.track),
            child: const Text('Use my lyrics file'),
          ),
        );
      }
      return FadeIn(
        child: lyrics.synced ? _SyncedLyrics(track: widget.track, lyrics: lyrics) : _PlainLyrics(lyrics: lyrics),
      );
    },
  );
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
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white70),
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
      'Lyrics from ${lyrics.source}',
      textAlign: _textAlign,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
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
    final style = _lineStyle(context)?.copyWith(color: Colors.white.withValues(alpha: 0.8));
    final lines = lyrics.plain!.split('\n');
    return SmoothScroll(
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.symmetric(horizontal: _isCompact(context) ? 24 : 40, vertical: 24),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'These lyrics don\'t follow the song.',
              key: const ValueKey('lyrics-untimed'),
              textAlign: _textAlign,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
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
                    style: _extraStyle(context)?.copyWith(color: Colors.white70),
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
