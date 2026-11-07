import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/ui/widgets/app_dialog.dart';

Future<BuildContext> _host(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late BuildContext host;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          host = context;
          return const Scaffold();
        },
      ),
    ),
  );
  return host;
}

Widget _withDelete(BuildContext context) => AppDialog(
  title: 'Edit download',
  content: const Text('Body'),
  destructive: DestructiveButton(onPressed: () {}, child: const Text('Delete file')),
  actions: [
    TextButton(onPressed: () {}, child: const Text('Cancel')),
    FilledButton(onPressed: () {}, child: const Text('Save')),
  ],
);

// The dialog's card (Dialog itself fills the screen to centre it).
final _card = find.descendant(of: find.byType(Dialog), matching: find.byType(Material)).first;

void main() {
  testWidgets('on a computer the destructive action sits on the left of the same row as the others', (tester) async {
    final host = await _host(tester, const Size(1000, 700));
    showDialog<void>(context: host, builder: _withDelete);
    await tester.pumpAndSettle();
    final delete = tester.getRect(find.text('Delete file'));
    final cancel = tester.getRect(find.text('Cancel'));
    final save = tester.getRect(find.text('Save'));
    expect(delete.center.dy, moreOrLessEquals(save.center.dy, epsilon: 1));
    expect(delete.right, lessThan(cancel.left));
    expect(cancel.right, lessThan(save.left));
    // The dialog keeps its width whatever it shows.
    expect(tester.getSize(_card).width, DialogWidth.regular);
  });

  testWidgets('on a narrow phone the destructive action goes under the others instead of squeezing them', (
    tester,
  ) async {
    final host = await _host(tester, const Size(300, 700));
    showDialog<void>(
      context: host,
      builder: (context) => AppDialog(
        title: 'Edit download',
        content: const Text('Body'),
        destructive: DestructiveButton(onPressed: () {}, child: const Text('Delete offline file')),
        actions: [
          TextButton(onPressed: () {}, child: const Text('Cancel')),
          FilledButton(onPressed: () {}, child: const Text('Download FLAC')),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.text('Delete offline file')).top,
      greaterThan(tester.getRect(find.text('Cancel')).bottom),
    );
    expect(tester.getSize(_card).width, 300 - 32, reason: '16 px either side on a phone');
  });

  testWidgets('confirmDialog answers true only for its button', (tester) async {
    final host = await _host(tester, const Size(800, 600));
    var answer = confirmDialog(
      host,
      title: 'Delete?',
      body: 'Gone for good.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    await tester.pumpAndSettle();
    expect(find.text('Gone for good.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await answer, isFalse);

    answer = confirmDialog(host, title: 'Delete?', body: 'Gone for good.', confirmLabel: 'Delete', destructive: true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(await answer, isTrue);
  });
}
