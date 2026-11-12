import 'package:flutter/material.dart';

import '../../services/language.dart';
import '../../services/sources/music_sources.dart';
import 'sound_settings.dart' show SettingsCard, settingsMuted;

/// Settings › Accounts & services › Music sources: Internet Archive and Radio Paradise ([MusicSources]).
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
              SwitchListTile(
                secondary: const Icon(Icons.account_balance_outlined),
                title: Text(tr.sourceArchive),
                subtitle: Text(tr.sourceArchiveSubtitle, style: muted),
                value: _sources.archive,
                onChanged: _sources.setArchive,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.radio_outlined),
                title: Text(tr.sourceRadioParadise),
                subtitle: Text(tr.sourceRadioParadiseSubtitle, style: muted),
                value: _sources.radioParadise,
                onChanged: _sources.setRadioParadise,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
