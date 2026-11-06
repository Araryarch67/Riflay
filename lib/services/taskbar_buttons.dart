import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:windows_taskbar/windows_taskbar.dart';

import '../platform/host.dart';
import 'player_controller.dart';
import 'language.dart';

/// Windows: Previous, Play / Pause and Next under Riflay's taskbar thumbnail, as music players have, so the
/// song can be controlled from the taskbar without bringing the window up.
///
/// The buttons are set again only when what they show changes (playing, a song loaded, a next song), not on
/// every player notification: each set is a round trip to the shell.
class TaskbarButtons {
  TaskbarButtons._(this._c);

  final PlayerController _c;
  ({bool track, bool playing, bool next})? _shown;

  /// Starts following [c]. Nothing happens off Windows.
  static void start(PlayerController c) {
    if (!Host.isWindows) return;
    final buttons = TaskbarButtons._(c);
    c.addListener(buttons._sync);
    buttons._sync();
  }

  void _sync() {
    final now = (track: _c.currentTrack != null, playing: _c.isPlaying, next: _c.hasNext);
    if (now == _shown) return;
    _shown = now;
    // Greyed out until there is something to control.
    int mode(bool on) => on ? 0 : ThumbnailToolbarButtonMode.disabled;
    unawaited(
      WindowsTaskbar.setThumbnailToolbar([
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/taskbar/previous.ico'),
          tr.previous,
          () => unawaited(_c.previous()),
          mode: mode(now.track),
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon(now.playing ? 'assets/taskbar/pause.ico' : 'assets/taskbar/play.ico'),
          now.playing ? tr.pause : tr.play,
          () => unawaited(_c.togglePlay()),
          mode: mode(now.track),
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/taskbar/next.ico'),
          tr.next,
          () => unawaited(_c.next()),
          mode: mode(now.next),
        ),
      ]).catchError((Object e) => debugPrint('Taskbar buttons: $e')),
    );
  }
}
