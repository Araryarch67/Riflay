import 'dart:async';

import 'dart:isolate';

/// Runs [work] in a new isolate. See `background.dart`.
Future<R> inBackground<R>(FutureOr<R> Function() work) => Isolate.run(work);
