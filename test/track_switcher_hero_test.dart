import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/ui/player/player_common.dart';

void main() {
  testWidgets('opening the player during a song crossfade has one artwork Hero', (tester) async {
    final track = ValueNotifier(0);
    addTearDown(track.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: track,
                  builder: (_, value, _) => TrackSwitcher(
                    trackId: '$value',
                    child: Hero(key: ValueKey(value), tag: 'now-playing-art', child: Text('Track $value')),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(
                        body: Hero(tag: 'now-playing-art', child: Text('Player')),
                      ),
                    ),
                  ),
                  child: const Text('Open player'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    track.value = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Open player'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Player'), findsOneWidget);
  });
}
