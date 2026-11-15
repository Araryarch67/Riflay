// StreamAudioSource/Response are just_audio's documented way to feed custom byte streams;
// they are flagged experimental but stable across 0.9-0.10.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;

import '../models/track.dart';
import 'download_matches.dart';
import 'monochrome.dart';
import 'sources/music_sources.dart';

/// A place Smart merge may take a YouTube Music song's sound from, when it has the same recording in better
/// quality than YouTube's lossy stream. The order of [SmartMerge.providers] is the order of preference.
abstract class MergeProvider {
  String get name;

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
  bool get on => MusicSources.instance.monochrome;

  @override
  Future<List<Track>> search(String query) => client.search(query, limit: 30);

  @override
  Future<String> stream(Track match) async {
    final id = match.monochromeId;
    if (id == null) throw const FormatException('Not a Monochrome song');
    // A native Tracks song plays from its own address; an older share needs a fresh manifest.
    return id.startsWith('tracks:') ? match.uri.toString() : client.manifest(id);
  }
}

/// One provider's recording of a song.
typedef MergeMatch = ({MergeProvider provider, Track track});

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
    this.lookupTimeout = const Duration(seconds: 3),
    this.streamTimeout = const Duration(seconds: 2),
  }) : providers = providers ?? [MonochromeMerge()],
       _enabled = enabled ?? (() => MusicSources.instance.smartMerge);

  static final instance = SmartMerge().._listenForSettings();

  void _listenForSettings() => MusicSources.instance.addListener(clear);

  /// A change of enabled sources starts a fresh lookup, including failed ones.
  void clear() {
    _configurationRevision++;
    _found.clear();
    _gaveUp.clear();
    _used.clear();
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

  /// Videos whose merged sound failed to play: they stay on YouTube for the rest of the session.
  final _gaveUp = <String>{};

  static const _remembered = 400;

  /// How long a song waits for its lookup before it plays from YouTube instead.
  static const patience = Duration(seconds: 6);

  /// File types that keep the recording whole. `.m4a` is left out: it holds AAC as often as ALAC.
  static const _lossless = {'.flac', '.wav', '.aiff', '.aif', '.ape', '.wv', '.tta', '.dsf', '.dff'};

  /// Whether Smart merge is on for [track], a YouTube Music song that hasn't failed merged before.
  bool wants(Track track) => track.videoId != null && _enabled() && !_gaveUp.contains(track.videoId);

  /// Whether [track] should also be looked up on the streaming sources: [wants], with one of them on.
  bool streams(Track track) => wants(track) && providers.any((s) => s.on);

  /// The same recording among [candidates], or null: the one closest in length among those that are [same].
  static Track? best(Track origin, Iterable<Track> candidates) {
    Track? winner;
    var closest = const Duration(days: 1);
    for (final candidate in candidates) {
      if (!same(origin, candidate)) continue;
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
  static bool same(Track origin, Track candidate) {
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
    return _sameTitle(origin.title, candidate.title) && _shareArtist(origin, candidate);
  }

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
    return a.replaceAll(' ', '') == b.replaceAll(' ', '');
  }

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
    while (_found.length >= _remembered) {
      _found.remove(_found.keys.first);
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
    var song = best(track, await provider.search(plain.isEmpty ? track.title : plain));
    if (!provider.on || !wants(track) || elapsed.elapsed >= lookupTimeout) return null;
    if (song == null && track.artist != Track.unknownArtist) {
      song = best(track, await provider.search(track.artist.split(_between).first.trim()));
    }
    return song == null ? null : (provider: provider, track: song);
  }

  /// The merged sound of [videoId] didn't play: the next try, and every later one, uses YouTube.
  void giveUp(String videoId) {
    if (_found.containsKey(videoId) || _used.contains(videoId)) {
      _gaveUp.add(videoId);
      if (_gaveUp.length > _remembered) _gaveUp.remove(_gaveUp.first);
    }
  }

  /// Records a selected local/remote source so a decode failure can fall back
  /// even if a lookup has since been evicted from the cache.
  void markUsed(String videoId) {
    _used.add(videoId);
    if (_used.length > _remembered) _used.remove(_used.first);
  }

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

  Future<({MergeProvider provider, String stream})?> _candidate() async {
    final revision = merge.configurationRevision;
    if (!merge.streams(track)) return null;
    final matches = await merge.match(track);
    if (revision != merge.configurationRevision) return null;
    for (final match in matches) {
      try {
        if (revision != merge.configurationRevision) return null;
        if (!merge.wants(track) || !match.provider.on) continue;
        final stream = await match.provider.stream(match.track).timeout(merge.streamTimeout);
        if (revision != merge.configurationRevision) return null;
        if (!merge.wants(track) || !match.provider.on) continue;
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
        return (provider: match.provider, stream: stream);
      } catch (e) {
        debugPrint('Smart merge stream from ${match.provider.name}: ${e.runtimeType}');
      }
    }
    // Something matched and none of it streams: don't ask again this session.
    if (matches.isNotEmpty && revision == merge.configurationRevision) merge.giveUp(track.videoId!);
    return null;
  }

  Future<String?> _resolve() async {
    final revision = merge.configurationRevision;
    final result = await _candidate().timeout(SmartMerge.patience, onTimeout: () => null);
    if (revision != merge.configurationRevision || result == null || !merge.wants(track) || !result.provider.on) {
      return null;
    }
    from = result.provider;
    merge.markUsed(track.videoId!);
    return result.stream;
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final merged = await (_merged ??= _resolve());
    if (merged == null) return youtube.request(start, end);
    final dash = merged.trimLeft().startsWith('<');
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
