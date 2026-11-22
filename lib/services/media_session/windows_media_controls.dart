import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../platform/host.dart';
import 'media_session_service.dart';

/// Windows' System Media Transport Controls: the media flyout (volume / Quick Settings), the lock screen, keyboard
/// media keys (Fn shortcuts included) and Bluetooth headsets, which Windows sends to the app that owns the session,
/// focused or not. The runner holds the session (windows/runner/media_controls.cpp); this side tells it what plays
/// and takes its buttons.
class WindowsMediaControls implements MediaSessionAdapter {
  WindowsMediaControls({MethodChannel? channel, bool? enabled})
    : _channel = channel ?? const MethodChannel(channelName),
      _enabled = enabled ?? Host.isWindows;

  static const channelName = 'riflay/media_session';

  final MethodChannel _channel;
  final bool _enabled;
  void Function(MediaCommand)? _onCommand;
  Map<String, Object?>? _shownMetadata;
  Map<String, Object?>? _shownState;

  @override
  String get name => 'windows_smtc';

  @override
  Future<bool> attach(void Function(MediaCommand) onCommand) async {
    if (!_enabled) return false;
    _onCommand = onCommand;
    _channel.setMethodCallHandler(_onCall);
    try {
      if (await _channel.invokeMethod<bool>('enable') ?? false) return true;
    } on MissingPluginException {
      // A runner without the session (an old build): the in-app shortcuts still work.
    } on PlatformException catch (e) {
      debugPrint('Windows media controls: ${e.message}');
    }
    _channel.setMethodCallHandler(null);
    _onCommand = null;
    return false;
  }

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method != 'command') return null;
    final command = parseCommand(call.arguments);
    if (command != null) _onCommand?.call(command);
    return null;
  }

  /// The runner's `{command, positionMs}` as a command; null for one it doesn't know.
  @visibleForTesting
  static MediaCommand? parseCommand(Object? arguments) {
    if (arguments is! Map) return null;
    return switch (arguments['command']) {
      'play' => const MediaCommand.play(),
      'pause' => const MediaCommand.pause(),
      'toggle' => const MediaCommand.toggle(),
      'next' => const MediaCommand.next(),
      'previous' => const MediaCommand.previous(),
      'stop' => const MediaCommand.stop(),
      'seek' => switch (arguments['positionMs']) {
        final int ms => MediaCommand.seek(Duration(milliseconds: ms)),
        _ => null,
      },
      _ => null,
    };
  }

  @override
  Future<void> update(MediaSessionState state) async {
    final metadata = metadataOf(state);
    if (!mapEquals(metadata, _shownMetadata)) {
      _shownMetadata = metadata;
      await _channel.invokeMethod<void>('metadata', metadata);
    }
    final playback = stateOf(state);
    if (!mapEquals(playback, _shownState)) {
      _shownState = playback;
      await _channel.invokeMethod<void>('state', playback);
    }
  }

  /// The song as the flyout shows it. The cover is a file path or an `http(s)` URL.
  @visibleForTesting
  static Map<String, Object?> metadataOf(MediaSessionState s) {
    final t = s.track;
    if (t == null) return const {'id': null};
    final art = t.artUri;
    return {
      'id': t.id,
      'title': t.title,
      'artist': t.artist,
      'album': t.album ?? '',
      'art': art == null
          ? ''
          : art.scheme == 'file'
          ? art.toFilePath(windows: true)
          : (art.scheme == 'http' || art.scheme == 'https')
          ? art.toString()
          : '',
    };
  }

  /// Play / pause, where the song is and its length, and which buttons work.
  @visibleForTesting
  static Map<String, Object?> stateOf(MediaSessionState s) => {
    'status': s.track == null
        ? 'closed'
        : s.playing
        ? 'playing'
        : s.processing == MediaProcessing.completed
        ? 'stopped'
        : s.processing == MediaProcessing.loading
        ? 'changing'
        : 'paused',
    'positionMs': s.position.inMilliseconds,
    'durationMs': s.duration?.inMilliseconds ?? 0,
    'rate': s.speed,
    'canNext': s.canNext,
    'canPrevious': s.canPrevious,
  };

  @override
  Future<void> detach() async {
    _onCommand = null;
    _shownMetadata = null;
    _shownState = null;
    _channel.setMethodCallHandler(null);
    try {
      await _channel.invokeMethod<void>('disable');
    } on MissingPluginException {
      // Nothing to take down.
    }
  }
}
