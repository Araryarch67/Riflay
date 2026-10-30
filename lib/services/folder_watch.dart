import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import '../platform/background.dart';
import '../platform/host.dart';
import 'ios_folders.dart';
import 'player_controller.dart';

// ── Pure rules (no files, no clocks of their own: tested with fake events) ──────────────────────────────────────

/// What a file looked like the last time we listed its folder.
@immutable
class FileStamp {
  const FileStamp(this.size, this.modifiedMs);

  final int size;
  final int modifiedMs;

  @override
  bool operator ==(Object other) => other is FileStamp && other.size == size && other.modifiedMs == modifiedMs;

  @override
  int get hashCode => Object.hash(size, modifiedMs);

  @override
  String toString() => 'FileStamp($size, $modifiedMs)';
}

/// Every music file (and cue sheet, and SACD image) under a folder: path -> stamp.
typedef FolderSnapshot = Map<String, FileStamp>;

/// Files that are music for the library: songs, cue sheets and SACD images (what a folder scan reads).
bool isLibraryFile(String path) {
  final lower = path.toLowerCase();
  return Track.isAudioPath(path) || lower.endsWith('.cue') || lower.endsWith('.iso');
}

final _fragment = RegExp(r'\.f\d+\.\w+$'); // yt-dlp's separate video / audio pieces: name.f251.webm
const _partialExtensions = {
  'part',
  'tmp',
  'temp',
  'crdownload',
  'partial',
  'download',
  'swp',
  'swx',
  'ytdl',
  'opdownload',
  'filepart',
  'bc!',
  '!ut',
};

/// Files that are still being written or that a program keeps for itself: temp and partial downloads, editor
/// swap files, anything hidden. [root] makes folders above it (like a hidden home folder) not count.
bool isIgnoredPath(String path, {String? root}) {
  final relative = root != null && p.isWithin(root, path) ? p.relative(path, from: root) : path;
  final parts = p.split(relative);
  for (final part in parts) {
    if (part.startsWith('.') && part != '.' && part != '..') return true;
  }
  final name = p.basename(path);
  if (name.startsWith('~') || name.endsWith('~') || name.startsWith('#')) return true;
  final lower = name.toLowerCase();
  if (lower.contains('.part')) return true;
  if (_fragment.hasMatch(lower)) return true;
  return _partialExtensions.contains(p.extension(lower).replaceFirst('.', ''));
}

/// What changed between two listings of the same folder.
class SnapshotDiff {
  const SnapshotDiff({required this.added, required this.removed, required this.changed});

  final Set<String> added;
  final Set<String> removed;

  /// Same path, different size or modification time.
  final Set<String> changed;

  bool get isEmpty => added.isEmpty && removed.isEmpty && changed.isEmpty;
}

SnapshotDiff diffSnapshots(FolderSnapshot before, FolderSnapshot after) => SnapshotDiff(
  added: {
    for (final k in after.keys)
      if (!before.containsKey(k)) k,
  },
  removed: {
    for (final k in before.keys)
      if (!after.containsKey(k)) k,
  },
  changed: {
    for (final e in after.entries)
      if (before[e.key] case final old? when old != e.value) e.key,
  },
);

/// Waits out file events before anyone looks at them: a copy fires dozens of events while the file grows. A
/// path is ready once it has been quiet for [quiet] and its size is the same on two looks in a row; a path
/// that no longer has a size (deleted, or a folder) is ready as soon as it is quiet.
class ChangeSettler {
  ChangeSettler({this.quiet = const Duration(seconds: 3)});

  final Duration quiet;
  final Map<String, ({DateTime last, int? checkedSize, bool checked})> _pending = {};

  bool get isEmpty => _pending.isEmpty;
  int get length => _pending.length;

  void note(String path, DateTime now) {
    final old = _pending[path];
    _pending[path] = (last: now, checkedSize: old?.checkedSize, checked: old?.checked ?? false);
  }

  /// The paths that can be looked at now; they leave the queue. [sizeOf] is null for a path with no file.
  List<String> ready(DateTime now, int? Function(String path) sizeOf) {
    final done = <String>[];
    for (final e in _pending.entries.toList()) {
      if (now.difference(e.value.last) < quiet) continue;
      final size = sizeOf(e.key);
      if (size == null || (e.value.checked && e.value.checkedSize == size)) {
        done.add(e.key);
        _pending.remove(e.key);
      } else {
        _pending[e.key] = (last: e.value.last, checkedSize: size, checked: true);
      }
    }
    return done;
  }
}

/// Phones can't watch folders: look again when the app comes back, but not more often than [interval].
bool shouldRescan({required DateTime? last, required DateTime now, required Duration interval}) =>
    last == null || now.difference(last) >= interval;

/// What a look at a folder found out, for the library to apply.
class FolderPlan {
  const FolderPlan({
    this.addedPaths = const [],
    this.removedIds = const {},
    this.moved = const {},
    this.retagIds = const {},
  });

  /// New music files, cue sheets and SACD images, to read like a folder scan does.
  final List<String> addedPaths;

  /// Library songs whose file is gone.
  final Set<String> removedIds;

  /// Old song id -> the same song at its new place (everything but the path kept: tags, playlists, history).
  final Map<String, Track> moved;

  /// Songs whose file changed on disk: their tags are read again.
  final Set<String> retagIds;

  bool get isEmpty => addedPaths.isEmpty && removedIds.isEmpty && moved.isEmpty && retagIds.isEmpty;

  int get count => addedPaths.length + removedIds.length + moved.length + retagIds.length;
}

/// A plain file track (not a slice of a cue sheet, not an SACD song): its id is its file's address.
bool _isPlainFile(Track t) => t.path != null && !t.isRemote && !t.isCueTrack && t.id == t.uri.toString();

/// [old] at [newPath]: same tags, added date, source and, through the plan, the same playlists and history.
Track movedTo(Track old, String newPath) {
  final uri = Uri.file(newPath);
  return Track(
    id: uri.toString(),
    uri: uri,
    title: old.title,
    artist: old.artist,
    album: old.album,
    duration: old.duration,
    trackNumber: old.trackNumber,
    discNumber: old.discNumber,
    addedAt: old.addedAt,
    tagged: old.tagged,
    sourceUrl: old.sourceUrl,
    artworkUrl: old.artworkUrl,
    artistId: old.artistId,
  );
}

/// Works out what the library has to do so it matches [disk], the listing of [root].
///
/// - A file that is new is added; one the person removed from the library on purpose ([excluded]) is not.
/// - A library song whose file is gone is removed, only when the file really isn't there ([exists]) and the
///   folder doesn't look unplugged (a listing with nothing in it while the library has songs from it).
/// - A song that vanished while a file of the same kind appeared is a move or a rename: it is matched by the
///   exact size from [previous] (the last listing) or, without one, by the file name, and only when exactly
///   one pair fits. It keeps its tags and playlists. The new file is not read yet, so the length and tags are
///   not compared; an exact byte size is what tells the same file apart.
/// - A song whose size or modification time changed since [previous] has its tags read again.
FolderPlan planSync({
  required String root,
  required FolderSnapshot disk,
  FolderSnapshot? previous,
  required Iterable<Track> library,
  Set<String> excluded = const {},
  bool Function(String path)? exists,
}) {
  final fileExists = exists ?? (String path) => File(path).existsSync();
  final inRoot = [
    for (final t in library)
      if (t.path != null && !t.isRemote && p.isWithin(root, t.path!)) t,
  ];
  final knownPaths = {for (final t in inRoot) t.path!};

  final added = [
    for (final path in disk.keys)
      if (!knownPaths.contains(path) && !excluded.contains(path)) path,
  ]..sort();

  // An empty listing of a folder that had music is a drive that isn't there, not a deleted library.
  final unavailable = disk.isEmpty && inRoot.isNotEmpty;
  final gone = unavailable
      ? const <Track>[]
      : [
          for (final t in inRoot)
            if (!disk.containsKey(t.path!) && !fileExists(t.path!)) t,
        ];

  // Moves: one gone song <-> one new file, never a guess between several.
  final newSongs = [
    for (final a in added)
      if (Track.isAudioPath(a)) a,
  ];
  final claims = <Track, String>{};
  for (final t in gone.where(_isPlainFile)) {
    final ext = p.extension(t.path!).toLowerCase();
    final old = previous?[t.path!];
    var fits = [
      for (final a in newSongs)
        if (p.extension(a).toLowerCase() == ext && (old == null || disk[a]!.size == old.size)) a,
    ];
    final sameName = [
      for (final a in fits)
        if (p.basename(a).toLowerCase() == p.basename(t.path!).toLowerCase()) a,
    ];
    if (old == null) {
      fits = sameName; // no size to go by: only the same name counts
    } else if (fits.length > 1) {
      fits = sameName;
    }
    if (fits.length == 1) claims[t] = fits.single;
  }
  final claimedBy = <String, int>{};
  for (final a in claims.values) {
    claimedBy[a] = (claimedBy[a] ?? 0) + 1;
  }
  final moved = <String, Track>{};
  final taken = <String>{};
  for (final e in claims.entries) {
    if (claimedBy[e.value] != 1) continue;
    moved[e.key.id] = movedTo(e.key, e.value);
    taken.add(e.value);
  }

  final retag = <String>{};
  if (previous != null) {
    for (final t in inRoot) {
      final now = disk[t.path!];
      final before = previous[t.path!];
      if (now != null && before != null && now != before && _isPlainFile(t)) retag.add(t.id);
    }
  }

  return FolderPlan(
    addedPaths: [
      for (final a in added)
        if (!taken.contains(a)) a,
    ],
    removedIds: {
      for (final t in gone)
        if (!moved.containsKey(t.id)) t.id,
    },
    moved: moved,
    retagIds: retag,
  );
}

/// Lists the music under [root] with sizes and times, without opening any file. Null when the folder can't
/// be read (not there, no permission, drive unplugged). Runs on a background isolate in the app.
FolderSnapshot? readSnapshotSync(String root) {
  final top = Directory(root);
  if (!top.existsSync()) return null;
  final found = <String, FileStamp>{};
  final pending = [top];
  var first = true;
  while (pending.isNotEmpty) {
    final dir = pending.removeLast();
    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException {
      if (first) return null; // the folder itself: say so; a subfolder: skip it
      continue;
    }
    first = false;
    for (final e in entries) {
      if (isIgnoredPath(e.path, root: root)) continue;
      if (e is Directory) {
        pending.add(e);
      } else if (e is File && isLibraryFile(e.path)) {
        try {
          final s = e.statSync();
          found[e.path] = FileStamp(s.size, s.modified.millisecondsSinceEpoch);
        } on FileSystemException {
          // gone between the listing and now: the next look settles it
        }
      }
    }
  }
  return found;
}

// ── The watcher ─────────────────────────────────────────────────────────────────────────────────────────────

/// Keeps the library matching the music folders the person added.
///
/// Computers watch each folder (`Directory.watch`, recursive) and look again once the files have settled. If
/// watching can't start (Linux's inotify limit) or breaks, that folder is looked at every few minutes instead.
/// Phones can't watch: the folders are looked at when the app starts and whenever it comes back to the
/// foreground, at most every [phoneInterval]. A "look" lists the folder with sizes and times; tags are read
/// only for new or changed files, never for the ones that stayed the same.
///
/// Folders added before this existed aren't known (the library never kept them): adding the folder again once
/// makes it watched, and nothing is duplicated.
class FolderWatch extends ChangeNotifier with WidgetsBindingObserver {
  FolderWatch._();

  static final FolderWatch instance = FolderWatch._();

  static const _enabledKey = 'library.keepUpToDate.v1';
  static const _foldersKey = 'library.folders.v1';
  static const _excludedKey = 'library.excluded.v1';

  static const phoneInterval = Duration(minutes: 10);
  static const pollInterval = Duration(minutes: 3);
  static const _tick = Duration(seconds: 2);

  /// The first look after launch waits this long, so it doesn't compete with the first frames.
  static const firstLookDelay = Duration(seconds: 8);

  static bool get isPhone => Host.isAndroid || Host.isIOS;

  PlayerController? _c;
  bool _enabled = true;
  List<String> _folders = [];
  final Set<String> _excluded = {};
  final Map<String, FolderSnapshot> _previous = {};
  final Map<String, StreamSubscription<FileSystemEvent>> _watchers = {};
  final Map<String, Timer> _polls = {};
  final _settler = ChangeSettler();
  Timer? _ticker;
  DateTime? _lastLook;
  bool _looking = false;
  bool _again = false;
  Set<String> _dirty = {};

  /// Setting "Keep the library up to date". On by default.
  bool get keepUpToDate => _enabled;

  /// The music folders being kept up to date.
  List<String> get folders => List.unmodifiable(_folders);

  /// Whether a look at the folders is running right now.
  bool get checking => _looking;

  DateTime? get lastChecked => _lastLook;

  /// Reads the saved folders and starts keeping them up to date. Call once, after the library has loaded.
  static Future<void> start(PlayerController c) async {
    final w = instance;
    w._c = c;
    final prefs = await SharedPreferences.getInstance();
    w._enabled = prefs.getBool(_enabledKey) ?? true;
    var folders = prefs.getStringList(_foldersKey) ?? const [];
    if (Host.isIOS && folders.isNotEmpty) {
      // iOS can move an app's folders between launches; the library's songs were pointed at the new place.
      final moved = await IosFolders.restore();
      folders = [for (final f in folders) moved[f] ?? f];
    }
    w._folders = folders;
    w._excluded
      ..clear()
      ..addAll(prefs.getStringList(_excludedKey) ?? const []);
    try {
      WidgetsBinding.instance.addObserver(w);
    } catch (_) {
      return; // no Flutter binding (a plain unit test): nothing to watch
    }
    w._apply();
    // Things that changed while the app was closed; looked at once the app is up and the first frames are done.
    if (w._enabled) {
      Timer(firstLookDelay, () {
        if (w._enabled) unawaited(w.checkNow());
      });
    }
  }

  Future<void> setKeepUpToDate(bool on) async {
    _enabled = on;
    (await SharedPreferences.getInstance()).setBool(_enabledKey, on);
    _apply();
    notifyListeners();
    if (on) unawaited(checkNow());
  }

  /// A folder was added (by a scan): from now on it is kept up to date. Songs the person had removed from
  /// it are wanted again, since they added the folder.
  Future<void> remember(String dir) async {
    final clean = p.normalize(dir);
    _excluded.removeWhere((x) => p.isWithin(clean, x));
    await _saveExcluded();
    if (!_folders.contains(clean)) {
      _folders = [..._folders, clean];
      (await SharedPreferences.getInstance()).setStringList(_foldersKey, _folders);
      _apply();
      notifyListeners();
    }
    // A first listing, to compare the next ones with (sizes for spotting moves).
    Timer(const Duration(seconds: 5), () => unawaited(_look({clean})));
  }

  /// The person stopped keeping [dir] up to date. Its songs stay in the library.
  Future<void> forget(String dir) async {
    _folders = _folders.where((f) => f != dir).toList();
    _previous.remove(dir);
    (await SharedPreferences.getInstance()).setStringList(_foldersKey, _folders);
    _apply();
    notifyListeners();
  }

  /// A song was removed from the library on purpose: a later look at its folder must not bring it back.
  void exclude(Iterable<String?> paths) {
    var any = false;
    for (final path in paths) {
      if (path != null && _excluded.add(path)) any = true;
    }
    if (any) unawaited(_saveExcluded());
  }

  Future<void> _saveExcluded() async =>
      (await SharedPreferences.getInstance()).setStringList(_excludedKey, _excluded.toList());

  /// Looks at every folder now. Returns how many changes it applied.
  Future<int> checkNow() => _look(_folders.toSet());

  // — starting and stopping the watchers —

  void _apply() {
    final wanted = _enabled ? _folders.toSet() : <String>{};
    for (final dir in _watchers.keys.toList()) {
      if (!wanted.contains(dir)) _stopWatching(dir);
    }
    for (final dir in _polls.keys.toList()) {
      if (!wanted.contains(dir)) {
        _polls.remove(dir)?.cancel();
      }
    }
    if (isPhone) return; // phones are looked at when the app comes back
    for (final dir in wanted) {
      if (!_watchers.containsKey(dir) && !_polls.containsKey(dir)) _watch(dir);
    }
  }

  void _watch(String dir) {
    try {
      if (!Directory(dir).existsSync()) return _poll(dir);
      _watchers[dir] = Directory(dir)
          .watch(recursive: true)
          .listen(
            (e) => _onEvent(dir, e),
            onError: (Object err) {
              debugPrint('Watching $dir stopped, looking every few minutes instead: $err');
              _stopWatching(dir);
              _poll(dir);
            },
          );
    } on Object catch (err) {
      debugPrint('Could not watch $dir, looking every few minutes instead: $err');
      _poll(dir);
    }
  }

  void _stopWatching(String dir) {
    _watchers.remove(dir)?.cancel();
  }

  void _poll(String dir) {
    _polls[dir]?.cancel();
    _polls[dir] = Timer.periodic(pollInterval, (_) => unawaited(_look({dir})));
  }

  void _onEvent(String dir, FileSystemEvent e) {
    final now = DateTime.now();
    for (final path in [e.path, if (e is FileSystemMoveEvent && e.destination != null) e.destination!]) {
      if (isIgnoredPath(path, root: dir)) continue;
      // A song, a cue sheet, or something without a music extension that may be a folder moved or deleted.
      if (!isLibraryFile(path) && p.extension(path).isNotEmpty) continue;
      _settler.note(path, now);
      _dirty.add(dir);
    }
    _ticker ??= Timer.periodic(_tick, (_) => _onTick());
  }

  void _onTick() {
    final ready = _settler.ready(DateTime.now(), _sizeOf);
    if (_settler.isEmpty) {
      _ticker?.cancel();
      _ticker = null;
    }
    if (ready.isEmpty) return;
    final dirs = {
      for (final dir in _watchers.keys)
        if (ready.any((path) => p.isWithin(dir, path))) dir,
    };
    if (dirs.isNotEmpty) unawaited(_look(dirs));
  }

  static int? _sizeOf(String path) {
    try {
      if (FileSystemEntity.typeSync(path, followLinks: false) != FileSystemEntityType.file) return null;
      return File(path).lengthSync();
    } on FileSystemException {
      return null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_enabled || _folders.isEmpty) return;
    // Computers watch all the time; coming back only matters where nothing watches.
    final unwatched = isPhone || _polls.isNotEmpty;
    if (unwatched && shouldRescan(last: _lastLook, now: DateTime.now(), interval: phoneInterval)) {
      unawaited(checkNow());
    }
  }

  // — one look —

  Future<int> _look(Set<String> dirs) async {
    final c = _c;
    if (c == null || !_enabled || dirs.isEmpty) return 0;
    if (_looking) {
      _again = true;
      _dirty = {..._dirty, ...dirs};
      return 0;
    }
    _looking = true;
    notifyListeners();
    var changes = 0;
    try {
      var todo = dirs;
      do {
        _again = false;
        // A download in progress adds its own songs with their source; wait for it so ours doesn't win.
        while (c.youtube.activeCount > 0) {
          await Future<void>.delayed(const Duration(seconds: 10));
        }
        for (final dir in todo.where(_folders.contains)) {
          changes += await _lookAt(c, dir);
        }
        todo = _dirty;
        _dirty = {};
      } while (_again && todo.isNotEmpty);
      _lastLook = DateTime.now();
    } finally {
      _looking = false;
      notifyListeners();
    }
    return changes;
  }

  Future<int> _lookAt(PlayerController c, String dir) async {
    final disk = await inBackground(() => readSnapshotSync(dir));
    if (disk == null) return 0; // not readable right now: change nothing
    final before = _previous[dir];
    _previous[dir] = disk;
    // Forget exclusions for files that are gone, so the list doesn't grow for ever.
    final stale = _excluded.where((x) => p.isWithin(dir, x) && !disk.containsKey(x) && !File(x).existsSync()).toList();
    if (stale.isNotEmpty) {
      _excluded.removeAll(stale);
      unawaited(_saveExcluded());
    }
    // Off the UI isolate: the diff reads the whole library and may check files for existence. Plain data goes in.
    final library = c.library.toList(growable: false);
    final excluded = Set<String>.of(_excluded);
    final plan = await inBackground(
      () => planSync(root: dir, disk: disk, previous: before, library: library, excluded: excluded),
    );
    if (plan.isEmpty) return 0;
    try {
      await c.applyFolderChanges(plan);
    } catch (e) {
      debugPrint('Updating the library from $dir failed: $e');
      return 0;
    }
    return plan.count;
  }
}
