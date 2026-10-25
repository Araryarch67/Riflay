// StreamAudioSource.request is just_audio's documented byte-stream API (see
// youtube_audio_source.dart); the loopback server calls it directly.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'dlna.dart' show CastServer;

/// What [MpvPcm] decodes: a file (or URL) mpv opens itself, or bytes from a
/// [StreamAudioSource] (a YouTube stream, an SACD song built on the fly).
class PcmInput {
  const PcmInput.file(String this.path) : source = null;
  const PcmInput.stream(StreamAudioSource this.source) : path = null;

  final String? path;
  final StreamAudioSource? source;
}

/// Decoded audio from [MpvPcm.decode]: interleaved little-endian PCM.
class PcmStream {
  PcmStream._(this._session, this.rate, this.bits, this.channels);

  final _Session _session;

  /// Samples per second per channel.
  final int rate;

  /// Bits per sample: 16 (s16le) or 32 (s32le).
  final int bits;
  final int channels;

  /// The samples. Ends when the song (or the requested slice) does; cancelling
  /// the subscription stops the decoder.
  Stream<Uint8List> get data => _session.out.stream;

  /// Stops decoding and frees everything. Safe to call more than once, and
  /// after [data] has ended.
  Future<void> cancel() => _session.stop();
}

/// Decodes audio with libmpv instead of an `ffmpeg` process, which phones
/// can't run. A second mpv player (never the one that plays music) writes PCM
/// with its `pcm` audio output into a named pipe; this reads the pipe.
///
/// The `pcm` output isn't tied to a clock: mpv decodes as fast as the pipe is
/// read, and the pipe's size is the only back-pressure. Windows has no named
/// pipes of this kind, so it keeps using ffmpeg ([supported] is false).
abstract final class MpvPcm {
  /// Whether [decode] works on this system.
  static bool get supported => !Platform.isWindows;

  /// Every rate renderers take, for [decode]'s `maxRate`.
  static const _rates = [8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000, 88200, 96000, 176400, 192000];

  /// Decodes [input] from [start] to [end] (in the song) as stereo PCM of [bits] (16 or 32).
  ///
  /// With [rate] the output is resampled to it. With [maxRate] a song keeps its
  /// own rate unless that is above it, and then it is brought down to the
  /// nearest standard rate (DSD's 352.8 kHz becomes 176.4 kHz).
  ///
  /// Throws when mpv can't open [input] (within [openTimeout]).
  static Future<PcmStream> decode(
    PcmInput input, {
    Duration start = Duration.zero,
    Duration? end,
    int? rate,
    int? maxRate,
    required int bits,
    Duration openTimeout = const Duration(seconds: 20),
  }) async {
    assert(supported);
    assert(bits == 16 || bits == 32);
    MediaKit.ensureInitialized();
    final session = _Session();
    try {
      await session.open(input, start: start, end: end, rate: rate, maxRate: maxRate, bits: bits, timeout: openTimeout);
    } catch (_) {
      await session.stop();
      rethrow;
    }
    return PcmStream._(session, session.rate, session.bits, session.channels);
  }

  /// Where this process keeps its pipes under [temp]: a folder of its own, so a crash leaves one stale folder that the
  /// next start can recognise (see [sweepStale]) instead of loose files nobody owns.
  @visibleForTesting
  static String fifoDirectoryIn(String temp) => '$temp/riflay-pcm-$pid';

  static final _folder = RegExp(r'^riflay-pcm-(\d+)$');
  static final _loosePipe = RegExp(r'^riflay-pcm-[0-9a-f]+$');
  static bool _swept = false;

  /// Removes what earlier runs left in [temp]: the folders of processes that are gone, and the loose pipes that older
  /// versions made there. Runs once per process, before the first decode.
  @visibleForTesting
  static void sweepStale(String temp) {
    _swept = true;
    try {
      for (final e in Directory(temp).listSync(followLinks: false)) {
        final name = e.uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
        try {
          if (e is Directory) {
            final owner = int.tryParse(_folder.firstMatch(name)?.group(1) ?? '');
            if (owner != null && owner != pid && !_alive(owner)) e.deleteSync(recursive: true);
          } else if (_loosePipe.hasMatch(name) &&
              FileSystemEntity.typeSync(e.path, followLinks: false) == FileSystemEntityType.pipe &&
              DateTime.now().difference(e.statSync().modified) > const Duration(hours: 1)) {
            e.deleteSync();
          }
        } catch (_) {} // not ours to remove, or already gone
      }
    } catch (e) {
      debugPrint('PCM decoder: $e');
    }
  }

  /// This process's pipe folder, made (and the stale ones of dead processes swept) on first use.
  static Future<String> _directory() async {
    String temp;
    try {
      temp = (await getTemporaryDirectory()).path;
    } catch (_) {
      temp = Directory.systemTemp.path; // no plugin (unit tests)
    }
    if (!_swept) sweepStale(temp);
    return (Directory(fifoDirectoryIn(temp))..createSync(recursive: true)).path;
  }

  /// The `af` graph that keeps a song's rate if it is at most [maxRate] and
  /// otherwise lets libavfilter pick the closest rate that is allowed.
  @visibleForTesting
  static String rateFilter(int maxRate) {
    final allowed = [
      for (final r in _rates)
        if (r <= maxRate) r,
    ];
    if (allowed.isEmpty || allowed.last != maxRate) allowed.add(maxRate);
    return 'lavfi=[aformat=sample_rates=${allowed.join('|')}]';
  }
}

typedef _MkfifoNative = Int32 Function(Pointer<Utf8>, Uint32);
typedef _MkfifoNativeApple = Int32 Function(Pointer<Utf8>, Uint16);
typedef _Mkfifo = int Function(Pointer<Utf8>, int);

/// Makes a named pipe (a FIFO) at [path], owner-only.
void _mkfifo(String path) {
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
bool _pokeWriter(String path) {
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
bool _alive(int pid) {
  if (Platform.isLinux || Platform.isAndroid) return Directory('/proc/$pid').existsSync();
  return DynamicLibrary.process().lookupFunction<_KillNative, _Kill>('kill')(pid, 0) == 0;
}

/// One decode: the mpv player, the pipe, the reader and, for byte sources, the loopback server.
class _Session {
  final out = StreamController<Uint8List>();

  Player? _player;
  String? _fifo;
  RandomAccessFile? _reader;
  Future<RandomAccessFile>? _opening; // the reader's open, until it is assigned to [_reader]
  _SourceServer? _server;
  Future<void>? _pump;
  Future<void>? _stopping;
  bool _stop = false;
  Completer<void>? _resume;
  Uint8List _lead = Uint8List(0);

  int rate = 0, bits = 0, channels = 0;

  _Session() {
    out
      ..onListen = _startPump
      ..onResume = _wake
      ..onCancel = stop;
  }

  Future<void> open(
    PcmInput input, {
    required Duration start,
    required Duration? end,
    required int? rate,
    required int? maxRate,
    required int bits,
    required Duration timeout,
  }) async {
    final dir = await MpvPcm._directory();
    final fifo = _fifo = '$dir/${math.Random.secure().nextInt(1 << 32).toRadixString(16)}';
    _mkfifo(fifo);

    // Blocks (on an IO thread) until mpv opens its end, which it does when the first audio is decoded. Whatever
    // happens meanwhile, [_abandonReader] can always complete it, so this never outlives the session.
    final reader = Completer<RandomAccessFile>();
    _opening = reader.future;
    File(fifo).open().then(reader.complete, onError: reader.completeError);

    final failure = Completer<void>();
    final url = switch (input) {
      PcmInput(:final path?) => path,
      PcmInput(:final source?) => (_server = await _SourceServer.start(source)).url,
      _ => throw ArgumentError('no input'),
    };
    final player = _player = Player(
      configuration: const PlayerConfiguration(vo: 'null', osc: false, logLevel: MPVLogLevel.error),
    );
    final native = player.platform as NativePlayer;
    player.stream.error.listen((e) {
      debugPrint('PCM decoder: $e');
      if (!failure.isCompleted) failure.complete();
    });
    // The song ending before the pipe was opened: nothing to decode (a start past the end).
    player.stream.completed.listen((done) {
      if (done) {
        Future<void>.delayed(const Duration(milliseconds: 500), () {
          if (!failure.isCompleted) failure.complete();
        });
      }
    });
    final props = <String, String>{
      'vid': 'no',
      'ao': 'pcm',
      'ao-pcm-file': fifo,
      'ao-pcm-waveheader': 'yes',
      'ao-pcm-append': 'no',
      'keep-open': 'no',
      'idle': 'yes',
      'audio-channels': 'stereo',
      'audio-format': bits == 16 ? 's16' : 's32',
      'replaygain': 'no',
      'volume': '100',
      'cache-on-disk': 'no',
      if (rate != null) 'audio-samplerate': '$rate',
      if (rate == null && maxRate != null) 'af': MpvPcm.rateFilter(maxRate),
    };
    // Setting up the player is bounded too: the replies come from mpv, which may be wedged.
    await (() async {
      for (final e in props.entries) {
        await native.setProperty(e.key, e.value);
      }
      await player.open(Media(url, start: start > Duration.zero ? start : null, end: end), play: true);
    })().timeout(timeout, onTimeout: () => throw const FileSystemException('Couldn\'t decode: mpv did not start'));

    final timer = Timer(timeout, () {
      debugPrint('PCM decoder: mpv never opened its output');
      if (!failure.isCompleted) failure.complete();
    });
    try {
      final first = await Future.any<RandomAccessFile?>([reader.future, failure.future.then((_) => null)]);
      // Nothing will come: the caller's [stop] frees the blocked open.
      if (first == null) throw const FileSystemException('Couldn\'t decode');
      _reader = first;
      _opening = null;
    } finally {
      timer.cancel();
    }
    await _readHeader(timeout);
  }

  /// Frees a reader whose open is still waiting for mpv's end: pokes the pipe from the other side (never blocking)
  /// until the open returns, then closes what it returned.
  Future<void> _abandonReader() async {
    final opened = _opening, fifo = _fifo;
    _opening = null;
    if (opened == null || fifo == null) return;
    var settled = false;
    final closed = opened.then<void>((f) async {
      settled = true;
      await f.close();
    }, onError: (Object _) => settled = true);
    for (var i = 0; i < 60 && !settled; i++) {
      _pokeWriter(fifo);
      await Future.any<void>([closed, Future<void>.delayed(const Duration(milliseconds: 50))]);
    }
    if (!settled) debugPrint('PCM decoder: the pipe never opened for reading');
  }

  /// Reads the WAVE header mpv puts first (RIFF, `fmt `, then `data`), whatever size it is.
  Future<void> _readHeader(Duration timeout) async {
    final buf = BytesBuilder(copy: false);
    var bytes = Uint8List(0);
    while (true) {
      final chunk = await _reader!
          .read(4096)
          .timeout(timeout, onTimeout: () => throw const FileSystemException('Couldn\'t decode: no audio'));
      if (chunk.isEmpty) throw const FileSystemException('Couldn\'t decode: no audio');
      buf.add(chunk);
      bytes = buf.toBytes();
      final data = _parseWav(bytes);
      if (data != null) {
        _lead = Uint8List.sublistView(bytes, data);
        return;
      }
      if (bytes.length > 4096) throw const FormatException('Unexpected WAVE header');
    }
  }

  /// The offset where the samples start, or null if [b] is too short yet.
  int? _parseWav(Uint8List b) {
    if (b.length < 12) return null;
    final d = ByteData.sublistView(b);
    if (String.fromCharCodes(b, 0, 4) != 'RIFF' || String.fromCharCodes(b, 8, 12) != 'WAVE') {
      throw const FormatException('Not a WAVE header');
    }
    var o = 12;
    var haveFmt = false;
    while (o + 8 <= b.length) {
      final id = String.fromCharCodes(b, o, o + 4);
      final size = d.getUint32(o + 4, Endian.little);
      if (id == 'data') {
        if (!haveFmt) throw const FormatException('WAVE data before fmt');
        return o + 8;
      }
      final body = o + 8;
      if (id == 'fmt ') {
        if (b.length < body + 16) return null;
        var tag = d.getUint16(body, Endian.little);
        channels = d.getUint16(body + 2, Endian.little);
        rate = d.getUint32(body + 4, Endian.little);
        bits = d.getUint16(body + 14, Endian.little);
        if (tag == 0xFFFE && size >= 26) {
          if (b.length < body + 26) return null;
          tag = d.getUint16(body + 24, Endian.little); // the sub-format's first two bytes
        }
        if (tag != 1) throw FormatException('Not integer PCM ($tag)');
        haveFmt = true;
      }
      o = body + size + (size & 1);
    }
    return null;
  }

  void _wake() {
    if (_resume case final r? when !r.isCompleted) r.complete();
  }

  void _startPump() => _pump ??= _run();

  /// The one reader of the pipe: passes samples on, or (once stopping) throws them away until mpv closes its end.
  Future<void> _run() async {
    final reader = _reader;
    if (reader == null) return;
    try {
      if (_lead.isNotEmpty && !_stop) out.add(_lead);
      _lead = Uint8List(0);
      while (true) {
        // The listener (AirPlay's real-time pacing, a renderer's socket) sets the pace; mpv waits on the full pipe.
        if (!_stop && out.isPaused) {
          final wait = _resume = Completer<void>();
          await wait.future;
          _resume = null;
        }
        final chunk = await reader.read(65536);
        if (chunk.isEmpty) break; // mpv closed its end: the song is over
        if (!_stop) out.add(chunk);
      }
    } catch (e) {
      debugPrint('PCM decoder: $e');
    } finally {
      await _release();
      if (!out.isClosed) unawaited(out.close());
    }
  }

  /// Stops the decode and releases everything.
  Future<void> stop() => _stopping ??= _stopNow();

  Future<void> _stopNow() async {
    _stop = true;
    _wake();
    final player = _player;
    _player = null;
    // Disposing may wait on mpv, which can itself be stuck writing into a full pipe: keep reading.
    final disposed = player?.dispose().catchError((Object e) => debugPrint('PCM decoder: $e'));
    if (_reader != null) {
      _startPump();
      await _pump!.timeout(const Duration(seconds: 10), onTimeout: _release);
    } else {
      // Never got as far as a reader; its open may still be waiting for a writer.
      await _abandonReader();
      await _release();
    }
    await disposed?.timeout(
      const Duration(seconds: 10),
      onTimeout: () => debugPrint('PCM decoder: the player did not dispose'),
    );
    try {
      await _server?.close().timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('PCM decoder: $e');
    }
    _server = null;
    if (!out.isClosed) unawaited(out.close());
  }

  bool _released = false;

  Future<void> _release() async {
    if (_released) return;
    _released = true;
    final reader = _reader;
    _reader = null;
    try {
      // A read that mpv never answers would hold the close for good.
      await reader?.close().timeout(const Duration(seconds: 2));
    } catch (_) {}
    final fifo = _fifo;
    _fifo = null;
    if (fifo != null) {
      try {
        File(fifo).deleteSync();
      } catch (_) {}
    }
  }
}

/// A bytes source for mpv: HTTP on 127.0.0.1, an unguessable path, with
/// `Range` so mpv can seek in it.
class _SourceServer {
  _SourceServer._(this._http, this.source, this._token);

  final HttpServer _http;
  final StreamAudioSource source;
  final String _token;

  static Future<_SourceServer> start(StreamAudioSource source) async {
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final random = math.Random.secure();
    final token = List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final server = _SourceServer._(http, source, token);
    http.listen(server._handle);
    return server;
  }

  String get url => 'http://127.0.0.1:${_http.port}/$_token';

  Future<void> close() => _http.close(force: true);

  int? _length;

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      if (req.uri.pathSegments.length != 1 || req.uri.pathSegments.single != _token) {
        res.statusCode = HttpStatus.notFound;
        return await res.close();
      }
      if (_length == null) {
        final probe = await source.request(0, 1);
        await probe.stream.drain<void>().catchError((_) {});
        _length = probe.sourceLength;
      }
      final total = _length;
      if (total == null) throw StateError('Unknown stream length');
      final header = req.headers.value(HttpHeaders.rangeHeader);
      final range = CastServer.parseRange(header, total);
      res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      if (header != null && range == null) {
        res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
        return await res.close();
      }
      final r = range ?? (start: 0, end: total - 1);
      if (range != null) {
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes ${r.start}-${r.end}/$total');
      }
      res.contentLength = r.end - r.start + 1;
      if (req.method != 'HEAD') {
        final reply = await source.request(r.start, r.end + 1);
        await res.addStream(reply.stream);
      }
      await res.close();
    } catch (e) {
      // mpv hanging up mid-stream (a seek) is normal.
      debugPrint('PCM source server: $e');
      try {
        await res.close();
      } catch (_) {}
    }
  }
}
