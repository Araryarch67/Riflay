// Which locks keep the device awake, decided from plain facts. No platform
// code here, so it is unit tested; [StayAwake] applies the answer.

/// Settings › Playback › Keep screen on.
enum KeepScreenOn {
  off('Off'),
  whilePlaying('While playing'),
  whileOpen('While Riflay is open');

  const KeepScreenOn(this.label);
  final String label;
}

/// What is true right now.
class PowerFacts {
  const PowerFacts({
    required this.screen,
    required this.preventSleep,
    required this.playing,
    required this.foreground,
    required this.phone,
    required this.desktop,
    this.streaming = false,
  });

  final KeepScreenOn screen;

  /// Settings › Playback › "Don't sleep while playing" (computers).
  final bool preventSleep;
  final bool playing;

  /// The app's window is in front (resumed). Always true on computers.
  final bool foreground;
  final bool phone;
  final bool desktop;

  /// The song comes over the network.
  final bool streaming;
}

/// The locks to hold.
class PowerLocks {
  const PowerLocks({this.screen = false, this.systemSleep = false, this.cpu = false, this.wifi = false});

  /// The screen stays lit (wakelock_plus / the idle timer).
  final bool screen;

  /// The computer does not suspend on idle (logind, power request, IOPM).
  final bool systemSleep;

  /// Android: the CPU keeps running with the screen off.
  final bool cpu;

  /// Android: Wi-Fi keeps its full speed with the screen off.
  final bool wifi;

  @override
  bool operator ==(Object other) =>
      other is PowerLocks &&
      other.screen == screen &&
      other.systemSleep == systemSleep &&
      other.cpu == cpu &&
      other.wifi == wifi;

  @override
  int get hashCode => Object.hash(screen, systemSleep, cpu, wifi);

  @override
  String toString() => 'PowerLocks(screen: $screen, systemSleep: $systemSleep, cpu: $cpu, wifi: $wifi)';
}

PowerLocks decideLocks(PowerFacts f) {
  // A phone lets go of the screen when the app is no longer in front.
  final screen = switch (f.screen) {
    KeepScreenOn.off => false,
    KeepScreenOn.whilePlaying => f.playing && (f.foreground || !f.phone),
    KeepScreenOn.whileOpen => f.foreground || !f.phone,
  };
  return PowerLocks(
    screen: screen,
    systemSleep: f.desktop && f.preventSleep && f.playing,
    cpu: f.phone && f.playing,
    wifi: f.phone && f.playing && f.streaming,
  );
}
