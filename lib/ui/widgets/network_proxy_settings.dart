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

  @override
  Widget build(BuildContext context) => SettingsCard(
    children: [
      SwitchListTile(
        secondary: const Icon(Icons.public_rounded),
        title: Text(tr.networkProxy),
        subtitle: Text(tr.networkProxyAbout, style: settingsMuted(context)),
        value: _enabled,
        onChanged: _saving
            ? null
            : (value) => setState(() {
                _dirty = true;
                _enabled = value;
              }),
      ),
      if (_enabled)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _address,
                enabled: !_saving,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(labelText: tr.networkProxyAddress, hintText: 'http://127.0.0.1:7890'),
                onChanged: (_) => _dirty = true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bypass,
                enabled: !_saving,
                autocorrect: false,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: tr.networkProxyBypass,
                  helperText: tr.networkProxyBypassHint,
                  helperMaxLines: 3,
                ),
                onChanged: (_) => _dirty = true,
              ),
              const SizedBox(height: 12),
              Text(tr.networkProxyScope, style: settingsMuted(context)),
            ],
          ),
        ),
      if (_error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(_error!)),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Align(
          alignment: Alignment.centerRight,
          child: FilledButton(onPressed: _saving ? null : _save, child: Text(tr.save)),
        ),
      ),
    ],
  );
}
