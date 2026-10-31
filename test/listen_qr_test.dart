import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:riflay/services/listen_together/qr_code.dart';
import 'package:riflay/ui/pages/listen_qr.dart';

void main() {
  test('QR payload is only the normalized code, never an invite URL', () {
    expect(listenQrPayload('k7q 2xm'), 'K7Q2XM');
    expect(listenQrPayload('abcde-fghjk'), 'ABCDEFGHJK');
    for (final value in ['https://example.com', 'riflay://listen?code=K7Q2XM', '', '000000', 'random text']) {
      expect(listenCodeFromQr(value), isNull);
      expect(() => listenQrPayload(value), throwsArgumentError);
    }
  });

  test('invalid images and images without a QR code are rejected', () {
    expect(listenCodeFromImage(Uint8List.fromList([1, 2, 3])), isNull);
    final blank = img.Image(width: 100, height: 100);
    img.fill(blank, color: img.ColorRgb8(255, 255, 255));
    expect(listenCodeFromImage(img.encodePng(blank)), isNull);
  });

  for (final code in ['K7Q2XM', 'ABCDE-FGHJK']) {
    testWidgets('displayed QR decodes back to the room code: $code', (tester) async {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: boundary,
              child: ListenQrDialog(code: code),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final decoded = await tester.runAsync(() async {
        final screenshot = await render.toImage(pixelRatio: 2);
        final png = await screenshot.toByteData(format: ui.ImageByteFormat.png);
        screenshot.dispose();
        return listenCodeFromImage(png!.buffer.asUint8List());
      });
      expect(decoded, listenQrPayload(code));
      expect(find.text('Copy invite link'), findsNothing);
    });
  }

  testWidgets('desktop scanner offers image import and can be cancelled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ListenQrScanner())),
              child: const Text('Open scanner'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open scanner'));
    await tester.pumpAndSettle();
    expect(find.text('Open QR image'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Open scanner'), findsOneWidget);
  });
}
