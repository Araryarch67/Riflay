import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/language.dart';
import '../../services/spotiflac.dart';
import '../widgets/app_dialog.dart';
import '../widgets/page_scaffold.dart';
import 'sound_settings.dart' show SettingsCard;

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

  @override
  void initState() {
    super.initState();
    _run(() async {
      await engine.load();
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
    final qualityOptions = (plugin['quality_options'] as List? ?? const []).whereType<Map>().toList();
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
                      'button' => OutlinedButton(
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
                      'boolean' => SwitchListTile(
                        title: Text(field['label'].toString()),
                        subtitle: field['description'] is String ? Text(field['description']) : null,
                        value: values[field['key']] == true,
                        onChanged: (value) => update(() => values[field['key']] = value),
                      ),
                      'select' => DropdownButtonFormField<String>(
                        initialValue: (field['options'] as List? ?? []).contains(values[field['key']])
                            ? values[field['key']] as String?
                            : null,
                        decoration: InputDecoration(labelText: field['label'].toString()),
                        items: [
                          for (final option in field['options'] as List? ?? [])
                            DropdownMenuItem(value: option.toString(), child: Text(option.toString())),
                        ],
                        onChanged: (value) => values[field['key']] = value,
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
                  DropdownButtonFormField<String>(
                    initialValue: quality,
                    decoration: InputDecoration(labelText: tr.spotiflacQuality),
                    items: [
                      for (final option in qualityOptions)
                        DropdownMenuItem(
                          value: option['id'].toString(),
                          child: Text((option['label'] ?? option['id']).toString()),
                        ),
                    ],
                    onChanged: (value) {
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
      await engine.setQuality(id, quality);
      await engine.saveSettings(id, values);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: engine,
    builder: (context, _) => PageScaffold(
      title: tr.spotiflacExtensions,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          sliver: SliverList.list(
            children: [
              Text(tr.spotiflacAbout),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: busy ? null : _import,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(tr.importSflx),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _run(engine.refresh),
                    icon: const Icon(Icons.refresh),
                    label: Text(tr.retry),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: repository,
                enabled: !busy,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: tr.spotiflacRepository,
                  hintText: 'https://…/registry.json',
                  suffixIcon: IconButton(
                    tooltip: tr.spotiflacLoadRepository,
                    onPressed: busy
                        ? null
                        : () => _run(() async {
                            final result = await engine.registry(repository.text);
                            if (mounted) setState(() => catalog = result);
                          }),
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: Text(tr.spotiflacLocalNetwork),
                value: engine.localNetwork,
                onChanged: busy ? null : (value) => _run(() => engine.allowLocalNetwork(value)),
              ),
              if (busy) const LinearProgressIndicator(),
              if (failed) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(tr.spotiflacFailed)),
              if (engine.plugins.isEmpty && !busy)
                Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(tr.spotiflacEmpty)),
              if (engine.plugins.isNotEmpty)
                SettingsCard(
                  children: [
                    for (final plugin in engine.plugins)
                      ListTile(
                        title: Text(engine.nameOf(plugin['id'])),
                        subtitle: Text('${plugin['version']} · ${plugin['description']}'),
                        leading: Switch(
                          value: plugin['enabled'] == true,
                          onChanged: busy ? null : (value) => _run(() => engine.enable(plugin['id'], value)),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: tr.spotiflacSettings,
                              onPressed: busy ? null : () => _run(() => _settings(plugin)),
                              icon: const Icon(Icons.tune_rounded),
                            ),
                            IconButton(
                              tooltip: tr.remove,
                              onPressed: busy ? null : () => _run(() => engine.remove(plugin['id'])),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              for (final entry in catalog)
                ListTile(
                  title: Text(
                    (entry['display_name'] ?? entry['displayName'] ?? entry['name'] ?? entry['id']).toString(),
                  ),
                  subtitle: Text((entry['description'] ?? '').toString()),
                  trailing: TextButton(
                    onPressed: busy ? null : () => _run(() => engine.installFromRegistry(entry)),
                    child: Text(tr.install),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
