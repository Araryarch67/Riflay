import 'package:flutter/foundation.dart';

/// One line of the tray menu: a label that does [onTap], greyed out without one, or a divider.
@immutable
class TrayEntry {
  const TrayEntry(this.label, [this.onTap]) : divider = false;
  const TrayEntry.divider() : label = '', onTap = null, divider = true;

  final String label;
  final VoidCallback? onTap;
  final bool divider;

  bool get enabled => onTap != null;
}
