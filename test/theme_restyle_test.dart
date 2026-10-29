import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/main.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/services/cover_palette.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Counts its builds and does not touch a colour.
class _Quiet extends StatelessWidget {
  const _Quiet(this.builds);
  final List<int> builds;

  @override
  Widget build(BuildContext context) {
    builds.add(1);
    return const SizedBox(width: 10, height: 10);
  }
}

/// Reads the colours through the context.
class _Reader extends StatelessWidget {
  const _Reader(this.log);
  final List<Color> log;

  @override
  Widget build(BuildContext context) {
    log.add(AppColors.of(context).background);
    return const SizedBox(width: 10, height: 10);
  }
}

/// Reads the colours statically (what most of the app still does).
class _Static extends StatelessWidget {
  const _Static(this.log);
  final List<Color> log;

  @override
  Widget build(BuildContext context) {
    log.add(AppColors.solidBackground);
    return const SizedBox(width: 10, height: 10);
  }
}

class _Host extends StatefulWidget {
  const _Host(this.seen, this.themed);
  final List<Color> seen, themed;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  void _restyle() {
    setState(() {});
    restyleTree(context as Element);
  }

  @override
  void initState() {
    super.initState();
    Appearance.instance.addListener(_restyle);
  }

  @override
  void dispose() {
    Appearance.instance.removeListener(_restyle);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: appThemeNow(),
    themeAnimationDuration: Duration.zero,
    builder: (context, child) => AppColorsScope(colors: AppColorsScope.current(), child: child!),
    home: Builder(
      builder: (context) {
        widget.themed.add(Theme.of(context).colorScheme.primary);
        return _Reader(widget.seen);
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a palette change rebuilds what reads colours and nothing else', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final a = Appearance.instance;
    await a.reset();
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RiflayApp(controller: PlayerController()));
    await tester.pump(const Duration(milliseconds: 100));

    final quiet = <int>[], quietFree = <int>[], reader = <Color>[], legacy = <Color>[];
    // One instance, as a screen that is not rebuilt from above would be.
    final page = Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          ColorFree(child: _Quiet(quietFree)),
          _Quiet(quiet),
          _Reader(reader),
          _Static(legacy),
          const Text('words'),
        ],
      ),
    );
    tester.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute<void>(builder: (_) => page));
    await tester.pump(const Duration(seconds: 1));
    quiet.clear();
    quietFree.clear();
    reader.clear();
    legacy.clear();

    final before = a.palette.background;
    await a.setTheme(ThemeChoice.nord);
    await tester.pump();
    expect(a.palette.background, isNot(before));

    expect(quietFree, isEmpty, reason: 'a colour-free subtree is never rebuilt');
    expect(reader, hasLength(1), reason: 'built once, through its dependency');
    expect(reader.single.toARGB32(), a.palette.background.toARGB32());
    expect(legacy, isNotEmpty, reason: 'a static reader still follows');
    expect(legacy.last, a.palette.background);
    await tester.pump(const Duration(milliseconds: 400)); // Material eases its text style
    expect(DefaultTextStyle.of(tester.element(find.text('words'))).style.color, a.palette.textPrimary);

    // Same colours again: the scope does not notify, so only the sweep (which cannot tell who reads what) runs.
    reader.clear();
    quietFree.clear();
    await a.setTheme(ThemeChoice.nord);
    await tester.pump();
    expect(quietFree, isEmpty);
    expect(reader.length, lessThanOrEqualTo(1));
    await a.reset();
  });

  testWidgets('the cover-colour fade still arrives at the target palette', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final a = Appearance.instance;
    await a.reset();
    await a.setTheme(ThemeChoice.dynamic);
    final seen = <Color>[];
    final themed = <Color>[];
    // What RiflayApp does on every step, without a player behind it.
    await tester.pumpWidget(_Host(seen, themed));
    await tester.pump();

    final start = a.palette;
    a.setCoverColors(const CoverColors(Color(0xFFD08020), Color(0xFFE04060)));
    var notified = 0;
    a.addListener(() => notified++);
    for (var t = 0; t < 900; t += 16) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(a.palette, isNot(start));
    expect(seen.last.toARGB32(), a.palette.background.toARGB32(), reason: 'the screen ended on the target');
    expect(themed.last, a.palette.accent, reason: 'and so did the theme');
    expect(seen.toSet().length, greaterThan(3), reason: 'it eased through steps, not one jump');
    expect(notified, inInclusiveRange(2, 14));
    await a.reset();
  });

  test('the theme for a palette is built once, then answered from the cache', () async {
    SharedPreferences.setMockInitialValues({});
    final a = Appearance.instance;
    await a.reset();
    final first = appThemeNow();
    final s1 = themeCacheStats;
    expect(appThemeNow(), same(first));
    expect(themeCacheStats.cached, s1.cached + 1);
    expect(themeCacheStats.built, s1.built);

    await a.setTheme(ThemeChoice.nord);
    final nord = appThemeNow();
    expect(nord, isNot(same(first)));
    await a.setTheme(ThemeChoice.standard);
    expect(appThemeNow(), same(first), reason: 'a palette that comes back is not built again');
    expect(nord.colorScheme.primary, ThemeChoice.nord.palette.accent);
    expect(first.textTheme.bodyMedium?.fontFamily, 'Figtree', reason: 'the bundled typeface, not a download');
    await a.reset();
  });
}
