import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// The browser's downloads. See `browser_files.dart`.
abstract final class BrowserFiles {
  static bool get available => true;

  /// Hands [bytes] to the browser as a download named [name].
  static void save(Uint8List bytes, String name, {String mime = 'application/octet-stream'}) {
    final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
    final url = web.URL.createObjectURL(blob);
    try {
      _click(url, name);
    } finally {
      // After the click has started the download; revoking at once can cancel it in some browsers.
      Future<void>.delayed(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
    }
  }

  /// Has the browser download [url] as [name]. The name only holds for a same-origin URL (or one answering with
  /// `Content-Disposition`); the proxy's are.
  static void saveUrl(Uri url, String name) => _click(url.toString(), name);

  static void _click(String href, String name) {
    final a = web.HTMLAnchorElement()
      ..href = href
      ..download = name
      ..style.display = 'none';
    web.document.body!.append(a);
    a.click();
    a.remove();
  }
}
