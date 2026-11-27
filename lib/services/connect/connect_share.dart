import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';

import '../../models/track.dart';
import '../player_controller.dart';
import 'connect_channel.dart';
import 'connect_protocol.dart' show connectRef;
import 'connect_store.dart';
import 'connect_stream.dart';

/// Riflay Connect, stage 2: two paired people look at each other's shared albums, artists and playlists.
///
/// Only descriptions travel: a name, an artist, a year, how many songs, and the song titles. A path, a folder, a
/// file, an account or a token is never in a [ShareCollection]: it is built only from [Track.title] and
/// [Track.artist] ([shareOf]), so there is nothing to filter out later.
///
/// It runs on the pair room of stage 1 (same topics, same AES-GCM key): no second channel. Messages, all with a
/// `t` that starts with `shr.`:
///  * `shr.list`   viewer → owner: "what do you share?"
///  * `shr.idx`    owner → viewer: the index, in chunks (`rev`, `seq`, `of`, `items`). Pushed again when it changes.
///  * `shr.get`    viewer → owner: "send me the songs of `id`"
///  * `shr.col`    owner → viewer: the songs of one collection, in chunks (`id`, `v`, `seq`, `of`, `tracks`)
///
/// The owner is the only source. Each collection has a version that goes up when its content changes; the viewer
/// holds whatever version the owner's last index names, and a viewer can't change anything on the owner's side:
/// the owner answers `list` and `get` for what it shares and ignores the rest.

/// The JSON of one chunk's list stays under this, so a message (and its encrypted form) stays small for a public
/// broker however big the collection is.
const shareChunkBytes = 16 * 1024;

/// What one message, encrypted and ready for the broker, may weigh. The tests hold every message to it.
const shareMessageLimit = 24 * 1024;

/// Bounds on what is accepted from the other side, so a bad peer can't make this one hold everything in memory.
const shareMaxTracks = 10000;
const shareMaxCollections = 2000;
const shareMaxChunks = 400;

/// The owner looks for changes in what it shares at most this often.
const shareRefreshEvery = Duration(seconds: 5);

enum ShareKind { album, artist, playlist }

String _clip(String s, int max) => s.length <= max ? s : s.substring(0, max);

class ShareTrack {
  const ShareTrack(this.title, this.artist, {this.ref});

  final String title;
  final String artist;

  /// A hash that names the song for streaming, present only when its owner marked it as their own (see
  /// `ConnectOwnership`). Never a path or an id.
  final String? ref;

  Map<String, dynamic> toJson() => {'t': title, 'a': artist, 'r': ?ref};

  static ShareTrack? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    final t = j['t'], a = j['a'];
    if (t is! String || a is! String) return null;
    final r = j['r'];
    return ShareTrack(
      cleanConnectName(t, fallback: '', max: 200),
      cleanConnectName(a, fallback: '', max: 200),
      ref: r is String && RegExp(r'^[0-9a-f]{16}$').hasMatch(r) ? r : null,
    );
  }
}

/// A line of the index: everything about a collection except its songs.
class ShareEntry {
  const ShareEntry({
    required this.id,
    required this.kind,
    required this.name,
    required this.count,
    this.artist,
    this.year,
    this.version = 0,
  });

  /// A hash of what the owner calls it, never a path or a playlist's real id.
  final String id;
  final ShareKind kind;
  final String name;
  final String? artist;
  final int? year;
  final int count;
  final int version;

  ShareEntry withVersion(int v) =>
      ShareEntry(id: id, kind: kind, name: name, count: count, artist: artist, year: year, version: v);

  Map<String, dynamic> toJson() => {
    'id': id,
    'k': kind.name,
    'n': name,
    'a': ?artist,
    'y': ?year,
    'c': count,
    'v': version,
  };

  static ShareEntry? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    final id = j['id'], n = j['n'], c = j['c'], v = j['v'], a = j['a'], y = j['y'];
    final kind = ShareKind.values.where((k) => k.name == j['k']).firstOrNull;
    if (id is! String || n is! String || c is! int || v is! int || kind == null) return null;
    if (id.length > 64 || c < 0 || v < 0) return null;
    return ShareEntry(
      id: id,
      kind: kind,
      name: cleanConnectName(n, fallback: '', max: 200),
      count: c.clamp(0, shareMaxTracks),
      artist: a is String ? cleanConnectName(a, fallback: '', max: 200) : null,
      year: y is int && y > 0 && y < 10000 ? y : null,
      version: v,
    );
  }
}

class ShareCollection {
  const ShareCollection(this.entry, this.tracks);

  final ShareEntry entry;
  final List<ShareTrack> tracks;

  String get id => entry.id;

  ShareCollection copyWith({String? id, String? name}) => ShareCollection(
    ShareEntry(
      id: id ?? entry.id,
      kind: entry.kind,
      name: name ?? entry.name,
      count: entry.count,
      artist: entry.artist,
      year: entry.year,
      version: entry.version,
    ),
    tracks,
  );

  /// What the content is, without its version: when this changes the version goes up.
  String get digest => crypto.sha256
      .convert(
        utf8.encode(
          jsonEncode([
            (entry.withVersion(0)).toJson(),
            [for (final t in tracks) t.toJson()],
          ]),
        ),
      )
      .toString();

  Map<String, dynamic> toJson() => {
    'e': entry.toJson(),
    'tracks': [for (final t in tracks) t.toJson()],
  };

  static ShareCollection? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    final e = ShareEntry.fromJson(j['e']), tracks = j['tracks'];
    if (e == null || tracks is! List) return null;
    return ShareCollection(e, [for (final t in tracks.take(shareMaxTracks)) ?ShareTrack.fromJson(t)]);
  }
}

/// The one place a local album, artist or playlist becomes something that can be sent: titles and artists only.
ShareCollection shareOf(
  ShareKind kind,
  String key,
  String name,
  Iterable<Track> tracks, {
  String? artist,
  int? year,
  ConnectOwnership? ownership,
}) {
  final list = [
    for (final t in tracks.take(shareMaxTracks))
      ShareTrack(
        _clip(t.title, 200),
        _clip(t.artist, 200),
        ref: ownership?.canStream(t) == true ? connectRef(t.id) : null,
      ),
  ];
  return ShareCollection(
    ShareEntry(
      id: connectRef('share/${kind.name}/$key'),
      kind: kind,
      name: _clip(name, 200),
      artist: artist == null || artist.isEmpty ? null : _clip(artist, 200),
      year: year,
      count: list.length,
    ),
    list,
  );
}

/// Everything this device could share: its albums, artists and playlists. The person picks what actually goes.
List<ShareCollection> shareSourceOf(PlayerController p, {ConnectOwnership? ownership}) => [
  for (final (c, _) in _shareParts(p, ownership)) c,
];

/// The songs behind each shareable collection, by share id. Stays on this device: only [shareSourceOf] is sent.
Map<String, List<Track>> shareTracksOf(PlayerController p) => {
  for (final (c, tracks) in _shareParts(p, null)) c.id: tracks,
};

Iterable<(ShareCollection, List<Track>)> _shareParts(PlayerController p, ConnectOwnership? o) sync* {
  for (final c in p.albums) {
    final key = '${c.title.toLowerCase()}|${c.subtitle.toLowerCase()}';
    yield (shareOf(ShareKind.album, key, c.title, c.tracks, artist: c.subtitle, ownership: o), c.tracks);
  }
  for (final c in p.artists) {
    yield (shareOf(ShareKind.artist, c.title.toLowerCase(), c.title, c.tracks, ownership: o), c.tracks);
  }
  for (final l in p.playlists) {
    yield (shareOf(ShareKind.playlist, l.id, l.name, l.tracks, ownership: o), l.tracks);
  }
}

/// Splits [items] so each piece's JSON stays within [maxBytes]; always at least one piece, so an empty list still
/// says "nothing" to the other side.
List<List<Map<String, dynamic>>> shareChunks(List<Map<String, dynamic>> items, {int maxBytes = shareChunkBytes}) {
  final out = <List<Map<String, dynamic>>>[];
  var cur = <Map<String, dynamic>>[];
  var size = 2;
  for (final item in items) {
    final n = utf8.encode(jsonEncode(item)).length + 1;
    if (cur.isNotEmpty && size + n > maxBytes) {
      out.add(cur);
      cur = [];
      size = 2;
    }
    cur.add(item);
    size += n;
  }
  out.add(cur);
  return out;
}

/// What the owner remembers of a collection: its content hash and the version that goes with it.
class ShareStamp {
  const ShareStamp(this.digest, this.version);
  final String digest;
  final int version;
}

/// The versions after looking at the content now: the same content keeps its number, changed content goes up by
/// one, a first sight starts at 1. Collections no longer shared stay in [old], so sharing one again with
/// changes can't reuse a number a viewer already holds.
Map<String, ShareStamp> nextStamps(Map<String, ShareStamp> old, Map<String, String> digests) {
  final next = {...old};
  for (final e in digests.entries) {
    final was = old[e.key];
    if (was == null) {
      next[e.key] = ShareStamp(e.value, 1);
    } else if (was.digest != e.value) {
      next[e.key] = ShareStamp(e.value, was.version + 1);
    }
  }
  return next;
}

/// The sharing side: holds what is picked, numbers versions and answers requests. It reads nothing else.
class ShareOwner {
  ShareOwner({required this.source, Set<String>? selected, Map<String, ShareStamp>? stamps, int Function()? clock})
    : selected = selected ?? {},
      stamps = stamps ?? {},
      _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final List<ShareCollection> Function() source;
  final Set<String> selected;
  Map<String, ShareStamp> stamps;
  final int Function() _clock;

  /// Goes up whenever the index changes, and with the clock, so a viewer can drop an index older than one it has.
  int rev = 0;
  String? _signature;

  /// What is shared now, versions up to date. A picked collection that no longer exists is simply absent.
  List<ShareCollection> shared() {
    final all = <String, ShareCollection>{for (final c in source()) c.id: c};
    final mine = [for (final id in selected) ?all[id]];
    stamps = nextStamps(stamps, {for (final c in mine) c.id: c.digest});
    mine.sort((a, b) {
      final k = a.entry.kind.index.compareTo(b.entry.kind.index);
      return k != 0 ? k : a.entry.name.toLowerCase().compareTo(b.entry.name.toLowerCase());
    });
    return [for (final c in mine) ShareCollection(c.entry.withVersion(stamps[c.id]!.version), c.tracks)];
  }

  /// True when the index now differs from the last one worked out: time to tell the viewers.
  bool refresh([List<ShareCollection>? now]) {
    final s = (now ?? shared()).map((c) => '${c.id}@${c.entry.version}').join(',');
    if (s == _signature) return false;
    _signature = s;
    rev = rev + 1 > _clock() ? rev + 1 : _clock();
    return true;
  }

  List<Map<String, dynamic>> indexMessages() {
    final now = shared();
    refresh(now);
    final chunks = shareChunks([for (final c in now.take(shareMaxCollections)) c.entry.toJson()]);
    return [
      for (final (i, items) in chunks.indexed)
        {'t': 'shr.idx', 'rev': rev, 'seq': i, 'of': chunks.length, 'items': items},
    ];
  }

  /// The songs of [id], if it is shared; nothing for anything else, so asking for an id that isn't shared tells
  /// the viewer nothing.
  List<Map<String, dynamic>> collectionMessages(String id) {
    final c = shared().where((c) => c.id == id).firstOrNull;
    if (c == null) return const [];
    final chunks = shareChunks([for (final t in c.tracks) t.toJson()]);
    return [
      for (final (i, tracks) in chunks.indexed)
        {'t': 'shr.col', 'id': id, 'v': c.entry.version, 'seq': i, 'of': chunks.length, 'tracks': tracks},
    ];
  }

  /// The replies to a viewer's [m]; empty for anything that isn't a read request.
  List<Map<String, dynamic>> answer(Map<String, dynamic> m) => switch (m['t']) {
    'shr.list' => indexMessages(),
    'shr.get' => m['id'] is String ? collectionMessages(m['id'] as String) : const [],
    _ => const [],
  };
}

/// The looking side: the owner's index and the collections fetched so far. Read-only: nothing here is sent back
/// to change the owner's side.
class ShareViewer {
  /// What the owner shares now, as of the newest index.
  List<ShareEntry> entries = const [];
  final cache = <String, ShareCollection>{};
  final loading = <String>{};
  bool listed = false;

  /// A `shr.list` was sent since the connection came up.
  bool asked = false;
  int _rev = -1;
  int? _partRev;
  final _idxParts = <int, List<ShareEntry>>{};
  int _idxOf = 0;
  final _colParts = <String, ({int v, int of, Map<int, List<ShareTrack>> parts})>{};

  ShareCollection? loaded(String id) => cache[id];

  /// True when [id]'s cached copy is the version the owner's index names.
  bool isCurrent(ShareEntry e) => cache[e.id]?.entry.version == e.version;

  /// Handles a message from the owner; returns the requests to send back.
  List<Map<String, dynamic>> handle(Map<String, dynamic> m) {
    switch (m['t']) {
      case 'shr.idx':
        return _index(m);
      case 'shr.col':
        _collection(m);
    }
    return const [];
  }

  List<Map<String, dynamic>> _index(Map<String, dynamic> m) {
    final rev = m['rev'], seq = m['seq'], of = m['of'], items = m['items'];
    if (rev is! int || seq is! int || of is! int || items is! List) return const [];
    if (of < 1 || of > shareMaxChunks || seq < 0 || seq >= of || rev <= _rev) return const [];
    // An index older than the one held is a replay or arrived late: the owner's newest word stands.
    if (rev != _partRev || of != _idxOf) {
      _partRev = rev;
      _idxOf = of;
      _idxParts.clear();
    }
    _idxParts[seq] = [for (final e in items) ?ShareEntry.fromJson(e)];
    if (_idxParts.length < of) return const [];
    _rev = rev;
    entries = [for (var i = 0; i < of; i++) ..._idxParts[i]!].take(shareMaxCollections).toList();
    _idxParts.clear();
    _partRev = null;
    listed = true;
    final ids = {for (final e in entries) e.id};
    // Taken back by the owner: gone here too.
    cache.removeWhere((id, _) => !ids.contains(id));
    loading.removeWhere((id) => !ids.contains(id));
    _colParts.removeWhere((id, _) => !ids.contains(id));
    // The owner is the source: a copy that isn't the version it names is fetched again, older or newer.
    return [
      for (final e in entries)
        if (cache.containsKey(e.id) && !isCurrent(e)) ...request(e.id),
    ];
  }

  /// The `shr.get` for [id], unless it's already here or on its way.
  List<Map<String, dynamic>> request(String id) {
    final e = entries.where((e) => e.id == id).firstOrNull;
    if (e == null || loading.contains(id) || (cache.containsKey(id) && isCurrent(e))) return const [];
    loading.add(id);
    return [
      {'t': 'shr.get', 'id': id},
    ];
  }

  void _collection(Map<String, dynamic> m) {
    final id = m['id'], v = m['v'], seq = m['seq'], of = m['of'], tracks = m['tracks'];
    if (id is! String || v is! int || seq is! int || of is! int || tracks is! List) return;
    final entry = entries.where((e) => e.id == id).firstOrNull;
    // Not in the index, or not the version the index names: not for us (yet).
    if (entry == null || entry.version != v || of < 1 || of > shareMaxChunks || seq < 0 || seq >= of) return;
    var part = _colParts[id];
    if (part == null || part.v != v || part.of != of) {
      part = (v: v, of: of, parts: <int, List<ShareTrack>>{});
      _colParts[id] = part;
    }
    part.parts[seq] = [for (final t in tracks) ?ShareTrack.fromJson(t)];
    if (part.parts.length < of) return;
    _colParts.remove(id);
    loading.remove(id);
    final all = [for (var i = 0; i < of; i++) ...part.parts[i]!].take(shareMaxTracks).toList();
    cache[id] = ShareCollection(entry, all);
  }
}

class _Peer {
  _Peer(this.name);

  String name;
  void Function(Map<String, dynamic>)? send;

  /// Something from the other side arrived since it was attached.
  bool heard = false;
}

/// Sharing for this device: what it shares, what others share with it, and the local copies. One per player; the
/// controller and host of stage 1 hand it the messages of each pair room ([attach], [heard], [handle], [detach]).
class ConnectShare extends ChangeNotifier {
  ConnectShare({
    required this.source,
    this.changes,
    Future<ConnectStore> Function()? openStore,
    int Function()? clock,
    this.refreshEvery = shareRefreshEvery,
  }) : _openStore = openStore ?? ConnectStore.open,
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  static final _instances = Expando<ConnectShare>('ConnectShare');

  static ConnectShare of(PlayerController c) => _instances[c] ??= ConnectShare(
    source: () => shareSourceOf(c, ownership: ConnectOwnership.shared),
    changes: Listenable.merge([c, ConnectOwnership.shared]),
  );

  @visibleForTesting
  static void use(PlayerController c, ConnectShare s) => _instances[c] = s;

  final List<ShareCollection> Function() source;

  /// Tells when the library may have changed (the player); watched only while someone is connected.
  final Listenable? changes;
  final Future<ConnectStore> Function() _openStore;
  final int Function() _clock;
  final Duration refreshEvery;

  ConnectStore? _store;
  ShareOwner? _owner;
  Future<void>? _loading;
  var _copies = <ShareCollection>[];
  final _peers = <String, _Peer>{};
  final _viewers = <String, ShareViewer>{};
  Timer? _timer;
  var _watching = false;

  bool get loaded => _owner != null;

  Future<void> load() => _loading ??= () async {
    unawaited(ConnectOwnership.shared.ensureLoaded());
    final store = _store = await _openStore();
    final owner = ShareOwner(
      source: source,
      selected: store.sharedIds.toSet(),
      stamps: store.shareStamps,
      clock: _clock,
    );
    _owner = owner;
    _copies = store.shareCopies;
    notifyListeners();
  }();

  // --- What this device shares ---------------------------------------------------------------------------------

  /// Everything that could be shared, to pick from. Worked out on each call: keep the result while a page is open.
  List<ShareCollection> candidates() => source();

  Set<String> get selected => Set.unmodifiable(_owner?.selected ?? const <String>{});

  /// Starts or stops sharing one collection. Stopping takes it away from every viewer at once.
  Future<void> setShared(String id, bool on) async {
    await load();
    final owner = _owner!;
    if (on ? !owner.selected.add(id) : !owner.selected.remove(id)) return;
    await _store!.saveSharedIds(owner.selected.toList());
    await _push();
    notifyListeners();
  }

  /// Sends the index to everyone connected when it changed.
  Future<void> _push() async {
    final owner = _owner;
    if (owner == null) return;
    final before = owner.rev;
    final messages = owner.indexMessages();
    if (owner.rev == before) return;
    await _store!.saveShareStamps(owner.stamps);
    for (final p in _peers.values) {
      if (p.heard) messages.forEach(p.send!);
    }
  }

  void _libraryChanged() {
    if (_timer?.isActive ?? false) return;
    final owner = _owner;
    if (owner == null || owner.selected.isEmpty) return;
    _timer = Timer(refreshEvery, () => unawaited(_push()));
  }

  // --- What others share with this device ----------------------------------------------------------------------

  /// The other side of a pair, by the local id the pairing has.
  ShareViewer? viewerOf(String peerId) => _viewers[peerId];

  /// Paired devices that have something to show, or are here now.
  List<({String id, String name, bool connected, ShareViewer viewer})> get peers => [
    for (final e in _viewers.entries)
      (id: e.key, name: _peers[e.key]?.name ?? '', connected: _peers[e.key]?.send != null, viewer: e.value),
  ];

  /// A pair room is up: [send] puts a message in it.
  void attach(String peerId, String name, void Function(Map<String, dynamic>) send) {
    unawaited(load());
    _peers[peerId] = _Peer(name)..send = send;
    _viewers.putIfAbsent(peerId, ShareViewer.new).asked = false;
    if (!_watching && changes != null) {
      changes!.addListener(_libraryChanged);
      _watching = true;
    }
    notifyListeners();
  }

  void detach(String peerId) {
    _peers[peerId]?.send = null;
    _peers[peerId]?.heard = false;
    if (_watching && _peers.values.every((p) => p.send == null)) {
      changes?.removeListener(_libraryChanged);
      _watching = false;
    }
    notifyListeners();
  }

  /// The pairing is over: nothing of that device stays.
  void forget(String peerId) {
    detach(peerId);
    _peers.remove(peerId);
    _viewers.remove(peerId);
    notifyListeners();
  }

  /// A message arrived from the other side, so it is there: ask what it shares, once per connection.
  void heard(String peerId) {
    final peer = _peers[peerId], viewer = _viewers[peerId];
    if (peer?.send == null || viewer == null) return;
    peer!.heard = true;
    if (!viewer.asked) requestList(peerId);
  }

  /// Asks the other side for its index again.
  void requestList(String peerId) {
    final peer = _peers[peerId], viewer = _viewers[peerId];
    if (peer?.send == null || viewer == null) return;
    viewer.asked = true;
    peer!.send!({'t': 'shr.list'});
  }

  /// Asks for the songs of one shared collection, if not here yet.
  void open(String peerId, String id) {
    final peer = _peers[peerId], viewer = _viewers[peerId];
    if (peer?.send == null || viewer == null) return;
    viewer.request(id).forEach(peer!.send!);
    notifyListeners();
  }

  /// Whether [m] is one of this protocol's messages, for the room's own handler to pass on.
  static bool isShare(Map<String, dynamic> m) => m['t'] is String && (m['t'] as String).startsWith('shr.');

  /// Applies a share message from [peerId]: answers a request, or takes in what the owner sent.
  Future<void> handle(String peerId, Map<String, dynamic> m) async {
    await load();
    final peer = _peers[peerId], viewer = _viewers[peerId];
    final send = peer?.send;
    if (peer == null || viewer == null || send == null) return;
    peer.heard = true;
    switch (m['t']) {
      case 'shr.list' || 'shr.get':
        // The owner side: a viewer may only read what is shared.
        _owner!.answer(m).forEach(send);
        unawaited(_store!.saveShareStamps(_owner!.stamps));
      case 'shr.idx' || 'shr.col':
        viewer.handle(m).forEach(send);
        notifyListeners();
    }
  }

  // --- Local copies: the only thing that can be changed -------------------------------------------------------

  /// Copies kept on this device, no longer following the owner.
  List<ShareCollection> get copies => List.unmodifiable(_copies);

  Future<void> saveCopy(ShareCollection c) async {
    await load();
    _copies = [..._copies, c.copyWith(id: 'copy/${_clock()}/${_copies.length}')];
    await _store!.saveShareCopies(_copies);
    notifyListeners();
  }

  Future<void> renameCopy(String id, String name) async {
    final clean = cleanConnectName(name, fallback: '', max: 200);
    if (clean.isEmpty) return;
    _copies = [for (final c in _copies) c.id == id ? c.copyWith(name: clean) : c];
    await _store?.saveShareCopies(_copies);
    notifyListeners();
  }

  Future<void> removeCopy(String id) async {
    _copies = [..._copies.where((c) => c.id != id)];
    await _store?.saveShareCopies(_copies);
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_watching) changes?.removeListener(_libraryChanged);
    super.dispose();
  }
}
