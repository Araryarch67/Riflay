import 'package:flutter/material.dart';

import '../../../services/layout_prefs.dart';
import '../../shell_scope.dart';
import '../../theme.dart';
import '../../widgets/smooth_scroll.dart';
import '../../widgets/skeleton.dart';

/// The small spinner the result sections show while a search loads.
class SearchSpinner extends StatelessWidget {
  const SearchSpinner({super.key, required this.pad});

  final double pad;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: pad, vertical: 8),
      child: const SkeletonList(count: 2, rowSize: 36),
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

/// Search's chips (sources, result kinds) as Material 3 filter chips: an outlined, softly squared chip that fills
/// with the scheme's secondary container and gains a checkmark when picked. The rest of the app keeps its pills.
/// One row that scrolls sideways on phones (running off the page's edge, so it reads as scrollable); wrapping lines
/// on wider windows.
class SearchChips extends StatelessWidget {
  const SearchChips({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Outside a shell (the filters on their own): the wrapping lines.
    final child = (context.dependOnInheritedWidgetOfExactType<ShellScope>()?.compact ?? false)
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                for (final (i, chip) in children.indexed)
                  Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                    child: chip,
                  ),
              ],
            ),
          )
        : Wrap(spacing: 8, runSpacing: 8, children: children);
    final scheme = theme.colorScheme;
    bool on(Set<WidgetState> states) => states.contains(WidgetState.selected);
    return ChipTheme(
      data: theme.chipTheme.copyWith(
        backgroundColor: Colors.transparent,
        selectedColor: scheme.secondaryContainer,
        color: WidgetStateProperty.resolveWith((s) => on(s) ? scheme.secondaryContainer : Colors.transparent),
        checkmarkColor: scheme.onSecondaryContainer,
        showCheckmark: true,
        // The same width picked or not: only the colour of the line changes.
        side: WidgetStateBorderSide.resolveWith((s) => BorderSide(color: on(s) ? Colors.transparent : scheme.outline)),
        shape: RoundedRectangleBorder(borderRadius: LayoutPrefs.corner(8)),
        labelStyle: theme.textTheme.labelLarge?.copyWith(
          color: WidgetStateColor.resolveWith((s) => on(s) ? scheme.onSecondaryContainer : scheme.onSurfaceVariant),
        ),
      ),
      child: child,
    );
  }
}

/// The corners of Search's larger surfaces (the suggestions, the top result): a Material 3 shape of [base], square
/// when Settings asks for square corners and never rounder than the spec.
BorderRadius searchSurfaceCorners([double base = 28]) =>
    BorderRadius.circular(LayoutPrefs.radius(base).clamp(0, base).toDouble());

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
      borderRadius: searchSurfaceCorners(16),
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
              padding: const EdgeInsets.all(16),
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
