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
/// of the word being sung. The only thing that changes per frame is that clip,
/// so no widget rebuilds, no relayout, and the text is measured once per width.
class KaraokeLine extends StatefulWidget {
  const KaraokeLine({
    super.key,
    required this.words,
    required this.sungColor,
    required this.position,
    required this.ticks,
    required this.trusted,
  });

  final List<LyricWord> words;
  final Color sungColor;
  final Duration Function() position;
  final Stream<Duration> ticks;

  /// The position if it can be trusted, else null (nothing sung).
  final Duration? Function(Duration) trusted;

  @override
  State<KaraokeLine> createState() => KaraokeLineState();
}

class KaraokeLineState extends State<KaraokeLine> {
  late final ValueNotifier<({int sung, double fill})> _progress = ValueNotifier(_at(widget.position()));
  StreamSubscription<Duration>? _sub;

  ({int sung, double fill}) _at(Duration p) {
    final t = widget.trusted(p);
    return t == null ? (sung: 0, fill: 0.0) : karaokeProgress(widget.words, t);
  }

  /// Whole words sung and the fill (0 to 1) of the next one.
  @visibleForTesting
  ({int sung, double fill}) get progress => _progress.value;

  @override
  void initState() {
    super.initState();
    _sub = widget.ticks.listen((p) => _progress.value = _at(p));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.words.map((w) => w.text).join();
    final style = DefaultTextStyle.of(context).style;
    return CustomPaint(
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

  TextPainter? _tp;
  double _width = -1;

  /// Each word's boxes (more than one when it wraps), measured with the layout.
  final _boxes = <List<TextBox>>[];

  void _layout(double width) {
    if (_tp != null && width == _width) return;
    _width = width;
    final tp = _tp ??= TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: align,
      textDirection: direction,
      textScaler: scaler,
    );
    tp.layout(minWidth: width, maxWidth: width);
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

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.value;
    if (p.sung == 0 && p.fill <= 0) return;
    _layout(size.width);
    final clip = Path();
    for (var i = 0; i < p.sung && i < _boxes.length; i++) {
      for (final b in _boxes[i]) {
        clip.addRect(b.toRect());
      }
    }
    if (p.fill > 0 && p.sung < _boxes.length) {
      final boxes = _boxes[p.sung];
      var left = boxes.fold<double>(0, (sum, b) => sum + (b.right - b.left)) * p.fill;
      for (final b in boxes) {
        final w = b.right - b.left;
        if (left <= 0) break;
        final part = left.clamp(0, w).toDouble();
        clip.addRect(
          b.direction == TextDirection.rtl
              ? Rect.fromLTRB(b.right - part, b.top, b.right, b.bottom)
              : Rect.fromLTRB(b.left, b.top, b.left + part, b.bottom),
        );
        left -= w;
      }
    }
    canvas
      ..save()
      ..clipPath(clip);
    _tp!.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_KaraokePainter old) =>
      old.text != text || old.style != style || old.align != align || old.scaler != scaler;
}
