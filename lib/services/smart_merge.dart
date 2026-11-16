// StreamAudioSource/Response are just_audio's documented way to feed custom byte streams;
// they are flagged experimental but stable across 0.9-0.10.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import 'download_matches.dart';
import 'merged_download.dart';
import 'monochrome.dart';
import 'sources/music_sources.dart';

/// Where a merged song's sound comes from: [TrackSource.device] for a lossless file in the library, with the
/// source's name for what's shown.
typedef MergedSound = ({TrackSource source, String name});

/// A place Smart merge may take a YouTube Music song's sound from, when it has the same recording in better
/// quality than YouTube's lossy stream. The order of [SmartMerge.providers] is the order of preference.
abstract class MergeProvider {
  String get name;

  /// Its mark on the song's badge.
  TrackSource get source;

  /// Whether the person has this source on (Settings › Accounts & services › Music sources).
  bool get on;

  /// Songs that match [query]: a song's title, or its artist. Throws when the source can't be reached.
  Future<List<Track>> search(String query);

  /// What mpv plays for [match], one of this provider's songs: a web address, or a DASH manifest. Throws when
  /// the song can't be streamed now.
  Future<String> stream(Track match);
}

/// Monochrome: FLAC when it has it.
class MonochromeMerge implements MergeProvider {
  MonochromeMerge([Monochrome? client]) : client = client ?? Monochrome.instance;

  final Monochrome client;

  @override
  String get name => client.name;

  @override
  TrackSource get source => TrackSource.monochrome;

  @override
  bool get on => MusicSources.instance.monochrome;

  @override
  Future<List<Track>> search(String query) => client.search(query, limit: 30);

  /// Which songs are FLAC here, once checked: a song is the same file each time it's asked for.
  final _lossless = <String, bool>{};

  @override
  Future<String> stream(Track match) async {
    final id = match.monochromeId;
    if (id == null) throw const FormatException('Not a Monochrome song');
    // A native Tracks song plays from its own address; an older share needs a fresh manifest.
    final stream = id.startsWith('tracks:') ? match.uri.toString() : await client.manifest(id);
    // Only FLAC is better than YouTube's Opus: a song the service has only as AAC plays from YouTube.
    final lossless = _lossless[match.id] ?? (_lossless[match.id] = await client.lossless(stream));
    if (_lossless.length > 400) _lossless.remove(_lossless.keys.first);
    if (!lossless) throw const FormatException('Monochrome has this song only in lossy quality');
    return stream;
  }
}

/// One provider's recording of a song.
typedef MergeMatch = ({MergeProvider provider, Track track});

/// The better sound a song plays from: the source, and the address or manifest mpv plays.
typedef MergeChoice = ({MergeProvider provider, String stream});

class _MergeLookup {
  _MergeLookup(this.origin, this.providers, this.result, this.token);
  final Track origin;
  final List<MergeProvider> providers;
  final Future<List<MergeMatch>> result;
  final Object token;

  bool matches(Track track, List<MergeProvider> active) =>
      origin.title == track.title &&
      origin.artist == track.artist &&
      origin.duration == track.duration &&
      listEquals(providers, active);
}

/// Smart merge (Settings › Accounts & services › Music sources): a YouTube Music song plays its sound from the
/// best place that has the same recording. First a lossless file of it in the library on this device, then each
/// streaming source that is on, in [providers]' order, and YouTube's own stream when none has it. The song itself
/// stays the YouTube Music one, so its music video, lyrics, cover, likes and radio are untouched.
///
/// Only a recording that is surely the same one is taken ([best]); anything less plays from YouTube as before.
/// SpotiFLAC extensions are not here: Riflay downloads from them and cannot stream them, and a song downloaded
/// from one already plays from its file.
class SmartMerge {
  SmartMerge({
    List<MergeProvider>? providers,
    bool Function()? enabled,
    this.lookupTimeout = const Duration(seconds: 15),
    // Monochrome can take seconds to send a song's first bytes (0.5-9 s measured). The song plays from YouTube
    // meanwhile, so there is time to wait for it.
    this.streamTimeout = const Duration(seconds: 12),
    this.downloads = true,
    this.remembers = false,
    this.patience = const Duration(seconds: 8),
  }) : providers = providers ?? [MonochromeMerge()],
       _enabled = enabled ?? (() => MusicSources.instance.smartMerge);

  static final instance = SmartMerge(remembers: true).._listenForSettings();

  /// The better sound is fetched from its start and played from here ([MergedDownload]); false plays it from its
  /// address (tests that don't reach a server).
  final bool downloads;

  /// Matches are kept between sessions, so a song played before needs no lookup (about 1.5 s on Monochrome).
  final bool remembers;
  static const _rememberedKey = 'smartMerge.matches.v1';
  Map<String, Map<String, dynamic>>? _kept;

  Future<Map<String, Map<String, dynamic>>> _keptMatches() async {
    if (_kept case final kept?) return kept;
    var kept = <String, Map<String, dynamic>>{};
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_rememberedKey);
      if (raw != null) {
        kept = {
          for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
            e.key: (e.value as Map).cast<String, dynamic>(),
        };
      }
    } catch (e) {
      debugPrint('Smart merge: remembered matches unreadable: ${e.runtimeType}');
    }
    return _kept ??= kept;
  }

  void _remember(String videoId, MergeChoice choice) {
    if (!remembers) return;
    final found = _found[videoId];
    () async {
      final match = (await found?.result)?.where((m) => identical(m.provider, choice.provider)).firstOrNull;
      if (match == null) return;
      final kept = await _keptMatches();
      // Given up on meanwhile (it didn't play): not kept.
      if (_gaveUp.contains(videoId)) return;
      kept.remove(videoId);
      kept[videoId] = {'provider': choice.provider.name, 'track': match.track.toJson()};
      while (kept.length > _rememberedMax) {
        kept.remove(kept.keys.first);
      }
      await _saveKept(kept);
    }().ignore();
  }

  void _forget(String videoId) {
    if (!remembers) return;
    () async {
      final kept = await _keptMatches();
      if (kept.remove(videoId) != null) await _saveKept(kept);
    }().ignore();
  }

  static const _rememberedMax = 2000;

  static Future<void> _saveKept(Map<String, Map<String, dynamic>> kept) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_rememberedKey, jsonEncode(kept));
    } catch (e) {
      debugPrint('Smart merge: remembering matches failed: ${e.runtimeType}');
    }
  }

  /// The address each video's better sound comes from, once found.
  final _streamOf = <String, String>{};

  /// The download of [videoId]'s better sound, when it is fetched that way.
  MergedDownload? downloadOf(String videoId) => switch (_streamOf[videoId]) {
    final url? when downloads => MergedDownload.of(url),
    _ => null,
  };

  void _listenForSettings() => MusicSources.instance.addListener(clear);

  /// A change of enabled sources starts a fresh lookup, including failed ones.
  void clear() {
    _configurationRevision++;
    _found.clear();
    _gaveUp.clear();
    _used.clear();
    _soundFrom.clear();
    _streamOf.clear();
    _choosing.clear();
    changes.value++;
  }

  /// The streaming sources, best first.
  final List<MergeProvider> providers;
  final bool Function() _enabled;
  final Duration lookupTimeout;
  final Duration streamTimeout;

  /// What was found for a video this session (empty: nothing good enough), so a song is looked up once.
  final _found = <String, _MergeLookup>{};
  final _used = <String>{};
  int _configurationRevision = 0;
  int get configurationRevision => _configurationRevision;

  /// Where each video's sound came from this session, for the mark on its rows and cards.
  final _soundFrom = <String, MergedSound>{};

  /// Counts up when a song starts playing merged, for what shows where a song's sound comes from: the choice is
  /// made after the song became the player's current one.
  final changes = ValueNotifier<int>(0);

  /// Videos whose merged sound failed to play: they stay on YouTube for the rest of the session.
  final _gaveUp = <String>{};

  static const _remembered = 400;

  /// How long a song waits for its better sound (found, checked, its first bytes here) before it plays from
  /// YouTube instead. The lookup and download carry on: the next time the song plays, it opens straight away.
  final Duration patience;

  /// File types that keep the recording whole. `.m4a` is left out: it holds AAC as often as ALAC.
  static const _lossless = {'.flac', '.wav', '.aiff', '.aif', '.ape', '.wv', '.tta', '.dsf', '.dff'};

  /// Whether Smart merge is on for [track], a YouTube Music song that hasn't failed merged before.
  bool wants(Track track) => track.videoId != null && _enabled() && !_gaveUp.contains(track.videoId);

  /// Whether [track] should also be looked up on the streaming sources: [wants], with one of them on.
  bool streams(Track track) => wants(track) && providers.any((s) => s.on);

  /// The same recording among [candidates], or null: the one closest in length among those that are [same].
  static Track? best(Track origin, Iterable<Track> candidates, {bool byArtist = false}) {
    Track? winner;
    var closest = const Duration(days: 1);
    for (final candidate in candidates) {
      if (!same(origin, candidate, byArtist: byArtist)) continue;
      final apart = (origin.duration! - candidate.duration!).abs();
      if (apart < closest) {
        closest = apart;
        winner = candidate;
      }
    }
    return winner;
  }

  /// Whether [candidate] is surely [origin]'s recording: a wrong guess would play a different song under this
  /// one's name. Both lengths must be known and within three seconds, the version words (live, remix, …) must
  /// agree, the titles must be the same and the two must share an artist.
  ///
  /// [byArtist]: [candidate] is what the source answered when asked for [origin]'s artist. That stands in for a
  /// shared artist only when the two names can't be compared, one being in Latin letters and the other not
  /// ("Houshou Marine" and "宝鐘マリン"): the source's own index is then what ties them together.
  static bool same(Track origin, Track candidate, {bool byArtist = false}) {
    final a = origin.duration, b = candidate.duration;
    if (a == null ||
        b == null ||
        a <= Duration.zero ||
        b <= Duration.zero ||
        (a - b).abs() > const Duration(seconds: 3)) {
      return false;
    }
    final ours = DownloadMatches.versions(origin.title), theirs = DownloadMatches.versions(candidate.title);
    if (!ours.containsAll(theirs) || !theirs.containsAll(ours)) return false;
    final isrc = origin.extensionData?['isrc']?.toString().trim().toUpperCase();
    final otherIsrc = candidate.extensionData?['isrc']?.toString().trim().toUpperCase();
    if (isrc != null && isrc.isNotEmpty && otherIsrc != null && otherIsrc.isNotEmpty && isrc != otherIsrc) return false;
    return _sameTitle(origin.title, candidate.title) &&
        (_shareArtist(origin, candidate) || (byArtist && _otherScript(origin.artist, candidate.artist)));
  }

  static final _latin = RegExp('[A-Za-z]');

  /// One name is written in Latin letters and the other has none.
  static bool _otherScript(String one, String other) =>
      one.trim().isNotEmpty && other.trim().isNotEmpty && _latin.hasMatch(one) != _latin.hasMatch(other);

  /// A title without what services add around it: "(feat. …)", "[Official MV]" and the like.
  static String _title(String title) => DownloadMatches.normalized(
    title.replaceAll(
      RegExp(
        r'[(\[【（][^)\]】）]*\b(feat|ft|featuring|with|official|mv|video|audio|lyrics?)\b[^)\]】）]*[)\]】）]',
        caseSensitive: false,
      ),
      ' ',
    ),
  );

  /// The same title, however it is spaced ("I I I" and "III"). Fuzzy title
  /// matching is appropriate for a reviewed download, not an automatic swap.
  static bool _sameTitle(String one, String other) {
    final a = _title(one), b = _title(other);
    if (a.isEmpty || b.isEmpty) return false;
    if (a.replaceAll(' ', '') == b.replaceAll(' ', '')) return true;
    // A title given twice, in its own script and in Latin letters ("伝説の夜 - legendary night"): either half
    // being the other title is the same title.
    final ours = _halves(one), theirs = _halves(other);
    return (ours.length > 1 || theirs.length > 1) && ours.intersection(theirs).isNotEmpty;
  }

  static final _dash = RegExp(r'\s+[-–—|/]\s+');

  static Set<String> _halves(String title) => {
    for (final half in title.split(_dash))
      if (_key(half) case final key when key.length > 3) key,
  };

  static final _between = RegExp(r',|&|、|・|/|;|\bfeat\b\.?|\bft\b\.?|\bwith\b|\band\b| x |×', caseSensitive: false);

  static Set<String> _artists(String artist) => {
    for (final name in artist.split(_between))
      if (DownloadMatches.normalized(name) case final n
          when n.isNotEmpty && n != DownloadMatches.normalized(Track.unknownArtist))
        n,
  };

  /// Services can list artists in a different order or include extra featured
  /// artists. A title mentioning an unrelated artist is not evidence of a match.
  static bool _shareArtist(Track origin, Track candidate) {
    final ours = _artists(origin.artist), theirs = _artists(candidate.artist);
    return ours.intersection(theirs).isNotEmpty;
  }

  static String _key(String title) => _title(title).replaceAll(' ', '');

  /// The library's lossless files by their title ([_key]), rebuilt when the library changes ([_indexOf]).
  Map<String, List<Track>> _index = const {};
  Object? _indexOf;

  /// A lossless file of [track]'s recording in [library], or null. [revision] changes when the library does; the
  /// lookup is by title first, so a queue of thousands doesn't compare every song with every file.
  Track? local(Track track, List<Track> library, Object revision, {bool Function(Track)? available}) {
    if (!wants(track)) return null;
    if (_indexOf != revision) {
      _indexOf = revision;
      final index = <String, List<Track>>{};
      for (final file in library) {
        final path = file.path;
        final alac = file.audioQuality?.startsWith('ALAC') ?? false;
        if (path == null || file.isCueTrack || (!_lossless.contains(p.extension(path).toLowerCase()) && !alac)) {
          continue;
        }
        (index[_key(file.title)] ??= []).add(file);
      }
      _index = index;
    }
    final same = _index[_key(track.title)];
    return same == null ? null : best(track, available == null ? same : same.where(available));
  }

  /// What each video plays from, decided (or being decided): found, checked, its download begun. Asked once by
  /// whatever comes first (a card the pointer rests on, the next song in the queue, the song being played).
  final _choosing = <String, Future<MergeChoice?>>{};

  /// [track]'s better sound: a source that has the same recording and streams it, or null. Never throws.
  Future<MergeChoice?> choose(Track track) {
    final id = track.videoId;
    if (id == null || !streams(track)) return Future.value();
    final revision = _configurationRevision;
    return _choosing[id] ??= _choose(track).then(
      (choice) {
        // Nothing (it may be found later), an old answer, or an expiring manifest: asked again next time.
        if (choice == null || revision != _configurationRevision || choice.stream.trimLeft().startsWith('<')) {
          if (revision == _configurationRevision) _choosing.remove(id);
        } else {
          _remember(id, choice);
        }
        return choice;
      },
      onError: (Object e) {
        _choosing.remove(id);
        return null;
      },
    );
  }

  /// Gets [track] ready to play from its better sound, ahead of being played.
  void prefetch(Track track) => choose(track).ignore();

  Timer? _resting;

  /// The pointer came to rest on [track] (a row or a card): after a moment there, it is got ready ([prefetch]), so
  /// a click plays it straight away. Passing over doesn't fetch anything.
  void pointerOn(Track? track) {
    _resting?.cancel();
    if (track == null || !streams(track)) return;
    _resting = Timer(const Duration(milliseconds: 300), () => prefetch(track));
  }

  /// The pointer left before the moment was up.
  void pointerOff() => _resting?.cancel();

  Future<MergeChoice?> _choose(Track track) async {
    final revision = _configurationRevision;
    if (!streams(track)) return null;
    final asked = Stopwatch()..start();
    final matches = await match(track);
    if (revision != _configurationRevision) return null;
    debugPrint('Smart merge: ${matches.length} match(es) for ${track.videoId} after ${asked.elapsedMilliseconds} ms');
    var slow = false;
    for (final match in matches) {
      try {
        if (revision != _configurationRevision) return null;
        if (!wants(track) || !match.provider.on) continue;
        final stream = await match.provider.stream(match.track).timeout(streamTimeout);
        if (revision != _configurationRevision) return null;
        if (!wants(track) || !match.provider.on) continue;
        final dash = stream.trimLeft().startsWith('<');
        final uri = dash ? null : Uri.tryParse(stream);
        if (dash
            ? !RegExp(r'^\s*(?:<\?xml[\s\S]*?\?>\s*)?<MPD(?:\s|>)').hasMatch(stream)
            : uri == null ||
                  !const {'https', 'http'}.contains(uri.scheme) ||
                  uri.host.isEmpty ||
                  uri.userInfo.isNotEmpty ||
                  stream.contains(RegExp(r'[\r\n]'))) {
          throw const FormatException('Invalid merged audio manifest or URL');
        }
        if (downloads && !dash) {
          // Fetched from its start from now on (the FLAC check may already have begun it): by the time the song
          // switches over, it is ahead of where the song has got to.
          _streamOf[track.videoId!] = stream;
          MergedDownload.of(stream);
        }
        debugPrint(
          'Smart merge: ${match.provider.name} streams ${track.videoId} after ${asked.elapsedMilliseconds} ms',
        );
        return (provider: match.provider, stream: stream);
      } catch (e) {
        // Only slow: the song is asked again the next time it plays.
        if (e is TimeoutException) slow = true;
        debugPrint('Smart merge stream from ${match.provider.name}: ${e.runtimeType}');
      }
    }
    // Something matched and none of it streams (lossy only, or broken): don't ask again this session.
    if (matches.isNotEmpty && !slow && revision == _configurationRevision) giveUp(track.videoId!);
    return null;
  }

  /// [track]'s recording on the streaming sources that are on, best first; empty when none has it. Never throws:
  /// a source that can't be reached is left out, and the song is asked again the next time it comes up.
  Future<List<MergeMatch>> match(Track track) {
    final id = track.videoId;
    if (id == null || !wants(track)) return Future.value(const []);
    final active = providers.where((provider) => provider.on).toList();
    if (active.isEmpty) {
      _found.remove(id);
      return Future.value(const []);
    }
    if (_found[id] case final known? when known.matches(track, active)) return known.result;
    if (remembers) {
      final result = _rememberedOrSearch(track, id, active);
      _found[id] = _MergeLookup(track, active, result, Object());
      return result;
    }
    while (_found.length >= _remembered) {
      _found.remove(_found.keys.first);
    }
    final token = Object();
    final result = _search(track, id, active, token);
    _found[id] = _MergeLookup(track, active, result, token);
    return result;
  }

  Future<List<MergeMatch>> _rememberedOrSearch(Track track, String id, List<MergeProvider> active) async {
    final kept = (await _keptMatches())[id];
    if (kept != null) {
      final provider = active.where((p) => p.name == kept['provider']).firstOrNull;
      if (provider != null) {
        try {
          return [(provider: provider, track: Track.fromJson((kept['track'] as Map).cast<String, dynamic>()))];
        } catch (_) {}
      }
    }
    final token = Object();
    final result = _search(track, id, active, token);
    _found[id] = _MergeLookup(track, active, result, token);
    return result;
  }

  Future<List<MergeMatch>> _search(Track track, String id, List<MergeProvider> active, Object token) async {
    var failed = false;
    final found = await Future.wait([
      for (final provider in active)
        _on(provider, track).timeout(lookupTimeout).catchError((Object e) {
          debugPrint('Smart merge lookup on ${provider.name}: ${e.runtimeType}');
          failed = true;
          return null;
        }),
    ]);
    // A source that was down may have had it: this answer isn't kept.
    if (failed && identical(_found[id]?.token, token)) _found.remove(id);
    return [
      for (final match in found)
        if (match != null && match.provider.on) match,
    ];
  }

  /// [track]'s recording on [provider]. Asked by title, and when that doesn't find it by artist: a catalogue's
  /// search matches one field at a time, so title and artist together find neither.
  Future<MergeMatch?> _on(MergeProvider provider, Track track) async {
    if (!provider.on || !wants(track)) return null;
    final elapsed = Stopwatch()..start();
    // Without what follows a bracket ("(feat. …)", "[MV]"), which the catalogue's title rarely has.
    final plain = track.title.replaceAll(RegExp(r'[(\[【（].*$'), '').trim();
    // Both questions go out together: one after the other they took about as long as [lookupTimeout] allows,
    // and a song whose artist is written in another script is only found by the second.
    final artist = track.artist == Track.unknownArtist ? '' : track.artist.split(_between).first.trim();
    final byArtist = artist.isEmpty ? null : (provider.search(artist)..ignore());
    var song = best(track, await provider.search(plain.isEmpty ? track.title : plain));
    if (!provider.on || !wants(track) || elapsed.elapsed >= lookupTimeout) return null;
    if (song == null && byArtist != null) song = best(track, await byArtist, byArtist: true);
    return song == null ? null : (provider: provider, track: song);
  }

  /// The merged sound of [videoId] didn't play: the next try, and every later one, uses YouTube.
  void giveUp(String videoId) {
    _choosing.remove(videoId);
    _forget(videoId);
    if (_found.containsKey(videoId) || _used.contains(videoId)) {
      _gaveUp.add(videoId);
      if (_gaveUp.length > _remembered) _gaveUp.remove(_gaveUp.first);
      // The song's badge goes back to its own source.
      changes.value++;
    }
  }

  /// Records a selected local/remote source so a decode failure can fall back
  /// even if a lookup has since been evicted from the cache.
  /// [sound]: where it plays from; null leaves what's shown as it is.
  void markUsed(String videoId, {MergedSound? sound}) {
    _used.add(videoId);
    if (sound != null) {
      _soundFrom.remove(videoId);
      _soundFrom[videoId] = sound;
      if (_soundFrom.length > _remembered) _soundFrom.remove(_soundFrom.keys.first);
    }
    changes.value++;
    if (_used.length > _remembered) _used.remove(_used.first);
  }

  /// Where [videoId]'s sound came from this session: a lossless file in the library or a streaming source; null
  /// when it played from YouTube.
  MergedSound? soundFrom(String videoId) => _gaveUp.contains(videoId) ? null : _soundFrom[videoId];

  /// Whether retries must use the original YouTube stream for this song.
  bool gaveUpOn(String videoId) => _gaveUp.contains(videoId);
}

/// A YouTube Music song whose sound comes from the first of [SmartMerge.providers] that has the same recording
/// and can stream it, and from [youtube] otherwise. Which one is decided once, when the player first asks for
/// bytes.
class SmartMergeAudioSource extends StreamAudioSource {
  SmartMergeAudioSource(this.track, {required this.youtube, SmartMerge? merge})
    : merge = merge ?? SmartMerge.instance,
      super(tag: track);

  final Track track;

  /// The song's own YouTube stream, for when there is no match or its sound can't be had.
  final StreamAudioSource youtube;
  final SmartMerge merge;

  /// The provider whose sound plays, once decided; null for YouTube.
  MergeProvider? from;

  /// The address or DASH manifest mpv plays instead, or null for YouTube.
  Future<String?>? _merged;

  Future<MergeChoice?> _candidate() => merge.choose(track);

  Future<String?> _resolve() async {
    final revision = merge.configurationRevision;
    // The song waits a while for its better sound; past that it plays from YouTube, and the lookup and download
    // carry on for the next time it plays.
    final result = await _candidate().timeout(merge.patience, onTimeout: () => null);
    if (revision != merge.configurationRevision || result == null || !merge.wants(track) || !result.provider.on) {
      return null;
    }
    from = result.provider;
    merge.markUsed(track.videoId!, sound: (source: result.provider.source, name: result.provider.name));
    return result.stream;
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final merged = await (_merged ??= _resolve());
    if (merged == null) return youtube.request(start, end);
    final dash = merged.trimLeft().startsWith('<');
    if (merge.downloads && !dash) return MergedDownload.of(merged).source().request(start, end);
    final bytes = utf8.encode(dash ? merged : '#EXTM3U\n#EXTINF:-1,\n$merged\n#EXT-X-ENDLIST\n');
    final from = (start ?? 0).clamp(0, bytes.length);
    final to = (end ?? bytes.length).clamp(from, bytes.length);
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: to - from,
      offset: from,
      contentType: dash ? 'application/dash+xml' : 'application/vnd.apple.mpegurl',
      stream: Stream.value(bytes.sublist(from, to)),
    );
  }
}
