import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme.dart';

/// What floats over the page on glass (sheets, dialogs): the theme's own surface, see-through, over the page blurred,
/// so its words read over any cover and it takes the theme's colour instead of a neutral white or grey.
abstract final class Frosted {
  /// How much the page behind is blurred.
  static const sigma = 28.0;

  /// [child] frosted when panels are glass ([AppColors.glass]); as it is otherwise. Clipped by whatever holds it
  /// (a sheet's or a dialog's rounded material): the blur stays inside it.
  static Widget wrap(Widget child) => AppColors.glass
      ? BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: child,
        )
      : child;
}

/// [showModalBottomSheet], frosted on glass: the theme's surface over the page blurred, the drag handle on it too.
/// Off glass it is a plain sheet ([backgroundColor] as given).
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  BoxConstraints? constraints,
  bool isScrollControlled = false,
  ShapeBorder? shape,
  bool? showDragHandle,
  bool useRootNavigator = false,
  bool useSafeArea = false,
}) {
  if (!AppColors.glass) {
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      backgroundColor: backgroundColor,
      constraints: constraints,
      isScrollControlled: isScrollControlled,
      shape: shape,
      showDragHandle: showDragHandle,
      useRootNavigator: useRootNavigator,
      useSafeArea: useSafeArea,
    );
  }
  // The handle is drawn inside the frosted part, so the whole sheet is glass (the sheet's own handle sits above
  // what the builder makes, outside the blur).
  final handle = showDragHandle ?? Theme.of(context).bottomSheetTheme.showDragHandle ?? false;
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: AppColors.glassPopup,
    clipBehavior: Clip.antiAlias,
    constraints: constraints,
    isScrollControlled: isScrollControlled,
    shape: shape,
    showDragHandle: false,
    useRootNavigator: useRootNavigator,
    useSafeArea: useSafeArea,
    builder: (context) => Frosted.wrap(
      handle
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _Handle(),
                Flexible(child: builder(context)),
              ],
            )
          : builder(context),
    ),
  );
}

/// Material's drag handle: 32 × 4 in a 48 high strip.
class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: Center(
      child: Container(
        width: 32,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.textSecondary.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
  );
}
