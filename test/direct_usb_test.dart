import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/direct_usb.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test('a pipe that stops by itself is a failure, and Settings can say so', () {
    final d = DirectUsbOutput();
    d.read({'running': true, 'fifo': '/cache/direct_usb.fifo', 'route': 'none'});
    expect(d.failed, isFalse);
    d.read({'running': false, 'error': 'Direct USB stopped: UnsatisfiedLinkError'});
    expect(d.failed, isTrue);
    expect(d.error, 'Direct USB stopped: UnsatisfiedLinkError');
  });

  test('the app closing while Direct USB starts leaves it off once', () async {
    SharedPreferences.setMockInitialValues({'directUsb.starting.v1': true});
    expect(await DirectUsbOutput.closedLastTime(), isTrue);
    expect(await DirectUsbOutput.closedLastTime(), isFalse, reason: 'told once, then it may try again');
    SharedPreferences.setMockInitialValues({});
    expect(await DirectUsbOutput.closedLastTime(), isFalse);
  });
}
