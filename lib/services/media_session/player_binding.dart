import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/track.dart';
import '../media_session.dart';
import '../player_controller.dart';
import 'media_session_service.dart';
import 'windows_media_controls.dart';

/// [PlayerController] as the media session sees it. Every command goes to the controller's own methods, so the
/// libmpv pipeline, DSP, bit-perfect output, casting and Listen Together all behave as with the app's buttons.
class PlayerControllerBinding implements MediaSessionPlayer {
  PlayerControllerBinding(this._c);

  final PlayerController _c;

  @override
  void addListener(VoidCallback listener) => _c.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _c.removeListener(listener);

  @override
  Stream<void> get discontinuities {
    final p = _c.player;
    late final StreamController<void> out;
    final subs = <StreamSubscription<Object?>>[];
    out = StreamController<void>(
      onListen: () => subs.addAll([
        // Loading, buffering, playing, completed: the session shows each.
        p.playerStateStream.listen((_) => out.add(null)),
        // A seek, here or from the system, or the next song.
        p.positionDiscontinuityStream.listen((_) => out.add(null)),
        p.durationStream.listen((_) => out.add(null)),
        p.speedStream.listen((_) => out.add(null)),
      ]),
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return out.stream;
  }

  @override
  MediaSessionState snapshot() {
    final t = _c.currentTrack;
    final p = _c.player;
    return MediaSessionState(
      track: t == null ? null : infoOf(t, duration: _c.duration),
      // At the end of the queue just_audio keeps `playing` on although nothing sounds; the system must then offer
      // Play (which starts the queue over), not Pause.
      playing: _c.isPlaying && (_c.casting || p.processingState != ProcessingState.completed),
      processing: _c.casting
          ? (_c.isBuffering ? MediaProcessing.buffering : MediaProcessing.ready)
          : switch (p.processingState) {
              // Between songs, or a song opened but not started: there is something to play.
              ProcessingState.idle => t == null ? MediaProcessing.idle : MediaProcessing.ready,
              ProcessingState.loading => MediaProcessing.loading,
              ProcessingState.buffering => MediaProcessing.buffering,
              ProcessingState.ready => MediaProcessing.ready,
              ProcessingState.completed => MediaProcessing.completed,
            },
      position: _c.position,
      bufferedPosition: p.bufferedPosition,
      speed: p.speed,
      canNext: _c.hasNext,
      // Previous restarts the song when there is none before it.
      canPrevious: t != null,
    );
  }

  /// [t] as the system shows it; [duration] is the player's, known once the song is open.
  static MediaTrackInfo infoOf(Track t, {Duration? duration}) => MediaTrackInfo(
    id: t.id,
    title: t.title,
    artist: t.artist,
    album: t.album,
    duration: duration ?? t.duration,
    artUri: t.streams && t.artworkUrl != null ? Uri.tryParse(t.artworkUrl!) : null,
  );

  @override
  Future<Uri?> artworkFor(MediaTrackInfo track) async {
    final t = _c.currentTrack;
    if (t == null || t.id != track.id) return null;
    return (await MediaSession.artFile(t))?.uri;
  }

  @override
  Future<void> play() => _c.play();

  @override
  Future<void> pause() => _c.pause();

  @override
  Future<void> togglePlayPause() => _c.togglePlay();

  @override
  Future<void> next() => _c.next();

  @override
  Future<void> previous() => _c.previous();

  /// Stop keeps the queue and the place in the song: the system's Stop pauses.
  @override
  Future<void> stop() => _c.pause();

  @override
  Future<void> seek(Duration position) => _c.seek(position);
}

/// Starts Riflay's media session for [c]: Windows SMTC on Windows, audio_service everywhere else (Android
/// MediaSession, iOS / macOS MPRemoteCommandCenter, Linux MPRIS, the browser's Media Session). Once per process.
Future<MediaSessionService> startMediaSession(PlayerController c) async {
  final s = await MediaSessionService.start(PlayerControllerBinding(c), [
    WindowsMediaControls(),
    AudioServiceAdapter(c),
  ]);
  // Back in the foreground, the system is told everything again (it may have dropped the session meanwhile).
  _lifecycle ??= AppLifecycleListener(onStateChange: (state) => MediaSessionService.instance?.handleLifecycle(state));
  return s;
}

AppLifecycleListener? _lifecycle;
