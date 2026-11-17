// The desktop island for real: docked and floating, its bars following the music with the visualizer switch off,
// and a docked island dragged down going back to the top edge. Prints CAPTURE lines for a screenshot script.
// Run only with isolated APPDATA/LOCALAPPDATA.
// CPU sampling is external, so its work is not charged to the app process.
// ignore_for_file: invalid_use_of_visible_for_testing_member, depend_on_referenced_packages
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:riflay/services/splash_window.dart';
import 'package:riflay/main.dart' as app;
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/youtube_stream.dart';
import 'package:riflay/services/ranged_download.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/page_scaffold.dart';
import 'package:riflay/ui/player/mini_window.dart' show miniPlayer, refreshMiniPlayer, setMiniPlayer;

Element? _page() {
  Element? found;
  void visit(Element element) {
    if (element.widget is PageScaffold && element.getInheritedWidgetOfExactType<ShellScope>() != null) found = element;
    if (found == null) element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    _countFrames();
    final folder = Directory(Platform.environment['APPDATA']!);
    PathProviderPlatform.instance = _IsolatedPaths(folder.path);
    SharedPreferences.setMockInitialValues({
      'discord.enabled': false,
      'videoMode.on': false,
      'deviceSetup.v1': true,
      'sources.smartMerge.v1': false,
      'autoplay.v1': false,
    });
    await app.main([]);
    final watch = Stopwatch()..start();
    while (_page() == null && watch.elapsed.inSeconds < 90) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    final page = _page();
    if (page == null) throw StateError('App did not become ready');
    while (SplashWindow.active.value && watch.elapsed.inSeconds < 90) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await windowManager.show();
    await windowManager.focus();
    WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final c = PlayerScope.read(page);
    final gpuOnly = Platform.environment['RIFLAY_BENCH_GPU_ONLY'] == 'true';
    if (gpuOnly) await LayoutPrefs.instance.setVideoDecoder(VideoDecoder.hardware);
    await c.setAutoplay(false);
    final songs = await c.searchYoutube('Houshou Marine Kyapi');
    if (songs.isEmpty) throw StateError('No Kyapi search results');
    final song = songs.first;
    stdout.writeln('SONG ${song.title} | ${song.artist} | ${song.videoId}');
    // Use the exact same cached Kyapi frames in both phases. Network stalls
    // must not make a decoder appear cheap simply because it stopped drawing.
    final cache = Directory('${Directory.current.path}/build/kyapi-benchmark')..createSync(recursive: true);
    final file = File('${cache.path}/kyapi.mp4');
    if (!file.existsSync()) {
      final mv = await c.ytMusic.musicVideo(song.videoId!);
      if (mv == null) throw StateError('Kyapi music video was not found');
      final video = await YoutubeStream.video(mv.videoId, maxHeight: 720);
      final audio = await YoutubeStream.best(mv.videoId, aac: true);
      final picture = File('${cache.path}/picture.mp4');
      final sound = File('${cache.path}/sound.m4a');
      stdout.writeln('CACHE Kyapi ${mv.videoId} ${video.height}p');
      await Future.wait([
        rangedDownload(url: video.url, out: picture),
        rangedDownload(url: audio.url, out: sound, totalBytes: audio.size),
      ]);
      final pending = File('${cache.path}/kyapi.pending.mp4');
      final mux = await Process.run('ffmpeg', [
        '-hide_banner',
        '-loglevel',
        'error',
        '-y',
        '-i',
        picture.path,
        '-i',
        sound.path,
        '-map',
        '0:v:0',
        '-map',
        '1:a:0',
        '-c',
        'copy',
        pending.path,
      ]);
      if (mux.exitCode != 0) throw StateError('Could not prepare cached Kyapi: ${mux.stderr}');
      await pending.rename(file.path);
    }
    final local = Track(
      id: file.uri.toString(),
      uri: file.uri,
      title: song.title,
      artist: song.artist,
      artworkUrl: song.artworkUrl,
      duration: song.duration,
      sourceUrl: 'https://music.youtube.com/watch?v=${song.videoId}',
      tagged: true,
    );
    await LayoutPrefs.instance.setIslandBars(IslandBars.music);
    await LayoutPrefs.instance.setDesktopMini(DesktopMiniStyle.island);
    await c.playList([local], 0);
    await Future<void>.delayed(const Duration(seconds: 4));
    stdout.writeln('VISUALIZER switch=${LayoutPrefs.instance.visualizerEnabled}');
    Future<void> levels(String name) async {
      var most = 0.0, moving = 0;
      var last = <double>[];
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final v = c.audio.visualizerLevels.value;
        if (v.isNotEmpty) most = v.reduce((a, b) => a > b ? a : b) > most ? v.reduce((a, b) => a > b ? a : b) : most;
        if (v.isNotEmpty && last.isNotEmpty && v.length == last.length && v.join() != last.join()) moving++;
        last = List.of(v);
      }
      stdout.writeln('LEVELS $name most=${most.toStringAsFixed(2)} changed=$moving/50 active=${c.audio.visualizerActive}');
    }

    for (final place in [IslandPlacement.docked, IslandPlacement.floating]) {
      await LayoutPrefs.instance.setIslandPlacement(place);
      if (!miniPlayer.value) {
        await setMiniPlayer(true);
      } else {
        await refreshMiniPlayer();
      }
      await Future<void>.delayed(const Duration(seconds: 3));
      final b = await windowManager.getBounds();
      stdout.writeln('BOUNDS ${place.name} $b');
      stdout.writeln('CAPTURE island-${place.name}');
      await Future<void>.delayed(const Duration(seconds: 2));
      await levels(place.name);
    }
    // Dragged right and down while docked: it slides along the top edge only.
    final before = await windowManager.getBounds();
    stdout.writeln('DRAG');
    await Future<void>.delayed(const Duration(seconds: 4));
    final after = await windowManager.getBounds();
    stdout.writeln('SLID top ${before.top} -> ${after.top}, left ${before.left} -> ${after.left}');
    await LayoutPrefs.instance.setIslandBars(IslandBars.animated);
    await Future<void>.delayed(const Duration(seconds: 2));
    stdout.writeln('CAPTURE island-animated');
    await Future<void>.delayed(const Duration(seconds: 2));
    await setMiniPlayer(true, style: DesktopMiniStyle.window);
    await Future<void>.delayed(const Duration(seconds: 3));
    stdout.writeln('CAPTURE window');
    await Future<void>.delayed(const Duration(seconds: 2));
    stdout.writeln('PHASE done');
    exit(0);
  } catch (error, stack) {
    stderr.writeln('BENCHMARK FAILED: $error\n$stack');
    exit(1);
  }
}

class _IsolatedPaths extends PathProviderWindows {
  _IsolatedPaths(this.path);
  final String path;
  @override
  Future<String> getApplicationSupportPath() async => path;
  @override
  Future<String> getApplicationCachePath() async => path;
  @override
  Future<String> getTemporaryPath() async => path;
  @override
  Future<String> getApplicationDocumentsPath() async => path;
}

/// Once a second: how many frames Flutter drew and what they cost on the UI (build) and raster threads, so a
/// phase's frame rate can be read against the video's (a clock ticking at the display's rate shows up here).
void _countFrames() {
  var frames = 0;
  var build = 0, raster = 0;
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      frames++;
      build += t.buildDuration.inMicroseconds;
      raster += t.rasterDuration.inMicroseconds;
    }
  });
  Stream<void>.periodic(const Duration(seconds: 1)).listen((_) {
    stdout.writeln(
      'FRAMES at=${DateTime.now().millisecondsSinceEpoch} n=$frames build=${build ~/ 1000}ms raster=${raster ~/ 1000}ms',
    );
    frames = 0;
    build = 0;
    raster = 0;
  });
}
