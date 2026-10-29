import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/smooth_scroll.dart';

/// The small spinner the result sections show while a search loads.
class SearchSpinner extends StatelessWidget {
  const SearchSpinner({super.key, required this.pad});

  final double pad;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: pad, vertical: 16),
      child: const Align(
        alignment: Alignment.centerLeft,
        child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    ),
  );
}

/// One calm line in place of results ("No YouTube results.").
class SearchNote extends StatelessWidget {
  const SearchNote(this.message, {super.key, required this.pad});

  final String message;
  final double pad;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: pad, vertical: 8),
      child: Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
    ),
  );
}

/// Results arriving from the network fade in, top first (only the first dozen).
Widget maybeFade(int i, Widget child) => i < 12
    ? FadeIn(
        delay: Duration(milliseconds: 30 * i),
        offset: 8,
        child: child,
      )
    : child;

/// Coloured "genre"-style tile with a tilted cover peeking out of the corner.
class BrowseTile extends StatelessWidget {
  const BrowseTile({super.key, required this.title, required this.color, required this.cover, required this.onTap});

  final String title;
  final Color color;
  final Widget cover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned(
              right: -14,
              bottom: -6,
              width: 76,
              height: 76,
              child: Transform.rotate(
                angle: 0.44,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4))],
                  ),
                  child: cover,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
