import '../services/video_engine.dart';

/// The web has no window of its own for the video (see native_video.dart).
class NativeVideoPlayer implements VideoEngine {
  NativeVideoPlayer({required int window, required String hwdec, int? maxFps, required bool foreground}) {
    throw UnsupportedError('No native video player on the web');
  }

  static bool get available => false;

  @override
  Duration get position => Duration.zero;
  @override
  bool get playing => false;
  @override
  bool get buffering => false;

  /// The video's width over its height once its first picture is out, else null.
  double? get aspect => null;

  Future<void> open(String url, {Duration start = Duration.zero}) async {}
  Future<bool> firstFrame(Duration timeout) async => false;

  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration to) async {}
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<String> getProperty(String name) async => '';
  @override
  Future<void> setProperty(String name, String value) async {}
  @override
  Future<void> dispose() async {}
}
