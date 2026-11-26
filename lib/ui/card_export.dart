import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../platform/browser_files.dart';
import '../platform/host.dart';
import '../services/language.dart';

/// A shown card (a Wrap card, a lyric card) as a PNG, at [pixelRatio] times its size.
Future<Uint8List> renderCard(GlobalKey key, {double pixelRatio = 3}) async {
  final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) throw StateError('card not on screen');
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final ByteData? data;
  try {
    data = await image.toByteData(format: ui.ImageByteFormat.png);
  } finally {
    image.dispose();
  }
  final bytes = data?.buffer.asUint8List();
  if (bytes == null) throw StateError('no image');
  return bytes;
}

/// Saves a card to Downloads (the app's documents where there is none; the browser's downloads on the web);
/// the saved file's name, or null if it failed.
Future<String?> saveCard(
  BuildContext context,
  Future<Uint8List> Function() render,
  String fileName, {
  bool quiet = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await render();
    if (BrowserFiles.available) {
      BrowserFiles.save(bytes, fileName, mime: 'image/png');
      if (!quiet) messenger.showSnackBar(SnackBar(content: Text(tr.savedFile(fileName))));
      return fileName;
    }
    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    if (!quiet) messenger.showSnackBar(SnackBar(content: Text(tr.savedFile(p.basename(file.path)))));
    return p.basename(file.path);
  } catch (e) {
    debugPrint('Saving a card failed: $e');
    messenger.showSnackBar(SnackBar(content: Text(tr.couldntSaveImage)));
    return null;
  }
}

/// The phone's share sheet with a card and a caption. A computer has none: the card is saved and the caption
/// copied, to paste beside it.
Future<void> shareCard(
  BuildContext context,
  Future<Uint8List> Function() render,
  String fileName, {
  required String caption,
  required String subject,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (Host.isAndroid) {
    try {
      final bytes = await render();
      // The cache's shared/ folder: the one the share sheet may lend out (res/xml/update_file_paths.xml).
      final dir = Directory(p.join((await getTemporaryDirectory()).path, 'shared'))..createSync(recursive: true);
      final file = File(p.join(dir.path, fileName));
      await file.writeAsBytes(bytes, flush: true);
      final shown = await const MethodChannel('riflay/share')
          .invokeMethod<bool>('share', {'text': caption, 'subject': subject, 'file': file.path, 'mime': 'image/png'});
      if (shown ?? false) return;
    } catch (e) {
      debugPrint('Sharing a card failed: $e');
    }
  }
  if (!context.mounted) return;
  final name = await saveCard(context, render, fileName, quiet: true);
  if (name == null) return;
  await Clipboard.setData(ClipboardData(text: caption));
  messenger.showSnackBar(SnackBar(content: Text(tr.savedCaptionCopied(name))));
}
