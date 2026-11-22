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
/// display clock in [UiBeat], so it glides at the monitor's refresh rate. A paused song or hidden page
/// takes no display frames: the stream's ticks move the fill then.
class KaraokeLine extends StatefulWidget {
  const KaraokeLine({
    super.key,
    required this.words,
    required this.sungColor,
    required this.position,
    required this.ticks,
    required this.trusted,
    this.playing,
    this.textAlign,
  });

  final List<LyricWord> words;
  final TextAlign? textAlign;
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

class KaraokeLineState extends State<KaraokeLine> with WidgetsBindingObserver {
  _KaraokePainter? _painter;
  late final ValueNotifier<({int sung, double fill})> _progress = ValueNotifier(_at(widget.position()));
  StreamSubscription<Duration>? _sub;
  VoidCallback? _stopFrames;
  bool _visible = true;
  Duration? _lastPosition;
  late double _cursor = _progress.value.sung + _progress.value.fill;

  ({int sung, double fill}) _at(Duration p) {
    final t = widget.trusted(p);
    return t == null ? (sung: 0, fill: 0.0) : karaokeProgress(widget.words, t);
  }

  /// Whole words sung and the fill (0 to 1) of the next one.
  @visibleForTesting
  ({int sung, double fill}) get progress => _progress.value;

  /// Whether the frame clock is moving the fill (tests).
  @visibleForTesting
  bool get onBeat => _stopFrames != null;

  @override
  void initState() {
    super.initState();
    _lastPosition = widget.trusted(widget.position());
    // While the beat runs it holds the newer position; the stream's older ticks would pull the fill back.
    _sub = widget.ticks.listen((p) {
      if (_stopFrames == null) _snap(p);
    });
    widget.playing?.addListener(_sync);
    DesktopVisibility.instance.addListener(_sync);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _sync();

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
    if (oldWidget.words != widget.words) _snap(widget.position());
    if (oldWidget.playing != widget.playing) {
      oldWidget.playing?.removeListener(_sync);
      widget.playing?.addListener(_sync);
    }
    _sync();
  }

  void _sync() {
    // Only the visible, playing line needs its own animation beats.
    final want =
        _visible &&
        DesktopVisibility.instance.value &&
        PlayingMotion.decorates(WidgetsBinding.instance.lifecycleState) &&
        (widget.playing?.value ?? true);
    if (!want) {
      _stopFrames?.call();
      _stopFrames = null;
      return;
    }
    if (_stopFrames == null) {
      _snap(widget.position());
      _stopFrames = UiBeat.listenFrames(_advance);
    }
  }

  void _snap(Duration position) {
    final p = _at(position);
    _cursor = p.sung + p.fill;
    _lastPosition = widget.trusted(position);
    _progress.value = p;
  }

  void _advance(Duration elapsed) {
    final position = widget.position();
    final trusted = widget.trusted(position);
    if (trusted == null) return _snap(position);
    final previous = _lastPosition;
    final delta = previous == null ? Duration.zero : trusted - previous;
    // Seeks must land immediately. Small clock corrections and abrupt word stamps can glide instead.
    if (previous == null ||
        delta < const Duration(milliseconds: -80) ||
        delta > elapsed + const Duration(milliseconds: 350)) {
      return _snap(position);
    }
    _lastPosition = trusted;
    final target = karaokeProgress(widget.words, trusted);
    final to = target.sung + target.fill;
    final alpha = 1 - math.exp(-elapsed.inMicroseconds / 45000);
    var next = _cursor + (math.max(_cursor, to) - _cursor) * alpha;
    // Smooth only the presentation: never let it fall more than 80 ms behind the real word timings.
    final floor = karaokeProgress(widget.words, trusted - const Duration(milliseconds: 80));
    next = math.max(next, floor.sung + floor.fill);
    if ((to - next).abs() < 0.001) next = to;
    _cursor = next.clamp(0.0, widget.words.length.toDouble());
    final sung = _cursor.floor();
    _progress.value = (sung: sung, fill: _cursor - sung);
  }

  @override
  void dispose() {
    _painter?.disposeTexture();
    widget.playing?.removeListener(_sync);
    WidgetsBinding.instance.removeObserver(this);
    DesktopVisibility.instance.removeListener(_sync);
    _stopFrames?.call();
    _sub?.cancel();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.words.map((w) => w.text).join();
    final align = widget.textAlign ?? _textAlign;
    final style = DefaultTextStyle.of(context).style;
    final next = _KaraokePainter(
      words: widget.words,
      text: text,
      style: style.copyWith(color: widget.sungColor, shadows: const []),
      align: align,
      direction: Directionality.of(context),
      scaler: MediaQuery.textScalerOf(context),
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
      progress: _progress,
    );
    final previous = _painter;
    final _KaraokePainter painter;
    if (previous != null && !next.shouldRepaint(previous)) {
      painter = previous;
    } else {
      previous?.disposeTexture();
      painter = _painter = next;
    }
    // Its own layer: each fill tick repaints this line, not every line of the song around it.
    return RepaintBoundary(
      child: CustomPaint(
        foregroundPainter: painter,
        child: RepaintBoundary(child: Text(text, textAlign: align)),
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
    required this.pixelRatio,
    required this.progress,
  }) : super(repaint: progress);

  final List<LyricWord> words;
  final String text;
  final TextStyle style;
  final TextAlign align;
  final TextDirection direction;
  final TextScaler scaler;
  final double pixelRatio;
  final ValueListenable<({int sung, double fill})> progress;

  /// One soft edge across the line, in [_steps] strips of falling opacity.
  static const _feather = 18.0;
  static const _steps = 8;

  // Rasterize glyphs once. Fill ticks draw clipped GPU texture slices instead
  // of submitting the whole paragraph for each of the eight feather strips.
  ui.Image? _glyphs;
  Rect _textureBounds = Rect.zero;
  final _alpha = [
    for (var i = 0; i <= _steps; i++)
      Paint()..color = Colors.white.withValues(alpha: i == 0 ? 1 : 1 - (i - 0.5) / _steps),
  ];
  double _width = -1;

  void disposeTexture() {
    _glyphs?.dispose();
    _glyphs = null;
  }

  /// Each word's boxes (more than one when it wraps), measured with the layout.
  final _boxes = <List<TextBox>>[];
  final _widths = <double>[];

  void _layout(double width) {
    if (_glyphs != null && width == _width) return;
    _width = width;
    disposeTexture();
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: align,
      textDirection: direction,
      textScaler: scaler,
    )..layout(minWidth: width, maxWidth: width);
    _boxes.clear();
    _widths.clear();
    var start = 0;
    for (final w in words) {
      final end = start + w.text.length;
      // Not the trailing space: a fill that stops at the letters looks right.
      final trimmed = start + w.text.trimRight().length;
      _boxes.add(
        trimmed > start ? tp.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: trimmed)) : const [],
      );
      _widths.add(_boxes.last.fold(0.0, (sum, box) => sum + box.right - box.left));
      start = end;
    }
    final ratio = pixelRatio.clamp(1.0, 4.0);
    final imageWidth = math.max(1, (width * ratio).ceil());
    final imageHeight = math.max(1, (tp.height * ratio).ceil());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(ratio);
    tp.paint(canvas, Offset.zero);
    final picture = recorder.endRecording();
    _glyphs = picture.toImageSync(imageWidth, imageHeight);
    _textureBounds = Rect.fromLTWH(0, 0, imageWidth / ratio, imageHeight / ratio);
    picture.dispose();
    tp.dispose();
  }

  void _draw(Canvas canvas, int layer) {
    final image = _glyphs!;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      _textureBounds,
      _alpha[layer],
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.value;
    if (p.sung == 0 && p.fill <= 0) return;
    _layout(size.width);
    final solid = Path();
    final edge = <(Rect, int)>[];
    final total = _widths.fold(0.0, (sum, width) => sum + width);
    var cursor = 0.0;
    for (var i = 0; i < _widths.length; i++) {
      if (i < p.sung) cursor += _widths[i];
      if (i == p.sung) cursor += _widths[i] * p.fill;
    }
    // Carry one reveal edge across word boundaries. Restarting an ease and feather for each word made
    // the highlight stop, accelerate and flash at every boundary, even with accurate timestamps.
    final feather = math.min(_feather, math.min(cursor, math.max(0.0, total - cursor) * 4));
    final solidEnd = cursor - feather;
    var offset = 0.0;
    for (final boxes in _boxes) {
      for (final box in boxes) {
        final width = box.right - box.left;
        Rect slice(double from, double to) => box.direction == TextDirection.rtl
            ? Rect.fromLTRB(box.right - to, box.top, box.right - from, box.bottom)
            : Rect.fromLTRB(box.left + from, box.top, box.left + to, box.bottom);
        final filled = (solidEnd - offset).clamp(0.0, width);
        if (filled > 0) solid.addRect(slice(0, filled));
        for (var k = 0; k < _steps; k++) {
          final from = (solidEnd + feather * k / _steps - offset).clamp(0.0, width);
          final to = (solidEnd + feather * (k + 1) / _steps - offset).clamp(0.0, width);
          if (to > from) edge.add((slice(from, to), k + 1));
        }
        offset += width;
      }
    }
    canvas
      ..save()
      ..clipPath(solid);
    _draw(canvas, 0);
    canvas.restore();
    for (final (rect, layer) in edge) {
      canvas
        ..save()
        ..clipRect(rect);
      _draw(canvas, layer);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_KaraokePainter old) =>
      old.text != text ||
      old.words != words ||
      old.style != style ||
      old.align != align ||
      old.direction != direction ||
      old.scaler != scaler ||
      old.pixelRatio != pixelRatio;
}
