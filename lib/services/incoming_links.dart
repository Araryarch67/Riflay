import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../platform/host.dart';
import '../platform/link_relay.dart';
import 'youtube_links.dart';

/// YouTube links other apps hand to Riflay, wherever the system lets them:
///
/// - Android: "Open with" and the Share sheet (intent filters in `AndroidManifest.xml`; `MainActivity.kt`
///   keeps the link until Dart takes it over `riflay/incoming_link`, on a cold start and while running).
/// - Computers: a link on the command line (`riflay https://youtu.be/…`, or the desktop file's `%U`). While
///   Riflay already runs, the new process hands it to that copy and quits (`lib/platform/link_relay_io.dart`).
/// - Web: the installed web app's share target and `?text=` / `?url=` in the page's address.
///
/// The home shell opens them (`_openIncoming`): a song plays, a playlist or album opens.
/// Off with `RIFLAY_NO_OPEN_LINKS`: nothing is taken (Android still lists Riflay; opening it just starts it).
class IncomingLinks {
  IncomingLinks._();

  static final instance = IncomingLinks._();

  static const enabled = !bool.fromEnvironment('RIFLAY_NO_OPEN_LINKS');

  static const _channel = MethodChannel('riflay/incoming_link');

  /// The YouTube link in [text]: a link alone, or a whole shared message with one somewhere in it.
  /// Bare ids don't count, so a shared sentence is never read as one.
  static YoutubeLink? read(String text) => YoutubeLinks.parse(text);

  final _waiting = <String>[];
  void Function(String text)? _handler;

  /// [handler] gets every link from now on, and the ones that came before anyone listened.
  void listen(void Function(String text) handler) {
    _handler = handler;
    final waiting = [..._waiting];
    _waiting.clear();
    waiting.forEach(handler);
  }

  void stopListening(void Function(String text) handler) {
    if (_handler == handler) _handler = null;
  }

  @visibleForTesting
  void add(String text) {
    if (!enabled || text.trim().isEmpty) return;
    if (_handler case final handler?) {
      handler(text);
    } else {
      _waiting.add(text);
    }
  }

  /// Computers, before the window shows: a link given while Riflay already runs goes to that copy, and
  /// this process quits there and then.
  static Future<void> handOff(List<String> args) async {
    if (enabled) await handOffToRunningCopy(args.where(YoutubeLinks.looksLikeLink).toList());
  }

  /// Starts taking links. [args] are the command line's (computers).
  Future<void> start(List<String> args) async {
    if (!enabled) return;
    args.where(YoutubeLinks.looksLikeLink).forEach(add);
    pageLinks().forEach(add);
    if (Host.isAndroid) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'available') await _take();
      });
      await _take();
    }
    await listenForHandOffs(add);
  }

  Future<void> _take() async {
    try {
      final text = await _channel.invokeMethod<String>('take');
      if (text != null) add(text);
    } on PlatformException catch (e) {
      debugPrint('Incoming link: $e');
    }
  }
}
