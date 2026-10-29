import 'package:flutter/material.dart';

import '../../services/beta_features.dart';
import 'sound_settings.dart' show SettingsCard, settingsMuted;
import 'listen_together_page.dart' show BetaBadge;

/// Settings › Beta features: every feature still in Beta, each with an on / off switch.
class BetaSettings extends StatelessWidget {
  const BetaSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final beta = BetaFeatures.instance;
    final muted = settingsMuted(context);
    return ListenableBuilder(
      listenable: beta,
      builder: (context, _) => SettingsCard(
        children: [
          for (final f in BetaFeature.values)
            SwitchListTile(
              title: Row(
                children: [
                  Flexible(child: Text(f.title)),
                  const SizedBox(width: 8),
                  const BetaBadge(),
                ],
              ),
              subtitle: Text(f.description, style: muted),
              value: beta.isOn(f),
              onChanged: (v) async {
                await beta.set(f, v);
              },
            ),
        ],
      ),
    );
  }
}
