import 'dart:async';

import 'package:riflay/ui/debug_switches.dart';

/// Tests run on a computer, where Balanced is frugal (`LayoutPrefs.frugal`). They describe Balanced as a phone has
/// it; the tests of the frugal one turn it back on.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  DebugSwitches.fullBalanced = true;
  await testMain();
}
