import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;
import 'package:windows_taskbar/windows_taskbar.dart';

import '../platform/host.dart';
import 'player_controller.dart';
import 'language.dart';

/// Windows: Like, Shuffle, Previous, Play / Pause, Next and Repeat under Riflay's taskbar thumbnail, as music
/// players have, so the song can be controlled from the taskbar without bringing the window up. Like is there
/// only for a YouTube Music song while signed in (the shell hides a button left out).
///
/// The buttons are set again only when what they show changes (playing, a song loaded, a next song, shuffle,
/// repeat, liked), not on every player notification: each set is a round trip to the shell.
class TaskbarButtons {
  TaskbarButtons._(this._c);

  final PlayerController _c;
  ({bool track, bool playing, bool next, bool shuffle, LoopMode loop, bool? liked})? _shown;

  /// Starts following [c]. Nothing happens off Windows.
  static void start(PlayerController c) {
    if (!Host.isWindows) return;
    final buttons = TaskbarButtons._(c);
    c.addListener(buttons._sync);
    c.ytMusic.addListener(buttons._sync);
    buttons._sync();
  }

  void _sync() {
    final song = _c.currentTrack;
    final account = _c.ytMusic;
    final now = (
      track: song != null,
      playing: _c.isPlaying,
      next: _c.hasNext,
      shuffle: _c.shuffle,
      loop: _c.loopMode,
      liked: song != null && song.isRemote && account.canEdit ? account.isLiked(song) : null,
    );
    if (now == _shown) return;
    _shown = now;
    // Greyed out until there is something to control.
    int mode(bool on) => on ? 0 : ThumbnailToolbarButtonMode.disabled;
    unawaited(
      WindowsTaskbar.setThumbnailToolbar([
        if (now.liked case final liked?)
          ThumbnailToolbarButton(
            ThumbnailToolbarAssetIcon(liked ? 'assets/taskbar/liked.ico' : 'assets/taskbar/like.ico'),
            liked ? tr.removeFromLiked : tr.addToLiked,
            () => unawaited(account.setLiked(song!, !liked).catchError((Object e) => debugPrint('Like: $e'))),
          ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon(now.shuffle ? 'assets/taskbar/shuffle_on.ico' : 'assets/taskbar/shuffle.ico'),
          now.shuffle ? tr.disableShuffle : tr.enableShuffle,
          () => unawaited(_c.toggleShuffle()),
          mode: mode(now.track),
        ),
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
        // The tooltip says what a click does next: off → all → one → off.
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon(switch (now.loop) {
            LoopMode.off => 'assets/taskbar/repeat.ico',
            LoopMode.all => 'assets/taskbar/repeat_on.ico',
            LoopMode.one => 'assets/taskbar/repeat_one.ico',
          }),
          switch (now.loop) {
            LoopMode.off => tr.enableRepeat,
            LoopMode.all => tr.enableRepeatOne,
            LoopMode.one => tr.disableRepeat,
          },
          () => unawaited(_c.cycleLoopMode()),
          mode: mode(now.track),
        ),
      ]).catchError((Object e) => debugPrint('Taskbar buttons: $e')),
    );
  }
}
