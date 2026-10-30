import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/download_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<DownloadPrefs> _load(Map<String, Object> stored) async {
  SharedPreferences.setMockInitialValues(stored);
  final p = DownloadPrefs();
  await p.load();
  return p;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults: Opus, best available, standard FLAC', () async {
    final p = await _load({});
    expect(p.format, DownloadFormat.opus);
    expect(p.kbpsFor(DownloadFormat.opus), isNull);
    expect(p.kbpsFor(DownloadFormat.m4a), isNull);
    expect(p.flac, FlacQuality.standard);
    expect(p.askEveryTime, isTrue);
    expect(p.folder, isNull);
    expect(p.mobileData, isTrue);
    expect(p.choice, const DownloadChoice(DownloadFormat.opus));
  });

  test('the bitrate is kept per format and read back', () async {
    final p = await _load({});
    await p.setKbps(DownloadFormat.opus, 96);
    await p.setKbps(DownloadFormat.m4a, 128);
    await p.setFormat(DownloadFormat.m4a);
    await p.setFlac(FlacQuality.hiRes);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('downloads.kbps.opus'), 96);
    expect(prefs.getInt('downloads.kbps.m4a'), 128);

    final q = DownloadPrefs();
    await q.load();
    expect(q.kbpsFor(DownloadFormat.opus), 96);
    expect(q.kbpsFor(DownloadFormat.m4a), 128);
    expect(q.format, DownloadFormat.m4a);
    expect(q.flac, FlacQuality.hiRes);
    expect(q.choice, const DownloadChoice(DownloadFormat.m4a, kbps: 128));
  });

  test('the old "quality" setting becomes a bitrate for both formats', () async {
    final smaller = await _load({'downloads.quality': 'smaller'});
    expect(smaller.kbpsFor(DownloadFormat.opus), 96);
    expect(smaller.kbpsFor(DownloadFormat.m4a), 96);
    final smallest = await _load({'downloads.quality': 'smallest'});
    expect(smallest.kbpsFor(DownloadFormat.opus), 64);
    expect(smallest.kbpsFor(DownloadFormat.m4a), 64);
    final best = await _load({'downloads.quality': 'best'});
    expect(best.kbpsFor(DownloadFormat.opus), isNull);
  });

  test('a stored per-format bitrate wins over the old quality', () async {
    final p = await _load({'downloads.quality': 'smallest', 'downloads.kbps.opus': 128});
    expect(p.kbpsFor(DownloadFormat.opus), 128);
    expect(p.kbpsFor(DownloadFormat.m4a), 64);
  });

  test('a stored bitrate that is not on offer is ignored', () async {
    final p = await _load({'downloads.kbps.opus': 77, 'downloads.kbps.m4a': 96});
    expect(p.kbpsFor(DownloadFormat.opus), isNull);
    expect(p.kbpsFor(DownloadFormat.m4a), 96);
  });

  test('setKbps(null) removes the key', () async {
    final p = await _load({'downloads.kbps.opus': 64});
    expect(p.kbpsFor(DownloadFormat.opus), 64);
    await p.setKbps(DownloadFormat.opus, null);
    expect(p.kbpsFor(DownloadFormat.opus), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('downloads.kbps.opus'), isFalse);
  });
}
