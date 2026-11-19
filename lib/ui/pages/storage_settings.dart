import 'package:flutter/material.dart';

import '../../platform/features.dart';
import '../../services/language.dart';
import '../../services/app_cache.dart';
import '../../services/merged_download.dart';
import '../../services/sources/music_sources.dart';
import '../widgets/app_dialog.dart';
import '../widgets/controls.dart' show formatBytes;
import 'sound_settings.dart' show SettingsCard, settingsMuted;

class StorageSettings extends StatefulWidget {
  const StorageSettings({super.key});
  @override
  State<StorageSettings> createState() => _StorageSettingsState();
}

class _StorageSettingsState extends State<StorageSettings> {
  @override
  void initState() {
    super.initState();
    MusicSources.instance.load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: MusicSources.instance,
    builder: (context, _) => Column(
      children: [
        SettingsCard(
          children: [
            for (final (label, mb, save) in [
              (tr.musicCacheLimit, MusicSources.instance.smartMergeCacheMb, MusicSources.instance.setSmartMergeCacheMb),
              (tr.videoCacheLimit, MusicSources.instance.videoMb, MusicSources.instance.setVideoMb),
              (tr.imageCacheLimit, MusicSources.instance.imageMb, MusicSources.instance.setImageMb),
            ])
              _CacheSlider(key: ValueKey((label, mb)), label: label, mb: mb, save: save),
          ],
        ),
        if (Features.smartMerge)
          FutureBuilder<int>(
            future: MergedDownload.keptSize(),
            builder: (context, snap) => ListTile(
              title: Text(tr.smartMergeCache),
              subtitle: Text(tr.smartMergeCacheSubtitle(formatBytes(snap.data ?? 0))),
              trailing: TextButton(
                onPressed: (snap.data ?? 0) == 0
                    ? null
                    : () async {
                        await MergedDownload.clearKept();
                        if (mounted) setState(() {});
                      },
                child: Text(tr.smartMergeCacheClear),
              ),
            ),
          ),
        const _ClearCacheTile(),
      ],
    ),
  );
}

class _CacheSlider extends StatefulWidget {
  const _CacheSlider({super.key, required this.label, required this.mb, required this.save});
  final String label;
  final int mb;
  final Future<void> Function(int) save;
  @override
  State<_CacheSlider> createState() => _CacheSliderState();
}

class _CacheSliderState extends State<_CacheSlider> {
  late double value = widget.mb.clamp(0, 5120).toDouble();
  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(widget.label),
    trailing: Text('${value.round()} MB'),
    subtitle: Slider(
      value: value,
      max: 5120,
      divisions: 160,
      label: '${value.round()} MB',
      onChanged: (v) => setState(() => value = v),
      onChangeEnd: (v) => widget.save(v.round()),
    ),
  );
}

/// Clear cache, with what it would free; asks first ([AppCache]).
class _ClearCacheTile extends StatefulWidget {
  const _ClearCacheTile();

  @override
  State<_ClearCacheTile> createState() => _ClearCacheTileState();
}

class _ClearCacheTileState extends State<_ClearCacheTile> {
  late Future<int> _size = AppCache.size();
  bool _clearing = false;

  Future<void> _clear(int bytes) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: Text(tr.clearCacheConfirm(formatBytes(bytes))),
        content: Text(tr.clearCacheConfirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr.clearCacheAction)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _clearing = true);
    final freed = await AppCache.clear();
    if (!mounted) return;
    setState(() {
      _clearing = false;
      _size = AppCache.size();
    });
    messenger?.showSnackBar(SnackBar(content: Text(tr.clearCacheDone(formatBytes(freed)))));
  }

  @override
  Widget build(BuildContext context) {
    final muted = settingsMuted(context);
    return FutureBuilder(
      future: _size,
      builder: (context, snap) {
        final bytes = snap.data;
        return ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: Text(tr.clearCache),
          subtitle: Text(
            bytes == null || _clearing ? tr.clearCacheCounting : tr.clearCacheSubtitle(formatBytes(bytes)),
            style: muted,
          ),
          trailing: _clearing
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : null,
          enabled: bytes != null && bytes > 0 && !_clearing,
          onTap: bytes == null ? null : () => _clear(bytes),
        );
      },
    );
  }
}
