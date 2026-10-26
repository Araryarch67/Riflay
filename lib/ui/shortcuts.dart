import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

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
}

/// Every keyboard shortcut of the app. The shell binds these and the
/// "Keyboard shortcuts" dialog lists them, so the two can't drift apart.
const appShortcuts = <AppShortcut>[
  AppShortcut(AppAction.playPause, 'Play or pause', [
    SingleActivator(LogicalKeyboardKey.space),
    SingleActivator(LogicalKeyboardKey.mediaPlayPause),
  ], 'Space'),
  AppShortcut(AppAction.next, 'Next song', [
    SingleActivator(LogicalKeyboardKey.arrowRight, control: true),
    SingleActivator(LogicalKeyboardKey.mediaTrackNext),
  ], 'Ctrl+→'),
  AppShortcut(AppAction.previous, 'Previous song', [
    SingleActivator(LogicalKeyboardKey.arrowLeft, control: true),
    SingleActivator(LogicalKeyboardKey.mediaTrackPrevious),
  ], 'Ctrl+←'),
  AppShortcut(AppAction.volumeUp, 'Volume up', [SingleActivator(LogicalKeyboardKey.arrowUp, control: true)], 'Ctrl+↑'),
  AppShortcut(AppAction.volumeDown, 'Volume down', [
    SingleActivator(LogicalKeyboardKey.arrowDown, control: true),
  ], 'Ctrl+↓'),
  AppShortcut(AppAction.search, 'Search', [SingleActivator(LogicalKeyboardKey.keyK, control: true)], 'Ctrl+K'),
  AppShortcut(AppAction.back, 'Go back', [SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true)], 'Alt+←'),
  AppShortcut(AppAction.forward, 'Go forward', [SingleActivator(LogicalKeyboardKey.arrowRight, alt: true)], 'Alt+→'),
  AppShortcut(AppAction.pasteLink, 'Import a copied YouTube link', [
    SingleActivator(LogicalKeyboardKey.keyV, control: true),
    SingleActivator(LogicalKeyboardKey.keyV, meta: true),
  ], 'Ctrl+V'),
  AppShortcut(
    AppAction.fullScreen,
    'Full screen player',
    [SingleActivator(LogicalKeyboardKey.f11)],
    'F11',
    wideLayoutOnly: true,
  ),
  AppShortcut(AppAction.help, 'Show this list', [
    CharacterActivator('?'),
    SingleActivator(LogicalKeyboardKey.slash, control: true),
  ], '? or Ctrl+/'),
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
    if (actions[s.action] case final run? when !(compact && s.wideLayoutOnly))
      for (final a in s.activators) a: run,
};

/// Lists the keyboard shortcuts.
Future<void> showShortcutsDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      backgroundColor: AppColors.elevated,
      title: const Text('Keyboard shortcuts'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in appShortcuts)
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
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  },
);
