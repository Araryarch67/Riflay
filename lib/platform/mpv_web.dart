/// The libmpv player's surface the app uses. No player in a browser is one. See `mpv.dart`.
abstract interface class NativePlayer {
  Future<void> setProperty(String property, String value, {bool waitForInitialization = true});
  Future<String> getProperty(String property, {bool waitForInitialization = true});
  Future<void> command(List<String> command, {bool waitForInitialization = true});
  List<Future<void> Function()> get onLoadHooks;
  List<Future<void> Function()> get onUnloadHooks;
}
