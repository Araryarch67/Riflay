import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/play_history.dart';
import '../../services/scrobbler.dart';
import '../player_scope.dart';
import '../theme.dart';
import 'sound_settings.dart' show SettingTile, SettingsCard, settingsMuted;
import '../widgets/skeleton.dart';
import '../../services/language.dart';
import '../widgets/app_dialog.dart';

/// Settings › Accounts & services › Last.fm & ListenBrainz: where what you play is shared.
class ScrobbleSettings extends StatelessWidget {
  const ScrobbleSettings({super.key, this.scrobbler, this.history});

  /// The app's scrobbler by default.
  final Scrobbler? scrobbler;

  /// The app's listening history by default.
  final PlayHistory? history;

  @override
  Widget build(BuildContext context) {
    final s = scrobbler ?? Scrobbler.instance;
    final history = this.history ?? PlayHistory.instance;
    final muted = settingsMuted(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s, history]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(tr.scrobbleBody, style: muted),
          ),
          SettingsCard(
            children: [
              for (final service in s.services)
                SettingTile(
                  icon: Icons.query_stats_rounded,
                  title: Text(service.label),
                  subtitle: Text(_status(s, service), style: muted),
                  control: service.connected
                      ? TextButton(onPressed: () => s.disconnect(service), child: Text(tr.disconnect))
                      : FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.inverse,
                            foregroundColor: AppColors.onInverse,
                          ),
                          onPressed: () => switch (service) {
                            LastFm() => showDialog<void>(
                              context: context,
                              builder: (_) => _LastFmSignInDialog(scrobbler: s),
                            ),
                            _ => showDialog<void>(
                              context: context,
                              builder: (_) => _ListenBrainzDialog(scrobbler: s),
                            ),
                          },
                          child: Text(tr.connect),
                        ),
                ),
            ],
          ),
          if (s.services.any((x) => x.connected)) ...[
            const SizedBox(height: 16),
            SettingsCard(
              children: [
                for (final service in s.services)
                  if (service.connected) _ImportTile(scrobbler: s, service: service, history: history),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _status(Scrobbler s, ScrobbleService service) {
    if (!service.connected) return tr.notConnected;
    final who = service.user == null ? tr.connected : tr.connectedAs('${service.user}');
    final n = s.pending(service);
    return n == 0 ? who : tr.listensWaiting(n, who);
  }
}

/// "Bring in your past listens" from [service] into the listening history.
class _ImportTile extends StatelessWidget {
  const _ImportTile({required this.scrobbler, required this.service, required this.history});

  final Scrobbler scrobbler;
  final ScrobbleService service;
  final PlayHistory history;

  Future<void> _import(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    void say(String m) => messenger?.showSnackBar(SnackBar(content: Text(m)));
    try {
      final added = await scrobbler.importHistory(
        service,
        history: history,
        library: PlayerScope.read(context).library,
      );
      say(switch (added) {
        0 => tr.noNewListens,
        1 => tr.listensAdded(1),
        _ => tr.listensAdded(added),
      });
    } on ScrobbleError catch (e) {
      debugPrint('Import from ${service.label}: $e');
      say(e.signedOut ? tr.serviceSignedOut(service.label) : tr.couldntReachService(service.label));
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = settingsMuted(context);
    final running = scrobbler.importing == service;
    final busy = scrobbler.importing != null;
    final String subtitle;
    if (running) {
      subtitle = tr.readingListens('${scrobbler.importRead}');
    } else if (!history.enabled) {
      subtitle = tr.turnOnHistoryFirst;
    } else {
      subtitle = tr.bringInBody;
    }
    return SettingTile(
      icon: Icons.download_for_offline_outlined,
      title: Text(tr.bringInHistory(service.label)),
      subtitle: Text(subtitle, style: muted),
      control: running
          ? TextButton(onPressed: scrobbler.cancelImport, child: Text(tr.stop))
          : TextButton(onPressed: busy || !history.enabled ? null : () => _import(context), child: Text(tr.bringIn)),
    );
  }
}

/// Paste, check and save a ListenBrainz user token.
class _ListenBrainzDialog extends StatefulWidget {
  const _ListenBrainzDialog({required this.scrobbler});

  final Scrobbler scrobbler;

  @override
  State<_ListenBrainzDialog> createState() => _ListenBrainzDialogState();
}

class _ListenBrainzDialogState extends State<_ListenBrainzDialog> {
  final _token = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      await widget.scrobbler.connectListenBrainz(_token.text);
      if (mounted) Navigator.pop(context);
    } on ScrobbleError catch (e) {
      if (mounted) {
        setState(() => _error = e.retry ? tr.couldntReachService('ListenBrainz') : e.message);
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: Text(tr.connectService('ListenBrainz')),
    width: DialogWidth.regular,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr.listenBrainzTokenBody,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => launchUrl(
              Uri.parse(ListenBrainz.tokenPage),
              mode: LaunchMode.externalApplication,
            ).catchError((_) => false),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(tr.openListenBrainzSettings),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _token,
          autofocus: true,
          obscureText: true,
          enabled: !_checking,
          decoration: InputDecoration(
            labelText: tr.userToken,
            border: const OutlineInputBorder(),
            isDense: true,
            errorText: _error,
            errorMaxLines: 2,
          ),
          onSubmitted: (_) => _save(),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.cancel)),
      ListenableBuilder(
        listenable: _token,
        builder: (context, _) => FilledButton(
          onPressed: _checking || _token.text.trim().isEmpty ? null : _save,
          child: Text(_checking ? tr.checking : tr.connect),
        ),
      ),
    ],
  );
}

/// Opens Last.fm in the browser and waits there until the user has allowed Riflay.
class _LastFmSignInDialog extends StatefulWidget {
  const _LastFmSignInDialog({required this.scrobbler});

  final Scrobbler scrobbler;

  @override
  State<_LastFmSignInDialog> createState() => _LastFmSignInDialogState();
}

class _LastFmSignInDialogState extends State<_LastFmSignInDialog> {
  /// How long a sign-in waits; Last.fm's own token lasts an hour.
  static const _giveUpAfter = Duration(minutes: 10);

  Uri? _page;
  String? _error;
  Timer? _poll;
  final _started = Stopwatch();

  LastFm get _lastFm => widget.scrobbler.lastFm;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _begin() async {
    setState(() {
      _error = null;
      _page = null;
    });
    try {
      final page = await _lastFm.beginSignIn();
      if (!mounted) return;
      setState(() => _page = page);
      _started
        ..reset()
        ..start();
      await _open();
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
    } on ScrobbleError catch (e) {
      debugPrint('Last.fm sign-in failed: $e');
      if (mounted) setState(() => _error = tr.couldntReachService('Last.fm'));
    }
  }

  Future<void> _open() async {
    final page = _page;
    if (page != null) await launchUrl(page, mode: LaunchMode.externalApplication).catchError((_) => false);
  }

  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      if (await _lastFm.finishSignIn()) {
        _poll?.cancel();
        await widget.scrobbler.connected(_lastFm);
        if (mounted) Navigator.pop(context);
      } else if (_started.elapsed > _giveUpAfter) {
        _poll?.cancel();
        if (mounted) setState(() => _error = tr.signInTooLong);
      }
    } on ScrobbleError catch (e) {
      if (e.retry) return; // offline for a moment: the next check tries again
      _poll?.cancel();
      if (mounted) setState(() => _error = tr.lastfmDidntFinish);
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary);
    return AppDialog(
      title: Text(tr.connectService('Last.fm')),
      width: DialogWidth.regular,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null)
            Text(_error!, style: muted)
          else if (_page == null)
            const SkeletonBox(height: 8, radius: 4)
          else ...[
            Text(tr.lastfmAllowBody, style: muted),
            const SizedBox(height: 16),
            const SkeletonBox(height: 8, radius: 4),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.cancel)),
        if (_error != null)
          FilledButton(onPressed: _begin, child: Text(tr.tryAgain))
        else if (_page != null)
          FilledButton(onPressed: _open, child: Text(tr.openLastfmAgain)),
      ],
    );
  }
}
