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
  // Whether the song is playing: the word fill only runs on the frame clock then.
  late final _playing = ValueNotifier<bool>(_c.showsPlaying);

  void _onPlayer() {
    if (_playing.value != _c.showsPlaying) _playing.value = _c.showsPlaying;
  }

  @override
  void initState() {
    super.initState();
    _c.addListener(_onPlayer);
  }

  @override
  void dispose() {
    _c.removeListener(_onPlayer);
    _playing.dispose();
    super.dispose();
  }

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
    playing: _playing,
    position: () => _c.position - _shift.value,
    length: () => _c.currentTrack?.duration ?? _c.duration,
    onSeek: (to) {
      final at = to + _shift.value;
      _c.seek(at.isNegative ? Duration.zero : at);
      if (!_c.isPlaying) _c.play();
    },
    onHold: (i) =>
        showLyricCard(context, track: widget.track, lines: [for (final l in widget.lyrics.lines) l.text], initial: i),
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
    this.playing,
    this.position = _zero,
    this.length,
    required this.onSeek,
    this.onHold,
  });

  final Lyrics lyrics;

  /// A line was held (long-pressed, or right-clicked): its card to share.
  final ValueChanged<int>? onHold;

  /// The position a few times a second; the current line changes from it.
  final Stream<Duration> ticks;

  /// The position often enough to glide a word's fill.
  final Stream<Duration> smoothTicks;

  /// Whether the song is playing (the word fill moves only then). Null: always.
  final ValueListenable<bool>? playing;

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
    _stopGlide();
    _sub?.cancel();
    _showBack.dispose();
    _at.dispose();
    _scroll.dispose();
    super.dispose();
  }

  int _current = -2;
  double? _viewportHeight;

  /// Follow the current line as it changes. Switched off when the person
  /// scrolls by hand; the "Back to current line" button (or a tap on a line)
  /// switches it on again.
  bool _following = true;

  /// The current line is out of view while not following: shows the button.
  final _showBack = ValueNotifier<bool>(false);

  /// The follow scroll in frugal Balanced: [_scroll] eased to the current line on the shared [UiBeat] at 20 fps
  /// (~7 frames for its 350 ms) instead of at the display's rate (~25). Cancelled by a hand scroll or a newer line.
  UiBeatListener? _glide;

  void _glideTo(double to) {
    _glide?.cancel();
    final from = _scroll.position.pixels;
    if ((to - from).abs() < 1) return;
    const length = Duration(milliseconds: 350);
    var t = Duration.zero;
    _glide = UiBeat.listen(const Duration(milliseconds: 50), (elapsed) {
      t += elapsed;
      final done = t >= length;
      if (!mounted || !_scroll.hasClients) return _stopGlide();
      final eased = Curves.easeOutCubic.transform(done ? 1 : t.inMicroseconds / length.inMicroseconds);
      _scroll.jumpTo(from + (to - from) * eased);
      if (done) _stopGlide();
    });
  }

  void _stopGlide() {
    _glide?.cancel();
    _glide = null;
  }

  void _scrollToCurrent({bool animate = true}) {
    final ctx = _current < 0 ? null : _keys[_current].currentContext;
    if (ctx == null) return;
    if (animate && LayoutPrefs.frugal && LayoutPrefs.dur(const Duration(milliseconds: 350)) > Duration.zero) {
      final ro = ctx.findRenderObject();
      final viewport = ro == null ? null : RenderAbstractViewport.maybeOf(ro);
      if (ro != null && viewport != null && _scroll.hasClients) {
        final p = _scroll.position;
        return _glideTo(viewport.getOffsetToReveal(ro, 0.5).offset.clamp(p.minScrollExtent, p.maxScrollExtent));
      }
    }
    _stopGlide();
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: animate ? LayoutPrefs.dur(const Duration(milliseconds: 350)) : Duration.zero,
      curve: Curves.easeOutCubic,
    );
  }

  /// Whether the view has been put at the current line once. The first time is a jump: the page is still opening,
  /// and a 350 ms scroll on top of its transition doubled the frames (and the CPU) of opening the lyrics.
  bool _placed = false;

  void _follow(int index) {
    if (index == _current) return;
    _current = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_following) {
        // Behind another window the next line comes at once: nobody watches the glide (~7 frames a line).
        _scrollToCurrent(animate: _placed && PlayingMotion.decorates(WidgetsBinding.instance.lifecycleState));
        _placed = true;
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
    final center = (top + bottom) / 2;
    _showBack.value = (pixels - center).abs() > 24;
  }

  void _pauseFollowing() {
    _stopGlide();
    _following = false;
    _checkVisible();
  }

  /// Lines shown: Focused. The previous, the current and the next line, each in a third of the view, so the current
  /// one sits in the middle with room around it. Moving on fades the trio out, then the next one in (a slight rise
  /// with motion on), never both at once.
  Widget _focused(TextStyle? style, Color unsung, double pad) {
    final lines = widget.lyrics.lines;
    final side = style?.copyWith(fontSize: style.fontSize == null ? null : style.fontSize! * 0.8);
    Widget slot(int i, {required bool beside}) => _LineSlot(
      key: ValueKey(i),
      index: i,
      at: _at,
      line: lines[i],
      extra: extraFor(i),
      style: beside ? side : style,
      unsung: unsung,
      fade: beside ? 0.6 : 1,
      position: widget.position,
      ticks: widget.smoothTicks,
      playing: widget.playing,
      trusted: _trusted,
      onTap: () => widget.onSeek(lines[i].time),
      onHold: widget.onHold == null ? null : () => widget.onHold!(i),
    );
    return ValueListenableBuilder<int>(
      valueListenable: _at,
      builder: (context, at, _) {
        final current = at >= 0 && at < lines.length ? at : null;
        final before = current != null && current > 0 ? current - 1 : null;
        // Before the first line is sung, it waits as the next one.
        final after = current != null ? (current + 1 < lines.length ? current + 1 : null) : (at < 0 ? 0 : null);
        // Calm: the old lines fade out first, then the new ones fade in with a slight rise, so two sets of lines
        // are never on screen at once. Each half has its own soft curve (the old set runs it in reverse).
        return AnimatedSwitcher(
          duration: LayoutPrefs.dur(const Duration(milliseconds: 640)),
          transitionBuilder: (child, anim) {
            final half = CurvedAnimation(
              parent: anim,
              curve: const Interval(0.5, 1, curve: Curves.easeInOutCubic),
            );
            return FadeTransition(
              opacity: half,
              child: LayoutPrefs.moves
                  ? SlideTransition(
                      position: Tween(begin: const Offset(0, 0.012), end: Offset.zero).animate(half),
                      child: child,
                    )
                  : child,
            );
          },
          child: SizedBox.expand(
            key: ValueKey(at),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: Column(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: before == null ? null : slot(before, beside: true),
                    ),
                  ),
                  Expanded(child: Center(child: current == null ? null : slot(current, beside: false))),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: after == null ? null : slot(after, beside: true),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
    final unsung = dim ? AppColors.textMuted : AppColors.textPrimary.withValues(alpha: 0.75);
    if (LayoutPrefs.instance.lyricsLines == LyricsLines.focused) return _focused(style, unsung, pad);
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
        child: LayoutBuilder(
          builder: (context, box) {
            // Half a viewport of breathing room lets the first and last line
            // reach the same center as every line between them.
            final height = box.maxHeight;
            if (_viewportHeight != height) {
              _viewportHeight = height;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _following) _scrollToCurrent(animate: false);
              });
            }
            return Stack(
              children: [
                Positioned.fill(
                  // No scrollbar: the view follows the song, and on a computer each line's scroll showed it and
                  // faded it out again (~25 frames a line, ~10 ms of the main thread each on Linux). The wheel and
                  // a drag still scroll. RIFLAY_LYRICS_SCROLLBAR brings it back.
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: DebugSwitches.lyricsScrollbar),
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: EdgeInsets.fromLTRB(pad, height / 2, pad, height / 2),
                      child: Column(
                        crossAxisAlignment: _centred ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
                        children: [
                          if (widget.lyrics.otherVersion)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                tr.lyricsOtherVersion,
                                key: const ValueKey('lyrics-other-version'),
                                textAlign: _textAlign,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
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
                              playing: widget.playing,
                              trusted: _trusted,
                              onTap: () {
                                _following = true;
                                _showBack.value = false;
                                widget.onSeek(lines[i].time);
                                if (i == _current) _scrollToCurrent();
                              },
                              onHold: widget.onHold == null ? null : () => widget.onHold!(i),
                            ),
                          _Source(widget.lyrics),
                        ],
                      ),
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
                              foregroundColor: AppColors.textPrimary,
                              backgroundColor: AppColors.menu,
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            onPressed: _resume,
                            icon: const Icon(Icons.my_location_rounded, size: 18),
                            label: Text(tr.backToCurrentLine),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
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
    this.onHold,
    this.playing,
    this.fade = 1,
  });

  final int index;
  final ValueListenable<bool>? playing;

  /// Multiplies the line's colour opacity (the lines either side of the current one, in Focused).
  final double fade;
  final ValueListenable<int> at;
  final LyricLine line;
  final String? extra;
  final TextStyle? style;
  final Color unsung;
  final Duration Function() position;
  final Stream<Duration> ticks;
  final Duration? Function(Duration) trusted;
  final VoidCallback onTap;
  final VoidCallback? onHold;

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

  Color _faded(Color c) => widget.fade == 1 ? c : c.withValues(alpha: c.a * widget.fade);

  @override
  Widget build(BuildContext context) {
    lyricLineBuilds++;
    final line = widget.line;
    // Line by line never fills word by word, even where the lyrics have word timings.
    final timed =
        _place == _LinePlace.current && line.words.isNotEmpty && LayoutPrefs.instance.lyricsSync == LyricsSync.word;
    return _Line(
      text: line.text.isEmpty ? '♪' : line.text,
      extra: widget.extra,
      style: widget.style,
      karaoke: timed
          ? KaraokeLine(
              words: line.words,
              sungColor: AppColors.textPrimary,
              position: widget.position,
              ticks: widget.ticks,
              playing: widget.playing,
              trusted: widget.trusted,
            )
          : null,
      color: _faded(switch (_place) {
        _LinePlace.current => timed ? widget.unsung : AppColors.textPrimary,
        _LinePlace.sung => AppColors.textPrimary.withValues(alpha: 0.75),
        _LinePlace.upcoming => widget.unsung,
      }),
      extraColor: timed ? _faded(AppColors.textPrimary) : null,
      highlight: _place == _LinePlace.current && widget.fade == 1,
      onTap: widget.onTap,
      onHold: widget.onHold,
    );
  }
}

class _Line extends StatefulWidget {
  const _Line({
    required this.text,
    this.extra,
    required this.style,
    required this.color,
    this.extraColor,
    this.karaoke,
    this.highlight = false,
    required this.onTap,
    this.onHold,
  });

  /// The line being sung: on the dark glass, when Layout › Lyrics says so.
  final bool highlight;

  final String text;

  /// Pronunciation / translation, smaller, under the line.
  final String? extra;
  final TextStyle? style;
  final Color color;

  /// [extra]'s colour, when it isn't [color]: a word-timed line being sung is dim under its fill, but its
  /// pronunciation has no word timings to fill by, so it lights up whole.
  final Color? extraColor;

  /// Stands in for the plain text while a word-timed line is being sung.
  final Widget? karaoke;
  final VoidCallback onTap;
  final VoidCallback? onHold;

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
      onLongPress: widget.onHold,
      onSecondaryTap: widget.onHold,
      child: _Glass(
        on: widget.highlight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: _centred ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
          children: [
            AnimatedDefaultTextStyle(
              duration: _lineChange(200),
              style: (widget.style ?? const TextStyle()).copyWith(
                color: _hover && widget.karaoke == null ? AppColors.textPrimary : widget.color,
              ),
              child: widget.karaoke ?? Text(widget.text, textAlign: _textAlign),
            ),
            if (widget.extra case final extra?)
              AnimatedDefaultTextStyle(
                duration: _lineChange(200),
                style: (_extraStyle(context) ?? const TextStyle()).copyWith(
                  color: (_hover ? AppColors.textPrimary : widget.extraColor ?? widget.color).withValues(alpha: 0.8),
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

/// A line's pane: dark frosted glass, faint, behind the line being sung, fading in and out as the lines move on.
/// With the highlight off it is only the line's spacing. Every line keeps the pane's inset either way, so the words
/// don't move when it comes.
class _Glass extends StatelessWidget {
  const _Glass({required this.on, required this.child});

  final bool on;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!LayoutPrefs.instance.highlightLyricLine) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: child);
    }
    const radius = BorderRadius.all(Radius.circular(18));
    final duration = _lineChange(260);
    final pane = AnimatedContainer(
      // The whole row, not just the words' width.
      width: double.infinity,
      duration: duration,
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: on ? 0.2 : 0),
        borderRadius: radius,
        border: Border.all(color: Colors.white.withValues(alpha: on ? 0.07 : 0)),
      ),
      child: child,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      // The blur only behind the one line being sung, and not in Lightweight.
      child: on && !LayoutPrefs.lightweight
          ? ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: pane),
            )
          : pane,
    );
  }
}

/// How long a line takes to change look when the song moves on to the next one. Frugal Balanced on a computer
/// (`LayoutPrefs.frugal`): at once. Each fade drew at the display's rate, ~15 frames a line beside the scroll (which
/// glides on the beat there, see `_glide`), on a page where everything else moves 5-10 times a second.
Duration _lineChange(int ms) => LayoutPrefs.frugal ? Duration.zero : LayoutPrefs.dur(Duration(milliseconds: ms));
