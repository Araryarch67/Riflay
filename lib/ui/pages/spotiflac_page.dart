import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/language.dart';
import '../../services/spotiflac.dart';
import '../../services/layout_prefs.dart';
import '../shell_scope.dart';
import '../widgets/app_dialog.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/spotiflac_notice.dart';
import 'sound_settings.dart' show SettingsCard, SettingsIcon, settingsHeading, settingsMuted;

class SpotiflacPage extends StatefulWidget {
  const SpotiflacPage({super.key, this.engine});
  final Spotiflac? engine;
  @override
  State<SpotiflacPage> createState() => _SpotiflacPageState();
}

class _SpotiflacPageState extends State<SpotiflacPage> {
  late final engine = widget.engine ?? Spotiflac.instance;
  final repository = TextEditingController();
  List<Map<String, dynamic>> catalog = [];
  bool busy = false;
  bool failed = false;

  List<Map<String, dynamic>> get availableCatalog {
    final installed = engine.plugins.map((plugin) => plugin['id']).toSet();
    return catalog.where((entry) => !installed.contains(entry['id'] ?? entry['name'])).toList();
  }

  @override
  void initState() {
    super.initState();
    _run(() async {
      await engine.load();
      if (!mounted) return;
      repository.text = engine.registryUrl;
      await engine.refresh();
    });
  }

  @override
  void dispose() {
    repository.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      failed = false;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _import() async {
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['sflx', 'spotiflac-ext']);
    final path = result.firstOrNull?.path;
    if (path != null) await _run(() => engine.install(path));
  }

  Future<void> _loadRepository() async {
    final url = repository.text.trim();
    if (url.isEmpty) return;
    await _run(() async {
      final result = await engine.registry(url);
      if (mounted) setState(() => catalog = result);
    });
  }

  Widget _repositoryCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fieldShape = OutlineInputBorder(borderRadius: LayoutPrefs.corner(12));
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: LayoutPrefs.corner(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.public_rounded, color: scheme.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(child: Text(tr.spotiflacRepository, style: theme.textTheme.titleSmall)),
              ],
            ),
            const SizedBox(height: 12),
            Semantics(
              label: tr.spotiflacRepository,
              child: TextField(
                controller: repository,
                enabled: !busy,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) => _loadRepository(),
                decoration: InputDecoration(
                  hintText: 'https://…/registry.json',
                  filled: true,
                  fillColor: scheme.surface,
                  prefixIcon: const Icon(Icons.link_rounded),
                  border: fieldShape,
                  enabledBorder: fieldShape.copyWith(borderSide: BorderSide(color: scheme.outlineVariant)),
                  disabledBorder: fieldShape.copyWith(borderSide: BorderSide(color: scheme.outlineVariant)),
                  focusedBorder: fieldShape.copyWith(borderSide: BorderSide(color: scheme.primary, width: 2)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder(
              valueListenable: repository,
              builder: (context, value, _) => Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: busy || value.text.trim().isEmpty ? null : _loadRepository,
                    icon: const Icon(Icons.arrow_downward_rounded),
                    label: Text(tr.spotiflacLoadRepository),
                    style: FilledButton.styleFrom(backgroundColor: scheme.primary, foregroundColor: scheme.onPrimary),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : _import,
                    icon: const Icon(Icons.file_open_outlined),
                    label: Text(tr.importSflx),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(height: 4, child: busy ? const LinearProgressIndicator() : null),
          ],
        ),
      ),
    );
  }

  Future<void> _action(String id, String action) async {
    await engine.call('action', {'extension': id, 'action': action});
    final pending = await engine.call('pendingAuth', {'extension': id});
    if (pending is Map && pending['auth_url'] is String) {
      final uri = Uri.tryParse(pending['auth_url']);
      if (uri != null && const {'https', 'http'}.contains(uri.scheme) && uri.host.isNotEmpty) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  Future<void> _settings(Map<String, dynamic> plugin) async {
    final id = plugin['id'] as String;
    final values = await engine.settings(id);
    final fields = (plugin['settings'] as List? ?? const []).whereType<Map>().toList();
    final qualityOptions = plugin['has_download_provider'] == true
        ? (plugin['quality_options'] as List? ?? const []).whereType<Map>().toList()
        : <Map>[];
    var quality = engine.qualityOf(id);
    for (final field in fields) {
      values.putIfAbsent(field['key'] as String, () => field['default']);
    }
    if (!mounted) return;
    final form = GlobalKey<FormState>();
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AppDialog(
          title: engine.nameOf(id),
          content: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final field in fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: switch (field['type']) {
                      'button' => Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: FilledButton.tonal(
                          onPressed: () async {
                            try {
                              await _action(id, (field['action'] ?? field['key']).toString());
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.spotiflacFailed)));
                              }
                            }
                          },
                          child: Text(field['label'].toString()),
                        ),
                      ),
                      'boolean' => SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(field['label'].toString()),
                        subtitle: field['description'] is String ? Text(field['description']) : null,
                        value: values[field['key']] == true,
                        onChanged: (value) => update(() => values[field['key']] = value),
                      ),
                      'select' => DropdownMenu<String>(
                        selectOnly: true,
                        expandedInsets: EdgeInsets.zero,
                        initialSelection: (field['options'] as List? ?? []).contains(values[field['key']])
                            ? values[field['key']] as String?
                            : null,
                        label: Text(field['label'].toString()),
                        dropdownMenuEntries: [
                          for (final option in field['options'] as List? ?? [])
                            DropdownMenuEntry(value: option.toString(), label: option.toString()),
                        ],
                        onSelected: (value) => values[field['key']] = value,
                      ),
                      _ => TextFormField(
                        initialValue: values[field['key']]?.toString() ?? '',
                        obscureText: field['secret'] == true,
                        autocorrect: false,
                        enableSuggestions: field['secret'] != true,
                        keyboardType: field['type'] == 'number'
                            ? const TextInputType.numberWithOptions(decimal: true)
                            : TextInputType.text,
                        decoration: InputDecoration(
                          labelText: field['label'].toString(),
                          helperText: field['description'] as String?,
                        ),
                        validator: (value) =>
                            field['required'] == true && (value == null || value.trim().isEmpty) ||
                                field['type'] == 'number' &&
                                    value != null &&
                                    value.isNotEmpty &&
                                    num.tryParse(value) == null
                            ? tr.spotiflacInvalidSetting
                            : null,
                        onChanged: (value) =>
                            values[field['key']] = field['type'] == 'number' ? num.tryParse(value) : value,
                      ),
                    },
                  ),
                if (qualityOptions.isNotEmpty)
                  DropdownMenu<String>(
                    selectOnly: true,
                    expandedInsets: EdgeInsets.zero,
                    initialSelection: quality,
                    label: Text(tr.spotiflacQuality),
                    dropdownMenuEntries: [
                      for (final option in qualityOptions)
                        DropdownMenuEntry(
                          value: option['id'].toString(),
                          label: (option['label'] ?? option['id']).toString(),
                        ),
                    ],
                    onSelected: (value) {
                      if (value != null) quality = value;
                    },
                  ),
                if (fields.isEmpty && qualityOptions.isEmpty) Text(tr.spotiflacNoSettings),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr.cancel)),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(context, true);
              },
              child: Text(tr.save),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      if (qualityOptions.isNotEmpty) await engine.setQuality(id, quality);
      await engine.saveSettings(id, values);
    }
  }

  Widget _capabilities(Map<String, dynamic> plugin) {
    final capabilities = Spotiflac.capabilitiesOf(plugin);
    final downloads = capabilities.contains(SpotiflacCapability.download);
    final metadata = capabilities.contains(SpotiflacCapability.metadata);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final capability in capabilities)
                Chip(
                  label: Text(switch (capability) {
                    SpotiflacCapability.search => tr.navSearch,
                    SpotiflacCapability.metadata => tr.spotiflacMetadataCapability,
                    SpotiflacCapability.download => tr.download,
                    SpotiflacCapability.lyrics => tr.lyrics,
                  }),
                ),
            ],
          ),
          Text(
            downloads
                ? tr.spotiflacAudioProvider
                : !metadata &&
                      capabilities.contains(SpotiflacCapability.lyrics) &&
                      !capabilities.contains(SpotiflacCapability.search)
                ? tr.spotiflacLyricsOnly
                : tr.spotiflacMetadataOnly,
            style: settingsMuted(context),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final muted = text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final small = settingsMuted(context);
    final pad = ShellScope.of(context).compact ? 16.0 : 24.0;
    Widget heading(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(label, style: settingsHeading(context)),
    );
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) => PageScaffold(
        title: tr.spotiflacExtensions,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 28),
              child: Align(
                alignment: AlignmentDirectional.topStart,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(tr.spotiflacExtensions, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text(tr.spotiflacAbout, style: muted),
                      const SizedBox(height: 16),
                      const SpotiflacNotice(),
                      const SizedBox(height: 16),
                      _repositoryCard(context),
                      const SizedBox(height: 16),
                      if (failed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Material(
                            color: scheme.errorContainer,
                            borderRadius: LayoutPrefs.corner(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      tr.spotiflacFailed,
                                      style: text.bodyMedium?.copyWith(color: scheme.onErrorContainer),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      SettingsCard(
                        children: [
                          SwitchListTile(
                            secondary: const Icon(Icons.lan_outlined),
                            title: Text(tr.spotiflacLocalNetwork),
                            value: engine.localNetwork,
                            onChanged: busy ? null : (value) => _run(() => engine.allowLocalNetwork(value)),
                          ),
                        ],
                      ),
                      if (engine.plugins.isNotEmpty || !busy)
                        Row(
                          children: [
                            Expanded(child: heading(tr.installed)),
                            IconButton(
                              tooltip: tr.refresh,
                              onPressed: busy ? null : () => _run(engine.refresh),
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                          ],
                        ),
                      if (engine.plugins.isEmpty && !busy)
                        SettingsCard(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.extension_off_outlined),
                              title: Text(tr.spotiflacEmpty, style: muted),
                            ),
                          ],
                        ),
                      if (engine.plugins.isNotEmpty)
                        SettingsCard(
                          children: [
                            for (final plugin in engine.plugins)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ListTile(
                                    leading: const SettingsIcon(Icons.extension_outlined),
                                    title: Text(engine.nameOf(plugin['id'])),
                                    subtitle: Text('${plugin['version']} · ${plugin['description']}', style: small),
                                    trailing: Switch(
                                      value: plugin['enabled'] == true,
                                      onChanged: busy
                                          ? null
                                          : (value) => _run(() => engine.enable(plugin['id'], value)),
                                    ),
                                  ),
                                  _capabilities(plugin),
                                  // Under the row rather than beside the switch, so it all fits a phone.
                                  Padding(
                                    padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 8, 8),
                                    child: Wrap(
                                      spacing: 4,
                                      children: [
                                        TextButton.icon(
                                          onPressed: busy ? null : () => _run(() => _settings(plugin)),
                                          icon: const Icon(Icons.tune_rounded),
                                          label: Text(tr.spotiflacSettings),
                                        ),
                                        TextButton.icon(
                                          onPressed: busy ? null : () => _run(() => engine.remove(plugin['id'])),
                                          icon: const Icon(Icons.delete_outline_rounded),
                                          label: Text(tr.remove),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      if (availableCatalog.isNotEmpty) ...[
                        heading(tr.available),
                        SettingsCard(
                          children: [
                            for (final entry in availableCatalog)
                              ListTile(
                                leading: const SettingsIcon(Icons.extension_outlined),
                                title: Text(
                                  (entry['display_name'] ?? entry['displayName'] ?? entry['name'] ?? entry['id'])
                                      .toString(),
                                ),
                                subtitle: (entry['description'] ?? '').toString().isEmpty
                                    ? null
                                    : Text(entry['description'].toString(), style: small),
                                trailing: FilledButton.tonal(
                                  onPressed: busy ? null : () => _run(() => engine.installFromRegistry(entry)),
                                  child: Text(tr.install),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
