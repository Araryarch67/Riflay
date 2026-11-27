import 'package:flutter/material.dart';

/// What a decoration is: a small drawing, or words.
enum DecorationKind {
  note(Icons.music_note_rounded),
  track(Icons.audiotrack_rounded),
  wave(Icons.graphic_eq_rounded),
  headphones(Icons.headphones_rounded),
  disc(Icons.album_rounded),
  heart(Icons.favorite_rounded),
  sparkle(Icons.auto_awesome_rounded),
  star(Icons.star_rounded),
  flower(Icons.local_florist_rounded),
  bolt(Icons.bolt_rounded),
  moon(Icons.nightlight_round),
  sun(Icons.wb_sunny_rounded),
  cloud(Icons.cloud_rounded),
  text(Icons.title_rounded);

  const DecorationKind(this.icon);

  final IconData icon;
}

/// The colours a decoration can take.
const decorationColours = [
  Colors.white,
  Color(0xFF111111),
  Color(0xFFFF8FB1),
  Color(0xFFFF5252),
  Color(0xFFFFAB40),
  Color(0xFFFFE57F),
  Color(0xFF69F0AE),
  Color(0xFF40C4FF),
  Color(0xFF7C4DFF),
];

/// A sticker or words on the poster: where its middle is (0–1 of the poster), its size, its turn in the poster's
/// plane (radians), its colour, and for words, the words.
class PosterDecoration {
  PosterDecoration(
    this.kind, {
    required this.at,
    this.scale = 1,
    this.tilt = 0,
    this.colour = Colors.white,
    this.text = '',
  });

  DecorationKind kind;
  Offset at;
  double scale;
  double tilt;
  Color colour;
  String text;

  /// Shown on the poster, how see-through, and locked in place (Layers).
  bool visible = true;
  double opacity = 1;
  bool locked = false;

  PosterDecoration copy() => PosterDecoration(kind, at: at, scale: scale, tilt: tilt, colour: colour, text: text)
    ..visible = visible
    ..opacity = opacity
    ..locked = locked;

  Map<String, dynamic> toJson() => {
    'decoration': kind.name,
    'x': at.dx,
    'y': at.dy,
    'scale': scale,
    'tilt': tilt,
    'colour': colour.toARGB32(),
    'text': text,
    'visible': visible,
    'opacity': opacity,
    'locked': locked,
  };

  static PosterDecoration fromJson(Map<String, dynamic> j) {
    double n(String k, double d) => (j[k] as num?)?.toDouble() ?? d;
    return PosterDecoration(
        DecorationKind.values.asNameMap()[j['decoration']] ?? DecorationKind.sparkle,
        at: Offset(n('x', 0.5), n('y', 0.5)),
        scale: n('scale', 1),
        tilt: n('tilt', 0),
        colour: Color((j['colour'] as num?)?.toInt() ?? 0xFFFFFFFF),
        text: j['text'] as String? ?? '',
      )
      ..visible = j['visible'] != false
      ..opacity = n('opacity', 1)
      ..locked = j['locked'] == true;
  }
}

/// A decoration as drawn at size 1 on a poster 390 units wide, [unit] being one of those units: a drawing 72 across,
/// words 44 high, with a soft shadow so either reads on any photo.
class PosterDecorationView extends StatelessWidget {
  const PosterDecorationView({super.key, required this.decoration, required this.unit});

  final PosterDecoration decoration;
  final double unit;

  @override
  Widget build(BuildContext context) {
    final d = decoration;
    final shadow = Shadow(
      color: Colors.black.withValues(alpha: 0.35),
      blurRadius: 10 * unit,
      offset: Offset(0, 2 * unit),
    );
    if (d.kind == DecorationKind.text) {
      return Text(
        d.text.isEmpty ? ' ' : d.text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: d.colour,
          fontSize: 44 * d.scale * unit,
          fontWeight: FontWeight.w800,
          height: 1.1,
          letterSpacing: -0.5,
          shadows: [shadow],
        ),
      );
    }
    return Icon(d.kind.icon, size: 72 * d.scale * unit, color: d.colour, shadows: [shadow]);
  }
}
