/// What Video mode needs from the player that draws the music video: where it is, play / pause, seek, speed, and
/// mpv's properties. media_kit's player (drawn by Flutter through a texture) and Windows' own-window player
/// (`platform/native_video.dart`) both answer it.
abstract interface class VideoEngine {
  Duration get position;
  bool get playing;
  bool get buffering;

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration to);
  Future<void> setRate(double rate);
  Future<String> getProperty(String name);
  Future<void> setProperty(String name, String value);
  Future<void> dispose();
}
