import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One format a USB DAC takes bit-perfect (Android's `AudioMixerAttributes`, stereo).
@immutable
class MixerFormat {
  const MixerFormat(this.rate, this.encoding);

  factory MixerFormat.fromJson(Map<Object?, Object?> j) => MixerFormat(j['rate'] as int, j['encoding'] as String);

  final int rate;

  /// `pcm16`, `pcm24`, `pcm32` or `float`.
  final String encoding;

  /// mpv's `audio-format` that fills this format. ao_opensles opens s16, or s32 for anything wider.
  String get mpvFormat => encoding == 'pcm16' ? 's16' : 's32';

  @override
  bool operator ==(Object other) => other is MixerFormat && other.rate == rate && other.encoding == encoding;

  @override
  int get hashCode => Object.hash(rate, encoding);

  @override
  String toString() => '$encoding@$rate';
}

/// A USB audio output and what it takes bit-perfect.
class UsbDevice {
  const UsbDevice(this.id, this.name, this.formats);

  factory UsbDevice.fromJson(Map<Object?, Object?> j) => UsbDevice(j['id'] as int, j['name'] as String, [
    for (final f in (j['formats'] as List? ?? const [])) MixerFormat.fromJson((f as Map).cast()),
  ]);

  final int id;
  final String name;
  final List<MixerFormat> formats;

  /// DoP carries DSD64 in 24-bit PCM at 176.4 kHz and DSD128 at 352.8 kHz; the DAC gets it as 32-bit.
  bool takesDop(int dsdBitRate) => formats.contains(MixerFormat(dsdBitRate ~/ 16, 'pcm32'));

  /// Whether at least DSD64 can go out as DoP.
  bool get dopCapable => takesDop(2822400);
}

/// What [chooseMixer] decided for a song.
@immutable
class MixerChoice {
  const MixerChoice(this.format, {required this.exactRate, required this.exactDepth});

  final MixerFormat format;

  /// The DAC takes the song's own rate.
  final bool exactRate;

  /// The format holds every bit of the song.
  final bool exactDepth;

  /// The song can reach the DAC untouched.
  bool get bitPerfect => exactRate && exactDepth;

  @override
  bool operator ==(Object other) =>
      other is MixerChoice && other.format == format && other.exactRate == exactRate && other.exactDepth == exactDepth;

  @override
  int get hashCode => Object.hash(format, exactRate, exactDepth);
}

/// The mixer format for a song of [rate] and [bits] (16 or wider) out of what the DAC offers, or null if it offers
/// none. 16-bit songs use 16-bit PCM; anything wider uses 32-bit PCM, which holds 24 bits padded. A DAC without the
/// song's rate gets the nearest one (the higher on a tie) and the song is resampled to it, so it isn't bit-perfect.
MixerChoice? chooseMixer(List<MixerFormat> formats, {required int rate, required int bits}) {
  final pcm = formats.where((f) => f.encoding != 'float' && f.encoding != 'pcm24').toList();
  if (pcm.isEmpty) return null;
  final want = bits <= 16 ? 'pcm16' : 'pcm32';
  // A wider format holds a 16-bit song losslessly (padded); a narrower one doesn't hold a wide song.
  var pool = pcm.where((f) => f.encoding == want).toList();
  var exactDepth = true;
  if (pool.isEmpty) {
    pool = pcm;
    exactDepth = want == 'pcm16';
  }
  // Prefer the exact rate in the best-fitting depth, otherwise the nearest rate.
  pool.sort((a, b) {
    final byRate = (a.rate - rate).abs().compareTo((b.rate - rate).abs());
    if (byRate != 0) return byRate;
    if (a.rate != b.rate) return b.rate.compareTo(a.rate);
    return b.encoding.compareTo(a.encoding); // pcm32 over pcm16 at the same rate
  });
  final best = pool.first;
  return MixerChoice(best, exactRate: best.rate == rate, exactDepth: exactDepth);
}

/// Android 14's bit-perfect USB output, through `riflay/usb_dac` (MainActivity / UsbDac.kt).
class UsbDac extends ChangeNotifier {
  UsbDac({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('riflay/usb_dac');

  final MethodChannel _channel;

  /// Android 14 or later.
  bool supported = false;
  List<UsbDevice> devices = const [];

  /// The DAC used: the first one that offers a bit-perfect format.
  UsbDevice? get device => devices.where((d) => d.formats.isNotEmpty).firstOrNull;

  /// What was last set with [prefer], so a song of the same format doesn't set it again.
  MixerFormat? active;

  Future<void> init() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') _read(call.arguments);
    });
    try {
      _read(await _channel.invokeMethod<Object?>('state'));
    } catch (e) {
      debugPrint('USB DAC state: $e');
    }
  }

  void _read(Object? state) {
    if (state is! Map) return;
    supported = state['supported'] as bool? ?? false;
    devices = [for (final d in (state['devices'] as List? ?? const [])) UsbDevice.fromJson((d as Map).cast())];
    // A DAC that was unplugged took the setting with it.
    if (device == null) active = null;
    notifyListeners();
  }

  /// Asks Android to send tracks of exactly [format] to the DAC untouched.
  Future<bool> prefer(MixerFormat format) async {
    final d = device;
    if (d == null) return false;
    if (active == format) return true;
    try {
      final ok =
          await _channel.invokeMethod<bool>('prefer', {
            'device': d.id,
            'rate': format.rate,
            'encoding': format.encoding,
          }) ??
          false;
      active = ok ? format : null;
      return ok;
    } catch (e) {
      debugPrint('USB DAC prefer: $e');
      active = null;
      return false;
    }
  }

  /// Back to Android's normal mixing (other apps and the system sounds are heard again).
  Future<void> clear() async {
    final d = device;
    if (active == null || d == null) {
      active = null;
      return;
    }
    active = null;
    try {
      await _channel.invokeMethod<void>('clear', {'device': d.id});
    } catch (e) {
      debugPrint('USB DAC clear: $e');
    }
  }
}
