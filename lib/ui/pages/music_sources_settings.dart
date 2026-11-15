import 'package:flutter/material.dart';

import '../../services/language.dart';
import '../../services/sources/music_sources.dart';
import '../../platform/features.dart';
import '../../services/spotiflac.dart';
import '../shell_scope.dart';
import 'spotiflac_page.dart';
import '../widgets/monochrome_mark.dart';
import 'sound_settings.dart' show SettingsCard, settingsMuted;

/// Settings › Accounts & services › Music sources: SoundCloud, Monochrome and the SpotiFLAC extensions
/// ([MusicSources]).
class MusicSourcesSettings extends StatefulWidget {
  const MusicSourcesSettings({super.key});

  @override
  State<MusicSourcesSettings> createState() => _MusicSourcesSettingsState();
}

class _MusicSourcesSettingsState extends State<MusicSourcesSettings> {
  final _sources = MusicSources.instance;

  @override
  void initState() {
    super.initState();
    _sources.load().ignore();
  }

  @override
  Widget build(BuildContext context) {
    final muted = settingsMuted(context);
    return ListenableBuilder(
      listenable: _sources,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(tr.sourcesAbout, style: muted),
          ),
          SettingsCard(
            children: [
              if (Features.soundcloud)
                SwitchListTile(
                  secondary: const Icon(Icons.cloud_outlined),
                  title: Text(tr.sourceInSearch(tr.sourceSoundcloud)),
                  subtitle: Text(tr.sourceSearchToggleSubtitle, style: muted),
                  value: _sources.soundcloud,
                  onChanged: _sources.setSoundcloud,
                ),
              SwitchListTile(
                secondary: const MonochromeMark(size: 24),
                title: Text(tr.sourceInSearch(tr.sourceMonochrome)),
                subtitle: Text(tr.sourceSearchToggleSubtitle, style: muted),
                value: _sources.monochrome,
                onChanged: _sources.setMonochrome,
              ),
              if (Spotiflac.supported)
                ListTile(
                  leading: const Icon(Icons.extension_outlined),
                  title: Text(tr.spotiflacExtensions),
                  subtitle: Text(tr.spotiflacDownloadOnly, style: muted),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => ShellScope.of(context).open(const SpotiflacPage()),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
