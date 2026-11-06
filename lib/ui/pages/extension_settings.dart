import 'package:flutter/material.dart';

import '../../services/extensions/extension_store.dart';
import 'sound_settings.dart';
import '../widgets/skeleton.dart';
import '../../services/language.dart';

/// SpotiFLAC extension repositories, and the extensions from them: add or remove a repository, install, turn on or
/// off, update and remove extensions. Enabled extensions that search add their results to Search.
class ExtensionSettings extends StatefulWidget {
  const ExtensionSettings({super.key, this.store});

  /// Defaults to [ExtensionStore.instance].
  final ExtensionStore? store;

  @override
  State<ExtensionSettings> createState() => _ExtensionSettingsState();
}

class _ExtensionSettingsState extends State<ExtensionSettings> {
  late final ExtensionStore _store = widget.store ?? ExtensionStore.instance;
  final _url = TextEditingController();
  String? _urlError;

  @override
  void initState() {
    super.initState();
    _store.load().then((_) {
      // Read the repositories once per visit if nothing was read yet.
      if (mounted && _store.repositories.any((r) => _store.stateOf(r).registry == null)) _store.refresh();
    }, onError: (Object e) => debugPrint('Extensions not loaded: $e'));
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _add(String url) async {
    try {
      ExtensionStore.normalizeUrl(url);
    } on FormatException catch (e) {
      setState(() => _urlError = e.message);
      return;
    }
    setState(() => _urlError = null);
    _url.clear();
    await _store.addRepository(url);
  }

  Future<void> _run(Future<void> Function() action, String failed) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await action();
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('$failed: ${e is FormatException ? e.message : e}')));
    }
  }

  Future<void> _uninstall(InstalledExtension ext) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.removeNamedQuestion(ext.manifest.displayName)),
        content: Text(tr.removeExtensionBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr.remove)),
        ],
      ),
    );
    if (ok == true) await _run(() => _store.uninstall(ext.id), tr.couldntRemoveNamed(ext.manifest.displayName));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _store,
    builder: (context, _) {
      final installed = _store.installed;
      final have = {for (final e in installed) e.id};
      final available = [
        for (final e in _store.available)
          if (!have.contains(e.id)) e,
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 20),
            child: Text(tr.extensionsIntro, style: settingsMuted(context)),
          ),
          SettingsSection(title: tr.repositories, child: _repositories(context)),
          SettingsSection(
            title: tr.installed,
            child: installed.isEmpty
                ? SettingsCard(
                    children: [
                      ListTile(
                        title: Text(tr.noExtensionsYet),
                        subtitle: Text(tr.installFromRepo, style: settingsMuted(context)),
                      ),
                    ],
                  )
                : SettingsCard(children: [for (final e in installed) _installedTile(context, e)]),
          ),
          if (available.isNotEmpty)
            SettingsSection(
              title: tr.available,
              child: SettingsCard(children: [for (final e in available) _availableTile(context, e)]),
            ),
        ],
      );
    },
  );

  Widget _repositories(BuildContext context) {
    final repos = _store.repositories;
    final suggestions = [
      for (final s in suggestedRegistries)
        if (!repos.contains(s.url)) s,
    ];
    return SettingsCard(
      children: [
        for (final url in repos) _repoTile(context, url),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _url,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: tr.repositoryAddress,
                        hintText: 'https://…/registry.json',
                        errorText: _urlError,
                        isDense: true,
                      ),
                      onSubmitted: _add,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonal(onPressed: () => _add(_url.text), child: Text(tr.add)),
                ],
              ),
              if (suggestions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in suggestions)
                      ActionChip(
                        avatar: const Icon(Icons.add_rounded, size: 18),
                        label: Text(s.name),
                        tooltip: s.url,
                        onPressed: () => _add(s.url),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _repoTile(BuildContext context, String url) {
    final state = _store.stateOf(url);
    final name = [
      for (final s in suggestedRegistries)
        if (s.url == url) s.name,
    ].firstOrNull;
    final count = state.registry?.entries.length;
    final status = state.loading
        ? tr.reading
        : state.error != null
        ? tr.couldntReadIt('${state.error}')
        : count == null
        ? tr.notReadYet
        : tr.extensionsCount(count);
    return ListTile(
      leading: const Icon(Icons.source_outlined),
      title: Text(name ?? Uri.parse(url).host),
      subtitle: Text('$url\n$status', style: settingsMuted(context)),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: tr.refresh,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: state.loading ? null : () => _store.refresh(url),
          ),
          IconButton(
            tooltip: tr.removeRepository,
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _store.removeRepository(url),
          ),
        ],
      ),
    );
  }

  /// What Riflay does with it so far: searching. Downloads and lyrics from extensions aren't wired yet.
  static String _uses(ExtensionManifest m) {
    final parts = <String>[
      if (m.canSearch) tr.addsToSearch,
      if (m.isDownloadProvider) tr.downloadsUnsupported,
      if (m.isLyricsProvider) tr.lyricsUnsupported,
      if (m.requiredRuntimeFeatures.isNotEmpty) tr.needsSpotiflacFeatures,
    ];
    return parts.join(' · ');
  }

  Widget _installedTile(BuildContext context, InstalledExtension e) {
    final update = _store.updateFor(e.id);
    final busy = _store.isBusy(e.id);
    final m = e.manifest;
    return ListTile(
      leading: const Icon(Icons.extension_outlined),
      title: Text('${m.displayName}  ${m.version}'),
      subtitle: Text([if (m.description.isNotEmpty) m.description, _uses(m)].join('\n'), style: settingsMuted(context)),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const SkeletonBox.circle(size: 20)
          else if (update != null)
            IconButton(
              tooltip: tr.updateTo(update.version),
              icon: const Icon(Icons.system_update_alt_rounded),
              onPressed: () => _run(() => _store.install(update), tr.couldntUpdateNamed(m.displayName)),
            ),
          IconButton(
            tooltip: tr.remove,
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: busy ? null : () => _uninstall(e),
          ),
          Switch(value: e.enabled, onChanged: busy ? null : (on) => _store.setEnabled(e.id, on)),
        ],
      ),
    );
  }

  Widget _availableTile(BuildContext context, RegistryEntry e) {
    final busy = _store.isBusy(e.id);
    return ListTile(
      leading: const Icon(Icons.extension_outlined),
      title: Text('${e.displayName}  ${e.version}'),
      subtitle: Text(
        [if (e.description.isNotEmpty) e.description, if (e.tags.isNotEmpty) e.tags.join(', ')].join('\n'),
        style: settingsMuted(context),
      ),
      isThreeLine: true,
      trailing: busy
          ? const SkeletonBox.circle(size: 20)
          : FilledButton.tonal(
              onPressed: () => _run(() => _store.install(e), tr.couldntInstallNamed(e.displayName)),
              child: Text(tr.install),
            ),
    );
  }
}
