import 'package:flutter/material.dart';

import '../../services/appearance.dart';
import '../../services/beta_features.dart';
import '../../services/layout_prefs.dart';
import '../widgets/menus.dart';
import 'sound_settings.dart';

class BetaSettings extends StatelessWidget {
  const BetaSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final beta = BetaFeatures.instance;
    final layout = LayoutPrefs.instance;
    final look = Appearance.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([beta, layout, look]),
      builder: (context, _) => SettingsCard(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.graphic_eq_rounded),
            title: const Text('Audio visualizer'),
            subtitle: Text(BetaFeature.audioVisualizer.description),
            value: beta.isOn(BetaFeature.audioVisualizer),
            onChanged: (on) async {
              // Save the decoration before opening the native analysis gate.
              await layout.setVisualizer(on);
              await beta.set(BetaFeature.audioVisualizer, on);
            },
          ),
          if (beta.isOn(BetaFeature.audioVisualizer)) ...[
            SettingTile(
              icon: Icons.multiline_chart_rounded,
              title: const Text('Visualizer style'),
              subtitle: const Text('Paused for bit-perfect audio and reduced motion'),
              control: OptionPicker<VisualizerStyle>(
                value: layout.visualizerStyle,
                onChanged: layout.setVisualizerStyle,
                options: [for (final style in VisualizerStyle.values) (style, style.label)],
              ),
            ),
            if (layout.visualizerStyle.radial) ...[
              SettingTile(
                icon: Icons.open_in_full_rounded,
                title: const Text('Radius movement'),
                subtitle: Text(
                  '${(layout.visualizerRadius * 100).round()}% · How far the shape expands with the music',
                ),
                control: SizedBox(
                  width: 220,
                  child: Slider(
                    value: layout.visualizerRadius,
                    min: 0.5,
                    max: 2.5,
                    divisions: 20,
                    label: '${(layout.visualizerRadius * 100).round()}%',
                    onChanged: layout.setVisualizerRadius,
                  ),
                ),
              ),
              SettingTile(
                icon: Icons.line_weight_rounded,
                title: const Text('Line thickness'),
                subtitle: Text('${layout.visualizerThickness.toStringAsFixed(1)} px'),
                control: SizedBox(
                  width: 220,
                  child: Slider(
                    value: layout.visualizerThickness,
                    min: 1,
                    max: 8,
                    divisions: 14,
                    label: '${layout.visualizerThickness.toStringAsFixed(1)} px',
                    onChanged: layout.setVisualizerThickness,
                  ),
                ),
              ),
            ],
            SwitchListTile(
              title: const Text('Music-reactive background'),
              subtitle: const Text('Follows the music when an abstract Now Playing background is selected'),
              value: look.reactiveBackground,
              onChanged: look.setReactiveBackground,
            ),
          ],
        ],
      ),
    );
  }
}
