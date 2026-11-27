import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'audio_engine.dart';
import 'auto_eq.dart';

/// A frequency response: dB at each frequency (Hz), lowest first.
typedef FrCurve = ({List<double> freqs, List<double> db});

/// A headphone's measurement or a target curve, where it is fetched from, and who it is credited to.
@immutable
class LabCurve {
  const LabCurve({required this.name, required this.urls, required this.source, this.inEar});

  final String name;

  /// The files that make it up, averaged (a squig.link left and right channel; one file elsewhere).
  final List<Uri> urls;

  /// Who measured it or made it ("AutoEQ · crinacle", "squig.link"...).
  final String source;

  /// An in-ear's measurement (an over-ear's when false), when known: the target it starts with.
  final bool? inEar;

  @override
  bool operator ==(Object other) => other is LabCurve && listEquals(other.urls, urls);

  @override
  int get hashCode => Object.hashAll(urls);
}

/// What [AudioLab.fit] made: the equalizer's bands, and the curves to draw, on [AutoEq.fitFrequencies], each in dB
/// with the headphone's midrange at 0: the headphone, the target set to its level, and the headphone with the bands.
typedef LabFit = ({List<EqBand> bands, double error, List<double> headphone, List<double> target, List<double> after});

/// Riflay's audio lab: a headphone's measured frequency response, from AutoEQ's measurements, a squig.link site or a
/// file, set against a target (Harman's and others) and the equalizer fitted to close the gap. Measurements and
/// targets are fetched when picked, from the site they belong to; nothing else is sent.
abstract final class AudioLab {
  static const _autoEq = 'https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master';

  /// The targets AutoEQ keeps (github.com/jaakkopasanen/AutoEq/tree/master/targets), the useful ones, in-ear ones
  /// marked.
  static final targets = [
    for (final (name, inEar) in const [
      ('Harman over-ear 2018', false),
      ('Harman in-ear 2019', true),
      ('Harman over-ear 2018 without bass', false),
      ('Harman in-ear 2019 without bass', true),
      ('Diffuse field ISO 11904-1', null),
      ('Diffuse field 5128 -1dB per octave', null),
      ('oratory1990 optimum hifi over-ear', false),
      ('oratory1990 in-ear', true),
      ('AutoEq in-ear', true),
      ('zero', null),
    ])
      LabCurve(
        name: name == 'zero' ? 'Flat' : name,
        urls: [Uri.parse('$_autoEq/targets/${Uri.encodeComponent('$name.csv')}')],
        source: 'AutoEQ',
        inEar: inEar,
      ),
  ];

  /// The target a headphone starts with: Harman's for its kind.
  static LabCurve defaultTarget(LabCurve headphone) => targets[headphone.inEar == true ? 1 : 0];

  /// [e]'s measurement in AutoEQ's results (its CSV, whose second column is the raw response).
  static LabCurve fromAutoEq(AutoEqEntry e) => LabCurve(
    name: e.name,
    urls: [Uri.parse('$_autoEq/results/${e.path}/${Uri.encodeComponent('${e.name}.csv')}')],
    source: 'AutoEQ · ${e.by}',
    inEar: e.path.contains('in-ear') || e.path.contains('earbud'),
  );

  /// A frequency response from text: REW's and squig.link's `.txt`, AutoEQ's and others' `.csv`. Each line with two
  /// numbers (frequency, dB) counts; comments, headers and further columns are passed over.
  static FrCurve parse(String text) {
    final points = <(double, double)>[];
    for (final line in const LineSplitter().convert(text)) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('*') || t.startsWith('#') || t.startsWith('"')) continue;
      final cells = t.split(RegExp(r'[\s,;]+'));
      if (cells.length < 2) continue;
      final f = double.tryParse(cells[0]), db = double.tryParse(cells[1]);
      if (f == null || db == null || f <= 0 || !db.isFinite) continue;
      points.add((f, db));
    }
    points.sort((a, b) => a.$1.compareTo(b.$1));
    return (freqs: [for (final p in points) p.$1], db: [for (final p in points) p.$2]);
  }

  /// [c] at each of [freqs], straight between its points on a log scale, its ends held beyond them.
  static List<double> sample(FrCurve c, List<double> freqs) {
    if (c.freqs.isEmpty) return List.filled(freqs.length, 0);
    final out = <double>[];
    var j = 0;
    for (final f in freqs) {
      if (f <= c.freqs.first) {
        out.add(c.db.first);
        continue;
      }
      if (f >= c.freqs.last) {
        out.add(c.db.last);
        continue;
      }
      while (j < c.freqs.length - 2 && c.freqs[j + 1] < f) {
        j++;
      }
      while (j > 0 && c.freqs[j] > f) {
        j--;
      }
      final f0 = c.freqs[j], f1 = c.freqs[j + 1];
      final t = (math.log(f / f0) / math.log(f1 / f0)).clamp(0.0, 1.0);
      out.add(c.db[j] + (c.db[j + 1] - c.db[j]) * t);
    }
    return out;
  }

  /// The mean of [values] where [freqs] is between 300 Hz and 3 kHz: a curve's midrange level.
  static double _mid(List<double> freqs, List<double> values) {
    var sum = 0.0, n = 0;
    for (var i = 0; i < freqs.length; i++) {
      if (freqs[i] >= 300 && freqs[i] <= 3000) {
        sum += values[i];
        n++;
      }
    }
    return n == 0 ? 0 : sum / n;
  }

  /// [c] on [AutoEq.fitFrequencies] with its midrange (300 Hz-3 kHz) at 0 dB, so curves measured at different
  /// levels can be drawn and compared together.
  static List<double> level(FrCurve c) {
    final freqs = AutoEq.fitFrequencies;
    final v = sample(c, freqs);
    final mid = _mid(freqs, v);
    return [for (final x in v) x - mid];
  }

  /// [target] (levelled, on [AutoEq.fitFrequencies]) to taste: [bass] dB more below about 105 Hz (a low shelf, as
  /// Harman's own bass adjustment is) and [tilt] dB per octave about 1 kHz (positive brighter), levelled again.
  static List<double> adjusted(List<double> target, {double bass = 0, double tilt = 0}) {
    if (bass == 0 && tilt == 0) return target;
    final freqs = AutoEq.fitFrequencies;
    final shelf = AutoEqFilter(AutoEqFilterType.lowShelf, 105, bass, 0.7);
    final out = [
      for (var i = 0; i < freqs.length; i++)
        target[i] +
            (bass == 0 ? 0 : AutoEq.responseDb([shelf], freqs[i])) +
            tilt * math.log(freqs[i] / 1000) / math.ln2,
    ];
    final mid = _mid(freqs, out);
    return [for (final x in out) x - mid];
  }

  /// The equalizer that brings [headphone] to [target] (both levelled, on [AutoEq.fitFrequencies]): their gap,
  /// smoothed over a third of an octave (a measurement's narrow wiggles are its rig's as much as the headphone's) and
  /// held to ±12 dB, fitted with the equalizer's ten bands.
  static AutoEqFit fitBands(List<double> headphone, List<double> target) {
    final gap = [for (var i = 0; i < headphone.length; i++) target[i] - headphone[i]];
    // A third of an octave: two points of the 1/12-octave grid either side.
    final smooth = [
      for (var i = 0; i < gap.length; i++)
        () {
          var sum = 0.0, n = 0;
          for (var k = math.max(0, i - 2); k <= math.min(gap.length - 1, i + 2); k++) {
            sum += gap[k];
            n++;
          }
          return (sum / n).clamp(-12.0, 12.0);
        }(),
    ];
    return AutoEq.fitCurve(AutoEq.fitFrequencies, smooth);
  }

  /// What [bands] do on [AutoEq.fitFrequencies], in dB.
  static List<double> response(List<EqBand> bands) => [for (final f in AutoEq.fitFrequencies) AutoEq.bandsDb(bands, f)];

  /// [headphone] brought to [target] in one go: the bands, and the curves to draw.
  static LabFit fit(FrCurve headphone, FrCurve target) {
    final h = level(headphone), t = level(target);
    final eq = fitBands(h, t);
    final r = response(eq.bands);
    return (
      bands: eq.bands,
      error: eq.error,
      headphone: h,
      target: t,
      after: [for (var i = 0; i < h.length; i++) h[i] + r[i]],
    );
  }

  /// [bands] as AutoEQ's ParametricEQ.txt (what Equalizer APO, Wavelet, Peace and most EQ apps read), with the
  /// preamp that keeps the loudest boost from clipping.
  static String parametricText(List<EqBand> bands) {
    final peak = response(bands).fold(0.0, math.max);
    final lines = ['Preamp: ${(-peak).toStringAsFixed(1)} dB'];
    for (final (i, b) in bands.indexed) {
      lines.add(
        'Filter ${i + 1}: ON PK Fc ${b.frequency.round()} Hz Gain ${b.gain.toStringAsFixed(1)} dB Q ${b.q.toStringAsFixed(2)}',
      );
    }
    return lines.join('\n');
  }

  /// [curve]'s files fetched and averaged on [AutoEq.fitFrequencies] (a channel that fails is left out).
  static Future<FrCurve> load(LabCurve curve, {http.Client? client}) async {
    final get = client?.get ?? http.get;
    final got = <FrCurve>[];
    Object? failure;
    for (final url in curve.urls) {
      try {
        final r = await get(url).timeout(const Duration(seconds: 30));
        if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
        final c = parse(utf8.decode(r.bodyBytes, allowMalformed: true));
        if (c.freqs.length >= 8) got.add(c);
      } catch (e) {
        failure = e;
      }
    }
    if (got.isEmpty) throw Exception('no response in ${curve.name}: $failure');
    if (got.length == 1) return got.single;
    final freqs = AutoEq.fitFrequencies;
    final all = [for (final c in got) sample(c, freqs)];
    return (freqs: freqs, db: [for (var i = 0; i < freqs.length; i++) all.fold(0.0, (s, c) => s + c[i]) / all.length]);
  }

  // squig.link -------------------------------------------------------------------------------------------------------

  /// squig.link sites to pick from, by name; any other can be typed in.
  static const squigSites = [
    (name: 'squig.link (Super*)', url: 'squig.link'),
    (name: 'CSI Zone', url: 'csi-zone.squig.link'),
    (name: 'Kuping Sensi', url: 'kuping-sensi.squig.link'),
  ];

  /// [site] as the folder it is served from, with `https://` and a trailing slash (a page's address is its folder).
  static Uri squigBase(String site) {
    var s = site.trim();
    if (!s.contains('://')) s = 'https://$s';
    final u = Uri.parse(s);
    var path = u.path;
    if (!path.endsWith('/')) {
      path = path.split('/').last.contains('.') ? path.substring(0, path.lastIndexOf('/') + 1) : '$path/';
    }
    return Uri(scheme: u.scheme, host: u.host, port: u.hasPort ? u.port : null, path: path);
  }

  /// The data folder a site's `config.js` names (`DIR = "data/"`), or `data/`.
  static String squigDir(String config) =>
      RegExp(r'''DIR\s*=\s*["']([^"']+)["']''').firstMatch(config)?.group(1) ?? 'data/';

  /// The targets a site's `config.js` lists in `const targets = [...]` (lines commented out left out).
  static List<String> squigTargetNames(String config) {
    final at = config.indexOf(RegExp(r'targets\s*=\s*\['));
    if (at < 0) return const [];
    final code = [for (final line in const LineSplitter().convert(config.substring(at))) line.split('//').first]
        .join('\n');
    // To the bracket that closes the list.
    var depth = 0, end = code.length;
    for (var i = code.indexOf('['); i < code.length; i++) {
      if (code[i] == '[') depth++;
      if (code[i] == ']' && --depth == 0) {
        end = i;
        break;
      }
    }
    return [
      for (final m in RegExp(r'files\s*:\s*\[([^\]]*)\]').allMatches(code.substring(0, end)))
        ...RegExp(r'''["']([^"']+)["']''').allMatches(m.group(1)!).map((x) => x.group(1)!),
    ];
  }

  /// Every measurement a site's `phone_book.json` lists, a model's variants (tips, inserts…) each its own.
  static List<LabCurve> squigPhones(String phoneBook, Uri data, String siteName) {
    final out = <LabCurve>[];
    final brands = jsonDecode(phoneBook);
    if (brands is! List) return out;
    for (final brand in brands) {
      if (brand is! Map) continue;
      final brandName = '${brand['name'] ?? ''}'.trim();
      if (brandName.startsWith('_')) continue; // a site's own sandboxes
      for (final phone in (brand['phones'] as List? ?? const [])) {
        if (phone is! Map) continue;
        final name = '${phone['name'] ?? ''}'.trim();
        final files = switch (phone['file']) {
          final String f => [f],
          final List l => [for (final f in l) '$f'],
          _ => const <String>[],
        };
        final suffixes = switch (phone['suffix']) {
          final List l => [for (final x in l) '$x'],
          _ => const <String>[],
        };
        for (final (i, file) in files.indexed) {
          final suffix = i < suffixes.length ? suffixes[i].trim() : '';
          out.add(
            LabCurve(
              name: [brandName, name, suffix].where((x) => x.isNotEmpty).join(' '),
              urls: [
                data.resolve(Uri.encodeComponent('$file L.txt')),
                data.resolve(Uri.encodeComponent('$file R.txt')),
              ],
              source: siteName,
            ),
          );
        }
      }
    }
    return out;
  }

  /// A squig.link site's measurements and targets.
  static Future<({List<LabCurve> phones, List<LabCurve> targets})> squig(String site, {http.Client? client}) async {
    final get = client?.get ?? http.get;
    final base = squigBase(site);
    var config = '';
    try {
      final r = await get(base.resolve('config.js')).timeout(const Duration(seconds: 30));
      if (r.statusCode == 200) config = r.body;
    } catch (_) {
      // No config: the usual data folder, no targets of its own.
    }
    final data = base.resolve(squigDir(config));
    final r = await get(data.resolve('phone_book.json')).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw Exception('squig.link phone book: HTTP ${r.statusCode}');
    final siteName = base.host + (base.path == '/' ? '' : base.path.replaceAll(RegExp(r'/$'), ''));
    return (
      phones: squigPhones(utf8.decode(r.bodyBytes, allowMalformed: true), data, siteName),
      targets: [
        for (final t in squigTargetNames(config))
          LabCurve(name: t, urls: [data.resolve(Uri.encodeComponent('$t Target.txt'))], source: siteName),
      ],
    );
  }
}
