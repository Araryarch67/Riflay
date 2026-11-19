import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../platform/host.dart';
import '../platform/link_relay.dart';
import '../platform/features.dart';
import 'soundcloud.dart';
import 'youtube_links.dart';
import 'monochrome.dart';
import 'system_tray.dart';

/// YouTube (and SoundCloud) links other apps hand to Riflay, wherever the system lets them:
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

  /// The SoundCloud link in [text], when there is no YouTube one (and this build has SoundCloud).
  static SoundcloudLink? readSoundcloud(String text) =>
      Features.soundcloud && YoutubeLinks.parse(text) == null ? SoundcloudLink.parse(text) : null;

  /// Whether a command-line argument is a link Riflay opens.
  static bool isLink(String arg) =>
      YoutubeLinks.looksLikeLink(arg) ||
      (Features.soundcloud && SoundcloudLink.looksLikeLink(arg)) ||
      MonochromeLink.parse(arg) != null;

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

  bool _windowReady = false;
  bool _activationWaiting = false;

  void _activate() {
    if (_windowReady) {
      SystemTray.bringToFront().ignore();
    } else {
      _activationWaiting = true;
    }
  }

  /// Claims the production desktop instance before initializing the player and tray.
  Future<void> claimDesktop(List<String> args) => startDesktopRelay(
    enabled ? args.where(isLink).toList() : const [],
    onLink: (text) {
      if (isLink(text)) add(text);
    },
    onActivate: _activate,
  );

  /// Starts taking links. [args] are the command line's (computers).
  Future<void> start(List<String> args) async {
    _windowReady = true;
    if (_activationWaiting) {
      _activationWaiting = false;
      _activate();
    }
    if (!enabled) return;
    args.where(isLink).forEach(add);
    pageLinks().forEach(add);
    if (Host.isAndroid) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'available') await _take();
      });
      await _take();
    }
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
