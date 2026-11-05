import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/layout_prefs.dart';
import '../../services/metadata.dart';
import '../theme.dart';

/// A cover with no frame (Cover: Background): the artwork fills its box, sharp at the top and softer and softer
/// towards the bottom, keeping its own colours, slightly darkened where text sits on it.
///
/// The picture is baked once per song and size into one still image: a blurred copy of the cover over the whole box,
/// the sharp cover across the top fading out into it, a darkening gradient. It is then drawn with a plain [RawImage]:
/// nothing blurs while the song plays, so it costs no more than any picture. Lightweight keeps the sharp cover, with
/// no blur, and the darkening; behind text ([sharp] off, the lyrics) the picture is blurred to its colours always.
class FadedCover extends StatefulWidget {
  const FadedCover({
    super.key,
    required this.track,
    this.fade,
    this.blurStart = 0.5,
    this.sharp = true,
    this.darken = 0.4,
    this.fadeSide = false,
  });

  final Track? track;

  /// The colour of the page the cover meets at its foot (and, with [fadeSide], at its right edge): the picture ends
  /// in exactly that colour. Null when the cover is the whole page.
  final Color? fade;

  /// How far down the sharp cover (a square across the top, a little taller) it starts to give way to the blur: 0 to
  /// 1 of its height. It is gone at its foot.
  final double blurStart;

  /// False: no sharp cover at all, the whole box is the soft blur (behind lyrics).
  final bool sharp;

  /// How dark (0 to 1) the lower end is made, so text on it stays readable.
  final double darken;

  /// Also ends in [fade] over the right edge, where another panel follows.
  final bool fadeSide;

  @override
  State<FadedCover> createState() => _FadedCoverState();
}

class _FadedCoverState extends State<FadedCover> {
  // The last one baked, so reopening a page on the same song draws it at once.
  static String? _lastKey;
  static ui.Image? _last;

  // Longest picture baked: the page's logical size, capped.
  static const _maxWidth = 720;

  ui.Image? _image;
  String? _key;

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  int _up(num v) => ((v / 8).ceil() * 8).toInt();

  void _want(Track track, Size box) {
    final w = math.min(_maxWidth, _up(box.width));
    final h = math.min(1800, _up(box.height * w / box.width));
    final key = [
      track.albumKey ?? track.id,
      w,
      h,
      widget.blurStart,
      widget.sharp,
      widget.darken,
      LayoutPrefs.lightweight,
    ].join('|');
    if (key == _key) return;
    _key = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && key == _key) _bake(key, track, w, h);
    });
  }

  Future<void> _bake(String key, Track track, int w, int h) async {
    if (key == _lastKey && _last != null) {
      _show(_last!.clone());
      return;
    }
    final bytes = Metadata.cachedArtwork(track) ?? await Metadata.artwork(track);
    if (bytes == null || !mounted || key != _key) return;
    ui.Image? big, small, soft;
    try {
      Future<ui.Image> decode(int width) async {
        final codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
        final frame = await codec.getNextFrame();
        codec.dispose();
        return frame.image;
      }

      big = await decode(math.min(1024, math.max(w, h)));
      // Behind text (lyrics: no sharp cover) the picture is only its colours: a far smaller copy, stretched, so no
      // shape of the artwork is left to read through the words.
      small = await decode(widget.sharp ? 48 : 16);
      final veil = await _brightVeil(small, lowerOnly: widget.sharp);
      // Baked once per song, never per frame: behind text it is blurred in Lightweight too.
      final blur = !LayoutPrefs.lightweight || !widget.sharp;
      if (blur) {
        // Blurred once into a tiny picture, then stretched smoothly: that stretch is the soft look.
        final size = Size(small.width.toDouble(), small.height.toDouble());
        final tiny = ui.PictureRecorder();
        Canvas(tiny).drawImageRect(
          small,
          Offset.zero & size,
          Offset.zero & size,
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: widget.sharp ? 2 : 3,
              sigmaY: widget.sharp ? 2 : 3,
              tileMode: TileMode.clamp,
            ),
        );
        final picture = tiny.endRecording();
        soft = await picture.toImage(small.width, small.height);
        picture.dispose();
      }
      if (!mounted || key != _key) return;
      final rect = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, rect);

      // BoxFit.cover of [image] over [into].
      Rect source(ui.Image image, Rect into) {
        final size = Size(image.width.toDouble(), image.height.toDouble());
        // Anchored at the top, so heads and faces stay in view when the picture is cropped.
        return Alignment.topCenter.inscribe(applyBoxFit(BoxFit.cover, size, into.size).source, Offset.zero & size);
      }

      // The base: the blurred cover over the whole box (a small copy, stretched: that is the blur).
      // Lightweight has no blur: the sharp cover stretched over the box instead.
      if (soft != null) {
        canvas.drawImageRect(soft, source(soft, rect), rect, Paint()..filterQuality = FilterQuality.high);
      } else {
        canvas.drawImageRect(big, source(big, rect), rect, Paint()..filterQuality = FilterQuality.medium);
      }
      // The sharp cover across the top, fading out into the blur. Its own layer, once: this runs while baking.
      final sharpHeight = math.min(h.toDouble(), w * 1.25);
      if (widget.sharp && soft != null) {
        final top = Rect.fromLTWH(0, 0, w.toDouble(), sharpHeight);
        canvas.saveLayer(top, Paint());
        canvas.drawImageRect(big, source(big, top), top, Paint()..filterQuality = FilterQuality.medium);
        canvas.drawRect(
          top,
          Paint()
            ..blendMode = BlendMode.dstIn
            ..shader = ui.Gradient.linear(
              Offset.zero,
              Offset(0, sharpHeight),
              const [Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
              [0, widget.blurStart.clamp(0, 0.95), 1],
            ),
        );
        canvas.restore();
      }
      // A light veil at the top for the status bar and a darker one at the foot for the controls.
      final holdsAt = (sharpHeight * widget.blurStart / h).clamp(0.2, 0.9);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero,
            Offset(0, h.toDouble()),
            [
              Colors.black.withValues(alpha: 0.35),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: widget.darken),
            ],
            [0, 0.16, holdsAt, 1],
          ),
      );
      // A bright cover gets more shade where the text sits, so white text stays readable on it without changing
      // colour. A dark cover gets none. The darkening above already counts: the foot needs less on top of it.
      if (veil > 0) {
        final foot = math.max(0.0, 1 - (1 - veil) / (1 - widget.darken));
        final from = widget.sharp ? holdsAt : 0.0;
        canvas.drawRect(
          rect,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset.zero,
              Offset(0, h.toDouble()),
              [
                Colors.transparent,
                Colors.black.withValues(alpha: widget.sharp ? 0 : veil),
                Colors.black.withValues(alpha: veil),
                Colors.black.withValues(alpha: foot),
              ],
              [0, from, math.min(0.95, from + (widget.sharp ? 0.25 : 0)), 1],
            ),
        );
      }
      final picture = recorder.endRecording();
      final baked = await picture.toImage(w, h);
      picture.dispose();
      if (!mounted || key != _key) {
        baked.dispose();
        return;
      }
      _last?.dispose();
      _lastKey = key;
      _last = baked;
      _show(baked.clone());
    } catch (e) {
      debugPrint('Baking the cover failed: $e');
    } finally {
      big?.dispose();
      small?.dispose();
      soft?.dispose();
    }
  }

  /// How much shade (0 to 0.6) a cover this bright needs for white text to read on it: none for a dark one. Goes
  /// by its brighter parts (the 75th percentile), in the lower part only when the sharp cover holds the top.
  static Future<double> _brightVeil(ui.Image image, {required bool lowerOnly}) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return 0;
    double linear(int v) {
      final c = v / 255;
      return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }

    final lum = <double>[];
    for (var y = lowerOnly ? image.height ~/ 2 : 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final i = (y * image.width + x) * 4;
        lum.add(
          0.2126 * linear(data.getUint8(i)) +
              0.7152 * linear(data.getUint8(i + 1)) +
              0.0722 * linear(data.getUint8(i + 2)),
        );
      }
    }
    if (lum.isEmpty) return 0;
    lum.sort();
    final bright = lum[(lum.length * 0.75).floor()];
    // White on it reaches about 4.5:1 at a luminance of 0.18. A black veil of a scales sRGB by (1 - a).
    if (bright <= 0.18) return 0;
    return (1 - math.pow(0.18 / bright, 1 / 2.2)).clamp(0.0, 0.6).toDouble();
  }

  // Each view holds its own handle, so a newer cover replacing [_last] never pulls one out from under it.
  void _show(ui.Image image) {
    _image?.dispose();
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() => _image = image);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    return LayoutBuilder(
      builder: (context, box) {
        if (t != null && box.maxWidth.isFinite && box.maxHeight.isFinite && box.maxWidth > 0 && box.maxHeight > 0) {
          _want(t, box.biggest);
        }
        final image = _image;
        if (image == null) return ColoredBox(color: widget.fade ?? AppColors.of(context).hover);
        final fade = widget.fade;
        final clear = fade?.withValues(alpha: 0);
        return Stack(
          fit: StackFit.expand,
          children: [
            // Its own layer: the page above changes often, this picture never does.
            RepaintBoundary(
              child: RawImage(
                image: image,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            // The ends that meet the page are plain gradients over it, so they always match the page's colour as it
            // changes (a new song's palette), with no new bake.
            if (fade != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [clear!, fade],
                    stops: const [0.78, 1],
                  ),
                ),
              ),
            if (fade != null && widget.fadeSide)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [clear!, fade], stops: const [0.7, 1]),
                ),
              ),
          ],
        );
      },
    );
  }
}
