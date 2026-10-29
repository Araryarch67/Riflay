import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import 'lyrics.dart';

/// More places to ask for lyrics, none of them needing an account or a key:
/// Kugou (word by word), QQ Music, Musixmatch (word by word), Genius (words
/// only) and Megalobiz. Each returns null when the song isn't there and throws
/// when the site can't be reached, like [LyricsService.netease].
abstract final class MoreLyrics {
  static final _http = http.Client();

  static const _browser = {
    'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
  };

  /// What a lyrics site is asked for: the cleaned title and the artist, null
  /// when the artist is unknown (a wrong song's lyrics are worse than none).
  static ({String title, String artist, int? seconds})? _ask(Track track) {
    if (track.artist == Track.unknownArtist || track.artist.trim().isEmpty) return null;
    final title = LyricsService.cleanTitle(track.title);
    if (title.isEmpty) return null;
    return (title: title, artist: track.artist, seconds: track.duration?.inSeconds);
  }

  /// A hit is the song when its title is the same, it shares an artist and its
  /// length is within 3 seconds: covers and remixes share titles.
  static bool _isSong(
    ({String title, String artist, int? seconds}) want, {
    required String title,
    required Iterable<String> artists,
    num? seconds,
  }) {
    final who = LyricsService.norm(want.artist);
    if (LyricsService.norm(LyricsService.cleanTitle(title)) != LyricsService.norm(want.title)) return false;
    final named = artists.any((a) {
      final n = LyricsService.norm(a);
      return n.isNotEmpty && who.isNotEmpty && (who.contains(n) || n.contains(who));
    });
    if (!named) return false;
    final mine = want.seconds;
    return mine == null || seconds == null || seconds <= 0 || (seconds - mine).abs() <= 3;
  }

  /// "A、B", "A & B", "A/B" → the artists one by one (and the whole as well).
  static List<String> _split(String names) => [
    names,
    ...names.split(RegExp(r'[、,&/;]|\sfeat\.?\s|\sx\s', caseSensitive: false)).map((s) => s.trim()),
  ];

  static Never _fail(String site, http.Response res) => throw HttpException('$site ${res.statusCode}');

  static dynamic _json(http.Response res) => jsonDecode(utf8.decode(res.bodyBytes));

  // Credit lines at the top of Chinese lyrics ("词：", "作曲 :", "Composer:"…).
  static final _credit = RegExp(
    r'^\s*(作词|作詞|作曲|编曲|編曲|制作人|製作人|监制|混音|混音工程|录音|录音工程|录音助理|和声|合声|合声编写|母带|吉他|贝斯|鼓|词|曲|原唱|OP|SP|'
    r'(lyrics?|music|written|composed|arranged|produced|mixed|mastered|recorded)\s+by|composer|lyricist|arranger|producer)\s*[:：]',
    caseSensitive: false,
  );

  /// Whether a line is a credit rather than something sung.
  @visibleForTesting
  static bool isCredit(String text) => _credit.hasMatch(text);

  /// Kugou and QQ put "Song - Artist" as their first line.
  static bool _isHeadline(String text, String title) =>
      text.contains(' - ') && LyricsService.norm(text).contains(LyricsService.norm(title));

  static const _instrumentalNote = '纯音乐';

  // ---------------------------------------------------------------- Kugou

  /// Kugou (KRC): every word timed. Wrong or missing songs give null.
  static Future<Lyrics?> kugou(Track track, {http.Client? client}) async {
    final want = _ask(track);
    if (want == null) return null;
    final c = client ?? _http;
    final res = await c.get(
      Uri.https('lyrics.kugou.com', '/search', {
        'ver': '1',
        'man': 'yes',
        'client': 'pc',
        'keyword': '${want.artist} - ${want.title}',
        if (want.seconds != null) 'duration': '${want.seconds! * 1000}',
      }),
      headers: _browser,
    );
    if (res.statusCode != 200) _fail('Kugou', res);
    final body = _json(res);
    final found = ((body is Map ? body['candidates'] : null) as List? ?? const []).whereType<Map>();
    final matches = found.where(
      (m) => _isSong(
        want,
        title: '${m['song']}',
        artists: _split('${m['singer']}'),
        seconds: (m['duration'] as num?) == null ? null : (m['duration'] as num) / 1000,
      ),
    );
    for (final m in matches.take(3)) {
      final id = '${m['id']}', key = '${m['accesskey']}';
      for (final fmt in const ['krc', 'lrc']) {
        final lr = await c.get(
          Uri.https('lyrics.kugou.com', '/download', {
            'ver': '1',
            'client': 'pc',
            'id': id,
            'accesskey': key,
            'fmt': fmt,
            'charset': 'utf8',
          }),
          headers: _browser,
        );
        if (lr.statusCode != 200) _fail('Kugou', lr);
        final content = (_json(lr) as Map)['content'];
        if (content is! String || content.isEmpty) continue;
        try {
          final bytes = base64.decode(content);
          final l = fmt == 'krc'
              ? parseKrc(decodeKrc(bytes), title: want.title)
              : _lines(utf8.decode(bytes, allowMalformed: true), want.title, 'Kugou');
          if (l != null && !l.isEmpty) return l;
        } catch (e) {
          debugPrint('Lyrics: Kugou $fmt: $e');
        }
      }
    }
    return null;
  }

  static const _krcKey = [64, 71, 97, 119, 94, 50, 116, 71, 81, 54, 49, 45, 206, 210, 110, 105];

  /// The text inside Kugou's KRC download: "krc1", then zlib after an XOR with a fixed key.
  @visibleForTesting
  static String decodeKrc(List<int> bytes) {
    if (bytes.length < 5 || String.fromCharCodes(bytes.take(4)) != 'krc1') throw const FormatException('not KRC');
    final xored = Uint8List.fromList([for (var i = 4; i < bytes.length; i++) bytes[i] ^ _krcKey[(i - 4) % 16]]);
    return utf8.decode(zlib.decode(xored), allowMalformed: true);
  }

  static final _krcLine = RegExp(r'^\[(\d+),(\d+)\](.*)$');
  static final _krcWord = RegExp(r'<(\d+),(\d+),\d+>');

  /// Parses KRC text: `[startMs,durMs]<offset,dur,0>word…` per line, word
  /// offsets counted from the line's start. Credits and the headline go.
  @visibleForTesting
  static Lyrics? parseKrc(String text, {String? title}) {
    final lines = <LyricLine>[];
    for (final raw in const LineSplitter().convert(text)) {
      final m = _krcLine.firstMatch(raw.trim());
      if (m == null) continue;
      final start = int.parse(m[1]!), dur = int.parse(m[2]!);
      final rest = m[3]!;
      final marks = _krcWord.allMatches(rest).toList();
      final words = <LyricWord>[];
      for (var i = 0; i < marks.length; i++) {
        final end = i + 1 < marks.length ? marks[i + 1].start : rest.length;
        final word = rest.substring(marks[i].end, end);
        if (word.isEmpty) continue;
        final from = start + int.parse(marks[i][1]!);
        words.add(
          LyricWord(Duration(milliseconds: from), Duration(milliseconds: from + int.parse(marks[i][2]!)), word),
        );
      }
      final fixed = _tidy(words);
      final plain = marks.isEmpty ? rest.trim() : fixed.map((w) => w.text).join();
      if (plain.isEmpty || isCredit(plain)) continue;
      lines.add(
        LyricLine(
          Duration(milliseconds: start),
          plain,
          end: Duration(milliseconds: start + dur),
          words: fixed.length > 1 ? fixed : const [],
        ),
      );
    }
    if (lines.isNotEmpty && title != null && _isHeadline(lines.first.text, title)) lines.removeAt(0);
    return lines.isEmpty ? null : Lyrics(lines: lines, source: 'Kugou');
  }

  /// Words with no space before the first and none after the last.
  static List<LyricWord> _tidy(List<LyricWord> words) {
    final out = [...words];
    while (out.isNotEmpty && out.first.text.trim().isEmpty) {
      out.removeAt(0);
    }
    while (out.isNotEmpty && out.last.text.trim().isEmpty) {
      out.removeLast();
    }
    if (out.isEmpty) return out;
    final first = out.first, last = out.last;
    out[0] = LyricWord(first.start, first.end, first.text.trimLeft());
    final i = out.length - 1;
    out[i] = LyricWord(last.start, last.end, i == 0 ? out[0].text.trimRight() : last.text.trimRight());
    return out;
  }

  /// LRC text from a Chinese site: credits and the headline removed.
  static Lyrics? _lines(String text, String title, String source) {
    final kept = <String>[];
    for (final line in const LineSplitter().convert(text.replaceAll('﻿', ''))) {
      final body = line.replaceFirst(RegExp(r'^(\s*\[[^\]]*\])+'), '').trim();
      if (body.isNotEmpty && isCredit(body)) continue;
      kept.add(line);
    }
    final l = Lyrics.parse(kept.join('\n'), source: source);
    if (l.lines.isEmpty) return l.isEmpty ? null : l;
    var lines = l.lines;
    if (_isHeadline(lines.first.text, title)) lines = lines.sublist(1);
    final sung = lines.where((x) => x.text.isNotEmpty).toList();
    if (sung.isEmpty) return null;
    if (sung.length <= 2 && sung.any((x) => x.text.contains(_instrumentalNote))) {
      return Lyrics(instrumental: true, source: source);
    }
    return Lyrics(lines: lines, source: source);
  }

  // -------------------------------------------------------------- QQ Music

  /// QQ Music: lines with times. (Its word-timed QRC needs a custom triple DES; not done.)
  static Future<Lyrics?> qqMusic(Track track, {http.Client? client}) async {
    final want = _ask(track);
    if (want == null) return null;
    final c = client ?? _http;
    const headers = {..._browser, 'Referer': 'https://y.qq.com'};
    final res = await c.get(
      Uri.https('c.y.qq.com', '/soso/fcgi-bin/client_search_cp', {
        'w': '${want.artist} ${want.title}',
        'format': 'json',
        'n': '10',
        'p': '1',
      }),
      headers: headers,
    );
    if (res.statusCode != 200) _fail('QQ Music', res);
    final data = _json(res);
    final list = (((data is Map ? data['data'] : null) as Map?)?['song'] as Map?)?['list'] as List? ?? const [];
    final matches = list.whereType<Map>().where(
      (s) => _isSong(
        want,
        title: '${s['songname']}',
        artists: [for (final a in (s['singer'] as List? ?? const []).whereType<Map>()) ..._split('${a['name']}')],
        seconds: s['interval'] as num?,
      ),
    );
    for (final s in matches.take(3)) {
      final lr = await c.get(
        Uri.https('c.y.qq.com', '/lyric/fcgi-bin/fcg_query_lyric_new.fcg', {
          'songmid': '${s['songmid']}',
          'format': 'json',
          'nobase64': '1',
        }),
        headers: headers,
      );
      if (lr.statusCode != 200) _fail('QQ Music', lr);
      final l = parseQqLyric(utf8.decode(lr.bodyBytes), title: want.title);
      if (l != null) return l;
    }
    return null;
  }

  /// The lyric reply of QQ Music (JSON, or JSON in a callback) → lines.
  @visibleForTesting
  static Lyrics? parseQqLyric(String body, {String? title}) {
    final json = body.trim().startsWith('{') ? body : body.substring(body.indexOf('(') + 1, body.lastIndexOf(')'));
    final lyric = (jsonDecode(json) as Map)['lyric'];
    if (lyric is! String || lyric.trim().isEmpty) return null;
    return _lines(lyric, title ?? '', 'QQ Music');
  }

  // ------------------------------------------------------------ Musixmatch

  static String? _mxmToken;
  static DateTime? _mxmPause;
  static const _mxmApp = 'web-desktop-app-v1.0';

  /// Forgets the token and the pause (for tests).
  @visibleForTesting
  static void resetMusixmatch() {
    _mxmToken = null;
    _mxmPause = null;
  }

  static const _mxmHeaders = {..._browser, 'Cookie': 'AWSELB=0; AWSELBCORS=0'};

  /// A token only counts when it isn't the all-zero stand-in the service
  /// hands out when it has refused us (that one only gets made-up lyrics).
  static bool _realToken(Object? t) => t is String && t.length >= 20 && t.replaceAll('0', '').isNotEmpty;

  static void _mxmRefused(String why) {
    debugPrint('Lyrics: Musixmatch refused: $why');
    _mxmToken = null;
    _mxmPause = DateTime.now().add(const Duration(minutes: 30));
    SharedPreferences.getInstance()
        .then((p) {
          p.remove('musixmatch.token');
          p.setInt('musixmatch.pause', _mxmPause!.millisecondsSinceEpoch);
        })
        .catchError((_) {});
  }

  static Future<String?> _mxmGetToken(http.Client c) async {
    if (_mxmToken != null) return _mxmToken;
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getString('musixmatch.token');
      if (_realToken(saved)) return _mxmToken = saved;
      final pause = p.getInt('musixmatch.pause');
      if (pause != null && _mxmPause == null) _mxmPause = DateTime.fromMillisecondsSinceEpoch(pause);
    } catch (_) {}
    if (_mxmPause != null && DateTime.now().isBefore(_mxmPause!)) return null;
    final res = await c.get(
      Uri.https('apic-desktop.musixmatch.com', '/ws/1.1/token.get', {
        'app_id': _mxmApp,
        'format': 'json',
        'guid': '${DateTime.now().microsecondsSinceEpoch}',
      }),
      headers: _mxmHeaders,
    );
    if (res.statusCode >= 500) _fail('Musixmatch', res);
    String? token;
    try {
      final message = (_json(res) as Map)['message'] as Map;
      final header = message['header'] as Map;
      final body = message['body'];
      if (header['status_code'] == 200 && body is Map) token = body['user_token'] as String?;
    } catch (_) {}
    if (!_realToken(token)) {
      _mxmRefused('no token (status ${res.statusCode})');
      return null;
    }
    try {
      (await SharedPreferences.getInstance()).setString('musixmatch.token', token!);
    } catch (_) {}
    return _mxmToken = token;
  }

  /// Musixmatch through the public desktop-app token: word by word where the
  /// song has it, else timed lines. Can stop working at any time.
  static Future<Lyrics?> musixmatch(Track track, {http.Client? client}) async {
    final want = _ask(track);
    if (want == null) return null;
    final c = client ?? _http;
    final token = await _mxmGetToken(c);
    if (token == null) return null;
    final res = await c.get(
      Uri.https('apic-desktop.musixmatch.com', '/ws/1.1/macro.subtitles.get', {
        'format': 'json',
        'namespace': 'lyrics_richsynched',
        'subtitle_format': 'lrc',
        'app_id': _mxmApp,
        'q_track': want.title,
        'q_artist': want.artist,
        if (want.seconds != null) 'q_duration': '${want.seconds}',
        if (want.seconds != null) 'f_subtitle_length_max_deviation': '3',
        'usertoken': token,
        'optional_calls': 'track.richsync',
      }),
      headers: _mxmHeaders,
    );
    if (res.statusCode >= 500) _fail('Musixmatch', res);
    if (res.statusCode == 401 || res.statusCode == 403 || res.statusCode == 429) {
      _mxmRefused('status ${res.statusCode}');
      return null;
    }
    final Map calls;
    try {
      final message = (_json(res) as Map)['message'] as Map;
      final status = (message['header'] as Map)['status_code'];
      if (status == 401 || status == 402 || status == 429) {
        _mxmRefused('answer $status');
        return null;
      }
      calls = (message['body'] as Map)['macro_calls'] as Map;
    } catch (e) {
      debugPrint('Lyrics: Musixmatch reply not understood: $e');
      return null;
    }
    return parseMusixmatch(calls.cast<String, dynamic>(), want);
  }

  static Map? _mxmBody(Map<String, dynamic> calls, String name) {
    final call = calls[name];
    if (call is! Map) return null;
    final message = call['message'];
    if (message is! Map || (message['header'] as Map?)?['status_code'] != 200) return null;
    return message['body'] as Map?;
  }

  /// The `macro_calls` of a Musixmatch reply → lyrics, null when the match isn't the song.
  @visibleForTesting
  static Lyrics? parseMusixmatch(Map<String, dynamic> calls, ({String title, String artist, int? seconds}) want) {
    final track = _mxmBody(calls, 'matcher.track.get')?['track'];
    if (track is! Map) return null;
    if (!_isSong(
      want,
      title: '${track['track_name']}',
      artists: _split('${track['artist_name']}'),
      seconds: track['track_length'] as num?,
    )) {
      return null;
    }
    if (track['instrumental'] == 1) return const Lyrics(instrumental: true, source: 'Musixmatch');
    final rich = (_mxmBody(calls, 'track.richsync.get')?['richsync'] as Map?)?['richsync_body'];
    if (rich is String && rich.isNotEmpty) {
      try {
        final l = parseRichsync(rich);
        if (l != null) return l;
      } catch (e) {
        debugPrint('Lyrics: Musixmatch richsync: $e');
      }
    }
    final subs = _mxmBody(calls, 'track.subtitles.get')?['subtitle_list'] as List? ?? const [];
    for (final s in subs.whereType<Map>()) {
      final body = (s['subtitle'] as Map?)?['subtitle_body'];
      if (body is! String || body.trim().isEmpty) continue;
      final l = Lyrics.parse(body, source: 'Musixmatch');
      if (l.synced) return l;
    }
    return null;
  }

  /// Musixmatch's richsync: `[{ts, te, l: [{c, o}], x}]`, a line from `ts` to
  /// `te` seconds, each piece `c` starting `o` seconds after `ts`.
  @visibleForTesting
  static Lyrics? parseRichsync(String json) {
    Duration sec(num s) => Duration(milliseconds: (s * 1000).round());
    final lines = <LyricLine>[];
    for (final item in (jsonDecode(json) as List).whereType<Map>()) {
      final ts = item['ts'] as num, te = item['te'] as num;
      // Pieces are words, syllables or single spaces; a space ends a word.
      final starts = <Duration>[];
      final texts = <String>[];
      for (final piece in (item['l'] as List? ?? const []).whereType<Map>()) {
        final c = '${piece['c']}';
        if (c.trim().isEmpty) {
          if (texts.isNotEmpty && !texts.last.endsWith(' ')) texts[texts.length - 1] += ' ';
          continue;
        }
        if (c.startsWith(RegExp(r'\s')) && texts.isNotEmpty && !texts.last.endsWith(' ')) {
          texts[texts.length - 1] += ' ';
        }
        starts.add(sec(ts + (piece['o'] as num)));
        texts.add(c.trimLeft());
      }
      if (texts.isEmpty) continue;
      final lineEnd = sec(te);
      final words = [
        for (var i = 0; i < texts.length; i++)
          LyricWord(
            starts[i],
            i + 1 < texts.length ? starts[i + 1] : (lineEnd > starts[i] ? lineEnd : starts[i]),
            texts[i],
          ),
      ];
      final fixed = _tidy(words);
      final text = fixed.map((w) => w.text).join();
      if (text.isEmpty) continue;
      lines.add(LyricLine(sec(ts), text, end: lineEnd, words: fixed.length > 1 ? fixed : const []));
    }
    return lines.isEmpty ? null : Lyrics(lines: lines, source: 'Musixmatch');
  }

  // ---------------------------------------------------------------- Genius

  /// Genius: the words of the song, no times.
  static Future<Lyrics?> genius(Track track, {http.Client? client}) async {
    final want = _ask(track);
    if (want == null) return null;
    final c = client ?? _http;
    final res = await c.get(
      Uri.https('genius.com', '/api/search/song', {'q': '${want.artist} ${want.title}'}),
      headers: _browser,
    );
    if (res.statusCode != 200) _fail('Genius', res);
    final data = _json(res);
    final sections = ((data is Map ? data['response'] : null) as Map?)?['sections'] as List? ?? const [];
    final hits = [for (final s in sections.whereType<Map>()) ...(s['hits'] as List? ?? const []).whereType<Map>()];
    // Translations and remixes are other titles or other "artists", so they fail the match.
    final matches = <String>[];
    for (final h in hits) {
      final r = h['result'];
      if (r is! Map) continue;
      final url = Uri.tryParse('${r['url']}');
      if (url == null || url.host != 'genius.com' || (r['lyrics_state'] != null && r['lyrics_state'] != 'complete')) {
        continue;
      }
      if (_isSong(
        want,
        title: '${r['title']}',
        artists: [..._split('${(r['primary_artist'] as Map?)?['name']}'), ..._split('${r['artist_names']}')],
      )) {
        matches.add('$url');
      }
    }
    for (final url in matches.take(2)) {
      final page = await c.get(Uri.parse(url), headers: _browser);
      if (page.statusCode == 404) continue;
      if (page.statusCode != 200) _fail('Genius', page);
      final text = geniusText(utf8.decode(page.bodyBytes, allowMalformed: true));
      if (text == null) continue;
      if (RegExp(r'^\[?instrumental\]?$', caseSensitive: false).hasMatch(text)) {
        return const Lyrics(instrumental: true, source: 'Genius');
      }
      return Lyrics(plain: text, source: 'Genius');
    }
    return null;
  }

  /// Everything inside the `<div …>` that starts at [from], tags and all.
  static int _divEnd(String html, int from) {
    final tag = RegExp(r'<(/?)div\b[^>]*>', caseSensitive: false);
    var depth = 0;
    for (final m in tag.allMatches(html, from)) {
      depth += m[1] == '/' ? -1 : 1;
      if (depth == 0) return m.end;
    }
    return html.length;
  }

  static final _htmlEntity = RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);');

  /// "&amp;", "&#x27;", "&#8217;" → the characters.
  static String _unescape(String s) => s.replaceAllMapped(_htmlEntity, (m) {
    final e = m[1]!;
    if (e.startsWith('#x')) return String.fromCharCode(int.parse(e.substring(2), radix: 16));
    if (e.startsWith('#')) return String.fromCharCode(int.parse(e.substring(1)));
    return switch (e) {
      'amp' => '&',
      'lt' => '<',
      'gt' => '>',
      'quot' => '"',
      'apos' => "'",
      'nbsp' => ' ',
      _ => m[0]!,
    };
  });

  /// The words in a Genius song page: its `data-lyrics-container` blocks, line
  /// breaks kept, the "N Contributors … Lyrics" header and ads left out.
  @visibleForTesting
  static String? geniusText(String html) {
    final parts = <String>[];
    final open = RegExp(r'<div\b[^>]*data-lyrics-container="true"[^>]*>', caseSensitive: false);
    var at = 0;
    for (final m in open.allMatches(html)) {
      if (m.start < at) continue; // inside the last one
      at = _divEnd(html, m.start);
      var block = html.substring(m.end, at);
      block = block.endsWith('</div>') ? block.substring(0, block.length - 6) : block;
      // Header, buttons and ads are blocks marked "exclude from selection".
      final skip = RegExp(r'<div\b[^>]*data-exclude-from-selection="true"[^>]*>', caseSensitive: false);
      for (var s = skip.firstMatch(block); s != null; s = skip.firstMatch(block)) {
        block = block.replaceRange(s.start, _divEnd(block, s.start), '');
      }
      parts.add(
        _unescape(
          block.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n').replaceAll(RegExp(r'<[^>]*>'), ''),
        ),
      );
    }
    var text = parts.map((p) => p.trim()).where((p) => p.isNotEmpty).join('\n\n');
    // An older page layout keeps the header inside the text.
    text = text.replaceFirst(RegExp(r'^\d+\s*Contributors?[^\n]*?Lyrics\s*', caseSensitive: false), '');
    text = text
        .replaceAll('\r', '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceFirst(RegExp(r'\d*Embed$'), '')
        .trim();
    return text.isEmpty ? null : text;
  }

  // ------------------------------------------------------------- Megalobiz

  /// Megalobiz (lines with times), asked through its public lyrics API.
  static Future<Lyrics?> megalobiz(Track track, {http.Client? client}) async {
    final want = _ask(track);
    if (want == null) return null;
    final c = client ?? _http;
    const headers = {'User-Agent': 'Riflay (https://github.com/Araryarch67/Riflay)'};
    final res = await c.get(
      Uri.https('api.megalobiz.com', '/api/public/v1/search', {
        'title': want.title,
        'artist': want.artist,
        if (want.seconds != null) 'duration': '${want.seconds}',
        'limit': '10',
      }),
      headers: headers,
    );
    if (res.statusCode == 429) throw const HttpException('Megalobiz 429');
    if (res.statusCode != 200) _fail('Megalobiz', res);
    final data = _json(res);
    final results = (data is Map ? data['results'] : null) as List? ?? const [];
    final matches = results.whereType<Map>().where(
      (r) => _isSong(want, title: '${r['title']}', artists: _split('${r['artist']}'), seconds: r['duration'] as num?),
    );
    for (final r in matches.take(3)) {
      final lr = await c.get(
        Uri.https('api.megalobiz.com', '/api/public/v1/lrc/${r['id']}', {'format': 'lrc'}),
        headers: headers,
      );
      if (lr.statusCode == 404) continue;
      if (lr.statusCode != 200) _fail('Megalobiz', lr);
      final l = _lines(utf8.decode(lr.bodyBytes, allowMalformed: true), want.title, 'Megalobiz');
      if (l != null && l.synced) return l;
    }
    return null;
  }
}
