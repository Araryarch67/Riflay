import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/manual_audio.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/sources/music_sources.dart';
import 'package:riflay/ui/widgets/audio_source_picker.dart';

class _Controller extends PlayerController {
  final local = Track.fromUri(Uri.file('/music/Kyapi.m4a'))
      .copyWith(title: 'Kyapi', artist: 'Houshou Marine', audioQuality: 'FLAC · 24-bit / 48 kHz');
  ManualAudioChoice? selected;
  bool changed = false;
  @override
  List<Track> get library => [local];
  @override
  ManualAudioChoice? audioChoice(Track track) => selected;
  @override
  Future<void> setAudioChoice(Track track, ManualAudioChoice? choice) async {
    selected = choice;
    changed = true;
  }
}

void main() {
  testWidgets('audio picker exposes automatic, YouTube and measured library audio', (tester) async {
    final c = _Controller();
    final monochrome = MusicSources.instance.monochrome;
    MusicSources.instance.monochrome = false;
    addTearDown(() async {
      MusicSources.instance.monochrome = monochrome;
      await tester.runAsync(() async {
        c.dispose();
      });
    });
    final song = Track.youtube(videoId: 'pickerSong1', title: 'きゃぴ - Kyapi', artist: 'Houshou Marine');
    await tester.pumpWidget(
      PlayerScope(
        controller: c,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(onPressed: () => showAudioSourcePicker(context, song), child: const Text('Sources')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Sources'));
    await tester.pumpAndSettle();
    expect(find.text('Automatic (Smart Merge)'), findsOneWidget);
    expect(find.text('YouTube Music'), findsOneWidget);
    expect(find.textContaining('FLAC · 24-bit / 48 kHz'), findsOneWidget);
    await tester.tap(find.text('Kyapi'));
    await tester.pumpAndSettle();
    expect(c.selected?.track, same(c.local));
    expect(find.text('Audio source'), findsNothing);
    await tester.tap(find.text('Sources'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Automatic (Smart Merge)'));
    await tester.pumpAndSettle();
    expect(c.changed, isTrue);
    expect(c.selected, isNull);
  });
}
