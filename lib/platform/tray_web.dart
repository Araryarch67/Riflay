import 'package:flutter/foundation.dart';

import 'tray_entry.dart';

/// A browser tab has no tray. See `tray.dart`.
class NativeTray {
  NativeTray._();

  static Future<bool> available() async => false;

  static Future<NativeTray?> show({required String tooltip, required VoidCallback onOpen}) async => null;

  Future<void> setMenu(List<TrayEntry> entries) async {}

  Future<void> remove() async {}
}
