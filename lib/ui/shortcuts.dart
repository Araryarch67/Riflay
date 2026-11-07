import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/features.dart';
import 'theme.dart';
import '../services/language.dart';
import 'widgets/app_dialog.dart';

/// What a keyboard shortcut does. The shell maps each to a callback.
enum AppAction { playPause, next, previous, volumeUp, volumeDown, search, back, forward, pasteLink, fullScreen, help }

/// One shortcut: the keys that trigger it and how it's shown to people.
class AppShortcut {
  const AppShortcut(this.action, this.label, this.activators, this.keys, {this.wideLayoutOnly = false});

  final AppAction action;
  final String label;
  final List<ShortcutActivator> activators;

  /// How the keys are written in the shortcuts list and in tooltips.
  final String keys;

  /// Only bound in the wide (desktop) layout.
  final bool wideLayoutOnly;

  /// Whether this build has what the shortcut does (pasting a link downloads it, which the web build can't).
  bool get available => action != AppAction.pasteLink || Features.downloads;
}

/// Every keyboard shortcut of the app. The shell binds these and the
/// "Keyboard shortcuts" dialog lists them, so the two can't drift apart.
/// A getter, so the names follow the language shown.
List<AppShortcut> get appShortcuts => <AppShortcut>[
  AppShortcut(AppAction.playPause, tr.scPlayPause, [
    SingleActivator(LogicalKeyboardKey.space),
    SingleActivator(LogicalKeyboardKey.mediaPlayPause),
  ], tr.keySpace),
  AppShortcut(AppAction.next, tr.scNext, [
    SingleActivator(LogicalKeyboardKey.arrowRight, control: true),
    SingleActivator(LogicalKeyboardKey.mediaTrackNext),
  ], 'Ctrl+→'),
  AppShortcut(AppAction.previous, tr.scPrevious, [
    SingleActivator(LogicalKeyboardKey.arrowLeft, control: true),
    SingleActivator(LogicalKeyboardKey.mediaTrackPrevious),
  ], 'Ctrl+←'),
  AppShortcut(AppAction.volumeUp, tr.scVolumeUp, [
    SingleActivator(LogicalKeyboardKey.arrowUp, control: true),
  ], 'Ctrl+↑'),
  AppShortcut(AppAction.volumeDown, tr.scVolumeDown, [
    SingleActivator(LogicalKeyboardKey.arrowDown, control: true),
  ], 'Ctrl+↓'),
  AppShortcut(AppAction.search, tr.navSearch, [SingleActivator(LogicalKeyboardKey.keyK, control: true)], 'Ctrl+K'),
  AppShortcut(AppAction.back, tr.scBack, [SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true)], 'Alt+←'),
  AppShortcut(AppAction.forward, tr.scForward, [SingleActivator(LogicalKeyboardKey.arrowRight, alt: true)], 'Alt+→'),
  AppShortcut(AppAction.pasteLink, tr.scPasteLink, [
    SingleActivator(LogicalKeyboardKey.keyV, control: true),
    SingleActivator(LogicalKeyboardKey.keyV, meta: true),
  ], 'Ctrl+V'),
  AppShortcut(
    AppAction.fullScreen,
    tr.scFullScreen,
    [SingleActivator(LogicalKeyboardKey.f11)],
    'F11',
    wideLayoutOnly: true,
  ),
  AppShortcut(AppAction.help, tr.scHelp, [
    CharacterActivator('?'),
    SingleActivator(LogicalKeyboardKey.slash, control: true),
  ], tr.scSlashOr),
];

/// Whether the device has a keyboard to speak of (shortcuts are listed and named in tooltips).
bool get hasKeyboardShortcuts =>
    defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS;

/// The keys as written on this computer: ⌘ for Ctrl on a Mac, where the shortcut takes Cmd.
String _keysFor(AppShortcut s) {
  final cmd = defaultTargetPlatform == TargetPlatform.macOS && s.activators.any((a) => a is SingleActivator && a.meta);
  return cmd ? s.keys.replaceFirst('Ctrl+', '⌘') : s.keys;
}

/// A tooltip that names the shortcut: `Next (Ctrl+→)`. Just [label] on a phone.
String tipWith(String label, AppAction action) {
  if (!hasKeyboardShortcuts) return label;
  final s = appShortcuts.firstWhere((s) => s.action == action);
  return '$label (${_keysFor(s)})';
}

/// The shell's key map: every shortcut's keys to its callback in [actions]
/// (the wide-layout-only ones are left out when [compact]).
Map<ShortcutActivator, VoidCallback> bindShortcuts(Map<AppAction, VoidCallback> actions, {required bool compact}) => {
  for (final s in appShortcuts)
    if (actions[s.action] case final run? when s.available && !(compact && s.wideLayoutOnly))
      for (final a in s.activators) a: run,
};

/// Lists the keyboard shortcuts.
Future<void> showShortcutsDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) {
    final text = Theme.of(context).textTheme;
    return AppDialog(
      title: Text(tr.keyboardShortcuts),
      width: DialogWidth.regular,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in appShortcuts)
            if (s.available)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(s.label)),
                    Text(_keysFor(s), style: text.bodyMedium?.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr.close))],
    );
  },
);
