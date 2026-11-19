import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'auto_eq.dart';

/// Additional measured earphone profiles from the OPRA CC BY-SA 4.0 catalog.
abstract final class OpraEq {
  static const cacheName = 'opra_eq.jsonl';
  static final attribution = Uri.parse('https://github.com/opra-project/OPRA#how-is-this-repository-licensed');
  static final _url = Uri.parse('https://raw.githubusercontent.com/opra-project/OPRA/main/dist/database_v1.jsonl');
  static const _maxAge = Duration(days: 7);
  static Future<List<AutoEqEntry>>? _pending;

  static Future<List<AutoEqEntry>> index({http.Client? client}) => _pending ??= _load(client).then(
    (entries) => entries,
    onError: (Object error, StackTrace stack) {
      _pending = null;
      Error.throwWithStackTrace(error, stack);
    },
  );

  static Future<List<AutoEqEntry>> _load(http.Client? client) async {
    final file = kIsWeb ? null : File(p.join((await getApplicationSupportDirectory()).path, cacheName));
    final modified = await file?.lastModified().then<DateTime?>((value) => value, onError: (Object _) => null);
    Future<List<AutoEqEntry>> readCache(File cached) async => compute(parse, await cached.readAsBytes());
    if (file != null && modified != null && DateTime.now().difference(modified) < _maxAge) {
      final cached = await readCache(file);
      if (cached.isNotEmpty) return cached;
    }
    try {
      final response = await (client?.get ?? http.get)(_url).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200 || response.bodyBytes.length > 32 * 1024 * 1024) {
        throw const FormatException('Invalid OPRA download');
      }
      final parsed = await compute(parse, response.bodyBytes);
      if (parsed.isEmpty) throw const FormatException('Empty OPRA catalog');
      if (file != null) {
        final part = File('${file.path}.part');
        try {
          await part.writeAsBytes(response.bodyBytes, flush: true);
          await part.rename(file.path);
        } on FileSystemException catch (e) {
          debugPrint('OPRA cache could not be written: ${e.runtimeType}');
        }
      }
      return parsed;
    } catch (_) {
      if (file != null && modified != null) {
        final cached = await readCache(file);
        if (cached.isNotEmpty) return cached;
      }
      rethrow;
    }
  }

  /// Reads the documented vendor, product and EQ relationships in the JSONL distribution.
  static List<AutoEqEntry> parse(Uint8List bytes) {
    final vendors = <String, String>{};
    final earphones = <String, (String, String)>{};
    final profiles = <({String id, String productId, String author, String? details, List<AutoEqFilter> filters})>[];
    for (final line in LineSplitter.split(utf8.decode(bytes, allowMalformed: true))) {
      final Object? json;
      try {
        json = jsonDecode(line);
      } on FormatException {
        continue;
      }
      switch (json) {
        case {'type': 'vendor', 'id': final String id, 'data': {'name': final String name}}:
          vendors[id] = name;
        case {
          'type': 'product',
          'id': final String id,
          'data': {'name': final String name, 'vendor_id': final String vendor, 'subtype': 'in_ear' || 'earbuds'},
        }:
          earphones[id] = (name, vendor);
        case {'type': 'eq', 'id': final String id, 'data': final Map data}:
          if (data
              case {
                'type': 'parametric_eq',
                'product_id': final String product,
                'author': final String author,
                'parameters': {'bands': final List bands},
              }
              when bands.isNotEmpty && bands.length <= 32) {
            final filters = [for (final band in bands) ?_filter(band)];
            if (filters.length == bands.length) {
              final details = data['details'];
              profiles.add((
                id: id,
                productId: product,
                author: author,
                details: details is String ? details : null,
                filters: filters,
              ));
            }
          }
      }
    }
    return [
      for (final profile in profiles)
        if (earphones[profile.productId] case (final model, final vendor))
          AutoEqEntry(
            name: _modelName(vendors[vendor] ?? '', model),
            path: 'opra:${profile.id}',
            source: '${profile.author} (OPRA)',
            rig: profile.details,
            filters: profile.filters,
          ),
    ];
  }

  static String _modelName(String brand, String model) =>
      brand.isEmpty || model.toLowerCase().startsWith('${brand.toLowerCase()} ') ? model : '$brand $model';

  static AutoEqFilter? _filter(Object? band) {
    if (band case {'type': final String kind, 'frequency': final num frequency, 'q': final num q}) {
      final gain = (band as Map)['gain_db'] ?? 0;
      if (gain is! num || gain.abs() > 60 || frequency < 10 || frequency > 20000 || q < .1 || q > 100) return null;
      final type = switch (kind) {
        'peak_dip' => AutoEqFilterType.peaking,
        'low_shelf' => AutoEqFilterType.lowShelf,
        'high_shelf' => AutoEqFilterType.highShelf,
        _ => null,
      };
      if (type != null) return AutoEqFilter(type, frequency.toDouble(), gain.toDouble(), q.toDouble());
    }
    return null;
  }

  static void forgetIndex() => _pending = null;
}
