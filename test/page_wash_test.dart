import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/page_scaffold.dart';

void main() {
  testWidgets('the colour wash behind a page\'s header scrolls away with the page', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
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
          child: PageScaffold(
            title: 'Home',
            gradientColor: Colors.purple,
            slivers: [
              SliverList.list(children: [for (var i = 0; i < 60; i++) SizedBox(height: 60, child: Text('Row $i'))]),
            ],
          ),
        ),
      ),
    );
    final wash = find.byWidgetPredicate(
      (w) => w is AnimatedContainer && (w.decoration as BoxDecoration?)?.gradient != null,
    );
    expect(wash, findsOneWidget);
    final top = tester.getRect(wash).top;
    await tester.drag(find.text('Row 3'), const Offset(0, -200));
    await tester.pumpAndSettle();
    final moved = tester.getRect(find.text('Row 3')).top;
    expect(moved, lessThan(top + 3 * 60 + 100), reason: 'the page did scroll');
    expect(tester.getRect(wash).top, lessThan(top - 100), reason: 'the wash went up with it, not held in place');
  });
}
