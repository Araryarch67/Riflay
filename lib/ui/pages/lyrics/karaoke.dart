// Word-by-word fill of the line being sung.
part of '../lyrics_page.dart';

/// How far a word-timed line has been sung at [position]: [sung] whole words,
/// then [fill] (0 to 1) of the next one.
({int sung, double fill}) karaokeProgress(List<LyricWord> words, Duration position) {
  var sung = 0;
  var fill = 0.0;
  for (final w in words) {
    if (position >= w.end) {
      sung++;
    } else {
      final span = (w.end - w.start).inMicroseconds;
      if (position > w.start && span > 0) fill = (position - w.start).inMicroseconds / span;
      break;
    }
  }
  return (sung: sung, fill: fill);
}

/// The current line of word-timed lyrics. The line is drawn once in the dim
/// colour (a plain [Text]); on top, a painter lays out the same text in the
/// sung colour and clips it to the sung part: whole words, then the left part
/// of the word being sung, with a short soft edge. The only thing that changes per
/// frame is that clip, so no widget rebuilds, no relayout, and the text is measured once per width.
///
/// While the line is the current one, the page is on screen and the song plays, the fill runs on the shared
/// [UiBeat] clock, reading the player's interpolated position on each beat (30 times a second, 60 in Heavy), so it
/// glides rather than stepping with the position stream. Lightweight, a paused song and a hidden page take no beats at
/// all: the stream's ticks move the fill then.
class KaraokeLine extends StatefulWidget {
  const KaraokeLine({
    super.key,
    required this.words,
    required this.sungColor,
    required this.position,
    required this.ticks,
    required this.trusted,
    this.playing,
  });

  final List<LyricWord> words;
  final Color sungColor;
  final Duration Function() position;
  final Stream<Duration> ticks;

  /// Whether the song plays; the beat clock runs only then. Null: always.
  final ValueListenable<bool>? playing;

  /// The position if it can be trusted, else null (nothing sung).
  final Duration? Function(Duration) trusted;

  @override
  State<KaraokeLine> createState() => KaraokeLineState();
}

class KaraokeLineState extends State<KaraokeLine> {
  late final ValueNotifier<({int sung, double fill})> _progress = ValueNotifier(_at(widget.position()));
  StreamSubscription<Duration>? _sub;
  UiBeatListener? _beat;
  bool _visible = true;

  ({int sung, double fill}) _at(Duration p) {
    final t = widget.trusted(p);
    return t == null ? (sung: 0, fill: 0.0) : karaokeProgress(widget.words, t);
  }

  /// Whole words sung and the fill (0 to 1) of the next one.
  @visibleForTesting
  ({int sung, double fill}) get progress => _progress.value;

  /// Whether the frame clock is moving the fill (tests).
  @visibleForTesting
  bool get onBeat => _beat != null;

  @override
  void initState() {
    super.initState();
    // While the beat runs it holds the newer position; the stream's older ticks would pull the fill back.
    _sub = widget.ticks.listen((p) {
      if (_beat == null) _progress.value = _at(p);
    });
    widget.playing?.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A page under another (the lyrics behind Now Playing) takes no beats.
    _visible = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  @override
  void didUpdateWidget(KaraokeLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) {
      oldWidget.playing?.removeListener(_sync);
      widget.playing?.addListener(_sync);
    }
    _sync();
  }

  void _sync() {
    final want = !LayoutPrefs.lightweight && _visible && (widget.playing?.value ?? true);
    if (!want) {
      _beat?.cancel();
      _beat = null;
      return;
    }
    _beat ??= UiBeat.listen(
      LayoutPrefs.heavy ? UiBeat.period : UiBeat.period * 2,
      (_) => _progress.value = _at(widget.position()),
    );
  }

  @override
  void dispose() {
    widget.playing?.removeListener(_sync);
    _beat?.cancel();
    _sub?.cancel();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.words.map((w) => w.text).join();
    final style = DefaultTextStyle.of(context).style;
    // Its own layer: each fill tick repaints this line, not every line of the song around it.
    return RepaintBoundary(
      child: CustomPaint(
        foregroundPainter: _KaraokePainter(
          words: widget.words,
          text: text,
          style: style.copyWith(color: widget.sungColor),
          align: _textAlign,
          direction: Directionality.of(context),
          scaler: MediaQuery.textScalerOf(context),
          progress: _progress,
        ),
        child: Text(text, textAlign: _textAlign),
      ),
    );
  }
}

class _KaraokePainter extends CustomPainter {
  _KaraokePainter({
    required this.words,
    required this.text,
    required this.style,
    required this.align,
    required this.direction,
    required this.scaler,
    required this.progress,
  }) : super(repaint: progress);

  final List<LyricWord> words;
  final String text;
  final TextStyle style;
  final TextAlign align;
  final TextDirection direction;
  final TextScaler scaler;
  final ValueListenable<({int sung, double fill})> progress;

  /// The soft edge of the fill: this wide, in [_steps] strips of falling opacity. Whole sung words stay fully coloured.
  static const _feather = 12.0;
  static const _steps = 4;

  /// The sung colour at full strength, then at the strengths of the edge's strips. Laid out once per width.
  final _layers = <TextPainter>[];
  double _width = -1;

  /// Each word's boxes (more than one when it wraps), measured with the layout.
  final _boxes = <List<TextBox>>[];

  void _layout(double width) {
    if (_layers.isNotEmpty && width == _width) return;
    _width = width;
    _layers.clear();
    for (var i = 0; i <= _steps; i++) {
      // Layer 0 is solid; layer k is the k-th strip of the edge, fainter towards where the fill ends.
      final alpha = i == 0 ? 1.0 : 1 - (i - 0.5) / _steps;
      _layers.add(
        TextPainter(
          text: TextSpan(
            text: text,
            style: style.copyWith(color: (style.color ?? Colors.white).withValues(alpha: alpha)),
          ),
          textAlign: align,
          textDirection: direction,
          textScaler: scaler,
        )..layout(minWidth: width, maxWidth: width),
      );
    }
    final tp = _layers.first;
    _boxes.clear();
    var start = 0;
    for (final w in words) {
      final end = start + w.text.length;
      // Not the trailing space: a fill that stops at the letters looks right.
      final trimmed = start + w.text.trimRight().length;
      _boxes.add(
        trimmed > start ? tp.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: trimmed)) : const [],
      );
      start = end;
    }
  }

  /// A mild ease in and out, so a short word does not snap across.
  static double _ease(double t) => t * t * (3 - 2 * t);

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.value;
    if (p.sung == 0 && p.fill <= 0) return;
    _layout(size.width);
    final solid = Path();
    for (var i = 0; i < p.sung && i < _boxes.length; i++) {
      for (final b in _boxes[i]) {
        solid.addRect(b.toRect());
      }
    }
    // The strips of the soft edge, each with the layer that has its opacity.
    final edge = <(Rect, int)>[];
    if (p.fill > 0 && p.sung < _boxes.length) {
      final boxes = _boxes[p.sung];
      var left = boxes.fold<double>(0, (sum, b) => sum + (b.right - b.left)) * _ease(p.fill);
      for (final b in boxes) {
        final w = b.right - b.left;
        if (left <= 0) break;
        final part = left.clamp(0, w).toDouble();
        final rtl = b.direction == TextDirection.rtl;
        // The feather lies behind where the fill ends, inside the word; a fill just begun is all feather.
        final feather = math.min(_feather, part);
        final solidPart = part - feather;
        if (solidPart > 0) {
          solid.addRect(
            rtl
                ? Rect.fromLTRB(b.right - solidPart, b.top, b.right, b.bottom)
                : Rect.fromLTRB(b.left, b.top, b.left + solidPart, b.bottom),
          );
        }
        for (var k = 0; k < _steps; k++) {
          // Strip k, counted from the solid side: fainter the nearer the end.
          final a = solidPart + feather * k / _steps, z = solidPart + feather * (k + 1) / _steps;
          edge.add((
            rtl
                ? Rect.fromLTRB(b.right - z, b.top, b.right - a, b.bottom)
                : Rect.fromLTRB(b.left + a, b.top, b.left + z, b.bottom),
            k + 1,
          ));
        }
        left -= w;
      }
    }
    canvas
      ..save()
      ..clipPath(solid);
    _layers.first.paint(canvas, Offset.zero);
    canvas.restore();
    for (final (rect, layer) in edge) {
      canvas
        ..save()
        ..clipRect(rect);
      _layers[layer].paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_KaraokePainter old) =>
      old.text != text || old.style != style || old.align != align || old.scaler != scaler;
}
