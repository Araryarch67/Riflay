import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records what the player is asked to open; everything else answers at once.
class _Player extends AudioPlayerPlatform {
  _Player(super.id);

  static final loads = <LoadRequest>[];
  final _events = StreamController<PlaybackEventMessage>.broadcast();

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => const Stream.empty();

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    loads.add(request);
    _events.add(
      PlaybackEventMessage(
        processingState: ProcessingStateMessage.ready,
        updateTime: DateTime.now(),
        updatePosition: request.initialPosition ?? Duration.zero,
        bufferedPosition: Duration.zero,
        duration: const Duration(minutes: 3),
        icyMetadata: null,
        currentIndex: request.initialIndex ?? 0,
        androidAudioSessionId: null,
      ),
    );
    return LoadResponse(duration: const Duration(minutes: 3));
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async => PlayResponse();
  @override
  Future<PauseResponse> pause(PauseRequest request) async => PauseResponse();
  @override
  Future<SeekResponse> seek(SeekRequest request) async => SeekResponse();
  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async => SetVolumeResponse();
  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async => SetSpeedResponse();
  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async => SetPitchResponse();
  @override
  Future<SetSkipSilenceResponse> setSkipSilence(SetSkipSilenceRequest request) async => SetSkipSilenceResponse();
  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async => SetLoopModeResponse();
  @override
  Future<SetShuffleModeResponse> setShuffleMode(SetShuffleModeRequest request) async => SetShuffleModeResponse();
  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(SetShuffleOrderRequest request) async => SetShuffleOrderResponse();
  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse> setAutomaticallyWaitsToMinimizeStalling(
    SetAutomaticallyWaitsToMinimizeStallingRequest request,
  ) async => SetAutomaticallyWaitsToMinimizeStallingResponse();
  @override
  Future<SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse>
  setCanUseNetworkResourcesForLiveStreamingWhilePaused(
    SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest request,
  ) async => SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse();
  @override
  Future<SetPreferredPeakBitRateResponse> setPreferredPeakBitRate(SetPreferredPeakBitRateRequest request) async =>
      SetPreferredPeakBitRateResponse();
  @override
  Future<SetAllowsExternalPlaybackResponse> setAllowsExternalPlayback(SetAllowsExternalPlaybackRequest request) async =>
      SetAllowsExternalPlaybackResponse();
  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
    SetAndroidAudioAttributesRequest request,
  ) async => SetAndroidAudioAttributesResponse();
  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async => DisposeResponse();
}

class _Platform extends JustAudioPlatform {
  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async => _Player(request.id);
  @override
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) async => DisposePlayerResponse();
  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(DisposeAllPlayersRequest request) async =>
      DisposeAllPlayersResponse();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Play on a restored queue opens the song on screen, even after a seek', () async {
    JustAudioPlatform.instance = _Platform();
    Track song(String id) => Track(id: id, uri: Uri.file('/music/$id.wav'), title: id, artist: 'Artist');
    SharedPreferences.setMockInitialValues({
      'library.v1': '[]',
      'autoplay.v1': false,
      'discord.enabled': false,
      'playback.queue.v1': jsonEncode({
        'tracks': [song('first').toJson(), song('shown').toJson()],
        'index': 1,
        'positionMs': 5000,
      }),
    });
    final c = PlayerController();
    addTearDown(c.dispose);
    await c.load();
    expect(c.currentTrack?.id, 'shown');
    await c.seek(const Duration(seconds: 8));
    unawaited(c.play());
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(_Player.loads.last.initialIndex, 1, reason: 'the song on screen, not the first in the queue');
    expect(c.currentTrack?.id, 'shown');
  });
}
