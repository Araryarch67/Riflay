import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/layout_prefs.dart';
import '../../services/metadata.dart';
import '../../services/player_controller.dart';
import '../../services/splash_window.dart';
import '../player/now_playing_page.dart' show BlurredCover;
import '../theme.dart';
import 'controls.dart' show Artwork;

/// Settings › Glass over the cover: what shows behind the glass panels (the playing song's cover, a random cover
/// or the user's own picture, blurred or sharp) under a veil so text on the glass reads. A cover is a random
/// one from the library before anything plays (one for the run). Nothing is drawn while the setting is off, nor
/// behind the start-up intro (its window is see-through).
class CoverBackdrop extends StatelessWidget {
  const CoverBackdrop({super.key, required this.child});

  final Widget child;

  /// The library song shown as a random cover: picked once, so the background holds still.
  static String? _randomId;

  static Track? _random(PlayerController c) {
    final withCovers = c.library.where((t) => t.artworkUrl != null || t.uri.isScheme('file')).toList();
    if (withCovers.isEmpty) return null;
    final kept = withCovers.where((t) => t.id == _randomId).firstOrNull;
    if (kept != null) return kept;
    final pick = withCovers[math.Random().nextInt(withCovers.length)];
    _randomId = pick.id;
    return pick;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([LayoutPrefs.instance, SplashWindow.active]),
    builder: (context, app) {
      final prefs = LayoutPrefs.instance;
      if (!prefs.coverGlass || SplashWindow.active.value) return app!;
      final image = prefs.glassBackground == GlassBackground.image ? prefs.glassImage : null;
      return Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: AppColors.solidBackground),
          PlayerSelect<({Track? track, int library})>(
            select: (c) => (track: c.currentTrack, library: c.libraryRevision.value),
            builder: (context, now, _) {
              final player = PlayerScope.read(context);
              final cover = prefs.glassBackground == GlassBackground.playing
                  ? now.track ?? _random(player)
                  : _random(player);
              final Widget picture;
              if (image != null) {
                picture = _Picture(
                  key: ValueKey('image:$image:${prefs.glassBlur}'),
                  path: image,
                  blur: prefs.glassBlur,
                );
              } else if (cover == null) {
                picture = const SizedBox.expand();
              } else {
                final key = cover.albumKey ?? cover.id;
                picture = RepaintBoundary(
                  key: ValueKey('$key:${prefs.glassBlur}'),
                  child: prefs.glassBlur
                      ? BlurredCover(track: cover)
                      : SizedBox.expand(child: Artwork(track: cover, radius: 0)),
                );
              }
              return _ShadeProbe(
                track: image == null ? cover : null,
                image: image,
                child: AnimatedSwitcher(duration: LayoutPrefs.dur(const Duration(milliseconds: 600)), child: picture),
              );
            },
          ),
          // The veil: dark under a dark theme, light under a light one; heavier towards the foot, and over a
          // bright picture (where white text would otherwise sink into it).
          ValueListenableBuilder<double>(
            valueListenable: GlassShade.brightness,
            builder: (context, bright, _) => DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: AppColors.light
                      ? [
                          Colors.white.withValues(alpha: 0.30 + 0.15 * (1 - bright)),
                          Colors.white.withValues(alpha: 0.45 + 0.15 * (1 - bright)),
                        ]
                      : [
                          Colors.black.withValues(alpha: 0.18 + 0.30 * bright),
                          Colors.black.withValues(alpha: 0.40 + 0.22 * bright),
                        ],
                ),
              ),
            ),
          ),
          // Panels read the picture's brightness through their colours (AppColors.of): a new one refreshes them.
          ValueListenableBuilder<double>(
            valueListenable: GlassShade.brightness,
            builder: (context, _, app) => AppColorsScope(colors: AppColorsScope.current(), child: app!),
            child: app,
          ),
        ],
      );
    },
    child: child,
  );
}

/// The user's picture filling the window: sharp, or blurred (decoded small and blurred once, as a still layer).
class _Picture extends StatelessWidget {
  const _Picture({super.key, required this.path, required this.blur});

  final String path;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    Widget missing(BuildContext context, Object error, StackTrace? stack) => const SizedBox.expand();
    if (!blur) {
      return SizedBox.expand(
        child: Image.file(file, fit: BoxFit.cover, filterQuality: FilterQuality.medium, errorBuilder: missing),
      );
    }
    // A small decode, stretched smoothly and blurred a little: the soft look without blurring a full-size picture.
    return RepaintBoundary(
      child: ClipRect(
        child: Transform.scale(
          // Past the edges, where the blur would fade to nothing.
          scale: 1.08,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: SizedBox.expand(
              child: Image.file(
                file,
                fit: BoxFit.cover,
                cacheWidth: 96,
                filterQuality: FilterQuality.medium,
                errorBuilder: missing,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Measures how bright the picture is (its average luminance, 0 to 1) into [GlassShade.brightness]: [track]'s
/// cover, or the picture at [image].
class _ShadeProbe extends StatefulWidget {
  const _ShadeProbe({required this.track, required this.image, required this.child});

  final Track? track;
  final String? image;
  final Widget child;

  @override
  State<_ShadeProbe> createState() => _ShadeProbeState();
}

class _ShadeProbeState extends State<_ShadeProbe> {
  String? _key;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  @override
  void didUpdateWidget(_ShadeProbe old) {
    super.didUpdateWidget(old);
    _measure();
  }

  Future<void> _measure() async {
    final track = widget.track, image = widget.image;
    final key = image ?? (track == null ? null : track.albumKey ?? track.id);
    if (key == _key) return;
    _key = key;
    if (key == null) return;
    try {
      final Uint8List? bytes = image != null
          ? await File(image).readAsBytes()
          : Metadata.cachedThumbnail(track!) ?? await Metadata.thumbnail(track);
      if (bytes == null || !mounted || key != _key) return;
      // Eight by eight is plenty for an average.
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 8, targetHeight: 8);
      final frame = (await codec.getNextFrame()).image;
      codec.dispose();
      final data = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.dispose();
      if (data == null || !mounted || key != _key) return;
      var sum = 0.0;
      final pixels = data.lengthInBytes ~/ 4;
      for (var i = 0; i < pixels; i++) {
        final r = data.getUint8(i * 4), g = data.getUint8(i * 4 + 1), b = data.getUint8(i * 4 + 2);
        sum += (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
      }
      GlassShade.brightness.value = (sum / pixels).clamp(0.0, 1.0);
    } catch (e) {
      debugPrint('Background brightness not measured: $e');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
