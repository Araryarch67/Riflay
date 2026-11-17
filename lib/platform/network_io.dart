import 'dart:io';

import '../services/network_settings.dart';

/// Native builds use a configured HTTP forward proxy, if enabled. See `network.dart`.
Uri? get webProxy => null;

/// Runs the app. See `network.dart`.
R runWithNetwork<R>(R Function() body) => HttpOverrides.runWithHttpOverrides(body, _NetworkOverrides());

class _NetworkOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = NetworkSettings.instance.route;
}

/// Whether the browser plays Opus in WebM. See `network.dart`.
bool get playsOpus => true;

/// The page's title. See `network.dart`; native windows keep their own.
String get pageTitle => 'Riflay';
set pageTitle(String title) {}
