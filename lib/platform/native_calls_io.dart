import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../services/stay_awake.dart' show IdleInhibitor;

/// `malloc_trim` from glibc; null where the C library has none (musl).
int Function(int)? lookupMallocTrim() {
  try {
    return DynamicLibrary.process().lookupFunction<Int32 Function(IntPtr), int Function(int)>('malloc_trim');
  } catch (_) {
    return null; // not glibc (e.g. musl)
  }
}

/// The CPU and operating system the app was built for, as `Abi.toString()` names it ("linux_x64").
String get currentAbi => Abi.current().toString();

typedef _MkfifoNative = Int32 Function(Pointer<Utf8>, Uint32);
typedef _MkfifoNativeApple = Int32 Function(Pointer<Utf8>, Uint16);
typedef _Mkfifo = int Function(Pointer<Utf8>, int);

/// Makes a named pipe (a FIFO) at [path], owner-only.
void mkfifo(String path) {
  final lib = DynamicLibrary.process();
  // mode_t is 16 bits on Apple systems and 32 on Linux / Android.
  final _Mkfifo call = Platform.isMacOS || Platform.isIOS
      ? lib.lookupFunction<_MkfifoNativeApple, _Mkfifo>('mkfifo')
      : lib.lookupFunction<_MkfifoNative, _Mkfifo>('mkfifo');
  final name = path.toNativeUtf8();
  try {
    if (call(name, 384) != 0) throw FileSystemException('mkfifo failed', path); // 0600
  } finally {
    calloc.free(name);
  }
}

typedef _OpenNative = Int32 Function(Pointer<Utf8>, Int32);
typedef _Open = int Function(Pointer<Utf8>, int);
typedef _CloseNative = Int32 Function(Int32);
typedef _Close = int Function(int);
typedef _KillNative = Int32 Function(Int32, Int32);
typedef _Kill = int Function(int, int);

/// Opens and at once closes the write end of the pipe at [path] without ever blocking, which completes a reader's
/// blocked `open`. False when no reader is waiting (the open fails with ENXIO).
///
/// `File.open(mode: writeOnly)` would do the same, but if the reader is not there it blocks an IO thread for good.
bool pokeWriter(String path) {
  final lib = DynamicLibrary.process();
  final open = lib.lookupFunction<_OpenNative, _Open>('open');
  final close = lib.lookupFunction<_CloseNative, _Close>('close');
  const writeOnly = 1; // O_WRONLY
  final nonBlock = Platform.isMacOS || Platform.isIOS ? 0x4 : 0x800; // O_NONBLOCK
  final name = path.toNativeUtf8();
  try {
    final fd = open(name, writeOnly | nonBlock);
    if (fd < 0) return false;
    close(fd);
    return true;
  } finally {
    calloc.free(name);
  }
}

/// Whether the process [pid] is still running.
bool processAlive(int pid) {
  if (Platform.isLinux || Platform.isAndroid) return Directory('/proc/$pid').existsSync();
  return DynamicLibrary.process().lookupFunction<_KillNative, _Kill>('kill')(pid, 0) == 0;
}

/// Windows: a power request. Not SetThreadExecutionState, which belongs to an
/// OS thread, and Dart may run this isolate on another one next time.
class WindowsPowerRequest implements IdleInhibitor {
  Pointer<Void>? _handle;

  @override
  Future<void> acquire() async {
    if (_handle != null) return;
    final k = DynamicLibrary.open('kernel32.dll');
    final create = k.lookupFunction<Pointer<Void> Function(Pointer<Void>), Pointer<Void> Function(Pointer<Void>)>(
      'PowerCreateRequest',
    );
    final set = k.lookupFunction<Int32 Function(Pointer<Void>, Int32), int Function(Pointer<Void>, int)>(
      'PowerSetRequest',
    );
    // REASON_CONTEXT: Version 0, Flags POWER_REQUEST_CONTEXT_SIMPLE_STRING (1), then the string.
    final ctx = calloc<Uint8>(32);
    final reason = 'Riflay is playing music'.toNativeUtf16();
    try {
      ctx.cast<Uint32>()[1] = 1;
      (ctx + 8).cast<IntPtr>().value = reason.address;
      final h = create(ctx.cast());
      // INVALID_HANDLE_VALUE
      if (h.address == -1 || h.address == 0) throw StateError('PowerCreateRequest failed');
      if (set(h, 1) == 0) throw StateError('PowerSetRequest failed'); // PowerRequestSystemRequired
      _handle = h;
    } finally {
      calloc.free(reason);
      calloc.free(ctx);
    }
  }

  @override
  Future<void> release() async {
    final h = _handle;
    _handle = null;
    if (h == null) return;
    final k = DynamicLibrary.open('kernel32.dll');
    k.lookupFunction<Int32 Function(Pointer<Void>, Int32), int Function(Pointer<Void>, int)>('PowerClearRequest')(h, 1);
    k.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('CloseHandle')(h);
  }
}

/// macOS: an IOPMAssertion that prevents idle system sleep.
class MacAssertion implements IdleInhibitor {
  int? _id;

  @override
  Future<void> acquire() async {
    if (_id != null) return;
    final cf = DynamicLibrary.open('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation');
    final io = DynamicLibrary.open('/System/Library/Frameworks/IOKit.framework/IOKit');
    final makeString = cf
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Uint32),
          Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, int)
        >('CFStringCreateWithCString');
    final release = cf.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('CFRelease');
    final create = io
        .lookupFunction<
          Int32 Function(Pointer<Void>, Uint32, Pointer<Void>, Pointer<Uint32>),
          int Function(Pointer<Void>, int, Pointer<Void>, Pointer<Uint32>)
        >('IOPMAssertionCreateWithName');
    const utf8 = 0x08000100;
    final type = 'PreventUserIdleSystemSleep'.toNativeUtf8();
    final name = 'Riflay is playing music'.toNativeUtf8();
    final out = calloc<Uint32>();
    final cfType = makeString(nullptr, type, utf8);
    final cfName = makeString(nullptr, name, utf8);
    try {
      // kIOPMAssertionLevelOn = 255
      if (create(cfType, 255, cfName, out) != 0) throw StateError('IOPMAssertionCreateWithName failed');
      _id = out.value;
    } finally {
      release(cfType);
      release(cfName);
      calloc.free(type);
      calloc.free(name);
      calloc.free(out);
    }
  }

  @override
  Future<void> release() async {
    final id = _id;
    _id = null;
    if (id == null) return;
    final io = DynamicLibrary.open('/System/Library/Frameworks/IOKit.framework/IOKit');
    io.lookupFunction<Int32 Function(Uint32), int Function(int)>('IOPMAssertionRelease')(id);
  }
}
