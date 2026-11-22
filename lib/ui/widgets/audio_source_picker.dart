import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/download_matches.dart';
import '../../services/language.dart';
import '../../services/manual_audio.dart';
import '../../services/player_controller.dart';
import '../../services/sources/music_sources.dart';
import 'frosted.dart';

Future<void> showAudioSourcePicker(BuildContext context, Track track) {
  final controller = PlayerScope.read(context);
  return showAppSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _AudioSourcePicker(controller: controller, track: track),
  );
}

class _AudioSourcePicker extends StatefulWidget {
  const _AudioSourcePicker({required this.controller, required this.track});
  final PlayerController controller;
  final Track track;

  @override
  State<_AudioSourcePicker> createState() => _AudioSourcePickerState();
}

class _AudioSourcePickerState extends State<_AudioSourcePicker> {
  String _query = '';
  List<Track> _remote = [];
  bool _searching = false;
  bool _failed = false;
  bool _saving = false;
  int _searchRevision = 0;
  late List<Track> _local;

  @override
  void initState() {
    super.initState();
    _local = DownloadMatches.rank(widget.track, widget.controller.library.where((t) => t.path != null).toList());
  }

  Future<void> _select(ManualAudioChoice? choice) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.controller.setAudioChoice(widget.track, choice);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.audioSourceFailed)));
    }
  }

  Future<void> _search() async {
    final revision = ++_searchRevision;
    setState(() {
      _searching = true;
      _failed = false;
    });
    try {
      final result = await widget.controller.monochrome
          .search(_query.trim().isEmpty ? '${widget.track.title} ${widget.track.artist}' : _query.trim())
          .timeout(const Duration(seconds: 15));
      if (mounted && revision == _searchRevision) {
        setState(() {
          _remote = result;
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted && revision == _searchRevision) {
        setState(() {
          _failed = true;
          _searching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.controller.audioChoice(widget.track);
    final query = _query.toLowerCase().trim();
    final local = _local.where((t) => query.isEmpty || '${t.title} ${t.artist}'.toLowerCase().contains(query)).toList();
    final choices = [...local, ..._remote];
    final text = Theme.of(context).textTheme;
    Widget mode(String label, IconData icon, bool checked, VoidCallback action) => ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: checked ? const Icon(Icons.check_rounded) : null,
      enabled: !_saving,
      onTap: action,
    );
    return SafeArea(
      child: SizedBox(
        height: math.min(680, MediaQuery.sizeOf(context).height * .85),
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            children: [
              ListTile(
                title: Text(tr.audioSource, style: text.titleLarge),
                subtitle: Text(tr.audioSourceHint),
              ),
              if (_saving) const LinearProgressIndicator(),
              mode(tr.audioSourceAutomatic, Icons.auto_awesome_outlined, selected == null, () => _select(null)),
              mode(
                'YouTube Music',
                Icons.play_circle_outline_rounded,
                selected != null && selected.track == null,
                () => _select(const ManualAudioChoice.youtube()),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  enabled: !_saving,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: tr.audioSourceSearch,
                  ),
                  onChanged: (value) => setState(() {
                    _query = value;
                    _remote = [];
                    _failed = false;
                    _searchRevision++;
                    _searching = false;
                  }),
                  onSubmitted: MusicSources.instance.monochrome ? (_) => _search() : null,
                ),
              ),
              if (MusicSources.instance.monochrome)
                TextButton.icon(
                  onPressed: _searching || _saving ? null : _search,
                  icon: const Icon(Icons.search_rounded),
                  label: Text(tr.audioSourceSearchMonochrome),
                ),
              if (_searching) const LinearProgressIndicator(),
              if (_failed) Padding(padding: const EdgeInsets.all(8), child: Text(tr.downloadMatchFailed)),
              Expanded(
                child: choices.isEmpty
                    ? Center(child: Text(tr.audioSourceEmpty))
                    : ListView.builder(
                        itemCount: choices.length,
                        itemBuilder: (context, index) {
                          final track = choices[index];
                          return ListTile(
                            leading: Icon(track.path != null ? Icons.library_music_outlined : Icons.cloud_outlined),
                            title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              [
                                track.artist,
                                track.path != null ? tr.yourLibrary : 'Monochrome',
                                ?track.qualityLabel,
                              ].join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: selected?.track?.id == track.id ? const Icon(Icons.check_rounded) : null,
                            enabled: !_saving,
                            onTap: () => _select(ManualAudioChoice.track(track)),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
