import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/ui/pages/search/search_parts.dart';
import 'package:riflay/ui/widgets/skeleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final prefs = LayoutPrefs.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await prefs.reset();
    await prefs.setPerformance(PerformanceMode.balanced);
  });
  tearDown(() async {
    await prefs.setPerformance(PerformanceMode.balanced);
    await prefs.reset();
  });

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('skeletons share one clock that runs only while one is on screen, and slowly', (tester) async {
    expect(SkeletonClock.users, 0);
    await tester.pumpWidget(host(const SkeletonList(count: 3)));
    // Every box asks for the clock, but there is one beat for all of them.
    expect(SkeletonClock.users, greaterThan(0));
    final before = SkeletonClock.phase.value;
    await tester.pump(const Duration(milliseconds: 400));
    expect(SkeletonClock.phase.value, isNot(before), reason: 'the shimmer moves');
    // About ten beats a second, not one per frame: 400 ms is a handful of changes.
    var changes = 0;
    void count() => changes++;
    SkeletonClock.phase.addListener(count);
    await tester.pump(const Duration(milliseconds: 1000));
    SkeletonClock.phase.removeListener(count);
    expect(changes, inInclusiveRange(7, 12));

    await tester.pumpWidget(const SizedBox());
    expect(SkeletonClock.users, 0, reason: 'nothing mounted: the clock is given up');
  });

  testWidgets('Lightweight and reduced motion keep skeletons still', (tester) async {
    await prefs.setPerformance(PerformanceMode.lightweight);
    await tester.pumpWidget(host(const SkeletonList(count: 3)));
    expect(SkeletonClock.users, 0);
    await tester.pumpWidget(const SizedBox());

    await prefs.setPerformance(PerformanceMode.balanced);
    await prefs.setMotion(Motion.off);
    await tester.pumpWidget(host(const SkeletonBox(width: 40, height: 10)));
    expect(SkeletonClock.users, 0);
  });

  testWidgets('a skeleton under another page takes no beats', (tester) async {
    await tester.pumpWidget(host(const TickerMode(enabled: false, child: SkeletonBox(width: 40, height: 10))));
    expect(SkeletonClock.users, 0);
    await tester.pumpWidget(host(const TickerMode(enabled: true, child: SkeletonBox(width: 40, height: 10))));
    expect(SkeletonClock.users, 1);
    await tester.pumpWidget(const SizedBox());
    expect(SkeletonClock.users, 0);
  });

  testWidgets('the shapes: rows with a cover and two text bars, a shelf of cards, a page', (tester) async {
    await tester.pumpWidget(host(const SkeletonList(count: 5)));
    expect(find.byType(SkeletonRow), findsNWidgets(5));
    await tester.pumpWidget(host(const SkeletonCardShelf(count: 4)));
    expect(find.byType(SkeletonBox), findsNWidgets(4 * 3));
    await tester.pumpWidget(host(const SkeletonPage(rows: 3)));
    expect(find.byType(SkeletonRow), findsNWidgets(3));
    await tester.pumpWidget(host(const SkeletonText(lines: 3)));
    expect(find.byType(SkeletonBox), findsNWidgets(3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a search waiting for results shows rows, not a spinner', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CustomScrollView(slivers: [SearchSpinner(pad: 16)])),
      ),
    );
    expect(find.byType(SkeletonList), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
