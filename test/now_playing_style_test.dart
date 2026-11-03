import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/lyrics.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/player_presets.dart';
import 'package:riflay/ui/pages/lyrics_page.dart';
import 'package:riflay/ui/pages/player_presets_page.dart';
import 'package:riflay/ui/player/mini_player.dart';
import 'package:riflay/ui/player/now_playing_page.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/controls.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _track = Track(id: 'style-test', uri: Uri.parse('file:///style-test.mp3'), title: 'Style test', artist: 'Artist');

class _Player extends PlayerController {
  final track = _track;
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

Future<_Player> _show(WidgetTester tester, Widget page, Size size) async {
  SharedPreferences.setMockInitialValues({'library.v1': jsonEncode(<Object>[])});
  final c = _Player();
  await tester.runAsync(c.load);
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
    await p.setPlayerCover(PlayerCover.fullBleed);
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
    expect(p.playerCover, PlayerCover.card);
    await p.load();
    expect(p.playerCover, PlayerCover.fullBleed);
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
    expect(p.playerCover, PlayerCover.card);
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
    expect(playerPresetName(), 'Stacked');
    await p.load();
    expect(playerPresetName(), 'Stacked', reason: 'saved as individual settings');

    await p.setTransport(PlayerTransport.plain);
    expect(playerPresetName(), isNull, reason: 'one part changed by hand: a custom mix');

    await PlayerPreset.kawaii.apply(p);
    expect(p.playerCover, PlayerCover.fullBleed);
    expect(p.playerHeader, PlayerHeader.playingFrom);
    expect(p.titleActions, TitleActions.plain);
    expect(p.progressShape, ProgressBarShape.straight);
    expect(p.progressBar, ProgressBarStyle.thin);
    expect(p.showTimeLeft, isTrue);
    expect(p.transport, PlayerTransport.plain);
    expect(p.bottomRow, PlayerBottomRow.minimal);
    expect(p.lyricsLayout, LyricsLayout.topHeader);
    expect(p.miniPlayer, MiniPlayerStyle.capsule);
    expect(p.albumHeader, AlbumHeaderStyle.hero);
    expect(Appearance.instance.nowPlaying, NowPlayingBackground.blurredCover);
    expect(playerPresetName(), 'Kawaii');
    expect(PlayerPreset.kawaii.changesTo(p), 0);

    await PlayerPreset.classic.apply(p);
    expect(p.classicPlayerFace, isTrue);
    expect(p.isCustomised, isFalse);
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

  testWidgets('Stacked parts: header, share, pill Play, bottom chips with Lyrics, volume; Play toggles', (
    tester,
  ) async {
    await PlayerPreset.stacked.apply(p);
    final c = await _show(tester, const NowPlayingPage(), const Size(360, 640));
    expect(find.text('Now Playing'), findsOneWidget);
    expect(find.text('Style test'), findsOneWidget);
    expect(_tip('Share'), findsOneWidget);
    expect(_tip('Add to Liked music'), findsNothing, reason: 'a file on this device cannot be liked');
    expect(find.text('Play'), findsOneWidget);
    for (final t in ['Queue', 'Sleep timer', 'Enable shuffle', 'Lyrics', 'Enable repeat', 'More', 'Previous', 'Next']) {
      expect(_tip(t), findsOneWidget, reason: t);
    }
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(2), reason: 'the progress bar and the volume');
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
                    ..showVolumeRow = n.isEven;
                  await tester.pumpWidget(
                    _tree(c, size, KeyedSubtree(key: ValueKey(n++), child: const NowPlayingPage())),
                  );
                  await tester.pump();
                  final mix = '$cover $header $actions $transport $bottom';
                  expect(tester.takeException(), isNull, reason: mix);
                  expect(_tip('Lyrics'), findsOneWidget, reason: mix);
                  expect(_tip('More'), findsOneWidget, reason: '$mix: exactly one More');
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
