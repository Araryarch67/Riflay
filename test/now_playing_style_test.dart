import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/ui/widgets/app_dialog.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/lyrics.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/player_presets.dart';
import 'package:riflay/services/video_mode.dart';
import 'package:riflay/services/ytmusic_web.dart';
import 'package:riflay/services/youtube_music_account.dart';
import 'package:riflay/ui/pages/lyrics_page.dart';
import 'package:riflay/ui/pages/player_presets_page.dart';
import 'package:riflay/ui/player/mini_player.dart';
import 'package:riflay/ui/player/now_playing_page.dart';
import 'package:riflay/ui/player/player_parts.dart';
import 'package:riflay/ui/player/player_glass.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/controls.dart';
import 'package:riflay/ui/widgets/faded_cover.dart';
import 'package:riflay/ui/widgets/signal_path.dart';
import 'package:riflay/ui/widgets/wavy_seek_track.dart' show PillSeekTrack;
import 'package:riflay/ui/widgets/stats_for_nerds.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _track = Track(id: 'style-test', uri: Uri.parse('file:///style-test.mp3'), title: 'Style test', artist: 'Artist');

class _Player extends PlayerController {
  _Player([Track? track]) : track = track ?? _track;
  final Track track;
  bool playing = false;
  int toggles = 0;

  @override
  Track get currentTrack => track;
  @override
  bool get canPlay => true;
  @override
  bool get showsPlaying => playing;
  @override
  Duration? get duration => const Duration(minutes: 3);
  @override
  Future<void> togglePlay() async {
    toggles++;
    playing = !playing;
    notifyListeners();
  }
}

class _LikeAccount extends YoutubeMusicAccount {
  bool connected = false, liked = false;

  @override
  bool get canEdit => connected;
  @override
  bool isLiked(Track track) => liked;
  @override
  Future<void> setLiked(Track track, bool value) async {
    liked = value;
    notifyListeners();
  }

  void connect(bool value) {
    connected = value;
    notifyListeners();
  }
}

class _LikePlayer extends _Player {
  final account = _LikeAccount();
  @override
  YoutubeMusicAccount get ytMusic => account;
}

Finder _tip(String start) => find.byWidgetPredicate((w) => w is Tooltip && (w.message ?? '').startsWith(start));

Widget _tree(_Player c, Size size, Widget page) => PlayerScope(
  controller: c,
  child: MaterialApp(
    home: ShellScope(
      compact: true,
      width: size.width,
      open: (_, {location}) {},
      openCollection: (_) {},
      openQueue: () {},
      openNowPlaying: () {},
      openLyrics: () {},
      openDownloads: () {},
      importFromYoutube: ({url}) {},
      addFiles: () {},
      addFolder: null,
      child: page,
    ),
  ),
);

Future<_Player> _show(WidgetTester tester, Widget page, Size size, {Track? track}) async {
  SharedPreferences.setMockInitialValues({'library.v1': jsonEncode(<Object>[])});
  final c = _Player(track);
  await tester.runAsync(c.load);
  // Kawaii's Music video background starts the video machinery (timers, a decoder): not what these tests are about.
  await tester.runAsync(() => Appearance.instance.setNowPlaying(NowPlayingBackground.color));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_tree(c, size, page));
  await tester.pump(const Duration(milliseconds: 100));
  return c;
}

Future<void> _close(WidgetTester tester, _Player c) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() async => c.dispose());
}

void main() {
  final p = LayoutPrefs.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await p.reset();
    await Appearance.instance.setNowPlaying(NowPlayingBackground.color);
  });
  tearDown(() async {
    await p.reset();
    await Appearance.instance.setNowPlaying(NowPlayingBackground.color);
  });

  test('every player setting starts as Classic, persists and resets', () async {
    expect(p.classicPlayerFace, isTrue);
    expect(p.isCustomised, isFalse);
    await p.setPlayerCover(PlayerCover.background);
    await p.setPlayerHeader(PlayerHeader.playingFrom);
    await p.setTitleActions(TitleActions.plain);
    await p.setShowTimeLeft(true);
    await p.setTransport(PlayerTransport.pill);
    await p.setShowVolumeRow(false);
    await p.setBottomRow(PlayerBottomRow.minimal);
    await p.setLyricsLayout(LyricsLayout.topHeader);
    await p.setMiniPlayer(MiniPlayerStyle.capsule);
    await p.setAlbumHeader(AlbumHeaderStyle.hero);
    await p.setProgressShape(ProgressBarShape.pill);
    expect(p.isCustomised, isTrue);
    p.restore(const {});
    expect(p.playerCover, PlayerCover.flower);
    await p.load();
    expect(p.playerCover, PlayerCover.background);
    expect(p.playerHeader, PlayerHeader.playingFrom);
    expect(p.titleActions, TitleActions.plain);
    expect(p.showTimeLeft, isTrue);
    expect(p.transport, PlayerTransport.pill);
    expect(p.showVolumeRow, isFalse);
    expect(p.bottomRow, PlayerBottomRow.minimal);
    expect(p.lyricsLayout, LyricsLayout.topHeader);
    expect(p.miniPlayer, MiniPlayerStyle.capsule);
    expect(p.albumHeader, AlbumHeaderStyle.hero);
    expect(p.progressShape, ProgressBarShape.pill);
    p.restore({'playerCover': 'from-the-future', 'bottomRow': 'chips'});
    expect(p.playerCover, PlayerCover.flower);
    expect(p.bottomRow, PlayerBottomRow.chips);
    await p.reset();
    expect(p.classicPlayerFace, isTrue);
    expect(p.isCustomised, isFalse);
    expect(p.showVolumeRow, isTrue);
    expect(p.lyricsLayout, LyricsLayout.classic);
  });

  test('a preset writes each setting, and "matches" follows the settings, not a stored name', () async {
    expect(playerPresetName(), 'Classic');
    expect(PlayerPreset.stacked.changesTo(p), greaterThan(0));
    await PlayerPreset.stacked.apply(p);
    expect(p.playerCover, PlayerCover.background);
    expect(p.playerHeader, PlayerHeader.centered);
    expect(p.titleActions, TitleActions.boxed);
    expect(p.progressShape, ProgressBarShape.pill);
    expect(p.progressBar, ProgressBarStyle.thick);
    expect(p.transport, PlayerTransport.pill);
    expect(p.bottomRow, PlayerBottomRow.chips);
    expect(p.lyricsLayout, LyricsLayout.bottomCard);
    expect(p.miniPlayer, MiniPlayerStyle.classic);
    expect(p.albumHeader, AlbumHeaderStyle.classic);
    expect(p.showVolumeRow, isTrue);
    expect(p.volumeSlider, VolumeSliderShape.pill);
    expect(playerPresetName(), 'Stacked');
    await p.load();
    expect(playerPresetName(), 'Stacked', reason: 'saved as individual settings');

    await p.setTransport(PlayerTransport.plain);
    expect(playerPresetName(), isNull, reason: 'one part changed by hand: a custom mix');

    await PlayerPreset.kawaii.apply(p);
    expect(p.playerCover, PlayerCover.background);
    expect(p.playerHeader, PlayerHeader.playingFrom);
    expect(p.titleActions, TitleActions.plain);
    expect(p.progressShape, ProgressBarShape.wavy);
    expect(p.showVolumeRow, isFalse);
    expect(p.playingRow, PlayingRowStyle.card);
    expect(p.progressBar, ProgressBarStyle.thin);
    expect(p.showTimeLeft, isTrue);
    expect(p.transport, PlayerTransport.plain);
    expect(p.bottomRow, PlayerBottomRow.minimal);
    expect(p.lyricsLayout, LyricsLayout.topHeader);
    expect(p.miniPlayer, MiniPlayerStyle.capsule);
    expect(p.albumHeader, AlbumHeaderStyle.hero);
    expect(Appearance.instance.nowPlaying, NowPlayingBackground.video);
    expect(playerPresetName(), 'Kawaii');
    expect(PlayerPreset.kawaii.changesTo(p), 0);

    await PlayerPreset.classic.apply(p);
    expect(p.classicPlayerFace, isTrue);
    expect(p.isCustomised, isFalse);
    expect(p.visualizer, isTrue);
    expect(p.visualizerStyle, VisualizerStyle.pulse);
  });

  test('old saved cover shapes migrate to Square, Flower or Background', () {
    p.restore({'playerCover': 'fullBleed'});
    expect(p.playerCover, PlayerCover.background);
    p.restore({'playerCover': 'card'});
    expect(p.playerCover, PlayerCover.flower, reason: 'a card was the flower unless the shape setting said square');
    p.restore({'playerCover': 'card', 'visualizerCoverShape': 'square'});
    expect(p.playerCover, PlayerCover.square);
    p.restore({'visualizerCoverShape': 'square'});
    expect(p.playerCover, PlayerCover.square);
    p.restore(const {});
    expect(p.playerCover, PlayerCover.flower);
    expect(p.visualizerCoverShape, VisualizerCoverShape.flower);
  });

  testWidgets('Kawaii: no volume row, the speaker opens a volume popup in the Slider look, icons only', (tester) async {
    await tester.runAsync(() => PlayerPreset.kawaii.apply(p));
    final c = await _show(tester, const NowPlayingPage(), const Size(412, 915));
    expect(find.byType(FadedCover), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget, reason: 'only the progress bar: no volume row');
    expect(_tip('Volume'), findsOneWidget);
    expect(_tip('Lyrics'), findsOneWidget);
    expect(find.text('Speaker'), findsNothing, reason: 'no caption while the sound plays here');
    expect(find.text('Listen together'), findsNothing, reason: 'no text on the buttons');
    await tester.tap(_tip('Volume'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNWidgets(2), reason: 'the popup has the volume slider');
    final popup = tester.element(find.byType(Slider).last);
    expect(SliderTheme.of(popup).trackShape, isA<PillSeekTrack>(), reason: 'Kawaii\'s Slider look is the pill');
    expect(find.byIcon(Icons.volume_mute_rounded), findsOneWidget, reason: 'mute, at the slider\'s low end');
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(200, 100));
    await tester.pumpAndSettle();
    await _close(tester, c);
  });

  testWidgets('Share is one tap away on every preset: a visible button, or in the More sheet', (tester) async {
    for (final preset in PlayerPreset.all) {
      await tester.runAsync(() => preset.apply(p));
      final c = await _show(tester, const NowPlayingPage(), const Size(412, 915));
      if (find.byTooltip('Share').evaluate().isEmpty) {
        await tester.tap(_tip('More'));
        await tester.pumpAndSettle();
        expect(find.text('Share'), findsOneWidget, reason: '${preset.name}: Share in the More sheet');
        Navigator.of(tester.element(find.text('Share'))).pop();
        await tester.pumpAndSettle();
      }
      await _close(tester, c);
    }
  });

  testWidgets('Detail stats open from the cover on every preset, the cover-as-page ones too', (tester) async {
    for (final preset in PlayerPreset.all) {
      await tester.runAsync(() => preset.apply(p));
      final c = await _show(tester, const NowPlayingPage(), const Size(412, 915));
      expect(find.byType(NowPlayingCover), findsOneWidget, reason: preset.name);
      unawaited(showDetailStats(tester.element(find.byType(NowPlayingCover))));
      await tester.pumpAndSettle();
      expect(find.text('Detail stats'), findsOneWidget, reason: '${preset.name}: the sheet is up');
      expect(tester.takeException(), isNull, reason: preset.name);
      Navigator.of(tester.element(find.text('Detail stats'))).pop();
      await tester.pumpAndSettle();
      await _close(tester, c);
    }
  });

  testWidgets('the Song / Video switch shows for a song with a video, fades, and comes back on a touch above', (
    tester,
  ) async {
    final song = Track.youtube(videoId: 'switch-test', title: 'Style test', artist: 'Artist');
    VideoMode.instance.debugSetFound('switch-test', const MusicVideo(videoId: 'switch-test'));
    addTearDown(() => VideoMode.instance.debugSetFound('switch-test', null));
    // Song picked: the switch still shows, and no video player starts (no media_kit in widget tests).
    VideoMode.instance.setOn(false);
    addTearDown(() => VideoMode.instance.setOn(true));
    final c = await _show(tester, const NowPlayingPage(), const Size(412, 915), track: song);
    double shown() => tester
        .widget<AnimatedOpacity>(find.ancestor(of: find.text('Video'), matching: find.byType(AnimatedOpacity)).first)
        .opacity;
    expect(find.text('Video'), findsOneWidget, reason: 'at the top, no ⋯ needed');
    expect(shown(), 1);
    await tester.pump(const Duration(seconds: 4));
    expect(shown(), 0, reason: 'out of the way of the cover');
    await tester.tapAt(const Offset(206, 300));
    await tester.pump();
    expect(shown(), 1, reason: 'a touch on the cover brings it back');
    await tester.pump(const Duration(seconds: 4));
    await tester.tapAt(const Offset(206, 860));
    await tester.pump();
    expect(shown(), 0, reason: 'the buttons below leave it hidden');
    await _close(tester, c);
    await tester.runAsync(() => p.setShowVideoSwitch(false));
    final off = await _show(tester, const NowPlayingPage(), const Size(412, 915), track: song);
    expect(find.text('Video'), findsNothing, reason: 'Off in Settings');
    await _close(tester, off);
    // VideoMode lets go of its views a moment after they close.
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('Kawaii puts the quality badge in the time row, between the two times', (tester) async {
    await tester.runAsync(() => PlayerPreset.kawaii.apply(p));
    expect(p.qualityBadgePlace, QualityBadgePlace.timeRow);
    final c = await _show(tester, const NowPlayingPage(), const Size(412, 915));
    final badge = tester.getCenter(find.byType(QualityBadge));
    final seek = tester.getRect(find.byType(SeekBar));
    expect(badge.dx, closeTo(seek.center.dx, 16));
    expect(badge.dy, greaterThan(tester.getCenter(find.byType(Slider)).dy), reason: 'under the bar, on the time row');
    await _close(tester, c);
    await PlayerPreset.classic.apply(p);
    expect(p.qualityBadgePlace, QualityBadgePlace.underArtist);
  });

  testWidgets('the quality badge is on every preset until its own switch hides it', (tester) async {
    for (final preset in PlayerPreset.all) {
      await tester.runAsync(() => preset.apply(p));
      var c = await _show(tester, const NowPlayingPage(), const Size(412, 915));
      expect(find.byType(QualityBadge), findsOneWidget, reason: preset.name);
      await _close(tester, c);
    }
    await p.setShowQualityBadge(false);
    final c = await _show(tester, const NowPlayingPage(), const Size(412, 915));
    expect(find.byType(QualityBadge), findsNothing);
    await _close(tester, c);
  });

  testWidgets('Kawaii lyrics: one header row, with the lyrics options in its More menu', (tester) async {
    await tester.runAsync(() => PlayerPreset.kawaii.apply(p));
    final c = await _show(tester, const LyricsPage(fullScreen: true), const Size(412, 915));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(LyricsTopHeader), findsOneWidget);
    expect(find.byType(LyricsExtrasButtons), findsNothing, reason: 'no second row');
    expect(_tip('More'), findsOneWidget);
    expect(_tip('Close'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _close(tester, c);
  });

  testWidgets('the Share pair hides Like while signed out and follows login, like and logout', (tester) async {
    final c = _LikePlayer();
    final track = Track.youtube(videoId: 'liked-test', title: 'Test', artist: 'Artist');
    await tester.pumpWidget(_tree(c, const Size(412, 915), Scaffold(body: SharePair(track: track))));
    expect(find.byTooltip('Share'), findsOneWidget);
    expect(find.byTooltip('Add to Liked music'), findsNothing);

    c.account.connect(true);
    await tester.pump();
    expect(find.byTooltip('Add to Liked music'), findsOneWidget);
    await tester.tap(find.byTooltip('Add to Liked music'));
    await tester.pumpAndSettle();
    expect(c.account.liked, isTrue);
    expect(find.byTooltip('Remove from Liked music'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove from Liked music'));
    await tester.pumpAndSettle();
    expect(c.account.liked, isFalse);

    c.account.connect(false);
    await tester.pump();
    expect(find.byTooltip('Add to Liked music'), findsNothing);
    expect(find.byTooltip('Share'), findsOneWidget);
    await _close(tester, c);
  });

  testWidgets('Stacked: a joined Share pair, a joined bottom group and a round More', (tester) async {
    await tester.runAsync(() => PlayerPreset.stacked.apply(p));
    final c = await _show(tester, const NowPlayingPage(), const Size(412, 915));
    expect(find.byType(JoinedButtons), findsNWidgets(2));
    expect(tester.widgetList<JoinedButtons>(find.byType(JoinedButtons)).where((j) => j.outlined), hasLength(1));
    expect(_tip('More'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _close(tester, c);
  });

  testWidgets('the presets page asks first, then applies', (tester) async {
    await _show(tester, const PlayerPresetsPage(), const Size(412, 915));
    expect(find.text('Your settings match Classic'), findsOneWidget);
    await tester.tap(find.text('Stacked'));
    await tester.pumpAndSettle();
    expect(find.textContaining('This changes'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(p.classicPlayerFace, isTrue);
    await tester.tap(find.text('Stacked'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(p.transport, PlayerTransport.pill);
    expect(find.text('Your settings match Stacked'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the presets page can select the normal and Liquid variants separately', (tester) async {
    final c = await _show(tester, const PlayerPresetsPage(), const Size(412, 915));
    await tester.runAsync(() => PlayerPreset.liquidKawaii.apply(p));
    await tester.pumpAndSettle();
    expect(find.text('Your settings match Liquid Kawaii'), findsOneWidget);

    for (final preset in [
      PlayerPreset.kawaii,
      PlayerPreset.liquidKawaii,
      PlayerPreset.stacked,
      PlayerPreset.liquidStacked,
    ]) {
      await tester.scrollUntilVisible(find.text(preset.name), 180, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text(preset.name));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsOneWidget, reason: 'the other preset must be selectable');
      await tester.tap(find.text('Apply'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(p.tabBar, preset.tabBar);
      expect(p.playerGlassControls, preset.glassControls);
      tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text('Your settings match ${preset.name}'), findsOneWidget);
    }
    await _close(tester, c);
  });

  for (final preset in [PlayerPreset.liquidStacked, PlayerPreset.liquidKawaii]) {
    testWidgets('${preset.name} gives transparent player controls liquid surfaces and keeps playback usable', (
      tester,
    ) async {
      await tester.runAsync(() => preset.apply(p));
      final c = await _show(tester, const NowPlayingPage(), const Size(360, 640));
      expect(find.byType(PlayerGlassLayer), findsOneWidget);
      expect(find.byType(LiquidGlass), findsWidgets);
      expect(find.ancestor(of: _tip('Close').first, matching: find.byType(LiquidGlass)), findsWidgets);
      // The seek bar, Play and volume stay solid; Liquid Stacked's previous and next are glass, Kawaii's solid.
      expect(find.ancestor(of: find.byType(SeekBar).first, matching: find.byType(LiquidGlass)), findsNothing);
      expect(find.ancestor(of: _tip('Play').first, matching: find.byType(LiquidGlass)), findsNothing);
      for (final tip in ['Previous', 'Next']) {
        expect(
          find.ancestor(of: _tip(tip).first, matching: find.byType(LiquidGlass)),
          preset == PlayerPreset.liquidStacked ? findsWidgets : findsNothing,
          reason: tip,
        );
      }
      expect(find.descendant(of: find.byType(PlayerVolumeRow), matching: find.byType(LiquidGlass)), findsNothing);
      if (preset == PlayerPreset.liquidKawaii) {
        expect(find.ancestor(of: _tip('Volume').first, matching: find.byType(LiquidGlass)), findsNothing);
      }
      await tester.tap(_tip('Play').first);
      await tester.pump();
      expect(c.toggles, 1);
      expect(tester.takeException(), isNull);
      await _close(tester, c);
    });
  }

  for (final preset in [PlayerPreset.liquidStacked, PlayerPreset.liquidKawaii]) {
    testWidgets('${preset.name} frosts the seek bar, transport and volume when their switches are on', (tester) async {
      await tester.runAsync(() => preset.apply(p));
      await tester.runAsync(() async {
        await p.setGlassSeekBar(true);
        await p.setGlassTransport(true);
        await p.setGlassVolume(true);
      });
      final c = await _show(tester, const NowPlayingPage(), const Size(360, 640));
      expect(find.ancestor(of: find.byType(SeekBar).first, matching: find.byType(LiquidGlass)), findsWidgets);
      for (final tip in ['Previous', 'Next']) {
        expect(
          find.ancestor(of: _tip(tip).first, matching: find.byType(LiquidGlass)),
          findsWidgets,
          reason: tip,
        );
      }
      if (preset == PlayerPreset.liquidKawaii) {
        expect(find.ancestor(of: _tip('Play').first, matching: find.byType(LiquidGlass)), findsWidgets);
      }
      // Kawaii has no volume row: its volume is the speaker pill in the bottom row.
      expect(
        preset == PlayerPreset.liquidKawaii
            ? find.ancestor(of: _tip('Volume').first, matching: find.byType(LiquidGlass))
            : find.descendant(of: find.byType(PlayerVolumeRow), matching: find.byType(LiquidGlass)),
        findsWidgets,
      );
      await tester.runAsync(() async {
        await p.setGlassSeekBar(false);
        await p.setGlassTransport(false);
        await p.setGlassVolume(false);
      });
      await _close(tester, c);
    });
  }

  testWidgets('Liquid Kawaii: shuffle, repeat and Close are glass circles, not squircles', (tester) async {
    await tester.runAsync(() => PlayerPreset.liquidKawaii.apply(p));
    final c = await _show(tester, const NowPlayingPage(), const Size(360, 640));
    for (final tip in ['Enable shuffle', 'Enable repeat', 'Close']) {
      final glass = find.ancestor(of: _tip(tip).first, matching: find.byType(LiquidGlass)).first;
      expect(tester.widget<LiquidGlass>(glass).shape, isA<LiquidOval>(), reason: tip);
      final size = tester.getSize(glass);
      expect(size.width, size.height, reason: '$tip: an oval on a square is a circle');
    }
    await _close(tester, c);
  });

  testWidgets('Liquid Stacked: glass previous and next on their own, a solid Play pill', (tester) async {
    await tester.runAsync(() => p.setGlassTransport(false));
    await tester.runAsync(() => PlayerPreset.liquidStacked.apply(p));
    expect(p.glassTransport, isTrue);
    final c = await _show(tester, const NowPlayingPage(), const Size(360, 640));
    for (final tip in ['Previous', 'Next']) {
      expect(
        find.ancestor(of: _tip(tip).first, matching: find.byType(LiquidGlass)),
        findsWidgets,
        reason: tip,
      );
    }
    expect(find.ancestor(of: _tip('Play').first, matching: find.byType(LiquidGlass)), findsNothing);
    await tester.runAsync(() => p.setGlassTransport(false));
    await _close(tester, c);
  });

  testWidgets('normal Stacked and Kawaii keep their original player surfaces', (tester) async {
    for (final preset in [PlayerPreset.stacked, PlayerPreset.kawaii]) {
      await tester.runAsync(() => preset.apply(p));
      final c = await _show(tester, const NowPlayingPage(), const Size(360, 640));
      expect(find.byType(LiquidGlass), findsNothing);
      await _close(tester, c);
    }
  });

  testWidgets('Lightweight keeps Liquid player controls usable without rendering glass', (tester) async {
    await tester.runAsync(() => PlayerPreset.liquidStacked.apply(p));
    p.performance = PerformanceMode.lightweight;
    final c = await _show(tester, const NowPlayingPage(), const Size(360, 640));
    expect(find.byType(LiquidGlass), findsNothing);
    await tester.tap(_tip('Play').first);
    await tester.pump();
    expect(c.toggles, 1);
    expect(tester.takeException(), isNull);
    await _close(tester, c);
  });

  testWidgets('Stacked parts: header, share, pill Play, bottom chips with Lyrics, volume; Play toggles', (
    tester,
  ) async {
    await PlayerPreset.stacked.apply(p);
    final c = await _show(tester, const NowPlayingPage(), const Size(360, 640));
    expect(find.text('Now Playing'), findsOneWidget);
    // The test font is as wide as it is tall, so the title may scroll (two copies) beside the two buttons.
    expect(find.text('Style test'), findsWidgets);
    expect(_tip('Share'), findsOneWidget);
    expect(_tip('Add to Liked music'), findsNothing, reason: 'a file cannot be liked on YouTube Music');
    expect(find.text('Play'), findsOneWidget);
    for (final t in ['Queue', 'Sleep timer', 'Enable shuffle', 'Lyrics', 'Enable repeat', 'More', 'Previous', 'Next']) {
      expect(_tip(t), findsOneWidget, reason: t);
    }
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget, reason: 'Stacked has its volume row, as a pill');
    expect(find.byType(Slider), findsNWidgets(2), reason: 'the progress bar and the volume slider');
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(c.toggles, 1);
    expect(find.text('Pause'), findsOneWidget);
    await _close(tester, c);
  });

  testWidgets('time left counts down on the right of the progress bar', (tester) async {
    await p.setShowTimeLeft(true);
    final c = await _show(tester, const NowPlayingPage(), const Size(360, 640));
    expect(find.text('-3:00'), findsOneWidget);
    await _close(tester, c);
  });

  for (final row in PlayerBottomRow.values) {
    testWidgets('bottom row ${row.label} always has Lyrics', (tester) async {
      await p.setBottomRow(row);
      final c = await _show(tester, const NowPlayingPage(), const Size(360, 640));
      expect(_tip('Lyrics'), findsOneWidget);
      expect(_tip('Queue'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _close(tester, c);
    });
  }

  for (final size in const [Size(360, 640), Size(412, 915)]) {
    for (final preset in PlayerPreset.all) {
      testWidgets('${preset.name} fits ${size.width.toInt()}x${size.height.toInt()}: player, lyrics, mini player', (
        tester,
      ) async {
        final dir = Directory.systemTemp.createTempSync('riflay-style-test');
        UserLyrics.dirOverride = dir;
        addTearDown(() {
          UserLyrics.dirOverride = null;
          try {
            dir.deleteSync(recursive: true);
          } on FileSystemException {
            // Windows may still hold the file for a moment; it is a temp folder.
          }
        });
        await tester.runAsync(() => preset.apply(p));
        final track = _track;
        await tester.runAsync(() => UserLyrics.save(track, '[00:00.00]Some words\n[00:10.00]More words'));

        var c = await _show(tester, const NowPlayingPage(), size);
        expect(_tip('Lyrics'), findsOneWidget, reason: 'Now Playing');
        expect(_tip('Close'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'Now Playing');
        await _close(tester, c);

        c = await _show(tester, const LyricsPage(fullScreen: true), size);
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull, reason: 'Lyrics page');
        if (preset.lyrics != LyricsLayout.classic) expect(_tip('More'), findsOneWidget);
        if (preset.lyrics == LyricsLayout.bottomCard) {
          expect(_tip('Now Playing'), findsOneWidget, reason: 'expand button');
          expect(find.byType(SeekBar), findsOneWidget);
        }
        await _close(tester, c);

        c = await _show(
          tester,
          Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: MiniPlayer(onOpen: () {}),
            ),
          ),
          size,
        );
        expect(tester.takeException(), isNull, reason: 'Mini player');
        expect(_tip('Next'), findsOneWidget);
        expect(_tip('Previous'), preset.mini == MiniPlayerStyle.capsule ? findsOneWidget : findsNothing);
        await _close(tester, c);
      });
    }
  }

  for (final size in const [Size(360, 640), Size(412, 915)]) {
    testWidgets(
      'every mix of cover, top, title buttons, controls and bottom row fits ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        final c = await _show(tester, const SizedBox(), size);
        var n = 0;
        for (final cover in PlayerCover.values) {
          for (final header in PlayerHeader.values) {
            for (final actions in TitleActions.values) {
              for (final transport in PlayerTransport.values) {
                for (final bottom in PlayerBottomRow.values) {
                  p
                    ..playerCover = cover
                    ..playerHeader = header
                    ..titleActions = actions
                    ..transport = transport
                    ..bottomRow = bottom
                    ..showVolumeRow = n.isEven
                    ..qualityBadgePlace = n % 3 == 0 ? QualityBadgePlace.timeRow : QualityBadgePlace.underArtist;
                  await tester.pumpWidget(
                    _tree(c, size, KeyedSubtree(key: ValueKey(n++), child: const NowPlayingPage())),
                  );
                  await tester.pump();
                  final mix = '$cover $header $actions $transport $bottom';
                  expect(tester.takeException(), isNull, reason: mix);
                  expect(_tip('Lyrics'), findsOneWidget, reason: mix);
                  expect(_tip('More'), findsOneWidget, reason: '$mix: exactly one More');
                  expect(find.byType(QualityBadge), findsOneWidget, reason: '$mix: the quality badge stays');
                  if (actions == TitleActions.boxed) expect(_tip('Share'), findsOneWidget, reason: '$mix: Share');
                }
              }
            }
          }
        }
        await _close(tester, c);
      },
    );
  }
}
