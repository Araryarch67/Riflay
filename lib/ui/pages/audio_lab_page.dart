import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/audio_engine.dart';
import '../../services/audio_lab.dart';
import '../../services/auto_eq.dart';
import '../../services/language.dart';
import '../../services/player_controller.dart';
import '../theme.dart';
import '../widgets/frosted.dart';
import '../widgets/menus.dart';

/// Opens the audio lab over whatever is showing (Settings or the expanded player's side panel).
Future<void> openAudioLab(BuildContext context) {
  final c = PlayerScope.read(context);
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlayerScope(controller: c, child: const AudioLabPage()),
    ),
  );
}

enum _Source { autoEq, squig, file }

/// A headphone's measured response, a target, and the equalizer itself, on one graph: the equalizer's bands are
/// points on it to drag, live as the music plays, or fitted to the target in one tap. Riflay's take on a squig.link
/// page with AutoEQ and a parametric equalizer in it.
class AudioLabPage extends StatefulWidget {
  const AudioLabPage({super.key});

  @override
  State<AudioLabPage> createState() => _AudioLabPageState();
}

AutoEqFit _fitIn((List<double>, List<double>) pair) => AudioLab.fitBands(pair.$1, pair.$2);

class _AudioLabPageState extends State<AudioLabPage> {
  static const _siteKey = 'lab.squigSite';

  var _source = _Source.autoEq;
  final _site = TextEditingController(text: AudioLab.squigSites.first.url);
  Future<({List<LabCurve> phones, List<LabCurve> targets})>? _squig;
  String? _squigFor;
  Future<List<AutoEqEntry>>? _autoEq;
  List<LabCurve> _siteTargets = const [];

  /// The headphone (its name, where it came from, its kind), levelled, once loaded.
  String? _name;
  String? _from;
  bool? _inEar;
  List<double>? _headphone;

  /// The target (none: the equalizer alone), levelled, and how it is adjusted.
  LabCurve? _target;
  List<double>? _targetCurve;
  double _bass = 0, _tilt = 0;

  /// The band picked on the graph, and the bands while one is dragged (sent to the equalizer a few times a second).
  int _picked = 0;
  List<EqBand>? _draft;
  Timer? _send;

  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(
      SharedPreferences.getInstance().then((p) {
        final site = p.getString(_siteKey);
        if (site != null && mounted) setState(() => _site.text = site);
      }),
    );
  }

  @override
  void dispose() {
    _send?.cancel();
    _site.dispose();
    super.dispose();
  }

  AudioEngine get _audio => PlayerScope.read(context).audio;

  List<LabCurve> get _targets =>
      {if (_source == _Source.squig) ..._siteTargets, ...AudioLab.targets, ?_target}.toList();

  List<double>? get _shownTarget =>
      _targetCurve == null ? null : AudioLab.adjusted(_targetCurve!, bass: _bass, tilt: _tilt);

  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } catch (e) {
      debugPrint('Audio lab: ${e.runtimeType}');
      if (mounted) setState(() => _error = tr.labLoadFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useHeadphone(LabCurve c) => _run(() async {
    final fr = await AudioLab.load(c);
    if (!mounted) return;
    final first = _headphone == null;
    setState(() {
      _name = c.name;
      _from = c.source;
      _inEar = c.inEar;
      _headphone = AudioLab.level(fr);
    });
    // The first headphone gets a target: its site's Harman one, else Harman's for its kind.
    if (first && _target == null) {
      final own = _targets.where((t) => t.source == c.source && t.name.toLowerCase().contains('harman'));
      await _loadTarget(own.isNotEmpty ? own.first : AudioLab.defaultTarget(c));
    }
  });

  Future<void> _loadTarget(LabCurve? t) async {
    final curve = t == null ? null : AudioLab.level(await AudioLab.load(t));
    if (!mounted) return;
    setState(() {
      _target = t;
      _targetCurve = curve;
    });
  }

  Future<void> _pickFile() async {
    final file = (await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'csv'],
      dialogTitle: tr.labChooseFile,
    )).firstOrNull;
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await _run(() async {
      final fr = AudioLab.parse(utf8.decode(bytes, allowMalformed: true));
      if (fr.freqs.length < 8) throw const FormatException('no response in the file');
      setState(() {
        _name = file.name.replaceAll(RegExp(r'\.(txt|csv)$', caseSensitive: false), '');
        _from = tr.labSourceFile;
        _inEar = null;
        _headphone = AudioLab.level(fr);
      });
    });
  }

  Future<void> _pickHeadphone() async {
    final picked = await _pickFromList();
    if (picked != null) await _useHeadphone(picked);
  }

  /// Another headphone's response as the target: this one tuned to sound like it.
  Future<void> _pickTargetHeadphone() async {
    final picked = await _pickFromList();
    if (picked != null) await _run(() => _loadTarget(picked));
  }

  /// A measurement picked from the source's list (AutoEQ's, or the squig.link site's), loading the list first.
  Future<LabCurve?> _pickFromList() async {
    final List<LabCurve> items;
    try {
      setState(() {
        _busy = true;
        _error = null;
      });
      if (_source == _Source.squig) {
        final site = _site.text.trim();
        unawaited(SharedPreferences.getInstance().then((p) => p.setString(_siteKey, site)));
        if (_squigFor != site) {
          _squig = AudioLab.squig(site);
          _squigFor = site;
        }
        final data = await _squig!;
        items = data.phones;
        if (mounted) setState(() => _siteTargets = data.targets);
      } else {
        _autoEq ??= AutoEq.index();
        items = [for (final e in await _autoEq!) AudioLab.fromAutoEq(e)];
      }
    } catch (e) {
      debugPrint('Audio lab list: ${e.runtimeType}');
      if (mounted) {
        setState(() {
          _error = tr.labLoadFailed;
          _squig = null;
          _squigFor = null;
          _autoEq = null;
        });
      }
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return null;
    return showAppSheet<LabCurve>(
      context: context,
      backgroundColor: AppColors.elevated,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _PickSheet(items: items),
    );
  }

  // The equalizer --------------------------------------------------------------------------------------------------

  /// [i] set to [band], drawn at once and sent to the equalizer a few times a second while it moves.
  void _edit(int i, EqBand band) {
    final bands = [...(_draft ?? _audio.bands)]..[i] = band;
    setState(() => _draft = bands);
    _send ??= Timer(const Duration(milliseconds: 90), () => unawaited(_flush()));
  }

  Future<void> _flush() async {
    _send?.cancel();
    _send = null;
    final bands = _draft;
    if (bands == null) return;
    final audio = _audio;
    if (!audio.eqEnabled) await audio.setEqEnabled(true);
    for (var i = 0; i < bands.length && i < audio.bands.length; i++) {
      final now = audio.bands[i], want = bands[i];
      if (now.frequency != want.frequency || now.gain != want.gain || now.q != want.q) await audio.setBand(i, want);
    }
  }

  Future<void> _settle() async {
    await _flush();
    if (mounted) setState(() => _draft = null);
  }

  Future<void> _fitToTarget() async {
    final hp = _headphone, tg = _shownTarget;
    if (hp == null || tg == null) return;
    setState(() => _busy = true);
    final fit = await compute(_fitIn, (hp, tg));
    if (!mounted) return;
    final name = '${_name ?? tr.labHeadphone} → ${_target?.name ?? ''}';
    await _audio.applyEqProfile(name, fit.bands);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _draft = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.labApplied(name))));
  }

  @override
  Widget build(BuildContext context) {
    final audio = PlayerScope.of(context).audio;
    return ListenableBuilder(listenable: audio, builder: (context, _) => _page(context, audio));
  }

  /// A section of the lab: a rounded tonal card, its icon in a tonal circle beside its title, [trailing] at the end.
  Widget _card({required IconData icon, required String title, Widget? trailing, required List<Widget> children}) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: scheme.secondaryContainer,
                  foregroundColor: scheme.onSecondaryContainer,
                  child: Icon(icon, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _page(BuildContext context, AudioEngine audio) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final small = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final bands = _draft ?? audio.bands;
    _picked = _picked.clamp(0, bands.length - 1);
    // The bands' curve is drawn either way (faint while the equalizer is off); what the headphone becomes counts it
    // only while it is on.
    final applied = audio.eqEnabled || _draft != null;
    final curve = AudioLab.response(bands);
    final eq = applied ? curve : List.filled(curve.length, 0.0);
    final hp = _headphone, tg = _shownTarget;
    final colours = (headphone: scheme.primary, target: scheme.outline, after: scheme.tertiary, eq: scheme.secondary);
    var worst = 0.0;
    if (hp != null && tg != null) {
      for (var i = 0; i < hp.length; i++) {
        if (AutoEq.fitFrequencies[i] <= 10000) worst = math.max(worst, (hp[i] + eq[i] - tg[i]).abs());
      }
    }
    final locked = audio.bitPerfect;
    final band = bands[_picked];
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final graph = _card(
      icon: Icons.show_chart_rounded,
      title: _name ?? tr.labResponse,
      trailing: IconButton.filledTonal(
        tooltip: tr.labExport,
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: AudioLab.parametricText(bands)));
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.labCopied)));
        },
        icon: const Icon(Icons.content_copy_rounded),
      ),
      children: [
        AspectRatio(
          aspectRatio: wide ? 2 : 1.45,
          child: DecoratedBox(
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 14, 6),
              child: _Graph(
                headphone: hp,
                target: tg,
                eq: eq,
                curve: curve,
                applied: applied,
                bands: bands,
                picked: _picked,
                colours: colours,
                grid: scheme.outlineVariant,
                label: text.labelSmall!.copyWith(color: scheme.onSurfaceVariant),
                enabled: !locked,
                onPick: (i) => setState(() => _picked = i),
                onMove: _edit,
                onEnd: () => unawaited(_settle()),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            if (hp != null) _Legend(colour: colours.headphone, label: _name ?? tr.labHeadphone),
            if (tg != null) _Legend(colour: colours.target, label: _target!.name),
            if (hp != null) _Legend(colour: colours.after, label: tr.labWithEq),
            _Legend(colour: colours.eq, label: tr.equalizer),
          ],
        ),
        const SizedBox(height: 8),
        Text(hp != null && tg != null ? tr.labGap(worst.toStringAsFixed(1)) : tr.labDragHint, style: small),
        if (_error case final error?) ...[
          const SizedBox(height: 8),
          Text(error, style: muted?.copyWith(color: scheme.error)),
        ],
      ],
    );

    final equalizer = _card(
      icon: Icons.equalizer_rounded,
      title: tr.equalizer,
      trailing: Switch(value: audio.eqEnabled, onChanged: locked ? null : (v) => audio.setEqEnabled(v)),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < bands.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(_hz(bands[i].frequency)),
                    selected: i == _picked,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _picked = i),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _Knob(
          label: tr.labFrequency,
          value: math.log(band.frequency / 20) / math.log(1000),
          shown: '${_hz(band.frequency)}Hz',
          enabled: !locked,
          onChanged: (t) => _edit(_picked, band.copyWith(frequency: (20 * math.pow(1000, t)).roundToDouble())),
          onEnd: () => unawaited(_settle()),
        ),
        _Knob(
          label: tr.labGain,
          value: (band.gain + 12) / 24,
          shown: '${band.gain > 0 ? '+' : ''}${band.gain.toStringAsFixed(1)} dB',
          enabled: !locked,
          onChanged: (t) => _edit(_picked, band.copyWith(gain: ((t * 24 - 12) * 10).roundToDouble() / 10)),
          onEnd: () => unawaited(_settle()),
        ),
        _Knob(
          label: 'Q',
          value: math.log(band.q / 0.3) / math.log(8 / 0.3),
          shown: band.q.toStringAsFixed(2),
          enabled: !locked,
          onChanged: (t) => _edit(_picked, band.copyWith(q: (0.3 * math.pow(8 / 0.3, t) * 100).roundToDouble() / 100)),
          onEnd: () => unawaited(_settle()),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: hp == null || tg == null || _busy || locked ? null : _fitToTarget,
                icon: const Icon(Icons.auto_fix_high_rounded),
                label: Text(tr.labFitTarget),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(onPressed: locked ? null : () => audio.applyPreset('Flat'), child: Text(tr.reset)),
          ],
        ),
      ],
    );

    final headphone = _card(
      icon: Icons.headphones_rounded,
      title: tr.labHeadphone,
      children: [
        SegmentedButton<_Source>(
          segments: [
            const ButtonSegment(value: _Source.autoEq, label: Text('AutoEQ')),
            const ButtonSegment(value: _Source.squig, label: Text('squig.link')),
            ButtonSegment(value: _Source.file, label: Text(tr.labSourceFile)),
          ],
          selected: {_source},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _source = s.first),
        ),
        const SizedBox(height: 12),
        if (_source == _Source.squig) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final site in AudioLab.squigSites)
                ChoiceChip(
                  label: Text(site.name),
                  selected: _site.text.trim() == site.url,
                  onSelected: _busy
                      ? null
                      : (_) {
                          setState(() => _site.text = site.url);
                          unawaited(_pickHeadphone());
                        },
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _site,
            decoration: InputDecoration(
              labelText: tr.labSite,
              hintText: 'name.squig.link',
              filled: true,
              isDense: true,
              prefixIcon: const Icon(Icons.public_rounded),
            ),
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => unawaited(_pickHeadphone()),
          ),
          const SizedBox(height: 12),
        ],
        Material(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: Icon(_source == _Source.file ? Icons.upload_file_rounded : Icons.search_rounded),
            title: Text(_name ?? (_source == _Source.file ? tr.labChooseFile : tr.labPick)),
            subtitle: _from == null ? null : Text(_from!, style: small),
            trailing: _busy
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right_rounded),
            onTap: _busy ? null : () => unawaited(_source == _Source.file ? _pickFile() : _pickHeadphone()),
          ),
        ),
      ],
    );

    final target = _card(
      icon: Icons.adjust_rounded,
      title: tr.labTarget,
      children: [
        LayoutBuilder(
          // As wide as the card lets it be: the pill's own padding and arrow take about fifty points.
          builder: (context, box) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: OptionPicker<LabCurve?>(
              value: _target,
              maxWidth: math.max(80, box.maxWidth - 56),
              options: [(null, tr.labNone), for (final t in _targets) (t, '${t.name} · ${t.source}')],
              onChanged: _busy ? null : (t) => unawaited(_run(() => _loadTarget(t))),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonalIcon(
            onPressed: _busy || _source == _Source.file ? null : () => unawaited(_pickTargetHeadphone()),
            icon: const Icon(Icons.compare_arrows_rounded),
            label: Text(tr.labTargetHeadphone),
          ),
        ),
        if (_inEar != null && _target?.inEar != null && _target!.inEar != _inEar) ...[
          const SizedBox(height: 8),
          Text(tr.labKindMismatch, style: small),
        ],
        if (_target != null) ...[
          const SizedBox(height: 8),
          _Knob(
            label: tr.labBass,
            value: (_bass + 6) / 18,
            shown: '${_bass > 0 ? '+' : ''}${_bass.toStringAsFixed(1)} dB',
            enabled: true,
            onChanged: (t) => setState(() => _bass = ((t * 18 - 6) * 2).roundToDouble() / 2),
          ),
          _Knob(
            label: tr.labTilt,
            value: (_tilt + 1.5) / 3,
            shown: '${_tilt > 0 ? '+' : ''}${_tilt.toStringAsFixed(1)} dB/oct',
            enabled: true,
            onChanged: (t) => setState(() => _tilt = ((t * 3 - 1.5) * 10).roundToDouble() / 10),
          ),
        ],
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text(tr.audioLab)),
      body: SafeArea(
        child: LayoutBuilder(
          // The list as wide as the window, its content centred by its padding: the wheel scrolls it anywhere on the
          // page, the margins beside the content too.
          builder: (context, box) => ListView(
            padding: EdgeInsets.fromLTRB(
              math.max(16, (box.maxWidth - 1100) / 2),
              0,
              math.max(16, (box.maxWidth - 1100) / 2),
              32,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                child: Text(tr.audioLabSubtitle, style: muted),
              ),
              graph,
              const SizedBox(height: 12),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: equalizer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [headphone, const SizedBox(height: 12), target],
                      ),
                    ),
                  ],
                )
              else ...[
                equalizer,
                const SizedBox(height: 12),
                headphone,
                const SizedBox(height: 12),
                target,
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 20, 4, 0),
                child: Text(tr.labCredits, style: small),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _hz(double f) => f >= 1000 ? '${(f / 1000).toStringAsFixed(f >= 10000 ? 0 : 1)}k' : f.round().toString();

/// A setting on one line: its name, a slider over 0–1, and its value as shown.
class _Knob extends StatelessWidget {
  const _Knob({
    required this.label,
    required this.value,
    required this.shown,
    required this.enabled,
    required this.onChanged,
    this.onEnd,
  });

  final String label, shown;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final VoidCallback? onEnd;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 92, child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
      Expanded(
        child: Slider(
          value: value.clamp(0, 1),
          onChanged: enabled ? onChanged : null,
          onChangeEnd: onEnd == null ? null : (_) => onEnd!(),
        ),
      ),
      SizedBox(
        width: 92,
        child: Text(
          shown,
          textAlign: TextAlign.end,
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ),
    ],
  );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.colour, required this.label});

  final Color colour;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 3,
        decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(width: 6),
      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
    ],
  );
}

typedef _Colours = ({Color headphone, Color target, Color after, Color eq});

/// The graph, with the bands' points: tap near one to pick it, drag it to move it (sideways the frequency, up and
/// down the gain), Ctrl and the mouse wheel to narrow or widen it.
class _Graph extends StatelessWidget {
  const _Graph({
    required this.headphone,
    required this.target,
    required this.eq,
    required this.curve,
    required this.applied,
    required this.bands,
    required this.picked,
    required this.colours,
    required this.grid,
    required this.label,
    required this.enabled,
    required this.onPick,
    required this.onMove,
    required this.onEnd,
  });

  final List<double>? headphone, target;
  final List<double> eq, curve;
  final bool applied;
  final List<EqBand> bands;
  final int picked;
  final _Colours colours;
  final Color grid;
  final TextStyle label;
  final bool enabled;
  final ValueChanged<int> onPick;
  final void Function(int, EqBand) onMove;
  final VoidCallback onEnd;

  static const left = 34.0, bottom = 18.0, top = 15.0, floor = -20.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final plot = Rect.fromLTRB(left, 0, box.maxWidth, box.maxHeight - bottom);
      double x(double f) => plot.left + plot.width * math.log(f / 20) / math.log(1000);
      double y(double db) => plot.top + plot.height * (top - db.clamp(floor, top)) / (top - floor);
      double freqAt(double dx) => (20 * math.pow(1000, ((dx - plot.left) / plot.width).clamp(0.0, 1.0))).toDouble();
      double gainAt(double dy) => (top - (dy - plot.top) / plot.height * (top - floor)).clamp(-12.0, 12.0);
      int nearest(Offset p) {
        var best = 0;
        var bestD = double.infinity;
        for (var i = 0; i < bands.length; i++) {
          final d = (Offset(x(bands[i].frequency), y(bands[i].gain)) - p).distance;
          if (d < bestD) {
            bestD = d;
            best = i;
          }
        }
        return best;
      }

      // How near a point a touch must start to take it: elsewhere the touch scrolls the page.
      bool near(Offset global) {
        final at = (context.findRenderObject()! as RenderBox).globalToLocal(global);
        return bands.any((b) => (Offset(x(b.frequency), y(b.gain)) - at).distance < 32);
      }

      return Listener(
        // Ctrl and the wheel narrow or widen the picked band; the wheel alone scrolls the page, as anywhere else.
        onPointerSignal: (e) {
          if (!enabled || e is! PointerScrollEvent || !HardwareKeyboard.instance.isControlPressed) return;
          GestureBinding.instance.pointerSignalResolver.register(e, (e) {
            final b = bands[picked];
            final q = (b.q * math.exp(-(e as PointerScrollEvent).scrollDelta.dy / 800)).clamp(0.3, 8.0);
            onMove(picked, b.copyWith(q: (q * 100).roundToDouble() / 100));
            onEnd();
          });
        },
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            if (enabled) ...{
              // A tap anywhere picks the nearest band.
              TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                TapGestureRecognizer.new,
                (r) => r.onTapUp = (d) => onPick(nearest(d.localPosition)),
              ),
              // A drag started on a point is taken at once (in the scrolling page a drag up or down had been the
              // page's scroll); one started anywhere else is left to the page.
              _PointRecognizer: GestureRecognizerFactoryWithHandlers<_PointRecognizer>(
                () => _PointRecognizer(near),
                (r) => r
                  ..near = near
                  ..onStart = (global) {
                    final box = context.findRenderObject()! as RenderBox;
                    final index = nearest(box.globalToLocal(global));
                    onPick(index);
                    return _PointDrag(
                      onUpdate: (global) {
                        final at = box.globalToLocal(global);
                        final b = bands[index];
                        onMove(
                          index,
                          b.copyWith(
                            frequency: freqAt(at.dx).roundToDouble(),
                            gain: (gainAt(at.dy) * 10).roundToDouble() / 10,
                          ),
                        );
                      },
                      onEnd: onEnd,
                    );
                  },
              ),
            },
          },
          child: MouseRegion(
            cursor: enabled ? SystemMouseCursors.precise : MouseCursor.defer,
            child: CustomPaint(
              size: box.biggest,
              painter: _GraphPainter(graph: this, plot: plot, x: x, y: y),
            ),
          ),
        ),
      );
    },
  );
}

/// Drags that start on a band's point only.
class _PointRecognizer extends ImmediateMultiDragGestureRecognizer {
  _PointRecognizer(this.near);

  bool Function(Offset global) near;

  @override
  bool isPointerAllowed(PointerDownEvent event) => near(event.position) && super.isPointerAllowed(event);
}

/// One finger dragging a band's point.
class _PointDrag extends Drag {
  _PointDrag({required this.onUpdate, required this.onEnd});

  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;

  @override
  void update(DragUpdateDetails details) => onUpdate(details.globalPosition);

  @override
  void end(DragEndDetails details) => onEnd();

  @override
  void cancel() => onEnd();
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({required this.graph, required this.plot, required this.x, required this.y});

  final _Graph graph;
  final Rect plot;
  final double Function(double) x, y;

  @override
  void paint(Canvas canvas, Size size) {
    final g = graph;
    final line = Paint()..strokeWidth = 1;
    void write(String s, Offset at, {bool right = false}) {
      final p = TextPainter(
        text: TextSpan(text: s, style: g.label),
        textDirection: TextDirection.ltr,
      )..layout();
      p.paint(canvas, at - Offset(right ? p.width : p.width / 2, p.height / 2));
    }

    for (var db = _Graph.floor; db <= _Graph.top; db += 5) {
      canvas.drawLine(
        Offset(plot.left, y(db)),
        Offset(plot.right, y(db)),
        line..color = db == 0 ? g.grid : g.grid.withValues(alpha: 0.4),
      );
      write('${db > 0 ? '+' : ''}${db.round()}', Offset(_Graph.left - 6, y(db)), right: true);
    }
    for (final (f, name) in const [
      (20.0, '20'),
      (50.0, '50'),
      (100.0, '100'),
      (200.0, '200'),
      (500.0, '500'),
      (1000.0, '1k'),
      (2000.0, '2k'),
      (5000.0, '5k'),
      (10000.0, '10k'),
      (20000.0, '20k'),
    ]) {
      canvas.drawLine(Offset(x(f), plot.top), Offset(x(f), plot.bottom), line..color = g.grid.withValues(alpha: 0.4));
      write(name, Offset(x(f).clamp(plot.left + 8, plot.right - 10), size.height - _Graph.bottom / 2));
    }
    canvas.save();
    canvas.clipRect(plot.inflate(8));
    final freqs = AutoEq.fitFrequencies;
    void curve(List<double> db, Color colour, double width) {
      final path = Path();
      for (var i = 0; i < freqs.length; i++) {
        final p = Offset(x(freqs[i]), y(db[i]));
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeJoin = StrokeJoin.round,
      );
    }

    if (g.target case final t?) curve(t, g.colours.target, 2);
    if (g.headphone case final h?) {
      curve(h, g.colours.headphone.withValues(alpha: 0.85), 2);
      curve([for (var i = 0; i < h.length; i++) h[i] + g.eq[i]], g.colours.after, 2.5);
    }
    curve(g.curve, g.colours.eq.withValues(alpha: g.applied ? 0.95 : 0.35), 1.5);
    // The bands' points, the picked one bigger and ringed.
    for (var i = 0; i < g.bands.length; i++) {
      final b = g.bands[i];
      final at = Offset(x(b.frequency), y(b.gain));
      final on = i == g.picked;
      canvas.drawCircle(at, on ? 8 : 5, Paint()..color = g.colours.eq.withValues(alpha: g.enabled ? 1 : 0.4));
      if (on) {
        canvas.drawCircle(
          at,
          12,
          Paint()
            ..color = g.colours.eq
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GraphPainter old) => true;
}

/// A searchable list of measurements.
class _PickSheet extends StatefulWidget {
  const _PickSheet({required this.items});

  final List<LabCurve> items;

  @override
  State<_PickSheet> createState() => _PickSheetState();
}

class _PickSheetState extends State<_PickSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary);
    final words = _query.text.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final found = words.isEmpty
        ? widget.items.take(200).toList()
        : widget.items
              .where((c) {
                final name = c.name.toLowerCase();
                return words.every(name.contains);
              })
              .take(200)
              .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                controller: _query,
                autofocus: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: tr.autoEqSearch,
                  helperText: tr.autoEqModels(widget.items.length),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: found.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(tr.autoEqNoResults, style: muted),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                      itemCount: found.length,
                      itemBuilder: (context, i) => ListTile(
                        title: Text(found[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(found[i].source, style: muted),
                        onTap: () => Navigator.pop(context, found[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
