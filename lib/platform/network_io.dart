/// No proxy: native builds call every service directly. See `network.dart`.
Uri? get webProxy => null;

/// Runs the app. See `network.dart`.
R runWithNetwork<R>(R Function() body) => body();

/// Whether the browser plays Opus in WebM. See `network.dart`.
bool get playsOpus => true;
