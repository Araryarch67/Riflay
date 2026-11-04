import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

import 'tray_entry.dart';

/// Riflay's icon in the system tray (Windows' notification area, the macOS menu bar, a Linux AppIndicator).
///
/// Windows and macOS open the app on a click and the menu on a right-click; Linux opens the menu on any click.
class NativeTray with TrayListener {
  NativeTray._(this._onOpen);

  final VoidCallback _onOpen;

  /// Whether this desktop shows tray icons. A Linux desktop without a StatusNotifier host (GNOME without
  /// the AppIndicator extension, a bare window manager) would take the icon and show nothing, leaving a
  /// hidden window with no way back, so it counts as having none.
  static Future<bool> available() async {
    if (Platform.isWindows || Platform.isMacOS) return true;
    if (!Platform.isLinux) return false;
    final bus = DBusClient.session();
    try {
      return await bus.nameHasOwner('org.kde.StatusNotifierWatcher');
    } catch (e) {
      debugPrint('Tray: no session bus ($e)');
      return false;
    } finally {
      await bus.close();
    }
  }

  /// Puts the icon in the tray; null when there is no tray to put it in.
  static Future<NativeTray?> show({required String tooltip, required VoidCallback onOpen}) async {
    if (!await available()) return null;
    final tray = NativeTray._(onOpen);
    await trayManager.setIcon(Platform.isWindows ? 'assets/tray/tray.ico' : 'assets/tray/tray.png');
    // An AppIndicator has no hover text.
    if (!Platform.isLinux) await trayManager.setToolTip(tooltip);
    // tray_manager runs a menu item's onClick once per listener: this must stay the only one.
    trayManager.addListener(tray);
    return tray;
  }

  Future<void> setMenu(List<TrayEntry> entries) => trayManager.setContextMenu(
    Menu(
      items: [
        for (final e in entries)
          if (e.divider)
            MenuItem.separator()
          else
            MenuItem(label: _plain(e.label), disabled: !e.enabled, onClick: (_) => e.onTap?.call()),
      ],
    ),
  );

  Future<void> remove() async {
    trayManager.removeListener(this);
    await trayManager.destroy();
  }

  /// Windows reads `&` as a keyboard accelerator; a song called "Rock & Roll" must keep it.
  static String _plain(String label) => Platform.isWindows ? label.replaceAll('&', '&&') : label;

  @override
  void onTrayIconMouseDown() => _onOpen();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();
}
