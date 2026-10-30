import 'dart:async';

/// Runs [work] on the page's only thread, after the current frame's work. See `background.dart`.
Future<R> inBackground<R>(FutureOr<R> Function() work) => Future(work);
