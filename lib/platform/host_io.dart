import 'dart:io' show Platform;

/// The operating system, from `dart:io`. See `host.dart`.
abstract final class Host {
  static const isWeb = false;
  static bool get isAndroid => Platform.isAndroid;
  static bool get isIOS => Platform.isIOS;
  static bool get isLinux => Platform.isLinux;
  static bool get isMacOS => Platform.isMacOS;
  static bool get isWindows => Platform.isWindows;
  static Map<String, String> get environment => Platform.environment;
  static String get pathSeparator => Platform.pathSeparator;
  static String get operatingSystem => Platform.operatingSystem;
}
