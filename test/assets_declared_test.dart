import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every asset the app loads by name is bundled (listed in pubspec.yaml)', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final listed = RegExp(r'^\s*-\s*(assets/\S+)', multiLine: true).allMatches(pubspec).map((m) => m[1]!).toList();
    final missing = <String>{};
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      for (final m in RegExp(r'''['"](assets/[^'"$]+\.\w+)['"]''').allMatches(file.readAsStringSync())) {
        final asset = m[1]!;
        if (!listed.any((l) => l == asset || (l.endsWith('/') && asset.startsWith(l)))) missing.add(asset);
      }
    }
    expect(missing, isEmpty, reason: 'add them under flutter: assets: in pubspec.yaml');
  });
}
