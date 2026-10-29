import 'dart:async';

/// One guest's connection, as the host sees it.
abstract class ListenPeer {
  /// Unique per connection within a session.
  String get id;

  /// Text frames from this guest (encoded [ListenMessage]s). Ends when the guest is gone.
  Stream<String> get incoming;

  void send(String message);

  Future<void> close();
}

/// How a host is reached. A session uses exactly one: the same Wi-Fi
/// ([LanHostTransport]) or the internet through a relay ([RelayHostTransport]).
abstract class ListenHostTransport {
  /// Starts accepting guests. Returns what a guest needs to join: a short
  /// code they type, also encoded in [joinLink].
  Future<void> start();

  /// Six characters a guest can type, e.g. "K7Q2XM". Known after [start].
  String get code;

  /// e.g. `riflay://listen?...`, for a QR code or a shared link. Known after [start].
  Uri get joinLink;

  /// A guest connected; their first message should be a Hello.
  Stream<ListenPeer> get peers;

  Future<void> stop();
}

/// A guest's connection to the host.
abstract class ListenGuestConnection {
  Stream<String> get incoming;

  void send(String message);

  Future<void> close();
}

/// A session a guest could join, found without typing a code (same Wi-Fi only).
class FoundSession {
  const FoundSession({required this.hostName, required this.code, required this.joinLink});

  final String hostName;
  final String code;
  final Uri joinLink;
}
