import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/ui/player/player_parts.dart';

void main() {
  testWidgets('a downloaded song shares the link it came from, not only its name', (tester) async {
    final copied = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      },
    );
    final downloaded = Track(
      id: 'file:///music/kyapi.opus',
      uri: Uri.file('/music/kyapi.opus'),
      title: 'Kyapi',
      artist: 'Houshou Marine',
      sourceUrl: 'https://music.youtube.com/watch?v=abc123',
    );
    final own = Track(id: 'file:///music/mine.flac', uri: Uri.file('/music/mine.flac'), title: 'Mine', artist: 'Me');
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await shareTrack(ctx, downloaded);
    await shareTrack(ctx, own);
    await tester.pump();
    expect(copied, ['https://music.youtube.com/watch?v=abc123', 'Mine – Me']);
  });
}
