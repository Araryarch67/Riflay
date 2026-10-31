import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../platform/background.dart';
import '../../platform/host.dart';
import '../../services/listen_together/qr_code.dart';

/// Displays a room code that another Riflay can scan to join.
class ListenQrDialog extends StatelessWidget {
  const ListenQrDialog({super.key, required this.code});
  final String code;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Session QR code'),
    content: SizedBox(
      width: 280,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: listenQrPayload(code),
              backgroundColor: Colors.white,
              padding: const EdgeInsets.all(16),
              semanticsLabel: 'Listening session QR code',
            ),
            const SizedBox(height: 16),
            Text(code, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('In Riflay on another device, open Listen together and choose Scan QR code.'),
          ],
        ),
      ),
    ),
    actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
  );
}

/// Camera scanning on supported devices; QR image import also works on desktops.
class ListenQrScanner extends StatefulWidget {
  const ListenQrScanner({super.key});

  @override
  State<ListenQrScanner> createState() => _ListenQrScannerState();
}

class _ListenQrScannerState extends State<ListenQrScanner> {
  bool _done = false;
  bool _readingImage = false;
  String? _error;

  bool get _camera => Host.isAndroid || Host.isIOS || Host.isMacOS;

  void _read(Iterable<String?> values) {
    if (_done || !mounted) return;
    if (values.isEmpty) return;
    for (final value in values) {
      final code = value == null ? null : listenCodeFromQr(value);
      if (code != null) {
        _done = true;
        Navigator.of(context).pop(code);
        return;
      }
    }
    setState(() => _error = 'That QR code is not a Riflay session code.');
  }

  Future<void> _image() async {
    setState(() {
      _readingImage = true;
      _error = null;
    });
    try {
      final picked = await FilePicker.pickFiles(type: FileType.image);
      if (!mounted || _done || picked.isEmpty) return;
      final bytes = await picked.single.readAsBytes();
      final code = await inBackground(() => listenCodeFromImage(bytes));
      if (!mounted || _done) return;
      if (code == null) {
        setState(() => _error = "Couldn't find a Riflay session code in that image.");
      } else {
        _read([code]);
      }
    } catch (e) {
      debugPrint('Listen together: QR image: $e');
      if (mounted) setState(() => _error = "Couldn't read that image. Try another one.");
    } finally {
      if (mounted) setState(() => _readingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan QR code')),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: _camera
                ? MobileScanner(
                    onDetect: (capture) => _read(
                      capture.barcodes
                          .where((barcode) => barcode.format == BarcodeFormat.qrCode)
                          .map((barcode) => barcode.rawValue),
                    ),
                    errorBuilder: (context, error) => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Camera unavailable. Allow camera access in your device settings, or open a QR image.',
                        ),
                      ),
                    ),
                  )
                : const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Open an image of the session QR code to join.'),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_camera) const Text('Point the camera at the session QR code shown in Riflay.'),
                if (_error != null) ...[const SizedBox(height: 8), Semantics(liveRegion: true, child: Text(_error!))],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _readingImage ? null : _image,
                  icon: const Icon(Icons.image_outlined),
                  label: Text(_readingImage ? 'Reading image…' : 'Open QR image'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
