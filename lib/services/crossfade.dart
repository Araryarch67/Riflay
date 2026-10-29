import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track.dart';
import 'audio_engine.dart';

/// The decisions behind crossfade, as plain functions (no player involved).
///
/// How it works, in short: a song's last seconds are played a second time by a
/// second player (the "tail"), held in step with the first and silent. When the
/// fade starts the tail takes over the ending song and fades out, while the
/// main player, which owns the queue, jumps to the next song and fades it in.
/// Everything the app shows (the queue position, the song on screen, the media
/// session, the play history) is therefore already the next song's, as it is
/// after a normal skip, and nothing needs handing back at the end.
abstract final class CrossfadeRules {
  static const minSeconds = 1;
  static const maxSeconds = 12;
  static const defaultSeconds = 5;

  /// How long before the fade starts the tail is opened and brought in step.
  static const prepareLead = Duration(seconds: 8);

  /// The share of a song one fade may cover at most.
  static const _longestShare = 0.4;

  /// Whether [next] follows [current] on one album, as a gapless pair does: the next track of
  /// the same album (the next disc's first one counts), or the next part of one cue-sheet file.
  /// Tracks of one album that only happen to be side by side (shuffled) do not flow.
  static bool flowsInto(Track current, Track next) {
    if (current.isCueTrack && next.isCueTrack && current.uri == next.uri) {
      return current.end != null && current.end == next.start;
    }
    String? name(Track t) {
      final a = t.album?.trim().toLowerCase();
      return a == null || a.isEmpty ? null : a;
    }

    final album = name(current);
    if (album == null || album != name(next)) return false;
    final a = current.trackNumber, b = next.trackNumber;
    // No numbers to go by: the same album back to back is an album being played.
    if (a == null || b == null) return true;
    final discA = current.discNumber ?? 1, discB = next.discNumber ?? 1;
    return (discA == discB && b == a + 1) || (discB == discA + 1 && b == 1);
  }

  /// The fade for a pair of songs, or null when they are too short for one (under a second,
  /// or more than [_longestShare] of either song).
  static Duration? fadeLength({required int seconds, required Duration? current, required Duration? next}) {
    if (current == null) return null;
    var fade = Duration(seconds: seconds.clamp(minSeconds, maxSeconds));
    final longest = current * _longestShare;
    if (fade > longest) fade = longest;
    if (next != null && fade > next * _longestShare) fade = next * _longestShare;
    return fade < const Duration(seconds: 1) ? null : fade;
  }

  /// When the fade starts and when to start getting ready, or null when this pair keeps
  /// its normal (gapless) change: [skipAlbums] and the songs flow into each other, or no room for a fade.
  static CrossfadePlan? plan({
    required Track current,
    required Track next,
    required Duration? duration,
    required int seconds,
    required bool skipAlbums,
  }) {
    if (duration == null || (skipAlbums && flowsInto(current, next))) return null;
    final fade = fadeLength(seconds: seconds, current: duration, next: next.duration);
    if (fade == null) return null;
    final start = duration - fade;
    final prepare = start - prepareLead;
    return CrossfadePlan(fade: fade, startAt: start, prepareAt: prepare.isNegative ? Duration.zero : prepare);
  }

  /// Why crossfade can't run, in plain words, or null when it can. [direct] is the sound
  /// going straight to a DAC (exclusive mode, ASIO, a card held directly).
  static String? blockedNote({required bool bitPerfect, required bool direct}) {
    if (bitPerfect) return 'Off while bit-perfect mode is on';
    if (direct) return 'Off while the sound goes straight to your DAC';
    return null;
  }

  /// Whether the tail should be brought in step now.
  static bool shouldPrepare(CrossfadePlan plan, Duration position) =>
      position >= plan.prepareAt && position < plan.startAt - const Duration(milliseconds: 2500);

  /// Whether the fade should start now.
  static bool shouldStart(CrossfadePlan plan, Duration position) => position >= plan.startAt;

  /// Equal-power curves: the loudness stays level through the middle. [x] runs 0 to 1 over the fade.
  static double gainOut(double x) => math.cos(x.clamp(0.0, 1.0) * math.pi / 2);
  static double gainIn(double x) => math.sin(x.clamp(0.0, 1.0) * math.pi / 2);
}

/// When one crossfade happens.
class CrossfadePlan {
  const CrossfadePlan({required this.fade, required this.startAt, required this.prepareAt});

  /// How long both songs sound.
  final Duration fade;

  /// The position in the ending song where the fade starts.
  final Duration startAt;

  /// The position from which the second player is prepared.
  final Duration prepareAt;

  @override
  bool operator ==(Object other) =>
      other is CrossfadePlan && other.fade == fade && other.startAt == startAt && other.prepareAt == prepareAt;

  @override
  int get hashCode => Object.hash(fade, startAt, prepareAt);
}

/// What the crossfade needs to know about the queue.
typedef CrossfadeNext = ({Track current, Track next, int nextIndex})?;

enum _Phase { idle, preparing, ready, fading }

/// Runs crossfades on [main] with a second player (see [CrossfadeRules]).
///
/// It watches the main player and does nothing unless crossfade is on, the pair
/// of songs qualifies and everything can be done in step. Anything that goes wrong
/// (the second player is slow, out of step, an error) drops that one crossfade and
/// the songs change as they always do. A skip, a seek or a pause during a fade
/// ends it on the spot: the next song is already the main player's, so it just
/// goes to full volume.
class Crossfader {
  Crossfader({
    required this.main,
    required this.audio,
    required this.sourceFor,
    required this.upcoming,
    required this.blocked,
  }) {
    _subs.add(main.playingStream.listen((_) => _wake()));
    _subs.add(
      main.positionDiscontinuityStream.listen((d) {
        // Our own jump to the next song is not a seek by the user.
        if (d.reason == PositionDiscontinuityReason.seek && !_jumping) _interrupted();
      }),
    );
    audio.addListener(_wake);
  }

  final AudioPlayer main;
  final AudioEngine audio;
  final AudioSource Function(Track) sourceFor;

  /// The song playing, the one after it, and the one's index; null at the end of the queue.
  final CrossfadeNext Function() upcoming;

  /// True when something other than the settings rules crossfade out (casting, a DSD song, repeat one...).
  final bool Function() blocked;

  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _timer;
  bool _disposed = false;
  bool _busy = false;
  bool _jumping = false;
  _Phase _phase = _Phase.idle;
  AudioPlayer? _tail;

  /// The song the tail was opened for.
  String? _tailFor;

  /// A song that failed once isn't tried again.
  String? _failedFor;
  DateTime _notBefore = DateTime.fromMillisecondsSinceEpoch(0);

  final Stopwatch _clock = Stopwatch();
  CrossfadePlan? _plan;
  CrossfadeNext _fading;
  bool _jumped = false;

  /// Whether a crossfade is running (for the UI, and to hold off other work).
  bool get fading => _phase == _Phase.fading;

  /// How long the two players take over from one another at the start of the fade.
  static const _handover = Duration(milliseconds: 160);

  /// Out of step by more than this (seconds), a sound from the tail would be heard as an echo.
  static const _tolerance = 0.035;

  void _wake() {
    if (_disposed) return;
    final on = audio.crossfadeActive && main.playing;
    if (!on) {
      if (_phase != _Phase.idle) _cancel();
      _timer?.cancel();
      return;
    }
    if (!(_timer?.isActive ?? false) && !_busy) _timer = Timer(const Duration(milliseconds: 20), _tick);
  }

  /// The user paused, skipped or sought: whatever was going on ends.
  void _interrupted() {
    if (_phase == _Phase.idle) return;
    _notBefore = DateTime.now().add(const Duration(milliseconds: 1500));
    _cancel();
  }

  Future<void> _tick() async {
    if (_disposed || _busy) return;
    _busy = true;
    var next = const Duration(seconds: 1);
    try {
      next = await _step();
    } catch (e) {
      debugPrint('Crossfade dropped: $e');
      _failedFor = _tailFor ?? upcoming()?.current.id;
      _cancel();
    } finally {
      _busy = false;
    }
    if (!_disposed && audio.crossfadeActive && main.playing) {
      _timer?.cancel();
      _timer = Timer(next, _tick);
    }
  }

  /// One look at the situation; returns how long until the next one.
  Future<Duration> _step() async {
    if (_phase == _Phase.fading) return _fadeStep();
    final up = upcoming();
    if (blocked() || up == null || !main.playing) {
      if (_phase != _Phase.idle) _cancel();
      return const Duration(seconds: 1);
    }
    if (_tailFor != null && _tailFor != up.current.id) _cancel(); // another song is playing now
    if (_failedFor != up.current.id) _failedFor = null;
    final plan = CrossfadeRules.plan(
      current: up.current,
      next: up.next,
      duration: main.duration,
      seconds: audio.crossfadeSeconds,
      skipAlbums: audio.crossfadeSkipAlbums,
    );
    if (plan == null) {
      if (_phase != _Phase.idle) _cancel();
      return const Duration(seconds: 1);
    }
    final position = main.position;
    switch (_phase) {
      case _Phase.idle:
        if (_failedFor == up.current.id || DateTime.now().isBefore(_notBefore)) return const Duration(seconds: 1);
        if (CrossfadeRules.shouldPrepare(plan, position)) {
          await _prepare(plan, up);
          return const Duration(milliseconds: 20);
        }
        // Wake in time: half the way there, so a seek is noticed within a second.
        final wait = (plan.prepareAt - position).inMilliseconds ~/ 2;
        return Duration(milliseconds: wait.clamp(200, 1000));
      case _Phase.ready:
        if (CrossfadeRules.shouldStart(plan, position)) {
          await _begin(plan, up);
          return const Duration(milliseconds: 20);
        }
        return const Duration(milliseconds: 20);
      case _Phase.preparing:
      case _Phase.fading:
        return const Duration(milliseconds: 20);
    }
  }

  // ── Getting the tail in step ────────────────────────────────────────────

  Future<void> _prepare(CrossfadePlan plan, ({Track current, Track next, int nextIndex}) up) async {
    _phase = _Phase.preparing;
    _tailFor = up.current.id;
    final tail = AudioPlayer(
      handleInterruptions: false,
      androidApplyAudioAttributes: false,
      handleAudioSessionActivation: false,
    );
    _tail = tail;
    try {
      audio.expectSecondaryPlayer();
      try {
        await tail.setAudioSource(
          sourceFor(up.current),
          initialPosition: main.position + const Duration(milliseconds: 1500),
        );
      } finally {
        audio.secondaryPlayerRequested();
      }
      // Silent from the first sample: its volume is set before it plays.
      await audio.setSecondaryGain(0);
      if (_aborted(up)) return;

      // Start it when the main player reaches the spot it waits at, then bring it exactly in step
      // by looking at both players' own clocks.
      var latency = 0.06; // how long a seek or start takes before sound; learned below
      var m = await audio.mainTimePos();
      var t = await audio.secondaryTimePos();
      if (m == null || t == null) throw StateError('no clock');
      if (t - m < latency) {
        await audio.secondarySeek(m + 0.5);
        t = m + 0.5;
      }
      await Future<void>.delayed(Duration(milliseconds: ((t - m - latency) * 1000).round().clamp(0, 2000)));
      if (_aborted(up)) return;
      unawaited(tail.play().catchError((Object _) {}));

      for (var attempt = 0; attempt < 6; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        if (_aborted(up)) return;
        final measured = await _offset();
        if (measured == null) throw StateError('no clock');
        final (off, m) = measured; // positive: the tail is ahead
        if (off.abs() <= _tolerance) {
          if (main.position >= plan.startAt - const Duration(milliseconds: 150)) throw StateError('too late');
          _phase = _Phase.ready;
          return;
        }
        // Seeking lands later by what a seek takes: aim ahead by that, and learn it.
        if (attempt > 0) latency = math.max(0.01, latency - off);
        await audio.secondarySeek(m + latency);
      }
      throw StateError('could not keep in step');
    } catch (e) {
      // Only this attempt's failure counts: a pause or a seek has already dropped it.
      if (_phase == _Phase.preparing && identical(_tail, tail)) {
        debugPrint('Crossfade not possible for this song: $e');
        _failedFor = up.current.id;
        _cancel();
      }
    }
  }

  /// How far the tail is ahead of the main player (negative: behind), and where the main player is.
  /// An mpv clock moves in steps and the two reads are a moment apart, so it is the median of a few.
  Future<(double, double)?> _offset() async {
    final offsets = <double>[];
    double? at;
    for (var i = 0; i < 5; i++) {
      if (i > 0) await Future<void>.delayed(const Duration(milliseconds: 40));
      final now = await Future.wait([audio.mainTimePos(), audio.secondaryTimePos()]);
      final m = now[0], t = now[1];
      if (m == null || t == null) return null;
      offsets.add(t - m);
      at = m;
    }
    offsets.sort();
    return (offsets[offsets.length ~/ 2], at!);
  }

  bool _aborted(({Track current, Track next, int nextIndex}) up) {
    if (_phase != _Phase.preparing || _disposed) return true;
    final gone = !main.playing || upcoming()?.current.id != up.current.id;
    if (gone) _cancel();
    return gone;
  }

  // ── The fade ────────────────────────────────────────────────────────────

  Future<void> _begin(CrossfadePlan plan, ({Track current, Track next, int nextIndex}) up) async {
    _plan = plan;
    _fading = up;
    _jumped = false;
    _phase = _Phase.fading;
    _clock
      ..reset()
      ..start();
  }

  Future<Duration> _fadeStep() async {
    final plan = _plan!;
    final up = _fading!;
    final e = _clock.elapsed;
    final x = e.inMicroseconds / plan.fade.inMicroseconds; // 0 to 1 over the whole fade
    if (x >= 1) {
      _end();
      return const Duration(seconds: 1);
    }
    if (_jumped && !_jumping && main.sequenceState.currentIndex != up.nextIndex) {
      // Skipped (or the queue changed) in the middle of the fade: the new song just plays.
      _cancel();
      return const Duration(seconds: 1);
    }
    if (e < _handover) {
      // The tail takes the ending song over from the main player, which is the same sound.
      final h = e.inMicroseconds / _handover.inMicroseconds;
      await Future.wait([
        audio.setCrossGain(CrossfadeRules.gainOut(h)),
        audio.setSecondaryGain(CrossfadeRules.gainIn(h) * CrossfadeRules.gainOut(x)),
      ]);
      return const Duration(milliseconds: 30);
    }
    if (!_jumped) {
      _jumped = true;
      await audio.setCrossGain(0); // the next song starts silent
      _jumping = true;
      unawaited(
        main
            .seek(Duration.zero, index: up.nextIndex)
            .catchError((Object e) {
              debugPrint('Crossfade could not start the next song: $e');
              _cancel();
            })
            .whenComplete(() => Future<void>.delayed(const Duration(milliseconds: 400), () => _jumping = false)),
      );
    }
    await Future.wait([
      audio.setCrossGain(CrossfadeRules.gainIn(x)),
      audio.setSecondaryGain(CrossfadeRules.gainOut(x)),
    ]);
    return const Duration(milliseconds: 40);
  }

  void _end() {
    _release();
    audio.setCrossGain(1).ignore();
    _phase = _Phase.idle;
  }

  /// Drops whatever was going on: the tail goes, the main player is at full volume.
  void _cancel() {
    final wasFading = _phase == _Phase.fading;
    _release();
    audio.setCrossGain(1).ignore();
    _phase = _Phase.idle;
    if (wasFading) _notBefore = DateTime.now().add(const Duration(seconds: 2));
  }

  void _release() {
    final tail = _tail;
    _tail = null;
    _tailFor = null;
    _plan = null;
    _fading = null;
    _jumped = false;
    _clock.stop();
    audio.releaseSecondary();
    if (tail != null) {
      () async {
        try {
          await tail.stop();
          await tail.dispose();
        } catch (e) {
          debugPrint('Closing the crossfade player: $e');
        }
      }();
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    audio.removeListener(_wake);
    for (final s in _subs) {
      s.cancel();
    }
    _release();
    audio.setCrossGain(1).ignore();
  }
}
