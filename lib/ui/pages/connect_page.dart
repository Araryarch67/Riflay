import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../platform/features.dart';
import '../../services/connect/connect_controller.dart';
import '../../services/connect/connect_host.dart';
import '../../services/connect/connect_channel.dart';
import '../../services/connect/connect_protocol.dart';
import '../../services/connect/connect_rtc_webrtc.dart';
import '../../services/connect/connect_share.dart';
import '../../services/language.dart';
import '../../services/listen_together/protocol.dart' show SharedTrack;
import '../../services/ui_beat.dart';
import '../player_scope.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/page_scaffold.dart';
import 'connect_share_page.dart';
import 'listen_qr.dart';
import 'sound_settings.dart' show SettingsCard;

/// Riflay Connect: on a computer, allow other devices to control it and pair them; on any device, control a
/// paired computer. [host] and [controller] are only for tests.
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key, this.host, this.controller, this.canHost, this.share});

  final ConnectHost? host;
  final ConnectController? controller;
  final ConnectShare? share;

  /// Whether this device can be the one controlled; [Features.connectHost] when null.
  final bool? canHost;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  ConnectHost? _host;
  late final ConnectController _controller = widget.controller ?? ConnectController.instance;
  ConnectShare? _share;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_host == null && (widget.canHost ?? Features.connectHost)) {
      _host = widget.host ?? ConnectHost.of(PlayerScope.read(context));
      unawaited(_host!.load());
    }
    _share ??= widget.share ?? ConnectShare.of(PlayerScope.read(context));
    _controller.share ??= _share;
    _controller.rtc ??= connectRtcOf(PlayerScope.read(context));
    unawaited(_controller.load());
  }

  @override
  Widget build(BuildContext context) {
    final compact = context.dependOnInheritedWidgetOfExactType<ShellScope>()?.compact ?? false;
    final pad = compact ? 16.0 : 24.0;
    final text = Theme.of(context).textTheme;
    return PageScaffold(
      title: tr.connectTitle,
      slivers: [
        SliverToBoxAdapter(
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr.connectTitle, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(tr.connectIntro, style: text.bodyMedium?.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 16),
                    SettingsCard(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.library_music_rounded),
                          title: Text(tr.connectShareTitle),
                          subtitle: Text(tr.connectShareSummary),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            final shell = ShellScope.of(context);
                            unawaited(
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(builder: (_) => shell.wrap(ConnectSharePage(share: _share))),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    if (_host != null) ...[const SizedBox(height: 24), _HostSection(host: _host!)],
                    const SizedBox(height: 32),
                    _ControllerSection(controller: _controller),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

TextStyle? _muted(BuildContext context) =>
    Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary);

TextStyle? _heading(BuildContext context) =>
    Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800);

class _HostSection extends StatelessWidget {
  const _HostSection({required this.host});

  final ConnectHost host;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: host,
    builder: (context, _) {
      final pending = host.pending;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr.connectThisComputer, style: _heading(context)),
          const SizedBox(height: 12),
          SettingsCard(
            children: [
              SwitchListTile(
                title: Text(tr.connectAllow),
                subtitle: Text(host.unreachable ? tr.connectUnreachable : tr.connectAllowSubtitle),
                value: host.enabled,
                onChanged: host.loaded ? (on) => unawaited(host.setEnabled(on)) : null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (pending != null)
            _PairRequest(host: host, request: pending)
          else if (host.pairingCode != null)
            _PairingCode(host: host)
          else
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.inverse,
                foregroundColor: AppColors.onInverse,
                minimumSize: const Size(160, 48),
              ),
              onPressed: host.loaded ? () => unawaited(host.beginPairing()) : null,
              child: Text(tr.connectPairDevice),
            ),
          const SizedBox(height: 24),
          Text(tr.connectPairedDevices, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (host.controllers.isEmpty)
            Text(tr.connectNoControllers, style: _muted(context))
          else
            SettingsCard(
              children: [
                for (final c in host.controllers)
                  ListTile(
                    leading: const Icon(Icons.devices_other_rounded),
                    title: Text(c.name),
                    subtitle: host.isActive(c.id) ? Text(tr.connectActiveNow) : null,
                    trailing: TextButton(onPressed: () => unawaited(host.revoke(c.id)), child: Text(tr.connectRevoke)),
                  ),
              ],
            ),
        ],
      );
    },
  );
}

/// Someone entered the code: nothing is allowed until the owner says so.
class _PairRequest extends StatelessWidget {
  const _PairRequest({required this.host, required this.request});

  final ConnectHost host;
  final ConnectPairRequest request;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.elevated, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr.connectRequest(request.name), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.inverse,
                  foregroundColor: AppColors.onInverse,
                  minimumSize: const Size(120, 48),
                ),
                onPressed: () => unawaited(host.approve()),
                child: Text(tr.allow),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(120, 48)),
                onPressed: host.deny,
                child: Text(tr.connectDeny),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _PairingCode extends StatelessWidget {
  const _PairingCode({required this.host});

  final ConnectHost host;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr.connectPairingCode, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: SelectableText(
            host.pairingCode!,
            maxLines: 1,
            style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 2),
          ),
        ),
        const SizedBox(height: 16),
        QrImageView(
          data: host.pairingLink.toString(),
          size: 200,
          backgroundColor: Colors.white,
          padding: const EdgeInsets.all(12),
          semanticsLabel: tr.connectPairingQrSemantics,
        ),
        const SizedBox(height: 12),
        Text(tr.connectPairingHowTo, style: _muted(context)),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: host.cancelPairing, child: Text(tr.connectCancelPairing)),
      ],
    );
  }
}

class _ControllerSection extends StatefulWidget {
  const _ControllerSection({required this.controller});

  final ConnectController controller;

  @override
  State<_ControllerSection> createState() => _ControllerSectionState();
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue next) =>
      next.copyWith(text: next.text.toUpperCase());
}

class _ControllerSectionState extends State<_ControllerSection> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  ConnectController get _c => widget.controller;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _pair(String input) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _c.pair(input);
      _code.clear();
    } on ConnectPairException catch (e) {
      if (mounted) {
        setState(
          () => _error = switch (e.problem) {
            ConnectPairProblem.badCode => tr.connectBadCode,
            ConnectPairProblem.unreachable => tr.connectPairUnreachable,
            ConnectPairProblem.notFound => tr.connectPairNotFound,
            ConnectPairProblem.denied => tr.connectPairDenied,
          },
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ListenQrScanner(parse: connectCodeFrom, invalidMessage: () => tr.notAConnectQr),
      ),
    );
    if (!mounted || code == null) return;
    _code.text = code;
    await _pair(code);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _c,
    builder: (context, _) {
      final text = Theme.of(context).textTheme;
      final canCode = connectCodeFrom(_code.text) != null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr.connectControlTitle, style: _heading(context)),
          const SizedBox(height: 8),
          Text(tr.connectControlIntro, style: _muted(context)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  maxLength: 11,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9-]')), _UpperCase()],
                  style: const TextStyle(letterSpacing: 3, fontWeight: FontWeight.w700),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => canCode && !_busy ? _pair(_code.text) : null,
                  decoration: InputDecoration(labelText: tr.connectPairingCode, counterText: ''),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.inverse,
                  foregroundColor: AppColors.onInverse,
                  minimumSize: const Size(80, 48),
                ),
                onPressed: canCode && !_busy ? () => _pair(_code.text) : null,
                child: Text(tr.connectPair),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _scan,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: Text(tr.scanQr),
          ),
          if (_busy || _error != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(_busy ? tr.connectWaitingConfirm : _error!, style: _muted(context)),
            ),
          ],
          if (_c.hosts.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(tr.connectYourComputers, style: text.titleMedium),
            const SizedBox(height: 8),
            SettingsCard(
              children: [
                for (final h in _c.hosts)
                  ListTile(
                    selected: _c.active?.id == h.id,
                    leading: const Icon(Icons.computer_rounded),
                    title: Text(h.name),
                    subtitle: _c.active?.id == h.id ? Text(_statusText()) : null,
                    onTap: _c.active?.id == h.id ? null : () => unawaited(_c.connect(h)),
                    trailing: TextButton(onPressed: () => unawaited(_c.forget(h)), child: Text(tr.connectForget)),
                  ),
              ],
            ),
          ],
          if (_c.active != null) ...[const SizedBox(height: 24), _RemotePanel(controller: _c)],
        ],
      );
    },
  );

  String _statusText() => switch (_c.state) {
    ConnectLinkState.connected => tr.connectConnected,
    ConnectLinkState.connecting => tr.connectConnecting,
    ConnectLinkState.disconnected => tr.connectDisconnected,
  };
}

/// What the controlled computer plays, and the buttons to steer it. While not connected it shows the last state
/// it had, dimmed and not tappable, with "Not connected" in words.
class _RemotePanel extends StatefulWidget {
  const _RemotePanel({required this.controller});

  final ConnectController controller;

  @override
  State<_RemotePanel> createState() => _RemotePanelState();
}

class _RemotePanelState extends State<_RemotePanel> {
  UiBeatListener? _beat;
  double? _dragging;

  ConnectController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_follow);
    _follow();
  }

  /// The position is counted on once a second, and only while the song plays.
  void _follow() {
    final ticking = _c.state == ConnectLinkState.connected && (_c.remote?.playing ?? false);
    if (ticking && _beat == null) {
      _beat = UiBeat.listen(const Duration(seconds: 1), (_) {
        if (mounted && _dragging == null) setState(() {});
      });
    } else if (!ticking) {
      _beat?.cancel();
      _beat = null;
    }
  }

  @override
  void dispose() {
    _c.removeListener(_follow);
    _beat?.cancel();
    super.dispose();
  }

  String _clock(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final connected = _c.state == ConnectLinkState.connected;
    final s = _c.remote;
    final end = s?.durationMs;
    final position = _c.position.inMilliseconds;
    final seekable = connected && end != null && end > 0 && s?.track != null;
    final local = PlayerScope.read(context);
    final shareable = local.currentTrack == null ? null : SharedTrack.of(local.currentTrack!);
    return Opacity(
      opacity: connected ? 1 : 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Row(
              children: [
                Icon(
                  connected ? Icons.check_circle_outline_rounded : Icons.cloud_off_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(switch (_c.state) {
                    ConnectLinkState.connected => tr.connectConnected,
                    ConnectLinkState.connecting => tr.connectConnecting,
                    ConnectLinkState.disconnected => tr.connectDisconnected,
                  }, style: _muted(context)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (s?.track case final track?) ...[
            Text(track.title, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800), maxLines: 2),
            Text(track.artist, style: _muted(context), maxLines: 1, overflow: TextOverflow.ellipsis),
          ] else
            Text(tr.connectNothingPlaying, style: _muted(context)),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(_clock(Duration(milliseconds: (_dragging ?? position.toDouble()).round()))),
              Expanded(
                child: Slider(
                  value: seekable ? (_dragging ?? position.toDouble()).clamp(0, end.toDouble()) : 0,
                  max: seekable ? end.toDouble() : 1,
                  onChanged: seekable ? (v) => setState(() => _dragging = v) : null,
                  onChangeEnd: (v) {
                    _c.seek(Duration(milliseconds: v.round()));
                    setState(() => _dragging = null);
                  },
                ),
              ),
              Text(_clock(Duration(milliseconds: end ?? 0))),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: tr.previous,
                onPressed: connected ? _c.previous : null,
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              IconButton.filled(
                tooltip: (s?.playing ?? false) ? tr.pause : tr.play,
                iconSize: 32,
                onPressed: connected ? ((s?.playing ?? false) ? _c.pause : _c.play) : null,
                icon: Icon((s?.playing ?? false) ? Icons.pause_rounded : Icons.play_arrow_rounded),
              ),
              IconButton(
                tooltip: tr.next,
                onPressed: connected ? _c.next : null,
                icon: const Icon(Icons.skip_next_rounded),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                tooltip: tr.connectShuffle,
                isSelected: s?.shuffle ?? false,
                onPressed: connected ? () => _c.setShuffle(!(s?.shuffle ?? false)) : null,
                icon: const Icon(Icons.shuffle_rounded),
              ),
              IconButton(
                tooltip: switch (s?.repeat ?? ConnectRepeat.off) {
                  ConnectRepeat.off => tr.connectRepeatOff,
                  ConnectRepeat.all => tr.connectRepeatAll,
                  ConnectRepeat.one => tr.connectRepeatOne,
                },
                isSelected: (s?.repeat ?? ConnectRepeat.off) != ConnectRepeat.off,
                onPressed: connected
                    ? () => _c.setRepeat(
                        ConnectRepeat.values[((s?.repeat ?? ConnectRepeat.off).index + 1) %
                            ConnectRepeat.values.length],
                      )
                    : null,
                icon: Icon(
                  (s?.repeat ?? ConnectRepeat.off) == ConnectRepeat.one
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.volume_up_rounded, size: 20),
              Expanded(
                child: Slider(
                  value: (s?.volume ?? 0).clamp(0, 1),
                  semanticFormatterCallback: (v) => '${(v * 100).round()}%',
                  onChanged: connected && (s?.canSetVolume ?? false) ? _c.setVolume : null,
                ),
              ),
            ],
          ),
          if (s != null && s.queue.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(tr.queue, style: text.titleMedium),
            const SizedBox(height: 4),
            for (final (i, t) in s.queue.indexed)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                selected: i == s.queueIndex,
                title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
          if (shareable != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: connected ? () => _c.addToQueue(shareable) : null,
              icon: const Icon(Icons.playlist_add_rounded),
              label: Text(tr.connectAddHere),
            ),
            const SizedBox(height: 4),
            Text(tr.connectAddHint, style: _muted(context)),
          ],
          const SizedBox(height: 16),
          OutlinedButton(onPressed: _c.disconnect, child: Text(tr.connectStopControlling)),
        ],
      ),
    );
  }
}
