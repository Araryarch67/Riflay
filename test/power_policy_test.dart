import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/power_policy.dart';

PowerFacts facts({
  KeepScreenOn screen = KeepScreenOn.off,
  bool preventSleep = true,
  bool playing = false,
  bool foreground = true,
  bool phone = false,
  bool desktop = true,
  bool streaming = false,
}) => PowerFacts(
  screen: screen,
  preventSleep: preventSleep,
  playing: playing,
  foreground: foreground,
  phone: phone,
  desktop: desktop,
  streaming: streaming,
);

void main() {
  test('default: nothing held on a phone', () {
    expect(decideLocks(facts(phone: true, desktop: false)), const PowerLocks());
  });

  test('desktop holds the sleep lock only while playing, and only if enabled', () {
    expect(decideLocks(facts(playing: true)).systemSleep, isTrue);
    expect(decideLocks(facts()).systemSleep, isFalse);
    expect(decideLocks(facts(playing: true, preventSleep: false)).systemSleep, isFalse);
  });

  test('a phone never takes the desktop sleep lock', () {
    expect(decideLocks(facts(playing: true, phone: true, desktop: false)).systemSleep, isFalse);
  });

  test('screen: while playing', () {
    const m = KeepScreenOn.whilePlaying;
    expect(decideLocks(facts(screen: m, playing: true, phone: true, desktop: false)).screen, isTrue);
    expect(decideLocks(facts(screen: m, playing: false, phone: true, desktop: false)).screen, isFalse);
    expect(decideLocks(facts(screen: m, playing: true, foreground: false, phone: true, desktop: false)).screen, isFalse);
  });

  test('screen: while open follows the foreground on phones, not on computers', () {
    const m = KeepScreenOn.whileOpen;
    expect(decideLocks(facts(screen: m, phone: true, desktop: false)).screen, isTrue);
    expect(decideLocks(facts(screen: m, foreground: false, phone: true, desktop: false)).screen, isFalse);
    expect(decideLocks(facts(screen: m, foreground: false)).screen, isTrue);
  });

  test('phone: cpu lock while playing, wifi lock only when streaming', () {
    final local = decideLocks(facts(playing: true, phone: true, desktop: false));
    expect(local.cpu, isTrue);
    expect(local.wifi, isFalse);
    final online = decideLocks(facts(playing: true, phone: true, desktop: false, streaming: true));
    expect(online.wifi, isTrue);
    expect(decideLocks(facts(phone: true, desktop: false, streaming: true)).cpu, isFalse);
  });
}
