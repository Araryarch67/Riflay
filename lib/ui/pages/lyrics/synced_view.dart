// The timed lyrics: the line that follows the song, and the lines that rebuild only when their place changes.
part of '../lyrics_page.dart';

/// The synced lyrics of the playing song, wired to the player.
class _SyncedLyrics extends StatefulWidget {
  const _SyncedLyrics({required this.track, required this.lyrics});

  final Track track;
  final Lyrics lyrics;

  @override
  State<_SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends State<_SyncedLyrics> {
  late final PlayerController _c = PlayerScope.read(context);
  // The person's shift for this song: lyrics a second later are where the song was a second ago.
  late final ValueNotifier<Duration> _shift = LyricsTiming.of(widget.track);
  late final Stream<Duration> _ticks = _c
      .positionUpdates()
      .map((p) => p - _shift.value)
      .asBroadcastStream(onListen: (s) => s.resume(), onCancel: (s) => s.pause());
  late final Stream<Duration> _smooth = _c
      .smoothPosition()
      .map((p) => p - _shift.value)
      .asBroadcastStream(onListen: (s) => s.resume(), onCancel: (s) => s.pause());

  @override
  Widget build(BuildContext context) => SyncedLyricsView(
    lyrics: widget.lyrics,
    ticks: _ticks,
    smoothTicks: _smooth,
    position: () => _c.position - _shift.value,
    length: () => _c.currentTrack?.duration ?? _c.duration,
    onSeek: (to) {
      final at = to + _shift.value;
      _c.seek(at.isNegative ? Duration.zero : at);
      if (!_c.isPlaying) _c.play();
    },
  );
}

/// Lines that follow [ticks], the current one lit. A line with timed words
/// fills word by word, driven by [smoothTicks] (only that line listens to them).
/// Not selectable: a tap seeks, and nothing else happens on a long press.
class SyncedLyricsView extends StatefulWidget {
  const SyncedLyricsView({
    super.key,
    required this.lyrics,
    required this.ticks,
    required this.smoothTicks,
    this.position = _zero,
    this.length,
    required this.onSeek,
  });

  final Lyrics lyrics;

  /// The position a few times a second; the current line changes from it.
  final Stream<Duration> ticks;

  /// The position often enough to glide a word's fill.
  final Stream<Duration> smoothTicks;

  /// Where the song is right now, read when the view opens.
  final Duration Function() position;

  /// How long the song is. A position past it is a stale or bogus value
  /// (the last song's, or a stream still buffering): nothing is sung yet.
  final Duration? Function()? length;

  /// A line was tapped.
  final ValueChanged<Duration> onSeek;

  static Duration _zero() => Duration.zero;

  @override
  State<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<SyncedLyricsView> with _Extras {
  @override
  Lyrics get lyrics => widget.lyrics;

  late final List<GlobalKey> _keys = [for (final _ in widget.lyrics.lines) GlobalKey()];
  final _scroll = SmoothScrollController();
  StreamSubscription<Duration>? _sub;

  /// The line being sung. Only the line that stops being it and the one that
  /// becomes it rebuild ([_LineSlot]); the column is built once.
  final _at = ValueNotifier<int>(-1);

  /// The position as a line is picked for it; null when it can't be trusted.
  Duration? _trusted(Duration p) {
    final end = widget.length?.call();
    if (p < Duration.zero || (end != null && end > Duration.zero && p > end + const Duration(seconds: 2))) return null;
    return p;
  }

  // A little early: a line should light up as it starts, not after.
  int _lineAt(Duration position) {
    final p = _trusted(position);
    return p == null ? -1 : widget.lyrics.lineAt(p + const Duration(milliseconds: 150));
  }

  @override
  void initState() {
    super.initState();
    _at.value = _lineAt(widget.position());
    _follow(_at.value);
    _sub = widget.ticks.listen((p) {
      final at = _lineAt(p);
      if (at != _at.value && mounted) {
        _at.value = at;
        _follow(at);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _showBack.dispose();
    _at.dispose();
    _scroll.dispose();
    super.dispose();
  }

  int _current = -2;

  /// Follow the current line as it changes. Switched off when the person
  /// scrolls by hand; the "Back to current line" button (or a tap on a line)
  /// switches it on again.
  bool _following = true;

  /// The current line is out of view while not following: shows the button.
  final _showBack = ValueNotifier<bool>(false);

  void _scrollToCurrent() {
    final ctx = _current < 0 ? null : _keys[_current].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.35,
      duration: LayoutPrefs.dur(const Duration(milliseconds: 350)),
      curve: Curves.easeOutCubic,
    );
  }

  void _follow(int index) {
    if (index == _current) return;
    _current = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_following) {
        _scrollToCurrent();
      } else {
        _checkVisible();
      }
    });
  }

  /// Whether the current line is on screen, for the button.
  void _checkVisible() {
    final ro = _current < 0 ? null : _keys[_current].currentContext?.findRenderObject();
    final viewport = ro == null ? null : RenderAbstractViewport.maybeOf(ro);
    if (_following || !_scroll.hasClients || ro == null || viewport == null) {
      _showBack.value = false;
      return;
    }
    final top = viewport.getOffsetToReveal(ro, 0).offset;
    final bottom = viewport.getOffsetToReveal(ro, 1).offset;
    final pixels = _scroll.position.pixels;
    _showBack.value = pixels > top + 1 || pixels < bottom - 1;
  }

  void _pauseFollowing() {
    _following = false;
    _checkVisible();
  }

  void _resume() {
    _following = true;
    _showBack.value = false;
    _scrollToCurrent();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lyrics.lines;
    final style = _lineStyle(context);
    final pad = _isCompact(context) ? 24.0 : 40.0;
    final dim = LayoutPrefs.instance.dimUnsungLyrics;
    final unsung = dim ? Colors.black.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.75);
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is UserScrollNotification && n.direction != ScrollDirection.idle) {
          _pauseFollowing();
        } else if (!_following) {
          _checkVisible();
        }
        return false;
      },
      child: Listener(
        // A mouse wheel isn't a drag; it pauses following too.
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) _pauseFollowing();
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(pad, 24, pad, 0),
                child: Column(
                  crossAxisAlignment: _centred ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
                  children: [
                    if (widget.lyrics.otherVersion)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          'Timed for another version of this song. If they run early or late, use Adjust timing in the menu.',
                          key: const ValueKey('lyrics-other-version'),
                          textAlign: _textAlign,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
                        ),
                      ),
                    for (var i = 0; i < lines.length; i++)
                      _LineSlot(
                        key: _keys[i],
                        index: i,
                        at: _at,
                        line: lines[i],
                        extra: extraFor(i),
                        style: style,
                        unsung: unsung,
                        position: widget.position,
                        ticks: widget.smoothTicks,
                        trusted: _trusted,
                        onTap: () {
                          _following = true;
                          _showBack.value = false;
                          widget.onSeek(lines[i].time);
                        },
                      ),
                    _Source(widget.lyrics),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                child: ValueListenableBuilder<bool>(
                  valueListenable: _showBack,
                  builder: (context, show, _) => IgnorePointer(
                    ignoring: !show,
                    child: AnimatedOpacity(
                      duration: LayoutPrefs.dur(const Duration(milliseconds: 200)),
                      opacity: show ? 1 : 0,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.black.withValues(alpha: 0.6),
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        onPressed: _resume,
                        icon: const Icon(Icons.my_location_rounded, size: 18),
                        label: const Text('Back to current line'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How many lyric lines were built since start (tests).
@visibleForTesting
int lyricLineBuilds = 0;

/// Where a line is relative to the one being sung.
enum _LinePlace { sung, current, upcoming }

/// One lyric line that follows [at] but rebuilds only when its own place
/// changes (upcoming, current, sung): moving on a line costs two builds, not one per line.
class _LineSlot extends StatefulWidget {
  const _LineSlot({
    super.key,
    required this.index,
    required this.at,
    required this.line,
    required this.extra,
    required this.style,
    required this.unsung,
    required this.position,
    required this.ticks,
    required this.trusted,
    required this.onTap,
  });

  final int index;
  final ValueListenable<int> at;
  final LyricLine line;
  final String? extra;
  final TextStyle? style;
  final Color unsung;
  final Duration Function() position;
  final Stream<Duration> ticks;
  final Duration? Function(Duration) trusted;
  final VoidCallback onTap;

  @override
  State<_LineSlot> createState() => _LineSlotState();
}

class _LineSlotState extends State<_LineSlot> {
  late _LinePlace _place = _placeAt(widget.at.value);

  _LinePlace _placeAt(int at) => widget.index == at
      ? _LinePlace.current
      : widget.index < at
      ? _LinePlace.sung
      : _LinePlace.upcoming;

  @override
  void initState() {
    super.initState();
    widget.at.addListener(_moved);
  }

  @override
  void didUpdateWidget(_LineSlot old) {
    super.didUpdateWidget(old);
    if (!identical(old.at, widget.at)) {
      old.at.removeListener(_moved);
      widget.at.addListener(_moved);
    }
    _place = _placeAt(widget.at.value);
  }

  @override
  void dispose() {
    widget.at.removeListener(_moved);
    super.dispose();
  }

  void _moved() {
    final place = _placeAt(widget.at.value);
    if (place != _place) setState(() => _place = place);
  }

  @override
  Widget build(BuildContext context) {
    lyricLineBuilds++;
    final line = widget.line;
    final timed = _place == _LinePlace.current && line.words.isNotEmpty;
    return _Line(
      text: line.text.isEmpty ? '♪' : line.text,
      extra: widget.extra,
      style: widget.style,
      karaoke: timed
          ? KaraokeLine(
              words: line.words,
              sungColor: Colors.white,
              position: widget.position,
              ticks: widget.ticks,
              trusted: widget.trusted,
            )
          : null,
      color: switch (_place) {
        _LinePlace.current => timed ? widget.unsung : Colors.white,
        _LinePlace.sung => Colors.white.withValues(alpha: 0.75),
        _LinePlace.upcoming => widget.unsung,
      },
      onTap: widget.onTap,
    );
  }
}

class _Line extends StatefulWidget {
  const _Line({
    required this.text,
    this.extra,
    required this.style,
    required this.color,
    this.karaoke,
    required this.onTap,
  });

  final String text;

  /// Pronunciation / translation, smaller, under the line.
  final String? extra;
  final TextStyle? style;
  final Color color;

  /// Stands in for the plain text while a word-timed line is being sung.
  final Widget? karaoke;
  final VoidCallback onTap;

  @override
  State<_Line> createState() => _LineState();
}

class _LineState extends State<_Line> {
  bool _hover = false;

  /// Only a real mouse lights a line it passes over; a stylus or finger can
  /// leave "hovering" stuck on a phone, which lit lines for no reason.
  void _hovered(PointerEvent e, bool on) {
    if (e.kind != PointerDeviceKind.mouse || _hover == on) return;
    setState(() => _hover = on);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (e) => _hovered(e, true),
    onExit: (e) => _hovered(e, false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: _centred ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
          children: [
            AnimatedDefaultTextStyle(
              duration: LayoutPrefs.dur(const Duration(milliseconds: 200)),
              style: (widget.style ?? const TextStyle()).copyWith(
                color: _hover && widget.karaoke == null ? Colors.white : widget.color,
              ),
              child: widget.karaoke ?? Text(widget.text, textAlign: _textAlign),
            ),
            if (widget.extra case final extra?)
              AnimatedDefaultTextStyle(
                duration: LayoutPrefs.dur(const Duration(milliseconds: 200)),
                style: (_extraStyle(context) ?? const TextStyle()).copyWith(
                  color: (_hover ? Colors.white : widget.color).withValues(alpha: 0.8),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(extra, textAlign: _textAlign),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
