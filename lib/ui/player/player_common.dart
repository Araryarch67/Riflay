import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../theme.dart';
import '../widgets/marquee_text.dart';
import '../widgets/track_row.dart' show openArtist;

/// Cross-fades (and nudges up) whatever shows the current song when it changes.
class TrackSwitcher extends StatelessWidget {
  const TrackSwitcher({super.key, required this.trackId, required this.child, this.slide = true});

  final String? trackId;
  final Widget child;
  final bool slide;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: LayoutPrefs.dur(const Duration(milliseconds: 260)),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    layoutBuilder: (current, previous) => Stack(
      alignment: Alignment.centerLeft,
      children: [
        for (final child in previous) HeroMode(enabled: false, child: child),
        ?current,
      ],
    ),
    transitionBuilder: (child, anim) => FadeTransition(
      opacity: anim,
      child: slide && LayoutPrefs.moves
          ? SlideTransition(
              position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(anim),
              child: child,
            )
          : child,
    ),
    child: child,
  );
}

/// Text that underlines on hover and navigates on click.
class LinkText extends StatefulWidget {
  const LinkText(this.text, {super.key, required this.style, required this.onTap});

  final String text;
  final TextStyle? style;

  /// Null for plain text (e.g. streamed songs with no album page in the library).
  final VoidCallback? onTap;

  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final link = widget.onTap != null;
    return MouseRegion(
      cursor: link ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = link),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: MarqueeText(
          widget.text,
          style: widget.style?.copyWith(
            decoration: _hover ? TextDecoration.underline : null,
            color: _hover ? AppColors.textPrimary : null,
          ),
        ),
      ),
    );
  }
}

/// A song's artist line where each artist is its own link: "Kobo Kanaeru, Takanashi Kiara" opens either one.
/// One artist is a plain [LinkText]. [suffix] follows the names as plain text.
class ArtistLinks extends StatefulWidget {
  const ArtistLinks({super.key, required this.track, required this.style, this.suffix = ''});

  final Track track;
  final TextStyle? style;
  final String suffix;

  @override
  State<ArtistLinks> createState() => _ArtistLinksState();
}

class _ArtistLinksState extends State<ArtistLinks> {
  final _taps = <TapGestureRecognizer>[];
  int? _hover;

  @override
  void dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final names = track.artists;
    final c = PlayerScope.read(context);
    if (names.length < 2) {
      return LinkText('${track.artist}${widget.suffix}', style: widget.style, onTap: openArtist(context, c, track));
    }
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
    final spans = <InlineSpan>[];
    for (var i = 0; i < names.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: ', '));
      final open = openArtist(context, c, track, name: names[i]);
      final tap = open == null ? null : (TapGestureRecognizer()..onTap = open);
      if (tap != null) _taps.add(tap);
      final lit = _hover == i && open != null;
      spans.add(
        TextSpan(
          text: names[i],
          recognizer: tap,
          mouseCursor: open == null ? MouseCursor.defer : SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = i),
          onExit: (_) => setState(() => _hover = null),
          style: lit ? TextStyle(decoration: TextDecoration.underline, color: AppColors.textPrimary) : null,
        ),
      );
    }
    if (widget.suffix.isNotEmpty) spans.add(TextSpan(text: widget.suffix));
    return MarqueeText('${names.join(', ')}${widget.suffix}', style: widget.style, spans: spans);
  }
}

/// The mini player's progress line, updated every frame.
class MiniProgress extends StatefulWidget {
  const MiniProgress({super.key, required this.builder});

  final AsyncWidgetBuilder<Duration> builder;

  @override
  State<MiniProgress> createState() => _MiniProgressState();
}

class _MiniProgressState extends State<MiniProgress> {
  Stream<Duration>? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _position ??= PlayerScope.read(context).smoothPosition();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(stream: _position, builder: widget.builder);
}
