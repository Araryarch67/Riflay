import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer;
// Use the library media_kit actually loaded, including bundled Android/Apple builds.
// ignore: implementation_imports
import 'package:media_kit/src/player/native/core/native_library.dart';

typedef _GetProperty = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _FreeNative = Void Function(Pointer<Void>);
typedef _Free = void Function(Pointer<Void>);

/// A separate client keeps the core alive if playback is disposed during the read.
/// Only primitive data crosses the isolate boundary, never the player or its event queue.
Future<Map<String, String>> readMpvSnapshot(NativePlayer player, List<String> properties) async {
  if (player.disposed) return {};
  final library = NativeLibrary.path;
  final client = player.mpv.mpv_create_client(player.ctx, nullptr);
  if (client == nullptr) return {};
  try {
    return await compute(_readSnapshot, (library, client.address, properties));
  } catch (_) {
    // The worker catches read errors and releases its client; failure to start it leaves ownership here.
    player.mpv.mpv_destroy(client);
    return {};
  }
}

Map<String, String> _readSnapshot((String, int, List<String>) request) {
  final (path, address, properties) = request;
  final library = DynamicLibrary.open(path);
  final destroy = library.lookupFunction<_FreeNative, _Free>('mpv_destroy');
  final client = Pointer<Void>.fromAddress(address);
  try {
    final get = library.lookupFunction<_GetProperty, _GetProperty>('mpv_get_property_string');
    final free = library.lookupFunction<_FreeNative, _Free>('mpv_free');
    final values = <String, String>{};
    for (final property in properties) {
      final name = property.toNativeUtf8();
      try {
        final value = get(client, name);
        if (value == nullptr) {
          values[property] = '';
        } else {
          try {
            values[property] = value.toDartString();
          } finally {
            free(value.cast());
          }
        }
      } finally {
        calloc.free(name);
      }
    }
    return values;
  } catch (_) {
    return {};
  } finally {
    destroy(client);
  }
}
