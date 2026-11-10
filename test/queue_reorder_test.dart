import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/language.dart';
import 'package:riflay/services/listen_together/listen_together.dart';
import 'package:riflay/services/listen_together/protocol.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/pages/queue_page.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/theme.dart';
import 'package:riflay/ui/widgets/track_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

Track _song(String id) => Track(id: id, uri: Uri.file('/queue/$id.flac'), title: id, artist: 'Artist');

class _Controller extends PlayerController {
  final upcoming = [_song('first'), _song('second'), _song('third'), _song('fourth')];

  @override
  Track get currentTrack => _song('playing');

  @override
  List<Track> get upNext => upcoming;

  @override
  bool get showsPlaying => false;

  @override
  Future<void> moveInQueue(int from, int to) async {
    upcoming.insert(to, upcoming.removeAt(from));
    notifyListeners();
  }
}

class _Session extends ListenTogether {
  _Session(super.player);

  @override
  ListenRole role = ListenRole.guest;
  @override
  String get hostName => 'Host';
  @override
  SharedTrack? hostTrack = const SharedTrack(videoId: 'host-song', title: 'Host song', artist: 'Artist');
  @override
  List<SharedTrack> upNext = const [
    SharedTrack(videoId: 'a', title: 'Shared A', artist: 'Artist'),
    SharedTrack(videoId: 'b', title: 'Shared B', artist: 'Artist'),
  ];
}

Widget _app(PlayerController c) => PlayerScope(
  controller: c,
  child: MaterialApp(
    theme: buildAppTheme(),
    home: ShellScope(
      compact: true,
      width: 400,
      open: (_, {location}) {},
      openCollection: (_) {},
      openQueue: () {},
      openNowPlaying: () {},
      openLyrics: () {},
      openDownloads: () {},
      importFromYoutube: ({url}) {},
      addFiles: () {},
      addFolder: null,
      child: const Scaffold(body: QueuePage()),
    ),
  ),
);

void main() {
  testWidgets('guest queue follows the room, live updates and leaving the session', (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    await LayoutPrefs.instance.reset();
    final c = _Controller()..upcoming.clear();
    final session = _Session(c);
    ListenTogether.use(c, session);
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();
    expect(find.text('Host song'), findsOneWidget);
    expect(find.text('Shared A'), findsOneWidget);
    expect(find.text('Shared B'), findsOneWidget);
    expect(find.text('first'), findsNothing, reason: 'local songs are not the host queue');
    expect(find.byIcon(Icons.drag_handle_rounded), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing, reason: 'the host controls autoplay');
    for (final row in tester.widgetList<TrackRow>(find.byType(TrackRow))) {
      expect(row.onTap, isNull, reason: 'a guest cannot skip or re-add a queued song by tapping it');
    }

    session.upNext = [session.upNext.last, session.upNext.first, session.upNext.first];
    session.notifyListeners();
    await tester.pumpAndSettle();
    final shown = tester.widgetList<TrackRow>(find.byType(TrackRow)).map((row) => row.track.title).toList();
    expect(shown, ['Host song', 'Shared B', 'Shared A', 'Shared A']);

    session.hostTrack = null;
    session.upNext = [];
    session.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text(tr.waitingForHost('Host')), findsOneWidget);

    session.role = ListenRole.none;
    c.upcoming.addAll([_song('first'), _song('second')]);
    session.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('playing'), findsOneWidget);
    expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await session.leave();
    session.dispose();
    c.dispose();
  });

  testWidgets('phone queue drag keeps the row visible outside its route scope', (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    await LayoutPrefs.instance.reset();
    final c = _Controller();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      PlayerScope(
        controller: c,
        child: MaterialApp(
          theme: buildAppTheme(),
          // Phone Queue is a root route: ShellScope is below the Navigator's
          // overlay, so Flutter does not carry it into the drag proxy itself.
          home: ShellScope(
            compact: true,
            width: 400,
            open: (_, {location}) {},
            openCollection: (_) {},
            openQueue: () {},
            openNowPlaying: () {},
            openLyrics: () {},
            openDownloads: () {},
            importFromYoutube: ({url}) {},
            addFiles: () {},
            addFolder: null,
            child: const Scaffold(body: QueuePage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final title = find.text('first');
    final before = tester.getSize(title);
    final handle = find.byIcon(Icons.drag_handle_rounded).first;
    final gesture = await tester.startGesture(tester.getCenter(handle), kind: PointerDeviceKind.touch);
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(tester.getSize(title), before, reason: 'the drag keeps the phone row layout');
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(0, 15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(c.upcoming.first.title, 'second');
    expect(c.upcoming.map((t) => t.title), containsAll(['first', 'second', 'third', 'fourth']));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
