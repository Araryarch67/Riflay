import 'package:flutter/foundation.dart';

/// One line of the tray menu: a label that does [onTap], greyed out without one, a divider, a check item
/// ([checked] not null) or a submenu ([children] not null).
@immutable
class TrayEntry {
  const TrayEntry(this.label, [this.onTap]) : divider = false, checked = null, children = null;
  const TrayEntry.check(this.label, {required bool this.checked, this.onTap}) : divider = false, children = null;
  const TrayEntry.submenu(this.label, List<TrayEntry> this.children) : onTap = null, divider = false, checked = null;
  const TrayEntry.divider() : label = '', onTap = null, divider = true, checked = null, children = null;

  final String label;
  final VoidCallback? onTap;
  final bool divider;

  /// A check item's tick; null for a plain line.
  final bool? checked;

  /// A submenu's lines; null for a plain line.
  final List<TrayEntry>? children;

  bool get enabled => onTap != null || (children?.any((e) => e.enabled) ?? false);
}
