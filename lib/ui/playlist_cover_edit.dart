import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:image/image.dart' as img;

import '../models/track.dart';
import '../services/metadata.dart';
import 'widgets/app_dialog.dart';

import '../services/language.dart';
import '../services/playlist_covers.dart';
import 'widgets/controls.dart';
import 'widgets/menus.dart';

/// Picks a picture for [key]'s playlist (or Liked music) and keeps a copy in the app's own folder.
Future<void> choosePlaylistCover(BuildContext context, String key, String name) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final picked = (await FilePicker.pickFiles(type: FileType.image, dialogTitle: tr.chooseCoverArt)).firstOrNull;
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!context.mounted) return;
    final cropped = await previewCover(context, bytes);
    if (cropped == null) return;
    await PlaylistCovers.instance.setCover(key, cropped);
    messenger.showSnackBar(SnackBar(content: Text(tr.playlistCoverUpdated)));
  } catch (e) {
    debugPrint('Playlist cover not saved for $name: $e');
    messenger.showSnackBar(SnackBar(content: Text(tr.couldntUsePicture)));
  }
}

typedef _CoverPreview = ({Uint8List bytes, int width, int height});

img.Image _decodePhoto(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) throw const FormatException('Invalid cover photo');
  return img.bakeOrientation(image);
}

_CoverPreview _prepareCover(Uint8List bytes) {
  final photo = _decodePhoto(bytes);
  final image = math.max(photo.width, photo.height) > 1600
      ? img.copyResize(
          photo,
          width: photo.width >= photo.height ? 1600 : null,
          height: photo.height > photo.width ? 1600 : null,
        )
      : photo;
  return (bytes: img.encodeJpg(image, quality: 92), width: photo.width, height: photo.height);
}

/// The crop center in source coordinates after rotation and flipping.
typedef CoverCrop = ({double zoom, Offset center, int turns, bool flipped});

@visibleForTesting
Uint8List exportPlaylistCover((Uint8List, CoverCrop) input) {
  final (bytes, crop) = input;
  var image = _decodePhoto(bytes);
  if (crop.turns != 0) image = img.copyRotate(image, angle: crop.turns * 90);
  if (crop.flipped) image = img.copyFlip(image, direction: img.FlipDirection.horizontal);
  final shortest = math.min(image.width, image.height);
  final side = (shortest / crop.zoom).round().clamp(1, shortest).toInt();
  final cropped = img.copyCrop(
    image,
    x: (crop.center.dx * image.width - side / 2).round().clamp(0, image.width - side).toInt(),
    y: (crop.center.dy * image.height - side / 2).round().clamp(0, image.height - side).toInt(),
    width: side,
    height: side,
  );
  return img.encodeJpg(img.copyResize(cropped, width: 900, interpolation: img.Interpolation.average), quality: 92);
}

Future<Uint8List?> previewCover(BuildContext context, Uint8List bytes) async {
  final photo = await compute(_prepareCover, bytes);
  if (!context.mounted) return null;
  return showDialog<Uint8List>(
    context: context,
    builder: (_) => _CoverEditor(photo: photo, original: bytes),
  );
}

class _CoverEditor extends StatefulWidget {
  const _CoverEditor({required this.photo, required this.original});

  final _CoverPreview photo;
  final Uint8List original;

  @override
  State<_CoverEditor> createState() => _CoverEditorState();
}

class _CoverEditorState extends State<_CoverEditor> {
  static const _maxZoom = 5.0;
  static const _middle = Offset(0.5, 0.5);
  CoverCrop _crop = (zoom: 1, center: _middle, turns: 0, flipped: false);
  CoverCrop? _gestureStart;
  Offset _focalStart = Offset.zero;
  bool _saving = false;

  Size _imageSize(CoverCrop crop) => crop.turns.isOdd
      ? Size(widget.photo.height.toDouble(), widget.photo.width.toDouble())
      : Size(widget.photo.width.toDouble(), widget.photo.height.toDouble());

  Size _frameImage(CoverCrop crop, double side) {
    final image = _imageSize(crop);
    return image * (side * crop.zoom / image.shortestSide);
  }

  void _setCrop(CoverCrop crop) {
    final box = _frameImage(crop, 1);
    final x = math.min(0.5, 0.5 / box.width);
    final y = math.min(0.5, 0.5 / box.height);
    final center = Offset(crop.center.dx.clamp(x, 1 - x), crop.center.dy.clamp(y, 1 - y));
    setState(() => _crop = (zoom: crop.zoom, center: center, turns: crop.turns, flipped: crop.flipped));
  }

  void _zoom(double value) =>
      _setCrop((zoom: value.clamp(1, _maxZoom), center: _crop.center, turns: _crop.turns, flipped: _crop.flipped));

  void _rotate() => _setCrop((
    zoom: _crop.zoom,
    center: Offset(1 - _crop.center.dy, _crop.center.dx),
    turns: (_crop.turns + (_crop.flipped ? 3 : 1)) % 4,
    flipped: _crop.flipped,
  ));

  void _flip() => _setCrop((
    zoom: _crop.zoom,
    center: Offset(1 - _crop.center.dx, _crop.center.dy),
    turns: _crop.turns,
    flipped: !_crop.flipped,
  ));

  void _scale(ScaleUpdateDetails details, double side) {
    final start = _gestureStart!;
    final oldSize = _frameImage(start, side);
    final zoom = (start.zoom * details.scale).clamp(1.0, _maxZoom);
    final nextSize = oldSize * (zoom / start.zoom);
    final middle = Offset(side / 2, side / 2);
    final first = _focalStart - middle;
    final current = details.localFocalPoint - middle;
    _setCrop((
      zoom: zoom,
      center:
          start.center +
          Offset(
            first.dx / oldSize.width - current.dx / nextSize.width,
            first.dy / oldSize.height - current.dy / nextSize.height,
          ),
      turns: start.turns,
      flipped: start.flipped,
    ));
  }

  Widget _photo(double side, {bool grid = false}) {
    final box = _frameImage(_crop, side);
    return ClipRect(
      child: SizedBox.square(
        dimension: side,
        child: Stack(
          children: [
            Positioned(
              width: box.width,
              height: box.height,
              left: side / 2 - box.width * _crop.center.dx,
              top: side / 2 - box.height * _crop.center.dy,
              child: Transform.flip(
                flipX: _crop.flipped,
                child: RotatedBox(
                  quarterTurns: _crop.turns,
                  child: Image.memory(widget.photo.bytes, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
                ),
              ),
            ),
            if (grid)
              const Positioned.fill(
                child: IgnorePointer(child: CustomPaint(painter: _CropGrid())),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final bytes = await compute(exportPlaylistCover, (widget.original, _crop));
      if (mounted) Navigator.pop(context, bytes);
    } catch (error) {
      debugPrint('Playlist crop export failed: $error');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.couldntUsePicture)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final side = math.min(420.0, math.min(media.width - 80, media.height * 0.48)).clamp(120.0, 420.0);
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_saving,
      child: AppDialog(
        title: tr.changeCover,
        // The crop square and the dialog's own 24 px sides.
        width: side + 48,
        content: SizedBox(
          width: side,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Listener(
                    onPointerSignal: _saving
                        ? null
                        : (event) {
                            if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
                              GestureBinding.instance.pointerSignalResolver.register(event, (_) {
                                _zoom(_crop.zoom * math.exp(-event.scrollDelta.dy / 360));
                              });
                            }
                          },
                    child: GestureDetector(
                      onScaleStart: _saving
                          ? null
                          : (details) {
                              _gestureStart = _crop;
                              _focalStart = details.localFocalPoint;
                            },
                      onScaleUpdate: _saving ? null : (details) => _scale(details, side),
                      onDoubleTap: _saving ? null : () => _zoom(_crop.zoom == 1 ? 2 : 1),
                      child: _photo(side, grid: true),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton(
                    tooltip: tr.coverZoomOut,
                    onPressed: _saving || _crop.zoom == 1 ? null : () => _zoom(_crop.zoom - 0.25),
                    icon: const Icon(Icons.zoom_out_rounded),
                  ),
                  Expanded(
                    child: Slider(
                      value: _crop.zoom,
                      min: 1,
                      max: _maxZoom,
                      semanticFormatterCallback: (value) => '${(value * 100).round()}%',
                      onChanged: _saving ? null : _zoom,
                    ),
                  ),
                  IconButton(
                    tooltip: tr.coverZoomIn,
                    onPressed: _saving || _crop.zoom == _maxZoom ? null : () => _zoom(_crop.zoom + 0.25),
                    icon: const Icon(Icons.zoom_in_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Tooltip(
                    message: tr.coverPreview,
                    child: ClipRRect(borderRadius: BorderRadius.circular(8), child: _photo(44)),
                  ),
                  Flexible(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 2,
                      children: [
                        IconButton.filledTonal(
                          tooltip: tr.coverRotate,
                          onPressed: _saving ? null : _rotate,
                          icon: const Icon(Icons.rotate_right_rounded),
                        ),
                        IconButton.filledTonal(
                          tooltip: tr.coverFlip,
                          onPressed: _saving ? null : _flip,
                          icon: const Icon(Icons.flip_rounded),
                        ),
                        IconButton.filledTonal(
                          tooltip: tr.coverReset,
                          onPressed: _saving
                              ? null
                              : () => _setCrop((zoom: 1, center: _middle, turns: 0, flipped: false)),
                          icon: const Icon(Icons.restart_alt_rounded),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                tr.coverGestureHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: Text(tr.cancel)),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(tr.save),
          ),
        ],
      ),
    );
  }
}

class _CropGrid extends CustomPainter {
  const _CropGrid();

  @override
  void paint(Canvas canvas, Size size) {
    final shadow = Paint()
      ..color = Colors.black45
      ..strokeWidth = 2;
    final highlight = Paint()
      ..color = Colors.white70
      ..strokeWidth = 1;
    for (final fraction in [1 / 3, 2 / 3]) {
      final x = size.width * fraction;
      final y = size.height * fraction;
      for (final paint in [shadow, highlight]) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_CropGrid oldDelegate) => false;
}

Uint8List _collage(List<Uint8List> parts) {
  final image = img.Image(width: 900, height: 900);
  for (var i = 0; i < 4; i++) {
    final part = img.decodeImage(parts[i]);
    if (part == null) throw const FormatException();
    img.compositeImage(
      image,
      img.copyResizeCropSquare(img.bakeOrientation(part), size: 450),
      dstX: i % 2 * 450,
      dstY: i ~/ 2 * 450,
    );
  }
  return img.encodeJpg(image, quality: 92);
}

Future<void> collageCover(BuildContext context, String key, List<Track> tracks) async {
  try {
    final picks = await showDialog<List<Track>>(
      context: context,
      builder: (_) => _CollagePicker(tracks: tracks),
    );
    if (picks == null || !context.mounted) return;
    final parts = <Uint8List>[];
    for (final track in picks) {
      final art = await Metadata.artwork(track);
      if (art == null) throw const FormatException();
      parts.add(art);
    }
    if (!context.mounted) return;
    final bytes = await compute(_collage, parts);
    if (!context.mounted) return;
    final confirmed = await previewCover(context, bytes);
    if (confirmed == null) return;
    await PlaylistCovers.instance.setCover(key, confirmed);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.playlistCoverUpdated)));
    }
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.couldntUsePicture)));
  }
}

class _CollagePicker extends StatefulWidget {
  const _CollagePicker({required this.tracks});

  final List<Track> tracks;

  @override
  State<_CollagePicker> createState() => _CollagePickerState();
}

class _CollagePickerState extends State<_CollagePicker> {
  late final _tracks = {for (final track in widget.tracks) track.id: track}.values.toList();
  final _selected = <Track>[];
  String _query = '';

  void _toggle(Track track) => setState(() {
    if (!_selected.remove(track) && _selected.length < 4) _selected.add(track);
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final matches = _query.isEmpty
        ? _tracks
        : _tracks.where((track) => '${track.title} ${track.artist}'.toLowerCase().contains(_query)).toList();
    return AppDialog(
      title: tr.coverCollage,
      width: DialogWidth.wide,
      scrollable: false,
      content: SizedBox(
        height: 440,
        child: LayoutBuilder(
          builder: (context, bounds) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (bounds.maxHeight >= 235)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Column(
                          children: [
                            for (var row = 0; row < 2; row++)
                              Row(
                                children: [
                                  for (var i = row * 2; i < row * 2 + 2; i++)
                                    if (i < _selected.length)
                                      Tooltip(
                                        message: '${tr.unselect} · ${_selected[i].title}',
                                        child: InkWell(
                                          onTap: () => _toggle(_selected[i]),
                                          child: Artwork(track: _selected[i], size: 36, radius: 0),
                                        ),
                                      )
                                    else
                                      SizedBox.square(
                                        dimension: 36,
                                        child: ColoredBox(
                                          color: colors.surfaceContainerHighest,
                                          child: Icon(Icons.image_outlined, size: 16, color: colors.onSurfaceVariant),
                                        ),
                                      ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Text('${tr.selectedCount(_selected.length)} / 4')),
                    ],
                  ),
                ),
              TextField(
                decoration: InputDecoration(
                  hintText: tr.navSearch,
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final track = matches[index];
                    final checked = _selected.contains(track);
                    return ListTile(
                      leading: Artwork(track: track, size: 40),
                      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                      selected: checked,
                      trailing: Icon(checked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded),
                      onTap: checked || _selected.length < 4 ? () => _toggle(track) : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.cancel)),
        FilledButton(
          onPressed: _selected.length == 4 ? () => Navigator.pop(context, _selected.toList()) : null,
          child: Text(tr.settingsPreview),
        ),
      ],
    );
  }
}

/// Drops the picture chosen for [key], bringing back the automatic cover.
Future<void> removePlaylistCover(BuildContext context, String key) async {
  final messenger = ScaffoldMessenger.of(context);
  await PlaylistCovers.instance.removeCover(key);
  messenger.showSnackBar(SnackBar(content: Text(tr.playlistCoverRemoved)));
}

/// "Change cover" / "Remove cover" for a playlist or Liked music, beside the page's other buttons.
class PlaylistCoverMenu extends StatelessWidget {
  const PlaylistCoverMenu({super.key, required this.coverKey, required this.name, this.tracks = const []});
  final List<Track> tracks;

  final String coverKey;

  /// The playlist's name, for the error message if its picture can't be read.
  final String name;

  @override
  Widget build(BuildContext context) {
    final has = PlaylistCovers.instance.has(coverKey);
    return PopupMenuButton<VoidCallback>(
      // Over the whole window, so a click anywhere (sidebar included) closes it.
      useRootNavigator: true,
      tooltip: tr.playlistCover,
      icon: const Icon(Icons.edit_outlined),
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: () => choosePlaylistCover(context, coverKey, name),
          child: MenuRow(leading: const Icon(Icons.add_photo_alternate_outlined), title: Text(tr.changeCover)),
        ),
        if (tracks.length >= 4)
          PopupMenuItem(
            value: () => collageCover(context, coverKey, tracks),
            child: MenuRow(leading: const Icon(Icons.grid_view), title: Text(tr.coverCollage)),
          ),
        if (has)
          PopupMenuItem(
            value: () => removePlaylistCover(context, coverKey),
            child: MenuRow(leading: const Icon(Icons.hide_image_outlined), title: Text(tr.removeCover)),
          ),
      ],
    );
  }
}

/// [fallback] (a mosaic, or a song's cover), replaced by the picture chosen for [coverKey] when there is one.
class PlaylistArtwork extends StatelessWidget {
  const PlaylistArtwork({
    super.key,
    required this.coverKey,
    required this.fallback,
    this.size,
    this.radius = 4,
    this.circle = false,
  });

  final String? coverKey;
  final Widget fallback;
  final double? size;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final own = PlaylistCovers.instance.coverOf(coverKey);
    if (own == null) return fallback;
    return Artwork(track: own, size: size, radius: radius, circle: circle);
  }
}
