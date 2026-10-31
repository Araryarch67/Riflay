import '../services/stay_awake.dart' show IdleInhibitor;

/// No C library in a browser. See `native_calls.dart`.
int Function(int)? lookupMallocTrim() => null;

String get currentAbi => 'web';

void mkfifo(String path) => throw UnsupportedError('No named pipes in a browser');

bool pokeWriter(String path) => false;

bool processAlive(int pid) => false;

class WindowsPowerRequest implements IdleInhibitor {
  @override
  Future<void> acquire() async => throw UnsupportedError('No power requests in a browser');

  @override
  Future<void> release() async {}
}

class MacAssertion extends WindowsPowerRequest {}
