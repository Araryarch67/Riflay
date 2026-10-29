import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/color_tools.dart';
import '../theme.dart';

/// A small colour picker: hue, a saturation / brightness square and a hex field. Returns the colour
/// picked, or null when cancelled.
Future<Color?> showColorPicker(BuildContext context, {required String title, required Color initial}) =>
    showDialog<Color>(
      context: context,
      builder: (_) => _ColorPickerDialog(title: title, initial: initial),
    );

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.title, required this.initial});

  final String title;
  final Color initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final _hex = TextEditingController(text: hexOf(widget.initial));

  /// A colour typed in as hex, kept exactly (going through hue and brightness can be off by one).
  Color? _typed;

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _set(HSVColor v) {
    setState(() {
      _hsv = v;
      _typed = null;
    });
    _hex.value = TextEditingValue(text: hexOf(v.toColor()));
  }

  @override
  Widget build(BuildContext context) {
    final color = _typed ?? _hsv.toColor();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SaturationBrightness(hsv: _hsv, onChanged: _set),
            const SizedBox(height: 14),
            _HueBar(hue: _hsv.hue, onChanged: (h) => _set(_hsv.withHue(h))),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    'Aa',
                    style: TextStyle(color: onColorFor(color), fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _hex,
                    maxLength: 7,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[#0-9a-fA-F]'))],
                    decoration: const InputDecoration(
                      labelText: 'Hex',
                      counterText: '',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (t) {
                      final c = parseHex(t);
                      if (c != null) {
                        setState(() {
                          _hsv = HSVColor.fromColor(c);
                          _typed = c;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, color), child: const Text('Use this colour')),
      ],
    );
  }
}

/// The square: saturation across, brightness down.
class _SaturationBrightness extends StatelessWidget {
  const _SaturationBrightness({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const height = 160.0;
        final width = c.maxWidth;
        void pick(Offset p) => onChanged(
          hsv.withSaturation((p.dx / width).clamp(0.0, 1.0)).withValue((1 - p.dy / height).clamp(0.0, 1.0)),
        );
        return Semantics(
          label: 'Saturation and brightness',
          child: GestureDetector(
            onPanDown: (d) => pick(d.localPosition),
            onPanUpdate: (d) => pick(d.localPosition),
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: LinearGradient(colors: [Colors.white, HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()]),
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: hsv.saturation * width - 9,
                    top: (1 - hsv.value) * height - 9,
                    child: IgnorePointer(
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hsv.toColor(),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
                        ),
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
  }
}

/// The hue bar: the spectrum with a thumb.
class _HueBar extends StatelessWidget {
  const _HueBar({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        void pick(Offset p) => onChanged((p.dx / width).clamp(0.0, 1.0) * 359.99);
        return Semantics(
          label: 'Hue',
          child: GestureDetector(
            onPanDown: (d) => pick(d.localPosition),
            onPanUpdate: (d) => pick(d.localPosition),
            child: SizedBox(
              width: width,
              height: 20,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: LinearGradient(
                          colors: [
                            for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: hue / 359.99 * width - 10,
                    child: IgnorePointer(
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
                        ),
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
  }
}
