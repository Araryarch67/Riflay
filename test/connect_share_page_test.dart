import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/connect/connect_share.dart';
import 'package:riflay/services/connect/connect_store.dart';
import 'package:riflay/ui/pages/connect_share_page.dart';
import 'package:riflay/ui/player_scope.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connect_support.dart';

void main() {
  late ConnectShare share;
  late List<ShareCollection> source;
  late Track track;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    track = Track.fromUri(Uri.file('/home/ana/Music/Secret Folder/Song.flac'));
    source = [
      shareOf(ShareKind.album, 'blue', 'Blue Album', [track], artist: 'Ana'),
      shareOf(ShareKind.artist, 'ana', 'Ana', [track]),
      shareOf(ShareKind.playlist, 'p1', 'Road trip', [track]),
    ];
    final prefs = await SharedPreferences.getInstance();
    share = ConnectShare(source: () => source, openStore: () async => ConnectStore(prefs));
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump();
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(share.dispose);
    await tester.pumpWidget(
      PlayerScope(
        controller: FakeConnectPlayer(),
        child: MaterialApp(
          home: ShellScope(
            compact: false,
            width: 900,
            open: (_, {location}) {},
            openCollection: (_) {},
            openQueue: () {},
            openNowPlaying: () {},
            openLyrics: () {},
            openDownloads: () {},
            importFromYoutube: ({url}) {},
            addFiles: () {},
            addFolder: null,
            child: ConnectSharePage(share: share),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  bool checked(WidgetTester tester, String title) =>
      tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, title)).value!;

  testWidgets('nothing is shared until it is picked; each pick can be taken back', (tester) async {
    await open(tester);
    for (final name in ['Blue Album', 'Ana', 'Road trip']) {
      expect(checked(tester, name), isFalse, reason: '$name starts private');
    }
    expect(share.selected, isEmpty);

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Road trip'));
    await settle(tester);
    expect(checked(tester, 'Road trip'), isTrue);
    expect(checked(tester, 'Blue Album'), isFalse);
    expect(share.selected, {source[2].id});

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Road trip'));
    await settle(tester);
    expect(checked(tester, 'Road trip'), isFalse);
    expect(share.selected, isEmpty);
  });

  testWidgets('the list can be narrowed to albums, artists or playlists', (tester) async {
    await open(tester);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Playlists').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, 'Road trip'), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, 'Blue Album'), findsNothing);
  });

  testWidgets('what another device shares can be looked at and copied, with no way to change it', (tester) async {
    await open(tester);
    final theirs = shareOf(ShareKind.album, 'theirs', 'Their Album', [track, track], artist: 'Bo', year: 2001);
    share.attach('peer', 'Windows ABCD', (m) {});
    share.viewerOf('peer')!.handle({
      't': 'shr.idx',
      'rev': 1,
      'seq': 0,
      'of': 1,
      'items': [theirs.entry.withVersion(1).toJson()],
    });
    await share.handle('peer', {'t': 'shr.col', 'id': 'none'});
    share.viewerOf('peer')!.request(theirs.id);
    share.viewerOf('peer')!.handle({
      't': 'shr.col',
      'id': theirs.id,
      'v': 1,
      'seq': 0,
      'of': 1,
      'tracks': [for (final t in theirs.tracks) t.toJson()],
    });
    await share.handle('peer', {'t': 'shr.list'});
    await settle(tester);
    expect(find.text('Windows ABCD'), findsOneWidget);
    expect(find.text('Their Album'), findsOneWidget);
    expect(find.textContaining('2001'), findsOneWidget);

    await tester.tap(find.text('Their Album'));
    await tester.pumpAndSettle();
    expect(find.text('Shared by Windows ABCD. You can look, not change.'), findsOneWidget);
    expect(find.text('Rename'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.tap(find.text('Save a copy'));
    await settle(tester);
    expect(share.copies.single.entry.name, 'Their Album');
    expect(share.selected, isEmpty, reason: 'a copy is not shared onwards');
  });
}
