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
import 'package:riflay/ui/pages/collection_page.dart';
import 'package:riflay/ui/pages/layout_settings.dart';
import 'package:riflay/ui/pages/lyrics_page.dart';
import 'package:riflay/ui/player/desktop_player_bar.dart';
import 'package:riflay/ui/player/full_screen_player.dart';
import 'package:riflay/ui/player/player_parts.dart';
import 'package:riflay/ui/player/side_panel.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/collection_hero.dart';
import 'package:riflay/ui/widgets/controls.dart';
import 'package:riflay/ui/widgets/faded_cover.dart';
import 'package:riflay/ui/widgets/marquee_text.dart';
import 'package:riflay/ui/widgets/wavy_seek_track.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _track = Track(
  id: 'desktop-parts',
  uri: Uri.parse('file:///desktop-parts.mp3'),
  title: 'Desk song',
  artist: 'Artist',
);

class _Player extends PlayerController {
  @override
  Track get currentTrack => _track;
  @override
  bool get canPlay => true;
  @override
  Duration get duration => const Duration(minutes: 2, seconds: 30);
  @override
  Stream<Duration> smoothPosition() => Stream.value(const Duration(minutes: 1, seconds: 4));
}

const _sizes = [Size(1280, 800), Size(1920, 1080)];

Finder _tip(String message) => find.byTooltip(message);

/// Errors the harness reports other than the known setState in the bare cover (see expanded_panel_test).
final _errors = <String>[];

/// Runs [body] with errors collected instead of failing the test, so a failed expect() reports itself.
Future<void> _guarded(Future<void> Function() body) async {
  final old = FlutterError.onError;
  FlutterError.onError = (d) => _errors.add(d.exceptionAsString());
  try {
    await body();
  } finally {
    FlutterError.onError = old;
  }
}

Future<void> _pump(WidgetTester tester, [int ms = 50]) => _guarded(() => tester.pump(Duration(milliseconds: ms)));

List<String> get _real => [
  for (final e in _errors)
    if (!e.contains('during build') && !e.contains('Build scheduled')) e,
];

Widget _tree(_Player c, Size size, Widget page, {bool compact = false}) => PlayerScope(
  controller: c,
  child: MaterialApp(
    home: ShellScope(
      compact: compact,
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

Future<_Player> _show(WidgetTester tester, Widget page, Size size, {bool compact = false}) async {
  SharedPreferences.setMockInitialValues({'library.v1': jsonEncode(<Object>[]), 'discord.enabled': false});
  final c = _Player();
  await tester.runAsync(c.load);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _errors.clear();
  await _guarded(() async {
    await tester.pumpWidget(_tree(c, size, page, compact: compact));
    await tester.pump(const Duration(milliseconds: 100));
  });
  return c;
}

Future<void> _swap(WidgetTester tester, _Player c, Size size, Widget page, int n) async {
  await _guarded(() async {
    await tester.pumpWidget(_tree(c, size, KeyedSubtree(key: ValueKey(n), child: page)));
    await tester.pump(const Duration(milliseconds: 50));
  });
}

Future<void> _close(WidgetTester tester, _Player c) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() async => c.dispose());
}

Widget get _bar => const Scaffold(
  body: Align(
    alignment: Alignment.bottomCenter,
    child: DesktopPlayerBar(sidePanelOpen: false, onToggleSidePanel: null),
  ),
);

TrackSliderShape _seekShape(WidgetTester tester) {
  final slider = find.descendant(of: find.byType(SeekBar), matching: find.byType(Slider)).first;
  final theme = tester.widget<SliderTheme>(find.ancestor(of: slider, matching: find.byType(SliderTheme)).first);
  return TrackSliderShape(theme.data.trackShape);
}

/// What a seek bar paints its track with.
class TrackSliderShape {
  const TrackSliderShape(this.shape);
  final SliderTrackShape? shape;
  bool get pill => shape is PillSeekTrack;
  bool get wavy => shape is WavySeekTrack;
}

void main() {
  final p = LayoutPrefs.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await p.reset();
    await Appearance.instance.setNowPlaying(NowPlayingBackground.color);
    expandedPlayerPanel.value = ExpandedPanel.none;
    fullScreenPlayer.value = false;
  });
  tearDown(() async {
    await p.reset();
    expandedPlayerPanel.value = ExpandedPanel.none;
    fullScreenPlayer.value = false;
  });

  group('expanded player', () {
    for (final size in _sizes) {
      testWidgets('defaults are the original layout at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        final c = await _show(tester, const Scaffold(body: FullScreenPlayer()), size);
        expect(_real, isEmpty);
        expect(find.text('Now playing'), findsOneWidget);
        expect(find.byType(PartButton), findsNothing, reason: 'Classic title buttons are the plain icons');
        expect(tester.widget<Artwork>(find.byType(Artwork).first).radius, 12);
        expect(_tip('Lyrics'), findsOneWidget);
        expect(_tip('Equalizer'), findsOneWidget);
        await _close(tester, c);
      });

      testWidgets(
        'every cover, top and title-button mix keeps the Classic layout at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          final c = await _show(tester, const SizedBox(), size);
          var n = 0;
          for (final panel in [ExpandedPanel.none, ExpandedPanel.lyrics]) {
            expandedPlayerPanel.value = panel;
            for (final cover in PlayerCover.values) {
              for (final header in PlayerHeader.values) {
                for (final actions in TitleActions.values) {
                  p
                    ..playerCover = cover
                    ..playerHeader = header
                    ..titleActions = actions;
                  await _swap(tester, c, size, const Scaffold(body: FullScreenPlayer()), n++);
                  final mix = '$panel $cover $header $actions';
                  expect(_real, isEmpty, reason: mix);
                  expect(
                    _tip(panel == ExpandedPanel.lyrics ? 'Hide lyrics' : 'Lyrics'),
                    findsOneWidget,
                    reason: '$mix: Lyrics is always there',
                  );
                  expect(_tip('Equalizer'), findsOneWidget, reason: mix);
                  expect(find.text('Desk song'), findsOneWidget, reason: mix);
                  // The expanded player is Classic whatever the parts say: they shape the phone and the side panel.
                  expect(find.byType(FadedCover), findsNothing, reason: mix);
                  expect(tester.widget<Artwork>(find.byType(Artwork).first).radius, 12, reason: mix);
                  expect(find.text('Now Playing'), findsNothing, reason: mix);
                  expect(find.textContaining('Playing from'), findsNothing, reason: mix);
                  expect(_tip('Share'), findsNothing, reason: mix);
                  // The title never runs under its buttons.
                  final title = tester.getRect(find.byType(MarqueeText).first);
                  final menu = tester.getRect(find.byTooltip('More options for Desk song').first);
                  expect(title.right, lessThanOrEqualTo(menu.left + 0.5), reason: '$mix: title vs buttons');
                }
              }
            }
          }
          await _close(tester, c);
        },
      );
    }

    testWidgets('the Background cover leaves the expanded player Classic', (tester) async {
      final c = await _show(tester, const Scaffold(body: FullScreenPlayer()), const Size(1280, 800));
      p.playerCover = PlayerCover.background;
      await _swap(tester, c, const Size(1280, 800), const Scaffold(body: FullScreenPlayer()), 1);
      expect(find.byType(FadedCover), findsNothing);
      expect(tester.widget<Artwork>(find.byType(Artwork).first).radius, 12);
      await _close(tester, c);
    });

    testWidgets('Lyrics is there with nothing playing too, in every top', (tester) async {
      final c = await _show(tester, const SizedBox(), const Size(1280, 800));
      var n = 0;
      for (final header in PlayerHeader.values) {
        p.playerHeader = header;
        await _swap(tester, c, const Size(1280, 800), const Scaffold(body: FullScreenPlayer()), n++);
        expect(_tip('Lyrics'), findsOneWidget, reason: '$header');
      }
      await _close(tester, c);
    });
  });

  group('player bar', () {
    testWidgets('the volume popup opens above the button, inside a 1000x700 window', (tester) async {
      const size = Size(1000, 700);
      // A bar narrower than 860 px keeps volume behind its button; at the window's bottom-right corner.
      final c = await _show(
        tester,
        const Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: SizedBox(width: 800, child: DesktopPlayerBar(sidePanelOpen: false, onToggleSidePanel: null)),
          ),
        ),
        size,
      );
      final button = _tip('Volume');
      expect(button, findsOneWidget);
      final buttonRect = tester.getRect(button);
      await _guarded(() async {
        await tester.tap(button);
        await tester.pump(const Duration(milliseconds: 300));
      });
      final popup = find.byType(VolumeSlider);
      expect(popup, findsOneWidget);
      final rect = tester.getRect(popup);
      final window = Offset.zero & size;
      expect(window.contains(rect.topLeft) && window.contains(rect.bottomRight), isTrue, reason: '$rect in $window');
      expect(rect.bottom, lessThanOrEqualTo(buttonRect.top + 1), reason: 'above the button');
      await _close(tester, c);
    });

    testWidgets('the More menu opens inside a 1000x700 window', (tester) async {
      const size = Size(1000, 700);
      final c = await _show(tester, _bar, size);
      await _guarded(() async {
        await tester.tap(_tip('More options'));
        await tester.pump(const Duration(milliseconds: 300));
      });
      final menu = find.byType(PopupMenuItem<VoidCallback>).first;
      final rect = tester.getRect(menu);
      final window = Offset.zero & size;
      expect(window.contains(rect.topLeft) && window.contains(rect.bottomRight), isTrue, reason: '$rect in $window');
      await _close(tester, c);
    });

    for (final size in _sizes) {
      testWidgets('defaults are the original bar at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        final c = await _show(tester, _bar, size);
        expect(_real, isEmpty);
        expect(find.byType(TransportControls), findsOneWidget);
        expect(find.byType(DesktopControlsRow), findsNothing);
        expect(find.byType(PartButton), findsNothing);
        expect(find.byType(IconButton), findsWidgets);
        expect(_tip('Lyrics'), findsOneWidget);
        expect(_tip('Queue'), findsOneWidget);
        expect(_tip('Sleep timer'), findsNothing, reason: 'Chips only');
        expect(find.byType(VolumeSlider), findsOneWidget);
        expect(find.text('2:30'), findsOneWidget);
        expect(_seekShape(tester).wavy, isTrue, reason: 'today the default shape is wavy');
        await _close(tester, c);
      });

      testWidgets(
        'every bar style with every controls, bottom row and shape fits ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          final c = await _show(tester, const SizedBox(), size);
          var n = 0;
          for (final style in DesktopBarStyle.values) {
            for (final transport in PlayerTransport.values) {
              for (final row in PlayerBottomRow.values) {
                for (final shape in ProgressBarShape.values) {
                  p
                    ..desktopBar = style
                    ..transport = transport
                    ..bottomRow = row
                    ..progressShape = shape
                    ..showTimeLeft = n.isOdd
                    ..showVolumeRow = n % 3 != 0
                    ..playerCover = PlayerCover.values[n % 3];
                  await _swap(tester, c, size, _bar, n++);
                  final mix = '$style $transport $row $shape';
                  expect(_real, isEmpty, reason: mix);
                  expect(_tip('Lyrics'), findsOneWidget, reason: '$mix: Lyrics is always on the bar');
                  expect(_tip('Queue'), findsOneWidget, reason: mix);
                  // The bar is Classic whatever the parts say: they shape the phone and the side panel.
                  expect(_tip('Sleep timer'), findsNothing, reason: mix);
                  expect(find.byType(TransportControls), findsOneWidget, reason: mix);
                  expect(find.byType(DesktopControlsRow), findsNothing, reason: mix);
                  expect(_tip('Previous'), findsOneWidget, reason: mix);
                  expect(_tip('Next'), findsOneWidget, reason: mix);
                  expect(_seekShape(tester).pill, isFalse, reason: mix);
                  expect(find.text('2:30'), findsOneWidget, reason: '$mix: the elapsed time, as Classic');
                }
              }
            }
          }
          await _close(tester, c);
        },
      );
    }

    testWidgets('Lyrics turns to Hide lyrics in the expanded player, in every bottom row', (tester) async {
      fullScreenPlayer.value = true;
      expandedPlayerPanel.value = ExpandedPanel.lyrics;
      final c = await _show(tester, const SizedBox(), const Size(1280, 800));
      var n = 0;
      for (final row in PlayerBottomRow.values) {
        p.bottomRow = row;
        await _swap(tester, c, const Size(1280, 800), _bar, n++);
        expect(_tip('Hide lyrics'), findsOneWidget, reason: '$row');
      }
      await _close(tester, c);
    });

    testWidgets('the bar keeps the Classic controls and flower thumbnail in every preset', (tester) async {
      for (final preset in PlayerPreset.all) {
        await preset.apply(p);
        final c = await _show(tester, _bar, const Size(1280, 800));
        expect(find.byType(TransportControls), findsOneWidget, reason: preset.name);
        expect(find.byType(DesktopControlsRow), findsNothing, reason: preset.name);
        expect(tester.widget<Artwork>(find.byType(Artwork).first).flower, isTrue, reason: preset.name);
        await _close(tester, c);
      }
    });
  });

  group('side panel', () {
    for (final cover in PlayerCover.values) {
      for (final header in PlayerHeader.values) {
        testWidgets('$cover and $header fit a 340 px panel', (tester) async {
          p
            ..playerCover = cover
            ..playerHeader = header;
          final c = await _show(
            tester,
            Scaffold(
              body: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(width: 340, child: NowPlayingSidePanel(onClose: () {})),
              ),
            ),
            const Size(1280, 800),
          );
          expect(_real, isEmpty);
          final art = tester.getRect(
            cover == PlayerCover.background ? find.byType(FadedCover) : find.byType(Artwork).first,
          );
          // Background: the picture across the panel's top, a little taller than wide; else the card in the margins.
          expect(art.width, cover == PlayerCover.background ? 340 : 340 - 32);
          expect(art.height, closeTo(cover == PlayerCover.background ? 340 / 0.82 : art.width, 0.5));
          // No header row: the bar's Now playing view button shows and hides the panel.
          expect(find.text('Now Playing'), findsNothing);
          expect(find.byTooltip('Close'), findsNothing);
          await _close(tester, c);
        });
      }
    }
  });

  group('lyrics page', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('riflay-desktop-parts');
      UserLyrics.dirOverride = dir;
    });
    tearDown(() {
      UserLyrics.dirOverride = null;
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows may still hold the file for a moment; it is a temp folder.
      }
    });

    for (final size in _sizes) {
      for (final layout in LyricsLayout.values) {
        testWidgets('${layout.label} on desktop at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
          await tester.runAsync(() => UserLyrics.save(_track, '[00:00.00]Some words\n[00:10.00]More words'));
          p.lyricsLayout = layout;
          final c = await _show(tester, const Scaffold(body: LyricsPage()), size);
          await _pump(tester, 200);
          expect(_real, isEmpty);
          expect(find.byType(LyricsTopHeader), layout == LyricsLayout.topHeader ? findsOneWidget : findsNothing);
          expect(find.byType(LyricsBottomCard), layout == LyricsLayout.bottomCard ? findsOneWidget : findsNothing);
          expect(find.byType(LyricsPlainPlayer), findsNothing, reason: 'the player bar has the controls');
          expect(find.byType(SeekBar), findsNothing, reason: 'the player bar has the seek bar');
          // The player's More sheet isn't here on desktop (the lyrics' own options menu may be).
          expect(find.byType(PlayerMoreAction), findsNothing);
          expect(_tip('Expanded player'), layout == LyricsLayout.bottomCard ? findsOneWidget : findsNothing);
          expect(find.text('Desk song'), layout == LyricsLayout.classic ? findsNothing : findsOneWidget);
          await _close(tester, c);
        });
      }
    }

    testWidgets('the bottom card opens the expanded player on the lyrics', (tester) async {
      await tester.runAsync(() => UserLyrics.save(_track, '[00:00.00]Some words'));
      p.lyricsLayout = LyricsLayout.bottomCard;
      final c = await _show(tester, const Scaffold(body: LyricsPage()), const Size(1280, 800));
      await tester.tap(_tip('Expanded player'));
      await _pump(tester);
      expect(expandedPlayerPanel.value, ExpandedPanel.lyrics);
      expect(fullScreenPlayer.value, isTrue);
      fullScreenPlayer.value = false;
      windowFullScreen.value = false;
      await _close(tester, c);
    });
  });

  group('album and playlist top', () {
    final album = Collection(kind: CollectionKind.album, title: 'An album', subtitle: 'Artist', tracks: [_track]);

    for (final size in _sizes) {
      for (final style in AlbumHeaderStyle.values) {
        testWidgets('${style.label} on desktop at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
          p.albumHeader = style;
          final c = await _show(tester, CollectionPage(collection: album), size);
          expect(_real, isEmpty);
          expect(find.byType(CollectionHero), style == AlbumHeaderStyle.hero ? findsOneWidget : findsNothing);
          expect(find.text('An album'), findsWidgets);
          if (style == AlbumHeaderStyle.hero) {
            expect(_tip('Shuffle play'), findsOneWidget);
            expect(_tip('Play'), findsOneWidget);
            expect(_tip('Add all to queue'), findsOneWidget, reason: 'the list button of the round row');
          }
          await _close(tester, c);
        });
      }
    }

    testWidgets('a playlist of yours renames in place under the hero on desktop', (tester) async {
      p.albumHeader = AlbumHeaderStyle.hero;
      final playlist = Collection(
        kind: CollectionKind.playlist,
        id: 'p1',
        title: 'Mine',
        subtitle: '',
        tracks: [_track],
      );
      final c = await _show(
        tester,
        CollectionPage(collection: playlist, onRename: (_) async {}),
        const Size(1280, 800),
      );
      expect(_real, isEmpty);
      expect(find.byType(CollectionHero), findsOneWidget);
      expect(find.byTooltip('Rename'), findsWidgets);
      await _close(tester, c);
    });
  });

  group('settings and presets', () {
    testWidgets('the Player group and Presets are listed on desktop', (tester) async {
      tester.view.physicalSize = const Size(1280, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: LayoutSettings())),
        ),
      );
      // The groups, in order: Presets first, then Now Playing, the controls, lyrics, the visualizer, pages, bars.
      for (final group in [
        'Presets',
        'Now Playing',
        'Playback controls',
        'Lyrics',
        'Pages',
        'Bars',
        'Shapes and motion',
      ]) {
        expect(find.text(group), findsWidgets, reason: group);
      }
      expect(find.text('Player on phones'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Presets').first).dy,
        lessThan(tester.getTopLeft(find.text('Now Playing')).dy),
      );
      for (final t in [
        'Cover',
        'Buttons by the title',
        'Show time left',
        'Controls',
        'Bottom buttons',
        'Lyrics page',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.textContaining('desktop'), findsWidgets, reason: 'the notes say what differs on desktop');
    });

    for (final preset in PlayerPreset.all) {
      testWidgets('${preset.name} fits the expanded player, bar, lyrics page and album page on desktop', (
        tester,
      ) async {
        final dir = Directory.systemTemp.createTempSync('riflay-desktop-preset');
        UserLyrics.dirOverride = dir;
        addTearDown(() {
          UserLyrics.dirOverride = null;
          try {
            dir.deleteSync(recursive: true);
          } on FileSystemException {
            // A temp folder.
          }
        });
        await tester.runAsync(() => preset.apply(p));
        // Kawaii's Music video background starts the video machinery, which keeps timers: not what is under test.
        await Appearance.instance.setNowPlaying(NowPlayingBackground.color);
        await tester.runAsync(() => UserLyrics.save(_track, '[00:00.00]Some words'));
        final c = await _show(tester, const SizedBox(), const Size(1280, 800));
        var n = 0;
        for (final page in <Widget>[
          const Scaffold(body: FullScreenPlayer()),
          _bar,
          const Scaffold(body: LyricsPage()),
          CollectionPage(
            collection: Collection(kind: CollectionKind.album, title: 'An album', subtitle: 'Artist', tracks: [_track]),
          ),
        ]) {
          await _swap(tester, c, const Size(1280, 800), page, n++);
          expect(_real, isEmpty, reason: '${preset.name} #$n');
        }
        await _close(tester, c);
      });
    }
  });
}
