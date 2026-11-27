// StreamAudioSource/Response are just_audio's documented way to feed custom byte streams.
// ignore_for_file: experimental_member_use

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/track.dart';
import 'connect_protocol.dart' show connectRef;
import 'connect_store.dart';

/// Riflay Connect, stage 3: a controller plays a shared song with the audio coming straight from the owner's
/// computer. There is no audio server: the bytes travel over a direct connection (see [ConnectRoute]).
///
/// Copyright first. A file is only ever streamed to another person when its owner marked it, in settings, as
/// their own ([ConnectOwnership]). Nothing is marked by default, and a song that came from a streaming service
/// or a download is never eligible ([connectIsOwnFile]), even if someone marks it.

/// True only for a file on this device that Riflay didn't fetch from anywhere: not a YouTube/streamed song, not
/// something downloaded from a service or an extension. These can be marked as "mine"; nothing else can.
bool connectIsOwnFile(Track t) =>
    t.path != null &&
    !t.isRemote &&
    !t.isDownload &&
    !t.isCueTrack &&
    t.sourceUrl == null &&
    t.extensionId == null &&
    t.downloadYoutubeId == null;

/// The songs their owner marked as their own, kept in the preferences. Ids are local and never sent.
class ConnectOwnership extends ChangeNotifier {
  ConnectOwnership(this._ids, {this.onSave, this.loader});

  /// The one this device uses; its marks come from the preferences the first time they are needed.
  static final shared = ConnectOwnership(
    {},
    onSave: (ids) async => (await ConnectStore.open()).saveOwnIds(ids.toList()),
    loader: () async => (await ConnectStore.open()).ownIds,
  );

  final Set<String> _ids;
  final Future<void> Function(Set<String>)? onSave;
  final Future<Iterable<String>> Function()? loader;
  Future<void>? _loaded;

  Future<void> ensureLoaded() => _loaded ??= () async {
    if (loader != null) _ids.addAll(await loader!());
    notifyListeners();
  }();

  /// Whether [t] may be streamed to someone else. The one gate: the host asks this before reading a single byte.
  bool canStream(Track t) => connectIsOwnFile(t) && _ids.contains(t.id);

  /// How many of [tracks] are marked.
  int markedIn(Iterable<Track> tracks) => tracks.where(canStream).length;

  /// Marks or unmarks every eligible song of [tracks]; the rest are left alone (they can't be marked).
  Future<void> mark(Iterable<Track> tracks, bool own) async {
    final eligible = [
      for (final t in tracks)
        if (connectIsOwnFile(t)) t.id,
    ];
    own ? _ids.addAll(eligible) : _ids.removeAll(eligible);
    await onSave?.call(Set.of(_ids));
  }

  /// The song asked for by [ref], only if it may be streamed; null otherwise, and the host answers "no".
  Track? streamable(String ref, Iterable<Track> library) {
    for (final t in library) {
      if (connectRef(t.id) == ref) return canStream(t) ? t : null;
    }
    return null;
  }
}

/// Ways to reach the owner, in the order they are tried.
enum ConnectRoute {
  /// Same network: no NAT to cross, no third party.
  lan,

  /// WebRTC with a public STUN server to find the way through the NAT.
  stun,

  /// WebRTC through a relay the person set up themselves. Never on unless they did.
  turn,
}

/// Why no route worked, so the page can say something true.
enum ConnectRouteFailure { noRoute, ownerNotSharing }

class ConnectRouteResult<T> {
  const ConnectRouteResult.ok(this.route, this.connection) : failure = null;
  const ConnectRouteResult.failed(this.failure) : route = null, connection = null;

  final ConnectRoute? route;
  final T? connection;
  final ConnectRouteFailure? failure;

  bool get ok => connection != null;
}

/// Tries each route in [attempts] in the order LAN → STUN → TURN and keeps the first that connects. A route that
/// is missing (no TURN set up) is skipped; a route that throws or returns null counts as failed. When none works
/// the result says so: it never stays quiet, so the page can suggest the same network.
Future<ConnectRouteResult<T>> connectViaBestRoute<T>(Map<ConnectRoute, Future<T?> Function()> attempts) async {
  for (final route in ConnectRoute.values) {
    final attempt = attempts[route];
    if (attempt == null) continue;
    try {
      final connection = await attempt();
      if (connection != null) return ConnectRouteResult.ok(route, connection);
    } catch (_) {
      // Fall through to the next route.
    }
  }
  return const ConnectRouteResult.failed(ConnectRouteFailure.noRoute);
}

/// The relay and STUN servers a WebRTC connection may use. STUN is a public default (it only tells a device its
/// own public address); TURN is empty unless the person typed their own, and its login stays in this device's
/// preferences, never sent to the broker.
class ConnectIceConfig {
  const ConnectIceConfig({this.stun = defaultStun, this.turnUrl, this.turnUser, this.turnPassword});

  static const defaultStun = 'stun:stun.l.google.com:19302';

  final String stun;
  final String? turnUrl;
  final String? turnUser;
  final String? turnPassword;

  bool get hasTurn => turnUrl != null && turnUrl!.isNotEmpty;

  /// The `iceServers` list as WebRTC wants it.
  List<Map<String, dynamic>> get iceServers => [
    {'urls': stun},
    if (hasTurn) {'urls': turnUrl, 'username': turnUser ?? '', 'credential': turnPassword ?? ''},
  ];
}

/// Asks the owner for bytes `[start, end)` of the song named by [ref]. How it travels (a WebRTC data channel) is
/// the caller's business, so this stays testable without a network.
typedef ConnectRangeFetcher = Future<ConnectRange> Function(String ref, int start, int? end);

class ConnectRange {
  const ConnectRange({required this.sourceLength, required this.stream, required this.contentType});

  final int sourceLength;
  final Stream<List<int>> stream;
  final String contentType;
}

/// A shared song as just_audio sees it, same pattern as `YoutubeAudioSource`: it only asks for bytes when the
/// player does, so a queue of shared songs opens nothing up front.
class ConnectStreamSource extends StreamAudioSource {
  ConnectStreamSource(this.ref, {required this.fetch, super.tag});

  final String ref;
  final ConnectRangeFetcher fetch;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final from = start ?? 0;
    final r = await fetch(ref, from, end);
    final to = (end ?? r.sourceLength).clamp(from, r.sourceLength);
    return StreamAudioResponse(
      sourceLength: r.sourceLength,
      contentLength: to - from,
      offset: from,
      contentType: r.contentType,
      stream: r.stream,
    );
  }
}
