import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../ui/debug_switches.dart';
import 'audio_engine.dart';

/// One headphone or IEM in AutoEQ's results: its [name], who measured it ([source], on which [rig]), and where
/// its files are ([path], URL-encoded, under the results folder).
@immutable
class AutoEqEntry {
  const AutoEqEntry({required this.name, required this.path, required this.source, this.rig});

  final String name;
  final String path;
  final String source;
  final String? rig;

  /// "crinacle · 711", or the source alone.
  String get by => rig == null ? source : '$source · $rig';

  @override
  bool operator ==(Object other) => other is AutoEqEntry && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

enum AutoEqFilterType { peaking, lowShelf, highShelf }

/// One filter of an AutoEQ ParametricEQ.txt.
@immutable
class AutoEqFilter {
  const AutoEqFilter(this.type, this.frequency, this.gain, this.q);

  final AutoEqFilterType type;
  final double frequency;
  final double gain;
  final double q;
}

/// What [AutoEq.toBands] made of a profile: the equalizer's bands, and how far their curve strays from the
/// profile's, in dB, from 20 Hz to 10 kHz (0 when its filters were taken as they are).
typedef AutoEqFit = ({List<EqBand> bands, double error});

/// AutoEQ (github.com/jaakkopasanen/AutoEq, MIT): equalizer profiles for thousands of headphones and IEMs,
/// each made from a measurement so the model sounds like a neutral target (Harman's). The list of models is
/// downloaded when the picker first opens and kept for [_maxAge]; a profile is downloaded when picked. Nothing
/// is sent but those two requests to GitHub.
///
/// A profile is up to ten filters, peaking ones and shelves. Riflay's equalizer is ten peaking bands (FFmpeg's
/// `equalizer` and Web Audio's peaking filter, in every build), so a profile with shelves is fitted: ten peaking
/// bands that follow the profile's curve ([toBands]).
abstract final class AutoEq {
  static const _base = 'https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results';
  static const _maxAge = Duration(days: 30);

  /// The rate the curves are worked out at (the equalizer's filters differ little between 44.1 and 48 kHz).
  static const _rate = 48000;

  static List<AutoEqEntry>? _index;

  /// Every model in AutoEQ's results, from `results/INDEX.md`: lines like
  /// `- [KZ ZSN Pro](./crinacle/711%20in-ear/KZ%20ZSN%20Pro) by crinacle on 711`.
  static List<AutoEqEntry> parseIndex(String markdown) {
    final line = RegExp(r'^- \[(.+)\]\(\./(.+)\) by (.+?)(?: on (.+))?$');
    return [
      for (final l in markdown.split('\n'))
        if (line.firstMatch(l.trim()) case final m?) AutoEqEntry(name: m[1]!, path: m[2]!, source: m[3]!, rig: m[4]),
    ];
  }

  /// A ParametricEQ.txt's filters (the preamp line is left out: the equalizer works out its own headroom).
  static List<AutoEqFilter> parseParametric(String text) {
    final line = RegExp(
      r'Filter\s*\d*:\s*ON\s+(PK|LSC|HSC|LS|HS)\s+Fc\s+([\d.]+)\s*Hz\s+Gain\s+(-?[\d.]+)\s*dB\s+Q\s+([\d.]+)',
      caseSensitive: false,
    );
    return [
      for (final m in line.allMatches(text))
        AutoEqFilter(
          switch (m[1]!.toUpperCase()) {
            'LSC' || 'LS' => AutoEqFilterType.lowShelf,
            'HSC' || 'HS' => AutoEqFilterType.highShelf,
            _ => AutoEqFilterType.peaking,
          },
          double.parse(m[2]!),
          double.parse(m[3]!),
          double.parse(m[4]!),
        ),
    ];
  }

  /// [text]'s words, lower case, without punctuation, Roman model numbers as digits ("Chu II" is "chu 2").
  static List<String> _words(String text) => [
    for (final w in text.toLowerCase().split(RegExp(r'[^a-z0-9\u00c0-\uffff]+')))
      if (w.isNotEmpty)
        switch (w) {
          'ii' => '2',
          'iii' => '3',
          'iv' => '4',
          final w => w,
        },
  ];

  /// [entries] whose name holds every word of [query], any case, ignoring punctuation and spaces inside a name
  /// ("wh1000xm4" finds "WH-1000XM4", "Chu II" finds "Chu 2"); names that are it or start with it first.
  static List<AutoEqEntry> search(List<AutoEqEntry> entries, String query, {int limit = 100}) {
    final words = _words(query);
    if (words.isEmpty) return const [];
    final q = words.join(' ');
    final found = <(AutoEqEntry, int)>[];
    for (final e in entries) {
      final name = _words(e.name);
      final joined = name.join();
      if (!words.every(joined.contains)) continue;
      final n = name.join(' ');
      found.add((
        e,
        n == q
            ? 0
            : n.startsWith(q)
            ? 1
            : 2,
      ));
    }
    found.sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final (e, _) in found.take(limit)) e];
  }

  /// RBJ biquad coefficients (b0, b1, b2, a0, a1, a2) of [f] at [rate], as AutoEQ, FFmpeg and Web Audio make them.
  static (double, double, double, double, double, double) _coefficients(AutoEqFilter f, int rate) {
    final w0 = 2 * math.pi * f.frequency / rate, cs = math.cos(w0), alpha = math.sin(w0) / (2 * f.q);
    final a = math.pow(10, f.gain / 40).toDouble(), s = 2 * math.sqrt(a) * alpha;
    return switch (f.type) {
      AutoEqFilterType.peaking => (1 + alpha * a, -2 * cs, 1 - alpha * a, 1 + alpha / a, -2 * cs, 1 - alpha / a),
      AutoEqFilterType.lowShelf => (
        a * ((a + 1) - (a - 1) * cs + s),
        2 * a * ((a - 1) - (a + 1) * cs),
        a * ((a + 1) - (a - 1) * cs - s),
        (a + 1) + (a - 1) * cs + s,
        -2 * ((a - 1) + (a + 1) * cs),
        (a + 1) + (a - 1) * cs - s,
      ),
      AutoEqFilterType.highShelf => (
        a * ((a + 1) + (a - 1) * cs + s),
        -2 * a * ((a - 1) + (a + 1) * cs),
        a * ((a + 1) + (a - 1) * cs - s),
        (a + 1) - (a - 1) * cs + s,
        2 * ((a - 1) - (a + 1) * cs),
        (a + 1) - (a - 1) * cs - s,
      ),
    };
  }

  /// [filter]'s gain at each of [freqs], in dB.
  static List<double> _curve(AutoEqFilter filter, List<double> freqs) {
    final (b0, b1, b2, a0, a1, a2) = _coefficients(filter, _rate);
    return [
      for (final f in freqs)
        () {
          final cos1 = math.cos(2 * math.pi * f / _rate), cos2 = 2 * cos1 * cos1 - 1;
          double power(double c0, double c1, double c2) =>
              c0 * c0 + c1 * c1 + c2 * c2 + 2 * c1 * (c0 + c2) * cos1 + 2 * c0 * c2 * cos2;
          return 10 * math.log(power(b0, b1, b2) / power(a0, a1, a2)) / math.ln10;
        }(),
    ];
  }

  /// The combined gain of [filters] at [frequency], in dB.
  static double responseDb(List<AutoEqFilter> filters, double frequency) =>
      filters.fold(0.0, (sum, f) => sum + _curve(f, [frequency]).single);

  static AutoEqFilter _peaking(EqBand b) => AutoEqFilter(AutoEqFilterType.peaking, b.frequency, b.gain, b.q);

  /// The equalizer's [count] bands for a profile's [filters]. Peaking filters inside the equalizer's range
  /// (±12 dB, Q 0.3-8) are taken as they are; otherwise ten peaking bands are fitted to the profile's curve,
  /// 1/12 octave from 20 Hz to 20 kHz (above 10 kHz, where measurements of the ear are least sure, counting
  /// half), starting from its filters with each shelf as a wide band near its corner.
  static AutoEqFit toBands(List<AutoEqFilter> filters, {int count = 10}) {
    EqBand band(AutoEqFilter f) => switch (f.type) {
      AutoEqFilterType.peaking => EqBand(f.frequency, f.gain, q: f.q),
      AutoEqFilterType.lowShelf => EqBand(math.max(20, f.frequency / 2), f.gain, q: 0.5),
      AutoEqFilterType.highShelf => EqBand(math.min(18000, f.frequency * 1.6), f.gain, q: 0.5),
    };
    EqBand clamp(EqBand b) =>
        EqBand(b.frequency.clamp(20, 20000), b.gain.clamp(-12, 12), q: b.q.clamp(0.3, 8).toDouble());
    // The strongest first, when there are more than the equalizer has.
    final sorted = [...filters]..sort((a, b) => b.gain.abs().compareTo(a.gain.abs()));
    final start = [for (final f in sorted.take(count)) clamp(band(f))];
    final asIs =
        filters.length <= count &&
        filters.every(
          (f) =>
              f.type == AutoEqFilterType.peaking && f.gain.abs() <= 12 && f.q >= 0.3 && f.q <= 8 && f.frequency >= 20,
        );
    // Bands with nothing to do sit at the default frequencies the profile leaves free.
    final spare = [
      for (final f in defaultEqFrequencies)
        if (start.every((b) => (math.log(b.frequency / f) / math.ln2).abs() > 0.5)) EqBand(f, 0),
    ];
    List<EqBand> finish(List<EqBand> bands) {
      final all = [...bands, ...spare.take(count - bands.length)];
      for (var f = 20.0; all.length < count; f *= 2) {
        all.add(EqBand(f, 0));
      }
      return [
        for (final b in all..sort((a, b) => a.frequency.compareTo(b.frequency)))
          EqBand(b.frequency.roundToDouble(), (b.gain * 10).roundToDouble() / 10, q: (b.q * 100).roundToDouble() / 100),
      ];
    }

    if (asIs) return (bands: finish(start), error: 0);

    final freqs = [for (var i = 0; i <= 120; i++) 20 * math.pow(2, i / 12).toDouble()];
    final weight = [for (final f in freqs) f > 10000 ? 0.5 : 1.0];
    final target = List.filled(freqs.length, 0.0);
    for (final f in filters) {
      final c = _curve(f, freqs);
      for (var i = 0; i < freqs.length; i++) {
        target[i] += c[i];
      }
    }
    final bands = [...start];
    while (bands.length < count) {
      bands.add(EqBand(spare.isEmpty ? 1000 : spare[bands.length % spare.length].frequency, 0));
    }
    var curves = [for (final b in bands) _curve(_peaking(b), freqs)];
    final sum = List.filled(freqs.length, 0.0);
    for (final c in curves) {
      for (var i = 0; i < freqs.length; i++) {
        sum[i] += c[i];
      }
    }
    double errorWith(int k, List<double> curve) {
      var e = 0.0;
      for (var i = 0; i < freqs.length; i++) {
        final d = sum[i] - curves[k][i] + curve[i] - target[i];
        e += weight[i] * d * d;
      }
      return e;
    }

    var error = errorWith(0, curves[0]);
    // Coordinate descent: each band's gain, frequency and width in turn, smaller steps when nothing helps.
    var steps = (gain: 1.0, octave: 0.25, q: 0.25);
    for (var round = 0; round < 400 && steps.gain > 0.01; round++) {
      var better = false;
      for (var k = 0; k < bands.length; k++) {
        final b = bands[k];
        final tries = [
          b.copyWith(gain: b.gain + steps.gain),
          b.copyWith(gain: b.gain - steps.gain),
          b.copyWith(frequency: b.frequency * math.pow(2, steps.octave)),
          b.copyWith(frequency: b.frequency / math.pow(2, steps.octave)),
          b.copyWith(q: b.q * (1 + steps.q)),
          b.copyWith(q: b.q / (1 + steps.q)),
        ];
        for (final t in tries.map(clamp)) {
          final c = _curve(_peaking(t), freqs);
          final e = errorWith(k, c);
          if (e < error - 1e-9) {
            for (var i = 0; i < freqs.length; i++) {
              sum[i] += c[i] - curves[k][i];
            }
            curves = [...curves]..[k] = c;
            bands[k] = t;
            error = e;
            better = true;
            break;
          }
        }
      }
      if (!better) steps = (gain: steps.gain / 2, octave: steps.octave / 2, q: steps.q / 2);
    }
    var worst = 0.0;
    for (var i = 0; i < freqs.length; i++) {
      if (freqs[i] <= 10000) worst = math.max(worst, (sum[i] - target[i]).abs());
    }
    return (bands: finish(bands.where((b) => b.gain.abs() > 0.05).toList()), error: worst);
  }

  /// [AutoEqEntry.path] and the name as the file's URL.
  static Uri _profileUrl(AutoEqEntry e) =>
      Uri.parse('$_base/${e.path}/${Uri.encodeComponent('${e.name} ParametricEQ.txt')}');

  /// Every model, from the copy kept on this device when it is recent, else downloaded (and kept). An old copy
  /// still serves when the download fails.
  static Future<List<AutoEqEntry>> index({http.Client? client}) async {
    if (_index case final kept? when !DebugSwitches.autoEqFresh) return kept;
    final file = kIsWeb ? null : File(p.join((await getApplicationSupportDirectory()).path, 'autoeq_index.md'));
    final fresh =
        file != null &&
        file.existsSync() &&
        DateTime.now().difference(file.lastModifiedSync()) < _maxAge &&
        !DebugSwitches.autoEqFresh;
    if (fresh) return _index = parseIndex(await file.readAsString());
    try {
      final get = client?.get ?? http.get;
      final r = await get(Uri.parse('$_base/INDEX.md')).timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) throw HttpException('AutoEQ list: HTTP ${r.statusCode}');
      final entries = parseIndex(r.body);
      if (entries.isEmpty) throw const FormatException('AutoEQ list: no models');
      if (file != null) {
        final part = File('${file.path}.part');
        await part.writeAsString(r.body, flush: true);
        await part.rename(file.path);
      }
      return _index = entries;
    } catch (e) {
      if (file != null && file.existsSync()) return _index = parseIndex(await file.readAsString());
      rethrow;
    }
  }

  /// Downloads [e]'s profile and makes the equalizer's bands of it.
  static Future<AutoEqFit> fitFor(AutoEqEntry e, {http.Client? client}) async {
    final get = client?.get ?? http.get;
    final r = await get(_profileUrl(e)).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw HttpException('AutoEQ profile: HTTP ${r.statusCode}');
    final filters = parseParametric(r.body);
    if (filters.isEmpty) throw const FormatException('AutoEQ profile: no filters');
    return compute(_fit, filters);
  }

  static AutoEqFit _fit(List<AutoEqFilter> filters) => toBands(filters);

  /// Drops the list held in memory (Clear cache, tests): the next [index] reads it again.
  static void forgetIndex() => _index = null;
}
