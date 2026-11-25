import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/ytdlp.dart';

void main() {
  final now = DateTime(2026, 11, 25);

  test('a yt-dlp on PATH is used only while its release is recent', () {
    expect(YtDlp.recentRelease('2026.11.10\n', now: now), isTrue);
    expect(YtDlp.recentRelease('2026.10.01.232918', now: now), isTrue, reason: 'nightly');
    // Ubuntu 24.04's apt package: finds no formats today, so our own updated copy is used instead.
    expect(YtDlp.recentRelease('2024.04.09', now: now), isFalse);
    expect(YtDlp.recentRelease('2026.09.01', now: now), isFalse);
    expect(YtDlp.recentRelease('unknown', now: now), isFalse);
  });
}
