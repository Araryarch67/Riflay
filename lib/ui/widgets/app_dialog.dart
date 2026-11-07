import 'package:flutter/material.dart';

import '../../services/language.dart';
import '../theme.dart';

/// Gaps inside a dialog, so every popup breathes the same way: [section] between groups of options, [label]
/// under a group's heading, [note] above a muted line that explains the pick.
abstract final class DialogGap {
  static const double section = 24;
  static const double label = 12;
  static const double note = 8;
}

/// How wide a dialog gets on a computer. On a phone it is the screen less a 16 px margin each side.
abstract final class DialogWidth {
  /// A question or a short message.
  static const double compact = 400;

  /// Options in groups, or a form.
  static const double regular = 480;

  /// A list or a preview that needs the room.
  static const double wide = 560;
}

/// Riflay's dialog: a headline, content that scrolls when it doesn't fit, and one row of actions. The main
/// action goes last in [actions] (a [FilledButton]), Cancel before it (a [TextButton]). A [destructive] action
/// (Delete, Sign out) sits apart on the left, so it is never next to the button people mean to press.
///
/// Built on [Dialog] rather than [AlertDialog]: AlertDialog lays its actions out in an [OverflowBar], which has
/// no room for a left-hand action, and its content has no width of its own, so dialogs grew and shrank with
/// whatever they showed. Shape and colour come from the theme's `dialogTheme` (corners follow Layout).
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
    this.destructive,
    this.icon,
    this.width = DialogWidth.regular,
    this.scrollable = true,
    this.contentPadding,
  });

  /// The headline: a [Text] (a [String] is turned into one).
  final Object title;
  final Widget content;
  final List<Widget> actions;
  final Widget? destructive;

  /// Shown centred above a centred title, as Material does for an alert.
  final Widget? icon;
  final double width;

  /// False when [content] scrolls itself (a list) or must not scroll (a field that should stay in view).
  final bool scrollable;

  /// Defaults to 24 at the sides; a list that runs edge to edge passes zero.
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = MediaQuery.sizeOf(context).width < 600;
    final titleStyle = (theme.dialogTheme.titleTextStyle ?? theme.textTheme.headlineSmall)?.copyWith(
      color: AppColors.textPrimary,
    );
    final heading = title is Widget ? title as Widget : Text('$title');
    final padding = contentPadding ?? const EdgeInsets.symmetric(horizontal: 24);
    final body = scrollable
        ? SingleChildScrollView(padding: padding, child: content)
        : Padding(padding: padding, child: content);
    return Dialog(
      insetPadding: phone
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: icon == null ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    IconTheme.merge(
                      data: IconThemeData(size: 24, color: AppColors.accent),
                      child: icon!,
                    ),
                    const SizedBox(height: 16),
                  ],
                  DefaultTextStyle.merge(
                    style: titleStyle,
                    textAlign: icon == null ? TextAlign.start : TextAlign.center,
                    child: Semantics(header: true, child: heading),
                  ),
                ],
              ),
            ),
            Flexible(
              child: DefaultTextStyle.merge(
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                child: body,
              ),
            ),
            if (actions.isNotEmpty || destructive != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: DialogActions(destructive: destructive, children: actions),
              )
            else
              const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// The actions row: [children] at the end, [destructive] alone at the start. When a narrow phone can't fit them
/// on one line the main actions stay on top and the destructive one goes under them, both at the end.
class DialogActions extends StatelessWidget {
  const DialogActions({super.key, this.destructive, required this.children});

  final Widget? destructive;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final leading = destructive;
    if (leading == null) {
      return OverflowBar(
        alignment: MainAxisAlignment.end,
        overflowAlignment: OverflowBarAlignment.end,
        spacing: 8,
        overflowSpacing: 8,
        children: children,
      );
    }
    // A Wrap, not an OverflowBar: an OverflowBar takes the whole width, which would push the destructive action
    // onto a line of its own even where both fit. On the narrowest phones the Wrap still breaks its own line.
    final main = Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: children);
    return OverflowBar(
      alignment: MainAxisAlignment.spaceBetween,
      overflowAlignment: OverflowBarAlignment.end,
      overflowDirection: VerticalDirection.up,
      overflowSpacing: 8,
      children: [leading, main],
    );
  }
}

/// A destructive action for [AppDialog.destructive] or a confirmation: error-coloured, with no fill (it is never
/// the main action of a dialog that does something else).
class DestructiveButton extends StatelessWidget {
  const DestructiveButton({super.key, required this.onPressed, required this.child, this.filled = false});

  final VoidCallback? onPressed;
  final Widget child;

  /// For a dialog whose only purpose is the destructive step ("Delete this playlist?").
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return filled
        ? FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
            onPressed: onPressed,
            child: child,
          )
        : TextButton(
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            onPressed: onPressed,
            child: child,
          );
  }
}

/// A group of options in a dialog: its heading, the controls, and an optional muted line under them.
class DialogSection extends StatelessWidget {
  const DialogSection({super.key, required this.label, required this.child, this.note, this.trailing});

  final String label;
  final Widget child;
  final Widget? note;

  /// Beside the heading (a "Recommended" tag, a reset link).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                label,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
        const SizedBox(height: DialogGap.label),
        child,
        if (note != null) ...[
          const SizedBox(height: DialogGap.note),
          DefaultTextStyle.merge(
            style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
            child: note!,
          ),
        ],
      ],
    );
  }
}

/// [children] with [DialogGap.section] between them: a dialog's content, without hand-placed gaps.
class DialogBody extends StatelessWidget {
  const DialogBody({super.key, required this.children, this.gap = DialogGap.section});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
    ],
  );
}

/// A small pill beside a choice: "Recommended". [onSelected] is for a tag inside a selected chip, whose fill is
/// the accent the tag would otherwise be drawn in.
class DialogTag extends StatelessWidget {
  const DialogTag(this.label, {super.key, this.onSelected = false});

  final String label;
  final bool onSelected;

  @override
  Widget build(BuildContext context) {
    final ink = onSelected ? AppColors.onAccent : AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: ink.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: ink, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Asks a yes-or-no question; true when [confirmLabel] was pressed. [destructive] colours that button as a
/// warning (deleting, signing out).
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? body,
  Widget? content,
  required String confirmLabel,
  Widget? icon,
  bool destructive = false,
  bool useRootNavigator = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    useRootNavigator: useRootNavigator,
    builder: (context) => AppDialog(
      title: title,
      icon: icon,
      width: DialogWidth.compact,
      content: content ?? Text(body ?? ''),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr.cancel)),
        destructive
            ? DestructiveButton(filled: true, onPressed: () => Navigator.pop(context, true), child: Text(confirmLabel))
            : FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(confirmLabel)),
      ],
    ),
  );
  return ok == true;
}
