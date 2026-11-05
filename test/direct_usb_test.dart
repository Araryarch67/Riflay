import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/direct_usb.dart';

void main() {
  test('reads what DirectUsb.kt reports: the DAC, its permission, the route and the formats', () {
    final d = DirectUsbOutput();
    expect(d.running, isFalse);
    expect(d.hasDac, isFalse);
    d.read({
      'running': true,
      'fifo': '/cache/direct_usb.fifo',
      'devices': [
        {'name': 'CDS.KT USB Audio', 'permission': false},
      ],
      'route': 'direct',
      'routeFormat': '24-bit / 96000 Hz',
      'streamFormat': '32-bit / 96000 Hz / 2 ch',
      'underruns': 2,
      'error': null,
      'log': ['activated'],
    });
    expect(d.running, isTrue);
    expect(d.fifo, '/cache/direct_usb.fifo');
    expect(d.hasDac, isTrue);
    expect(d.needsPermission, isTrue);
    expect(d.devices.single.name, 'CDS.KT USB Audio');
    expect(d.route, 'direct');
    expect(d.routeFormat, '24-bit / 96000 Hz');
    expect(d.underruns, 2);
    expect(d.log, ['activated']);

    d.read({'running': false, 'fifo': '/cache/direct_usb.fifo', 'devices': <Object>[]});
    expect(d.running, isFalse, reason: 'a pipe that is not running is no pipe for mpv');
    expect(d.hasDac, isFalse);
  });
}
