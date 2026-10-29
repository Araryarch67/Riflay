import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/youtube_stream.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/track_row.dart';
import 'package:riflay/ui/ytmusic_edit.dart' show DownloadButton;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('a phone prefetches only on Wi-Fi or ethernet', () {
    expect(YoutubeStream.shouldPrefetchAhead(phone: true, unmetered: true), isTrue);
    expect(YoutubeStream.shouldPrefetchAhead(phone: true, unmetered: false), isFalse);
  });

  test('a computer always prefetches, whatever the network', () {
    expect(YoutubeStream.shouldPrefetchAhead(phone: false, unmetered: false), isTrue);
    expect(YoutubeStream.shouldPrefetchAhead(phone: false, unmetered: true), isTrue);
  });

  test('battery saver stops it everywhere', () {
    expect(YoutubeStream.shouldPrefetchAhead(phone: true, unmetered: true, batterySaver: true), isFalse);
    expect(YoutubeStream.shouldPrefetchAhead(phone: false, unmetered: true, batterySaver: true), isFalse);
  });

  test('the row download button: full, compact, then gone', () {
    expect(downloadButtonFor(300), RowDownload.full);
    expect(downloadButtonFor(299), RowDownload.compact);
    expect(downloadButtonFor(240), RowDownload.compact);
    expect(downloadButtonFor(239), RowDownload.none);
    for (final w in [320.0, 360.0, 375.0]) {
      expect(downloadButtonFor(w - 8), isNot(RowDownload.none));
    }
  });

  for (final width in const <double>[240, 320, 360, 375, 800]) {
    testWidgets('a streamed song\'s row fits ${width.toInt()} px wide, download button shown from 240', (tester) async {
      SharedPreferences.setMockInitialValues({'library.v1': jsonEncode(<Object>[])});
      final c = PlayerController();
      await tester.runAsync(c.load);
      tester.view.physicalSize = Size(width, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final orig = FlutterError.onError;
      FlutterError.onError = (d) {
        final s = d.toString();
        if (!s.contains('google_fonts') && !s.contains('GoogleFonts') && !s.contains('MissingPlugin')) orig?.call(d);
      };
      addTearDown(() => FlutterError.onError = orig);
      void nop() {}
      await tester.pumpWidget(
        PlayerScope(
          controller: c,
          child: MaterialApp(
            home: Builder(
              builder: (context) => ShellScope(
                compact: true,
                width: width,
                open: (_, {location}) {},
                openCollection: (_) {},
                openQueue: nop,
                openNowPlaying: nop,
                openLyrics: nop,
                openDownloads: nop,
                importFromYoutube: nop,
                addFiles: nop,
                addFolder: null,
                child: Scaffold(
                  body: TrackRow(
                    track: Track.youtube(
                      videoId: 'dQw4w9WgXcQ',
                      title: 'A fairly long song title that has to be cut',
                      artist: 'An artist with a long name',
                    ),
                    onTap: nop,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.byType(DownloadButton), findsOneWidget);
    });
  }
}
