import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/downloaded_tools.dart';
import 'package:riflay/services/executable_store.dart';

void main() {
  late Directory root;
  late Directory bin;
  late DownloadedTools tools;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('riflay-tools-test-');
    bin = await Directory('${root.path}/bin').create();
    tools = DownloadedTools(directory: () async => bin);
  });
  tearDown(() async => root.delete(recursive: true));

  test('finds all downloaded variants and partial files with locations and sizes', () async {
    for (final name in ['ffmpeg', 'ffmpeg.exe', 'yt-dlp.exe', 'yt-dlp_linux', 'yt-dlp_macos', 'ffmpeg.part']) {
      await File('${bin.path}/$name').writeAsString('tool');
    }
    await File('${bin.path}/notes.txt').writeAsString('keep');
    final files = await tools.scan();
    expect(files, hasLength(6));
    expect(files.every((file) => file.bytes == 4 && file.path.startsWith(bin.path)), isTrue);
    expect(files.map((file) => file.name).toSet(), {'FFmpeg', 'yt-dlp'});
  });

  test('deletes tools and partial downloads, preserving music, unknown files and nested folders', () async {
    await File('${bin.path}/ffmpeg').writeAsString('tool');
    await File('${bin.path}/yt-dlp_linux.part').writeAsString('partial');
    final keep = File('${bin.path}/notes.txt')..writeAsStringSync('keep');
    final music = File('${root.path}/song.flac')..writeAsStringSync('music');
    final nested = await Directory('${bin.path}/other').create();
    final unknown = File('${nested.path}/ffmpeg')..writeAsStringSync('keep');
    final result = await tools.deleteAll();
    expect(result.removed, 2);
    expect(result.failed, 0);
    expect(await tools.scan(), isEmpty);
    for (final file in [keep, music, unknown]) {
      expect(await file.exists(), isTrue);
    }
    expect((await tools.deleteAll()).removed, 0);
  });

  test('a missing tool folder is empty and cleanup does not create it', () async {
    await bin.delete();
    expect(await tools.scan(), isEmpty);
    expect((await tools.deleteAll()).removed, 0);
    expect(await bin.exists(), isFalse);
  });

  test('ignores links to executables outside the managed folder', () async {
    if (Platform.isWindows) return;
    final system = File('${root.path}/system-ffmpeg')..writeAsStringSync('system');
    await Link('${bin.path}/ffmpeg').create(system.path);
    expect(await tools.scan(), isEmpty);
    await tools.deleteAll();
    expect(await system.readAsString(), 'system');
    expect(await Link('${bin.path}/ffmpeg').exists(), isTrue);
  });

  test('does not follow a symlinked bin directory', () async {
    if (Platform.isWindows) return;
    final outside = await Directory('${root.path}/system-bin').create();
    final system = File('${outside.path}/ffmpeg')..writeAsStringSync('system');
    await bin.delete();
    await Link(bin.path).create(outside.path);
    expect(await tools.scan(), isEmpty);
    await tools.deleteAll();
    expect(await system.readAsString(), 'system');
  });

  test('cleanup waits for a download, and the next lookup sees the removed file', () async {
    final started = Completer<void>(), finish = Completer<void>();
    final download = ExecutableStore.run(() async {
      started.complete();
      await finish.future;
      await File('${bin.path}/ffmpeg').writeAsString('downloaded');
    });
    await started.future;
    final cleanup = tools.deleteAll();
    final nextLookup = ExecutableStore.run(() => File('${bin.path}/ffmpeg').exists());
    finish.complete();
    await download;
    expect((await cleanup).removed, 1);
    expect(await nextLookup, isFalse);
  });

  test('a failed operation does not prevent later scans', () async {
    await expectLater(ExecutableStore.run<void>(() async => throw StateError('failed')), throwsStateError);
    expect(await tools.scan(), isEmpty);
  });
}
