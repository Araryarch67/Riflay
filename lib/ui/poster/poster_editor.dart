import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/track.dart';
import '../../services/language.dart';
import '../../services/layout_prefs.dart';
import '../../platform/background.dart';
import '../../services/subject_cutout.dart';
import '../card_export.dart';
import '../player_scope.dart';
import '../widgets/app_logo.dart';
import '../widgets/controls.dart' show Artwork;
import '../widgets/faded_cover.dart';
import 'photo_grade.dart';
import 'poster_draft.dart';
import 'poster_card.dart';
import 'poster_decoration.dart';
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

/// Songs for a poster picked from [tracks] (a playlist, liked songs, all songs…), up to [PosterEditor.maxCards], then
/// the editor with them on it and the rest of the list to add from.
Future<void> showPosterFromList(BuildContext context, List<Track> tracks) async {
  final picked = await showModalBottomSheet<List<Track>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (context) => _PosterSongPicker(tracks: tracks),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;
  await showPosterEditor(context, songs: picked, pool: tracks);
}

class _PosterSongPicker extends StatefulWidget {
  const _PosterSongPicker({required this.tracks});

  final List<Track> tracks;

  @override
  State<_PosterSongPicker> createState() => _PosterSongPickerState();
}

class _PosterSongPickerState extends State<_PosterSongPicker> {
  final _picked = <Track>[];

  /// The fewest songs a poster from a list starts with (all of them, in a shorter list).
  static const minSongs = 3;

  @override
  Widget build(BuildContext context) {
    final full = _picked.length >= PosterEditor.maxCards;
    final needed = math.min(minSongs, widget.tracks.length);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr.posterPickSongs(_picked.length, PosterEditor.maxCards),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(tr.posterPickAtLeast(needed), style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: _picked.length < needed ? null : () => Navigator.of(context).pop(List.of(_picked)),
                  child: Text(tr.makePoster),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: widget.tracks.length,
              itemBuilder: (context, i) {
                final t = widget.tracks[i];
                final on = _picked.contains(t);
                return CheckboxListTile(
                  value: on,
                  // Full: only the picked ones can still be changed.
                  onChanged: !on && full ? null : (_) => setState(() => on ? _picked.remove(t) : _picked.add(t)),
                  secondary: Artwork(track: t, size: 44, radius: 8),
                  title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
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

  /// The song on the card; another can be put in its place, the card staying as it is.
  Track track;
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
  const _Knob(
    this.icon,
    this.label,
    this.value,
    this.min,
    this.max,
    this.set, {
    double? neutral,
    this.percent = false,
    this.raw = false,
  }) : neutral = neutral ?? min;

  final IconData icon;
  final String label;
  final double value, min, max, neutral;
  final ValueChanged<double> set;

  /// Shown as itself in percent (a size, a zoom, an opacity), not as a step from neutral.
  final bool percent;

  /// Shown as itself (a thickness in points).
  final bool raw;

  /// The value as shown: 0 at neutral, up to ±100 at the ends (or itself in percent).
  int get shown => raw
      ? value.round()
      : percent
      ? (value * 100).round()
      : neutral <= min
      ? ((value - min) / (max - min) * 100).round()
      : value >= neutral
      ? ((value - neutral) / (max - neutral) * 100).round()
      : -((neutral - value) / (neutral - min) * 100).round();
}

/// The steps a poster is made in, one tab each.
enum _Step { photo, songs, layout, decor, layers, canvas }

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

  /// The model that finds the person, and one being fetched (with how far).
  CutoutModel _model = CutoutModel.builtIn;
  CutoutModel? _fetching;
  double _fetched = 0;
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
  static const _deadZone = 6.0;

  /// Where the dragged card would be without snapping: moves add to this, so a slow drag can leave the middle (added
  /// to the snapped place, each small move was snapped back).
  Offset _dragAt = Offset.zero;

  /// The last poster, kept on the device: offered when the editor opens, saved as this one changes (not before the
  /// person has said whether to go on with the last one).
  ({Map<String, dynamic> state, Uint8List? photo, Uint8List? cutout})? _draft;
  bool _draftChecked = false;
  Timer? _autosave;
  String? _savedState;

  Map<String, dynamic> _state() => {
    'layers': [
      for (final l in _layers)
        switch (l) {
          final PosterItem item => item.toJson(),
          final PosterDecoration d => d.toJson(),
          _ => {'person': true},
        },
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
          l['person'] == true
              ? PosterPerson.layer
              : l['decoration'] != null
              ? PosterDecoration.fromJson(l.cast<String, dynamic>())
              : PosterItem.fromJson(l.cast<String, dynamic>()),
      ]);
    if (!_layers.contains(PosterPerson.layer)) _layers.add(PosterPerson.layer);
    _photo = photo;
    _cutout = cutout;
    unawaited(_mapSubject());
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
    layers: [
      for (final l in _layers)
        switch (l) {
          final PosterItem item => item.copy(),
          final PosterDecoration d => d.copy(),
          _ => l,
        },
    ],
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
    unawaited(_mapSubject());
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
    SubjectCutout.picked().then((m) {
      if (mounted) setState(() => _model = m);
    });
  }

  /// Where the person is in [_cutout], once read ([_subjectOf] is the cut-out it was read from).
  SubjectMap? _subject;
  Uint8List? _subjectOf;

  /// [_cutout] read for where the person is, in the background; kept only if the cut-out is still the same.
  Future<void> _mapSubject() async {
    final cut = _cutout;
    if (identical(cut, _subjectOf)) return;
    final map = cut == null ? null : await inBackground(() => SubjectMap.fromPng(cut));
    if (identical(_cutout, cut)) {
      _subject = map;
      _subjectOf = cut;
    }
  }

  /// [preset]'s [count] poses, those the person in the photo would hide moved where they can be seen.
  List<PosterPose> _layout(PosterPreset preset, int count, {bool preview = false}) {
    final poses = preset.layout(count);
    if (!preview && _cutout != null && !identical(_subjectOf, _cutout)) {
      // Not read yet (a poster opened before, a draft just back): read it, then lay the cards out again around them.
      final cut = _cutout;
      unawaited(
        _mapSubject().then((_) {
          if (mounted && identical(_cutout, cut) && _preset == preset) setState(() => _apply(preset));
        }),
      );
    }
    final map = _subject;
    if (map == null || !identical(_subjectOf, _cutout) || !_personShown) return poses;
    // A card's half-size at scale 1 on this poster, as parts of it (260 × 460 at unit 1; see _canvas).
    final ratio = _shape.ratio;
    final halfWide = 130 / 390 * math.min(1.0, 9 / 16 / ratio), halfTall = 230 / 390 * math.min(ratio, 9 / 16);
    // A person filling the photo: the spread-out presets laid out across the clear band above them instead.
    final outline = map.outline(posterAspect: ratio, photoAt: _photoAt, zoom: _photoZoom);
    final band = outline.top < 0.5
        ? preset.aboveHead(count, top: outline.top, headX: outline.headX, halfWide: halfWide, halfTall: halfTall)
        : null;
    return clearOfSubject(
      band ?? poses,
      (at, scale) => map.covering(
        at,
        halfWide * scale,
        halfTall * scale,
        posterAspect: ratio,
        photoAt: _photoAt,
        zoom: _photoZoom,
      ),
      halfWide: halfWide,
      halfTall: halfTall,
    );
  }

  /// The presets' layouts as they would come out on this poster, for their previews; worked out again only when what
  /// they depend on changes (finding them clear of the person tries thousands of placements).
  final _previews = <PosterPreset, List<PosterPose>>{};
  Object? _previewsFor;

  List<PosterPose> _preview(PosterPreset preset) {
    final count = _items.isEmpty ? 4 : _items.length;
    final key = (count, _cutout, _subjectOf, _photoAt, _photoZoom, _shape, _personShown);
    if (key != _previewsFor) {
      _previews.clear();
      _previewsFor = key;
      if (_cutout != null && !identical(_subjectOf, _cutout)) {
        // Read where the person is, then draw the previews again around them.
        unawaited(_mapSubject().then((_) => mounted ? setState(() {}) : null));
      }
    }
    return _previews[preset] ??= _layout(preset, count, preview: true);
  }

  /// Every card placed as [preset] has it (and given its look, when it suggests one), clear of the person.
  void _apply(PosterPreset preset) {
    _preset = preset;
    final items = _items.toList();
    for (final (i, pose) in _layout(preset, items.length).indexed) {
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
      cut = await SubjectCutout.cutout(bytes, model: _model);
    } catch (e) {
      debugPrint('Poster: no cutout: $e');
    }
    if (!mounted || !identical(_photo, bytes)) return;
    setState(() {
      _cutout = cut;
      _cutting = false;
    });
    // The layout set again around the person now found, so no card starts hidden behind them.
    if (cut != null) {
      await _mapSubject();
      if (mounted && identical(_cutout, cut)) setState(() => _apply(_preset));
    }
    if (cut == null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.posterNoCutout)));
  }

  /// A song from the playlist it was opened from, what plays, what played and the library; null when none is picked.
  Future<Track?> _pickSong() async {
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
    return picked;
  }

  /// The card's song swapped for another: where it sits, its size, turn and look stay.
  Future<void> _replaceSong(PosterItem item) async {
    final picked = await _pickSong();
    if (picked == null || !mounted) return;
    setState(() {
      _remember();
      item.track = picked;
    });
  }

  Future<void> _addSong() async {
    final picked = await _pickSong();
    if (picked == null || !mounted) return;
    setState(() {
      // Where the chosen preset puts one more card.
      final pose = _layout(_preset, _items.length + 1).last;
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
    if (layer is PosterItem || layer is PosterDecoration) _layers.remove(layer);
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
    final decoration = _selected is PosterDecoration ? _selected as PosterDecoration : null;
    _saveSoon();
    final hasWork = _items.isNotEmpty || _photo != null;
    return PopScope(
      canPop: !hasWork,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          backgroundColor: scheme.surface,
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
          // A wide window gets a picture editor's layout: the steps down the side, the poster as big as it can be,
          // and the settings in a panel at full height; a phone, the poster over its panel and the steps' tabs.
          child: LayoutBuilder(
            builder: (context, box) {
              final wide = _wide = box.maxWidth >= 840;
              final panel = AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                // At the top, not floating in the middle of a tall side panel.
                layoutBuilder: (current, previous) =>
                    Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
                child: card != null
                    ? _cardControls(card)
                    : decoration != null
                    ? _decorationControls(decoration)
                    : _stepPanel(),
              );
              return Column(
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
                  if (wide)
                    Expanded(
                      // Separate panels floating on the page, a gap between each, as an editor's are.
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 12,
                          children: [
                            Material(
                              color: scheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(10),
                              clipBehavior: Clip.antiAlias,
                              child: _stepRail(),
                            ),
                            Expanded(child: _posterArea(scheme)),
                            // A Material, not a coloured box: the list tiles in it draw their ink on it.
                            Material(
                              color: scheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(10),
                              clipBehavior: Clip.antiAlias,
                              // A quieter, denser kit for the side panel, as an editor's panels are.
                              child: Theme(
                                data: Theme.of(context).copyWith(
                                  visualDensity: VisualDensity.compact,
                                  chipTheme: ChipThemeData(
                                    labelStyle: Theme.of(context).textTheme.labelMedium,
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
                                    shape: const StadiumBorder(),
                                    showCheckmark: false,
                                  ),
                                  iconButtonTheme: IconButtonThemeData(
                                    style: IconButton.styleFrom(iconSize: 20, foregroundColor: scheme.onSurfaceVariant),
                                  ),
                                ),
                                child: Container(
                                  width: 380,
                                  padding: const EdgeInsets.only(top: 20),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      if (card == null)
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                                          child: Text(
                                            switch (_step) {
                                              _Step.photo => tr.posterPhoto,
                                              _Step.songs => tr.posterSongs,
                                              _Step.layout => tr.posterLayout,
                                              _Step.decor => tr.posterDecor,
                                              _Step.layers => tr.posterLayers,
                                              _Step.canvas => tr.posterCanvas,
                                            },
                                            style: Theme.of(context).textTheme.titleMedium
                                                ?.copyWith(fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      Expanded(child: panel),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    Expanded(child: _posterArea(scheme)),
                    // A sheet of its own under the poster, at a steady height: the poster doesn't jump as panels change.
                    Material(
                      color: scheme.surfaceContainerLow,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: SizedBox(height: 248, child: panel),
                      ),
                    ),
                    if (card == null && decoration == null) _stepTabs(),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// The poster, zoomable, with the slider's value over it while sliding and Fit once zoomed.
  Widget _posterArea(ColorScheme scheme) => GestureDetector(
    // A click or tap beside the poster lets go of what is picked, as on the poster's empty part.
    behavior: HitTestBehavior.opaque,
    onTap: _selected == null ? null : () => setState(() => _selected = null),
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
              scaleEnabled: !_movingPhoto && !_movable(_selected),
              child: Center(
                child: AspectRatio(aspectRatio: _shape.ratio, child: _canvas(scheme)),
              ),
            ),
            if (_live != null) Positioned(left: 0, right: 0, bottom: 16, child: Center(child: _liveLabel(_live!))),
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
  );

  /// The steps down the side of a wide window.
  Widget _stepRail() => NavigationRail(
    backgroundColor: Colors.transparent,
    selectedIndex: _step.index,
    onDestinationSelected: (i) => setState(() {
      _step = _Step.values[i];
      _selected = null;
    }),
    labelType: NavigationRailLabelType.all,
    groupAlignment: -0.85,
    destinations: [
      NavigationRailDestination(icon: const Icon(Icons.image_outlined), label: Text(tr.posterPhoto)),
      NavigationRailDestination(icon: const Icon(Icons.library_music_outlined), label: Text(tr.posterSongs)),
      NavigationRailDestination(icon: const Icon(Icons.auto_awesome_mosaic_outlined), label: Text(tr.posterLayout)),
      NavigationRailDestination(icon: const Icon(Icons.auto_awesome_outlined), label: Text(tr.posterDecor)),
      NavigationRailDestination(icon: const Icon(Icons.layers_outlined), label: Text(tr.posterLayers)),
      NavigationRailDestination(icon: const Icon(Icons.aspect_ratio_rounded), label: Text(tr.posterCanvas)),
    ],
  );

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
      // Square corners, as the saved picture has: what is edited is exactly what is kept.
      return ClipRect(
        child: Listener(
          onPointerDown: _fingerDown,
          onPointerMove: (e) => _fingerMove(e, size),
          onPointerUp: _fingerUp,
          onPointerCancel: _fingerUp,
          onPointerSignal: _wheel,
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
                    final PosterDecoration d when d.visible => _decoration(d, size, unit),
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
    return Positioned(
      left: item.at.dx * size.width - PosterCard.width / 2,
      top: item.at.dy * size.height,
      // Its middle on its place, whatever its height (a fixed guess had drawn cards higher than their place).
      child: FractionalTranslation(
        translation: const Offset(0, -0.5),
        child: IgnorePointer(
          ignoring: item.locked,
          child: Opacity(
            opacity: item.opacity,
            child: PosterSlab(
              style: item.style,
              thickness: item.depth,
              transform: item.transform(unit),
              child: Listener(
                onPointerDown: (e) => _touched(item, e.position),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _selected = item),
                  onScaleStart: (d) => _dragStart(item, d.focalPoint),
                  onScaleUpdate: (d) => _dragUpdate(item, d, size),
                  onScaleEnd: (_) => _dragEnd(),
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      border: selected ? Border.all(color: Colors.white, width: 3 / (item.scale * unit)) : null,
                    ),
                    // A hand over what can be dragged, closed while dragging.
                    child: MouseRegion(
                      cursor: _dragging && selected ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
                      child: PosterCard(track: item.track, progress: item.progress, style: item.style),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Moving a card or a decoration ---------------------------------------------------------------------------------

  /// Whether [layer] is a card or a decoration that can be moved (not locked).
  bool _movable(Object? layer) =>
      (layer is PosterItem && !layer.locked) || (layer is PosterDecoration && !layer.locked);

  ({Offset at, double scale, double tilt}) _poseOf(Object layer) => switch (layer) {
    final PosterItem i => (at: i.at, scale: i.scale, tilt: i.tilt),
    final PosterDecoration d => (at: d.at, scale: d.scale, tilt: d.tilt),
    _ => (at: const Offset(0.5, 0.5), scale: 1, tilt: 0),
  };

  /// Upright now (its turn snapped to 0), so the snap is felt once, as it is reached.
  bool _upright = false;

  /// [layer] put at [_dragAt] (snapped to the middle lines when near them), and sized and turned when given (snapped
  /// upright when near it), a light tick felt as either snap is reached.
  void _place(Object layer, {double? scale, double? tilt}) {
    // Kept on the poster, [_dragAt] itself left as it is: back from past the edge, it is under the pointer again.
    final to = Offset(_dragAt.dx.clamp(0.0, 1.0), _dragAt.dy.clamp(0.0, 1.0));
    final x = (to.dx - 0.5).abs() < _snapAt, y = (to.dy - 0.5).abs() < _snapAt;
    if ((x && !_guideX) || (y && !_guideY)) unawaited(HapticFeedback.selectionClick());
    _guideX = x;
    _guideY = y;
    final at = Offset(x ? 0.5 : to.dx, y ? 0.5 : to.dy);
    double? turn;
    if (tilt != null) {
      // Kept within a half turn either way: a pinch crossing the angle's wrap had spun the card round.
      final t = (tilt + math.pi) % (2 * math.pi) - math.pi;
      final upright = t.abs() < _snapTurn;
      if (upright && !_upright) unawaited(HapticFeedback.selectionClick());
      _upright = upright;
      turn = upright ? 0 : t;
    }
    switch (layer) {
      case final PosterItem i:
        i.at = at;
        if (scale != null) i.scale = scale.clamp(0.3, 2.5);
        if (turn != null) i.tilt = turn;
      case final PosterDecoration d:
        d.at = at;
        if (scale != null) d.scale = scale.clamp(0.2, 6.0);
        if (turn != null) d.tilt = turn;
    }
  }

  /// A finger's or the mouse's drag on a card or decoration (one finger: two are the canvas's pinch, below).
  bool _dragging = false;

  /// Where the drag began on screen, and where the layer was then: the layer is placed by how far the pointer has
  /// gone from there, so the spot held stays under it. Moves added up step by step had left it behind: the first
  /// few points (the dead zone) were lost, and so was every move past the poster's edge.
  Offset? _dragFrom;
  Offset _dragStartAt = Offset.zero;

  void _dragStart(Object layer, Offset from) {
    _dragFrom = identical(layer, _downOn) ? _downAt ?? from : from;
    _dragStartAt = _dragAt = _poseOf(layer).at;
    _pending = _snapshot();
    _dragging = true;
    setState(() => _selected = layer);
  }

  void _dragUpdate(Object layer, ScaleUpdateDetails d, Size size) {
    if (_pinch != null) {
      // Picked up again from wherever the pinch leaves it.
      _dragFrom = null;
      return;
    }
    final from = _dragFrom;
    if (from == null) {
      _dragFrom = d.focalPoint;
      _dragStartAt = _poseOf(layer).at;
      return;
    }
    final moved = d.focalPoint - from;
    if (_pending != null && moved.distance <= _deadZone) return;
    setState(() {
      if (_pending case final before?) {
        _remember(before);
        _pending = null;
      }
      // The pointer's move on screen (through the view's zoom), as a part of the poster.
      final zoom = _view.value.getMaxScaleOnAxis();
      _dragAt = _dragStartAt + Offset(moved.dx / size.width, moved.dy / size.height) / zoom;
      _place(layer);
    });
  }

  void _dragEnd() => setState(() {
    _dragging = false;
    _dragFrom = null;
    _pending = null;
    _guideX = _guideY = false;
  });

  /// The fingers on the canvas, where they are (in the poster's own points), first down first.
  final _fingers = <int, Offset>{};

  /// The card or decoration the first finger came down on, if any.
  Object? _downOn;

  /// Two fingers sizing, turning and moving one layer: the picked one, or the one the first finger is on, wherever
  /// the second lands (two on a small decoration had been hard to fit).
  ({Object layer, double span, double angle, Offset middle, double scale, double tilt, Offset at})? _pinch;

  /// Where the pointer came down on [_downOn], on screen: a drag starts from there (the drag itself is only known
  /// once the pointer has moved a little, and that first bit had been lost).
  Offset? _downAt;

  void _touched(Object layer, Offset at) {
    // Runs before the canvas counts the finger: the first finger's layer.
    if (_fingers.isEmpty) {
      _downOn = layer;
      _downAt = at;
    }
  }

  void _fingerDown(PointerDownEvent e) {
    _fingers[e.pointer] = e.localPosition;
    if (_fingers.length != 2) return;
    final layer = _movable(_downOn) ? _downOn : (_movable(_selected) ? _selected : null);
    if (layer == null) return;
    final [a, b] = _fingers.values.toList();
    final pose = _poseOf(layer);
    setState(() {
      if (_pending case final before?) {
        _remember(before);
        _pending = null;
      } else if (!_dragging) {
        _remember();
      }
      _selected = layer;
      _upright = pose.tilt == 0;
      _pinch = (
        layer: layer,
        span: math.max(1.0, (a - b).distance),
        angle: (b - a).direction,
        middle: (a + b) / 2,
        scale: pose.scale,
        tilt: pose.tilt,
        at: pose.at,
      );
    });
  }

  void _fingerMove(PointerMoveEvent e, Size size) {
    if (!_fingers.containsKey(e.pointer)) return;
    _fingers[e.pointer] = e.localPosition;
    final p = _pinch;
    if (p == null || _fingers.length < 2) return;
    final [a, b] = _fingers.values.take(2).toList();
    setState(() {
      final middle = (a + b) / 2;
      _dragAt = p.at + Offset((middle.dx - p.middle.dx) / size.width, (middle.dy - p.middle.dy) / size.height);
      _place(p.layer, scale: p.scale * (a - b).distance / p.span, tilt: p.tilt + (b - a).direction - p.angle);
    });
  }

  void _fingerUp(PointerEvent e) {
    _fingers.remove(e.pointer);
    if (_fingers.isEmpty) _downOn = _downAt = null;
    if (_pinch != null && _fingers.length < 2) {
      setState(() {
        _pinch = null;
        _guideX = _guideY = false;
      });
    }
  }

  /// When the wheel last turned: a burst of wheel steps is one change to undo.
  DateTime _lastWheel = DateTime(0);

  /// The mouse wheel over the poster sizes the picked card or decoration; with Shift (or sideways), turns it.
  void _wheel(PointerSignalEvent e) {
    final layer = _selected;
    if (e is! PointerScrollEvent || layer == null || !_movable(layer)) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (e) {
      final scroll = (e as PointerScrollEvent).scrollDelta;
      final turn = HardwareKeyboard.instance.isShiftPressed || (scroll.dy == 0 && scroll.dx != 0);
      final by = scroll.dy != 0 ? scroll.dy : scroll.dx;
      final now = DateTime.now();
      setState(() {
        if (now.difference(_lastWheel) > const Duration(milliseconds: 700)) _remember();
        _lastWheel = now;
        final pose = _poseOf(layer);
        _dragAt = pose.at;
        _upright = pose.tilt == 0;
        // A wheel step (100) a fifteenth bigger or smaller, or about 9° round.
        turn ? _place(layer, tilt: pose.tilt + by * 0.0015) : _place(layer, scale: pose.scale * math.exp(-by / 1500));
        _guideX = _guideY = false;
      });
    });
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
      NavigationDestination(icon: const Icon(Icons.auto_awesome_outlined), label: tr.posterDecor),
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
      _Step.decor => _decorStep(),
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
                year2023: _classicSlider ? false : null,
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
                          percent: knob.percent,
                          raw: knob.raw,
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

  /// The photo cut out again, with the model now picked.
  Future<void> _recut() async {
    final photo = _photo;
    if (photo == null) return;
    setState(() => _cutting = true);
    Uint8List? cut;
    try {
      cut = await SubjectCutout.cutout(photo, model: _model);
    } catch (e) {
      debugPrint('Poster: no cutout: $e');
    }
    if (!mounted || !identical(_photo, photo)) return;
    setState(() {
      _remember();
      _cutout = cut;
      _cutting = false;
    });
  }

  /// [m] picked: fetched first when it isn't on the device (its size said, and its licence accepted where it has one).
  Future<void> _chooseModel(CutoutModel m) async {
    if (m == _model || _fetching != null) return;
    if (!m.downloaded) {
      final size = (m.bytes / (1 << 20)).round();
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr.posterModelDownloadTitle(_modelName(m))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr.posterModelDownloadBody(size)),
              if (m.licence case final licence?) ...[
                const SizedBox(height: 12),
                Text(tr.posterModelRmbgLicence),
                TextButton.icon(
                  onPressed: () => launchUrl(Uri.parse(licence), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(tr.posterReadLicence),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr.cancel)),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(m.licence == null ? tr.posterDownload : tr.posterAcceptDownload),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      setState(() {
        _fetching = m;
        _fetched = 0;
      });
      try {
        await SubjectCutout.download(
          m,
          progress: (v) {
            if (mounted) setState(() => _fetched = v);
          },
        );
      } catch (e) {
        debugPrint('Poster: model not downloaded: $e');
        if (mounted) {
          setState(() => _fetching = null);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.posterModelFailed)));
        }
        return;
      }
      if (!mounted) return;
      setState(() => _fetching = null);
    }
    setState(() => _model = m);
    unawaited(SubjectCutout.pick(m));
    await _recut();
  }

  String _modelName(CutoutModel m) => switch (m) {
    CutoutModel.builtIn => tr.posterModelBuiltIn,
    CutoutModel.modnet => 'MODNet',
    CutoutModel.rmbg => 'RMBG',
  };

  /// The cut-out models to pick from, a line on each, and a download's progress.
  Widget _modelChooser() {
    final text = Theme.of(context).textTheme;
    final fetching = _fetching;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(tr.posterCutoutModel, style: text.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in CutoutModel.values)
              ChoiceChip(
                avatar: m.downloaded ? null : const Icon(Icons.download_rounded, size: 16),
                label: Text(_modelName(m)),
                selected: _model == m,
                onSelected: _cutting || fetching != null ? null : (_) => _chooseModel(m),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (fetching != null) ...[
          Text(tr.posterModelDownloading(_modelName(fetching)), style: text.bodySmall),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: _fetched > 0 ? _fetched : null),
        ] else
          Text(switch (_model) {
            CutoutModel.builtIn => tr.posterModelBuiltInHint,
            CutoutModel.modnet => tr.posterModelModnetHint,
            CutoutModel.rmbg => tr.posterModelRmbgHint,
          }, style: text.bodySmall),
      ],
    );
  }

  /// The editor in a wide window (a side panel), set as it is laid out.
  bool _wide = false;

  /// A row of choices: a strip to scroll sideways on a phone, all of them in rows in a wide window's side panel.
  /// Choices in rows down the panel, centred on a phone: a phone's panel filled instead of one row scrolled sideways
  /// with room left empty under it.
  Widget _grid({required List<Widget> children}) => Wrap(
    spacing: 12,
    runSpacing: 10,
    alignment: _wide ? WrapAlignment.start : WrapAlignment.center,
    children: children,
  );

  Widget _row({required double height, required List<Widget> children}) => _wide
      ? Wrap(runSpacing: 10, children: children)
      : SizedBox(
          height: height,
          // Not cut off at the panel's margins: a row scrolled sideways runs on to the screen's edges.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            // A handful of choices: all built, not only those on screen.
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        );

  /// The side panel's sections folded away, by title.
  final _folded = <String>{};

  /// A Lightroom-style section: its name in small capitals with a chevron to fold it, its settings under it.
  Widget _section(String title, List<Widget> children, {List<Widget> actions = const []}) {
    final open = !_folded.contains(title);
    final text = Theme.of(context).textTheme;
    final quiet = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => open ? _folded.add(title) : _folded.remove(title)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
            child: Row(
              children: [
                Icon(open ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 16, color: quiet),
                const SizedBox(width: 8),
                Text(
                  title.toUpperCase(),
                  style: text.labelSmall?.copyWith(
                    fontSize: 11,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w600,
                    color: quiet,
                  ),
                ),
                const Spacer(),
                ...actions,
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 18, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ],
    );
  }

  /// A Lightroom slider: the name, the slider and the value on one line; a double click on the name sets it back to
  /// neutral.
  /// Whether the user's slider look is Classic: only then do the editor's sliders take a look of their own.
  bool get _classicSlider => LayoutPrefs.instance.volumeSlider == VolumeSliderShape.classic;

  Widget _lrSlider(_Knob k, {bool locked = false}) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final centred = k.neutral > k.min && !k.percent && !k.raw;
    final shown = k.shown;
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: GestureDetector(
              onDoubleTap: locked
                  ? null
                  : () => setState(() {
                      _remember();
                      k.set(k.neutral);
                    }),
              child: Text(
                k.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.9)),
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              // The look the user picked for sliders (Pill, Thin line) as anywhere else; Classic gets the slim one.
              data: !_classicSlider
                  ? SliderTheme.of(context)
                  : SliderTheme.of(context).copyWith(
                      trackHeight: 1.5,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5, elevation: 0, pressedElevation: 0),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: scheme.onSurface.withValues(alpha: 0.7),
                      inactiveTrackColor: scheme.outlineVariant.withValues(alpha: 0.6),
                      thumbColor: scheme.onSurface,
                    ),
              child: Slider(
                value: k.value.clamp(k.min, k.max),
                min: k.min,
                max: k.max,
                onChangeStart: (_) => _remember(),
                onChanged: locked ? null : (v) => setState(() => k.set(v)),
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              k.percent ? '$shown%' : (centred && shown > 0 ? '+$shown' : '$shown'),
              textAlign: TextAlign.end,
              style: text.bodySmall?.copyWith(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The photo's panel in a wide window: its source and zoom, the presets, then light, colour and effects.
  Widget _lightroomPhoto(List<_Knob> k) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _section(tr.posterSectionImage, [
          Text(
            _photo == null
                ? tr.posterStepPhoto
                : _cutting
                ? tr.posterFindingYou
                : _cutout == null
                ? tr.posterNoCutout
                : tr.posterFoundYou,
            style: text.bodySmall,
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: _cutting ? null : _pickPhoto,
            icon: Icon(_photo == null ? Icons.add_photo_alternate_outlined : Icons.swap_horiz_rounded),
            label: Text(_photo == null ? tr.choosePhoto : tr.posterReplacePhoto),
          ),
          if (_photo != null) ...[const SizedBox(height: 6), _lrSlider(k[0])],
          const SizedBox(height: 10),
          _modelChooser(),
        ]),
        if (_photo != null) ...[
          _section(tr.posterPresets, [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final filter in PhotoFilter.values)
                  ChoiceChip(
                    label: Text(filter.label),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() {
                      _remember();
                      _filter = filter;
                      _grade = filter.grade;
                    }),
                  ),
              ],
            ),
          ]),
          _section(tr.posterSectionLight, [_lrSlider(k[1]), _lrSlider(k[2]), _lrSlider(k[5])]),
          _section(tr.posterSectionColor, [_lrSlider(k[3]), _lrSlider(k[4])]),
          _section(tr.posterSectionEffects, [_lrSlider(k[6])]),
        ],
      ],
    );
  }

  /// A picked card's panel in a wide window: what it is and what can be done with it, then its transform, 3D and look.
  Widget _lightroomCard(PosterItem item, List<_Knob> k) {
    final text = Theme.of(context).textTheme;
    final locked = item.locked;
    return ListView(
      key: ObjectKey(item),
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
          child: Row(
            children: [
              Artwork(track: item.track, size: 40, radius: 8),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                    Text(
                      locked ? tr.posterLockedHint : item.track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              FilledButton(onPressed: () => setState(() => _selected = null), child: Text(tr.done)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                tooltip: tr.posterReplaceSong,
                onPressed: () => _replaceSong(item),
                icon: const Icon(Icons.swap_horiz_rounded),
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
                tooltip: tr.posterBackward,
                onPressed: () => _move(item, -1),
                icon: const Icon(Icons.flip_to_back_rounded),
              ),
              IconButton(
                tooltip: locked ? tr.posterUnlock : tr.posterLock,
                isSelected: locked,
                onPressed: () => setState(() {
                  _remember();
                  item.locked = !item.locked;
                }),
                icon: Icon(locked ? Icons.lock_rounded : Icons.lock_open_rounded),
              ),
              IconButton(
                tooltip: tr.remove,
                onPressed: () => _remove(item),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        _section(tr.posterSectionTransform, [_lrSlider(k[0], locked: locked), _lrSlider(k[1], locked: locked)]),
        _section(
          '3D',
          [_lrSlider(k[2], locked: locked), _lrSlider(k[3], locked: locked), _lrSlider(k[4], locked: locked)],
          actions: [
            TextButton(
              onPressed: locked
                  ? null
                  : () => setState(() {
                      _remember();
                      item
                        ..pitch = 0
                        ..yaw = 0;
                    }),
              child: Text(tr.posterFlat),
            ),
          ],
        ),
        _section(tr.posterSectionCard, [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final style in PosterCardStyle.values)
                ChoiceChip(
                  label: Text(switch (style) {
                    PosterCardStyle.light => tr.posterLight,
                    PosterCardStyle.dark => tr.posterDark,
                    PosterCardStyle.glass => tr.posterGlass,
                    PosterCardStyle.liquid => tr.styleLiquidGlass,
                    PosterCardStyle.cover => tr.posterCoverColour,
                  }),
                  selected: item.style == style,
                  onSelected: locked
                      ? null
                      : (_) => setState(() {
                          _remember();
                          item.style = _style = style;
                        }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _lrSlider(k[5], locked: locked),
          _lrSlider(k[6], locked: locked),
        ]),
      ],
    );
  }

  /// A short line saying what this step is for.
  Widget _say(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium,
      textAlign: _wide ? TextAlign.start : TextAlign.center,
    ),
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
      _Knob(Icons.zoom_in_rounded, tr.posterZoom, _photoZoom, 1, 4, (v) => _photoZoom = v, percent: true),
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
    if (_wide) return _lightroomPhoto(knobs);
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
            if (!_cutting) ...[const SizedBox(height: 12), _modelChooser()],
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
            _modelChooser(),
            const SizedBox(height: 10),
            // Colour: a filter in one tap, then a setting at a time.
            _row(
              height: 40,
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
            const SizedBox(height: 10),
            _adjuster(knobs, _photoKnob, (i) => setState(() => _photoKnob = i)),
          ],
        ],
      ),
    );
  }

  Widget _songsStep() {
    Widget tile({required Widget picture, required String label}) => SizedBox(
      width: 80,
      child: Column(
        children: [
          picture,
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _say(tr.posterStepSongs),
          _grid(
            children: [
              if (_items.length < PosterEditor.maxCards)
                tile(
                  picture: SizedBox.square(
                    dimension: 80,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _addSong,
                      child: const Icon(Icons.add_rounded, size: 30),
                    ),
                  ),
                  label: tr.posterAddSong,
                ),
              for (final item in _items)
                tile(
                  picture: Stack(
                    children: [
                      Artwork(track: item.track, size: 80, radius: 14),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => _remove(item),
                            child: Tooltip(
                              message: tr.remove,
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  label: item.track.title,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _layoutStep() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _say(_items.isEmpty ? tr.posterStepLayoutEmpty : tr.posterStepLayout),
      _row(
        height: 150,
        children: [
          for (final preset in PosterPreset.values)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 96,
                height: 150,
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
                        child: PosterPresetPreview(
                          preset: preset,
                          selected: preset == _preset,
                          poses: _preview(preset),
                          aspect: _shape.ratio,
                          photo: _photoShown ? _photo : null,
                          front: _personShown ? _cutout : null,
                          photoAt: _photoAt,
                          zoom: _photoZoom,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(preset.label, style: Theme.of(context).textTheme.labelLarge),
                    ],
                  ),
                ),
              ),
            ),
        ],
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
          _row(height: 182, children: [for (final s in PosterShape.values) tile(s)]),
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
    final shown = _layers.reversed.where((l) => l is! PosterPerson || _cutout != null).toList();
    final picked = _selected;
    Widget row(Object layer, {required int? index}) {
      final on = identical(layer, picked);
      final locked = switch (layer) {
        final PosterItem item => item.locked,
        final PosterDecoration d => d.locked,
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
        final PosterDecoration d => (
          Icon(d.kind.icon, color: d.colour, shadows: const [Shadow(blurRadius: 4)]),
          d.kind == DecorationKind.text && d.text.isNotEmpty ? d.text : tr.posterDecoration,
          tr.posterDecoration,
          d.visible,
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
                      case final PosterDecoration d:
                        d.visible = !d.visible;
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
                        case final PosterDecoration d:
                          d.locked = !d.locked;
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
      final PosterDecoration d => d.opacity,
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
              case final PosterDecoration d:
                d.opacity = v;
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
              if (picked is PosterItem || picked is PosterDecoration)
                IconButton(
                  tooltip: tr.posterDuplicate,
                  onPressed: () =>
                      picked is PosterItem ? _duplicate(picked) : _duplicateDecoration(picked as PosterDecoration),
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
              if (picked is PosterItem || picked is PosterDecoration)
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

  // Decorations ----------------------------------------------------------------------------------------------------

  /// [kind] added at the top of the poster's layers, picked, a little off the middle so a few added in a row don't
  /// pile up exactly; words are asked for first.
  Future<void> _addDecoration(DecorationKind kind) async {
    var text = '';
    if (kind == DecorationKind.text) {
      final typed = await _askText('');
      if (typed == null || typed.trim().isEmpty || !mounted) return;
      text = typed.trim();
    }
    setState(() {
      _remember();
      final d = PosterDecoration(
        kind,
        at: Offset(0.3 + _random.nextDouble() * 0.4, 0.15 + _random.nextDouble() * 0.2),
        scale: kind == DecorationKind.text ? 1 : 0.8 + _random.nextDouble() * 0.4,
        tilt: (kind == DecorationKind.text ? 0 : _random.nextDouble() - 0.5) * 0.5,
        text: text,
      );
      _layers.add(d);
      _selected = d;
    });
  }

  Future<String?> _askText(String start) => showDialog<String>(
    context: context,
    builder: (context) => _TextDialog(start: start),
  );

  void _duplicateDecoration(PosterDecoration d) => setState(() {
    _remember();
    final copy = d.copy()
      ..at = Offset((d.at.dx + 0.06).clamp(0.0, 1.0), (d.at.dy + 0.04).clamp(0.0, 1.0))
      ..locked = false;
    _layers.insert(_layers.indexOf(d) + 1, copy);
    _selected = copy;
  });

  /// Whether [d] is in front of the person (over their cut-out) rather than behind them.
  bool _inFront(PosterDecoration d) => _layers.indexOf(d) > _layers.indexOf(PosterPerson.layer);

  void _toggleFront(PosterDecoration d) => setState(() {
    _remember();
    final front = !_inFront(d);
    _layers.remove(d);
    final person = _layers.indexOf(PosterPerson.layer);
    _layers.insert(front ? person + 1 : person, d);
  });

  /// A decoration on the poster: dragged, pinched to size and turned with two fingers, as a card is.
  Widget _decoration(PosterDecoration d, Size size, double unit) {
    final selected = identical(d, _selected);
    return Positioned(
      left: d.at.dx * size.width,
      top: d.at.dy * size.height,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: IgnorePointer(
          ignoring: d.locked,
          child: Opacity(
            opacity: d.opacity,
            child: Transform.rotate(
              angle: d.tilt,
              child: Listener(
                onPointerDown: (e) => _touched(d, e.position),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _selected = d),
                  onScaleStart: (u) => _dragStart(d, u.focalPoint),
                  onScaleUpdate: (u) => _dragUpdate(d, u, size),
                  onScaleEnd: (_) => _dragEnd(),
                  child: Container(
                    padding: EdgeInsets.all(8 * unit),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10 * unit),
                      border: selected ? Border.all(color: Colors.white, width: 2) : null,
                    ),
                    child: MouseRegion(
                      cursor: _dragging && selected ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
                      child: PosterDecorationView(decoration: d, unit: unit),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Decorations to add, a tap each: words first, then the drawings; in a row a phone scrolls sideways.
  Widget _decorStep() {
    Widget choice(DecorationKind kind) => IconButton.filledTonal(
      tooltip: kind == DecorationKind.text ? tr.posterAddText : tr.posterDecoration,
      iconSize: 26,
      style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
      onPressed: () => _addDecoration(kind),
      icon: Icon(kind.icon),
    );
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _say(tr.posterStepDecor),
          _grid(
            children: [
              choice(DecorationKind.text),
              for (final kind in DecorationKind.values)
                if (kind != DecorationKind.text) choice(kind),
            ],
          ),
        ],
      ),
    );
  }

  /// A picked decoration's controls: what can be done with it, its colour, then its size, turn and opacity.
  Widget _decorationControls(PosterDecoration d) {
    final text = Theme.of(context).textTheme;
    final locked = d.locked;
    final knobs = [
      _Knob(Icons.open_in_full_rounded, tr.posterSize, d.scale, 0.2, 6, (v) => d.scale = v, neutral: 1, percent: true),
      _Knob(Icons.rotate_right_rounded, tr.posterRotate, d.tilt, -math.pi, math.pi, (v) => d.tilt = v, neutral: 0),
      _Knob(Icons.opacity_rounded, tr.posterOpacity, d.opacity, 0, 1, (v) => d.opacity = v, neutral: 1, percent: true),
    ];
    final front = _inFront(d);
    return ListView(
      key: ObjectKey(d),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      children: [
        Row(
          children: [
            Icon(d.kind.icon, color: d.colour, shadows: const [Shadow(blurRadius: 4)]),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                d.kind == DecorationKind.text ? d.text : tr.posterDecoration,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall,
              ),
            ),
            FilledButton(onPressed: () => setState(() => _selected = null), child: Text(tr.done)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            if (d.kind == DecorationKind.text)
              IconButton(
                tooltip: tr.posterEditText,
                onPressed: () async {
                  final typed = await _askText(d.text);
                  if (typed == null || typed.trim().isEmpty || !mounted) return;
                  setState(() {
                    _remember();
                    d.text = typed.trim();
                  });
                },
                icon: const Icon(Icons.edit_rounded),
              ),
            if (_cutout != null)
              IconButton(
                tooltip: front ? tr.posterBehind : tr.posterInFront,
                isSelected: front,
                onPressed: () => _toggleFront(d),
                icon: Icon(front ? Icons.person_rounded : Icons.person_outline_rounded),
              ),
            IconButton(
              tooltip: tr.posterDuplicate,
              onPressed: () => _duplicateDecoration(d),
              icon: const Icon(Icons.copy_rounded),
            ),
            IconButton(
              tooltip: locked ? tr.posterUnlock : tr.posterLock,
              isSelected: locked,
              onPressed: () => setState(() {
                _remember();
                d.locked = !d.locked;
              }),
              icon: Icon(locked ? Icons.lock_rounded : Icons.lock_open_rounded),
            ),
            IconButton(tooltip: tr.remove, onPressed: () => _remove(d), icon: const Icon(Icons.delete_outline_rounded)),
          ],
        ),
        const SizedBox(height: 4),
        Text(tr.posterColour, style: text.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in decorationColours)
              Semantics(
                button: true,
                selected: d.colour.toARGB32() == c.toARGB32(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: locked
                      ? null
                      : () => setState(() {
                          _remember();
                          d.colour = c;
                        }),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: d.colour.toARGB32() == c.toARGB32()
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                        width: d.colour.toARGB32() == c.toARGB32() ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final k in knobs) _lrSlider(k, locked: locked),
      ],
    );
  }

  // A picked card ------------------------------------------------------------------------------------------------

  /// A card's controls: its settings a pill at a time, its look, and what can be done with it; Done back to the
  /// steps.
  Widget _cardControls(PosterItem item) {
    final knobs = [
      _Knob(
        Icons.open_in_full_rounded,
        tr.posterSize,
        item.scale,
        0.3,
        2.5,
        (v) => item.scale = v,
        neutral: 1,
        percent: true,
      ),
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
      _Knob(Icons.view_in_ar_rounded, tr.posterThickness, item.depth, 0, 20, (v) => item.depth = v, raw: true),
      _Knob(Icons.linear_scale_rounded, tr.posterProgress, item.progress, 0, 1, (v) => item.progress = v),
      _Knob(Icons.opacity_rounded, tr.posterOpacity, item.opacity, 0.1, 1, (v) => item.opacity = v, percent: true),
    ];
    if (_wide) return _lightroomCard(item, knobs);
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
                  tooltip: tr.posterReplaceSong,
                  onPressed: () => _replaceSong(item),
                  icon: const Icon(Icons.swap_horiz_rounded),
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
            _row(
              height: 40,
              children: [
                for (final style in PosterCardStyle.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(switch (style) {
                        PosterCardStyle.light => tr.posterLight,
                        PosterCardStyle.dark => tr.posterDark,
                        PosterCardStyle.glass => tr.posterGlass,
                        PosterCardStyle.liquid => tr.styleLiquidGlass,
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

/// Words for a decoration, typed in a dialog that owns its field (disposed with it, once its closing has played out).
class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.start});

  final String start;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _field = TextEditingController(text: widget.start);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.start.isEmpty ? tr.posterAddText : tr.posterEditText),
    content: TextField(
      controller: _field,
      autofocus: true,
      maxLines: 3,
      minLines: 1,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(hintText: tr.posterTextHint),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr.cancel)),
      FilledButton(onPressed: () => Navigator.of(context).pop(_field.text), child: Text(tr.done)),
    ],
  );
}
