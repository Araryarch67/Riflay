import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/language.dart';
import '../../services/subject_cutout.dart';
import '../card_export.dart';
import '../player_scope.dart';
import '../widgets/app_logo.dart';
import '../widgets/controls.dart' show Artwork;
import '../widgets/faded_cover.dart';
import 'photo_grade.dart';
import 'poster_draft.dart';
import 'poster_card.dart';
import 'poster_presets.dart';

/// Opens the poster editor with [songs] on it; [pool] (a playlist's songs, say) comes first when adding more.
Future<void> showPosterEditor(BuildContext context, {List<Track> songs = const [], List<Track> pool = const []}) {
  final c = PlayerScope.read(context);
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => PlayerScope(
        controller: c,
        child: PosterEditor(songs: songs, pool: pool),
      ),
    ),
  );
}

/// One song card on the poster: where its centre is (0–1 of the poster), its size, how it is turned in space
/// (radians: [pitch] about the across axis, [yaw] about the up axis, [tilt] in the poster's plane), how far along
/// its progress bar is and its look.
class PosterItem {
  PosterItem(
    this.track, {
    required this.at,
    this.scale = 1,
    this.tilt = 0,
    this.pitch = 0,
    this.yaw = 0,
    this.progress = 0.4,
    this.style = PosterCardStyle.light,
  });

  final Track track;
  Offset at;
  double scale;
  double tilt;
  double pitch;
  double yaw;
  double progress;
  PosterCardStyle style;

  /// Shown on the poster, and how see-through (Layers).
  bool visible = true;
  double opacity = 1;

  /// How thick the card is in 3D (0: a flat sheet), before it is sized.
  double depth = 4;

  /// Locked: nothing on the poster moves, sizes or turns it, and taps go through to what is under it.
  bool locked = false;

  PosterItem copy() =>
      PosterItem(track, at: at, scale: scale, tilt: tilt, pitch: pitch, yaw: yaw, progress: progress, style: style)
        ..visible = visible
        ..opacity = opacity
        ..depth = depth
        ..locked = locked;

  Map<String, dynamic> toJson() => {
    'track': track.toJson(),
    'x': at.dx,
    'y': at.dy,
    'scale': scale,
    'tilt': tilt,
    'pitch': pitch,
    'yaw': yaw,
    'progress': progress,
    'style': style.name,
    'visible': visible,
    'opacity': opacity,
    'depth': depth,
    'locked': locked,
  };

  static PosterItem fromJson(Map<String, dynamic> j) {
    double n(String k, double d) => (j[k] as num?)?.toDouble() ?? d;
    return PosterItem(
        Track.fromJson((j['track'] as Map).cast<String, dynamic>()),
        at: Offset(n('x', 0.5), n('y', 0.5)),
        scale: n('scale', 1),
        tilt: n('tilt', 0),
        pitch: n('pitch', 0),
        yaw: n('yaw', 0),
        progress: n('progress', 0.4),
        style: PosterCardStyle.values.asNameMap()[j['style']] ?? PosterCardStyle.light,
      )
      ..visible = j['visible'] != false
      ..opacity = n('opacity', 1)
      ..depth = n('depth', 4)
      ..locked = j['locked'] == true;
  }

  /// The card as drawn: seen in perspective, turned about its three axes, then sized.
  Matrix4 transform(double unit) => Matrix4.identity()
    ..setEntry(3, 2, 0.0022)
    ..rotateX(pitch)
    ..rotateY(yaw)
    ..rotateZ(tilt)
    ..scaleByDouble(scale * unit, scale * unit, 1, 1);
}

/// The person cut out of the photo, as a layer: cards above it stand in front of them, cards below behind.
class PosterPerson {
  const PosterPerson._();
  static const layer = PosterPerson._();
}

/// The photo, as what can be selected (it is always the bottom layer).
class PosterPhoto {
  const PosterPhoto._();
  static const layer = PosterPhoto._();
}

/// A poster's shape: how wide it is to how tall, and how many pixels wide it is saved.
enum PosterShape {
  story(9 / 16, 1080),
  portrait(4 / 5, 1080),
  square(1, 1080),
  landscape(16 / 9, 1920);

  const PosterShape(this.ratio, this.pixelsWide);
  final double ratio;
  final int pixelsWide;

  String get label => switch (this) {
    story => tr.posterShapeStory,
    portrait => tr.posterShapePortrait,
    square => tr.posterShapeSquare,
    landscape => tr.posterShapeLandscape,
  };

  /// "9:16 · 1080 × 1920": its proportions and the size it is saved at.
  String get detail {
    final ratio = switch (this) {
      story => '9:16',
      portrait => '4:5',
      square => '1:1',
      landscape => '16:9',
    };
    return '$ratio · $pixelsWide × ${(pixelsWide / this.ratio).round()}';
  }

  IconData get icon => switch (this) {
    story => Icons.crop_portrait_rounded,
    portrait => Icons.crop_5_4_rounded,
    square => Icons.crop_square_rounded,
    landscape => Icons.crop_landscape_rounded,
  };
}

/// A poster (Story-sized by default, or another [PosterShape]), made of layers like a picture editor: the photo at
/// the bottom, song cards, and the person cut out of the photo (on the device) among them, so cards can stand behind
/// or in front of them. Made step by step from the tabs under it (photo, songs, layout, layers, canvas); a card tapped
/// on the poster gets its own few controls.
class PosterEditor extends StatefulWidget {
  const PosterEditor({super.key, this.songs = const [], this.pool = const []});

  final List<Track> songs;

  /// Where the songs to add are found first: the playlist or mix it was opened from.
  final List<Track> pool;

  /// The most cards a poster takes.
  static const maxCards = 8;

  @override
  State<PosterEditor> createState() => _PosterEditorState();
}

/// One setting under the adjust pills: what it is, its value, range and neutral (where it shows 0), and how it
/// changes.
class _Knob {
  const _Knob(this.icon, this.label, this.value, this.min, this.max, this.set, {double? neutral})
    : neutral = neutral ?? min;

  final IconData icon;
  final String label;
  final double value, min, max, neutral;
  final ValueChanged<double> set;

  /// The value as shown: 0 at neutral, up to ±100 at the ends.
  int get shown => neutral <= min
      ? ((value - min) / (max - min) * 100).round()
      : value >= neutral
      ? ((value - neutral) / (max - neutral) * 100).round()
      : -((neutral - value) / (neutral - min) * 100).round();
}

/// The steps a poster is made in, one tab each.
enum _Step { photo, songs, layout, layers, canvas }

class _PosterEditorState extends State<PosterEditor> {
  final _poster = GlobalKey();

  /// Bottom to top, over the photo: the cards and [PosterPerson.layer].
  final _layers = <Object>[PosterPerson.layer];
  Object? _selected;
  Uint8List? _photo, _cutout;

  /// The photo's place: moved by a part of the poster, zoomed from its centre. The cut-out follows it exactly.
  Offset _photoAt = Offset.zero;
  double _photoZoom = 1;
  bool _cutting = false;
  PosterShape _shape = PosterShape.story;

  /// Shown or hidden, and how see-through, per layer (cards keep theirs).
  bool _photoShown = true, _personShown = true;
  double _photoOpacity = 1, _personOpacity = 1;

  /// The photo locked: a drag on the poster no longer moves or zooms it (nor the cut-out with it).
  bool _photoLocked = false;

  /// The photo's colours; the cut-out takes the same, so the person matches the photo they came from.
  PhotoGrade _grade = PhotoGrade.original;
  PhotoFilter? _filter = PhotoFilter.original;

  /// The look a new card gets: the last one picked.
  PosterCardStyle _style = PosterCardStyle.light;
  PosterPreset _preset = PosterPreset.scatter;

  /// "Riflay" at the foot of the poster; off on request.
  bool _watermark = true;
  _Step _step = _Step.photo;

  /// The poster's zoom while editing (pinch or drag an empty spot); a saved poster is never zoomed.
  final _view = TransformationController();

  /// The poster's middle lines, shown while a card being dragged sits on them.
  bool _guideX = false, _guideY = false;

  /// How far a finger has gone on a card before the card follows: a touch or a slip doesn't move it.
  double _slop = 0;
  static const _deadZone = 6.0;

  /// The last poster, kept on the device: offered when the editor opens, saved as this one changes (not before the
  /// person has said whether to go on with the last one).
  ({Map<String, dynamic> state, Uint8List? photo, Uint8List? cutout})? _draft;
  bool _draftChecked = false;
  Timer? _autosave;
  String? _savedState;

  Map<String, dynamic> _state() => {
    'layers': [
      for (final l in _layers) l is PosterItem ? l.toJson() : {'person': true},
    ],
    'photoX': _photoAt.dx,
    'photoY': _photoAt.dy,
    'photoZoom': _photoZoom,
    'photoShown': _photoShown,
    'photoLocked': _photoLocked,
    'personShown': _personShown,
    'photoOpacity': _photoOpacity,
    'personOpacity': _personOpacity,
    'grade': [_grade.brightness, _grade.contrast, _grade.saturation, _grade.warmth, _grade.fade, _grade.vignette],
    'filter': _filter?.name,
    'shape': _shape.name,
    'watermark': _watermark,
    'preset': _preset.name,
  };

  void _load(Map<String, dynamic> j, Uint8List? photo, Uint8List? cutout) {
    double n(String k, double d) => (j[k] as num?)?.toDouble() ?? d;
    _layers
      ..clear()
      ..addAll([
        for (final l in (j['layers'] as List? ?? const []).cast<Map>())
          l['person'] == true ? PosterPerson.layer : PosterItem.fromJson(l.cast<String, dynamic>()),
      ]);
    if (!_layers.contains(PosterPerson.layer)) _layers.add(PosterPerson.layer);
    _photo = photo;
    _cutout = cutout;
    _photoAt = Offset(n('photoX', 0), n('photoY', 0));
    _photoZoom = n('photoZoom', 1);
    _photoShown = j['photoShown'] != false;
    _photoLocked = j['photoLocked'] == true;
    _personShown = j['personShown'] != false;
    _photoOpacity = n('photoOpacity', 1);
    _personOpacity = n('personOpacity', 1);
    final g = (j['grade'] as List? ?? const []).cast<num>();
    if (g.length == 6) {
      _grade = PhotoGrade(
        brightness: g[0].toDouble(),
        contrast: g[1].toDouble(),
        saturation: g[2].toDouble(),
        warmth: g[3].toDouble(),
        fade: g[4].toDouble(),
        vignette: g[5].toDouble(),
      );
    }
    _filter = PhotoFilter.values.asNameMap()[j['filter']];
    _shape = PosterShape.values.asNameMap()[j['shape']] ?? PosterShape.story;
    _watermark = j['watermark'] != false;
    _preset = PosterPreset.values.asNameMap()[j['preset']] ?? PosterPreset.scatter;
    _selected = null;
    _undo.clear();
    _redo.clear();
  }

  Future<void> _checkDraft() async {
    final draft = await PosterDraft.load();
    if (!mounted) return;
    final layers = draft?.state['layers'] as List?;
    setState(() {
      _draft = layers != null && layers.length > 1 ? draft : null;
      _draftChecked = true;
    });
  }

  /// The banner's answer: go on with the last poster, or start this one (the last is then let go).
  void _answerDraft({required bool resume}) {
    final draft = _draft;
    setState(() {
      _draft = null;
      if (resume && draft != null) _load(draft.state, draft.photo, draft.cutout);
    });
    if (!resume) unawaited(PosterDraft.clear());
  }

  /// A moment after the poster stops changing, it is kept.
  void _saveSoon() {
    if (!_draftChecked || _draft != null) return;
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 900), _saveNow);
  }

  Future<void> _saveNow() async {
    _autosave?.cancel();
    if (_items.isEmpty && _photo == null) return;
    final state = _state();
    final text = jsonEncode(state);
    if (text == _savedState) return;
    _savedState = text;
    await PosterDraft.save(state, photo: _photo, cutout: _cutout);
  }

  /// Leaving with something on the poster: said that it is kept, and asked.
  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.posterLeaveTitle),
        content: Text(tr.posterLeaveBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr.posterKeepEditing)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(tr.posterLeave)),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    await _saveNow();
    if (mounted) Navigator.of(context).pop();
  }

  /// Undo and Redo: the poster as it was before each change (cards copied), newest last.
  final _undo = <_Snapshot>[], _redo = <_Snapshot>[];
  static const _historySize = 50;

  /// Taken when a drag starts, kept only once it really moves: a tap leaves nothing to undo.
  _Snapshot? _pending;

  _Snapshot _snapshot() => _Snapshot(
    layers: [for (final l in _layers) l is PosterItem ? l.copy() : l],
    photo: _photo,
    cutout: _cutout,
    photoAt: _photoAt,
    photoZoom: _photoZoom,
    photoShown: _photoShown,
    photoLocked: _photoLocked,
    personShown: _personShown,
    photoOpacity: _photoOpacity,
    personOpacity: _personOpacity,
    grade: _grade,
    filter: _filter,
    shape: _shape,
    watermark: _watermark,
    preset: _preset,
  );

  void _restore(_Snapshot s) {
    _layers
      ..clear()
      ..addAll(s.layers);
    _photo = s.photo;
    _cutout = s.cutout;
    _photoAt = s.photoAt;
    _photoZoom = s.photoZoom;
    _photoShown = s.photoShown;
    _photoLocked = s.photoLocked;
    _personShown = s.personShown;
    _photoOpacity = s.photoOpacity;
    _personOpacity = s.personOpacity;
    _grade = s.grade;
    _filter = s.filter;
    _shape = s.shape;
    _watermark = s.watermark;
    _preset = s.preset;
    _selected = null;
  }

  /// Before a change: the poster as it is now goes on the undo list.
  void _remember([_Snapshot? before]) {
    if (_draft != null) _answerDraft(resume: false);
    _undo.add(before ?? _snapshot());
    if (_undo.length > _historySize) _undo.removeAt(0);
    _redo.clear();
  }

  void _undoLast() => setState(() {
    if (_undo.isEmpty) return;
    _redo.add(_snapshot());
    _restore(_undo.removeLast());
  });

  void _redoLast() => setState(() {
    if (_redo.isEmpty) return;
    _undo.add(_snapshot());
    _restore(_redo.removeLast());
  });

  /// The setting picked under the photo's and the card's adjust pills.
  int _photoKnob = 0, _cardKnob = 0;

  /// The setting being slid and its value, shown on the poster while the finger is on the slider.
  String? _live;

  /// A card snaps to the middle when this near (part of the poster), and to upright when this near (radians).
  static const _snapAt = 0.015, _snapTurn = 0.07;

  @override
  void dispose() {
    if (_autosave?.isActive ?? false) unawaited(_saveNow());
    _autosave?.cancel();
    _view.dispose();
    super.dispose();
  }

  final _random = math.Random();

  Iterable<PosterItem> get _items => _layers.whereType<PosterItem>();

  @override
  void initState() {
    super.initState();
    for (final t in widget.songs.take(PosterEditor.maxCards)) {
      _layers.insert(
        _layers.length - 1,
        PosterItem(t, at: const Offset(0.5, 0.5), progress: 0.2 + _random.nextDouble() * 0.6),
      );
    }
    _apply(PosterPreset.scatter);
    unawaited(_checkDraft());
  }

  /// Every card placed as [preset] has it (and given its look, when it suggests one).
  void _apply(PosterPreset preset) {
    _preset = preset;
    final items = _items.toList();
    for (final (i, pose) in preset.layout(items.length).indexed) {
      items[i]
        ..at = pose.at
        ..scale = pose.scale
        ..tilt = pose.tilt
        ..pitch = pose.pitch
        ..yaw = pose.yaw;
      if (preset.style case final style?) items[i].style = style;
    }
    if (preset.style case final style?) _style = style;
  }

  Future<void> _pickPhoto() async {
    final file = (await FilePicker.pickFiles(type: FileType.image, dialogTitle: tr.choosePhoto)).firstOrNull;
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    _remember();
    setState(() {
      _photo = bytes;
      _cutout = null;
      _photoAt = Offset.zero;
      _photoZoom = 1;
      _photoShown = _personShown = true;
      _cutting = true;
    });
    Uint8List? cut;
    try {
      cut = await SubjectCutout.cutout(bytes);
    } catch (e) {
      debugPrint('Poster: no cutout: $e');
    }
    if (!mounted || !identical(_photo, bytes)) return;
    setState(() {
      _cutout = cut;
      _cutting = false;
    });
    if (cut == null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.posterNoCutout)));
  }

  Future<void> _addSong() async {
    final c = PlayerScope.read(context);
    final seen = <String>{};
    final songs = [
      for (final t in [...widget.pool, ?c.currentTrack, ...c.recentlyPlayed, ...c.library])
        if (seen.add(t.id)) t,
    ];
    final picked = await showModalBottomSheet<Track>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, scroll) => ListView.builder(
          controller: scroll,
          itemCount: songs.length,
          itemBuilder: (context, i) => ListTile(
            leading: Artwork(track: songs[i], size: 44, radius: 8),
            title: Text(songs[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(songs[i].artist, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => Navigator.of(context).pop(songs[i]),
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      // Where the chosen preset puts one more card.
      final pose = _preset.layout(_items.length + 1).last;
      final item = PosterItem(
        picked,
        at: pose.at,
        scale: pose.scale,
        tilt: pose.tilt,
        pitch: pose.pitch,
        yaw: pose.yaw,
        progress: 0.2 + _random.nextDouble() * 0.6,
        style: _style,
      );
      // Under the person, like the others.
      _remember();
      _layers.insert(_layers.indexOf(PosterPerson.layer), item);
    });
  }

  /// [layer] one step up (+1) or down (−1) among the layers.
  void _move(Object layer, int by) => setState(() {
    _remember();
    final i = _layers.indexOf(layer);
    final to = (i + by).clamp(0, _layers.length - 1);
    _layers
      ..removeAt(i)
      ..insert(to, layer);
  });

  void _duplicate(PosterItem item) => setState(() {
    _remember();
    final copy =
        PosterItem(
            item.track,
            at: Offset((item.at.dx + 0.06).clamp(0.0, 1.0), (item.at.dy + 0.04).clamp(0.0, 1.0)),
            scale: item.scale,
            tilt: item.tilt,
            pitch: item.pitch,
            yaw: item.yaw,
            progress: item.progress,
            style: item.style,
          )
          ..opacity = item.opacity
          ..depth = item.depth;
    _layers.insert(_layers.indexOf(item) + 1, copy);
    _selected = copy;
  });

  void _remove(Object layer) => setState(() {
    _remember();
    if (layer is PosterItem) _layers.remove(layer);
    if (layer is PosterPhoto) _photo = _cutout = null;
    _selected = null;
  });

  String get _fileName => 'Riflay Poster ${DateTime.now().millisecondsSinceEpoch}.png';

  /// The poster at its shape's width in pixels, nothing selected on it.
  Future<Uint8List> _render() async {
    if (_selected != null) {
      setState(() => _selected = null);
      await WidgetsBinding.instance.endOfFrame;
    }
    final width = _poster.currentContext?.size?.width ?? 360;
    return renderCard(_poster, pixelRatio: _shape.pixelsWide / width);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = _selected is PosterItem ? _selected as PosterItem : null;
    _saveSoon();
    final hasWork = _items.isNotEmpty || _photo != null;
    return PopScope(
      canPop: !hasWork,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr.poster),
          actions: [
            IconButton(
              tooltip: tr.undo,
              onPressed: _undo.isEmpty ? null : _undoLast,
              icon: const Icon(Icons.undo_rounded),
            ),
            IconButton(
              tooltip: tr.redo,
              onPressed: _redo.isEmpty ? null : _redoLast,
              icon: const Icon(Icons.redo_rounded),
            ),
            IconButton(
              tooltip: tr.save,
              onPressed: _items.isEmpty ? null : () => saveCard(context, _render, _fileName),
              icon: const Icon(Icons.download_rounded),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              // An icon, filled: a label pushed the title off a phone's bar.
              child: IconButton.filled(
                tooltip: tr.share,
                onPressed: _items.isEmpty
                    ? null
                    : () => shareCard(context, _render, _fileName, caption: tr.posterCaption, subject: 'Riflay'),
                icon: const Icon(Icons.ios_share_rounded),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_draft != null)
                MaterialBanner(
                  leading: const Icon(Icons.restore_rounded),
                  content: Text(tr.posterResume),
                  actions: [
                    TextButton(onPressed: () => _answerDraft(resume: false), child: Text(tr.posterStartNew)),
                    FilledButton(onPressed: () => _answerDraft(resume: true), child: Text(tr.posterContinue)),
                  ],
                ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Stack(
                      children: [
                        InteractiveViewer(
                          transformationController: _view,
                          minScale: 1,
                          maxScale: 5,
                          // A drag on an empty spot pans the zoomed poster, unless the photo is being moved.
                          panEnabled: !_movingPhoto,
                          scaleEnabled: !_movingPhoto,
                          child: Center(
                            child: AspectRatio(aspectRatio: _shape.ratio, child: _canvas(scheme)),
                          ),
                        ),
                        if (_live != null)
                          Positioned(left: 0, right: 0, bottom: 16, child: Center(child: _liveLabel(_live!))),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: ListenableBuilder(
                            listenable: _view,
                            builder: (context, _) => _view.value.getMaxScaleOnAxis() <= 1.01
                                ? const SizedBox.shrink()
                                : FilledButton.tonalIcon(
                                    onPressed: () => _view.value = Matrix4.identity(),
                                    icon: const Icon(Icons.fit_screen_rounded),
                                    label: Text(tr.posterFit),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // A steady height: the poster doesn't jump as panels change.
              SizedBox(
                height: 248,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: card != null ? _cardControls(card) : _stepPanel(),
                ),
              ),
              if (card == null) _stepTabs(),
            ],
          ),
        ),
      ),
    );
  }

  // The poster ---------------------------------------------------------------------------------------------------

  /// A drag on the poster's empty part moves the photo: on the Photo step, or with the photo picked in Layers.
  bool get _movingPhoto =>
      _photo != null && !_photoLocked && (_selected is PosterPhoto || (_selected == null && _step == _Step.photo));

  Widget _canvas(ColorScheme scheme) => LayoutBuilder(
    builder: (context, box) {
      final size = box.biggest;
      // Cards are drawn at a phone's width (390) and scaled with the poster's shorter side, so a saved poster looks
      // as edited and a wide one doesn't blow them up.
      final unit = math.min(size.width, size.height * 9 / 16) / 390;
      var startZoom = _photoZoom;
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: RepaintBoundary(
          key: _poster,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The empty poster and the photo: a tap clears the pick; a drag moves the photo, a pinch zooms it.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _selected = null),
                onScaleStart: (_) {
                  startZoom = _photoZoom;
                  _pending = _movingPhoto ? _snapshot() : null;
                },
                onScaleUpdate: !_movingPhoto
                    ? null
                    : (d) => setState(() {
                        if (_pending case final before?) {
                          _remember(before);
                          _pending = null;
                        }
                        _photoAt += Offset(d.focalPointDelta.dx / size.width, d.focalPointDelta.dy / size.height);
                        if (d.pointerCount > 1) _photoZoom = (startZoom * d.scale).clamp(1.0, 4.0);
                      }),
                child: _background(scheme, size),
              ),
              for (final layer in _layers)
                switch (layer) {
                  final PosterItem item when item.visible => _card(item, size, unit),
                  // The person over the cards below them, from the same photo at the same place.
                  PosterPerson() when _cutout != null && _personShown => IgnorePointer(
                    child: Opacity(opacity: _personOpacity, child: _placed(_cutout!, size)),
                  ),
                  _ => const SizedBox.shrink(),
                },
              if (_guideX)
                IgnorePointer(
                  child: Center(child: Container(width: 1.5, color: Colors.pinkAccent.withValues(alpha: 0.9))),
                ),
              if (_guideY)
                IgnorePointer(
                  child: Center(child: Container(height: 1.5, color: Colors.pinkAccent.withValues(alpha: 0.9))),
                ),
              if (_watermark) _watermarkMark(unit),
              if (_items.isEmpty && _photo == null)
                IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        tr.posterEmpty,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              if (_cutting)
                ColoredBox(
                  color: Colors.black45,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(tr.posterFindingYou, style: const TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _watermarkMark(double unit) => IgnorePointer(
    child: Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(bottom: 24 * unit),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLogo(size: 28 * unit),
            SizedBox(width: 8 * unit),
            Text(
              'Riflay',
              style: TextStyle(
                color: Colors.white,
                fontSize: 23 * unit,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                shadows: const [Shadow(color: Color(0x80000000), blurRadius: 8)],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// [bytes] (the photo or its cut-out) where the photo is: covering the poster, moved and zoomed.
  Widget _placed(Uint8List bytes, Size size) => Transform(
    alignment: Alignment.center,
    transform: Matrix4.translationValues(_photoAt.dx * size.width, _photoAt.dy * size.height, 0)
      ..scaleByDouble(_photoZoom, _photoZoom, 1, 1),
    child: Graded(
      grade: _grade,
      child: Image.memory(bytes, fit: BoxFit.cover, width: size.width, height: size.height, gaplessPlayback: true),
    ),
  );

  Widget _background(ColorScheme scheme, Size size) {
    if (_photo case final photo? when _photoShown) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: scheme.surfaceContainerLowest),
          Opacity(opacity: _photoOpacity, child: _placed(photo, size)),
          Vignette(amount: _grade.vignette),
        ],
      );
    }
    if (_items.firstOrNull case final first?) return FadedCover(track: first.track, darken: 0.3, sharp: false);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [scheme.primaryContainer, scheme.surface],
        ),
      ),
    );
  }

  Widget _card(PosterItem item, Size size, double unit) {
    final selected = identical(item, _selected);
    var startScale = item.scale, startTilt = item.tilt;
    return Positioned(
      left: item.at.dx * size.width - PosterCard.width / 2,
      top: item.at.dy * size.height - 230,
      // Locked: the poster's touches go through it.
      child: IgnorePointer(
        ignoring: item.locked,
        child: Transform(
          alignment: Alignment.center,
          transform: item.transform(unit),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _selected = item),
            onScaleStart: (_) {
              startScale = item.scale;
              startTilt = item.tilt;
              _slop = 0;
              _pending = _snapshot();
              setState(() => _selected = item);
            },
            onScaleUpdate: (d) => setState(() {
              // The finger's move on screen (through the view's zoom), as a part of the poster.
              final zoom = _view.value.getMaxScaleOnAxis();
              _slop += d.focalPointDelta.distance;
              if ((_slop > _deadZone || d.pointerCount > 1) && _pending != null) {
                _remember(_pending);
                _pending = null;
              }
              if (_slop > _deadZone || d.pointerCount > 1) {
                var at = item.at + Offset(d.focalPointDelta.dx / size.width, d.focalPointDelta.dy / size.height) / zoom;
                at = Offset(at.dx.clamp(0.0, 1.0), at.dy.clamp(0.0, 1.0));
                _guideX = (at.dx - 0.5).abs() < _snapAt;
                _guideY = (at.dy - 0.5).abs() < _snapAt;
                item.at = Offset(_guideX ? 0.5 : at.dx, _guideY ? 0.5 : at.dy);
              }
              if (d.pointerCount > 1) {
                item.scale = (startScale * d.scale).clamp(0.3, 2.5);
                final turn = startTilt + d.rotation;
                item.tilt = turn.abs() < _snapTurn ? 0 : turn;
              }
            }),
            onScaleEnd: (_) => setState(() => _guideX = _guideY = false),
            child: Opacity(
              opacity: item.opacity,
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  border: selected ? Border.all(color: Colors.white, width: 3 / (item.scale * unit)) : null,
                ),
                child: PosterSlab(
                  style: item.style,
                  thickness: item.depth,
                  child: PosterCard(track: item.track, progress: item.progress, style: item.style),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // The steps ----------------------------------------------------------------------------------------------------

  /// The steps, in the order a poster is made: big, labelled, one at a time.
  Widget _stepTabs() => NavigationBar(
    height: 64,
    selectedIndex: _step.index,
    onDestinationSelected: (i) => setState(() => _step = _Step.values[i]),
    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    destinations: [
      NavigationDestination(icon: const Icon(Icons.image_outlined), label: tr.posterPhoto),
      NavigationDestination(icon: const Icon(Icons.library_music_outlined), label: tr.posterSongs),
      NavigationDestination(icon: const Icon(Icons.auto_awesome_mosaic_outlined), label: tr.posterLayout),
      NavigationDestination(icon: const Icon(Icons.layers_outlined), label: tr.posterLayers),
      NavigationDestination(icon: const Icon(Icons.aspect_ratio_rounded), label: tr.posterCanvas),
    ],
  );

  Widget _stepPanel() => Padding(
    key: ValueKey(_step),
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: switch (_step) {
      _Step.photo => _photoStep(),
      _Step.songs => _songsStep(),
      _Step.layout => _layoutStep(),
      _Step.layers => _layersStep(),
      _Step.canvas => _canvasStep(),
    },
  );

  Widget _liveLabel(String text) {
    final scheme = Theme.of(context).colorScheme;
    final (name, value) = (text.substring(0, text.lastIndexOf(' ')), text.substring(text.lastIndexOf(' ') + 1));
    return Material(
      color: scheme.surfaceContainerHighest,
      shape: const StadiumBorder(),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: ShapeDecoration(color: scheme.primary, shape: const StadiumBorder()),
              child: Text(
                value,
                style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Material's adjust row: a pill per setting, the picked one lit, and one slider for it.
  Widget _adjuster(List<_Knob> knobs, int at, ValueChanged<int> pick, {bool locked = false}) {
    final scheme = Theme.of(context).colorScheme;
    final knob = knobs[at.clamp(0, knobs.length - 1)];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final (i, k) in knobs.indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Tooltip(
                    message: k.label,
                    child: Material(
                      color: identical(k, knob) ? scheme.primaryContainer : scheme.surfaceContainerHigh,
                      shape: const StadiumBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => pick(i),
                        child: SizedBox(
                          width: 64,
                          child: Icon(
                            k.icon,
                            color: identical(k, knob) ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            SizedBox(width: 96, child: Text(knob.label, style: Theme.of(context).textTheme.labelLarge)),
            Expanded(
              child: Slider(
                // ignore: deprecated_member_use
                year2023: false,
                value: knob.value.clamp(knob.min, knob.max),
                min: knob.min,
                max: knob.max,
                onChangeStart: (_) => setState(() {
                  _remember();
                  _live = '${knob.label} ${knob.shown}';
                }),
                onChanged: locked
                    ? null
                    : (v) => setState(() {
                        knob.set(v);
                        final now = _Knob(
                          knob.icon,
                          knob.label,
                          v,
                          knob.min,
                          knob.max,
                          knob.set,
                          neutral: knob.neutral,
                        );
                        _live = '${knob.label} ${now.shown}';
                      }),
                onChangeEnd: (_) => setState(() => _live = null),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// A short line saying what this step is for.
  Widget _say(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
  );

  Widget _slider(String label, double value, double min, double max, ValueChanged<double> change) => Row(
    children: [
      SizedBox(width: 84, child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChangeStart: (_) => _remember(),
          onChanged: (v) => setState(() => change(v)),
        ),
      ),
    ],
  );

  Widget _photoStep() {
    void grade(PhotoGrade g) {
      _grade = g;
      _filter = null;
    }

    final knobs = [
      _Knob(Icons.zoom_in_rounded, tr.posterZoom, _photoZoom, 1, 4, (v) => _photoZoom = v),
      _Knob(
        Icons.light_mode_outlined,
        tr.posterBrightness,
        _grade.brightness,
        -0.5,
        0.5,
        (v) => grade(_grade.copyWith(brightness: v)),
        neutral: 0,
      ),
      _Knob(
        Icons.contrast_rounded,
        tr.posterContrast,
        _grade.contrast,
        0.5,
        1.5,
        (v) => grade(_grade.copyWith(contrast: v)),
        neutral: 1,
      ),
      _Knob(
        Icons.water_drop_outlined,
        tr.posterSaturation,
        _grade.saturation,
        0,
        2,
        (v) => grade(_grade.copyWith(saturation: v)),
        neutral: 1,
      ),
      _Knob(
        Icons.thermostat_rounded,
        tr.posterWarmth,
        _grade.warmth,
        -1,
        1,
        (v) => grade(_grade.copyWith(warmth: v)),
        neutral: 0,
      ),
      _Knob(Icons.blur_on_rounded, tr.posterFade, _grade.fade, 0, 1, (v) => grade(_grade.copyWith(fade: v))),
      _Knob(
        Icons.vignette_outlined,
        tr.posterVignette,
        _grade.vignette,
        0,
        1,
        (v) => grade(_grade.copyWith(vignette: v)),
      ),
    ];
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_photo == null || _cutting) ...[
            _say(_photo == null ? tr.posterStepPhoto : tr.posterFindingYou),
            FilledButton.icon(
              onPressed: _cutting ? null : _pickPhoto,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(tr.choosePhoto),
              style: FilledButton.styleFrom(minimumSize: const Size(220, 48)),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    _cutout == null ? tr.posterNoCutout : tr.posterFoundYou,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: _pickPhoto,
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: Text(tr.posterReplacePhoto),
                ),
              ],
            ),
            // Colour: a filter in one tap, then a setting at a time.
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final filter in PhotoFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(filter.label),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() {
                          _remember();
                          _filter = filter;
                          _grade = filter.grade;
                        }),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _adjuster(knobs, _photoKnob, (i) => setState(() => _photoKnob = i)),
          ],
        ],
      ),
    );
  }

  Widget _songsStep() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _say(tr.posterStepSongs),
      SizedBox(
        height: 120,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final item in _items)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: SizedBox(
                  width: 84,
                  child: Column(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Artwork(track: item.track, size: 76, radius: 14),
                          Positioned(
                            top: -8,
                            right: -8,
                            child: IconButton.filledTonal(
                              iconSize: 16,
                              visualDensity: VisualDensity.compact,
                              tooltip: tr.remove,
                              onPressed: () => _remove(item),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(item.track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ),
            if (_items.length < PosterEditor.maxCards)
              SizedBox(
                width: 84,
                child: Column(
                  children: [
                    SizedBox.square(
                      dimension: 76,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _addSong,
                        child: const Icon(Icons.add_rounded, size: 32),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(tr.posterAddSong, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _layoutStep() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _say(_items.isEmpty ? tr.posterStepLayoutEmpty : tr.posterStepLayout),
      SizedBox(
        height: 150,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final preset in PosterPreset.values)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _items.isEmpty
                      ? null
                      : () => setState(() {
                          _remember();
                          _apply(preset);
                        }),
                  child: Column(
                    children: [
                      Expanded(
                        child: PosterPresetPreview(preset: preset, selected: preset == _preset),
                      ),
                      const SizedBox(height: 6),
                      Text(preset.label, style: Theme.of(context).textTheme.labelLarge),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  /// The poster's size as frames drawn to its proportions, the one in use lit; the Riflay mark under them.
  Widget _canvasStep() {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    Widget tile(PosterShape shape) {
      final on = shape == _shape;
      // Each frame as tall as the row, as wide as its proportions make it.
      const tall = 72.0;
      final wide = (tall * shape.ratio).clamp(40.0, 128.0);
      return Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Material(
          color: on ? scheme.secondaryContainer : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => setState(() {
              _remember();
              _shape = shape;
            }),
            child: Container(
              width: 150,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: on ? scheme.primary : Colors.transparent, width: 2),
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: tall,
                    child: Center(
                      child: Container(
                        width: wide,
                        height: wide / shape.ratio,
                        decoration: BoxDecoration(
                          color: on ? scheme.primary : scheme.outlineVariant,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(shape.icon, size: 20, color: on ? scheme.onPrimary : scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    shape.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelLarge?.copyWith(fontWeight: on ? FontWeight.w700 : null),
                  ),
                  Text(shape.detail, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 182,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [for (final s in PosterShape.values) tile(s)]),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.branding_watermark_outlined),
            title: Text(tr.posterWatermark),
            subtitle: Text(tr.posterWatermarkHint),
            value: _watermark,
            onChanged: (v) => setState(() {
              _remember();
              _watermark = v;
            }),
          ),
        ],
      ),
    );
  }

  // Layers, as a picture editor lists them -----------------------------------------------------------------------

  /// Top first: each with its eye, picture and name, dragged by its handle to reorder; the picked one's opacity and
  /// actions under the list. The photo stays at the bottom, as a picture editor's background layer does.
  Widget _layersStep() {
    final scheme = Theme.of(context).colorScheme;
    final shown = _layers.reversed.where((l) => l is PosterItem || _cutout != null).toList();
    final picked = _selected;
    Widget row(Object layer, {required int? index}) {
      final on = identical(layer, picked);
      final locked = switch (layer) {
        final PosterItem item => item.locked,
        PosterPhoto() => _photoLocked,
        _ => false,
      };
      final (Widget thumb, String name, String kind, bool visible) = switch (layer) {
        PosterItem(:final track, :final visible) => (
          Artwork(track: track, size: 36, radius: 6),
          track.title,
          tr.posterCard,
          visible,
        ),
        PosterPerson() => (
          _cutout == null ? const Icon(Icons.person_outline_rounded) : Image.memory(_cutout!, width: 36, height: 36),
          tr.posterYou,
          tr.posterCutOut,
          _personShown,
        ),
        _ => (
          _photo == null
              ? const Icon(Icons.image_outlined)
              : ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(_photo!, width: 36, height: 36, fit: BoxFit.cover),
                ),
          tr.posterPhoto,
          tr.posterBackground,
          _photoShown,
        ),
      };
      return Material(
        key: ObjectKey(layer),
        color: on ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _selected = on ? null : layer),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: visible ? tr.posterHide : tr.posterShow,
                  onPressed: () => setState(() {
                    _remember();
                    switch (layer) {
                      case final PosterItem item:
                        item.visible = !item.visible;
                      case PosterPerson():
                        _personShown = !_personShown;
                      default:
                        _photoShown = !_photoShown;
                    }
                  }),
                  icon: Icon(visible ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                ),
                SizedBox.square(dimension: 36, child: Center(child: thumb)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: visible ? null : scheme.onSurface.withValues(alpha: 0.5)),
                      ),
                      Text(kind, style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ),
                ),
                if (layer is! PosterPerson)
                  IconButton(
                    tooltip: locked ? tr.posterUnlock : tr.posterLock,
                    isSelected: locked,
                    onPressed: () => setState(() {
                      _remember();
                      switch (layer) {
                        case final PosterItem item:
                          item.locked = !item.locked;
                        default:
                          _photoLocked = !_photoLocked;
                      }
                    }),
                    icon: Icon(locked ? Icons.lock_rounded : Icons.lock_open_rounded, size: 20),
                  ),
                if (index != null)
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle_rounded)),
                  )
                else
                  // The photo stays at the bottom, as a picture editor's background does.
                  const SizedBox(width: 40),
              ],
            ),
          ),
        ),
      );
    }

    final opacity = switch (picked) {
      final PosterItem item => item.opacity,
      PosterPerson() => _personOpacity,
      PosterPhoto() => _photoOpacity,
      _ => null,
    };
    return Column(
      children: [
        if (opacity != null)
          _slider(tr.posterOpacity, opacity, 0, 1, (v) {
            switch (picked) {
              case final PosterItem item:
                item.opacity = v;
              case PosterPerson():
                _personOpacity = v;
              default:
                _photoOpacity = v;
            }
          })
        else
          _say(tr.posterStepLayers),
        Expanded(
          child: ReorderableListView(
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) => setState(() {
              _remember();
              final layer = shown.removeAt(from);
              shown.insert(to, layer);
              final hidden = _cutout == null ? [PosterPerson.layer] : const <Object>[];
              _layers
                ..clear()
                ..addAll(hidden)
                ..addAll(shown.reversed);
            }),
            footer: _photo == null ? null : row(PosterPhoto.layer, index: null),
            children: [for (final (i, layer) in shown.indexed) row(layer, index: i)],
          ),
        ),
        if (picked != null && picked is! PosterPhoto)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (picked is PosterItem)
                IconButton(
                  tooltip: tr.posterDuplicate,
                  onPressed: () => _duplicate(picked),
                  icon: const Icon(Icons.copy_rounded),
                ),
              IconButton(
                tooltip: tr.posterForward,
                onPressed: () => _move(picked, 1),
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
              IconButton(
                tooltip: tr.posterBackward,
                onPressed: () => _move(picked, -1),
                icon: const Icon(Icons.arrow_downward_rounded),
              ),
              if (picked is PosterItem)
                IconButton(
                  tooltip: tr.remove,
                  onPressed: () => _remove(picked),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
      ],
    );
  }

  // A picked card ------------------------------------------------------------------------------------------------

  /// A card's controls: its settings a pill at a time, its look, and what can be done with it; Done back to the
  /// steps.
  Widget _cardControls(PosterItem item) {
    final knobs = [
      _Knob(Icons.open_in_full_rounded, tr.posterSize, item.scale, 0.3, 2.5, (v) => item.scale = v, neutral: 1),
      _Knob(
        Icons.rotate_right_rounded,
        tr.posterRotate,
        item.tilt,
        -math.pi,
        math.pi,
        (v) => item.tilt = v,
        neutral: 0,
      ),
      _Knob(
        Icons.swap_vert_rounded,
        tr.posterTilt,
        item.pitch,
        -math.pi / 3,
        math.pi / 3,
        (v) => item.pitch = v,
        neutral: 0,
      ),
      _Knob(
        Icons.swap_horiz_rounded,
        tr.posterTurn,
        item.yaw,
        -math.pi / 3,
        math.pi / 3,
        (v) => item.yaw = v,
        neutral: 0,
      ),
      _Knob(Icons.view_in_ar_rounded, tr.posterThickness, item.depth, 0, 20, (v) => item.depth = v),
      _Knob(Icons.linear_scale_rounded, tr.posterProgress, item.progress, 0, 1, (v) => item.progress = v),
      _Knob(Icons.opacity_rounded, tr.posterOpacity, item.opacity, 0.1, 1, (v) => item.opacity = v),
    ];
    return Padding(
      key: ObjectKey(item),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SingleChildScrollView(
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: tr.posterDuplicate,
                  onPressed: () => _duplicate(item),
                  icon: const Icon(Icons.copy_rounded),
                ),
                IconButton(
                  tooltip: tr.posterForward,
                  onPressed: () => _move(item, 1),
                  icon: const Icon(Icons.flip_to_front_rounded),
                ),
                IconButton(
                  tooltip: tr.remove,
                  onPressed: () => _remove(item),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
                const SizedBox(width: 4),
                FilledButton(onPressed: () => setState(() => _selected = null), child: Text(tr.done)),
              ],
            ),
            const SizedBox(height: 6),
            if (item.locked)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(tr.posterLockedHint, style: Theme.of(context).textTheme.bodySmall),
              ),
            _adjuster(knobs, _cardKnob, (i) => setState(() => _cardKnob = i), locked: item.locked),
            const SizedBox(height: 4),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final style in PosterCardStyle.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(switch (style) {
                          PosterCardStyle.light => tr.posterLight,
                          PosterCardStyle.dark => tr.posterDark,
                          PosterCardStyle.glass => tr.posterGlass,
                          PosterCardStyle.cover => tr.posterCoverColour,
                        }),
                        selected: item.style == style,
                        onSelected: (_) => setState(() {
                          _remember();
                          item.style = _style = style;
                        }),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The poster at one moment, for Undo and Redo.
class _Snapshot {
  _Snapshot({
    required this.layers,
    required this.photo,
    required this.cutout,
    required this.photoAt,
    required this.photoZoom,
    required this.photoShown,
    required this.photoLocked,
    required this.personShown,
    required this.photoOpacity,
    required this.personOpacity,
    required this.grade,
    required this.filter,
    required this.shape,
    required this.watermark,
    required this.preset,
  });

  final List<Object> layers;
  final Uint8List? photo, cutout;
  final Offset photoAt;
  final double photoZoom, photoOpacity, personOpacity;
  final bool photoShown, photoLocked, personShown, watermark;
  final PhotoGrade grade;
  final PhotoFilter? filter;
  final PosterShape shape;
  final PosterPreset preset;
}
