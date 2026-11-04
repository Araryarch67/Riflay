import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/app_updates.dart';
import '../pages/sound_settings.dart' show settingsMuted;
import 'skeleton.dart';

/// An explicit check, followed by an Android download and system installation.
class AppUpdateTile extends StatefulWidget {
  const AppUpdateTile({super.key, this.updates});
  final AppUpdates? updates;

  @override
  State<AppUpdateTile> createState() => _AppUpdateTileState();
}

class _AppUpdateTileState extends State<AppUpdateTile> {
  late final _updates = widget.updates ?? AppUpdates();
  AppRelease? _release;
  bool _busy = false;
  double? _progress;
  String? _path;
  String _message = 'Check GitHub for a newer version of Riflay';

  @override
  void dispose() {
    _updates.dispose();
    super.dispose();
  }

  Future<void> _act() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_release == null) {
        setState(() => _message = 'Checking for updates…');
        final release = await _updates.check();
        if (!mounted) return;
        setState(() {
          _release = release.newerThan(_updates.installedVersion) ? release : null;
          _message = _release == null ? "You're using the latest version" : 'Version ${release.version} is available';
        });
      } else if (!_updates.android || _updates.assetFor(_release!) == null) {
        if (!await launchUrl(_release!.url, mode: LaunchMode.externalApplication)) {
          throw StateError('Could not open release page');
        }
      } else if (_path == null) {
        setState(() {
          _message = 'Downloading version ${_release!.version}…';
          _progress = 0;
        });
        final path = await _updates.download(_release!, (progress) {
          if (mounted) setState(() => _progress = progress);
        });
        if (!mounted) return;
        setState(() {
          _path = path;
          _progress = null;
          _message = 'Version ${_release!.version} is ready to install';
        });
      } else {
        setState(() => _message = 'Opening the Android installer…');
        final opened = await _updates.install(_path!);
        if (!mounted) return;
        setState(() {
          _message = opened
              ? 'Complete the update in the Android installer'
              : 'Allow Riflay to install updates, then try again';
        });
      }
    } catch (error) {
      debugPrint('App update: $error');
      if (!mounted) return;
      setState(() {
        _progress = null;
        _message = switch (error) {
          PlatformException(code: 'signature') =>
            'This copy uses a different signing key. Back up your data before installing the release',
          FormatException() when _release != null => "Couldn't verify the update. Try downloading it again",
          _ when _release == null => "Couldn't check for updates. Try again",
          _ => "Couldn't update Riflay. Try again",
        };
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _path != null
        ? 'Install update'
        : _release == null
        ? 'Check for updates'
        : _updates.android && _updates.assetFor(_release!) != null
        ? 'Download update'
        : 'Get update';
    return ListTile(
      leading: const Icon(Icons.system_update_rounded),
      title: Text(_busy && _progress != null ? 'Downloading… ${(_progress! * 100).round()}%' : label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_message, style: settingsMuted(context)),
          if (_progress != null) ...[const SizedBox(height: 8), LinearProgressIndicator(value: _progress)],
        ],
      ),
      trailing: _busy
          ? const SkeletonBox.circle(size: 18)
          : Icon(_path != null ? Icons.install_mobile_rounded : Icons.chevron_right_rounded, size: 20),
      onTap: _busy ? null : _act,
    );
  }
}
