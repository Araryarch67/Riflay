import 'package:flutter/material.dart';

import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../theme.dart';
import '../widgets/marquee_text.dart';

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
    layoutBuilder: (current, previous) => Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
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
