import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/airplay.dart';
import 'package:riflay/services/cast.dart';
import 'package:riflay/services/dlna.dart';

void main() {
  final tv = DlnaTarget(
    DlnaRenderer(
      id: 'tv',
      name: 'TV',
      location: Uri.parse('http://10.0.0.2/d.xml'),
      avTransport: Uri.parse('http://10.0.0.2/av'),
      avTransportType: 'urn:schemas-upnp-org:service:AVTransport:1',
    ),
  );
  final speaker = AirPlayTarget(AirPlayDevice(name: 'Kitchen', host: InternetAddress('10.0.0.3'), port: 7000));

  test('toggle adds in order and removes on a second tap', () {
    var g = CastGroup.toggle(const [], tv);
    g = CastGroup.toggle(g, speaker);
    expect(g, [tv, speaker]);
    expect(CastGroup.toggle(g, tv), [speaker]);
  });

  test('same ignores order but not membership', () {
    expect(CastGroup.same([tv, speaker], [speaker, tv]), isTrue);
    expect(CastGroup.same([tv], [tv, speaker]), isFalse);
    expect(CastGroup.same(const [], const []), isTrue);
  });

  test('a Cast with nothing connected has an empty group', () {
    final cast = Cast(onEnded: () {}, onError: (_) {});
    expect(cast.group, isEmpty);
    cast.dispose();
  });
}
