import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Words people read go through `tr` (AGENT.md › Translations). This looks for English typed straight into the
/// places a screen shows text: `Text('…')`, `tooltip: '…'`, `title: '…'`, `labelText: '…'` and the like.
void main() {
  // Names that stay as they are in every language.
  const names = {
    'Riflay', 'YouTube Music', 'YouTube', 'Spotify', 'Wrap', 'Riflay Wrap', 'Figtree', 'Matugen', 'Bit-perfect',
    'Direct USB', 'Discord Rich Presence', 'ListenBrainz', 'Last.fm', 'Hex', 'Aa', 'DSP', 'GNU AGPL v3.0', //
    'Riflay video', 'Riflay video check', // mpv window titles, never shown
  };
  // Files whose words stay English on purpose.
  const englishFiles = {
    // Detail stats: copied into bug reports, so its rows stay in the words the code and issues use.
    'lib/ui/widgets/stats_for_nerds.dart',
  };
  final ui = RegExp(
    r'''(?:\bText\(|\bTextSpan\(text:|\b(?:tooltip|title|subtitle|label|hintText|labelText|helperText|errorText|'''
    r'''message|semanticLabel|semanticsLabel|dialogTitle|kicker|headline|body|content|description|'''
    r'''channelDescription|heading)\s*:\s*)\s*(?:const\s+)?(?:Text\()?\s*('|")((?:(?!\1)[^\\\n]|\\.)*)\1''',
  );
  // Prose: two words, or one capitalised word, once interpolations are taken out.
  final prose = RegExp(r"[A-Za-z][A-Za-z'’]+[ ,.:;!?]+[a-z]{2,}|^[A-Z][a-z]{2,}[.…]?$");

  test('no English typed into what a screen shows', () {
    final found = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final path = f.path.replaceAll(r'\', '/');
      if (!path.endsWith('.dart') || path.contains('/l10n/') || englishFiles.contains(path)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        for (final m in ui.allMatches(lines[i])) {
          final literal = m[2]!;
          if (names.contains(literal) || literal.contains('://')) continue;
          final words = literal.replaceAll(r"\'", "'").replaceAll(RegExp(r'\$\{[^}]*\}|\$\w+'), ' ').trim();
          if (prose.hasMatch(words)) found.add('$path:${i + 1}: $literal');
        }
      }
    }
    expect(found, isEmpty, reason: 'put these in lib/l10n/app_*.arb and read them through tr:\n${found.join('\n')}');
  });
}
