import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../services/layout_prefs.dart';
import '../theme.dart';

/// A toast that opens the page associated with its message.
class LinkedToast extends SnackBar {
  LinkedToast(String message, {super.key, required String label, required this.open})
    : super(
        content: Text(message),
        action: SnackBarAction(label: label, onPressed: open),
        persist: false,
      );

  final VoidCallback open;
}

/// Applies the app's glass surface to the existing ScaffoldMessenger queue and actions.
class GlassToastMessenger extends ScaffoldMessenger {
  const GlassToastMessenger({super.key, required super.child});

  @override
  ScaffoldMessengerState createState() => _GlassToastMessengerState();
}

class _GlassToastMessengerState extends ScaffoldMessengerState {
  @override
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    SnackBar snackBar, {
    AnimationStyle? snackBarAnimationStyle,
  }) {
    return super.showSnackBar(
      SnackBar(
        content: _GlassToastFace(snackBar),
        behavior: snackBar.behavior,
        margin: snackBar.margin,
        width: snackBar.width,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        duration: snackBar.duration,
        persist: snackBar.persist,
        showCloseIcon: false,
        dismissDirection: snackBar.dismissDirection,
        hitTestBehavior: snackBar.hitTestBehavior,
        onVisible: snackBar.onVisible,
      ),
      snackBarAnimationStyle: snackBarAnimationStyle,
    );
  }
}

class _GlassToastFace extends StatelessWidget {
  const _GlassToastFace(this.toast);

  final SnackBar toast;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context).snackBarTheme;
    final radius = BorderRadius.circular(LayoutPrefs.radius(14));
    final glass = !LayoutPrefs.lightweight;
    final shape = RoundedRectangleBorder(
      borderRadius: radius,
      side: BorderSide(color: colors.border),
    );
    final action = toast.action;
    final linked = toast is LinkedToast ? toast as LinkedToast : null;
    final content = Material(
      color: colors.elevated.withValues(alpha: glass ? .82 : .96),
      shape: shape,
      child: InkWell(
        onTap: linked == null
            ? null
            : () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar(reason: SnackBarClosedReason.action);
                linked.open();
              },
        borderRadius: radius,
        child: Padding(
          padding: toast.padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: LayoutBuilder(
            builder: (context, box) {
              final text = Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: toast.content);
              final buttons = [
                ?action,
                if (toast.showCloseIcon ?? theme.showCloseIcon ?? false)
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    color: toast.closeIconColor ?? theme.closeIconColor,
                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                    onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
                  ),
              ];
              if (buttons.isEmpty) return text;
              if (box.maxWidth < 290 || MediaQuery.textScalerOf(context).scale(14) > 18) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    text,
                    Wrap(alignment: WrapAlignment.end, children: buttons),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: text),
                  const SizedBox(width: 8),
                  ...buttons,
                ],
              );
            },
          ),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: radius,
      child: glass ? BackdropFilter(filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14), child: content) : content,
    );
  }
}
