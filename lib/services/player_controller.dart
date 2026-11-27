import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show ValueListenable, listEquals, visibleForTesting;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import '../platform/background.dart';
import '../platform/host.dart';
import '../platform/network.dart';
import 'audio_engine.dart';
import 'listen_together/listen_together.dart';
import 'cast.dart';
import 'crossfade.dart';
import 'cue_sheet.dart';
import 'discord_presence.dart';
import 'dlna.dart';
import 'dop.dart';
import 'ffmpeg.dart';
import 'folder_watch.dart';
import 'download_prefs.dart';
import 'ios_folders.dart';
import 'audio_analysis.dart';
import 'layout_prefs.dart';
import 'library_store.dart';
import 'lyrics.dart';
import 'lyrics_translation.dart';
import 'media_session.dart';
import 'lock_screen_lyrics.dart';
import 'connection.dart';
import 'metadata.dart';
import 'download_files.dart' show nameDownload;
import 'mv_sidecar.dart';
import 'sacd.dart';
import 'sleep_timer.dart';
import 'soundcloud.dart';
import 'merged_download.dart';
import 'smart_merge.dart';
import 'manual_audio.dart';
import 'playlist_covers.dart';
import 'playlist_transfer.dart';
import 'radio_queue.dart';
import 'request_gate.dart';
import 'sources/music_sources.dart';
import 'soundcloud_audio_source.dart';
import 'monochrome_audio_source.dart';
import 'monochrome.dart';
import 'spotiflac_audio_source.dart';
import 'spotify_audio_source.dart';
import 'shuffle.dart';
import 'memory_trim.dart';
import 'youtube_audio_source.dart';
import 'youtube_music_account.dart';
import 'youtube_importer.dart';
import 'youtube_stream.dart';
import 'ytdlp.dart';
import 'library_views.dart';
import 'ui_beat.dart';
import 'video_mode.dart';
import 'language.dart';
import '../ui/debug_switches.dart';

export '../ui/player_scope.dart';

/// Android: "Add folder" was refused the permission to read music.
class MusicPermissionDenied implements Exception {
  const MusicPermissionDenied();
}

class MusicFolderAlreadyAdded implements Exception {
  const MusicFolderAlreadyAdded();
}

/// Owns the audio player, the library and the play queue.
class PlayerController extends ChangeNotifier {
  PlayerController({
    SmartMerge? smartMerge,
    // StreamAudioSource is just_audio's supported custom-stream interface.
    // ignore: experimental_member_use
    StreamAudioSource Function(Track)? youtubeSource,
    @visibleForTesting this.radioLookup,
  }) : _smartMerge = smartMerge ?? SmartMerge.instance,
       // The public injection keeps test playback isolated from real accounts.
       // ignore: prefer_initializing_formals
       _youtubeSource = youtubeSource {
    soundcloud = SoundcloudClient.instance;
    // The first YouTube song then needs one request, not two.
    YoutubeStream.warmUp();
    sleep.attach(_SleepHost(this));
    // The proxy answers CORS: asked for that way, the song's samples reach the web build's effects and visualizer.
    if (AudioEngine.webEffects) player.setWebCrossOrigin(WebCrossOrigin.anonymous).ignore();
    AudioSession.instance.then((session) {
      if (_disposed) return;
      _watchAudioRoutes(session);
    }, onError: (Object e) => debugPrint('Audio session unavailable: $e'));
    // Direct USB (Android): what is queued for the DAC follows pause and play, and is dropped on a seek or a
    // jump to another song; a song running into the next one keeps flowing.
    _subs.add(player.playingStream.listen((on) => on ? audio.directUsb.play() : audio.directUsb.pause()));
    _subs.add(
      player.positionDiscontinuityStream.listen((d) {
        if (d.reason == PositionDiscontinuityReason.seek) {
          audio.directUsb.flush();
          _saveQueue();
        }
      }),
    );
    // Smart merge: a song playing from its better sound's download is watched; the next song is got ready.
    _subs.add(player.sequenceStateStream.listen((_) => _followSmartMerge()));
    // The choice of sound is made once the song is the player's current one: that is when it starts being watched.
    _smartMerge.changes.addListener(_followSmartMerge);
    _crossfader = Crossfader(
      main: player,
      audio: audio,
      sourceFor: _sourceFor,
      upcoming: _crossfadeUpcoming,
      blocked: _crossfadeBlocked,
    );
    _subs.add(
      // just_audio re-emits the sequence state with every position update
      // (several times a second); only a real queue / song change matters here.
      player.sequenceStateStream
          .distinct(
            (a, b) =>
                a.currentIndex == b.currentIndex &&
                a.loopMode == b.loopMode &&
                a.shuffleModeEnabled == b.shuffleModeEnabled &&
                listEquals(a.sequence, b.sequence),
          )
          .listen((_) {
            _saveQueue();
            if (_restoringQueue) {
              notifyListeners();
              return;
            }
            _maybeAutoplay();
            _followQueueRules();
            _followSoundcloudExpiry();
            _castFollow();
            _followDop();
            _prefetchNext();
            _prefetchDownloadFormats();
            _measureForLeveling();
            _recordRecent();
            _updatePresence();
            MemoryTrim.schedule();
            notifyListeners();
          }),
    );
    _subs.add(
      player.playerStateStream.listen((state) {
        _watchStall(state);
        if (!state.playing) _saveQueue();
        if (state.processingState == ProcessingState.completed) {
          _saveLongPosition();
          if (_stopAfter != null && identical(_stopAfter, player.sequenceState.currentSource)) {
            _stopAfter = null;
            unawaited(pause());
            notifyListeners();
            return;
          }
          YoutubeAudioSource.retainCache({});
          // The queue ran out: if autoplay hasn't added anything yet (or its last try failed), add now.
          _maybeAutoplay();
        }
        _recordRecent();
        _updatePresence();
        notifyListeners();
      }),
    );
    _subs.add(player.durationStream.listen(_correctDuration));
    _subs.add(player.errorStream.listen(_onPlaybackError));
    // Seeks move the Discord progress bar; track/play-state changes are covered above.
    _subs.add(player.positionDiscontinuityStream.listen((_) => _updatePresence(force: true)));
    // Plays count towards the YouTube Music history (signed in, setting on).
    _subs.add(ytMusic.reportPlaysOf(player, secondTicks(), () => currentTrack));
    _subs.add(secondTicks().listen(_endPreview));
    // Lets a song's music-video formats be looked up ahead with its audio ones.
    YoutubeStream.musicVideoIdLookup = (id) async => (await ytMusic.musicVideo(id))?.videoId;
    YtDlp.accountCookies = () => ytMusic.downloadCookies;
  }

  final SmartMerge _smartMerge;
  final _manualAudio = ManualAudio();

  ManualAudioChoice? audioChoice(Track track) => track.videoId == null ? null : _manualAudio.choice(track.videoId!);

  /// Changes only the audio, retaining YouTube metadata, queue, position and pause state.
  /// A null choice restores automatic Smart Merge for this song.
  Future<void> setAudioChoice(Track track, ManualAudioChoice? choice) async {
    final id = track.videoId;
    if (id == null || casting) throw StateError('Audio source cannot be changed here');
    if (choice?.track?.path case final path? when !File(path).existsSync()) {
      throw StateError('Audio file is unavailable');
    }
    await _manualAudio.set(id, choice);
    _smartMerge.resetPlayback(id);
    if (_disposed) return;
    final state = player.sequenceState;
    final index = state.currentIndex;
    final current = currentTrack;
    if (index != null && state.sequence.any((source) => (source.tag as Track).videoId == id)) {
      _cancelPlaybackRetry();
      _lateWatch?.cancel();
      final generation = _playbackRetryGeneration;
      final wasPlaying = player.playing;
      final length = current?.videoId == id ? choice?.track?.duration : null;
      final position = length != null && length > Duration.zero && player.position >= length
          ? length - const Duration(milliseconds: 1)
          : player.position;
      _quality = null;
      _qualityComplete = false;
      _qualityReads = 0;
      _qualityTimer?.cancel();
      await player.setAudioSources(
        [for (final source in state.sequence) _sourceFor(source.tag as Track)],
        initialIndex: index,
        initialPosition: position,
      );
      // Android's native backend applies initialPosition asynchronously. An
      // explicit seek after loading also commits it while the song is paused.
      if (!_disposed && generation == _playbackRetryGeneration) await player.seek(position);
      if (wasPlaying && !_disposed && generation == _playbackRetryGeneration) unawaited(_play());
    }
    notifyListeners();
  }

  // ignore: experimental_member_use
  final StreamAudioSource Function(Track)? _youtubeSource;

  String? _formatsFor;

  /// A few seconds into a YouTube song, looks up its download formats, so the picker is ready when tapped.
  void _prefetchDownloadFormats() {
    if (Host.isWeb) return; // no downloads in a browser
    final t = currentTrack;
    final id = t != null && t.isRemote ? t.videoId : null;
    if (id == null || id == _formatsFor) return;
    _formatsFor = id;
    Timer(const Duration(seconds: 3), () {
      if (_formatsFor == id && currentTrack?.videoId == id) YoutubeStream.prefetchDownloadCandidatesIfAllowed(id);
    });
  }

  static const _autoplayKey = 'autoplay.v1';

  bool _autoplay = true;

  /// Like YouTube Music: when the queue runs out, keep going with similar songs.
  bool get autoplay => _autoplay;

  Future<void> setAutoplay(bool value) async {
    _autoplay = value;
    notifyListeners();
    _maybeAutoplay();
    await (await SharedPreferences.getInstance()).setBool(_autoplayKey, value);
  }

  /// Songs the queue gained from autoplay (the queue page labels them).
  final Set<String> _autoplayed = {};
  bool isAutoplayed(Track t) => _autoplayed.contains(t.id);

  String? _autoplaySeed;
  int? _autoplayGeneration;
  bool _regenerating = false;
  bool get regenerating => _regenerating;
  int _radioGeneration = 0;
  Future<bool> regenerateQueue() async => await _regenerateQueue() != null;

  Future<List<Track>?> _regenerateQueue({Track? radioSeed}) async {
    if (holdAutoplay || _regenerating || (radioSeed == null && currentTrack == null)) return null;
    _regenerating = true;
    var generation = ++_radioGeneration;
    notifyListeners();
    try {
      if (radioSeed != null && !_matchesRadioSeed(currentTrack, radioSeed)) {
        final started = playList([radioSeed], 0, from: tr.radioFrom(radioSeed.title));
        generation = _radioGeneration;
        await started;
        if (generation != _radioGeneration || !_matchesRadioSeed(currentTrack, radioSeed)) return null;
      }
      final original = player.sequenceState;
      final current = currentTrack;
      if (current == null || original.currentIndex == null) return null;
      final seed = radioSeed ?? _autoplaySeedFor(current);
      final similar = await _radioFor(seed, station: radioSeed != null);
      final state = player.sequenceState;
      if (generation != _radioGeneration ||
          !identical(state.currentSource, original.currentSource) ||
          !listEquals(state.sequence, original.sequence)) {
        return null;
      }
      final cut = state.currentIndex! + 1;
      final retained = state.sequence.take(cut).map((s) => s.tag as Track).toList();
      final fresh = RadioQueue.arrange(
        seed: seed,
        candidates: _playableQueueTracks(similar).where(_canRecommend),
        excluded: retained,
      );
      if (fresh.isEmpty) return null;
      await player.addAudioSources([for (final t in fresh) _sourceFor(t)]);
      if (generation != _radioGeneration) return null;
      if (cut < state.sequence.length) await player.removeAudioSourceRange(cut, state.sequence.length);
      if (generation != _radioGeneration) return null;
      _ordered = [...retained, ...fresh];
      _autoplayed
        ..clear()
        ..addAll(fresh.map((t) => t.id));
      _autoplaySeed = current.id;
      if (radioSeed != null) playingFrom = tr.radioFrom(radioSeed.title);
      _saveQueue();
      if (!casting && player.playing && player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero, index: cut);
        unawaited(_play());
      }
      return generation == _radioGeneration ? [current, ...fresh] : null;
    } catch (e) {
      debugPrint('Regenerate queue: $e');
      return null;
    } finally {
      _regenerating = false;
      notifyListeners();
      if (generation != _radioGeneration) _maybeAutoplay();
    }
  }

  /// Set while following someone in Listen together: the host decides what plays next.
  bool holdAutoplay = false;

  /// The most recent song linked to YouTube Music, used when the current song has no artist metadata.
  @visibleForTesting
  static Track? autoplaySeedIn(List<Track> queue, int at) {
    for (var i = at.clamp(-1, queue.length - 1); i >= 0; i--) {
      if (queue[i].youtubeId != null) return queue[i];
    }
    return null;
  }

  Track _autoplaySeedFor(Track current) => current.youtubeId != null || current.artists.isNotEmpty
      ? current
      : autoplaySeedIn(queue, queueIndex ?? queue.length - 1) ?? current;

  /// What could follow [seed]. A song streaming from a service gets that service's recommendations only. A song
  /// from this device (a download or the person's own file) gets YouTube Music's recommendations for its match
  /// when there is one (a download's own video, else a search by artist and title), plus songs from the library
  /// like it. Offline, or when nothing matches, the library alone keeps it going. A [station] mixes the two in
  /// turn; autoplay keeps YouTube Music's first and the library after.
  Future<List<Track>> _radioFor(Track seed, {bool station = false}) async {
    Future<List<Track>> online() =>
        radioLookup?.call(seed) ?? RadioQueue.load(seed, searchSongs: ytMusic.searchSongs, upNext: ytMusic.upNext);
    if (seed.streams) return online();
    final fromLibrary = _libraryRadioFor(seed, station: station);
    List<Track> recommended;
    try {
      recommended = await online().timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('Radio for a song on this device, YouTube Music skipped: $e');
      recommended = const [];
    }
    return station ? RadioQueue.interleave(fromLibrary, recommended) : [...recommended, ...fromLibrary];
  }

  /// Library songs for [seed]'s radio, never one of the recent plays nor (for autoplay) one already queued.
  List<Track> _libraryRadioFor(Track seed, {required bool station}) {
    final recent = _recentIds.take(30).toSet();
    return RadioQueue.fromLibrary(
      seed: seed,
      library: library.where((t) => !recent.contains(t.id)),
      excluded: station ? const [] : queue,
      random: libraryRadioRandom,
    );
  }

  /// Fixed in tests, so the library's part of a radio comes in a known order.
  @visibleForTesting
  math.Random? libraryRadioRandom;

  @visibleForTesting
  final Future<List<Track>> Function(Track)? radioLookup;

  static bool _matchesRadioSeed(Track? current, Track seed) =>
      current?.id == seed.id || (seed.offlineId != null && current?.offlineId == seed.offlineId);

  /// Near the end of the queue (last two songs), appends YouTube Music's
  /// "Up next" for the current song's match on YouTube Music. When the queue already ran out while they were
  /// being looked up, playback carries on with the first of them.
  void _maybeAutoplay() {
    if (_restoringQueue ||
        _regenerating ||
        !_autoplay ||
        holdAutoplay ||
        _autoplayGeneration == _radioGeneration ||
        player.loopMode != LoopMode.off) {
      return;
    }
    final current = currentTrack;
    if (current == null || _autoplaySeed == current.id) return;
    final seq = player.sequenceState;
    final at = seq.currentIndex;
    if (at == null || at < seq.sequence.length - 2) return;
    final seed = _autoplaySeedFor(current);
    _autoplaySeed = current.id;
    final generation = _radioGeneration;
    _autoplayGeneration = generation;
    _radioFor(seed)
        .then((similar) async {
          if (generation != _radioGeneration) return;
          final recentIds = _recentIds.take(30).toSet();
          final fresh = RadioQueue.arrange(
            seed: seed,
            candidates: _playableQueueTracks(similar).where((t) => _canRecommend(t) && !recentIds.contains(t.id)),
            excluded: queue.followedBy(recentlyPlayed.take(30)),
          );
          if (fresh.isEmpty || !_autoplay) return;
          _autoplayed.addAll(fresh.map((t) => t.id));
          _ordered = [..._ordered, ...fresh];
          final firstNew = player.sequenceState.sequence.length;
          await player.addAudioSources([for (final t in fresh) _sourceFor(t)]);
          if (generation != _radioGeneration) return;
          notifyListeners();
          // The last song ended before these arrived: the player sits at the end, so start the first of them.
          if (!casting &&
              player.playing &&
              player.processingState == ProcessingState.completed &&
              player.loopMode == LoopMode.off) {
            await player.seek(Duration.zero, index: firstNew);
            await _play();
          }
        })
        .catchError((Object e) {
          debugPrint('Autoplay failed: $e');
          if (generation == _radioGeneration) _autoplaySeed = null;
        })
        .whenComplete(() {
          if (_autoplayGeneration == generation) _autoplayGeneration = null;
        });
  }

  /// The radios started lately (newest first), as the temporary playlists they began with: Home's "Made for you"
  /// keeps them, so a station can be gone back to after the queue has moved on.
  final recentRadios = ValueNotifier<List<Collection>>(const []);
  static const _recentRadiosKey = 'radio.recent.v1';

  /// Kept across restarts: each station's title, seed artist and songs.
  Future<void> _saveRecentRadios() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _recentRadiosKey,
      jsonEncode([
        for (final r in recentRadios.value)
          {
            'id': r.id,
            'title': r.title,
            'subtitle': r.subtitle,
            'tracks': [for (final t in r.tracks) t.toJson()],
          },
      ]),
    );
  }

  @visibleForTesting
  static List<Collection> recentRadiosFrom(String? saved) {
    if (saved == null) return const [];
    try {
      return [
        for (final r in (jsonDecode(saved) as List).cast<Map>())
          Collection(
            kind: CollectionKind.radio,
            id: r['id'] as String?,
            title: r['title'] as String? ?? '',
            subtitle: r['subtitle'] as String? ?? '',
            tracks: List.unmodifiable([
              for (final t in (r['tracks'] as List? ?? const []).cast<Map>()) Track.fromJson(t.cast()),
            ]),
          ),
      ].where((r) => r.tracks.isNotEmpty).toList(growable: false);
    } catch (e) {
      debugPrint('Recent radios not read: $e');
      return const [];
    }
  }

  /// Starts [seed]'s radio and returns a temporary playlist for the new session.
  Future<Collection?> startRadio(Track seed) async {
    if (_regenerating) return null;
    final session = ListenTogether.of(this);
    if (session.role == ListenRole.guest) {
      await session.suggest(seed);
      return null;
    }
    if (!canQueue(seed)) {
      notify(tr.spotiflacDownloadToPlay);
      return null;
    }
    final tracks = await _regenerateQueue(radioSeed: seed);
    if (tracks != null && !_disposed) {
      final station = Collection(
        kind: CollectionKind.radio,
        // Unique across restarts: kept stations come back with their ids.
        id: 'radio:${DateTime.now().microsecondsSinceEpoch}',
        title: tr.radioFrom(seed.title),
        subtitle: seed.artist,
        tracks: List.unmodifiable(tracks),
      );
      // One per seed song: starting the same radio again replaces the older one.
      recentRadios.value = [
        station,
        ...recentRadios.value.where((old) => old.title != station.title),
      ].take(5).toList(growable: false);
      unawaited(_saveRecentRadios());
      return station;
    }
    if (!_disposed && _matchesRadioSeed(currentTrack, seed)) {
      notify(tr.queueRefreshFailed);
    }
    return null;
  }

  static const _discordAppId = '1561368591297941655';
  static const _discordKey = 'discord.enabled';
  static const _discordOptionsKey = 'discord.options';

  // Read the saved privacy preference before sending the first activity.
  final DiscordPresence discord = DiscordPresence(_discordAppId)..enabled = false;

  bool get discordEnabled => discord.enabled;

  DiscordOptions get discordOptions => discord.options;

  Future<void> setDiscordOptions(DiscordOptions value) async {
    discord.options = value;
    _updatePresence(force: true);
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(_discordOptionsKey, jsonEncode(value.toJson()));
  }

  Future<void> setDiscordEnabled(bool value) async {
    discord.enabled = value;
    _updatePresence(force: true);
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_discordKey, value);
  }

  (Track?, bool, Duration?, String?, String?)? _presenceKey;

  /// In-app screen currently shown (e.g. "home", "library", "search"), for the Discord idle presence.
  String? _browsingLocation;
  String? get browsingLocation => _browsingLocation;

  void setBrowsingLocation(String? location) {
    if (_browsingLocation == location) return;
    _browsingLocation = location;
    if (currentTrack == null || (!isPlaying && !discordOptions.whilePaused)) {
      _updatePresence();
    }
  }

  /// "FLAC · 24-bit / 96 kHz" of the current song for the Discord presence, once mpv has it.
  String? _quality;
  String? get presenceQuality => _quality;
  final _playedQualities = <String, String>{};

  /// Quality of the actual file or selected stream, then catalogue metadata.
  String? qualityOf(Track track) =>
      (currentTrack?.id == track.id ? _quality : null) ??
      _playedQualities[track.id] ??
      downloadedCopy(track)?.qualityLabel ??
      track.qualityLabel;
  bool _qualityComplete = false;
  String? _qualityFor;
  Timer? _qualityTimer;
  int _qualityReads = 0;

  void _updatePresence({bool force = false}) {
    final current = currentTrack;
    final onDevice = casting;
    final track = onDevice
        ? (cast.loadedKey == current?.id ? current : null)
        : (player.processingState == ProcessingState.completed ? null : current);
    final playing = track != null && (onDevice ? cast.playing && !cast.loading : player.playing);
    final length = track == null ? null : (onDevice ? cast.duration : player.duration) ?? track.duration;
    if (track?.id != _qualityFor) {
      _quality = null;
      _qualityComplete = false;
      _qualityFor = track?.id;
      _qualityReads = 0;
      _qualityTimer?.cancel();
    }
    // Skip no-op updates (playerStateStream fires on every buffering change).
    final key = (track, playing, length, _quality, _browsingLocation);
    if (key != _presenceKey || force) {
      _presenceKey = key;
      discord.update(
        track: track,
        playing: playing,
        position: position,
        duration: length,
        quality: _quality,
        browsingLocation: _browsingLocation,
      );
    }
    if (playing && !onDevice) _watchQuality();
  }

  /// With leveling on, the next song (and this one, for next time) is measured if it is a file without a
  /// measurement: its ReplayGain fallback is then ready before it loads. One at a time, in the background.
  Future<void> _measureForLeveling() async {
    if (audio.effectiveLeveling == VolumeLeveling.off || !AudioAnalysis.supported) return;
    final next = upNext;
    for (final t in [?currentTrack, if (next.isNotEmpty) next.first]) {
      final path = AudioAnalysis.fileOf(t);
      if (path == null || AudioAnalysis.savedFor(path) != null) continue;
      try {
        await AudioAnalysis.of(t);
      } catch (e) {
        debugPrint('Measuring ${t.title} for leveling: $e');
      }
    }
  }

  /// mpv knows a song's format and bitrate only once it plays (YouTube's bitrate a little later), so
  /// the signal path is read at 1, 4 and 10 s into a song instead of polled, stopping at the first full label.
  void _watchQuality() {
    if (!AudioEngine.supported || _disposed) return;
    if ((_qualityTimer?.isActive ?? false) || _qualityComplete || _qualityReads >= 3) return;
    final wait = Duration(seconds: const [1, 3, 6][_qualityReads]);
    final id = _qualityFor;
    _qualityTimer = Timer(wait, () async {
      _qualityReads++;
      final path = await audio.signalPath();
      if (_disposed || id != _qualityFor) return;
      _qualityComplete = path?.qualityComplete ?? false;
      final label = path?.qualityText;
      if (label != null && label != _quality) {
        _quality = label;
        if (id != null) {
          _playedQualities.remove(id);
          _playedQualities[id] = label;
          if (_playedQualities.length > 128) _playedQualities.remove(_playedQualities.keys.first);
        }
        _updatePresence(force: true);
        notifyListeners();
      } else if (isPlaying) {
        _watchQuality();
      }
    });
  }

  static const _playlistsKey = 'playlists.v1';
  static const _recentRemoteKey = 'recent.remote.v1';
  static const _recentKey = 'recent.v1';
  static const _maxRecent = 24;

  // Another app's sound (a video, a notification, a game) doesn't pause or duck the music: both play on. Only
  // unplugged headphones pause it (below), so a song doesn't suddenly come out of the speaker.
  final AudioPlayer player = AudioPlayer(handleInterruptions: false);

  /// "Stop the music in 30 minutes": fades the volume down and pauses.
  final SleepTimer sleep = SleepTimer();

  /// Overlaps the end of a song with the start of the next (Settings › Sound › Sound effects (DSP) › Crossfade).
  late final Crossfader _crossfader;

  /// Whether one song is fading into the next right now.
  bool get crossfading => _crossfader.fading;

  /// The sleep timer's fade: a factor on the volume, so the user's own level is never touched.
  void _setSleepFade(double gain) {
    if (casting) return; // the TV or speaker has its own volume; the timer only pauses it
    if (AudioEngine.supported) {
      audio.setSleepGain(gain).ignore();
    } else {
      player.setVolume(gainOfLevel(_level.value) * gain).ignore();
    }
  }

  /// The song playing and the one after it, for the crossfade; null at the end of the queue.
  CrossfadeNext _crossfadeUpcoming() {
    final seq = player.sequenceState;
    final at = seq.currentIndex;
    final i = _neighbour(1);
    if (at == null || i == null || i == at || at >= seq.sequence.length) return null;
    return (current: seq.sequence[at].tag as Track, next: seq.sequence[i].tag as Track, nextIndex: i);
  }

  /// What rules a crossfade out beyond the Settings (which [AudioEngine.crossfadeActive] covers).
  bool _crossfadeBlocked() {
    // Repeat one has no next song; "End of this song" must end at the song's end; a TV plays by itself.
    // A Listen together guest follows the host, who decides what comes next: jumping ahead to the next song
    // here would look like the guest choosing a song of their own (and they would be taken out of the session).
    if (casting || holdAutoplay || player.loopMode == LoopMode.one || sleep.mode == SleepMode.endOfSong) return true;
    // The second player plays at the song's own pace: with a tempo or pitch of its own the two wouldn't meet.
    if (audio.mpvSpeed != 1) return true;
    if (!audio.dopActive) return false;
    final up = _crossfadeUpcoming();
    bool dsd(Track t) => SacdDisc.isSacdTrack(t) || (t.path != null && DsdFile.isDsdPath(t.path!));
    return up == null || dsd(up.current) || dsd(up.next);
  }

  late final YoutubeImporter youtube = YoutubeImporter(
    onTrackReady: (t) => _addTracks([t]),
    musicVideoLookup: (id) => ytMusic.musicVideo(id),
  );

  /// Equalizer, output device, gapless, leveling and the signal path (desktop).
  final AudioEngine audio = AudioEngine();

  /// Signed-in YouTube Music library (official OAuth + YouTube Data API).
  final YoutubeMusicAccount ytMusic = YoutubeMusicAccount();
  final List<StreamSubscription<dynamic>> _subs = [];

  List<Track> _library = [];

  /// The library, read-only (a view, not a copy: widgets ask for it on every build).
  List<Track> get library => _views.library;

  List<String> _recentIds = [];

  /// Human-readable name of whatever the queue was started from.
  String? playingFrom;

  bool _scanning = false;
  bool get scanning => _scanning;

  Track? get currentTrack => player.sequenceState.currentSource?.tag as Track?;

  final _audioTracks = Expando<Track>();

  /// The actual file behind the queue identity, including manual audio and
  /// Smart Merge. Timing must follow the selected recording's own lyrics.
  Track? get currentAudioTrack {
    final source = player.sequenceState.currentSource;
    return source == null ? null : _audioTracks[source] ?? currentTrack;
  }

  List<Track> get queue => player.sequenceState.effectiveSequence.map((s) => s.tag as Track).toList();

  /// Current occurrence in play order, even when a track is queued more than once.
  int? get queueIndex {
    final state = player.sequenceState;
    final source = state.currentSource;
    if (source == null) return null;
    final index = state.effectiveSequence.indexOf(source);
    return index < 0 ? null : index;
  }

  /// Whether anything is queued (without copying the queue, as [queue] does).
  bool get hasQueue => player.sequenceState.sequence.isNotEmpty;

  /// Tracks after the current one in play order.
  final _skipOnce = <IndexedAudioSource>{};
  IndexedAudioSource? _stopAfter, _lastQueueSource;
  bool skipping(IndexedAudioSource source) => _skipOnce.contains(source);
  bool stopping(IndexedAudioSource source) => identical(_stopAfter, source);
  void toggleSkip(IndexedAudioSource source) {
    if (!_skipOnce.remove(source)) _skipOnce.add(source);
    notifyListeners();
  }

  void toggleStop(IndexedAudioSource source) {
    _stopAfter = stopping(source) ? null : source;
    notifyListeners();
  }

  void _followQueueRules() {
    final seq = player.sequenceState;
    final now = seq.currentSource;
    final old = _lastQueueSource;
    _lastQueueSource = now;
    if (_skipOnce.isNotEmpty) _skipOnce.removeWhere((s) => !seq.sequence.contains(s));
    if (_stopAfter != null && !seq.sequence.contains(_stopAfter)) _stopAfter = null;
    if (now == null || identical(old, now)) return;
    if (old != null && stopping(old)) {
      _stopAfter = null;
      unawaited(pause());
    } else if (_skipOnce.remove(now)) {
      unawaited(hasNext ? next() : pause());
    }
  }

  List<Track> get upNext {
    final seq = player.sequenceState;
    return [for (final s in seq.sequence.skip((seq.currentIndex ?? -1) + 1)) s.tag as Track];
  }

  /// The song after the current one, if any.
  Track? get nextTrack {
    final seq = player.sequenceState;
    final i = seq.currentIndex;
    return i == null || i + 1 >= seq.sequence.length ? null : seq.sequence[i + 1].tag as Track;
  }

  final _errors = StreamController<String>.broadcast();

  /// Human-readable playback failures (a stream that wouldn't resolve, a file that's gone).
  Stream<String> get errors => _errors.stream;

  /// Shows [message] in a SnackBar, the way playback failures are, for other long-running work (a FLAC conversion).
  void notify(String message) => _errors.add(message);

  String? _lastError;
  DateTime _lastErrorAt = DateTime(0);
  Future<void>? _closingPlayer;
  bool _cancelledOpening = false;

  /// A stream that fails to resolve shouldn't stall the whole queue: report it and move on.
  void _onPlaybackError(PlayerException e) {
    if (_disposed ||
        _restoringQueue ||
        _closingPlayer != null ||
        _cancelledOpening ||
        (!_starting && player.audioSources.isEmpty)) {
      return;
    }
    if (_retryLoadFailed case final pending? when !pending.isCompleted) {
      pending.complete(false);
      return;
    }
    // Native playlists may report several subsequent failures while the first
    // song is already waiting to recover. Keep that original retry intact.
    if (_playbackRetryTimer?.isActive ?? false) return;
    // mpv reports one failure in several lines ("cannot open file", "failed
    // to open"): handle it once, or the queue would skip past good songs too.
    final now = DateTime.now();
    if (e.message == _lastError && now.difference(_lastErrorAt) < const Duration(seconds: 3)) return;
    _lastError = e.message;
    _lastErrorAt = now;
    // The player's current index can still be the song before (it fails while
    // opening): mpv names the file it couldn't open, so go by that.
    final seq = player.sequenceState.sequence;
    final failed = RegExp(r"'([^']+)'|open (.+)\.$").firstMatch(e.message ?? '');
    final path = failed?.group(1) ?? failed?.group(2);
    final at = path == null
        ? -1
        : seq.indexWhere((s) {
            final track = s.tag as Track;
            return track.path == path || track.uri.toString() == path;
          });
    final index = at >= 0 ? at : e.index ?? player.sequenceState.currentIndex;
    final currentIndex = player.sequenceState.currentIndex;
    // A delayed failure can describe the previous source after a good track has already opened.
    if (!_starting && player.processingState == ProcessingState.ready && index != null && index != currentIndex) {
      return;
    }
    final track = index != null ? seq.elementAtOrNull(index)?.tag as Track? : currentTrack;
    // In plain words: mpv's own message (paths, stream URLs) only goes to the log.
    debugPrint('Playback error: ${e.message}');
    final wasPlaying = player.playing || _starting || _retryWantsPlay;
    _recoverOrReport(track, index, wasPlaying);
  }

  void _recoverOrReport(Track? track, int? index, bool wasPlaying) {
    if (_disposed) return;
    // Streams often fail once and play on the next try (an expired link, a dropped
    // connection): try the same song again a few times before giving up on it.
    if (track != null && index != null && _retryPlayback(track, index, wasPlaying)) return;
    _retryWantsPlay = false;
    notifyListeners();
    // A Spotify song that never starts is nearly always the account: no Premium, or a sign-in that ran out.
    _errors.add(track?.spotifyId != null ? tr.spotifyCantPlay : tr.couldntPlay(track?.title ?? tr.thisSong));
    // Repeat-one would retry the same broken song forever: skip it all the same. A paused player stays paused.
    final next = _neighbour(1, from: index);
    if (next != null) {
      final generation = _playbackRetryGeneration;
      player.seek(Duration.zero, index: next).then((_) {
        if (wasPlaying && generation == _playbackRetryGeneration) _play();
      }, onError: (Object _) {});
    }
  }

  @visibleForTesting
  static List<Duration> playbackRetryDelays = const [
    Duration(milliseconds: 800),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 6),
    Duration(seconds: 10),
    Duration(seconds: 15),
    Duration(seconds: 20),
    Duration(seconds: 20),
  ];
  String? _retryingId;
  int? _retryingIndex;
  int _retries = 0;
  DateTime _lastRetryAt = DateTime(0);
  Timer? _playbackRetryTimer;
  int _playbackRetryGeneration = 0;
  Completer<bool>? _retryLoadFailed;
  Completer<bool>? _openingCancelled;
  bool _retryWantsPlay = false;
  bool get _recovering => (_playbackRetryTimer?.isActive ?? false) || _retryLoadFailed != null;

  void _cancelPlaybackRetry() {
    final wasWaiting = _recovering || _starting;
    _playbackRetryGeneration++;
    _playbackRetryTimer?.cancel();
    _playbackRetryTimer = null;
    final pending = _retryLoadFailed;
    if (pending != null && !pending.isCompleted) pending.complete(false);
    _retryLoadFailed = null;
    final opening = _openingCancelled;
    if (opening != null && !opening.isCompleted) opening.complete(false);
    _openingCancelled = null;
    _starting = false;
    _retryWantsPlay = false;
    _retryingId = null;
    _retryingIndex = null;
    _retries = 0;
    _lastError = null;
    if (wasWaiting) notifyListeners();
  }

  /// True while [playList] waits for its first song to open (the player isn't "playing" yet).
  bool _starting = false;

  /// Resolves and reloads [track] after a backoff, at most [playbackRetryDelays.length] times
  /// in a row. False once it has run out of tries (the caller reports it and moves on).
  bool _retryPlayback(Track track, int index, bool play) {
    if (!track.streams && !const {'https', 'http'}.contains(track.uri.scheme)) return false;
    if (_retryingId == track.id && _retryingIndex == index && (_playbackRetryTimer?.isActive ?? false)) return true;
    final now = DateTime.now();
    // A different song, or one that played fine for a while since: start counting again.
    if (track.id != _retryingId ||
        index != _retryingIndex ||
        now.difference(_lastRetryAt) > const Duration(minutes: 2)) {
      _retryingId = track.id;
      _retryingIndex = index;
      _retries = 0;
    }
    if (_retries >= playbackRetryDelays.length) return false;
    // Each try already fell back to YouTube Music: more tries only keep the player waiting at 0:00.
    if (track.spotifyId != null && _retries >= 2) return false;
    final delay = playbackRetryDelays[_retries++];
    _lastRetryAt = now;
    final attempt = _retries;
    final sameSong = player.sequenceState.currentIndex == index;
    final position = sameSong ? player.position : Duration.zero;
    final generation = _playbackRetryGeneration;
    final failedSource = player.sequenceState.sequence.elementAtOrNull(index);
    _retryWantsPlay = play;
    // Keep mpv from audibly moving on while this song is reconnecting.
    player.pause().ignore();
    debugPrint('Retrying playback ($attempt/${playbackRetryDelays.length})');
    _playbackRetryTimer = Timer(delay, () async {
      _playbackRetryTimer = null;
      if (_disposed || generation != _playbackRetryGeneration) return;
      // Something else was picked meanwhile: leave it.
      final seq = player.sequenceState.sequence;
      final targetIndex = seq.indexWhere((source) => identical(source, failedSource));
      if (targetIndex < 0) {
        _retryWantsPlay = false;
        notifyListeners();
        return;
      }
      // A fresh stream lookup: the old link may be what failed.
      if (track.videoId case final id?) {
        // Merged sound that failed isn't tried again: the retry plays the song's own stream.
        _smartMerge.giveUp(id);
        YoutubeAudioSource.forget(id);
        YoutubeStream.invalidateEverywhere(id);
      }
      // This try's own failure must be heard, not taken for a repeat of the last one.
      _lastError = null;
      final failed = _retryLoadFailed = Completer<bool>();
      notifyListeners();
      var loaded = false;
      try {
        // A seek can reuse the same failed source. Rebuild the sources so each
        // provider resolves a fresh URL, retaining the queue and position.
        loaded = await Future.any([
          player
              .setAudioSources(
                [for (final source in seq) _sourceFor(source.tag as Track)],
                initialIndex: targetIndex,
                initialPosition: position,
              )
              .then((_) => true),
          failed.future,
        ]).timeout(const Duration(seconds: 45), onTimeout: () => false);
      } catch (e) {
        debugPrint('Playback retry failed: ${e.runtimeType}');
      } finally {
        if (identical(_retryLoadFailed, failed)) _retryLoadFailed = null;
      }
      if (_disposed || generation != _playbackRetryGeneration) return;
      if (!loaded) {
        _recoverOrReport(track, targetIndex, play);
      } else if (play) {
        unawaited(
          _play().catchError((Object error) {
            if (!_disposed && generation == _playbackRetryGeneration) _recoverOrReport(track, targetIndex, play);
          }),
        );
      }
      notifyListeners();
    });
    notifyListeners();
    return true;
  }

  /// How much of a Monochrome song plays before it is downloaded: it is a download source, not a streaming one.
  static const previewLength = Duration(minutes: 1);

  @visibleForTesting
  void endPreviewAt(Duration position) => _endPreview(position);

  void _endPreview(Duration position) {
    if (casting || position < previewLength || currentTrack?.monochromeId == null) return;
    // Back to its start, paused: Play hears the preview again instead of stopping at once.
    unawaited(pause().then((_) => player.seek(Duration.zero)));
    _errors.add(tr.monochromePreviewEnded);
  }

  /// Keeps only the current and next song cached, and starts the next download.
  /// Untagged sources (for example an audio-engine probe) are not queue tracks.
  void _prefetchNext() {
    if (Host.isWeb) return; // the proxy looks songs up when the browser asks for them
    final seq = player.sequenceState;
    final at = seq.currentIndex;
    if (at == null) return;
    YoutubeAudioSource.retainCache({
      for (final s in seq.sequence.skip(at).take(2))
        if (s.tag case final Track t) ?t.videoId,
    });
    for (final s in seq.sequence.skip(at + 1).take(1)) {
      if (s.tag case final Track t when t.isRemote && downloadedCopy(t) == null) {
        if (_manualAudio.choice(t.videoId!) case final choice?) {
          if (choice.track?.path == null) _resolveAhead(t.videoId!);
          continue;
        }
        final local = _smartMerge.local(t, _views.library, (
          _views.library,
          libraryRevision.value,
        ), available: (file) => File(file.path!).existsSync());
        if (local != null) continue;
        if (_smartMerge.streams(t)) {
          // Look the next song up now; its YouTube stream is only fetched ahead when it will be the one played.
          _smartMerge.choose(t).then((choice) {
            if (choice == null && !_disposed && nextTrack?.id == t.id) _resolveAhead(t.videoId!);
          }).ignore();
        } else {
          _resolveAhead(t.videoId!);
        }
      }
    }
  }

  /// Looks a song's stream up in advance and fetches its first seconds, so it
  /// starts right away.
  void _resolveAhead(String videoId) => YoutubeAudioSource.preload(videoId, yt: youtube.client).ignore();

  /// Whether the play button has something to start: the queue, or the local library.
  bool get canPlay => player.audioSources.isNotEmpty || _library.isNotEmpty;

  bool get isPlaying => casting ? cast.playing : player.playing;

  /// What a play/pause button should show: [isPlaying] stays true at the end of the queue, where nothing is heard.
  bool get showsPlaying => casting
      ? cast.playing
      : _starting ||
            (_recovering && _retryWantsPlay) ||
            player.playing && player.processingState != ProcessingState.completed;
  bool get isBuffering => casting
      ? cast.loading
      : _starting ||
            _recovering ||
            player.processingState == ProcessingState.loading ||
            player.processingState == ProcessingState.buffering;

  /// Where the current song is, here or on the cast device.
  Duration get position => casting ? cast.position : player.position;

  Duration? get duration => casting ? cast.duration ?? player.duration : player.duration;

  static const seekSteps = [0, 2, 5, 10, 15, 30];
  static const _seekStepKey = 'playback.seekStepSeconds';
  int _seekStepSeconds = 5;
  int get seekStepSeconds => _seekStepSeconds;

  Future<void> setSeekStepSeconds(int seconds) async {
    if (!seekSteps.contains(seconds)) return;
    _seekStepSeconds = seconds;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setInt(_seekStepKey, seconds);
  }

  Future<void> seekByStep({required bool forward}) async {
    if (_seekStepSeconds == 0 || currentTrack == null) return;
    final target = position + Duration(seconds: forward ? _seekStepSeconds : -_seekStepSeconds);
    final end = duration;
    await seek(
      target.isNegative
          ? Duration.zero
          : end != null && target > end
          ? end
          : target,
    );
  }

  Future<void> seek(Duration to) async {
    _cancelPlaybackRetry();
    if (ListenTogether.of(this).requestSeek(to)) return;
    if (!casting && _soundcloudExpired) return _refreshSoundcloud(at: to);
    await (casting ? cast.seek(to) : player.seek(to));
  }

  /// Plays. At the end of the queue (nothing left to play) it starts the queue over, as [togglePlay] does:
  /// the media keys and the system's Play button call this, and would otherwise do nothing.
  Future<void> play() async {
    if (_closingPlayer != null) return;
    _sayIfOffline(currentTrack);
    _bluetoothResume = null;
    _bluetoothPause = null;
    if (!casting && player.audioSources.isNotEmpty && player.processingState == ProcessingState.completed) {
      await player.seek(Duration.zero, index: 0);
    }
    return _play();
  }

  /// Online or not, said as it changes: a streamed song stuck at 0:00 then has its reason on screen.
  bool _wasOnline = true;
  void _onlineChanged() {
    final on = Connection.instance.online.value;
    if (on == _wasOnline) return;
    _wasOnline = on;
    _errors.add(on ? tr.backOnline : tr.youreOffline);
    notifyListeners();
  }

  /// Play pressed on a song that needs the internet while there is none.
  void _sayIfOffline(Track? t) {
    if (t != null && !Connection.instance.online.value && !isOffline(t)) _errors.add(tr.youreOffline);
  }

  /// A streamed song still loading after a few seconds: the connection is looked at again (a Wi-Fi with no
  /// internet behind it says connected).
  Timer? _stall;
  void _watchStall(PlayerState state) {
    _stall?.cancel();
    final waiting =
        state.processingState == ProcessingState.loading || state.processingState == ProcessingState.buffering;
    final t = currentTrack;
    if (!waiting || !state.playing || t == null || isOffline(t)) return;
    _stall = Timer(const Duration(seconds: 6), () => Connection.instance.check().ignore());
  }

  Future<void> pause() {
    _bluetoothResume = null;
    _bluetoothPause = null;
    if (_starting || _recovering) _cancelledOpening = true;
    _cancelPlaybackRetry();
    return casting ? cast.pause() : player.pause();
  }

  ({String device, String track})? _bluetoothResume;
  ({String track, DateTime at})? _bluetoothPause;

  void _watchAudioRoutes(AudioSession session) {
    var outputs = <String>{};
    String? lastRemoved;
    DateTime? removedAt;
    var revision = 0;
    Future<void> refresh() async {
      final request = ++revision;
      try {
        final Set<String> next;
        if (Host.isAndroid) {
          final devices = await AndroidAudioManager().getDevices(AndroidGetAudioDevicesFlags.outputs);
          next = {
            for (final device in devices)
              if (device.type == AndroidAudioDeviceType.bluetoothA2dp &&
                  device.address != null &&
                  device.address!.isNotEmpty)
                device.address!,
          };
        } else {
          final devices = await session.getDevices(includeInputs: false);
          next = {
            for (final device in devices)
              if (device.isOutput &&
                  // ignore: experimental_member_use
                  (device.type == AudioDeviceType.bluetoothA2dp || device.type == AudioDeviceType.bluetoothLe))
                device.id,
          };
        }
        if (_disposed) return;
        if (request == revision) {
          final removed = outputs.difference(next);
          if (removed.length == 1 && outputs.length == 1) {
            lastRemoved = removed.single;
            removedAt = DateTime.now();
          }
          outputs = next;
        }
        final paused = _bluetoothPause;
        if (paused != null &&
            lastRemoved != null &&
            removedAt != null &&
            paused.at.difference(removedAt!).abs() < const Duration(seconds: 2) &&
            DateTime.now().difference(paused.at) < const Duration(seconds: 2)) {
          _bluetoothResume = (device: lastRemoved!, track: paused.track);
          _bluetoothPause = null;
        }
        final pending = _bluetoothResume;
        if (pending != null && outputs.length == 1 && outputs.contains(pending.device)) {
          _bluetoothResume = null;
          if (currentTrack?.id == pending.track && !player.playing && !casting && canPlay) {
            unawaited(play());
          }
        }
      } catch (error) {
        debugPrint('Bluetooth audio route unavailable: $error');
      }
    }

    final mobile = Host.isAndroid || Host.isIOS;
    if (mobile) {
      unawaited(refresh());
      _subs.add(session.devicesChangedEventStream.listen((_) => unawaited(refresh())));
    }
    _subs.add(
      session.becomingNoisyEventStream.listen((_) {
        final track = player.playing && !casting ? currentTrack?.id : null;
        unawaited(player.pause());
        if (mobile && track != null) {
          _bluetoothPause = (track: track, at: DateTime.now());
          unawaited(refresh());
        }
      }),
    );
  }

  /// 0-1: where the volume slider sits, for this device or the cast device.
  ///
  /// This device's gain is the cube of it, as with mpv's own volume (which the
  /// app's 64-bit filter stands in for off the system mixer): with linear gain
  /// halfway is only −6 dB, and all the audible change is crammed into the
  /// bottom of the slider. A cast device's volume is its own 0-100 scale,
  /// already shaped by the device.
  double get volume => casting ? (cast.volume ?? 0) / 100 : _level.value;

  /// This device's [volume]: the one level the slider shows, every song plays
  /// at and the next launch starts from. Only [setVolume] changes it, so
  /// just_audio's own volume (which its interruption handling doubles on
  /// Android once a notification has ducked it) can't drift from the slider.
  ValueListenable<double> get volumeLevel => _level;
  final _level = ValueNotifier<double>(1);

  static double levelOfGain(double gain) => gain <= 0 ? 0 : math.pow(gain.clamp(0, 1), 1 / 3).toDouble();
  static double gainOfLevel(double level) => math.pow(level.clamp(0, 1), 3).toDouble();

  bool get canSetVolume => !casting || (cast.target?.hasVolume ?? false);

  Future<void> setVolume(double v) {
    v = v.clamp(0, 1);
    if (casting) return cast.setVolume((v * 100).round());
    _level.value = v;
    _saveVolume?.cancel();
    _saveVolume = Timer(const Duration(milliseconds: 500), _storeVolume);
    return _playAt(v);
  }

  Future<void> _storeVolume() async {
    if (_outputKey case final key?) _outputVolumes[key] = _level.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_volumeKey, _level.value);
    if (_outputKey != null) await prefs.setString(_outputVolumesKey, jsonEncode(_outputVolumes));
  }

  /// The engine applies it to mpv (desktop and Android); elsewhere it is just_audio's.
  Future<void> _playAt(double level) =>
      AudioEngine.supported ? audio.setVolume(gainOfLevel(level)) : player.setVolume(gainOfLevel(level));

  static const _volumeKey = 'volume.v1';

  /// The volume last used on each output ([AudioEngine.outputKey]): turned down for an IEM on a bit-perfect DAC
  /// (which Android holds at full volume), it isn't left that low for the phone's speaker once the DAC is pulled
  /// out, and comes back with the DAC.
  static const _outputVolumesKey = 'volume.byOutput.v1';
  final _outputVolumes = <String, double>{};
  String? _outputKey;

  /// The output changed: the level kept for it (if it has one) replaces the one used on the previous output.
  void _followOutput() {
    if (!AudioEngine.supported || casting) return;
    final key = audio.outputKey;
    final previous = _outputKey;
    if (key == previous) return;
    _outputKey = key;
    if (previous == null) {
      // The first output seen: it starts from the saved level.
      _outputVolumes.putIfAbsent(key, () => _level.value);
      return;
    }
    _outputVolumes[previous] = _level.value;
    final kept = _outputVolumes[key];
    _outputVolumes.putIfAbsent(key, () => _level.value);
    if (kept != null && kept != _level.value) setVolume(kept).ignore();
    _storeOutputVolumes().ignore();
  }

  Future<void> _storeOutputVolumes() async =>
      (await SharedPreferences.getInstance()).setString(_outputVolumesKey, jsonEncode(_outputVolumes));
  Timer? _saveVolume;

  /// The level Unmute goes back to.
  double? _unmuteTo;

  /// Remembers the level a slider drag starts from, for Unmute after dragging to 0.
  void volumeDragStarted() {
    if (volume > 0) _unmuteTo = volume;
  }

  Future<void> toggleMute() {
    if (volume > 0) {
      _unmuteTo = volume;
      return setVolume(0);
    }
    return setVolume(_unmuteTo ?? 1);
  }

  /// Ctrl+↑ / Ctrl+↓ and the mouse wheel over the volume slider.
  Future<void> nudgeVolume(double by) async {
    if (canSetVolume && audio.dopPlaying == null) await setVolume(((volume + by) * 20).round() / 20);
  }

  /// [position] often enough that a seek bar glides instead of ticking (here
  /// or on the cast device). That's a step of half a pixel on the widest bar,
  /// not every frame: a 4-minute song moves a 1200 px bar 5 px a second, so
  /// updating at 60 fps redrew the window for nothing the eye could see.
  Stream<Duration> smoothPosition() => _positionStream(smooth: true);

  /// [position] a few times a second, for views that rebuild a lot per tick.
  Stream<Duration> positionUpdates() => _positionStream(smooth: false);

  /// The lyric highlight's position budget is independent of the seek bar and window focus.
  Stream<Duration> lyricsPosition() => _beatTicks(() => const Duration(milliseconds: 50));

  static bool get _drawn => switch (WidgetsBinding.instance.lifecycleState) {
    AppLifecycleState.hidden || AppLifecycleState.paused || AppLifecycleState.detached => false,
    _ => true,
  };

  Stream<Duration> _positionStream({required bool smooth}) {
    StreamSubscription<Duration>? sub;
    bool? wasCasting;
    PerformanceMode? wasMode;
    late final StreamController<Duration> out;
    void attach() {
      final mode = LayoutPrefs.instance.performance;
      if (wasCasting == casting && wasMode == mode) return;
      wasCasting = casting;
      wasMode = mode;
      sub?.cancel();
      sub =
          (casting
                  ? cast.positionTicks(every: Duration(milliseconds: smooth ? 50 : 200))
                  : smooth
                  ? _smoothTicks(lightweight: mode == PerformanceMode.lightweight)
                  : _beatTicks(() => const Duration(milliseconds: 200)))
              // Nothing is drawn while the window is minimized or hidden: a tick there would only wake the
              // UI and raster threads. The next tick after it is shown again puts the views right.
              .listen((p) {
                if (_drawn) out.add(p);
              });
    }

    out = StreamController<Duration>(
      onListen: () {
        attach();
        cast.addListener(attach);
        // A new Performance mode takes effect on a bar that is already showing.
        LayoutPrefs.instance.addListener(attach);
      },
      onCancel: () {
        cast.removeListener(attach);
        LayoutPrefs.instance.removeListener(attach);
        return sub?.cancel();
      },
    );
    return out.stream;
  }

  /// [position] on the shared [UiBeat], so a seek bar, the karaoke fill and the visualizer
  /// that move in the same beat are drawn in one frame instead of one each. A tick every
  /// 1/2400 of the song (half a pixel of a 1200 px bar), 60 to 4 times a second. Lightweight
  /// ticks once a second, with the elapsed time beside the bar: there a playing song draws
  /// nothing else, and on Linux each frame costs the main thread several milliseconds.
  Stream<Duration> _smoothTicks({required bool lightweight}) => _beatTicks(() {
    final step = (duration ?? Duration.zero) ~/ 2400;
    // Lightweight, or another window has the focus: once a second, with the time beside the bar.
    final unfocused =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.inactive && !DebugSwitches.moveUnfocused;
    // The music video on screen shows the song moving; each frame drawn over its surface costs the Linux main thread
    // ~20 ms, so the bar steps once a second then too (VideoMode.showing).
    final video = VideoMode.instance.showing && !DebugSwitches.motionWithVideo;
    final slow = (lightweight && !DebugSwitches.quickLightweightSeekBar) || unfocused || video;
    // Balanced on a computer: on the beat everything else there moves at.
    final min = slow
        ? const Duration(seconds: 1)
        : (LayoutPrefs.frugal ? LayoutPrefs.frugalEvery : const Duration(milliseconds: 16));
    final max = slow ? const Duration(seconds: 1) : const Duration(milliseconds: 250);
    return step < min ? min : (step > max ? max : step);
  });

  /// [position] about once a second while a song plays, for what only needs to know how far it has got (scrobbling,
  /// play history, YouTube Music's play reports, Listen together). One beat for all of them, also while the window
  /// is hidden. just_audio's own position streams were 5 Hz timers that never stopped once made.
  Stream<Duration> secondTicks() => _beatTicks(() => const Duration(seconds: 1), whileHidden: true);

  /// [position] every [every] on the shared [UiBeat] while a song plays (and the window is shown, unless
  /// [whileHidden]). Off the beat otherwise: a listener left on it kept its timer waking the app. A seek made
  /// elsewhere (media keys, MPRIS) still comes through, as a position discontinuity, and so does a change of song or
  /// state (the controller's listeners).
  Stream<Duration> _beatTicks(Duration Function() every, {bool whileHidden = false}) {
    UiBeatListener? beat;
    StreamSubscription<PositionDiscontinuity>? seeks;
    StreamSubscription<bool>? playing;
    AppLifecycleListener? shown;
    late final StreamController<Duration> out;

    Duration? last;
    void tick() {
      final p = position;
      // Nothing moved (a seek bar at the end, a stall): nothing is drawn.
      if (p != last) out.add(last = p);
    }

    void sync() {
      // What is drawn follows what the screen shows as playing; the rest, the player itself.
      final moving = whileHidden ? player.playing : showsPlaying || DebugSwitches.beatWhilePaused;
      final run = moving && (whileHidden || _drawn);
      if (run) {
        beat ??= UiBeat.listen(every(), (_) {
          beat!.period = every();
          tick();
        });
      } else {
        beat?.cancel();
        beat = null;
        tick();
      }
    }

    out = StreamController<Duration>(
      onListen: () {
        out.add(last = position);
        sync();
        addListener(sync);
        seeks = player.positionDiscontinuityStream.listen((_) => tick());
        if (whileHidden) playing = player.playingStream.listen((_) => sync());
        // Minimized or hidden, nothing is drawn: the beat stops until the window is back.
        if (!whileHidden) shown = AppLifecycleListener(onStateChange: (_) => sync());
      },
      onCancel: () {
        removeListener(sync);
        beat?.cancel();
        beat = null;
        shown?.dispose();
        playing?.cancel();
        return seeks?.cancel();
      },
    );
    return out.stream;
  }

  bool get shuffle => _shuffled;
  LoopMode get loopMode => player.loopMode;

  /// Every platform reads a picked folder in place (iOS through a bookmark kept by `FolderAccess.swift`).
  bool get canScanFolders => true;

  // Derived library views are worked out once per library change, not on every rebuild: Home, the
  // sidebar and every song row ask for them, and sorting or scanning the whole
  // library each time stalled every song change for tens of milliseconds.

  /// Bumped on in-place library edits; replacing [_library] invalidates by identity.
  int _libraryEdits = 0;
  LibraryViews? _cachedViews;

  /// Songs replaced in place since [_cachedViews] was made (their versions then, and now). Tag-only changes
  /// like these are folded into the views instead of rebuilding them.
  final Map<String, Track> _editedOld = {};
  final Map<String, Track> _editedNow = {};

  /// Puts [t] in place of the library's song at [i] (same list, same order).
  void _replaceAt(int i, Track t) {
    final was = _library[i];
    _editedOld.putIfAbsent(was.id, () => was);
    _editedNow[was.id] = t;
    _library[i] = t;
    _libraryEdits++;
  }

  LibraryViews get _views {
    final v = _cachedViews;
    if (v != null && identical(v.tracks, _library)) {
      if (v.edits == _libraryEdits) return v;
      if (_editedNow.isNotEmpty) {
        final next = v.patched(_libraryEdits, Map.of(_editedNow), Map.of(_editedOld));
        _editedOld.clear();
        _editedNow.clear();
        return _cachedViews = next;
      }
    }
    _editedOld.clear();
    _editedNow.clear();
    return _cachedViews = LibraryViews(_library, _libraryEdits);
  }

  List<Track> get recentlyAdded => _views.recentlyAdded;

  /// Streamed songs played recently (they aren't in the library, so they're remembered here).
  Map<String, Track> _recentRemote = {};

  /// Identity token for views that rebuild when the order or membership of recents changes.
  Object get recentlyPlayedRevision => _recentIds;

  /// Library and YouTube Music songs together, most recent first.
  bool _unavailableExtensionRecent(Track track) {
    final extensionDownload = Uri.tryParse(track.sourceUrl ?? '')?.scheme == 'spotiflac';
    if (track.extensionId == null && !extensionDownload) return false;
    final local = track.extensionId == null ? track : downloadedCopy(track);
    final path = local?.path;
    return path == null || !File(path).existsSync();
  }

  List<Track> get recentlyPlayed {
    final tracks = <Track>[];
    for (final id in _recentIds) {
      final track = _recentRemote[id] ?? _views.byId[id];
      if (track == null || _unavailableExtensionRecent(track)) continue;
      final playable = track.extensionId == null ? track : downloadedCopy(track)!;
      final duplicate = tracks.indexWhere((other) => SmartMerge.same(other, playable));
      if (duplicate < 0) {
        tracks.add(playable);
      } else if (playable.videoId != null && tracks[duplicate].videoId == null) {
        // One recording played from YouTube Music and Monochrome is one recent
        // song; keep YouTube's identity, lyrics and artwork for its card.
        tracks[duplicate] = playable;
      }
    }
    return tracks;
  }

  String? _dismissedRecentPlaying;

  /// Removes an entry from the recent shelf, including its persisted streamed metadata.
  Future<void> removeFromRecentlyPlayed(Track track) async {
    if (!_recentIds.contains(track.id)) return;
    _recentIds = _recentIds.where((id) => id != track.id).toList();
    _recentRemote.remove(track.id);
    if (currentTrack?.id == track.id) _dismissedRecentPlaying = track.id;
    _recentsTimer?.cancel();
    _recentsTimer = null;
    notifyListeners();
    await _storeRecents();
  }

  Collection get allSongs => _views.allSongs;

  /// Everything imported from YouTube, newest first.
  Collection? get youtubeDownloads => _views.youtubeDownloads;

  /// The music folders the person added, each with the songs under it (Library › Local).
  List<Collection> get folders => _views.foldersOf(FolderWatch.instance.folders);

  /// The folder collection of [path], while that folder is still one of the music folders.
  Collection? folderAt(String? path) => folders.where((f) => f.id == path).firstOrNull;

  /// The music folders made playlists (Playlists): each is the folder's songs right now, never a copy.
  List<Collection> get folderPlaylists => LibraryViews.folderPlaylistsOf(folders, FolderWatch.instance.playlistFolders);

  List<UserPlaylist> _playlists = [];
  List<UserPlaylist> get playlists => List.unmodifiable(_playlists);

  Collection playlistCollection(UserPlaylist p) => Collection(
    kind: CollectionKind.playlist,
    id: p.id,
    title: p.name,
    subtitle: tr.songsPlural(p.tracks.length),
    tracks: p.tracks,
    coverKey: PlaylistCovers.playlistKey(p.id),
  );

  Collection? playlistById(String? id) => _playlists.where((p) => p.id == id).map(playlistCollection).firstOrNull;

  /// Playlists keep their own copy of each song: one that holds a download no longer in the library (downloaded
  /// again since, or left out as a repeat) gets the library's download of the same video. True when any changed.
  bool _repointDownloads() {
    final ids = {for (final t in _library) t.id};
    final latest = <String, Track>{};
    for (final t in _library) {
      final v = youtubeVideoIdOf(t.sourceUrl);
      if (v != null) latest[v] = t;
    }
    var changed = false;
    _playlists = [
      for (final p in _playlists)
        p.copyWith(
          tracks: [
            for (final t in p.tracks)
              switch (youtubeVideoIdOf(t.sourceUrl)) {
                final v? when !ids.contains(t.id) && latest[v] != null && t.path != null => () {
                  changed = true;
                  return latest[v]!;
                }(),
                _ => t,
              },
          ],
        ),
    ];
    return changed;
  }

  Future<void> _savePlaylists() async => (await SharedPreferences.getInstance()).setString(
    _playlistsKey,
    jsonEncode([for (final p in _playlists) p.toJson()]),
  );

  void _updatePlaylist(String id, UserPlaylist Function(UserPlaylist p) change) {
    _playlists = [for (final p in _playlists) p.id == id ? change(p) : p];
    notifyListeners();
    unawaited(_savePlaylists());
  }

  UserPlaylist createPlaylist(String name, {List<Track> tracks = const []}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final p = UserPlaylist(id: 'pl$now', name: name, tracks: _unique(tracks), createdAt: now);
    _playlists = [p, ..._playlists];
    notifyListeners();
    unawaited(_savePlaylists());
    return p;
  }

  void renamePlaylist(String id, String name) => _updatePlaylist(id, (p) => p.copyWith(name: name));

  void deletePlaylist(String id) {
    _playlists = _playlists.where((p) => p.id != id).toList();
    notifyListeners();
    unawaited(_savePlaylists());
  }

  /// Adds songs to the end, skipping ones already in it. Returns how many were added.
  int addToPlaylist(String id, List<Track> tracks) {
    var added = 0;
    _updatePlaylist(id, (p) {
      final next = _unique([...p.tracks, ...tracks]);
      added = next.length - p.tracks.length;
      return p.copyWith(tracks: next);
    });
    return added;
  }

  /// Removes the selected songs with one library update and records their positions for Undo.
  List<({int index, Track track})> removePlaylistTracks(String id, List<Track> tracks) {
    final playlist = playlistById(id);
    if (playlist == null) return const [];
    final ids = tracks.map((track) => track.id).toSet();
    final removed = [
      for (final (index, track) in playlist.tracks.indexed)
        if (ids.contains(track.id)) (index: index, track: track),
    ];
    if (removed.isEmpty) return removed;
    _updatePlaylist(id, (p) => p.copyWith(tracks: p.tracks.where((t) => !ids.contains(t.id)).toList()));
    return removed;
  }

  /// Restores removed songs in their previous positions, leaving any intervening edits in place.
  void restorePlaylistTracks(String id, List<({int index, Track track})> removed) => _updatePlaylist(id, (p) {
    final tracks = [...p.tracks];
    final ids = tracks.map((track) => track.id).toSet();
    for (final row in removed) {
      if (ids.add(row.track.id)) tracks.insert(row.index.clamp(0, tracks.length), row.track);
    }
    return p.copyWith(tracks: tracks);
  });

  void removeFromPlaylist(String id, Track track) => removePlaylistTracks(id, [track]);

  void movePlaylistItem(String id, int from, int to) => _updatePlaylist(id, (p) {
    final list = [...p.tracks];
    final t = list.removeAt(from);
    list.insert(to.clamp(0, list.length), t);
    return p.copyWith(tracks: list);
  });

  /// Moves one song of a Riflay playlist by dragging. [newIndex] is where it ends up in the finished list
  /// (what a reorderable list's `onReorderItem` reports).
  void movePlaylistTrack(String id, int oldIndex, int newIndex) {
    final p = _playlists.where((p) => p.id == id).firstOrNull;
    if (p == null || oldIndex < 0 || oldIndex >= p.tracks.length) return;
    final to = newIndex.clamp(0, p.tracks.length - 1);
    if (to != oldIndex) movePlaylistItem(id, oldIndex, to);
  }

  static List<Track> _unique(List<Track> tracks) {
    final seen = <String>{};
    return [
      for (final t in tracks)
        if (seen.add(t.id)) t,
    ];
  }

  /// A YouTube song that was also downloaded plays from the file: no network, no buffering.
  Track? downloadedCopy(Track t) {
    final id = t.offlineId;
    return id == null ? null : _views.downloads[id];
  }

  /// Whether [t] can play without internet.
  bool isOffline(Track t) => !t.streams || downloadedCopy(t) != null;

  List<Collection> get albums => _views.albums;

  List<Collection> get artists => _views.artists;

  /// Albums and artists together, by name (the library list's "everything").
  List<Collection> get albumsAndArtists => _views.albumsAndArtists;

  Collection? artistNamed(String name) =>
      _views.artistByName[name] ?? _views.artistByName[Track.splitArtists(name).firstOrNull];

  Collection? albumOf(Track track) => _views.albumOfTrack[track.id];

  List<Track> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final v = _views;
    return [
      for (var i = 0; i < v.tracks.length; i++)
        if (v.searchKeys[i].contains(q)) v.tracks[i],
    ];
  }

  final _searches = <String, Future<List<Track>>>{};

  /// Songs on YouTube matching [query]; they stream when played. No sign-in needed.
  /// Recent queries are answered from memory, and the top hit's stream is
  /// looked up ahead of time so it starts the moment it's clicked.
  Future<List<Track>> searchYoutube(String query) {
    final key = query.trim().toLowerCase();
    final cached = _searches.remove(key);
    if (cached != null) return _searches[key] = cached; // most recent last
    final future = _searchYoutube(query);
    _searches[key] = future;
    if (_searches.length > 40) _searches.remove(_searches.keys.first);
    future.then<void>(
      (tracks) {
        final top = tracks.firstOrNull?.videoId;
        if (top != null) _resolveAhead(top);
      },
      onError: (Object _) {
        _searches.remove(key);
      },
    );
    return future;
  }

  /// SoundCloud's client (search, links, streams). Tests put one of their own here.
  SoundcloudClient get soundcloud => _soundcloud;
  set soundcloud(SoundcloudClient client) {
    _soundcloud = client;
    _soundcloudServed?.cancel();
    _soundcloudServed = client.served.listen((id) {
      if (id == currentTrack?.soundcloudId) _followSoundcloudExpiry();
    });
  }

  late SoundcloudClient _soundcloud;
  Monochrome monochrome = Monochrome.instance;
  StreamSubscription<String>? _soundcloudServed;
  Timer? _soundcloudRefresh;

  /// How long before its segments run out a playing SoundCloud track is loaded again: mpv reads ahead.
  static const _soundcloudMargin = Duration(minutes: 10);

  /// SoundCloud signs a track's segments for about two hours; mpv would stop at the first one it can no longer
  /// fetch (a long mix, a song paused for hours). Before that, one timer (nothing runs meanwhile) loads the
  /// track again where it is, with a fresh playlist.
  void _followSoundcloudExpiry() {
    _soundcloudRefresh?.cancel();
    _soundcloudRefresh = null;
    final id = currentTrack?.soundcloudId;
    final at = id == null ? null : soundcloud.expiresAt(id);
    if (at == null) return;
    final due = at.subtract(_soundcloudMargin).difference(DateTime.now());
    _soundcloudRefresh = Timer(due.isNegative ? Duration.zero : due, () {
      if (currentTrack?.soundcloudId == id) _refreshSoundcloud().ignore();
    });
  }

  /// Whether the playing SoundCloud track's segments ran out (or nearly): timers don't run while a phone sleeps.
  bool get _soundcloudExpired {
    final id = currentTrack?.soundcloudId;
    final at = id == null ? null : soundcloud.expiresAt(id);
    return at != null && DateTime.now().isAfter(at.subtract(const Duration(minutes: 1)));
  }

  /// Loads the current SoundCloud track again at [at] (where it is), as it was playing or paused.
  Future<void> _refreshSoundcloud({Duration? at}) async {
    final id = currentTrack?.soundcloudId;
    final index = player.currentIndex;
    if (id == null || index == null || casting) return;
    final position = at ?? player.position;
    final wasPlaying = player.playing;
    soundcloud.forget(id);
    debugPrint('SoundCloud: a fresh playlist for $id at $position');
    await _load([for (final s in player.sequenceState.sequence) s.tag as Track], index, position: position);
    if (wasPlaying) unawaited(player.play());
  }

  final _soundcloudSearches = <String, Future<List<Track>>>{};

  /// SoundCloud tracks matching [query] that play in full; recent queries are answered from memory
  /// (`RIFLAY_NO_SOUNDCLOUD_CACHE` asks every time).
  Future<List<Track>> searchSoundcloud(String query) {
    const cache = !bool.fromEnvironment('RIFLAY_NO_SOUNDCLOUD_CACHE');
    final key = query.trim().toLowerCase();
    if (!cache) return soundcloud.search(query);
    final cached = _soundcloudSearches.remove(key);
    if (cached != null) return _soundcloudSearches[key] = cached;
    final future = soundcloud.search(query);
    _soundcloudSearches[key] = future;
    if (_soundcloudSearches.length > 20) _soundcloudSearches.remove(_soundcloudSearches.keys.first);
    future.catchError((Object _) {
      _soundcloudSearches.remove(key);
      return const <Track>[];
    });
    return future;
  }

  /// Whether [t] is in the library (a SoundCloud track saved there, a file).
  bool inLibrary(Track t) => _views.byId.containsKey(t.id);

  /// Saves streamed SoundCloud tracks into the library, where they stay listed with the songs on this device.
  /// Returns how many were new.
  Future<int> saveToLibrary(Iterable<Track> tracks) => _addTracks([
    for (final t in tracks)
      if (t.soundcloudId != null || t.monochromeId != null || t.extensionId != null || t.spotifyId != null) t,
  ]);

  /// YouTube Music's own song search first; plain YouTube search if that fails.
  Future<List<Track>> _searchYoutube(String query) async {
    try {
      final songs = await ytMusic.searchSongs(query);
      if (songs.isNotEmpty) return songs;
    } catch (e) {
      debugPrint('YouTube Music search failed, using YouTube: $e');
    }
    final results = await youtube.client.search.search('$query song');
    return [
      // A live stream has no end and no audio-only stream: it can't play as a song.
      for (final v in results.where((v) => !v.isLive).take(20))
        () {
          final names = YoutubeImporter.parseTitle(v.title, v.author);
          return Track.youtube(
            videoId: v.id.value,
            title: names.title,
            artist: names.artist,
            duration: v.duration,
            artworkUrl: v.thumbnails.highResUrl,
          );
        }(),
    ];
  }

  Future<void> load() async {
    await MusicSources.instance.load();
    final prefs = await SharedPreferences.getInstance();
    _manualAudio.load(prefs);
    // Side by side: the library (its own file, read in the background), the
    // YouTube Music session and the audio settings.
    final library = LibraryStore.load(prefs);
    // iOS: picked folders have to be reopened before any of their songs can be read.
    final folders = Host.isIOS ? IosFolders.restore() : Future.value(const <String, String>{});
    await Future.wait([library, folders, ytMusic.load(), audio.load(), PlaylistCovers.instance.load()]);
    // A downloads folder picked in Files is one of them.
    if (Host.isIOS) await DownloadPrefs.instance.repointFolder(await folders);
    _followTempo(); // a tempo or pitch kept from last time
    // iOS moves the app's folder on updates; elsewhere downloads stay put.
    _library = Host.isIOS
        ? await Future.wait(IosFolders.repoint(await library, await folders).map(YoutubeImporter.relocate))
        : await library;
    // Libraries from before 1.1.4 may hold a song downloaded twice, one entry for a file that is gone.
    if (!Host.isWeb) {
      final cleaned = LibraryViews.withoutRepeatedDownloads(_library, (t) => File(t.path!).existsSync());
      if (cleaned.length != _library.length) {
        debugPrint('Library: ${_library.length - cleaned.length} repeated downloads left out');
        _library = cleaned;
        unawaited(_save());
      }
    }
    _recentIds = prefs.getStringList(_recentKey) ?? [];
    recentRadios.value = recentRadiosFrom(prefs.getString(_recentRadiosKey));
    final savedPlaylists = prefs.getString(_playlistsKey);
    try {
      // A playlist that can't be read is left out, not all of them; the saved text is kept aside first, since
      // the next save writes over it.
      final kept = <UserPlaylist>[];
      final all = jsonDecode(savedPlaylists ?? '[]') as List;
      for (final j in all) {
        try {
          kept.add(UserPlaylist.fromJson((j as Map).cast()));
        } catch (e) {
          debugPrint('Leaving out an unreadable playlist: $e');
        }
      }
      if (kept.length != all.length) await prefs.setString('$_playlistsKey.unreadable', savedPlaylists!);
      _playlists = kept;
      if (Host.isIOS) {
        final moved = await folders;
        _playlists = [for (final p in _playlists) p.copyWith(tracks: IosFolders.repoint(p.tracks, moved))];
      }
      if (_repointDownloads()) unawaited(_savePlaylists());
      _recentRemote = {
        for (final j in jsonDecode(prefs.getString(_recentRemoteKey) ?? '[]') as List)
          if (Track.fromJson((j as Map).cast()) case final t) t.id: t,
      };
    } catch (e) {
      debugPrint('Ignoring unreadable playlists: $e');
      if (_playlists.isEmpty && savedPlaylists != null) {
        await prefs.setString('$_playlistsKey.unreadable', savedPlaylists);
      }
    }
    final blockedRecents = {
      for (final id in _recentIds)
        if ((_recentRemote[id] ?? _views.byId[id]) case final track?)
          if (_unavailableExtensionRecent(track)) id,
    };
    if (blockedRecents.isNotEmpty) {
      _recentIds.removeWhere(blockedRecents.contains);
      _recentRemote.removeWhere((id, _) => blockedRecents.contains(id));
      await _storeRecents();
    }
    // Warm the shared catalogue connection and first audio bytes before the
    // first click, using only the two most recently played YouTube songs.
    if (!Host.isWeb) {
      for (final track in recentlyPlayed.where((track) => track.isRemote).take(2)) {
        _smartMerge.prefetch(track);
      }
    }
    discord.enabled = prefs.getBool(_discordKey) ?? true;
    try {
      final saved = prefs.getString(_discordOptionsKey);
      if (saved != null) discord.options = DiscordOptions.fromJson((jsonDecode(saved) as Map).cast());
    } catch (e) {
      debugPrint('Discord options unreadable: $e');
    }
    _updatePresence(force: true);
    _autoplay = prefs.getBool(_autoplayKey) ?? true;
    final seekStep = prefs.getInt(_seekStepKey);
    _seekStepSeconds = seekSteps.contains(seekStep) ? seekStep! : 5;
    final loop = LoopMode.values.asNameMap()[prefs.getString(_loopKey)];
    final level = prefs.getDouble(_volumeKey);
    if (level != null) _level.value = level.clamp(0, 1);
    try {
      final kept = jsonDecode(prefs.getString(_outputVolumesKey) ?? '{}') as Map<String, dynamic>;
      for (final e in kept.entries) {
        if (e.value is num) _outputVolumes[e.key] = (e.value as num).toDouble().clamp(0, 1);
      }
    } catch (_) {
      // Unreadable: each output starts from the saved level.
    }
    Ffmpeg.onDownload = _errors.add;
    // A browser has no files, tag tools or music folders (see lib/platform/host.dart).
    if (!Host.isWeb) unawaited(Metadata.probeTagTools().then((_) => notifyListeners()));
    unawaited(LyricsTranslation.load());
    unawaited(MediaSession.loadLyricsSetting());
    unawaited(LockScreenLyrics.attach(this));
    Connection.instance.online.addListener(_onlineChanged);
    Connection.instance.start();
    unawaited(AudioAnalysis.load());
    unawaited(LyricsService.loadBetterLyricsKey());
    audio.addListener(notifyListeners);
    audio.addListener(_followOutput);
    // The output at start keeps the saved level, so moving to another one later has something to come back to.
    _followOutput();
    _dopWasActive = audio.dopActive;
    audio.addListener(_onAudioSettings);
    audio.addListener(_followTempo);
    final session = ListenTogether.of(this);
    session.addListener(() => audio.holdTempoPitch(session.role != ListenRole.none));
    notifyListeners();
    // The player's own loop mode and volume are not needed before the first frame; they follow it.
    await _restoreQueue(prefs);
    sleep.loadSchedules(prefs, (id) async {
      final playlist = _playlists.where((playlist) => playlist.id == id).firstOrNull;
      if (playlist != null && playlist.tracks.isNotEmpty && ListenTogether.of(this).role != ListenRole.guest) {
        await playCollection(playlistCollection(playlist));
      }
    });
    unawaited(_applyPlayerSettings(loop, level));
    if (Host.isWeb) return;
    unawaited(_enrichUntagged());
    unawaited(FolderWatch.start(this)); // keeps the music folders up to date (folder_watch.dart)
  }

  Future<void> _applyPlayerSettings(LoopMode? loop, double? level) async {
    try {
      if (loop != null && loop != LoopMode.off) await player.setLoopMode(loop);
      if (level != null) await _playAt(_level.value);
    } catch (e) {
      debugPrint('Restoring loop mode / volume failed: $e');
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _save() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    _savePending = false;
    return LibraryStore.save(await SharedPreferences.getInstance(), _library);
  }

  Timer? _saveTimer;
  bool _savePending = false;

  /// How long small library changes (a corrected length) wait, so a run of them is one save.
  static const saveDelay = Duration(seconds: 2);

  /// [_save] after [saveDelay]; more changes meanwhile ride along.
  void _saveSoon() {
    _savePending = true;
    _saveTimer ??= Timer(saveDelay, () {
      _saveTimer = null;
      if (_savePending && !_disposed) _save().ignore();
    });
  }

  @visibleForTesting
  void saveSoon() => _saveSoon();

  /// Writes any save that is still waiting (app exit, before a shutdown).
  Future<void> flushSaves() async {
    if (_recentsTimer != null) {
      _recentsTimer!.cancel();
      _recentsTimer = null;
      await _storeRecents();
    }
    if (_savePending) await _save();
  }

  /// Library saves skipped for waiting ones, for tests.
  bool get savePending => _savePending;

  /// Only counts tracks that actually start playing, not ones the queue passes through while loading.
  void _recordRecent() {
    final current = currentTrack;
    if (current != null && _unavailableExtensionRecent(current)) return;
    final id = current?.id;
    if (id != _dismissedRecentPlaying) _dismissedRecentPlaying = null;
    // Pause, buffer and progress notifications for this same playback must not undo a manual dismissal.
    if (id != null && id == _dismissedRecentPlaying) return;
    if (id == null || !isPlaying || (_recentIds.isNotEmpty && _recentIds.first == id)) return;
    _recentIds = [id, ..._recentIds.where((r) => r != id)].take(_maxRecent).toList();
    if (current != null && current.streams) {
      _recentRemote = {
        for (final e in _recentRemote.entries)
          if (_recentIds.contains(e.key)) e.key: e.value,
        current.id: current,
      };
    }
    _storeRecentsSoon();
  }

  Timer? _recentsTimer;

  /// Coalesces recents writes: skipping through songs writes once.
  void _storeRecentsSoon() {
    _recentsTimer ??= Timer(const Duration(seconds: 1), () {
      _recentsTimer = null;
      _storeRecents().ignore();
    });
  }

  Future<void> _storeRecents() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_recentKey, _recentIds);
    await p.setString(_recentRemoteKey, jsonEncode([for (final t in _recentRemote.values) t.toJson()]));
  }

  /// Tag-based durations are estimates (e.g. CBR MP3s without a Xing header);
  /// the decoder's value is authoritative, so persist it once known. Not a
  /// zero: mpv reports one while a file opens, and the song's length was
  /// saved as 0:00 (a song saved so is put right the next time it plays).
  void _correctDuration(Duration? actual) {
    final track = currentTrack;
    if (actual == null || actual <= Duration.zero || track == null) return;
    final known = track.duration;
    if (track.isRemote && known == null) _joinScannedLocal().ignore();
    if (known != null && (known - actual).abs() < const Duration(seconds: 1)) return;
    final i = _library.indexWhere((t) => t.id == track.id);
    if (i < 0) return;
    _replaceAt(i, _library[i].copyWith(duration: actual));
    notifyListeners();
    _saveSoon();
  }

  Future<int> pickFiles() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [...Track.audioExtensions, 'cue', 'iso'],
      dialogTitle: tr.addMusic,
    );
    final cues = files.where((f) => f.name.toLowerCase().endsWith('.cue') && f.path != null);
    final split = await _readCues([for (final f in cues) File(f.path!)]);
    final isos = [
      for (final f in files)
        if (f.name.toLowerCase().endsWith('.iso') && f.path != null) f.path!,
    ];
    return _addTracks([
      ...split.tracks,
      ...await _readSacds(isos),
      for (final f in files)
        if (!f.name.toLowerCase().endsWith('.cue') &&
            !f.name.toLowerCase().endsWith('.iso') &&
            !split.covers.contains(f.path))
          Track.fromUri(f.uri, displayName: f.name),
    ]);
  }

  /// Songs from cue sheets; a sheet that can't be read is skipped (its audio file then shows as one track).
  Future<({List<Track> tracks, Set<String> covers})> _readCues(List<File> cues) async {
    final tracks = <Track>[];
    final covers = <String>{};
    for (final cue in cues) {
      try {
        final r = CueSheet.read(cue);
        tracks.addAll(r.tracks);
        covers.addAll(r.covers);
      } catch (e) {
        debugPrint('Skipping cue sheet ${cue.path}: $e');
      }
    }
    return (tracks: tracks, covers: covers);
  }

  /// Songs on SACD images; other ISOs (DVDs, data discs) are skipped.
  static Future<List<Track>> _readSacds(List<String> paths) async {
    if (paths.isEmpty) return const [];
    return inBackground(() => [for (final p in paths) ...?SacdDisc.read(p)?.tracks()]);
  }

  Future<int> pickFolder() async {
    final dir = await chooseFolder();
    if (dir == null) return 0;
    return scanFolder(dir);
  }

  /// Asks for a music folder (and, on Android, the permission to read music); null when none was picked.
  Future<String?> chooseFolder() async {
    // Android: the songs are read where they are, which takes the permission to read music.
    if (Host.isAndroid && await _musicPermission.invokeMethod<bool>('request') != true) {
      throw const MusicPermissionDenied();
    }
    return Host.isIOS ? IosFolders.pick() : FilePicker.getDirectoryPath(dialogTitle: tr.addMusicFolder);
  }

  static const _musicPermission = MethodChannel('riflay/music_permission');

  final _addingFolders = <String>{};

  /// Adds every song, cue sheet and SACD image under [dir], rejecting registered folders. [asPlaylist] also
  /// makes the folder a playlist that follows it (Playlists).
  Future<int> scanFolder(String dir, {bool asPlaylist = false}) async {
    dir = await canonicalFolderPath(dir);
    if (!_addingFolders.add(dir)) throw const MusicFolderAlreadyAdded();
    try {
      if (await FolderWatch.instance.containsFolder(dir)) throw const MusicFolderAlreadyAdded();
      final entries = Directory(dir).list(recursive: true, followLinks: false);
      final tracks = <Track>[];
      final cues = <File>[];
      final isos = <String>[];
      await for (final e in entries) {
        if (e is! File) continue;
        if (Track.isAudioPath(e.path)) tracks.add(Track.fromUri(Uri.file(e.path)));
        if (e.path.toLowerCase().endsWith('.cue')) cues.add(e);
        if (e.path.toLowerCase().endsWith('.iso')) isos.add(e.path);
      }
      final split = await _readCues(cues);
      tracks.removeWhere((t) => split.covers.contains(t.path));
      tracks.sort((a, b) => a.id.compareTo(b.id));
      await FolderWatch.instance.remember(dir);
      if (asPlaylist) await FolderWatch.instance.setPlaylist(dir, true);
      return await _addTracks([...tracks, ...split.tracks, ...await _readSacds(isos)]);
    } finally {
      _addingFolders.remove(dir);
    }
  }

  Future<int> _addTracks(Iterable<Track> tracks) async {
    final known = _library.map((t) => t.id).toSet();
    final fresh = tracks.where((t) => known.add(t.id)).toList();
    if (fresh.isEmpty) return 0;
    // A song downloaded again (another format) replaces its earlier download in the library, rather than
    // showing twice; the older file is left where it is.
    final again = {for (final t in fresh) ?youtubeVideoIdOf(t.sourceUrl)};
    _library = [
      for (final t in _library)
        if (!again.contains(youtubeVideoIdOf(t.sourceUrl))) t,
      ...fresh,
    ];
    if (again.isNotEmpty && _repointDownloads()) unawaited(_savePlaylists());
    notifyListeners();
    await _save();
    unawaited(_enrichUntagged());
    return fresh.length;
  }

  /// How far the tag scan is; for views that show progress, so they need not follow [libraryRevision].
  final scanProgress = ValueNotifier<({int done, int total})>((done: 0, total: 0));

  void _setProgress(int done, int total) {
    if (!_disposed) scanProgress.value = (done: done, total: total);
  }

  /// How often the UI is told of new tags while they are being read.
  static const scanNotifyEvery = Duration(seconds: 2);

  /// The clock for the scan's throttles (tests set their own).
  DateTime Function() now = DateTime.now;

  /// Reads embedded tags for any track that hasn't been scanned yet.
  Future<void> _enrichUntagged() async {
    if (_scanning) return;
    _scanning = true;
    const qualityVersionKey = 'library.codecQuality.v1';
    bool needsMetadata(Track t) => !t.tagged || (t.path != null && t.audioQuality == null);
    try {
      final prefs = await SharedPreferences.getInstance();
      // Older scans saved the extension as the codec (FLAC named .m4a was "M4A").
      // Refresh once off the UI isolate; existing libraries then merge without reimporting.
      final refreshQuality = prefs.getBool(qualityVersionKey) != true;
      var pending = _library.where((t) => needsMetadata(t) || (refreshQuality && t.path != null)).toList();
      _setProgress(0, pending.length);
      notifyListeners();
      while (pending.isNotEmpty) {
        // Where each song sits, worked out again only if the library was replaced meanwhile.
        List<Track>? indexed;
        var at = <String, int>{};
        var notified = now();
        await Metadata.enrichAll(pending, (batch) {
          if (!identical(indexed, _library)) {
            indexed = _library;
            at = {for (var i = 0; i < _library.length; i++) _library[i].id: i};
          }
          for (final t in batch) {
            if (at[t.id] case final i?) _replaceAt(i, t);
          }
          // A first play can start before an old library's codec refresh finishes.
          // Join its newly recognised file now instead of requiring another tap.
          _joinScannedLocal().ignore();
          _setProgress(scanProgress.value.done + batch.length, scanProgress.value.total);
          // Sorting and grouping the library again is the costly part, so the UI hears of the new tags every
          // [scanNotifyEvery] and once at the end; progress has its own notifier.
          if (now().difference(notified) >= scanNotifyEvery) {
            notified = now();
            notifyListeners();
          }
        });
        await _save();
        // Pick up anything imported while we were scanning.
        pending = _library.where(needsMetadata).toList();
        _setProgress(0, pending.length);
      }
      if (refreshQuality) await prefs.setBool(qualityVersionKey, true);
    } finally {
      _scanning = false;
      notifyListeners();
      MemoryTrim.schedule();
    }
  }

  Future<void> _joinScannedLocal() async {
    if (_disposed || casting || _leavingMerge) return;
    final state = player.sequenceState;
    final source = state.currentSource;
    final track = currentTrack;
    final index = state.currentIndex;
    if (track?.videoId == null || index == null || _manualAudio.choice(track!.videoId!) != null) return;
    // A song streamed from YouTube (the type test only; just_audio marks the class experimental).
    // ignore: experimental_member_use
    if (source is! StreamAudioSource || (source is SmartMergeAudioSource && source.from != null)) return;
    if (_smartMerge.soundFrom(track.videoId!)?.source == TrackSource.device) return;
    final matching = _withMeasuredDuration(track);
    final file = _smartMerge.local(matching, _views.library, (
      _views.library,
      libraryRevision.value,
    ), available: (candidate) => File(candidate.path!).existsSync());
    if (file == null) return;
    _leavingMerge = true;
    final playing = player.playing;
    final generation = _playbackRetryGeneration;
    try {
      await player.setAudioSources(
        [for (final item in state.sequence) _sourceFor(item.tag as Track)],
        initialIndex: index,
        initialPosition: player.position,
      );
      if (playing && !_disposed && generation == _playbackRetryGeneration) unawaited(_play());
    } catch (error) {
      debugPrint('Smart merge: joining scanned local audio failed: ${error.runtimeType}');
    } finally {
      _leavingMerge = false;
    }
  }

  /// Writes new tags into [track]'s file and refreshes it in the library.
  Future<void> editTags(Track track, TagEdit edit) async {
    // Windows can't replace a file that is open: the playing song lets go of it while it is rewritten.
    final state = player.sequenceState;
    final index = state.currentIndex;
    final release = Host.isWindows && track.path != null && index != null && currentAudioTrack?.path == track.path;
    final position = player.position, playing = player.playing;
    if (release) await player.stop();
    final Track updated;
    try {
      updated = await Metadata.writeTags(track, edit);
    } finally {
      if (release && !_disposed) {
        await _load([for (final s in state.sequence) s.tag as Track], index, position: position);
        if (playing) unawaited(_play());
      }
    }
    final i = _library.indexWhere((t) => t.id == track.id);
    if (i >= 0) {
      _replaceAt(i, updated);
    } else {
      _libraryEdits++;
    }
    notifyListeners();
    await _save();
  }

  /// Keeps [updated] in the library in place of the song with its id, for edits
  /// the file itself can't hold (a downloaded song's title in a format with no tag writer).
  Future<void> replaceTrack(Track updated) async {
    final i = _library.indexWhere((t) => t.id == updated.id);
    if (i < 0) return;
    _library = [..._library]..[i] = updated;
    _libraryEdits++;
    notifyListeners();
    await _save();
  }

  Future<void> removeTrack(Track track) => removeTracks([track]);

  /// Takes songs out of the library (their files stay). A folder look must not bring them back.
  Future<void> removeTracks(Iterable<Track> tracks) async {
    final ids = {for (final t in tracks) t.id};
    if (ids.isEmpty) return;
    FolderWatch.instance.exclude([for (final t in tracks) t.path]);
    _library = _library.where((t) => !ids.contains(t.id)).toList();
    notifyListeners();
    await _save();
  }

  /// Deletes downloaded songs: out of the library, and their files off this device. Returns how many files
  /// couldn't be deleted (they are still taken out of the library).
  Future<int> deleteDownloads(Iterable<Track> tracks) async {
    final gone = tracks.where((t) => t.isDownload).toList();
    var failed = 0;
    for (final t in gone) {
      try {
        if (FileSystemEntity.typeSync(t.path!, followLinks: false) == FileSystemEntityType.file) {
          await File(t.path!).delete();
        }
      } on FileSystemException {
        failed++;
      }
      // Its music video ("Download with MV") goes with it.
      await MvSidecar.delete(t.path!);
    }
    await removeTracks(gone);
    return failed;
  }

  /// A download still named after its source's id: `mono_…`, `sflx_…`, or an 11-character YouTube video id.
  static final _idName = RegExp(r'^(mono_[A-Za-z0-9_-]+|sflx_[0-9a-f]{64}|[A-Za-z0-9_-]{11})$');

  /// Gives downloads made before they were named "Artist - Title" that name, with their lyrics and music video
  /// beside them, and points the library and playlists at the new files. The song playing (its file open) and
  /// anything that can't be moved keep their names. Returns how many were renamed.
  Future<int> renameDownloads() async {
    if (Host.isWeb) return 0;
    final moved = <String, Track>{};
    for (final t in List.of(_library)) {
      final path = t.path;
      if (!t.isDownload || path == null || t.start != null || t.id == currentTrack?.id) continue;
      if (!_idName.hasMatch(p.basenameWithoutExtension(path))) continue;
      final file = File(path);
      try {
        if (!await file.exists()) continue;
        final named = await nameDownload(file, artist: t.artist, title: t.title);
        if (named.path == path) continue;
        // What follows the song's name moves with it.
        final from = p.withoutExtension(path), to = p.withoutExtension(named.path);
        for (final ext in ['.lrc', '.mv.mp4', '.mv.webm', '.mv.json']) {
          final side = File('$from$ext');
          if (await side.exists()) await side.rename('$to$ext').catchError((_) => side);
        }
        final uri = Uri.file(named.path);
        moved[t.id] = t.copyWith(id: uri.toString(), uri: uri);
      } catch (e) {
        debugPrint('Download not renamed ($path): $e');
      }
    }
    if (moved.isEmpty) return 0;
    _library = [for (final t in _library) moved[t.id] ?? t];
    libraryRevision.value++;
    notifyListeners();
    await _save();
    await swapTrackRefs(moved);
    return moved.length;
  }

  /// Applies what a look at a music folder found: new files, gone files, moved files and changed files.
  Future<void> applyFolderChanges(FolderPlan plan) async {
    if (plan.removedIds.isNotEmpty || plan.moved.isNotEmpty || plan.retagIds.isNotEmpty) {
      _library = [
        for (final t in _library)
          if (!plan.removedIds.contains(t.id))
            if (plan.moved[t.id] case final m?)
              m
            else if (plan.retagIds.contains(t.id))
              t.copyWith(tagged: false)
            else
              t,
      ];
      notifyListeners();
      await _save();
      await swapTrackRefs(plan.moved);
    }
    final paths = plan.addedPaths;
    final cues = [
      for (final path in paths)
        if (path.toLowerCase().endsWith('.cue')) File(path),
    ];
    final isos = [
      for (final path in paths)
        if (path.toLowerCase().endsWith('.iso')) path,
    ];
    final split = await _readCues(cues);
    final songs = [
      for (final path in paths)
        if (Track.isAudioPath(path) && !split.covers.contains(path)) Track.fromUri(Uri.file(path)),
    ];
    final fresh = [...songs, ...split.tracks, ...await _readSacds(isos)];
    // A whole-album file the library already lists as one song is now split by its new cue sheet.
    if (split.tracks.isNotEmpty) {
      final known = _library.map((t) => t.id).toSet();
      if (split.tracks.any((t) => !known.contains(t.id))) {
        final whole = {for (final c in split.covers) Uri.file(c).toString()};
        _library = _library.where((t) => !whole.contains(t.id)).toList();
      }
    }
    if (await _addTracks(fresh) == 0 && plan.retagIds.isNotEmpty) unawaited(_enrichUntagged());
  }

  /// Points playlists and "recently played" at [to] wherever they hold a song with the id in [to]'s keys: a
  /// song that moved, or the copy kept in place of a duplicate. A playlist that has the new one already
  /// doesn't get it twice.
  Future<void> swapTrackRefs(Map<String, Track> to) async {
    if (to.isEmpty) return;
    var playlistsChanged = false;
    _playlists = [
      for (final pl in _playlists)
        if (pl.tracks.any((t) => to.containsKey(t.id)))
          () {
            playlistsChanged = true;
            final seen = <String>{};
            return pl.copyWith(
              tracks: [
                for (final t in pl.tracks)
                  if (seen.add((to[t.id] ?? t).id)) to[t.id] ?? t,
              ],
            );
          }()
        else
          pl,
    ];
    final recent = {for (final id in _recentIds) to[id]?.id ?? id}.toList();
    final recentChanged = !listEquals(recent, _recentIds);
    _recentIds = recent;
    if (playlistsChanged || recentChanged) notifyListeners();
    if (playlistsChanged) await _savePlaylists();
    if (recentChanged) (await SharedPreferences.getInstance()).setStringList(_recentKey, _recentIds);
  }

  /// The queue in its original order; the player holds the shuffled copy.
  ///
  /// Shuffle is done here, not with just_audio's shuffle(): the desktop
  /// backend (media_kit / mpv) has no setShuffleOrder, so that call throws there.
  List<Track> _ordered = const [];
  bool _shuffled = false;
  final _random = math.Random();

  static const _longPositionKey = 'playback.longPositions.v1';
  final _longPositions = <String, int>{};

  Duration? resumePosition(Track track) => ExtraFeature.resumeLongTracks.enabled && _longPositions.containsKey(track.id)
      ? Duration(milliseconds: _longPositions[track.id]!)
      : null;

  Future<void> resumeLongTrack(Track track, {String? from}) async {
    final saved = resumePosition(track);
    if (saved != null) await _playList([track], 0, from: from, startPosition: saved);
  }

  void _saveLongPosition() {
    final track = currentTrack;
    final length = duration;
    if (!ExtraFeature.resumeLongTracks.enabled ||
        track == null ||
        length == null ||
        length < const Duration(minutes: 15) ||
        ListenTogether.of(this).role == ListenRole.guest) {
      return;
    }
    final at = position;
    final stored = _longPositions[track.id];
    if (at < const Duration(seconds: 12) || length - at < const Duration(seconds: 20)) {
      if (_longPositions.remove(track.id) == null) return;
    } else {
      if (stored == at.inMilliseconds) return;
      _longPositions.remove(track.id);
      _longPositions[track.id] = at.inMilliseconds;
      if (_longPositions.length > 200) _longPositions.remove(_longPositions.keys.first);
    }
    _queuePrefs?.setString(_longPositionKey, jsonEncode(_longPositions)).ignore();
  }

  Future<void> hideRecommendedTrack(Track track) async {
    await LayoutPrefs.instance.hideRecommendation(track.id);
    final state = player.sequenceState;
    final at = state.sequence.indexWhere((s) => (s.tag as Track?)?.id == track.id, (state.currentIndex ?? -1) + 1);
    if (at >= 0 && isAutoplayed(track)) await removeQueueIndex(at);
  }

  bool _canRecommend(Track track) =>
      !ExtraFeature.hideRecommendations.enabled || !LayoutPrefs.instance.hiddenRecommendations.contains(track.id);

  static const _queuePrefsKey = 'playback.queue.v1';
  SharedPreferences? _queuePrefs;
  AppLifecycleListener? _queueLifecycle;
  bool _restoringQueue = false;
  bool _queueSaveScheduled = false;

  /// The restored queue isn't opened yet. just_audio forgets its starting song once anything seeks the idle player
  /// (the bar, Next), and Play then opened the first song in the queue instead of the one on screen.
  bool _restoredIdle = false;

  Future<void> _restoreQueue(SharedPreferences prefs) async {
    _queuePrefs = prefs;
    try {
      final decoded = jsonDecode(prefs.getString(_longPositionKey) ?? '{}') as Map<String, dynamic>;
      _longPositions.addEntries(
        decoded.entries.where((entry) => entry.value is int).map((entry) => MapEntry(entry.key, entry.value as int)),
      );
    } on FormatException catch (error) {
      debugPrint('Long playback positions unreadable: $error');
    } on TypeError catch (error) {
      debugPrint('Long playback positions unreadable: $error');
    }
    _queueLifecycle ??= AppLifecycleListener(onPause: _saveQueue, onHide: _saveQueue);
    final raw = prefs.getString(_queuePrefsKey);
    if (raw == null || player.audioSources.isNotEmpty) return;
    _restoringQueue = true;
    try {
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      final tracks = (saved['tracks'] as List).map((item) => Track.fromJson((item as Map).cast())).toList();
      if (tracks.isEmpty) return;
      final ordered = (saved['ordered'] as List?)?.map((item) => Track.fromJson((item as Map).cast())).toList();
      final index = (saved['index'] as int).clamp(0, tracks.length - 1);
      final position = Duration(milliseconds: math.max(0, saved['positionMs'] as int));
      _ordered = ordered ?? tracks;
      _shuffled = saved['shuffled'] == true && ordered != null;
      playingFrom = saved['from'] as String?;
      // Populate the idle playlist. The media engine opens it only when the listener presses Play.
      await player.setAudioSources([for (final track in tracks) _sourceFor(track)], preload: false);
      await player.seek(position, index: index);
      _restoredIdle = true;
    } catch (e) {
      debugPrint('Restoring playback queue failed: $e');
      if (player.audioSources.isEmpty) {
        _ordered = const [];
        _shuffled = false;
        playingFrom = null;
      }
    } finally {
      _restoringQueue = false;
    }
    if (!_disposed) notifyListeners();
  }

  void _saveQueue() {
    if (_queuePrefs == null || _queueSaveScheduled || _restoringQueue || _changingShuffle) return;
    _queueSaveScheduled = true;
    scheduleMicrotask(() {
      _queueSaveScheduled = false;
      if (!_disposed) _writeQueue();
    });
  }

  void _writeQueue() {
    final prefs = _queuePrefs;
    if (prefs == null || _restoringQueue || ListenTogether.of(this).role == ListenRole.guest) return;
    _saveLongPosition();
    final state = player.sequenceState;
    if (state.sequence.any((source) => source.tag is! Track)) return;
    if (state.sequence.isEmpty) {
      if (prefs.containsKey(_queuePrefsKey)) prefs.remove(_queuePrefsKey).ignore();
      return;
    }
    final snapshot = jsonEncode({
      'tracks': [for (final source in state.sequence) (source.tag as Track).toJson()],
      if (_shuffled) 'ordered': [for (final track in _ordered) track.toJson()],
      'shuffled': _shuffled,
      'index': state.currentIndex ?? 0,
      'positionMs': position.inMilliseconds,
      'from': playingFrom,
    });
    if (prefs.getString(_queuePrefsKey) != snapshot) {
      prefs.setString(_queuePrefsKey, snapshot).ignore();
    }
  }

  /// The same song on YouTube Music, for a Spotify song the account can't play (no Premium).
  Future<YoutubeAudioSource?> _youtubeInstead(Track t, {required Track tag}) async {
    final song = ForeignSong(title: t.title, artist: t.artist, duration: t.duration);
    final hit = PlaylistTransfer.best(song, await searchYoutube('${t.title} ${t.artist.replaceAll(',', '')}'));
    return hit == null ? null : YoutubeAudioSource(hit.videoId!, yt: youtube.client, tag: tag);
  }

  AudioSource _sourceFor(Track t, {Track? tag}) {
    final source = _buildSourceFor(t, tag: tag);
    if (t.path != null) _audioTracks[source] = t;
    return source;
  }

  AudioSource _buildSourceFor(Track t, {Track? tag}) {
    final identity = tag ?? t;
    if (SacdDisc.isSacdTrack(t)) {
      final found = SacdDisc.find(t);
      if (found != null) {
        final (disc, song) = found;
        // DoP needs the DSD itself; DST-compressed discs play as PCM.
        if (audio.dopActive && !disc.area.dst) {
          final dsd = SacdDsd(disc, song);
          if (audio.dopFits(dsd.bitRate)) return DopAudioSource(dsd, tag: identity);
        }
        return SacdAudioSource(disc, song, tag: identity);
      }
    }
    if (audio.dopActive && !t.isCueTrack && t.path != null && DsdFile.isDsdPath(t.path!)) {
      final dsd = DsdFile.read(t.path!);
      if (dsd != null && audio.dopFits(dsd.bitRate)) return DopAudioSource(dsd, tag: identity);
    }
    if (t.monochromeId != null || t.extensionId != null) {
      final local = downloadedCopy(t);
      if (local?.path case final path? when File(path).existsSync()) return _sourceFor(local!, tag: identity);
    }
    if (t.isRemote) {
      // The web build plays straight from the proxy; it can't feed the browser's player a byte stream.
      if (webAudioUri(t.videoId!) case final uri?) return AudioSource.uri(uri, tag: identity);
      if (_manualAudio.choice(t.videoId!) case final choice?) {
        final chosen = choice.track;
        // A Monochrome stream picked before it became download-only plays YouTube instead.
        final available = chosen?.path != null && File(chosen!.path!).existsSync();
        if (available && !_smartMerge.gaveUpOn(t.videoId!)) {
          _smartMerge.markUsed(t.videoId!, sound: (source: TrackSource.device, name: ''));
          return _sourceFor(chosen, tag: identity);
        }
        // An explicit YouTube choice, a missing file or a failed override uses the
        // original audio, never a different automatic recording.
        return _youtubeSource?.call(identity) ?? YoutubeAudioSource(t.videoId!, yt: youtube.client, tag: identity);
      }
      // Smart merge: the same recording from a lossless file here, then from a source that has it in better
      // quality, and the song's own stream otherwise.
      final merge = _smartMerge;
      final matching = _withMeasuredDuration(t);
      final file = merge.local(matching, _views.library, (
        _views.library,
        libraryRevision.value,
      ), available: (file) => File(file.path!).existsSync());
      if (file != null) {
        // The name is the UI's to give (Your Library, in the reader's language).
        merge.markUsed(t.videoId!, sound: (source: TrackSource.device, name: ''));
        return _sourceFor(file, tag: identity);
      }
      final local = downloadedCopy(t);
      if (local != null && !merge.gaveUpOn(t.videoId!)) return _sourceFor(local, tag: identity);
      final own = _youtubeSource?.call(identity) ?? YoutubeAudioSource(t.videoId!, yt: youtube.client, tag: identity);
      return merge.streams(matching) ? SmartMergeAudioSource(matching, youtube: own, merge: merge) : own;
    }
    if (t.soundcloudId case final id?) return SoundcloudAudioSource(id, client: soundcloud, tag: identity);
    if (t.extensionId != null) return SpotiflacAudioSource(t);
    if (t.spotifyId case final id?) {
      return SpotifyAudioSource(
        id,
        tag: identity,
        fallback: () => _youtubeInstead(t, tag: identity),
      );
    }
    if (t.monochromeId case final id? when !id.startsWith('tracks:')) return MonochromeAudioSource(id, tag: identity);
    return t.isCueTrack
        ? ClippingAudioSource(child: AudioSource.uri(t.uri), start: t.start, end: t.end, tag: identity)
        : AudioSource.uri(t.uri, tag: identity);
  }

  /// Search cards and shared links can omit length. Only the playing song may
  /// borrow the decoder's measured duration; another queued song must never do so.
  Track _withMeasuredDuration(Track track) {
    final actual = player.duration;
    return track.duration == null &&
            track.videoId != null &&
            track.videoId == currentTrack?.videoId &&
            actual != null &&
            actual > Duration.zero
        ? track.copyWith(duration: actual)
        : track;
  }

  bool _dopWasActive = false;

  /// Tempo & pitch: the player's speed follows them (the engine sets the filter and the pitch correction).
  void _followTempo() {
    final speed = audio.mpvSpeed;
    if ((player.speed - speed).abs() > 1e-6) unawaited(player.setSpeed(speed));
  }

  /// DoP switched on or off: rebuild the queue so DSD songs change over,
  /// from where the current one is.
  void _onAudioSettings() {
    if (audio.dopActive == _dopWasActive) return;
    _dopWasActive = audio.dopActive;
    final seq = player.sequenceState;
    final at = seq.currentIndex;
    final hasDsd = seq.sequence.any((s) {
      final t = s.tag as Track;
      return SacdDisc.isSacdTrack(t) || (t.path != null && DsdFile.isDsdPath(t.path!));
    });
    if (at == null || !hasDsd) return;
    final wasPlaying = player.playing;
    final position = player.position;
    _load([for (final s in seq.sequence) s.tag as Track], at, position: position).then((_) {
      if (wasPlaying) unawaited(player.play());
    }, onError: (Object e) => debugPrint('Reloading for DoP failed: $e'));
  }

  /// Tells the engine when a DoP stream plays (it holds volume at 100%).
  void _followDop() {
    final source = player.sequenceState.currentSource;
    audio.dopPlaying = source is DopAudioSource ? DsdPlayback(source.dsd.bitRate) : null;
  }

  /// [first] followed by everything else in random order.
  List<Track> _shuffledFrom(List<Track> tracks, int first) => spreadArtists([
    tracks[first],
    ...([...tracks]..removeAt(first))..shuffle(_random),
  ]);

  Future<void> _load(List<Track> order, int index, {Duration? position}) async {
    try {
      await player.setAudioSources(
        [for (final t in order) _sourceFor(t)],
        initialIndex: index,
        initialPosition: position,
      );
    } on PlayerInterruptedException {
      // Something newer took over (another song picked, or a broken one skipped): fine.
    }
  }

  Track? _playableQueueTrack(Track track) {
    if (_unavailableExtensionRecent(track)) return null;
    // A downloaded Monochrome song plays in full from its file; otherwise only its preview ([previewLength]).
    if (track.monochromeId != null) return downloadedCopy(track) ?? track;
    return track.extensionId == null ? track : downloadedCopy(track);
  }

  bool canQueue(Track track) => _playableQueueTrack(track) != null;

  List<Track> _playableQueueTracks(List<Track> tracks) => [for (final track in tracks) ?_playableQueueTrack(track)];

  /// Replaces the queue with [tracks] and starts playing at [index].
  Future<void> playList(List<Track> tracks, int index, {String? from, bool shuffled = false}) =>
      _playList(tracks, index, from: from, shuffled: shuffled);

  Future<void> _playList(
    List<Track> tracks,
    int index, {
    String? from,
    bool shuffled = false,
    Duration? startPosition,
  }) async {
    if (_closingPlayer case final closing?) await closing;
    if (_disposed) return;
    _saveLongPosition();
    _cancelPlaybackRetry();
    if (tracks.isEmpty) return;
    _cancelledOpening = false;
    final selected = _playableQueueTrack(tracks[index.clamp(0, tracks.length - 1)]);
    _sayIfOffline(selected);
    if (selected == null) {
      _errors.add(tr.spotiflacDownloadToPlay);
      return;
    }
    final selectedIndex = tracks
        .take(index.clamp(0, tracks.length - 1))
        .where((track) => _playableQueueTrack(track) != null)
        .length;
    tracks = _playableQueueTracks(tracks);
    index = selectedIndex;
    // A guest picking a song doesn't leave Listen together: the song goes to the host's queue (when the host
    // lets friends add songs). Following the host's own song still loads it here.
    final session = ListenTogether.of(this);
    if (session.role == ListenRole.guest && !session.followingHost) {
      return session.suggest(tracks[index.clamp(0, tracks.length - 1)], announce: true);
    }
    _radioGeneration++;
    playingFrom = from;
    _autoplayed.clear();
    _autoplaySeed = null;
    _ordered = List.of(tracks);
    _shuffled = shuffled;
    final generation = _playbackRetryGeneration;
    try {
      // A song that fails to open never finishes loading: stop waiting once
      // the player reports it ([_onPlaybackError] moves on from there).
      final failed = Completer<bool>();
      final cancelled = _openingCancelled = Completer<bool>();
      final sub = player.errorStream.listen((_) => failed.isCompleted ? null : failed.complete(false));
      _starting = true;
      notifyListeners();
      _retryingId = null;
      final loaded =
          await Future.any([
            _load(
              shuffled ? _shuffledFrom(tracks, index) : tracks,
              shuffled ? 0 : index,
              position: startPosition,
            ).then((_) => true),
            failed.future,
            cancelled.future,
          ]).timeout(const Duration(seconds: 45), onTimeout: () => false).whenComplete(() {
            if (generation == _playbackRetryGeneration) _starting = false;
            if (identical(_openingCancelled, cancelled)) _openingCancelled = null;
            return sub.cancel();
          });
      if (loaded && !_disposed && generation == _playbackRetryGeneration && !_recovering) {
        unawaited(_play(restart: true));
      } else if (!loaded &&
          !_disposed &&
          generation == _playbackRetryGeneration &&
          !_recovering &&
          _retryingId != tracks[index].id) {
        _recoverOrReport(tracks[index], player.sequenceState.currentIndex, true);
      }
    } on PlayerException catch (e) {
      debugPrint('Playback failed: ${e.message}');
      // Already being tried again ([_onPlaybackError] heard it too): it reports if that runs out.
      if (!_disposed && generation == _playbackRetryGeneration && _retryingId != tracks[index].id) _onPlaybackError(e);
    }
    notifyListeners();
  }

  Future<void> playCollection(Collection c, {int index = 0, bool shuffled = false}) =>
      playList(c.tracks, shuffled ? _random.nextInt(c.tracks.length) : index, from: c.title, shuffled: shuffled);

  /// True when [c] is what the queue was started from.
  bool isPlayingFrom(Collection c) {
    if (playingFrom != c.title) return false;
    final id = currentTrack?.id;
    return c.tracks.any((t) => t.id == id);
  }

  Future<void> playQueueItem(Track track) async {
    final index = player.sequenceState.sequence.indexWhere((s) => (s.tag as Track).id == track.id);
    if (index < 0) return;
    await playQueueIndex(index);
  }

  /// Plays the exact queue occurrence, including a repeated copy of the same track.
  Future<void> playQueueIndex(int index) async {
    _saveLongPosition();
    _cancelPlaybackRetry();
    RangeError.checkValidIndex(index, player.sequenceState.sequence);
    await player.seek(Duration.zero, index: index);
    unawaited(_play(restart: true));
  }

  /// Puts [tracks] right after the current song ("Play next").
  Future<void> playNext(List<Track> tracks) async {
    tracks = _playableQueueTracks(tracks);
    if (tracks.isEmpty) return;
    final session = ListenTogether.of(this);
    if (session.role == ListenRole.guest) {
      for (final track in tracks) {
        await session.suggest(track);
      }
      return;
    }
    final current = currentTrack;
    final at = player.sequenceState.currentIndex;
    if (current == null || at == null) return playList(tracks, 0);
    final inOrder = _ordered.indexWhere((t) => t.id == current.id);
    _ordered = [..._ordered]..insertAll(inOrder < 0 ? _ordered.length : inOrder + 1, tracks);
    await player.insertAudioSources(at + 1, [for (final t in tracks) _sourceFor(t)]);
    notifyListeners();
  }

  /// Puts [tracks] after the current song and after any of [after] still ahead in the queue: songs friends
  /// add in Listen together play in the order they came.
  Future<void> queueAfter(List<Track> tracks, {required Set<String> after}) async {
    tracks = _playableQueueTracks(tracks);
    if (tracks.isEmpty) return;
    final current = currentTrack;
    final at = player.sequenceState.currentIndex;
    if (current == null || at == null) return playList(tracks, 0);
    final sequence = player.sequenceState.sequence;
    var insertAt = at + 1;
    for (var i = at + 1; i < sequence.length; i++) {
      if (after.contains((sequence[i].tag as Track).id)) insertAt = i + 1;
    }
    final before = (sequence[insertAt - 1].tag as Track).id;
    final inOrder = _ordered.indexWhere((t) => t.id == before);
    _ordered = [..._ordered]..insertAll(inOrder < 0 ? _ordered.length : inOrder + 1, tracks);
    await player.insertAudioSources(insertAt, [for (final t in tracks) _sourceFor(t)]);
    notifyListeners();
  }

  /// Moves the song [from] places after the current one to [to] places after it (the queue page's drag).
  Future<void> moveInQueue(int from, int to) async {
    final at = player.sequenceState.currentIndex;
    final length = player.sequenceState.sequence.length;
    if (at == null || from == to) return;
    final a = at + 1 + from, b = at + 1 + to;
    if (a >= length || b >= length || a <= at || b <= at) return;
    await player.moveAudioSource(a, b);
    notifyListeners();
  }

  /// Takes the song [index] places after the current one out of the queue.
  Future<void> removeFromQueue(int index) async {
    final at = player.sequenceState.currentIndex;
    final sequence = player.sequenceState.sequence;
    if (at == null) return;
    final i = at + 1 + index;
    if (i >= sequence.length) return;
    await removeQueueIndex(i);
  }

  /// Clears the upcoming queue while keeping the current occurrence and playback position.
  Future<void> clearUpcomingQueue() async {
    if (ListenTogether.of(this).role == ListenRole.guest) return;
    final state = player.sequenceState;
    final current = state.currentIndex;
    if (current == null || current + 1 >= state.sequence.length) return;
    _radioGeneration++;
    _autoplaySeed = currentTrack?.id;
    final counts = <String, int>{};
    for (final source in state.sequence.take(current + 1)) {
      final track = source.tag as Track;
      counts.update(track.id, (count) => count + 1, ifAbsent: () => 1);
    }
    final retainedIds = counts.keys.toSet();
    await player.removeAudioSourceRange(current + 1, state.sequence.length);
    _ordered = [
      for (final track in _ordered)
        if (counts.update(track.id, (count) => count - 1, ifAbsent: () => -1) >= 0) track,
    ];
    _autoplayed.retainAll(retainedIds);
    _saveQueue();
    notifyListeners();
  }

  /// Removes an upcoming row and returns an Undo action tied to the same queue.
  Future<Future<void> Function()?> removeUpcomingWithUndo(int index) async {
    final seq = player.sequenceState;
    if (index < 0 || index >= seq.sequence.length || seq.currentIndex == null || index <= seq.currentIndex!) {
      return null;
    }
    final track = seq.sequence[index].tag as Track;
    final before = seq.sequence[index - 1];
    final next = index + 1 < seq.sequence.length ? seq.sequence[index + 1] : null;
    final orderedAt = _ordered.indexWhere((t) => t.id == track.id);
    final wasAutoplay = isAutoplayed(track);
    await removeQueueIndex(index);
    return () async {
      if (_disposed) return;
      final now = player.sequenceState;
      final sourceBefore = now.sequence.indexOf(before);
      final sourceAfter = next == null ? -1 : now.sequence.indexOf(next);
      if (sourceBefore < 0 && sourceAfter < 0) return;
      final index = math.max((now.currentIndex ?? -1) + 1, sourceAfter >= 0 ? sourceAfter : sourceBefore + 1);
      _ordered = [..._ordered]..insert(orderedAt < 0 ? _ordered.length : orderedAt.clamp(0, _ordered.length), track);
      if (wasAutoplay) _autoplayed.add(track.id);
      await player.insertAudioSources(index, [_sourceFor(track)]);
      _saveQueue();
      notifyListeners();
    };
  }

  /// Removes an absolute queue index, as returned by the CLI's queue listing.
  Future<void> removeQueueIndex(int index) async {
    _cancelPlaybackRetry();
    final sequence = player.sequenceState.sequence;
    RangeError.checkValidIndex(index, sequence);
    final track = sequence[index].tag as Track;
    await player.removeAudioSourceAt(index);
    // Out of the play-in-order list too, so turning shuffle off doesn't bring it back.
    final inOrder = _ordered.indexWhere((t) => t.id == track.id);
    if (inOrder >= 0) _ordered = [..._ordered]..removeAt(inOrder);
    _saveQueue();
    notifyListeners();
  }

  /// Puts [tracks] at the end of the queue ("Add to queue").
  Future<void> addToQueue(List<Track> tracks) async {
    tracks = _playableQueueTracks(tracks);
    if (tracks.isEmpty) return;
    // A guest adds to the host's queue instead (when the host lets them).
    final session = ListenTogether.of(this);
    if (session.role == ListenRole.guest) {
      for (final track in tracks) {
        await session.suggest(track, announce: tracks.length == 1);
      }
      return;
    }
    if (currentTrack == null) return playList(tracks, 0);
    _ordered = [..._ordered, ...tracks];
    await player.addAudioSources([for (final t in tracks) _sourceFor(t)]);
    notifyListeners();
  }

  /// Stops and empties the queue: the mini player and the notification go away.
  Future<void> closePlayer() => _closingPlayer ??= _closePlayer().whenComplete(() => _closingPlayer = null);

  Future<void> _closePlayer() async {
    _bluetoothResume = null;
    _bluetoothPause = null;
    _cancelledOpening = true;
    _cancelPlaybackRetry();
    _radioGeneration++;
    sleep.cancel();
    if (casting) await cast.disconnect();
    await player.stop();
    await player.clearAudioSources();
    await YoutubeAudioSource.clearCache();
    _ordered = const [];
    _autoplayed.clear();
    _autoplaySeed = null;
    playingFrom = null;
    _saveQueue();
    notifyListeners();
    MemoryTrim.schedule();
  }

  Future<void> togglePlay() async {
    if (_closingPlayer != null) return;
    _bluetoothResume = null;
    _bluetoothPause = null;
    if (!casting && (_starting || (_recovering && _retryWantsPlay))) return pause();
    _cancelPlaybackRetry();
    if (player.audioSources.isEmpty) {
      if (canPlay) await playCollection(allSongs);
    } else if (casting) {
      await (cast.playing ? cast.pause() : _play());
    } else if (player.playing && player.processingState != ProcessingState.completed) {
      await player.pause();
    } else {
      // At the end of the queue play() would do nothing: the song the player shows (the last one) plays again from its
      // start. Not the queue's first song: Play on a bar showing one song must not start another.
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero, index: player.currentIndex ?? 0);
      }
      unawaited(_play());
    }
  }

  /// While a song plays from its better sound's download: should the download fall behind where the song is (the
  /// connection died, or is slower than the sound), the song goes back to its own sound there before it runs out.
  Timer? _mergeWatch;
  String? _mergeWatched;

  void _watchMergedDownload() {
    final source = player.sequenceState.currentSource;
    final id = source is SmartMergeAudioSource && source.from != null ? source.track.videoId : null;
    final download = id == null ? null : _smartMerge.downloadOf(id);
    if (download == null || download.done) {
      _mergeWatch?.cancel();
      _mergeWatch = null;
      _mergeWatched = null;
      return;
    }
    if (_mergeWatched == id && _mergeWatch != null) return;
    _mergeWatch?.cancel();
    _mergeWatched = id;
    _mergeWaitingSince = null;
    _mergeWatch = Timer.periodic(const Duration(milliseconds: 500), (_) => _checkMergedDownload(id!, download));
  }

  bool _leavingMerge = false;
  DateTime? _mergeWaitingSince;

  /// How long a song waits on its better sound's download, with nothing coming, before it goes back to YouTube.
  static const _mergeGivesUpAfter = Duration(seconds: 8);

  Future<void> _checkMergedDownload(String id, MergedDownload download) async {
    final state = player.sequenceState;
    final source = state.currentSource;
    if (_disposed || source is! SmartMergeAudioSource || source.track.videoId != id || source.from == null) {
      _mergeWatch?.cancel();
      _mergeWatch = null;
      _mergeWatched = null;
      return;
    }
    if (download.done || _leavingMerge || !player.playing) return;
    final length = player.duration ?? source.track.duration;
    if (length == null) return;
    final total = download.total;
    if (total == null) return;
    // Close to where the song is, or waiting on it (it hasn't got going, or it is buffering).
    final edge = ((player.position + const Duration(seconds: 2)).inMilliseconds / length.inMilliseconds).clamp(
      0.0,
      1.0,
    );
    final waiting = !download.covers((total * edge).ceil()) || player.processingState != ProcessingState.ready;
    // A short lag is waited out (the player buffers a moment, and the download comes back faster than the song
    // plays). Only a download that has given up, or one that sends nothing for a long while as the song waits
    // on it, takes the song back to YouTube.
    final now = DateTime.now();
    if (!waiting) _mergeWaitingSince = null;
    final since = _mergeWaitingSince ??= now;
    // Counted from when the song began waiting, or from the last bytes if any came since.
    final last = download.lastProgress.isAfter(since) ? download.lastProgress : since;
    // Turned away (too many requests): no use waiting, it goes back while the song still has its last seconds.
    if (!download.failed && !(waiting && download.busy) && !(waiting && now.difference(last) > _mergeGivesUpAfter)) {
      return;
    }
    // Behind: back to the song's own sound, from here.
    _leavingMerge = true;
    debugPrint('Smart merge: the download of $id stopped coming, back to YouTube');
    try {
      // Turned away by the service's request limit: only until that is over (its next source plays YouTube and
      // moves back once the limit is lifted, SmartMergeAudioSource.late). Otherwise for the rest of the session.
      if (download.busy && !download.failed) {
        _smartMerge.markLimited(id);
      } else {
        _smartMerge.giveUp(id);
      }
      _cancelPlaybackRetry();
      final index = state.currentIndex;
      if (index == null) return;
      await player.setAudioSources(
        [for (final s in state.sequence) _sourceFor(s.tag as Track)],
        initialIndex: index,
        initialPosition: player.position,
      );
      if (!_disposed) unawaited(_play());
    } catch (e) {
      debugPrint('Smart merge: going back to YouTube failed: $e');
    } finally {
      _leavingMerge = false;
    }
  }

  String? _prefetched;

  /// A song that began from YouTube because its better sound took longer than [SmartMerge.patience] (a slow
  /// catalogue): once that sound is found and its download has got past where the song is, the song moves over
  /// to it there, so the first play is merged too instead of only the next one.
  SmartMergeAudioSource? _lateFollowed;
  Timer? _lateWatch;

  void _followLateMerge() {
    final source = player.sequenceState.currentSource;
    // A song left before its better sound came no longer waits for it (its badge stops saying it's coming).
    if (_lateFollowed case final left? when !identical(left, source) && left.from == null) {
      _smartMerge.markWaiting(left.track.videoId!, false);
    }
    if (source is! SmartMergeAudioSource || source.from != null || identical(source, _lateFollowed)) return;
    final late = source.late;
    if (late == null) return;
    _lateFollowed = source;
    _lateWatch?.cancel();
    late.then((choice) {
      if (choice == null || _disposed || !identical(player.sequenceState.currentSource, source)) return;
      _lateWatch?.cancel();
      _lateWatch = Timer.periodic(const Duration(milliseconds: 500), (_) => _joinLateMerge(source));
    }).ignore();
  }

  /// How much of the song must be left for moving over to be worth it.
  static const _lateMergeLeft = Duration(seconds: 15);

  /// How far past the song's position its better sound's download must be, so the song carries on at once there.
  static const _lateMergeAhead = Duration(seconds: 10);

  Future<void> _joinLateMerge(SmartMergeAudioSource source) async {
    void stop() {
      _lateWatch?.cancel();
      _lateWatch = null;
    }

    final id = source.track.videoId;
    if (_disposed || id == null || !identical(player.sequenceState.currentSource, source) || casting) return stop();
    if (_smartMerge.gaveUpOn(id) || !_smartMerge.wants(source.track)) return stop();
    if (_leavingMerge) return;
    final length = player.duration ?? source.track.duration;
    if (length == null || length <= Duration.zero) return;
    if (length - player.position < _lateMergeLeft) return stop();
    // Fetched from its start: wait until it is past where the song is (a stream played from its address needs no
    // wait).
    if (_smartMerge.downloadOf(id) case final download?) {
      // Got ready ahead it holds only its start: this song is moving over to it, so the whole file comes.
      download.play();
      final total = download.total;
      if (total == null) return;
      final edge = ((player.position + _lateMergeAhead).inMilliseconds / length.inMilliseconds).clamp(0.0, 1.0);
      if (!download.covers((total * edge).ceil())) return;
    }
    stop();
    final state = player.sequenceState;
    final index = state.currentIndex;
    if (index == null) return;
    _leavingMerge = true;
    final playing = player.playing;
    debugPrint('Smart merge: $id moves over to its better sound at ${player.position}');
    try {
      _cancelPlaybackRetry();
      await player.setAudioSources(
        [for (final s in state.sequence) _sourceFor(s.tag as Track)],
        initialIndex: index,
        initialPosition: player.position,
      );
      if (playing && !_disposed) unawaited(_play());
    } catch (e) {
      debugPrint('Smart merge: moving over to the better sound failed: $e');
    } finally {
      _leavingMerge = false;
    }
  }

  void _followSmartMerge() {
    if (_disposed || _restoringQueue) return;
    _watchMergedDownload();
    _followLateMerge();
    // The next song is looked up and its download begun while this one plays, so it opens at once.
    final up = _crossfadeUpcoming();
    final next = up?.next;
    if (next == null || next.id == _prefetched) return;
    _prefetched = next.id;
    if (next.videoId == null || _manualAudio.choice(next.videoId!) == null) _smartMerge.prefetch(next);
    // The one after it too, a little later and only while the service isn't limiting requests: two songs
    // skipped in a row still open at once (each got ready ahead is only its first 2 MB).
    _prefetchAfter?.cancel();
    final after = _neighbour(2);
    if (after == null || after == up!.nextIndex) return;
    final second = player.sequenceState.sequence[after].tag as Track;
    // Only a song Smart merge would play from elsewhere: nothing to get ready for the others.
    if (!_smartMerge.streams(second) || _manualAudio.choice(second.videoId!) != null) return;
    _prefetchAfter = Timer(const Duration(seconds: 20), () {
      if (_disposed || RequestGate.anyBusy.value || _crossfadeUpcoming()?.next.id != next.id) return;
      _smartMerge.prefetch(second);
    });
  }

  Timer? _prefetchAfter;

  /// Plays here, or on the cast device. [restart]: the song was just chosen,
  /// so start it from the top even if it's the one already on the device.
  Future<void> _play({bool restart = false}) async {
    if (_disposed || _closingPlayer != null) return;
    _cancelledOpening = false;
    _bluetoothResume = null;
    _bluetoothPause = null;
    if (!casting) {
      final generation = _playbackRetryGeneration;
      if (_soundcloudExpired) await _refreshSoundcloud();
      if (_disposed || generation != _playbackRetryGeneration) return;
      if (_restoredIdle) {
        _restoredIdle = false;
        final state = player.sequenceState;
        final index = state.currentIndex;
        if (player.processingState == ProcessingState.idle && index != null) {
          // Opened here at the song and spot on screen, not where just_audio would start.
          unawaited(_load([for (final s in state.sequence) s.tag as Track], index, position: player.position));
        }
      }
      return player.play();
    }
    if (cast.loadedKey != currentTrack?.id) return _castCurrent(play: true);
    // Already sent (the queue change just did it).
    if (cast.loading) return;
    if (restart) await cast.seek(Duration.zero);
    return cast.play();
  }

  /// The song [offset] steps away in play order (the queue is already in
  /// shuffled order when shuffling). Wraps around in repeat-all.
  ///
  /// Not just_audio's next/previous index: in repeat-one those point back at
  /// the current song, so Next and Previous would only restart it.
  int? _neighbour(int offset, {int? from}) {
    final seq = player.sequenceState;
    final at = from ?? seq.currentIndex;
    final n = seq.sequence.length;
    if (at == null || n == 0) return null;
    final i = at + offset;
    if (i >= 0 && i < n) return i;
    return player.loopMode == LoopMode.all ? (i % n + n) % n : null;
  }

  bool get hasNext => _neighbour(1) != null;
  bool get hasPrevious => _neighbour(-1) != null;

  Future<void> next() async {
    _saveLongPosition();
    _cancelPlaybackRetry();
    final i = _neighbour(1);
    if (i != null) await player.seek(Duration.zero, index: i);
  }

  /// Restarts the current track unless we're near the beginning.
  Future<void> previous() => _previous(restartCurrent: true);

  /// Goes straight to the previous queue entry when the mini player is swiped.
  Future<void> previousTrack() => _previous(restartCurrent: false);

  Future<void> _previous({required bool restartCurrent}) async {
    _saveLongPosition();
    _cancelPlaybackRetry();
    final i = _neighbour(-1);
    if (restartCurrent && (position > const Duration(seconds: 3) || i == null)) {
      await seek(Duration.zero);
    } else if (i != null) {
      await player.seek(Duration.zero, index: i);
    }
  }

  bool _changingShuffle = false;

  /// Moves the existing sources so the current stream and paused position survive shuffle.
  Future<void> toggleShuffle() async {
    if (_changingShuffle) return;
    final current = currentTrack;
    if (current == null || _ordered.isEmpty) return;
    final enable = !_shuffled;
    final at = _ordered.indexWhere((t) => t.id == current.id);
    if (at < 0) return;
    final state = player.sequenceState;
    final playingSource = state.currentSource;
    if (playingSource == null || state.sequence.length != _ordered.length) return;
    final remaining = [...state.sequence]..remove(playingSource);
    final target = <IndexedAudioSource>[];
    final tracks = enable ? _shuffledFrom(_ordered, at) : _ordered;
    for (var i = 0; i < tracks.length; i++) {
      if (i == (enable ? 0 : at)) {
        target.add(playingSource);
      } else {
        final sourceAt = remaining.indexWhere((source) => (source.tag as Track).id == tracks[i].id);
        if (sourceAt < 0) return;
        target.add(remaining.removeAt(sourceAt));
      }
    }
    _changingShuffle = true;
    final generation = _playbackRetryGeneration;
    try {
      for (var i = 0; i < target.length; i++) {
        if (_disposed || generation != _playbackRetryGeneration) return;
        final sequence = player.sequenceState.sequence;
        if (sequence.length != target.length) return;
        final from = sequence.indexOf(target[i]);
        if (from < 0) return;
        if (from != i) await player.moveAudioSource(from, i);
      }
      _shuffled = enable;
      notifyListeners();
    } finally {
      _changingShuffle = false;
      _saveQueue();
    }
  }

  static const _loopKey = 'loop.v1';

  /// Off → repeat all → repeat one → off. Remembered, like shuffle in the
  /// streaming apps.
  Future<void> cycleLoopMode() async {
    final mode = switch (player.loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await player.setLoopMode(mode);
    // Repeat stops autoplay from adding songs; off lets it pick up again.
    if (mode == LoopMode.off) _maybeAutoplay();
    await (await SharedPreferences.getInstance()).setString(_loopKey, mode.name);
  }

  // The queue stays in [player], paused, while a TV or speaker plays: next,
  // previous and queue picks move it, and [_castFollow] sends the new song.

  late final Cast cast = Cast(
    onEnded: _castEnded,
    airPlay: () => Cast.canConvert,
    onError: (message) {
      _errors.add(message);
      // The device went away: carry on here, from where it was.
      if (!casting) _updatePresence(force: true);
    },
  )..addListener(_castChanged);

  bool get casting => cast.active;

  void _castChanged() {
    _updatePresence();
    notifyListeners();
  }

  /// Plays on [renderer] from where this device is, or back here (null).
  Future<void> castTo(CastTarget? renderer) async {
    if (renderer == null) return _stopCasting();
    if (cast.target == renderer) return;
    final from = position;
    final wasPlaying = isPlaying;
    try {
      await cast.connect(renderer);
    } catch (e) {
      debugPrint('Casting to ${renderer.name} failed: $e');
      _errors.add(tr.couldntReachDevice(renderer.name));
      return;
    }
    await player.pause();
    if (currentTrack != null) await _castCurrent(from: from, play: wasPlaying);
    _updatePresence(force: true);
  }

  Future<void> _stopCasting() async {
    if (!casting) return;
    final from = cast.position;
    final wasPlaying = cast.playing;
    final onDevice = cast.loadedKey;
    await cast.disconnect();
    if (onDevice != null && onDevice == currentTrack?.id) await player.seek(from);
    if (wasPlaying) unawaited(player.play());
    _updatePresence(force: true);
  }

  /// Sends the current song to the cast device when the queue moves on.
  void _castFollow() {
    if (!casting || currentTrack == null || cast.loadedKey == currentTrack!.id) return;
    _castCurrent(play: true);
  }

  Future<void> _castCurrent({Duration from = Duration.zero, bool play = true}) async {
    final t = currentTrack;
    if (t == null || !casting) return;
    // SoundCloud streams as HLS, which TVs and speakers rarely play; it stays on this device.
    if (t.soundcloudId != null) {
      notify(tr.soundcloudCantCast);
      return;
    }
    // Spotify's audio only leaves the bridge on this device's loopback.
    if (t.spotifyId != null) {
      notify(tr.spotifyCantCast);
      return;
    }
    if (t.monochromeId != null && downloadedCopy(t) == null) {
      notify(tr.monochromeCantCast);
      return;
    }
    if (t.extensionId != null && downloadedCopy(t) == null) {
      notify(tr.spotiflacCantCast);
      return;
    }
    await cast.load(_castItem(t), from: from, play: play);
  }

  void _castEnded() {
    if (player.loopMode == LoopMode.one) {
      _castCurrent(play: true);
    } else if (_neighbour(1) case final next?) {
      player.seek(Duration.zero, index: next).then((_) => _castFollow(), onError: (Object _) {});
    }
    _updatePresence(force: true);
  }

  /// Formats nearly every renderer plays as they are.
  static const _castMimes = {
    'mp3': 'audio/mpeg',
    'flac': 'audio/flac',
    'm4a': 'audio/mp4',
    'mp4': 'audio/mp4',
    'aac': 'audio/mp4',
    'wav': 'audio/wav',
  };

  CastItem _castItem(Track t) {
    final local = t.isRemote || t.monochromeId != null || t.extensionId != null ? downloadedCopy(t) : t;
    final path = local?.path;
    final CastMedia Function(Duration) media;
    final sacd = SacdDisc.isSacdTrack(t) ? SacdDisc.find(t) : null;
    if (sacd != null) {
      // No renderer plays DSD: the song (as DSDIFF) is converted to FLAC.
      final source = SacdAudioSource(sacd.$1, sacd.$2);
      media = (from) => CastTranscode(path!, start: from, maxRate: 176400, source: source);
    } else if (path == null) {
      // Most TVs and speakers can't decode Opus, so YouTube songs go as AAC.
      final source = YoutubeAudioSource(t.videoId!, yt: youtube.client, aac: true);
      media = (_) => CastStream(source, 'audio/mp4');
    } else {
      final ext = path.split('.').last.toLowerCase();
      final direct = _castMimes[ext];
      if ((direct != null && !t.isCueTrack) || !Cast.canConvert) {
        // Without a decoder, the device may still know the format.
        media = (_) => CastFile(path, direct ?? 'audio/${ext == 'ogg' || ext == 'oga' ? 'ogg' : ext}');
      } else {
        final dsd = ext == 'dsf' || ext == 'dff';
        media = (from) =>
            CastTranscode(path, start: (t.start ?? Duration.zero) + from, end: t.end, maxRate: dsd ? 176400 : 192000);
      }
    }
    return CastItem(
      key: t.id,
      media: media,
      title: t.title,
      artist: t.artist,
      album: t.album,
      duration: t.isCueTrack && t.end != null ? t.end! - t.start! : t.duration ?? player.duration,
      art: () => Metadata.artwork(t),
    );
  }

  bool _disposed = false;

  /// Bumped whenever the library or the Riflay playlists changed, for views
  /// that show only those (the library list, a collection's songs): they then
  /// skip the far more frequent changes of what's playing.
  final libraryRevision = ValueNotifier<int>(0);
  (List<Track>, int, List<UserPlaylist>)? _revisionOf;
  DateTime? _lastRevisionBump;

  /// Work started in [load] (tag tools probe, tag enrichment) can finish after dispose.
  @override
  void notifyListeners() {
    if (_disposed) return;
    final seen = _revisionOf;
    if (seen == null || !identical(seen.$1, _library) || seen.$2 != _libraryEdits || !identical(seen.$3, _playlists)) {
      // Tags arriving in a scan only change what songs say about themselves: those wait for the next
      // [scanNotifyEvery] (and the end of the scan). Anything else is shown at once.
      final onlyTags = seen != null && identical(seen.$1, _library) && identical(seen.$3, _playlists);
      final at = now();
      final last = _lastRevisionBump;
      if (!(onlyTags && _scanning && last != null && at.difference(last) < scanNotifyEvery)) {
        _revisionOf = (_library, _libraryEdits, _playlists);
        _lastRevisionBump = at;
        libraryRevision.value++;
      }
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    Connection.instance.online.removeListener(_onlineChanged);
    _stall?.cancel();
    recentRadios.dispose();
    _writeQueue();
    _queueLifecycle?.dispose();
    _disposed = true;
    _cancelPlaybackRetry();
    _qualityTimer?.cancel();
    _soundcloudRefresh?.cancel();
    _soundcloudServed?.cancel();
    // A level set in the last half second is still kept.
    if (_saveVolume?.isActive ?? false) {
      _saveVolume!.cancel();
      _storeVolume().ignore();
    }
    MemoryTrim.stop();
    cast.dispose();
    _smartMerge.changes.removeListener(_followSmartMerge);
    _prefetchAfter?.cancel();
    _lateWatch?.cancel();
    _mergeWatch?.cancel();
    _crossfader.dispose();
    sleep.dispose();
    for (final s in _subs) {
      s.cancel();
    }
    player.dispose();
    unawaited(YoutubeAudioSource.clearCache().catchError((Object e) => debugPrint('Audio cache cleanup: $e')));
    _errors.close();
    youtube.dispose();
    ytMusic.dispose();
    audio.dispose();
    discord.dispose();
    libraryRevision.dispose();
    scanProgress.dispose();
    _recentsTimer?.cancel();
    if (_recentsTimer != null) _storeRecents().ignore();
    _saveTimer?.cancel();
    if (_savePending) _save().ignore();
    _level.dispose();
    super.dispose();
  }
}

/// Lets the [SleepTimer] read and control the player.
class _SleepHost implements SleepHost {
  _SleepHost(this.c);
  final PlayerController c;

  @override
  bool get playing => c.isPlaying;

  @override
  String? get trackId => c.currentTrack?.id;

  @override
  Duration? get songRemaining {
    final d = c.duration;
    if (d == null || d <= const Duration(seconds: 1)) return null; // not known yet
    final left = d - c.position;
    return left.isNegative ? Duration.zero : left;
  }

  @override
  void setFade(double gain) => c._setSleepFade(gain);

  @override
  Future<void> pause() => c.pause();
}
