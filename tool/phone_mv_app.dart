// The real app on a phone, put in the state to look at: a preset applied, Video mode on, a YouTube Music song with
// its music video playing and Now Playing open. Turn the phone and take screenshots with adb (tool/phone_mv.sh).
//   flutter run -t tool/phone_mv_app.dart --android-project-arg=riflayDev=true
// RIFLAY_PHONE_PRESET (dart-define): a preset's name ("Liquid Stacked" by default); RIFLAY_PHONE_QUERY: the song.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:riflay/main.dart' as app;
import 'package:riflay/services/beta_features.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/player_presets.dart';
import 'package:riflay/ui/player_scope.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/page_scaffold.dart';

Element? _find(bool Function(Element) test) {
  Element? found;
  void visit(Element e) {
    if (found != null) return;
    if (test(e)) {
      found = e;
      return;
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

Future<void> main() async {
  const query = String.fromEnvironment('RIFLAY_PHONE_QUERY', defaultValue: 'Houshou Marine Kyapi');
  const preset = String.fromEnvironment('RIFLAY_PHONE_PRESET', defaultValue: 'Liquid Stacked');
  await app.main(const []);
  Element? page;
  while ((page = _find((e) => e.widget is PageScaffold)) == null) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  await BetaFeatures.instance.set(BetaFeature.videoMode, true);
  await PlayerPreset.all.firstWhere((p) => p.name == preset).apply(LayoutPrefs.instance);
  final c = PlayerScope.read(page!);
  final found = await c.searchYoutube(query);
  final song = found.firstWhere((t) => t.videoId != null);
  debugPrint('PHONE playing ${song.title} · ${song.artist} ($preset)');
  await c.playList([song], 0, from: 'Recently played');
  ShellScope.of(_find((e) => e.widget is PageScaffold)!).openNowPlaying();
}
