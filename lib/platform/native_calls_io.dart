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

/// Trims free memory back to the operating system.
/// - Linux: invokes `malloc_trim(0)` from glibc. With [workingSet] it also pages the process out
///   (`madvise(MADV_PAGEOUT)` on its own mappings): like Windows below, nothing is freed, the pages go to swap (zram
///   on most desktops, compressed in memory) or, for files, back to the page cache, and fault back in when touched.
/// - Android: asks its allocator to hand free pages back (`mallopt(M_PURGE_ALL)`, Android 12's Scudo; `M_PURGE`
///   before it). The system, not the app, decides what is paged out there.
/// - Windows: compacts the process heap via `HeapCompact` (kernel32.dll). With [workingSet] it also empties the
///   working set (`SetProcessWorkingSetSize`): that frees nothing that is committed, it only pages it out, and
///   every page the app touches afterwards faults back in. Worth it only while the window is hidden.
void trimProcessMemory({bool workingSet = false}) {
  if (Platform.isLinux) {
    try {
      lookupMallocTrim()?.call(0);
    } catch (_) {}
    if (workingSet) _pageOutLinux();
  } else if (Platform.isAndroid) {
    _purgeAndroid();
  } else if (Platform.isWindows) {
    _trimWindows(workingSet);
  }
}

void _purgeAndroid() {
  try {
    final mallopt = DynamicLibrary.open('libc.so')
        .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>('mallopt');
    // M_PURGE_ALL (-104) also empties the per-thread caches; an allocator without it answers 0, then M_PURGE (-101).
    if (mallopt(-104, 0) == 0) mallopt(-101, 0);
  } catch (_) {}
}

/// `MADV_PAGEOUT` (Linux 5.4) over every private mapping of this process. Shared ones (the compositor's buffers, the
/// GPU's) and the kernel's own ([vdso], [vvar]) are left alone; pages other processes map too are skipped by the
/// kernel, and an older kernel just answers EINVAL.
void _pageOutLinux() {
  try {
    final madvise = DynamicLibrary.process()
        .lookupFunction<Int32 Function(IntPtr, Size, Int32), int Function(int, int, int)>('madvise');
    const pageOut = 21;
    for (final line in File('/proc/self/maps').readAsLinesSync()) {
      final f = line.split(RegExp(r'\s+'));
      if (f.length < 5 || f[1].length < 4 || f[1][0] != 'r' || f[1][3] != 'p') continue;
      final path = f.length > 5 ? f.sublist(5).join(' ') : '';
      if (path.startsWith('/dev/') || path.startsWith('[v') || path == '[stack]') continue;
      final range = f[0].split('-');
      final start = int.parse(range[0], radix: 16), end = int.parse(range[1], radix: 16);
      madvise(start, end - start, pageOut);
    }
  } catch (_) {}
}

void _trimWindows(bool workingSet) {
  try {
    final k = DynamicLibrary.open('kernel32.dll');
    final getCurrentProcess = k.lookupFunction<IntPtr Function(), int Function()>('GetCurrentProcess');
    final setWorkingSet = k.lookupFunction<Int32 Function(IntPtr, IntPtr, IntPtr), int Function(int, int, int)>(
      'SetProcessWorkingSetSize',
    );
    final getProcessHeap = k.lookupFunction<IntPtr Function(), int Function()>('GetProcessHeap');
    final heapCompact = k.lookupFunction<IntPtr Function(IntPtr, Uint32), int Function(int, int)>('HeapCompact');

    if (workingSet) setWorkingSet(getCurrentProcess(), -1, -1);
    final heap = getProcessHeap();
    if (heap != 0) {
      heapCompact(heap, 0);
    }
  } catch (_) {}
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

typedef _SignalNative = IntPtr Function(Int32, IntPtr);
typedef _Signal = int Function(int, int);

/// Android, Linux: a write to a pipe nobody reads any more fails (EPIPE) instead of ending the app. By default it
/// raises SIGPIPE, which kills the process without a trace, and libmpv leaves that default alone; Direct USB's mpv
/// writes into a pipe whose reader can stop. True when it is set.
bool ignoreBrokenPipes() {
  if (!Platform.isAndroid && !Platform.isLinux) return false;
  try {
    final lib = Platform.isAndroid ? DynamicLibrary.open('libc.so') : DynamicLibrary.process();
    const sigpipe = 13, sigIgn = 1; // SIGPIPE, SIG_IGN
    return lib.lookupFunction<_SignalNative, _Signal>('signal')(sigpipe, sigIgn) != -1; // SIG_ERR
  } catch (_) {
    return false;
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

/// Windows: the computer's physical memory in bytes (`GlobalMemoryStatusEx`), or null.
int? windowsTotalMemory() {
  if (!Platform.isWindows) return null;
  // MEMORYSTATUSEX: dwLength, dwMemoryLoad, then ullTotalPhys at byte 8 (64 bytes in all).
  final status = calloc<Uint8>(64);
  try {
    status.cast<Uint32>().value = 64;
    final k = DynamicLibrary.open('kernel32.dll');
    final ok = k.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('GlobalMemoryStatusEx')(
      status.cast(),
    );
    return ok == 0 ? null : (status + 8).cast<Uint64>().value;
  } catch (_) {
    return null;
  } finally {
    calloc.free(status);
  }
}

/// Windows: whether the computer has a battery (`GetSystemPowerStatus`), or null when it can't tell.
bool? windowsHasBattery() {
  if (!Platform.isWindows) return null;
  // SYSTEM_POWER_STATUS: ACLineStatus, BatteryFlag (128: no system battery, 255: unknown), … (12 bytes).
  final status = calloc<Uint8>(12);
  try {
    final k = DynamicLibrary.open('kernel32.dll');
    final ok = k.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('GetSystemPowerStatus')(
      status.cast(),
    );
    final flag = status[1];
    return ok == 0 || flag == 255 ? null : flag & 128 == 0;
  } catch (_) {
    return null;
  } finally {
    calloc.free(status);
  }
}
