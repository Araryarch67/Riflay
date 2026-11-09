import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../services/video_engine.dart';

const _dll = 'libmpv-video-2.dll';

// mpv's C API, the few calls used (libmpv/client.h).
typedef _Create = Pointer<Void> Function();
typedef _Handle = Int32 Function(Pointer<Void>);
typedef _HandleD = int Function(Pointer<Void>);
typedef _SetC = Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _SetD = int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _GetC = Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32, Pointer<Void>);
typedef _GetD = int Function(Pointer<Void>, Pointer<Utf8>, int, Pointer<Void>);
typedef _GetStrC = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _FreeC = Void Function(Pointer<Void>);
typedef _FreeD = void Function(Pointer<Void>);
typedef _CommandC = Int32 Function(Pointer<Void>, Uint64, Pointer<Pointer<Utf8>>);
typedef _CommandD = int Function(Pointer<Void>, int, Pointer<Pointer<Utf8>>);
typedef _WaitC = Pointer<Int32> Function(Pointer<Void>, Double);
typedef _WaitD = Pointer<Int32> Function(Pointer<Void>, double);
typedef _DestroyC = Void Function(Pointer<Void>);
typedef _DestroyD = void Function(Pointer<Void>);

const _formatFlag = 3;
const _formatInt64 = 4;
const _formatDouble = 5;

class _Mpv {
  _Mpv(DynamicLibrary l)
    : create = l.lookupFunction<_Create, _Create>('mpv_create'),
      initialize = l.lookupFunction<_Handle, _HandleD>('mpv_initialize'),
      setOption = l.lookupFunction<_SetC, _SetD>('mpv_set_option_string'),
      setProperty = l.lookupFunction<_SetC, _SetD>('mpv_set_property_string'),
      getProperty = l.lookupFunction<_GetC, _GetD>('mpv_get_property'),
      getString = l.lookupFunction<_GetStrC, _GetStrC>('mpv_get_property_string'),
      free = l.lookupFunction<_FreeC, _FreeD>('mpv_free'),
      commandAsync = l.lookupFunction<_CommandC, _CommandD>('mpv_command_async'),
      waitEvent = l.lookupFunction<_WaitC, _WaitD>('mpv_wait_event'),
      destroy = l.lookupFunction<_DestroyC, _DestroyD>('mpv_terminate_destroy');

  // Use the same SONAME as the Linux runner, so its render API receives a
  // handle from the very same loaded library (including bundled builds).
  static String get path => Platform.isLinux ? 'libmpv.so.2' : p.join(p.dirname(Platform.resolvedExecutable), _dll);
  static _Mpv? _instance;
  static _Mpv get instance => _instance ??= _Mpv(DynamicLibrary.open(path));

  final _Create create;
  final _HandleD initialize;
  final _SetD setOption;
  final _SetD setProperty;
  final _GetD getProperty;
  final _GetStrC getString;
  final _FreeD free;
  final _CommandD commandAsync;
  final _WaitD waitEvent;
  final _DestroyD destroy;
}

/// Muted music video in a Windows child window or Linux GTK OpenGL surface.
/// Video mode drives it; native frames do not invalidate a Flutter texture.
class NativeVideoPlayer implements VideoEngine {
  NativeVideoPlayer({required int window, required String hwdec, int? maxFps, required bool foreground}) {
    final mpv = _mpv;
    final h = mpv.create();
    if (h == nullptr) throw StateError('mpv could not be made');
    _h = h;
    void option(String name, String value) => using((a) {
      final r = mpv.setOption(h, name.toNativeUtf8(allocator: a), value.toNativeUtf8(allocator: a));
      if (r < 0) debugPrint('Native video: $name=$value refused ($r)');
    });
    option('config', 'no');
    option('terminal', 'no');
    option('load-scripts', 'no');
    option('ytdl', 'no');
    option('osc', 'no');
    option('osd-level', '0');
    option('input-default-bindings', 'no');
    option('input-vo-keyboard', 'no');
    option('input-cursor', 'no');
    option('cursor-autohide', 'no');
    option('idle', 'yes');
    option('keep-open', 'yes');
    option('force-window', 'no');
    if (Platform.isLinux) {
      option('vo', 'libmpv');
      option('video-timing-offset', '0');
    } else {
      option('wid', '$window');
      option('vo', 'gpu');
      option('gpu-context', 'd3d11');
    }
    option('hwdec', hwdec);
    option('keepaspect', 'yes');
    // A music video beside the page, not a film: plain bilinear scaling (no extra scaler passes or their lookup
    // textures), 8-bit intermediate pictures instead of 16-bit float, no dithering or debanding, and two pictures
    // queued instead of three. Each saves graphics memory (and the driver's copy of it in the process).
    option('scale', 'bilinear');
    option('dscale', 'bilinear');
    option('cscale', 'bilinear');
    option('correct-downscaling', 'no');
    option('linear-downscaling', 'no');
    option('sigmoid-upscaling', 'no');
    option('deband', 'no');
    option('dither-depth', 'no');
    option('fbo-format', 'rgba8');
    option('hdr-compute-peak', 'no');
    option('swapchain-depth', '2');
    // Video only: no sound track, no sound device, and only half a minute read ahead.
    option('aid', 'no');
    option('ao', 'null');
    option('cache', 'yes');
    // 15 s ahead at most (a 720p stream is ~1 MB a second); seeks back within it stay rare.
    option('cache-secs', '15');
    option('demuxer-max-bytes', '${(foreground ? 16 : 8) << 20}');
    option('demuxer-max-back-bytes', '${1 << 20}');
    // One decoding thread is plenty on the graphics card, and each thread keeps frames of its own.
    option('vd-lavc-threads', '1');
    option('hwdec-extra-frames', '2');
    if (maxFps != null) option('vf', 'fps=$maxFps');
    // For measuring: `RIFLAY_VIDEO_MPV_OPTIONS='name=value;…'`, as on the media_kit video player.
    for (final o in (Platform.environment['RIFLAY_VIDEO_MPV_OPTIONS'] ?? '').split(';')) {
      if (o.contains('=')) option(o.substring(0, o.indexOf('=')), o.substring(o.indexOf('=') + 1));
    }
    if (mpv.initialize(h) < 0) {
      mpv.destroy(h);
      throw StateError('mpv could not start');
    }
  }

  /// Linux links libmpv in the runner; Windows bundles a separate video DLL.
  static bool get available {
    if (Platform.isLinux) return true;
    if (!Platform.isWindows) return false;
    return _available ??= File(_Mpv.path).existsSync();
  }

  static bool? _available;

  static _Mpv get _mpv => _Mpv.instance;
  Pointer<Void>? _h;
  bool _playing = false;
  bool _attached = false;

  static const _surface = MethodChannel('riflay/video_window');

  /// The Linux runner owns the GL context; attach on its GTK thread before
  /// opening media. Failure lets Video mode use the texture backend instead.
  Future<void> attach() async {
    if (Platform.isLinux) {
      await _surface.invokeMethod<void>('attach', _h!.address);
      _attached = true;
    }
  }

  T? _read<T>(String name, int format, T Function(Pointer<Void>) read, int size) {
    final h = _h;
    if (h == null) return null;
    return using((a) {
      final out = a<Uint8>(size).cast<Void>();
      final r = _mpv.getProperty(h, name.toNativeUtf8(allocator: a), format, out);
      return r < 0 ? null : read(out);
    });
  }

  double? _double(String name) => _read(name, _formatDouble, (p) => p.cast<Double>().value, 8);
  int? _int(String name) => _read(name, _formatInt64, (p) => p.cast<Int64>().value, 8);
  bool? _flag(String name) => _read(name, _formatFlag, (p) => p.cast<Int32>().value != 0, 4);

  /// mpv queues an event for everything that happens; nobody here waits on them, so they are let go.
  void _drain() {
    final h = _h;
    if (h == null) return;
    for (var i = 0; i < 64; i++) {
      if (_mpv.waitEvent(h, 0).value == 0) break;
    }
  }

  void _command(List<String> args) {
    final h = _h;
    if (h == null) return;
    using((a) {
      final argv = a<Pointer<Utf8>>(args.length + 1);
      for (var i = 0; i < args.length; i++) {
        argv[i] = args[i].toNativeUtf8(allocator: a);
      }
      argv[args.length] = nullptr;
      _mpv.commandAsync(h, 0, argv);
    });
  }

  void _set(String name, String value) {
    final h = _h;
    if (h == null) return;
    using((a) => _mpv.setProperty(h, name.toNativeUtf8(allocator: a), value.toNativeUtf8(allocator: a)));
  }

  static String _seconds(Duration d) => (d.inMicroseconds / 1e6).toStringAsFixed(3);

  /// Starts [url] paused at [start].
  Future<void> open(String url, {Duration start = Duration.zero}) async {
    _playing = false;
    if (Platform.isWindows) {
      _command(['loadfile', url, 'replace', 'start=${_seconds(start)},pause=yes']);
      return;
    }
    // mpv 0.38 inserted an index argument before loadfile's per-file options.
    // Properties avoid depending on the Linux system mpv's command signature.
    _set('pause', 'yes');
    _set('start', _seconds(start));
    _command(['loadfile', url, 'replace']);
  }

  /// Waits until the first picture is out (its size is known and it has a position); false when it never came.
  Future<bool> firstFrame(Duration timeout) async {
    final until = DateTime.now().add(timeout);
    while (_h != null && DateTime.now().isBefore(until)) {
      _drain();
      if ((_int('dwidth') ?? 0) > 1 && _double('time-pos') != null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  /// The video's width over its height once its first picture is out, else null.
  double? get aspect {
    final w = _int('dwidth'), h = _int('dheight');
    return w == null || h == null || w <= 1 || h <= 0 ? null : w / h;
  }

  @override
  Duration get position {
    _drain();
    final s = _double('time-pos');
    return s == null ? Duration.zero : Duration(microseconds: (s * 1e6).round());
  }

  @override
  bool get playing => _playing;

  @override
  bool get buffering => _flag('paused-for-cache') ?? false;

  @override
  Future<void> play() async {
    _playing = true;
    _set('pause', 'no');
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _set('pause', 'yes');
  }

  @override
  Future<void> seek(Duration to) async => _command(['seek', _seconds(to), 'absolute']);

  @override
  Future<void> setRate(double rate) async => _set('speed', rate.toStringAsFixed(3));

  @override
  Future<String> getProperty(String name) async {
    final h = _h;
    if (h == null) return '';
    return using((a) {
      final s = _mpv.getString(h, name.toNativeUtf8(allocator: a));
      if (s == nullptr) return '';
      final v = s.toDartString();
      _mpv.free(s.cast());
      return v;
    });
  }

  @override
  Future<void> setProperty(String name, String value) async => _set(name, value);

  /// mpv's shutdown waits for its threads (and the graphics card): not on the UI thread.
  @override
  Future<void> dispose() async {
    final h = _h;
    if (h == null) return;
    _h = null;
    // Free the render context with its GL context current before destroying
    // mpv. A handle in the request prevents an old player detaching a new one.
    if (_attached) {
      await _surface.invokeMethod<void>('detach', h.address);
      _attached = false;
    }
    final address = h.address;
    final path = _Mpv.path;
    await Isolate.run(() => _Mpv(DynamicLibrary.open(path)).destroy(Pointer<Void>.fromAddress(address)));
  }
}
