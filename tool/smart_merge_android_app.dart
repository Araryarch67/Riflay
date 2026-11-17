// Real-device regression: build only with --android-project-arg=riflayDev=true.
// Pass --dart-define=RIFLAY_LOCAL_MERGE_FILE=/storage/emulated/0/Documents/song.flac.
// Uses the separate Dev app's data and a cache copy; never edits the original music.
// ignore_for_file: invalid_use_of_visible_for_testing_member, depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:riflay/main.dart' as app;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/manual_audio.dart';
import 'package:riflay/services/metadata.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/smart_merge.dart';

Future<void> _until(bool Function() ready) async {
  final watch = Stopwatch()..start();
  while (!ready() && watch.elapsed < const Duration(seconds: 40)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  if (!ready()) throw StateError('Timed out waiting for playback');
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
  debugPrint('SMART_MERGE_ANDROID PASS $message');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final package = await PackageInfo.fromPlatform();
  if (!Platform.isAndroid || package.packageName != 'dev.riflay.riflay.dev') {
    throw StateError('Run only in the isolated Android Dev application');
  }
  try {
    const path = String.fromEnvironment('RIFLAY_LOCAL_MERGE_FILE');
    if (path.isEmpty) throw StateError('RIFLAY_LOCAL_MERGE_FILE is required');
    final dir = await Directory.systemTemp.createTemp('riflay-codec-merge-');
    final file = await File(path).copy('${dir.path}/Kyapi.m4a');
    final measured = await Metadata.enrich(Track.fromUri(file.uri));
    _check(
      measured.audioQuality?.startsWith('FLAC') == true,
      'FLAC signature overrides .m4a: ${measured.audioQuality}',
    );
    // Reproduce a library imported before codec detection was fixed.
    SharedPreferences.setMockInitialValues({
      'library.v1': jsonEncode([measured.copyWith(audioQuality: 'M4A').toJson()]),
      'sources.smartMerge.v1': true,
      'sources.monochrome.v1': false,
      'discord.enabled': false,
      'videoMode.on': false,
      'deviceSetup.v1': true,
      'autoplay.v1': false,
    });
    await app.main([]);
    PlayerController? controller;
    void visit(Element element) {
      if (element.widget case app.RiflayApp(:final controller)) {
        // Capturing outside the pattern keeps the resolved controller available below.
        found = controller;
      }
      element.visitChildren(visit);
    }

    await _until(() {
      found = null;
      WidgetsBinding.instance.rootElement?.visitChildren(visit);
      controller = found;
      return controller != null;
    });
    final c = controller!;
    await _until(() => !c.scanning);
    _check(c.library.single.audioQuality?.startsWith('FLAC') == true, 'old M4A quality migrated without reimport');
    await c.setAutoplay(false);
    await c.setVolume(.04);
    final song = Track.youtube(
      videoId: '-H4bB6hxeEs',
      title: 'きゃぴ - Kyapi',
      artist: 'Houshou Marine',
      duration: const Duration(seconds: 199),
    );
    await c.playList([song], 0);
    await _until(() => c.player.playing && c.position > const Duration(seconds: 1));
    _check(c.player.sequenceState.currentSource is UriAudioSource, 'automatic merge uses local audio');
    _check(SmartMerge.instance.soundFrom(song.videoId!)?.source == TrackSource.device, 'YouTube x library badge');
    _check(c.currentTrack?.id == song.id, 'YouTube metadata identity retained');
    final signal = await c.audio.signalPath();
    debugPrint('SMART_MERGE_ANDROID SIGNAL ${signal?.qualityText}');
    await c.player.pause();
    await c.player.seek(const Duration(seconds: 12));
    debugPrint('SMART_MERGE_ANDROID BEFORE SWITCH ${c.position}');
    await c.setAudioChoice(song, const ManualAudioChoice.youtube());
    debugPrint('SMART_MERGE_ANDROID AFTER YOUTUBE ${c.position}');
    _check(!c.player.playing, 'manual YouTube keeps pause');
    _check(SmartMerge.instance.soundFrom(song.videoId!) == null, 'manual YouTube clears merged badge');
    _check(
      (c.position - const Duration(seconds: 12)).abs() < const Duration(seconds: 1),
      'manual YouTube retains position',
    );
    await c.setAudioChoice(song, ManualAudioChoice.track(c.library.single));
    _check(!c.player.playing && c.currentTrack?.id == song.id, 'manual local keeps pause and YouTube identity');
    _check(
      (c.position - const Duration(seconds: 12)).abs() < const Duration(seconds: 1),
      'manual local retains position',
    );
    await c.setAudioChoice(song, null);
    _check(c.audioChoice(song) == null, 'automatic selection restored');
    unawaited(c.player.play());
    await _until(() => c.position > const Duration(seconds: 13));
    debugPrint('SMART_MERGE_ANDROID ALL PASSED');
  } catch (error, stack) {
    debugPrint('SMART_MERGE_ANDROID FAILED $error\n$stack');
  }
}

PlayerController? found;
