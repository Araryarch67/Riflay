import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/main.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/player_presets.dart';
import 'package:riflay/ui/debug_switches.dart';
import 'package:riflay/ui/pages/search_page.dart' show SearchBox;
import 'package:riflay/ui/player/mini_player.dart';
import 'package:riflay/ui/shell/phone_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Player extends PlayerController {
  _Player({this.playing = true});

  final bool playing;
  final track = Track(
    id: 'glass-test',
    uri: Uri.parse('file:///glass-test.mp3'),
    title: 'Glass test',
    artist: 'Artist',
  );

  @override
  Track? get currentTrack => playing ? track : null;
  @override
  bool get hasNext => true;
}

/// The bar as the shell hosts it: under a long list whose scrolling reaches it through the link.
class _Harness extends StatefulWidget {
  const _Harness({required this.link, required this.onOpen, this.tab = PhoneTab.home});

  final GlassBarLink link;
  final VoidCallback onOpen;
  final PhoneTab tab;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late PhoneTab tab = widget.tab;

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    body: NotificationListener<ScrollNotification>(
      onNotification: widget.link.onScroll,
      child: ListView.builder(
        key: const ValueKey('list'),
        itemCount: 200,
        itemBuilder: (context, i) => SizedBox(height: 48, child: Text('Row $i')),
      ),
    ),
    bottomNavigationBar: PhoneBottomBar(
      onOpenPlayer: widget.onOpen,
      tab: tab,
      onSelect: (t) => setState(() => tab = t),
      link: widget.link,
    ),
  );
}

void main() {
  final prefs = LayoutPrefs.instance;
  final collapsedButton = find.byKey(PhoneBottomBar.tabsButtonKey);
  final list = find.byKey(const ValueKey('list'));

  setUp(() async {
    SharedPreferences.setMockInitialValues({'library.v1': jsonEncode(<Object>[])});
    await prefs.reset();
    prefs.tabBar = TabBarStyle.glass;
  });
  tearDown(() async {
    DebugSwitches.noTabBarCollapse = false;
    await prefs.reset();
  });

  Future<({GlassBarLink link, List<int> opened})> show(
    WidgetTester tester,
    Size size, {
    bool playing = true,
    PhoneTab tab = PhoneTab.home,
  }) async {
    final c = _Player(playing: playing);
    await tester.runAsync(c.load);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final link = GlassBarLink();
    addTearDown(link.dispose);
    final opened = <int>[];
    await tester.pumpWidget(
      PlayerScope(
        controller: c,
        child: MaterialApp(
          home: _Harness(link: link, onOpen: () => opened.add(1), tab: tab),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return (link: link, opened: opened);
  }

  Rect rectOf(WidgetTester tester, Finder f) => tester.getRect(f);

  Finder selectedTab(String label) =>
      find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label && w.properties.selected == true);

  for (final size in const [Size(360, 640), Size(412, 915)]) {
    final w = size.width.toInt();

    testWidgets('$w px: scrolling down shrinks the bar to one row, up and the top bring it back', (tester) async {
      final bar = await show(tester, size);
      // At rest: the mini player on its own row over the tabs, Search beside them.
      expect(collapsedButton, findsNothing);
      expect(find.byTooltip('Next'), findsOneWidget);
      final mini = rectOf(tester, find.byType(GlassMiniPlayer));
      final search = rectOf(tester, find.byTooltip('Search'));
      final settings = rectOf(tester, find.byTooltip('Settings'));
      expect(mini.bottom, lessThanOrEqualTo(settings.top), reason: 'the mini player is above the tabs');
      expect(search.left, greaterThanOrEqualTo(settings.right), reason: 'Search is right of the tabs');
      expect(search.right, lessThanOrEqualTo(size.width - 12));
      expect(tester.takeException(), isNull);

      await tester.drag(list, const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 170));
      expect(tester.takeException(), isNull, reason: 'halfway');
      await tester.pumpAndSettle();
      expect(bar.link.collapsed.value, isTrue);
      expect(collapsedButton, findsOneWidget);
      expect(find.byTooltip('Next'), findsNothing, reason: 'the compact mini player has play / pause only');
      expect(find.byTooltip('Play'), findsOneWidget);
      final row = rectOf(tester, find.byType(GlassMiniPlayer));
      final button = rectOf(tester, collapsedButton);
      final searchNow = rectOf(tester, find.byTooltip('Search'));
      expect(row.center.dy, moreOrLessEquals(searchNow.center.dy), reason: 'one row');
      expect(button.right, lessThanOrEqualTo(row.left));
      expect(row.right, lessThanOrEqualTo(searchNow.left));
      expect(tester.takeException(), isNull);

      await tester.drag(list, const Offset(0, 100));
      await tester.pumpAndSettle();
      expect(bar.link.collapsed.value, isFalse, reason: 'scrolling up');
      expect(collapsedButton, findsNothing);
      expect(find.byTooltip('Next'), findsOneWidget);

      await tester.drag(list, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(collapsedButton, findsOneWidget);
      tester.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(collapsedButton, findsNothing, reason: 'back at the top');
      expect(tester.takeException(), isNull);
    });

    testWidgets('$w px: the round tab button brings the tabs back; the compact mini player opens the player', (
      tester,
    ) async {
      final bar = await show(tester, size);
      await tester.drag(list, const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(GlassMiniPlayer));
      await tester.pump();
      expect(bar.opened, [1]);
      await tester.tap(collapsedButton);
      await tester.pumpAndSettle();
      expect(bar.link.collapsed.value, isFalse);
      expect(collapsedButton, findsNothing);
      expect(find.byTooltip('Settings'), findsOneWidget);
    });

    testWidgets('$w px: with nothing playing the shrunk row is the tab button and Search', (tester) async {
      await show(tester, size, playing: false);
      expect(find.byType(GlassMiniPlayer), findsNothing);
      await tester.drag(list, const Offset(0, -300));
      await tester.pumpAndSettle();
      final button = rectOf(tester, collapsedButton);
      final search = rectOf(tester, find.byTooltip('Search'));
      expect(button.left, 12);
      expect(search.right, size.width - 12);
      expect(button.center.dy, search.center.dy);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$w px: on Search the field is in the bar, and typing puts it alone on the keyboard', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await show(tester, size, tab: PhoneTab.search);
      await tester.pumpAndSettle();
      final field = find.byKey(PhoneBottomBar.searchFieldKey);
      expect(field, findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(collapsedButton, findsOneWidget, reason: 'the tab before Search, as a round button');
      expect(find.byType(GlassMiniPlayer), findsOneWidget, reason: 'full width, on its own row');
      expect(find.byTooltip('Next'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(field);
      tester.view.viewInsets = FakeViewPadding(bottom: size.height * 0.4);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(collapsedButton, findsNothing);
      expect(find.byType(GlassMiniPlayer), findsNothing);
      expect(tester.getRect(field).bottom, lessThan(size.height * 0.6), reason: 'above the keyboard');
      await tester.enterText(field, 'led zeppelin');
      await tester.pump();
      expect(find.byTooltip('Clear'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(field, findsNothing, reason: 'back on the tab before Search');
      expect(find.byTooltip('Settings'), findsOneWidget);
    });
  }

  testWidgets('on Search the round button is Home, whichever tab came before; Close returns to that tab', (
    tester,
  ) async {
    await show(tester, const Size(412, 915), tab: PhoneTab.library);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    final round = tester.widget<Tooltip>(find.descendant(of: collapsedButton, matching: find.byType(Tooltip)));
    expect(round.message, 'Home');
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byKey(PhoneBottomBar.searchFieldKey), findsNothing);
    expect(selectedTab('Library'), findsOneWidget, reason: 'back on Library');

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.tap(collapsedButton);
    await tester.pumpAndSettle();
    expect(find.byKey(PhoneBottomBar.searchFieldKey), findsNothing);
    expect(selectedTab('Home'), findsOneWidget, reason: 'the round button went Home');
  });

  testWidgets('without full motion the bar switches at once', (tester) async {
    prefs.motion = Motion.reduced;
    await show(tester, const Size(412, 915));
    await tester.drag(list, const Offset(0, -300));
    await tester.pump();
    await tester.pump();
    expect(collapsedButton, findsOneWidget);
    expect(find.byTooltip('Next'), findsNothing);
  });

  testWidgets('RIFLAY_NO_TAB_BAR_COLLAPSE keeps the bar full', (tester) async {
    DebugSwitches.noTabBarCollapse = true;
    await show(tester, const Size(412, 915));
    await tester.drag(list, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(collapsedButton, findsNothing);
  });

  testWidgets('the app: the search page leaves its box to the Liquid glass bar', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = PlayerController();
    await tester.runAsync(c.load);
    final orig = FlutterError.onError;
    FlutterError.onError = (d) {
      final s = d.toString();
      if (!s.contains('google_fonts') && !s.contains('GoogleFonts') && !s.contains('MissingPlugin')) orig?.call(d);
    };
    addTearDown(() => FlutterError.onError = orig);
    await tester.pumpWidget(RiflayApp(controller: c));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('Search'));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byKey(PhoneBottomBar.searchFieldKey), findsOneWidget);
    expect(find.byType(SearchBox), findsNothing);

    await tester.runAsync(() => prefs.setTabBar(TabBarStyle.floating));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(PhoneBottomBar.searchFieldKey), findsNothing);
    expect(find.byType(SearchBox), findsOneWidget, reason: 'other tab bars leave the box on the page');
  });

  test('Liquid Kawaii is Kawaii with the Liquid glass tab bar, and is named over it', () async {
    prefs.tabBar = TabBarStyle.capsule;
    await PlayerPreset.kawaii.apply(prefs);
    expect(prefs.tabBar, TabBarStyle.capsule, reason: 'Kawaii leaves the tab bar alone');
    expect(playerPresetName(), 'Kawaii');
    await PlayerPreset.liquidKawaii.apply(prefs);
    expect(prefs.tabBar, TabBarStyle.glass);
    expect(playerPresetName(), 'Liquid Kawaii');
    expect(PlayerPreset.kawaii.changesTo(prefs), 0, reason: 'every other setting is Kawaii\'s');
  });
}
