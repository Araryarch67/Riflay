import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/app_updates.dart';
import '../pages/sound_settings.dart' show settingsMuted;
import 'controls.dart' show formatBytes;
import 'skeleton.dart';
import '../../services/language.dart';

/// An explicit check, followed by an Android download and system installation.
class AppUpdateTile extends StatefulWidget {
  const AppUpdateTile({super.key, this.updates, this.release}) : _dialog = false;
  const AppUpdateTile._dialog({required this.updates, required this.release}) : _dialog = true;
  final bool _dialog;
  final AppUpdates? updates;

  /// A newer release already found ([showUpdatePopup]): the tile starts at getting it.
  final AppRelease? release;

  @override
  State<AppUpdateTile> createState() => _AppUpdateTileState();
}

class _AppUpdateTileState extends State<AppUpdateTile> {
  late final _updates = widget.updates ?? AppUpdates();
  late AppRelease? _release = widget.release;
  bool _busy = false;
  double? _progress;
  String? _path;
  // Null until a check starts: the idle line, read in the language shown.
  String? _message;
  bool _failed = false;

  @override
  void dispose() {
    _updates.dispose();
    super.dispose();
  }

  Future<void> _act() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      if (_release == null) {
        setState(() => _message = tr.checkingUpdates);
        final release = await _updates.check();
        if (!mounted) return;
        setState(() {
          _release = release.newerThan(_updates.installedVersion) ? release : null;
          _message = _release == null ? tr.latestVersion : tr.versionAvailable(release.version);
        });
      } else if (!_updates.android || _updates.assetFor(_release!) == null) {
        if (!await launchUrl(_release!.url, mode: LaunchMode.externalApplication)) {
          throw StateError('Could not open release page');
        }
      } else if (_path == null) {
        setState(() {
          _message = tr.downloadingVersion(_release!.version);
          _progress = 0;
        });
        final path = await _updates.download(_release!, (progress) {
          if (mounted) setState(() => _progress = progress);
        });
        if (!mounted) return;
        setState(() {
          _path = path;
          _progress = null;
          _message = tr.versionReady(_release!.version);
        });
      } else {
        setState(() => _message = tr.openingInstaller);
        final opened = await _updates.install(_path!);
        if (!mounted) return;
        setState(() {
          _message = opened ? tr.completeInInstaller : tr.allowInstallUpdates;
        });
      }
    } catch (error) {
      debugPrint('App update: $error');
      if (!mounted) return;
      setState(() {
        _failed = true;
        _progress = null;
        _message = switch (error) {
          PlatformException(code: 'signature') => tr.differentSigningKey,
          FormatException() when _release != null => tr.couldntVerifyUpdate,
          _ when _release == null => tr.couldntCheckUpdates,
          _ => tr.couldntUpdateRiflay,
        };
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _path != null
        ? tr.installUpdate
        : _release == null
        ? tr.checkForUpdates
        : _updates.android && _updates.assetFor(_release!) != null
        ? tr.downloadUpdate
        : tr.getUpdate;
    if (widget._dialog) return _buildDialog(context, label);
    return ListTile(
      leading: const Icon(Icons.system_update_rounded),
      title: Text(_busy && _progress != null ? 'Downloading… ${(_progress! * 100).round()}%' : label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Found at start: the popup's title already says which version.
          if (_message != null || widget.release == null)
            Text(_message ?? tr.checkGithubUpdate, style: settingsMuted(context)),
          if (_progress != null) ...[const SizedBox(height: 8), LinearProgressIndicator(value: _progress)],
        ],
      ),
      trailing: _busy
          ? const SkeletonBox.circle(size: 18)
          : Icon(_path != null ? Icons.install_mobile_rounded : Icons.chevron_right_rounded, size: 20),
      onTap: _busy ? null : _act,
    );
  }

  Widget _buildDialog(BuildContext context, String label) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final asset = _updates.android ? _updates.assetFor(_release!) : null;
    final progress = _progress;
    final ready = _path != null;
    final icon = _failed
        ? Icons.error_outline_rounded
        : ready
        ? Icons.task_alt_rounded
        : Icons.system_update_rounded;
    final actionIcon = ready
        ? Icons.install_mobile_rounded
        : asset != null
        ? Icons.download_rounded
        : Icons.open_in_new_rounded;

    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        constraints: const BoxConstraints(maxWidth: 400),
        scrollable: true,
        icon: Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _failed ? colors.errorContainer : colors.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 32, color: _failed ? colors.onErrorContainer : colors.onPrimaryContainer),
          ),
        ),
        title: Text(tr.versionAvailable(_release!.version), textAlign: TextAlign.center),
        content: SizedBox(
          width: 352,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(Icons.file_download_outlined, color: colors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(text: 'Riflay'),
                                TextSpan(text: ' ${_release!.version}'),
                              ],
                            ),
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            asset == null ? 'GitHub Releases' : asset.name,
                            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (asset != null) ...[
                            const SizedBox(height: 4),
                            Text(formatBytes(asset.bytes), style: theme.textTheme.labelMedium),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 20),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _message!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _failed ? colors.error : colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              if (progress != null) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: progress, minHeight: 8, borderRadius: BorderRadius.circular(4)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (asset != null)
                      Expanded(
                        child: Text(
                          tr.bytesOf(formatBytes(asset.bytes * progress), formatBytes(asset.bytes)),
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      )
                    else
                      const Spacer(),
                    Text('${(progress * 100).round()}%', style: theme.textTheme.labelLarge),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: Text(tr.notNow)),
          FilledButton.icon(
            onPressed: _busy ? null : _act,
            icon: _busy
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(actionIcon, size: 18),
            label: Text(label),
          ),
        ],
      ),
    );
  }
}

/// Tells about a newer [release] that the check at start found ([AppUpdates.checkAtStart]): its version, and the tile
/// that gets it (an Android download and install, elsewhere the release page). [updates] is the checker that found
/// it, and is disposed with the tile.
Future<void> showUpdatePopup(BuildContext context, AppUpdates updates, AppRelease release) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) => AppUpdateTile._dialog(updates: updates, release: release),
);
