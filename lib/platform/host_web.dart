/// The browser: no operating system to ask. See `host.dart`.
abstract final class Host {
  static const isWeb = true;
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isLinux => false;
  static bool get isMacOS => false;
  static bool get isWindows => false;
  static Map<String, String> get environment => const {};
  static String get pathSeparator => '/';
  static String get operatingSystem => 'web';
}
