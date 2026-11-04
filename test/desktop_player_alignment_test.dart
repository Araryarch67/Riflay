import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:riflay/main.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/player/desktop_player_bar.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/controls.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SongPlayer extends PlayerController {
  final song = Track(
    id: 'alignment',
    uri: Uri.parse('file:///alignment.mp3'),
    title: 'A long song title that must fit the available player space',
    artist: 'Artist with a long name',
  );
  @override
  Track get currentTrack => song;
  @override
  Duration get duration => const Duration(minutes: 2, seconds: 30);
  @override
  Stream<Duration> smoothPosition() => Stream.value(const Duration(minutes: 1, seconds: 4));
}

class _MenuPlayer extends _SongPlayer {
  bool _shuffle = false;
  LoopMode _loop = LoopMode.off;
  @override
  bool get hasQueue => true;
  @override
  bool get shuffle => _shuffle;
  @override
  LoopMode get loopMode => _loop;
  @override
  Future<void> toggleShuffle() async {
    _shuffle = !_shuffle;
    notifyListeners();
  }

  @override
  Future<void> cycleLoopMode() async {
    _loop = _loop == LoopMode.off ? LoopMode.all : LoopMode.off;
    notifyListeners();
  }
}

void main() {
  for (final style in DesktopBarStyle.values) {
    testWidgets('${style.name} sits along the window\'s foot, under the page, never over it', (tester) async {
      SharedPreferences.setMockInitialValues({'discord.enabled': false});
      await LayoutPrefs.instance.reset();
      await LayoutPrefs.instance.setDesktopBar(style);
      final c = _SongPlayer();
      await tester.runAsync(c.load);
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(RiflayApp(controller: c));
      await tester.pump(const Duration(milliseconds: 500));
      final scaffoldFinder = find.ancestor(of: find.byType(DesktopPlayerBar), matching: find.byType(Scaffold)).first;
      final scaffold = tester.widget<Scaffold>(scaffoldFinder);
      final page = tester.getRect(find.byWidget(scaffold.body!));
      final window = tester.getRect(scaffoldFinder);
      final bar = tester.getRect(find.byType(DesktopPlayerBar));
      expect(page.bottom, lessThanOrEqualTo(bar.top + 0.1), reason: 'the page ends where the bar starts');
      expect(bar.bottom, closeTo(window.bottom, 0.1));
      expect(bar.width, closeTo(window.width, 0.1), reason: 'full width, not a dock');
      expect(find.byKey(const ValueKey('desktop-player-dock')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async => c.dispose());
      await LayoutPrefs.instance.reset();
    });
  }

  test('saved floating looks come back as the flush ones nearest them', () {
    LayoutPrefs.instance.restore({'desktopBar': 'floating'});
    expect(LayoutPrefs.instance.desktopBar, DesktopBarStyle.classic);
    LayoutPrefs.instance.restore({'desktopBar': 'capsule'});
    expect(LayoutPrefs.instance.desktopBar, DesktopBarStyle.compact);
    LayoutPrefs.instance.restore(const {});
  });

  testWidgets('library creation and import actions share the Add menu', (tester) async {
    SharedPreferences.setMockInitialValues({'discord.enabled': false});
    await LayoutPrefs.instance.reset();
    final c = _SongPlayer();
    await tester.runAsync(c.load);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RiflayApp(controller: c));
    await tester.pump(const Duration(milliseconds: 500));
    for (final label in ['New playlist', 'Import a playlist', 'Spotify library']) {
      expect(find.text(label), findsNothing, reason: 'one-off actions leave space for the library');
    }
    await tester.tap(find.byTooltip('Add').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    for (final label in ['New playlist', 'Import a playlist', 'Spotify library', 'Add songs']) {
      expect(
        find.descendant(of: find.byWidgetPredicate((widget) => widget is PopupMenuItem), matching: find.text(label)),
        findsOneWidget,
      );
    }
    await tester.tapAt(const Offset(600, 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async => c.dispose());
  });

  testWidgets('desktop keeps shuffle and repeat visible and volume available in narrow windows', (tester) async {
    SharedPreferences.setMockInitialValues({'discord.enabled': false});
    await LayoutPrefs.instance.reset();
    final c = _MenuPlayer();
    await tester.runAsync(c.load);
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RiflayApp(controller: c));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.descendant(of: find.byType(DesktopPlayerBar), matching: find.byType(ModeButton)), findsNWidgets(2));
    await tester.tap(find.byTooltip('Enable shuffle'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.shuffle, isTrue);
    expect(find.byTooltip('Disable shuffle'), findsOneWidget);
    await tester.tap(find.byTooltip('Enable repeat'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.loopMode, LoopMode.all);
    expect(find.byTooltip('Enable repeat one'), findsOneWidget);
    await tester.tap(find.byTooltip('More options'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Lyrics'), findsOneWidget);
    await tester.tapAt(const Offset(400, 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Volume'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(VolumeSlider), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async => c.dispose());
  });

  for (final style in DesktopBarStyle.values) {
    for (final width in [700.0, 1024.0, 1920.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('${style.name} at $width and text scale $scale keeps metadata and time aligned', (tester) async {
          SharedPreferences.setMockInitialValues({'discord.enabled': false});
          await LayoutPrefs.instance.reset();
          await LayoutPrefs.instance.setDesktopBar(style);
          final c = _SongPlayer();
          await tester.runAsync(c.load);
          tester.view.physicalSize = Size(width, 400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            PlayerScope(
              controller: c,
              child: MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: ShellScope(
                  compact: false,
                  width: width,
                  open: (_, {location}) {},
                  openCollection: (_) {},
                  openQueue: () {},
                  openNowPlaying: () {},
                  openLyrics: () {},
                  openDownloads: () {},
                  importFromYoutube: () {},
                  addFiles: () {},
                  addFolder: null,
                  child: const Scaffold(
                    body: Align(
                      alignment: Alignment.bottomCenter,
                      child: DesktopPlayerBar(sidePanelOpen: false, onToggleSidePanel: null),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
          if (style == DesktopBarStyle.compact) {
            final title = tester.getTopLeft(find.text(c.song.title).first).dx;
            final artist = tester.getTopLeft(find.text(c.song.artist).first).dx;
            final elapsed = tester.getTopLeft(find.text('1:04')).dx;
            final artwork = tester.getRect(find.byType(Artwork).first);
            expect(artist, closeTo(title, 0.1));
            expect(elapsed, closeTo(title, 0.1));
            expect(artwork.right, lessThan(title));
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async => c.dispose());
          await LayoutPrefs.instance.reset();
        });
      }
    }
  }
}
