import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/services/language.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/pages/lyrics_page.dart';
import 'package:riflay/ui/pages/settings_index.dart';
import 'package:riflay/ui/pages/settings_page.dart';
import 'package:riflay/ui/pages/settings_preview.dart';
import 'package:riflay/ui/player/now_playing_page.dart';
import 'package:riflay/ui/shell/phone_navigation.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/live_preview.dart';
import 'package:riflay/ui/widgets/shelf.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings in a small app of its own, as in settings_navigation_test.
Widget _app(PlayerController c, List<String> visited, {bool compact = false, Widget home = const SettingsPage()}) {
  final navigator = GlobalKey<NavigatorState>();
  return MaterialApp(
    navigatorKey: navigator,
    builder: (context, child) => PlayerScope(
      controller: c,
      child: ShellScope(
        compact: compact,
        width: compact ? 400 : 1280,
        open: (page, {location}) {
          visited.add(location ?? '');
          navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => page));
        },
        openCollection: (_) {},
        openQueue: () {},
        openNowPlaying: () {},
        openLyrics: () {},
        openDownloads: () {},
        importFromYoutube: () {},
        addFiles: () {},
        addFolder: null,
        child: child!,
      ),
    ),
    home: home,
  );
}

void main() {
  void onLinux(String name, Future<void> Function(WidgetTester tester) body, {Size size = const Size(1280, 1800)}) =>
      testWidgets(name, (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          SharedPreferences.setMockInitialValues({});
          // A music video background would start the video machinery: not what this is about.
          await tester.runAsync(() => Appearance.instance.setNowPlaying(NowPlayingBackground.color));
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await body(tester);
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 5));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        } finally {
          debugDefaultTargetPlatformOverride = null;
          await tester.runAsync(LayoutPrefs.instance.reset);
          await tester.runAsync(() => Language.instance.set(AppLanguage.english));
        }
      });

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byKey(SettingsPage.searchKey), query);
    await tester.pump();
  }

  test('every option has its own id, and every parent is an option on the same page', () {
    final ids = [for (final o in SettingsOptions.all) o.id];
    expect(ids.toSet().length, ids.length);
    for (final o in SettingsOptions.all.where((o) => o.parent != null)) {
      expect(SettingsOptions.byId(o.parent!)?.place, o.place, reason: o.id);
    }
  });

  onLinux('search finds options by title, by other words and in other languages', (tester) async {
    await tester.pumpWidget(_app(PlayerController(), []));
    await search(tester, 'corners');
    expect(find.text('Corners'), findsOneWidget);
    expect(find.text('Look & feel › Pages & navigation'), findsWidgets, reason: 'each result says where it is');
    expect(find.text('Sound'), findsNothing, reason: 'the groups make way for the results');

    // Another word for it.
    await search(tester, 'rounded');
    expect(find.text('Corners'), findsOneWidget);

    // Indonesian and Japanese words while the screens are in English.
    await search(tester, 'sudut');
    expect(find.text('Corners'), findsOneWidget);
    await search(tester, '歌詞');
    expect(find.text('Lyrics page'), findsOneWidget);

    // The title first: "Equalizer" before the options that only mention it.
    await search(tester, 'equalizer');
    final titles = [for (final t in tester.widgetList<Text>(find.byType(Text))) t.data];
    expect(titles.indexOf('Equalizer'), lessThan(titles.indexOf('Song that is playing')));

    await search(tester, 'zzqx');
    expect(find.textContaining('No settings match'), findsOneWidget);

    await search(tester, '');
    expect(find.text('Sound'), findsOneWidget, reason: 'an empty box shows the groups again');
  });

  onLinux('search works in the language shown', (tester) async {
    await tester.runAsync(() => Language.instance.set(AppLanguage.indonesian));
    await tester.pumpWidget(_app(PlayerController(), []));
    await search(tester, 'sudut');
    expect(find.text(tr.corners), findsOneWidget);
    expect(find.text('${tr.groupLook} › ${tr.topicLayout}'), findsWidgets);
  });

  onLinux('a result opens its page, scrolled to the option and lit up for a moment', (tester) async {
    final visited = <String>[];
    await tester.pumpWidget(_app(PlayerController(), visited));
    await search(tester, 'tab bar on phones');
    await tester.tap(find.text('Tab bar on phones'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(visited.last, 'settings:look/layout');
    expect(find.byKey(SettingsPage.highlightKey), findsOneWidget);
    final row = find.ancestor(of: find.text('Tab bar on phones'), matching: find.byType(ListTile)).first;
    final light = tester.getRect(find.byKey(SettingsPage.highlightKey));
    expect(light, tester.getRect(row), reason: 'the light is over the row');
    // Scrolled into view, about a third of the way down.
    final y = tester.getCenter(row).dy;
    expect(y, inInclusiveRange(0, 1800 * 0.6));
    // Its preview shows beside the list.
    expect(find.byType(SettingPreviewCard), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(SettingsPage.highlightKey), findsNothing, reason: 'the light goes out');
  });

  onLinux('an option hidden behind its switch opens at that switch', (tester) async {
    final visited = <String>[];
    await tester.runAsync(() => LayoutPrefs.instance.setPlayerGlassControls(false));
    await tester.pumpWidget(_app(PlayerController(), visited));
    await search(tester, 'glass progress');
    await tester.tap(find.text('Glass progress bar'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(visited.last, 'settings:look/now-playing');
    final row = find.ancestor(of: find.text('Liquid Glass controls'), matching: find.byType(ListTile)).first;
    expect(tester.getRect(find.byKey(SettingsPage.highlightKey)), tester.getRect(row));
  });

  onLinux('every option offered here is found on its page', (tester) async {
    final c = PlayerController();
    for (final place in SettingsPlace.values.where((p) => p.available)) {
      await tester.pumpWidget(_app(c, [], home: place.page));
      await tester.pump(const Duration(milliseconds: 300));
      for (final o in SettingsOptions.all.where((o) => o.place == place && o.offered)) {
        // Shown, or its parent is (the part only shows once its switch is on).
        var target = o;
        while (find.text(target.marker, skipOffstage: false).evaluate().isEmpty && target.parent != null) {
          target = SettingsOptions.byId(target.parent!)!;
        }
        // Rows that depend on the account, the device or a song are allowed to be missing here.
        if (const {'youtubeMusic', 'ytHistory', 'outputDevice', 'deleteExecutables', 'updates'}.contains(o.id)) {
          continue;
        }
        expect(find.text(target.marker, skipOffstage: false), findsWidgets, reason: '${o.id} on ${place.name}');
      }
    }
  });

  onLinux('every row on a page of options is registered for search', (tester) async {
    final c = PlayerController();
    // Rows that are things, not options: a watched folder, a Home section, an installed extension.
    bool listed(String title) =>
        HomeSection.values.any((s) => s.label == title) ||
        const {'YouTube Music', 'Last.fm', 'ListenBrainz'}.contains(title) ||
        title == tr.noExtensionsYet;
    final missing = <String>[];
    for (final place in SettingsPlace.values.where((p) => p.available)) {
      await tester.pumpWidget(_app(c, [], home: place.page));
      await tester.pump(const Duration(milliseconds: 300));
      final markers = {
        for (final o in SettingsOptions.all.where((o) => o.place == place)) ...[o.marker, o.title(tr)],
      };
      for (final tile in tester.widgetList<ListTile>(find.byType(ListTile, skipOffstage: false))) {
        final title = tile.title;
        if (title is! Text || title.data == null) continue;
        if (!markers.contains(title.data) && !listed(title.data!)) missing.add('${place.name}: ${title.data}');
      }
    }
    expect(missing, isEmpty, reason: 'add these to SettingsOptions.all (settings_index.dart)');
  });

  onLinux('tapping an option that changes the look previews it beside the list', (tester) async {
    await tester.pumpWidget(_app(PlayerController(), [], home: SettingsPlace.layout.page));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(tr.settingsPreviewHint), findsOneWidget, reason: 'a computer has room beside the list');
    expect(find.byType(SettingPreviewCard), findsNothing);

    Future<void> tapRow(String title) async {
      final row = find.ancestor(of: find.text(title), matching: find.byType(ListTile)).first;
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getTopLeft(row) + const Offset(80, 12));
      await tester.pump();
      await tester.pump();
    }

    // Corners and spacing: covers and song rows, the real ones.
    await tapRow('Corners');
    expect(find.byType(SettingPreviewCard), findsOneWidget);
    expect(find.descendant(of: find.byType(LivePreview), matching: find.byType(Shelf)), findsOneWidget);
    final card = tester.getRect(find.byType(SettingPreviewCard));
    final list = tester.getRect(find.ancestor(of: find.text('Corners'), matching: find.byType(ListTile)).first);
    expect(card.left, greaterThan(list.right), reason: 'beside the list');
    expect((card.top - list.top).abs(), lessThan(40), reason: 'level with its row');
    // Standing still: nothing asks for frames while it is on screen.
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);

    // It follows the option as it changes.
    final before = tester.widget<KeyedSubtree>(
      find.descendant(of: find.byType(LivePreview), matching: find.byType(KeyedSubtree)).first,
    );
    await tester.runAsync(() => LayoutPrefs.instance.setCorners(CornerStyle.values.last));
    await tester.pump();
    final after = tester.widget<KeyedSubtree>(
      find.descendant(of: find.byType(LivePreview), matching: find.byType(KeyedSubtree)).first,
    );
    expect(after.key, isNot(before.key), reason: 'built afresh with the new look');

    await tapRow('Tab bar on phones');
    expect(find.descendant(of: find.byType(LivePreview), matching: find.byType(PhoneBottomBar)), findsOneWidget);

    await tester.pumpWidget(_app(PlayerController(), [], home: SettingsPlace.lyrics.page));
    await tester.pump(const Duration(milliseconds: 300));
    await tapRow('Lyrics page');
    expect(find.descendant(of: find.byType(LivePreview), matching: find.byType(SyncedLyricsView)), findsOneWidget);

    await tester.pumpWidget(_app(PlayerController(), [], home: SettingsPlace.nowPlaying.page));
    await tester.pump(const Duration(milliseconds: 300));
    await tapRow('Cover');
    expect(find.descendant(of: find.byType(LivePreview), matching: find.byType(NowPlayingPage)), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);

    // A row without a preview closes it.
    await tapRow('Song / Video switch');
    expect(find.byType(SettingPreviewCard), findsNothing);
  });

  onLinux('on a phone the preview shows over the rows above the option, and closes', (tester) async {
    await tester.pumpWidget(_app(PlayerController(), [], compact: true, home: SettingsPlace.layout.page));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(tr.settingsPreviewHint), findsNothing, reason: 'no room beside the list');
    final row = find.ancestor(of: find.text('Spacing'), matching: find.byType(ListTile)).first;
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(row) + const Offset(60, 12));
    await tester.pumpAndSettle();
    expect(find.byType(SettingPreviewCard), findsOneWidget);
    final card = tester.getRect(find.byType(SettingPreviewCard));
    expect(card.bottom, lessThanOrEqualTo(tester.getRect(row).top), reason: 'above its row');
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(SettingPreviewCard.closeKey));
    await tester.pumpAndSettle();
    expect(find.byType(SettingPreviewCard), findsNothing);
  }, size: const Size(400, 860));
}
