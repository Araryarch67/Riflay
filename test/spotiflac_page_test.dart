import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:riflay/services/language.dart';
import 'package:riflay/services/spotiflac.dart';
import 'package:riflay/ui/pages/spotiflac_page.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/spotiflac_notice.dart';

class _Extensions extends Spotiflac {
  final entry = <String, dynamic>{
    'id': 'example',
    'display_name': 'Example',
    'version': '1',
    'description': '',
    'has_metadata_provider': true,
    'has_lyrics_provider': true,
    'has_download_provider': false,
  };

  @override
  Future<void> load() async {}

  @override
  Future<void> refresh() async => notifyListeners();

  @override
  Future<List<Map<String, dynamic>>> registry(String url, {http.Client? client}) async => [entry];

  @override
  Future<void> installFromRegistry(Map<String, dynamic> entry, {http.Client? client}) async {
    plugins = [
      {...entry, 'enabled': false},
    ];
    notifyListeners();
  }

  @override
  Future<void> remove(String id) async {
    plugins = [];
    notifyListeners();
  }
}

void main() {
  testWidgets('installed extensions leave Available and return after removal', (tester) async {
    final engine = _Extensions();
    addTearDown(engine.dispose);
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ShellScope(
          compact: false,
          width: 1000,
          open: (_, {location}) {},
          openCollection: (_) {},
          openQueue: () {},
          openNowPlaying: () {},
          openLyrics: () {},
          openDownloads: () {},
          importFromYoutube: () {},
          addFiles: () {},
          addFolder: null,
          child: Scaffold(body: SpotiflacPage(engine: engine)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SpotiflacNotice), findsOneWidget);
    expect(find.text(tr.spotiflacDownloadOnly), findsOneWidget);
    await tester.tap(find.byTooltip(tr.spotiflacLoadRepository));
    await tester.pumpAndSettle();
    expect(find.text(tr.available), findsOneWidget);
    await tester.tap(find.text(tr.install));
    await tester.pumpAndSettle();
    expect(find.text('Example'), findsOneWidget);
    expect(find.text(tr.available), findsNothing);
    expect(find.text(tr.install), findsNothing);
    expect(find.text(tr.spotiflacMetadataCapability), findsOneWidget);
    expect(find.text(tr.lyrics), findsOneWidget);
    expect(find.text(tr.spotiflacMetadataOnly), findsOneWidget);
    engine.plugins.single['has_download_provider'] = true;
    await engine.refresh();
    await tester.pumpAndSettle();
    expect(find.text(tr.spotiflacMetadataOnly), findsNothing);
    expect(find.text(tr.spotiflacAudioProvider), findsOneWidget);
    expect(find.text(tr.download), findsOneWidget);
    await tester.tap(find.text(tr.remove));
    await tester.pumpAndSettle();
    expect(find.text(tr.available), findsOneWidget);
    expect(find.text(tr.install), findsOneWidget);
  });
}
