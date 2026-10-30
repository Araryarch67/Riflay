// Takes the screenshots in docs/screenshots for the README.
//
// Everything in the pictures is made up: the test writes a small library of generated songs (noise with tags
// and a generated cover) to /tmp/Music/Riflay, fills a listening history with invented plays, and keeps the
// network shut (only this computer's loopback is reachable), so no real artist, account or path ends up in a
// picture. Needs ffmpeg on the PATH. Does nothing without SHOTS.
//
//   weston --backend=headless --socket=om-test --width=3840 --height=2160 &   # once
//   env -u DISPLAY -u DBUS_SESSION_BUS_ADDRESS WAYLAND_DISPLAY=om-test GDK_BACKEND=wayland \
//     XDG_DATA_HOME=/tmp/om-shots-data \
//     flutter test integration_test/readme_screenshots_test.dart -d linux --dart-define=SHOTS=/tmp/om-shots
//
// mpv is sent to its null output (no sound device is touched) and muted. Run it from a copy of the project (see
// AGENT.md), then turn the PNGs into docs/screenshots/*.webp (ffmpeg -c:v libwebp -quality 80).
//
// Skipped on purpose: Video mode (it only exists for the music video of a YouTube song, which needs a real song)
// and the Search page (its YouTube Music half fails offline, and online it lists real artists).

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer;
import 'package:riflay/main.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/services/download_prefs.dart';
import 'package:riflay/services/listen_together/listen_together.dart';
import 'package:riflay/services/play_history.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/private_files.dart';
import 'package:riflay/services/video_download.dart';
import 'package:riflay/services/youtube_importer.dart';
import 'package:riflay/ui/download_options.dart';
import 'package:riflay/ui/pages/about_settings.dart' show debugSystem;
import 'package:riflay/ui/pages/duplicates_page.dart';
import 'package:riflay/ui/player_panels.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/signal_path.dart';
import 'package:riflay/ui/widgets/sleep_timer_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

const shots = String.fromEnvironment('SHOTS');

/// Where the made-up library lives; the same folder the download settings point at in the pictures.
const music = '/tmp/Music/Riflay';

/// One made-up album: [colors] paint its cover, [flac] says which songs are lossless.
typedef Album = ({String artist, String name, bool flac, List<int> colors, String type, List<String> songs});

const albums = <Album>[
  (
    artist: 'Marlow Quartet',
    name: 'Dusk Signals',
    flac: true,
    colors: [0x1b2a49, 0xe07a5f, 0xf2cc8f],
    type: 'radial',
    songs: ['Lantern Row', 'Paper Moons', 'Slow Tide Home', 'Glass Weather', 'Evening Cartography'],
  ),
  (
    artist: 'Pale Harbor',
    name: 'Salt and Static',
    flac: false,
    colors: [0x0b3c49, 0x3a9ea5, 0xf4f1de],
    type: 'linear',
    songs: ['Low Light Parade', 'Harbor Clocks', 'Wires in the Fog', 'Where the Radio Ends', 'Soft Landing'],
  ),
  (
    artist: 'Lumen Fields',
    name: 'Open Meridian',
    flac: true,
    colors: [0x3d1e6d, 0x8e44ad, 0xf7b267],
    type: 'spiral',
    songs: ['Meridian', 'Quiet Engines', 'Amber Hours', 'Northbound Dreaming', 'Field Notes'],
  ),
  (
    artist: 'The Quiet Orchard',
    name: 'Small Hours',
    flac: false,
    colors: [0x2d3a1f, 0x7a9e4b, 0xe9d985],
    type: 'circular',
    songs: ['Kettle Song', 'Window Seat', 'Fern and Lamplight', 'Late Bus', 'Wool Blanket'],
  ),
  (
    artist: 'Nova Vesper',
    name: 'Neon Index',
    flac: false,
    colors: [0x0f0f2d, 0xff2e63, 0x08d9d6],
    type: 'radial',
    songs: ['Signal Bloom', 'Chrome Lullaby', 'Midnight Index', 'Pulse Garden', 'Afterglow'],
  ),
  (
    artist: 'Copper Tide',
    name: 'Rust and Rhythm',
    flac: true,
    colors: [0x3b1f14, 0xb5532b, 0xe8b24a],
    type: 'linear',
    songs: ['Brass Lanterns', 'Tidal Math', 'Copper Wire Blues', 'Harbor Drum', 'Seventh Wave'],
  ),
  (
    artist: 'Ivy and the Drift',
    name: 'Green Room',
    flac: false,
    colors: [0x14342b, 0x2fb67d, 0xc6f0d4],
    type: 'spiral',
    songs: ['Ivy Stairs', 'Drift', 'Greenhouse Rain', 'Moss Telephone', 'Sunroom'],
  ),
];

/// Songs that also sit in "Old backup" as an MP3: the duplicate finder's pictures.
const copies = {'Lantern Row', 'Meridian', 'Brass Lanterns'};

/// Lines of the one song that has lyrics, timed word by word (made up).
const lyrics = [
  'Lanterns hang along the harbour wall',
  'Every window learns the evening slowly',
  'I count the boats that never come back in',
  'And the water keeps the names we gave it',
  'Hold the light a little longer now',
  'Paper moons are drifting down the river',
  'We were only ever passing through',
  'Singing to the dark like it was listening',
  'Hold the light a little longer now',
  'Lantern row, lantern row',
  'Take me home before the tide turns over',
  'Lantern row, lantern row',
  'Everything is quiet where we left it',
];

Future<void> ff(List<String> args) async {
  final r = await Process.run('ffmpeg', ['-loglevel', 'error', '-y', ...args]);
  if (r.exitCode != 0) throw StateError('ffmpeg ${args.join(' ')}: ${r.stderr}');
}

String two(int n) => n.toString().padLeft(2, '0');

String stamp(double seconds) {
  final m = seconds ~/ 60;
  return '${two(m)}:${(seconds - m * 60).toStringAsFixed(2).padLeft(5, '0')}';
}

/// The library on disk: songs with tags and a cover each, one .lrc, and three MP3 copies in "Old backup".
Future<void> makeLibrary() async {
  final root = Directory(music);
  if (root.existsSync()) root.deleteSync(recursive: true);
  root.createSync(recursive: true);
  Directory('$music/Old backup').createSync();
  final art = Directory.systemTemp.createTempSync('om-covers');
  try {
    for (final (a, album) in albums.indexed) {
      final cover = '${art.path}/$a.jpg';
      await ff([
        '-f', 'lavfi', '-i', //
        'gradients=size=640x640:c0=0x${album.colors[0].toRadixString(16).padLeft(6, '0')}:c1=0x${album.colors[1].toRadixString(16).padLeft(6, '0')}'
            ':c2=0x${album.colors[2].toRadixString(16).padLeft(6, '0')}:nb_colors=3:seed=${a + 3}:type=${album.type}:duration=1',
        '-frames:v', '1', cover,
      ]);
      Directory('$music/${album.artist} - ${album.name}').createSync();
      for (final (i, title) in album.songs.indexed) {
        final seconds = 150 + (a * 31 + i * 47) % 110;
        final ext = album.flac ? 'flac' : 'mp3';
        final tags = [
          '-metadata',
          'title=$title',
          '-metadata',
          'artist=${album.artist}',
          '-metadata',
          'album=${album.name}',
          '-metadata',
          'track=${i + 1}',
          '-metadata',
          'date=${2019 + a}',
        ];
        Future<void> encode(String to, {required bool lossless}) => ff([
          '-f', 'lavfi', '-i', 'anoisesrc=d=$seconds:c=pink:r=44100:a=0.2:seed=${a * 10 + i}',
          '-i', cover, '-map', '0:a', '-map', '1:v', '-ac', '2', //
          if (lossless) ...['-c:a', 'flac'] else ...['-c:a', 'libmp3lame', '-b:a', '192k'],
          '-c:v', 'copy', '-disposition:v', 'attached_pic', ...tags, to,
        ]);
        final file = '$music/${album.artist} - ${album.name}/${two(i + 1)} $title.$ext';
        await encode(file, lossless: album.flac);
        if (copies.contains(title)) await encode('$music/Old backup/$title.mp3', lossless: false);
        if (title == 'Lantern Row') {
          final out = StringBuffer();
          for (final (n, line) in lyrics.indexed) {
            final start = 12.0 + n * 5.2;
            final words = line.split(' ');
            final step = 4.4 / words.length;
            out.writeln(
              '[${stamp(start)}]${[for (final (w, word) in words.indexed) '<${stamp(start + w * step)}>$word'].join(' ')} <${stamp(start + 4.4)}>',
            );
          }
          File('$music/${album.artist} - ${album.name}/${two(i + 1)} $title.lrc').writeAsStringSync(out.toString());
        }
      }
    }
  } finally {
    art.deleteSync(recursive: true);
  }
}

/// The network is shut apart from this computer (the pictures show no real service and the Home page has no
/// YouTube Music shelves to fill with real artists).
class _Offline extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = (uri, proxyHost, proxyPort) {
      final host = proxyHost ?? uri.host;
      if (host == '127.0.0.1' || host == 'localhost') {
        return Socket.startConnect(host, proxyPort ?? uri.port);
      }
      return Future.error(const SocketException('offline'));
    };
    return client;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> run(WidgetTester tester) async {
    final reportError = FlutterError.onError;
    FlutterError.onError = (details) {
      if ('${details.exception}'.contains('offline')) return debugPrint('Ignored (offline): ${details.exception}');
      reportError?.call(details);
    };
    ui.PlatformDispatcher.instance.onError = (e, s) {
      debugPrint('Ignored (offline): $e');
      return true;
    };
    HttpOverrides.global = _Offline();
    JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
    Directory(shots).createSync(recursive: true);
    await makeLibrary();

    // A silent-looking 24-bit / 96 kHz FLAC, for the signal path picture. Played directly, not added to the library.
    final dir = Directory.systemTemp.createTempSync('om-shots');
    final flac = '${dir.path}/Studio Session.flac';
    await ff([
      '-f', 'lavfi', '-i', 'sine=f=220:r=96000:d=600', '-ac', '2', '-sample_fmt', 's32', //
      '-metadata', 'title=Studio Session', '-metadata', 'artist=Marlow Quartet',
      '-metadata', 'album=Hi-Res Test', '-c:a', 'flac', flac,
    ]);
    final studio = Track(
      id: Uri.file(flac).toString(),
      uri: Uri.file(flac),
      title: 'Studio Session',
      artist: 'Marlow Quartet',
      album: 'Hi-Res Test',
    );

    // Covers for the download rows, from this computer.
    final art = Directory('${dir.path}/thumbs')..createSync();
    for (final (a, album) in albums.indexed) {
      await ff([
        '-f', 'lavfi', '-i', //
        'gradients=size=480x270:c0=0x${album.colors[0].toRadixString(16).padLeft(6, '0')}:c1=0x${album.colors[1].toRadixString(16).padLeft(6, '0')}'
            ':c2=0x${album.colors[2].toRadixString(16).padLeft(6, '0')}:nb_colors=3:seed=${a + 40}:type=linear:duration=1',
        '-frames:v', '1', '${art.path}/$a.jpg',
      ]);
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final file = File('${art.path}${req.uri.path}');
      if (file.existsSync()) {
        req.response.headers.contentType = ContentType('image', 'jpeg');
        await req.response.addStream(file.openRead());
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
    String thumb(int i) => 'http://127.0.0.1:${server.port}/$i.jpg';

    // Discord off: the real one, if running, would show these songs on the user's profile.
    SharedPreferences.setMockInitialValues({'discord.enabled': false, 'listen.name': 'Ana'});

    // No sound device: mpv's null output, and muted besides.
    final c = PlayerController();
    final apply = JustAudioMediaKit.onPlayerCreated!;
    JustAudioMediaKit.onPlayerCreated = (p) async {
      final mpv = p.platform as NativePlayer;
      await mpv.setProperty('ao', 'null');
      await mpv.setProperty('mute', 'yes');
      apply(p);
    };

    await c.load();
    await c.scanFolder(music);

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(RepaintBoundary(child: RiflayApp(controller: c)));

    // Lookups that need the internet fail quietly in the pictures; the test must not stop for them.
    void forgive() {
      while (tester.takeException() != null) {}
    }

    Future<void> settle([int ms = 600]) async {
      for (var i = 0; i < ms ~/ 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        forgive();
      }
    }

    Future<bool> until(bool Function() ok, {int seconds = 30}) async {
      for (var i = 0; i < seconds * 10; i++) {
        if (ok()) return true;
        await tester.pump(const Duration(milliseconds: 100));
        forgive();
      }
      return ok();
    }

    Future<void> shot(String name, {double pixelRatio = 1, Finder? of}) async {
      await settle(2500); // artwork and colours fade in
      final boundary = tester.renderObject<RenderRepaintBoundary>(of ?? find.byType(RepaintBoundary).first);
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: pixelRatio);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File('$shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    Future<void> playing() async {
      await until(() => c.player.playing && c.player.position > Duration.zero, seconds: 45);
    }

    // One picture failing must not lose the others.
    final failed = <String>[];
    Future<void> step(String name, Future<void> Function() body) async {
      try {
        await body();
      } catch (e, s) {
        failed.add(name);
        debugPrint('SHOT FAILED $name: $e\n$s');
        // Whatever is open is closed, so the next picture starts from a page.
        for (var i = 0; i < 3; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump(const Duration(milliseconds: 300));
        }
      }
    }

    Track song(String title, {bool flacOnly = true}) =>
        c.library.firstWhere((t) => t.title == title && (t.path?.contains('Old backup') != true));

    Future<void> openMore(String item) async {
      await tester.tap(find.byTooltip('More').first);
      await settle();
      await tester.tap(find.text(item).first);
      await settle();
    }

    try {
      await until(() => c.library.length >= 35 && c.library.every((t) => t.tagged), seconds: 60);

      // A listening history of invented plays, March to today.
      final rnd = Random(11);
      final all = c.library.where((t) => t.path?.contains('Old backup') != true).toList()..shuffle(rnd);
      final weights = [for (var i = 0; i < all.length; i++) 1 / pow(i + 1, 0.55)];
      final total = weights.fold<double>(0, (a, b) => a + b);
      Track pick() {
        var x = rnd.nextDouble() * total;
        for (var i = 0; i < all.length; i++) {
          x -= weights[i];
          if (x <= 0) return all[i];
        }
        return all.last;
      }

      final now = DateTime.now();
      for (var d = 230; d >= 0; d--) {
        final day = DateTime(now.year, now.month, now.day - d);
        if (rnd.nextDouble() < 0.12) continue;
        final songs = [for (var k = 0; k < 3 + rnd.nextInt(7); k++) pick()];
        if (rnd.nextDouble() < 0.5) songs.add(songs.first); // a favourite again the same day
        var minute = 7 * 60 + rnd.nextInt(180);
        for (final t in songs) {
          minute += 4 + rnd.nextInt(40);
          final at = day.add(Duration(minutes: minute));
          if (at.isAfter(now)) continue;
          PlayHistory.instance.record(t, Duration(seconds: 110 + rnd.nextInt(120)), at: at);
        }
      }

      // The songs that look downloaded from a music site (the Downloads page counts their files).
      for (final (i, title) in ['Harbor Clocks', 'Late Bus', 'Chrome Lullaby'].indexed) {
        final t = song(title);
        await c.replaceTrack(
          Track(
            id: t.id,
            uri: t.uri,
            title: t.title,
            artist: t.artist,
            album: t.album,
            duration: t.duration,
            trackNumber: t.trackNumber,
            addedAt: t.addedAt,
            tagged: true,
            sourceUrl: 'https://music.youtube.com/watch?v=Riflay00${i}xx',
          ),
        );
      }

      await DownloadPrefs.instance.load();
      await until(
        () => find.text('Recently played').evaluate().isNotEmpty || find.byTooltip('Home').evaluate().isNotEmpty,
      );
      await settle(3000);

      // Home with a song playing.
      final lantern = song('Lantern Row');
      await c.playList(c.library.where((t) => t.album == 'Dusk Signals').toList(), 0, from: 'Dusk Signals');
      await playing();
      await c.player.seek(const Duration(seconds: 48));
      await shot('home');

      // A Riflay playlist mixing artists.
      await step('playlist', () async {
        c.createPlaylist(
          'Slow evenings',
          tracks: [
            for (final t in [
              'Lantern Row',
              'Window Seat',
              'Amber Hours',
              'Harbor Clocks',
              'Wool Blanket',
              'Drift',
              'Slow Tide Home',
              'Greenhouse Rain',
            ])
              song(t),
          ],
        );
        await settle();
        await tester.tap(find.text('Slow evenings').first);
        await settle();
        await tester.tap(find.byTooltip('Shuffle play'));
        await playing();
        await shot('playlist');
      });

      // Smart playlists in the library.
      await step('smart-playlists', () async {
        await tester.tap(find.text('Most played').first);
        await settle();
        await shot('smart-playlists');
      });

      // Synced lyrics, word by word.
      await step('lyrics', () async {
        await c.playList([lantern], 0, from: 'Dusk Signals');
        await playing();
        await c.player.seek(const Duration(seconds: 33));
        await tester.tap(find.byTooltip('Lyrics'));
        await settle(5000);
        await shot('lyrics');
        await tester.tap(find.byTooltip('Lyrics').first);
        await settle();
      });

      // The sleep timer.
      await step('sleep-timer', () async {
        await tester.tap(find.byTooltip('Home'));
        await settle();
        showSleepTimer(tester.element(find.byType(Scaffold).first)).ignore();
        await settle();
        await shot('sleep-timer');
        await tester.tapAt(const Offset(60, 60));
        await settle();
      });

      // Listening stats and a Wrap.
      await step('stats', () async {
        // The library list in the sidebar builds its rows as they scroll into view.
        await tester.scrollUntilVisible(
          find.text('Your listening stats'),
          200,
          scrollable: find.ancestor(of: find.text('Recently added'), matching: find.byType(Scrollable)).first,
        );
        await settle();
        await tester.tap(find.text('Your listening stats').first);
        await settle(2000);
        await shot('stats');
        await tester.scrollUntilVisible(
          find.textContaining('in music').first,
          400,
          scrollable: find.byType(Scrollable).last,
        );
        await settle();
        await tester.tap(find.textContaining('in music').first);
        await settle(1500);
        for (var i = 0; i < 3; i++) {
          await tester.tap(find.byTooltip('Next').first);
          await settle(700);
        }
        // Just the card, as it is saved from the app.
        await shot(
          'wrap',
          pixelRatio: 3,
          of: find.descendant(of: find.byType(AspectRatio), matching: find.byType(RepaintBoundary)).first,
        );
        await tester.tap(find.byTooltip('Close').first);
        await settle();
      });

      // Settings and its pages.
      await step('settings', () async {
        await openMore('Settings');
        await shot('settings');
        // The folder is set before the page opens: it reads it once.
        await DownloadPrefs.instance.setFolder('/tmp/Music/Riflay');
        await tester.tap(find.text('Library & downloads'));
        await settle();
        await tester.tap(find.text('Downloads').last);
        await settle(1500);
        await shot('settings-downloads');
        await DownloadPrefs.instance.setFolder(null);
        await tester.tap(find.text('Settings').first); // the trail's first step: back to the list
        await settle();
        await Scrollable.ensureVisible(tester.element(find.text('Beta features')), alignment: 0.5);
        await settle();
        await tester.tap(find.text('Beta features'));
        await settle();
        await shot('settings-beta');
        await tester.tap(find.text('Settings').first);
        await settle();
        await tester.tap(find.text('Sound'));
        await settle();
        await tester.tap(find.text('Playback'));
        await settle();
        await tester.tap(find.text('Virtual speakers'));
        await shot('sound');
        await tester.tap(find.text('Virtual speakers'));
        await settle();
        await Scrollable.ensureVisible(tester.element(find.text('Crossfade').first), alignment: 0.3);
        await settle();
        await tester.tap(find.widgetWithText(SwitchListTile, 'Crossfade'));
        await settle();
        await Scrollable.ensureVisible(tester.element(find.text('Skip for albums')), alignment: 0.6);
        await settle();
        await shot('settings-crossfade');
        await tester.tap(find.widgetWithText(SwitchListTile, 'Crossfade'));
        await settle();
        await Scrollable.ensureVisible(tester.element(find.text('Equalizer')), alignment: 0.5);
        await settle();
        await tester.tap(find.text('Equalizer'));
        await settle();
        await tester.tap(find.widgetWithText(ChoiceChip, 'Bass boost'));
        await shot('equalizer');
        await tester.tap(find.widgetWithText(ChoiceChip, 'Flat'));
        await tester.tap(find.byType(Switch).first); // equalizer off again
        await settle();
      });

      // Settings › Library & downloads › Library, then the songs you have twice.
      await step('duplicates', () async {
        await openMore('Settings');
        await tester.tap(find.text('Library & downloads'));
        await settle();
        await tester.tap(find.text('Library').first);
        await settle();
        // Opened straight through the shell: on a computer the tile opens it under the same history entry as
        // the page itself, which is a step the history skips.
        ShellScope.of(tester.element(find.text('Find songs you have twice')))
            .open(const DuplicatesPage(), location: 'duplicates');
        await settle(3000);
        await shot('duplicates');
      });

      // The Downloads page, with a music video and a song on their way.
      await step('downloads', () async {
        final file = await PrivateFiles.file('download_queue.json');
        DownloadJob job(int i, String title, String channel, DownloadChoice choice) => DownloadJob(
          videoId: 'Riflay00${i}xx',
          title: title,
          channel: channel,
          thumbnailUrl: thumb(i),
          knownNames: true,
          choice: choice,
        );
        final jobs = [
          job(1, 'Harbor Clocks', 'Pale Harbor', DownloadChoice.video(VideoContainer.mp4, height: 1080)),
          job(2, 'Late Bus', 'The Quiet Orchard', const DownloadChoice(DownloadFormat.opus)),
          job(3, 'Chrome Lullaby', 'Nova Vesper', DownloadChoice.video(VideoContainer.webm, height: 1440)),
          job(4, 'Seventh Wave', 'Copper Tide', const DownloadChoice(DownloadFormat.flac)),
          job(5, 'Ivy Stairs', 'Ivy and the Drift', const DownloadChoice(DownloadFormat.opus)),
        ];
        for (final j in jobs) {
          j.status = DownloadStatus.failed;
        }
        await file.writeAsString(YoutubeImporter.encodeQueue(jobs));
        await c.youtube.restoreQueue();
        final running = {for (final j in c.youtube.jobs) j.videoId: j};
        void set(int i, void Function(DownloadJob) f) => f(running['Riflay00${i}xx']!);
        set(1, (j) {
          j
            ..status = DownloadStatus.downloading
            ..quality = 'Video · MP4 · 1080p'
            ..totalBytes = 96 * 1024 * 1024
            ..receivedBytes = 41 * 1024 * 1024
            ..progress = 41 / 96
            ..bytesPerSecond = 5.8 * 1024 * 1024;
        });
        set(2, (j) {
          j
            ..status = DownloadStatus.downloading
            ..quality = 'Opus · 160 kbps'
            ..totalBytes = 4400 * 1024
            ..receivedBytes = 3100 * 1024
            ..progress = 3100 / 4400
            ..bytesPerSecond = 1.4 * 1024 * 1024;
        });
        set(3, (j) {
          j
            ..status = DownloadStatus.done
            ..quality = 'Video · WebM · 1440p'
            ..totalBytes = 71 * 1024 * 1024
            ..track = song('Chrome Lullaby');
        });
        set(4, (j) {
          j
            ..status = DownloadStatus.downloading
            ..quality = 'FLAC · 16-bit / 44.1 kHz'
            ..phase = DownloadPhase.converting;
        });
        set(5, (j) => j.status = DownloadStatus.queued);
        // ignore: invalid_use_of_protected_member
        c.youtube.notifyListeners();
        // Downloads sits in the title bar's ⋯ menu.
        await openMore('Downloads');
        await settle(1500);
        await shot('downloads');
      });

      // The "Download as" dialog, with the sizes of each choice.
      await step('download-as', () async {
        VideoCandidate v(String id, int h, VideoCodec codec, int mb, {bool webm = false, int fps = 30}) =>
            VideoCandidate(id: id, height: h, codec: codec, fps: fps, sizeBytes: mb * 1024 * 1024, webm: webm);
        final formats = VideoFormats(
          [
            v('137', 1080, VideoCodec.avc, 62),
            v('136', 720, VideoCodec.avc, 31),
            v('135', 480, VideoCodec.avc, 17),
            v('134', 360, VideoCodec.avc, 10),
            v('272', 2160, VideoCodec.vp9, 190, webm: true),
            v('271', 1440, VideoCodec.vp9, 96, webm: true),
            v('248', 1080, VideoCodec.vp9, 46, webm: true),
            v('247', 720, VideoCodec.vp9, 23, webm: true),
            v('244', 480, VideoCodec.vp9, 12, webm: true),
          ],
          [
            const AudioCandidate(id: '140', opus: false, kbps: 128, sizeBytes: 3600 * 1024),
            const AudioCandidate(id: '251', opus: true, kbps: 160, sizeBytes: 4400 * 1024),
          ],
        );
        showDialog<DownloadChoice>(
          context: tester.element(find.byType(Scaffold).first),
          useRootNavigator: true,
          builder: (_) => DownloadOptionsDialog(
            initial: DownloadChoice.video(VideoContainer.mp4, height: 1080),
            candidates: Future.value(formats.audios),
            video: Future.value(formats),
            canRemux: true,
            canMakeMp3: true,
            canMakeFlac: true,
            canReencode: true,
          ),
        ).ignore();
        await settle(1500);
        await shot('download-as');
        await tester.tap(find.text('Cancel'));
        await settle();
      });

      // Settings › About, and the themes under Look & feel › Appearance.
      await step('about-appearance', () async {
        await openMore('Settings');
        await Scrollable.ensureVisible(tester.element(find.text('About')), alignment: 0.5);
        await settle();
        debugSystem = 'Linux 6.12.1';
        await tester.tap(find.text('About'));
        await settle();
        await shot('settings-about');
        await tester.tap(find.text('Settings').first);
        await settle();
        await tester.tap(find.text('Look & feel'));
        await settle();
        await tester.tap(find.text('Appearance'));
        await settle();
        await shot('appearance');
      });

      // Spotify import, signed out (the picture shows no account).
      await step('spotify', () async {
        await openMore('Settings');
        // Still on a Settings page from the last picture: its trail leads back to the list.
        if (find.text('Accounts & services').evaluate().isEmpty) {
          await tester.tap(find.text('Settings').first);
          await settle();
        }
        await tester.tap(find.text('Accounts & services'));
        await settle();
        await tester.tap(find.text('Spotify').first);
        await settle(1500);
        await shot('spotify');
      });

      // Listen together: hosting on this Wi-Fi.
      await step('listen-together', () async {
        await openMore('Listen together');
        await settle(1500);
        final session = ListenTogether.of(c);
        await tester.runAsync(() => session.host(mode: ListenMode.wifi, name: 'Ana'));
        await settle(2000);
        await shot('listen-together');
        await tester.runAsync(session.leave);
        await settle();
      });

      // Signal path of the hi-res file.
      await step('signal-path', () async {
        await tester.tap(find.byTooltip('Home'));
        await settle();
        await c.playList([studio], 0, from: 'Hi-Res Test');
        await playing();
        await until(() => find.textContaining('FLAC').evaluate().isNotEmpty);
        showSignalPath(tester.element(find.byType(QualityBadge).first)).ignore();
        await until(() => find.text('Decoded').evaluate().isNotEmpty);
        await shot('signal-path');
        await tester.tapAt(const Offset(700, 150));
        await settle();
      });

      // The Dynamic theme on a cover.
      await step('dynamic-theme', () async {
        await c.playList(c.library.where((t) => t.album == 'Neon Index').toList(), 1, from: 'Neon Index');
        await playing();
        await Appearance.instance.setTheme(ThemeChoice.dynamic);
        await settle(3000);
        await shot('dynamic-theme');
        await Appearance.instance.setTheme(ThemeChoice.standard);
        await settle();
      });

      // Desktop full-screen player.
      await step('fullscreen', () async {
        await c.playList(c.library.where((t) => t.album == 'Open Meridian').toList(), 0, from: 'Open Meridian');
        await playing();
        await tester.tap(find.byTooltip('More options'));
        await settle();
        await tester.tap(find.text('Full screen'));
        await settle(4000); // past the "Press Esc" hint
        await shot('fullscreen');
        await tester.tap(find.byTooltip('Exit full screen').first);
        await settle();
      });

      // A tablet-sized window: the library folds into a rail of covers.
      await step('tablet', () async {
        tester.view.physicalSize = const Size(1024, 768);
        await tester.tap(find.byTooltip('Home').first);
        await settle(1500);
        await shot('tablet');
        tester.view.physicalSize = const Size(1440, 900);
        await settle();
      });

      // Phone: home, its Library and Settings tabs, then the full-screen player.
      await step('phone', () async {
        tester.view.devicePixelRatio = 2;
        tester.view.physicalSize = const Size(800, 1720);
        await c.playList(c.library.where((t) => t.album == 'Small Hours').toList(), 0, from: 'Small Hours');
        await playing();
        await settle(1500);
        // The tab bar's tabs are icons, named by their tooltips; Home is the round button in the middle.
        await tester.tap(find.byTooltip('Home').last);
        await settle(1500);
        await shot('phone-home', pixelRatio: 2);
        await tester.tap(find.byTooltip('Library').last);
        await settle(1500);
        await shot('phone-library', pixelRatio: 2);
        await tester.tap(find.byTooltip('Settings').last);
        await settle(1500);
        await shot('phone-settings', pixelRatio: 2);
        await tester.tap(find.byTooltip('Home').last);
        await settle(1500);
        await tester.tap(find.byType(MiniPlayer));
        await shot('phone', pixelRatio: 2);
      });
    } finally {
      debugPrint('SHOTS FAILED: $failed');
      JustAudioMediaKit.onPlayerCreated = apply;
      await c.player.stop();
      await server.close(force: true);
      dir.deleteSync(recursive: true);
    }
  }

  testWidgets('README screenshots', (tester) async {
    if (shots.isEmpty) return;
    // Lookups that need the internet fail with errors nobody awaits; in a zone of their own they don't fail the test.
    final done = Completer<void>();
    runZonedGuarded(
      () => run(tester).then(done.complete, onError: done.completeError),
      (e, s) => debugPrint('Ignored (offline): $e'),
    );
    await done.future;
  }, timeout: const Timeout(Duration(minutes: 20)));
}
