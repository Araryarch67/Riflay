import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/main.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/audio_engine.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/shortcuts.dart';
import 'package:riflay/ui/widgets/track_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // The test binding pretends to be Android; these are desktop features.
  /// Runs [body] as on Linux, putting the platform back before the binding checks it.
  void onLinux(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  onLinux('? and Ctrl+/ open the shortcuts list, which names every binding', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(RiflayApp(controller: PlayerController()));
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?'), isTrue);
    await tester.pump();
    expect(find.text('Keyboard shortcuts'), findsOneWidget);
    for (final s in appShortcuts) {
      expect(find.text(s.label), findsOneWidget);
    }
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Keyboard shortcuts'), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('Keyboard shortcuts'), findsOneWidget);
  });

  onLinux('tooltips name the shortcut', (tester) async {
    expect(tipWith('Next', AppAction.next), 'Next (Ctrl+→)');
    expect(tipWith('Play', AppAction.playPause), 'Play (Space)');
  });

  onLinux('the now-playing ⋯ menu has Stats for nerds and Signal path', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = PlayerController();
    final track = Track(id: 't', uri: Uri.parse('file:///t.flac'), title: 'T', artist: 'A');
    Widget app(bool nowPlaying) => MaterialApp(
      home: PlayerScope(
        controller: controller,
        child: ShellScope(
          compact: false,
          width: 800,
          open: (_, {location}) {},
          openCollection: (_) {},
          openQueue: () {},
          openNowPlaying: () {},
          openLyrics: () {},
          openDownloads: () {},
          importFromYoutube: () {},
          addFiles: () {},
          addFolder: null,
          child: Scaffold(
            body: TrackMenuButton(track: track, nowPlaying: nowPlaying),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app(false));
    await tester.tap(find.byType(PopupMenuButton<void>));
    await tester.pumpAndSettle();
    expect(find.text('Stats for nerds'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.pumpWidget(app(true));
    await tester.tap(find.byType(PopupMenuButton<void>));
    await tester.pumpAndSettle();
    expect(find.text('Stats for nerds'), findsOneWidget, skip: !AudioEngine.supported);
    expect(find.text('Signal path'), findsOneWidget, skip: !AudioEngine.supported);
  });
}
