// Real Smart merge run. Only with isolated APPDATA/LOCALAPPDATA: see the comment on main.
// ignore_for_file: invalid_use_of_visible_for_testing_member, depend_on_referenced_packages
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:riflay/services/splash_window.dart';
import 'package:riflay/main.dart' as app;
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/page_scaffold.dart';

import 'package:riflay/services/smart_merge.dart';

Element? _page() {
  Element? found;
  void visit(Element element) {
    if (element.widget is PageScaffold && element.getInheritedWidgetOfExactType<ShellScope>() != null) found = element;
    if (found == null) element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

/// Smart merge, for real: YouTube Music songs with Monochrome's sound, from a clean start (no remembered matches,
/// no downloads kept). For each song: how long until it plays, where from, whether it moves over to the better
/// sound (built with RIFLAY_MERGE_PATIENCE_MS to force that), and that its position never jumps or stalls.
/// Then the next song (got ready ahead while the first played) and how soon it opens.
Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    final folder = Directory(Platform.environment['APPDATA']!);
    PathProviderPlatform.instance = _IsolatedPaths(folder.path);
    final kept = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}riflay-smart-merge');
    if (kept.existsSync()) kept.deleteSync(recursive: true);
    SharedPreferences.setMockInitialValues({
      'discord.enabled': false,
      'videoMode.on': false,
      'deviceSetup.v1': true,
      'sources.smartMerge.v1': true,
      'sources.monochrome.v1': true,
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
    final c = PlayerScope.read(page);
    await c.setAutoplay(false);
    // Quiet: it plays for minutes on the speakers of whoever runs it.
    await c.setVolume(0.02);
    final queries =
        (Platform.environment['RIFLAY_MERGE_SONGS'] ??
                'YOASOBI Idol;Kenshi Yonezu Kick Back;The Weeknd Blinding Lights;Aimer Zankyosanka')
            .split(';');
    final songs = [for (final q in queries) ...(await c.searchYoutube(q)).where((t) => t.videoId != null).take(1)];
    stdout.writeln('SONGS ${songs.map((s) => '${s.title} | ${s.artist}').join(' ; ')}');
    var problems = 0;
    for (var i = 0; i < songs.length; i++) {
      final song = songs[i];
      final w = Stopwatch()..start();
      if (i == 0) {
        await c.playList(songs, 0);
      } else {
        await c.next();
      }
      while (!(c.isPlaying && c.position > Duration.zero) && w.elapsed.inSeconds < 40) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      final started = w.elapsedMilliseconds;
      String from() {
        final s = c.player.sequenceState.currentSource;
        return s is SmartMergeAudioSource ? (s.from?.name ?? 'YouTube') : 'not merged (${s.runtimeType})';
      }

      stdout.writeln(
        'START ${song.title}: ${c.currentTrack?.videoId == song.videoId ? '' : 'WRONG SONG '}'
        'playing after $started ms from ${from()}',
      );
      if (!c.isPlaying) problems++;
      var last = c.position;
      var lastFrom = from();
      var stalled = 0;
      final until = Duration(seconds: i == songs.length - 1 ? 30 : 45);
      final t = Stopwatch()..start();
      while (t.elapsed < until) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        final now = c.position;
        final f = from();
        if (f != lastFrom) {
          stdout.writeln('  MOVED ${song.title}: $lastFrom -> $f at $last -> $now (${t.elapsedMilliseconds} ms in)');
          lastFrom = f;
        }
        if (now < last - const Duration(milliseconds: 300)) {
          // A new source reads 0 for a moment while it opens at its place: look again a second later.
          await Future<void>.delayed(const Duration(seconds: 1));
          final settled = c.position;
          if (settled < last - const Duration(milliseconds: 300)) {
            problems++;
            stdout.writeln('  JUMP BACK ${song.title}: $last -> $settled');
          } else {
            stdout.writeln('  carried on ${song.title}: $last -> $settled');
          }
          last = settled;
          continue;
        }
        stalled = now - last < const Duration(milliseconds: 50) ? stalled + 1 : 0;
        if (stalled == 4) {
          problems++;
          stdout.writeln('  STALL ${song.title} at $now (${c.isBuffering ? 'buffering' : 'not buffering'}, from $f)');
        }
        last = now;
      }
      stdout.writeln('END ${song.title}: at $last from ${from()}');
    }
    stdout.writeln('DONE problems=$problems');
    exit(problems == 0 ? 0 : 2);
  } catch (error, stack) {
    stderr.writeln('SMART MERGE RUN FAILED: $error\n$stack');
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
