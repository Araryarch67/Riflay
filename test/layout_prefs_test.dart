import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/ui/player/player_glass.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/player_presets.dart';
import 'package:riflay/ui/pages/layout_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final p = LayoutPrefs.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await p.reset();
  });

  test('optional tools are off by default and tint and track preferences reload independently', () async {
    expect(ExtraFeature.values.where((feature) => feature.enabled), isEmpty);
    await p.setExtraFeature(ExtraFeature.playlistSearch, true);
    await p.setMiniGlassTint(GlassTint.black);
    await p.setPlayerGlassTint(GlassTint.light);
    await p.toggleTrackPin('liked', 'a');
    await p.setLikedTrackOrder(['b', 'a']);
    p.restore(const {});
    expect(p.pinnedTracks, isEmpty);
    await p.load();
    expect(p.extraFeatures, {ExtraFeature.playlistSearch});
    expect(p.glassTint, GlassTint.theme);
    expect(p.miniGlassTint, GlassTint.black);
    expect(p.playerGlassTint, GlassTint.light);
    expect(p.pinnedTracks['liked'], {'a'});
    expect(p.likedTrackOrder, ['b', 'a']);
  });
  test('custom playlist order, pins, logo cover and expanded navigation persist', () async {
    await p.movePlaylist(['a', 'b', 'c'], 'c', -1);
    await p.togglePinnedPlaylist('b');
    await p.setPlayerCover(PlayerCover.logo);
    await p.setKeepPhoneNavOpen(true);
    p.restore(const {});
    expect(p.keepPhoneNavOpen, isFalse);
    await p.load();
    expect(p.playlistOrder, PlaylistOrder.custom);
    expect(p.customPlaylistOrder, ['a', 'c', 'b']);
    expect(p.pinnedPlaylists, {'b'});
    expect(p.playerCover, PlayerCover.logo);
    expect(p.keepPhoneNavOpen, isTrue);
  });
  test('player close button is hidden by default and its override persists', () async {
    expect(p.showPlayerClose, isFalse);
    await p.setShowPlayerClose(true);
    final saved = p.toJson();
    p.restore(const {});
    expect(p.showPlayerClose, isFalse);
    p.restore(saved);
    expect(p.showPlayerClose, isTrue);
  });

  test('defaults use Classic navigation and player appearance', () {
    expect(p.visualizer, isTrue, reason: 'Classic pulses around the cover');
    expect(p.visualizerStyle, VisualizerStyle.pulse);
    expect(p.visualizerCoverShape, VisualizerCoverShape.flower);
    expect(p.tabBar, TabBarStyle.capsule);
    expect(p.corners, CornerStyle.rounded);
    expect(p.density, Density.comfortable);
    expect(p.coverSize, CoverSize.medium);
    expect(p.homeOrder, HomeSection.values);
    expect(p.homeHidden, isEmpty);
    expect(p.progressBar, ProgressBarStyle.thin);
    expect(p.playButton, PlayButtonShape.flower);
    expect(p.showQualityBadge, isTrue);
    expect(p.qualityBadgePlace, QualityBadgePlace.timeRow);
    expect(p.volumeSlider, VolumeSliderShape.classic);
    expect(p.dimUnsungLyrics, isTrue);
    expect(p.motion, Motion.full);
    expect(p.pageMotion, PageMotionStyle.classic);
    expect(p.pageSpeed, PageMotionSpeed.relaxed);
    expect(p.progressShape, ProgressBarShape.wavy);
    expect(p.isCustomised, isFalse);
    expect(LayoutPrefs.radius(8), 8);
    expect(LayoutPrefs.dur(const Duration(milliseconds: 200)), const Duration(milliseconds: 200));
  });

  test('glass follows theme and explicit overrides round trip', () async {
    await p.setGlassTint(GlassTint.theme);
    final light = riflayGlassAppearance(themeIsLight: true);
    final dark = riflayGlassAppearance(themeIsLight: false);
    expect(dark.tint.toARGB32(), 0x5C000000);
    expect(light.tint.toARGB32(), 0x66FFFFFF);
    expect(dark.colorModel, isNot(light.colorModel));
    await p.setGlassTint(GlassTint.black);
    final saved = p.toJson();
    p.restore({});
    p.restore(saved);
    expect(riflayGlassAppearance(themeIsLight: true), dark);
    await p.setGlassTint(GlassTint.light);
    expect(riflayGlassAppearance(themeIsLight: false), light);
  });

  test('fresh player matches Classic and explicit saved bar styles survive', () {
    p.restore({});
    expect(PlayerPreset.classic.changesTo(p), 0);
    p.restore({'tabBar': 'glass'});
    expect(p.tabBar, TabBarStyle.glass);
  });

  test('Centre button is removed and old preferences fall back to Classic', () {
    expect(TabBarStyle.values.map((style) => style.name), isNot(contains('centre')));
    expect(TabBarStyle.values, hasLength(9));
    p.restore({'tabBar': 'centre'});
    expect(p.tabBar, TabBarStyle.capsule);
    expect(p.toJson()['tabBar'], 'capsule');
  });

  test('Lightweight limits covers and replaces Background across switching, restore and presets', () async {
    await p.setPerformance(PerformanceMode.balanced);
    await p.setPlayerCover(PlayerCover.background);
    await p.setPerformance(PerformanceMode.lightweight);
    expect(p.playerCoverChoices, [PlayerCover.flower, PlayerCover.square, PlayerCover.logo]);
    expect(p.playerCover, PlayerCover.square);
    await p.load();
    expect(p.playerCover, PlayerCover.square);
    await p.setPlayerCover(PlayerCover.flower);
    expect(p.playerCover, PlayerCover.flower);
    await p.setPlayerCover(PlayerCover.background);
    expect(p.playerCover, PlayerCover.square);
    await PlayerPreset.stacked.apply(p);
    expect(p.playerCover, PlayerCover.square);
    p.restore({'performance': 'lightweight', 'playerCover': 'background'});
    expect(p.playerCover, PlayerCover.square);
    await p.setPerformance(PerformanceMode.balanced);
    expect(p.playerCoverChoices, PlayerCover.values);
    expect(p.playerCover, PlayerCover.square);
    await p.setPlayerCover(PlayerCover.background);
    expect(p.playerCover, PlayerCover.background);
  });

  test('a visible volume slider limits bottom buttons and normalises saved or preset Icons', () async {
    expect(p.bottomRowChoices, [PlayerBottomRow.classic, PlayerBottomRow.chips]);
    await p.setShowVolumeRow(false);
    expect(p.bottomRowChoices, PlayerBottomRow.values);
    await p.setBottomRow(PlayerBottomRow.minimal);
    expect(p.bottomRow, PlayerBottomRow.minimal);
    await p.setShowVolumeRow(true);
    expect(p.bottomRow, PlayerBottomRow.classic);
    await p.setBottomRow(PlayerBottomRow.chips);
    await p.load();
    expect(p.bottomRow, PlayerBottomRow.chips);
    p.restore({'showVolumeRow': true, 'bottomRow': 'minimal'});
    expect(p.bottomRow, PlayerBottomRow.classic);
    await p.change(() {
      p.bottomRow = PlayerBottomRow.minimal;
      p.showVolumeRow = true;
    });
    expect(p.bottomRow, PlayerBottomRow.classic);
    await p.setShowVolumeRow(false);
    await p.setBottomRow(PlayerBottomRow.minimal);
    await p.load();
    expect(p.bottomRow, PlayerBottomRow.minimal);
  });

  test('circle play button and straight seek override persist independently', () async {
    await p.setPlayButton(PlayButtonShape.circle);
    await p.setProgressShape(ProgressBarShape.straight);
    await p.load();
    expect(p.playButton, PlayButtonShape.circle);
    expect(p.progressShape, ProgressBarShape.straight);
    await p.reset();
    expect(p.playButton, PlayButtonShape.flower);
    expect(p.progressShape, ProgressBarShape.wavy);
  });

  test('page motion starts on Classic; an old save\'s default Side reveal moves over, a choice made since stays', () {
    p.restore({'pageMotion': 'wipe'});
    expect(p.pageMotion, PageMotionStyle.classic, reason: 'Side reveal was only the old default');
    p.restore({'pageMotion': 'wipe', 'pageMotionVersion': 2});
    expect(p.pageMotion, PageMotionStyle.wipe, reason: 'picked after the change: kept');
    p.restore({'pageMotion': 'glide'});
    expect(p.pageMotion, PageMotionStyle.glide, reason: 'another choice is never touched');
    expect(p.toJson()['pageMotionVersion'], 2);
    p.restore(const {});
  });

  test('visualizer choice persists and reset returns to the original player', () async {
    await p.setDesktopBar(DesktopBarStyle.compact);
    await p.setVisualizer(true);
    await p.setVisualizerStyle(VisualizerStyle.dots);
    await p.load();
    expect(p.desktopBar, DesktopBarStyle.compact);
    expect(p.visualizer, isTrue);
    expect(p.visualizerStyle, VisualizerStyle.dots);
    await p.setVisualizer(false);
    await p.reset();
    expect(p.visualizer, isTrue);
    p.restore({'visualizerStyle': 'future-style'});
    expect(p.visualizerStyle, VisualizerStyle.pulse);
  });

  test('cover shape persists independently of visualizer enablement and defaults safely', () async {
    await p.setVisualizerCoverShape(VisualizerCoverShape.square);
    await p.load();
    expect(p.visualizerCoverShape, VisualizerCoverShape.square);
    expect(p.visualizer, isTrue);
    p.restore({'visualizerCoverShape': 'future-shape'});
    expect(p.visualizerCoverShape, VisualizerCoverShape.flower);
    await p.reset();
    expect(p.pageMotion, PageMotionStyle.classic);
    expect(p.pageSpeed, PageMotionSpeed.relaxed);
    expect(p.progressShape, ProgressBarShape.wavy);
  });

  test('old visualizer layouts migrate to Pulse; new choices still persist', () async {
    p.restore({'visualizer': true, 'visualizerStyle': 'wave'});
    expect(p.visualizerStyle, VisualizerStyle.pulse);
    await p.setVisualizerStyle(VisualizerStyle.wave);
    await p.load();
    expect(p.visualizerStyle, VisualizerStyle.wave);
  });

  test('visualizer radius and thickness persist, clamp and reset', () async {
    await p.setVisualizerRadius(2.1);
    await p.setVisualizerThickness(5.5);
    await p.load();
    expect(p.visualizerRadius, 2.1);
    expect(p.visualizerThickness, 5.5);
    await p.setVisualizerRadius(99);
    await p.setVisualizerThickness(-1);
    expect(p.visualizerRadius, 2.5);
    expect(p.visualizerThickness, 1);
    await p.reset();
    expect(p.visualizerRadius, 1.6);
    expect(p.visualizerThickness, 3);
  });

  test('corners scale one radius token', () async {
    await p.setCorners(CornerStyle.square);
    expect(LayoutPrefs.radius(8), 0);
    await p.setCorners(CornerStyle.extraRound);
    expect(LayoutPrefs.radius(8), 16);
  });

  test('motion: reduced shortens, off removes', () async {
    const d = Duration(milliseconds: 300);
    await p.setMotion(Motion.reduced);
    expect(LayoutPrefs.dur(d), lessThan(d));
    expect(LayoutPrefs.moves, isFalse);
    await p.setMotion(Motion.off);
    expect(LayoutPrefs.dur(d), Duration.zero);
  });

  test('saved settings come back, and reset clears them', () async {
    await p.setCorners(CornerStyle.square);
    await p.setHomeSectionShown(HomeSection.artists, false);
    await p.setHomeStyle(HomeStyle.carousel);
    await p.moveHomeSection(p.homeOrder.indexOf(HomeSection.recentlyAdded), 0);
    final saved = p.toJson();
    await p.reset();
    expect(p.isCustomised, isFalse);
    expect(p.homeStyle, HomeStyle.classic);
    p.restore(saved);
    expect(p.corners, CornerStyle.square);
    expect(p.homeStyle, HomeStyle.carousel);
    expect(p.homeShown.first, HomeSection.recentlyAdded);
    expect(p.homeShown, isNot(contains(HomeSection.artists)));
    expect(p.isCustomised, isTrue);
  });

  test('unknown or missing values fall back; new sections join in', () {
    p.restore({
      'corners': 'pointy',
      'homeOrder': ['albums', 'nonsense', 'albums', 'quickPicks'],
      'homeHidden': ['nonsense', 'discover'],
    });
    expect(p.corners, CornerStyle.rounded);
    expect(p.homeOrder.toSet(), HomeSection.values.toSet());
    expect(p.homeOrder.length, HomeSection.values.length);
    expect(p.homeHidden, {HomeSection.discover});
  });

  test('classic balanced preserves theme fast path, while corners still apply', () async {
    final base = ThemeData();
    await p.setPageMotion(PageMotionStyle.classic);
    await p.setPageSpeed(PageMotionSpeed.balanced);
    expect(identical(p.themed(base), base), isTrue);
    await p.setCorners(CornerStyle.square);
    final shape = p.themed(base).dialogTheme.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.zero);
  });

  testWidgets('Layout settings: change a choice and reset', (tester) async {
    tester.view.physicalSize = const Size(900, 7000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: LayoutSettings())),
      ),
    );
    expect(find.text('Corners'), findsOneWidget);
    expect(find.text('Rounded'), findsOneWidget);
    await tester.runAsync(() => p.setCorners(CornerStyle.square));
    await tester.pump();
    expect(find.text('Square'), findsOneWidget);
    await tester.tap(find.text('Reset layout to default'));
    await tester.pump();
    expect(p.corners, CornerStyle.rounded);
    // Hiding a section is a switch on its row.
    await tester.tap(find.widgetWithText(SwitchListTile, 'Artists'));
    await tester.pump();
    expect(p.homeHidden, {HomeSection.artists});
  });

  test('the lyrics options persist and default to how lyrics have always been', () async {
    expect(p.lyricsLines, LyricsLines.all);
    expect(p.lyricsSync, LyricsSync.word);
    await p.setLyricsLines(LyricsLines.focused);
    await p.setLyricsSync(LyricsSync.line);
    p.restore(const {});
    expect(p.lyricsLines, LyricsLines.all);
    await p.load();
    expect(p.lyricsLines, LyricsLines.focused);
    expect(p.lyricsSync, LyricsSync.line);
    p.restore({'lyricsLines': 'from-the-future', 'lyricsSync': 'nope'});
    expect(p.lyricsLines, LyricsLines.all);
    expect(p.lyricsSync, LyricsSync.word);
    await p.reset();
    expect(p.isCustomised, isFalse);
  });

  test('the quality badge place persists; the visualizer survives out of Beta only if it was opted in', () async {
    expect(p.qualityBadgePlace, QualityBadgePlace.timeRow);
    await p.setQualityBadgePlace(QualityBadgePlace.underArtist);
    await p.load();
    expect(p.qualityBadgePlace, QualityBadgePlace.underArtist);
    await p.reset();

    // An older save: the visualizer was on in the layout, but only counted with its Beta switch.
    SharedPreferences.setMockInitialValues({'layout.v1': '{"visualizer":true}'});
    await p.load();
    expect(p.visualizer, isFalse, reason: 'never opted in: stays off');
    SharedPreferences.setMockInitialValues({'layout.v1': '{"visualizer":true}', 'features.audioVisualizer': true});
    await p.load();
    expect(p.visualizer, isTrue, reason: 'opted in: kept');
    SharedPreferences.setMockInitialValues({'layout.v1': '{"visualizer":true,"visualizerStable":true}'});
    await p.load();
    expect(p.visualizer, isTrue, reason: 'a save made since is taken as it is');
    await p.reset();
  });

  test('the video decoder persists, is not a look, and Reset leaves it alone', () async {
    expect(p.videoDecoder, VideoDecoder.automatic);
    expect(VideoDecoder.automatic.hwdec, 'auto-safe');
    expect(VideoDecoder.software.hwdec, 'no');
    await p.setVideoDecoder(VideoDecoder.software);
    expect(p.isCustomised, isFalse);
    await p.load();
    expect(p.videoDecoder, VideoDecoder.software);
    await p.reset();
    expect(p.videoDecoder, VideoDecoder.software);
    await p.setVideoDecoder(VideoDecoder.automatic);
  });

  test('window buttons can be hidden, and Reset leaves them as they are', () async {
    expect(p.windowButtons, isTrue);
    await p.setWindowButtons(false);
    expect(p.isCustomised, isFalse);
    await p.load();
    expect(p.windowButtons, isFalse);
    await p.reset();
    expect(p.windowButtons, isFalse);
    await p.setWindowButtons(true);
  });

  test('Liquid player controls persist, and normal presets turn them off', () async {
    await p.setPlayerGlassControls(true);
    await p.load();
    expect(p.playerGlassControls, isTrue);
    await PlayerPreset.stacked.apply(p);
    expect(p.playerGlassControls, isFalse);
    await PlayerPreset.liquidStacked.apply(p);
    expect(p.playerGlassControls, isTrue);
    await PlayerPreset.kawaii.apply(p);
    expect(p.playerGlassControls, isFalse);
    await PlayerPreset.liquidKawaii.apply(p);
    expect(p.playerGlassControls, isTrue);
    await p.reset();
    expect(p.playerGlassControls, isFalse);
  });

  test('Liquid glass part switches start off, persist, and survive presets but Liquid Kawaii', () async {
    expect((p.glassSeekBar, p.glassTransport, p.glassVolume), (false, false, false));
    await p.setGlassSeekBar(true);
    await p.setGlassTransport(true);
    await p.setGlassVolume(true);
    await p.load();
    expect((p.glassSeekBar, p.glassTransport, p.glassVolume), (true, true, true));
    await PlayerPreset.kawaii.apply(p);
    expect((p.glassSeekBar, p.glassTransport, p.glassVolume), (true, true, true));
    // Liquid Kawaii is Liquid Glass controls alone: its seek bar, playback and volume are plain.
    await PlayerPreset.liquidKawaii.apply(p);
    expect((p.glassSeekBar, p.glassTransport, p.glassVolume), (false, false, false));
    await p.reset();
    expect((p.glassSeekBar, p.glassTransport, p.glassVolume), (false, false, false));
  });

  test('every preset keeps the whole song in view, not the focused three lines', () {
    for (final preset in PlayerPreset.all) {
      expect(preset.lyricsLines, LyricsLines.all, reason: preset.name);
    }
  });

  test('the volume slider look persists, and Stacked makes it a pill with the row shown', () async {
    expect(p.volumeSlider, VolumeSliderShape.classic);
    await p.setVolumeSlider(VolumeSliderShape.thin);
    await p.load();
    expect(p.volumeSlider, VolumeSliderShape.thin);
    await PlayerPreset.stacked.apply(p);
    expect(p.volumeSlider, VolumeSliderShape.pill);
    expect(p.showVolumeRow, isTrue);
    await PlayerPreset.kawaii.apply(p);
    expect(p.volumeSlider, VolumeSliderShape.pill, reason: 'the volume under the lyrics is a pill');
    await PlayerPreset.classic.apply(p);
    expect(p.volumeSlider, VolumeSliderShape.classic);
    expect(p.qualityBadgePlace, QualityBadgePlace.timeRow);
  });
}
