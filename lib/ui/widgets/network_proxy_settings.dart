import 'package:flutter/material.dart';

import '../../services/language.dart';
import '../../services/network_settings.dart';
import '../pages/sound_settings.dart' show SettingsCard, settingsMuted;

/// Settings for a user-supplied HTTP proxy and domain bypass rules.
class NetworkProxySettings extends StatefulWidget {
  const NetworkProxySettings({super.key});
  @override
  State<NetworkProxySettings> createState() => _NetworkProxySettingsState();
}

class _NetworkProxySettingsState extends State<NetworkProxySettings> {
  final _settings = NetworkSettings.instance;
  late final _address = TextEditingController(text: _settings.address);
  late final _bypass = TextEditingController(text: _settings.bypass);
  late bool _enabled = _settings.enabled;
  bool _dirty = false, _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _settings.load().then((_) {
      if (!mounted || _dirty) return;
      setState(() {
        _enabled = _settings.enabled;
        _address.text = _settings.address;
        _bypass.text = _settings.bypass;
      });
    });
  }

  @override
  void dispose() {
    _address.dispose();
    _bypass.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final address = _enabled ? _address.text : _settings.address;
    final bypass = _enabled ? _bypass.text : _settings.bypass;
    if (NetworkSettings.parseAddress(address) == null || NetworkSettings.parseBypass(bypass) == null) {
      setState(() => _error = tr.networkProxyInvalid);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _settings.save(enabled: _enabled, address: address, bypass: bypass);
      if (mounted) {
        _dirty = false;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.networkProxySaved)));
      }
    } catch (e) {
      debugPrint('Proxy settings: ${e.runtimeType}');
      if (mounted) setState(() => _error = tr.networkProxySaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _edited(String _) {
    if (_dirty && _error == null) return;
    setState(() {
      _dirty = true;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = settingsMuted(context);
    Widget label(String title) => ExcludeSemantics(child: Text(title, style: theme.textTheme.labelLarge));

    return SettingsCard(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.public_rounded),
              title: Text(tr.networkProxy),
              subtitle: Text(tr.networkProxyAbout, style: muted),
              value: _enabled,
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                      _enabled = value;
                      _dirty = true;
                      _error = null;
                    }),
            ),
            if (_enabled || _dirty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_enabled) ...[
                      label(tr.networkProxyAddress),
                      const SizedBox(height: 8),
                      Semantics(
                        label: tr.networkProxyAddress,
                        child: TextField(
                          controller: _address,
                          enabled: !_saving,
                          autocorrect: false,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(hintText: 'http://127.0.0.1:7890'),
                          onChanged: _edited,
                        ),
                      ),
                      const SizedBox(height: 16),
                      label(tr.networkProxyBypass),
                      const SizedBox(height: 8),
                      Semantics(
                        label: tr.networkProxyBypass,
                        child: TextField(
                          controller: _bypass,
                          enabled: !_saving,
                          autocorrect: false,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(),
                          onChanged: _edited,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(tr.networkProxyBypassHint, style: muted),
                      const SizedBox(height: 12),
                      Text(tr.networkProxyScope, style: muted),
                    ],
                    if (_error case final error?) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(error, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
                      ),
                    ],
                    if (_enabled) const SizedBox(height: 16),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: FilledButton(onPressed: _dirty && !_saving ? _save : null, child: Text(tr.save)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
