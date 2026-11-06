import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/downloaded_tools.dart';
import 'package:riflay/ui/pages/downloaded_tools_page.dart';

class _Tools extends DownloadedTools {
  var files = [const DownloadedTool(name: 'FFmpeg', path: '/riflay/bin/ffmpeg', bytes: 1024)];
  var deletes = 0;
  var failScan = false;
  var failDelete = false;

  @override
  Future<List<DownloadedTool>> scan() async {
    if (failScan) throw StateError('private diagnostic');
    return files;
  }

  @override
  Future<DeleteToolsResult> deleteAll() async {
    deletes++;
    if (failDelete) return const DeleteToolsResult(removed: 0, failed: 1);
    files = [];
    return const DeleteToolsResult(removed: 1, failed: 0);
  }
}

void main() {
  Future<_Tools> show(WidgetTester tester) async {
    final tools = _Tools();
    await tester.pumpWidget(MaterialApp(home: DownloadedToolsPage(tools: tools)));
    await tester.pumpAndSettle();
    return tools;
  }

  testWidgets('lists the actual path and size, cancel preserves files, confirm deletes all', (tester) async {
    final tools = await show(tester);
    expect(find.text('/riflay/bin/ffmpeg'), findsOneWidget);
    expect(find.textContaining('FFmpeg · '), findsOneWidget);
    await tester.tap(find.text('Delete all executables'));
    await tester.pumpAndSettle();
    expect(tools.deletes, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tools.deletes, 0);
    await tester.tap(find.text('Delete all executables'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(tools.deletes, 1);
    expect(find.text('No downloaded executables found.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });

  testWidgets('failed scan shows a calm error and allows retry', (tester) async {
    final tools = await show(tester);
    tools.failScan = true;
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't find downloaded executables. Try again."), findsOneWidget);
    expect(find.textContaining('private diagnostic'), findsNothing);
    tools.failScan = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('/riflay/bin/ffmpeg'), findsOneWidget);
  });

  testWidgets('partial deletion keeps remaining files visible and reports failure', (tester) async {
    final tools = await show(tester);
    tools.failDelete = true;
    await tester.tap(find.text('Delete all executables'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text("Some executables couldn't be deleted. Try again."), findsOneWidget);
    expect(find.text('/riflay/bin/ffmpeg'), findsOneWidget);
  });
}
