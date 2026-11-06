import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/bluetooth_codec.dart';

void main() {
  test("Android's codec numbers and masks in words", () {
    final ldac = BluetoothOutput.fromAndroid({
      'name': 'WH-1000XM4',
      'codec': 4,
      'rate': 0x08,
      'bits': 0x02,
      'specific1': 1000,
    });
    expect(ldac.label, 'LDAC 990 kbps · 96 kHz / 24-bit');
    expect(ldac.name, 'WH-1000XM4');
    expect(
      BluetoothOutput.fromAndroid({'codec': 4, 'rate': 0x02, 'bits': 0x01, 'specific1': 1003}).label,
      'LDAC (adaptive) · 48 kHz / 16-bit',
    );
    expect(BluetoothOutput.fromAndroid({'codec': 1, 'rate': 0x01, 'bits': 0x01}).label, 'AAC · 44.1 kHz / 16-bit');
    expect(BluetoothOutput.fromAndroid({'codec': 3, 'rate': 0x02, 'bits': 0x02}).label, 'aptX HD · 48 kHz / 24-bit');
    expect(BluetoothOutput.fromAndroid({'codec': 0}).label, 'SBC');
    expect(BluetoothOutput.fromAndroid({'codec': 9}).label, 'Codec 9', reason: "a vendor's own codec");
  });

  test('no codec read: the name alone, and whether the permission is missing', () {
    final hidden = BluetoothOutput.fromAndroid({'name': 'Buds', 'permission': false});
    expect(hidden.label, isNull);
    expect(hidden.needsPermission, isTrue);
    expect(BluetoothOutput.fromAndroid({'name': 'Buds'}).needsPermission, isFalse);
  });
}
