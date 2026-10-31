import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/play_history.dart';
import '../../services/scrobbler.dart';
import '../player_scope.dart';
import '../theme.dart';
import 'sound_settings.dart' show SettingTile, SettingsCard, settingsMuted;

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
            child: Text(
              'Songs you listen to past the halfway mark (or 4 minutes) are added to your profile there. '
              'Listens made offline are sent once you\'re back online.',
              style: muted,
            ),
          ),
          SettingsCard(
            children: [
              for (final service in s.services)
                SettingTile(
                  icon: Icons.query_stats_rounded,
                  title: Text(service.label),
                  subtitle: Text(_status(s, service), style: muted),
                  control: service.connected
                      ? TextButton(onPressed: () => s.disconnect(service), child: const Text('Disconnect'))
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
                          child: const Text('Connect'),
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
    if (!service.connected) return 'Not connected';
    final who = service.user == null ? 'Connected' : 'Connected as ${service.user}';
    final n = s.pending(service);
    return n == 0 ? who : '$who. $n ${n == 1 ? 'listen' : 'listens'} waiting to be sent.';
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
        0 => 'No new listens to bring in',
        1 => '1 listen added to your history',
        _ => '$added listens added to your history',
      });
    } on ScrobbleError catch (e) {
      debugPrint('Import from ${service.label}: $e');
      say(
        e.signedOut
            ? '${service.label} signed you out. Connect it again.'
            : 'Couldn\'t reach ${service.label}. Try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = settingsMuted(context);
    final running = scrobbler.importing == service;
    final busy = scrobbler.importing != null;
    final String subtitle;
    if (running) {
      subtitle = 'Reading your listens: ${scrobbler.importRead} so far';
    } else if (!history.enabled) {
      subtitle = 'Turn on the listening history in Library & downloads first.';
    } else {
      subtitle =
          'Adds the songs you played elsewhere to your stats, Wraps and Most played. Ones already here are skipped.';
    }
    return SettingTile(
      icon: Icons.download_for_offline_outlined,
      title: Text('Bring in your ${service.label} history'),
      subtitle: Text(subtitle, style: muted),
      control: running
          ? TextButton(onPressed: scrobbler.cancelImport, child: const Text('Stop'))
          : TextButton(
              onPressed: busy || !history.enabled ? null : () => _import(context),
              child: const Text('Bring in'),
            ),
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
        setState(() => _error = e.retry ? 'Couldn\'t reach ListenBrainz. Try again.' : e.message);
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Connect ListenBrainz'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Copy your user token from your ListenBrainz settings and paste it here.',
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
              label: const Text('Open ListenBrainz settings'),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _token,
            autofocus: true,
            obscureText: true,
            enabled: !_checking,
            decoration: InputDecoration(
              labelText: 'User token',
              border: const OutlineInputBorder(),
              isDense: true,
              errorText: _error,
              errorMaxLines: 2,
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ListenableBuilder(
        listenable: _token,
        builder: (context, _) => FilledButton(
          onPressed: _checking || _token.text.trim().isEmpty ? null : _save,
          child: Text(_checking ? 'Checking…' : 'Connect'),
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
      if (mounted) setState(() => _error = 'Couldn\'t reach Last.fm. Try again.');
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
        if (mounted) setState(() => _error = 'The sign-in took too long. Try again.');
      }
    } on ScrobbleError catch (e) {
      if (e.retry) return; // offline for a moment: the next check tries again
      _poll?.cancel();
      if (mounted) setState(() => _error = 'Last.fm didn\'t finish the sign-in. Try again.');
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary);
    return AlertDialog(
      title: const Text('Connect Last.fm'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null)
              Text(_error!, style: muted)
            else if (_page == null)
              const LinearProgressIndicator()
            else ...[
              Text(
                'Allow Riflay on the Last.fm page that opened in your browser. This closes by itself once you have.',
                style: muted,
              ),
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        if (_error != null)
          FilledButton(onPressed: _begin, child: const Text('Try again'))
        else if (_page != null)
          FilledButton(onPressed: _open, child: const Text('Open Last.fm again')),
      ],
    );
  }
}
