import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/listen_together/listen_together.dart';
import '../../services/listen_together/protocol.dart';
import '../../services/listen_together/transport.dart';
import '../../services/player_controller.dart';
import '../navigation.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/page_scaffold.dart';

/// Opens the Listen together page. From the phone's full-screen player the player closes first,
/// so the page is not hidden underneath it.
void openListenTogether(BuildContext context, {bool closePlayer = false}) {
  final shell = ShellScope.of(context);
  if (closePlayer) Navigator.of(context).maybePop();
  shell.open(const ListenTogetherPage(), location: Locations.listen);
}

/// A small button for the player: a plain icon, or "Listening with Ana" while in a session.
class ListenTogetherButton extends StatelessWidget {
  const ListenTogetherButton({super.key, this.size, this.color, this.closePlayer = false});

  final double? size;
  final Color? color;
  final bool closePlayer;

  @override
  Widget build(BuildContext context) {
    final session = ListenTogether.of(PlayerScope.read(context));
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final label = listenStatusLabel(session);
        if (label == null) {
          return IconButton(
            tooltip: 'Listen together',
            color: color,
            onPressed: () => openListenTogether(context, closePlayer: closePlayer),
            icon: Icon(Icons.group_outlined, size: size),
          );
        }
        return Tooltip(
          message: label,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ActionChip(
              visualDensity: VisualDensity.compact,
              backgroundColor: AppColors.accent.withValues(alpha: 0.18),
              side: BorderSide.none,
              avatar: Icon(Icons.group_rounded, size: 16, color: AppColors.accent),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              onPressed: () => openListenTogether(context, closePlayer: closePlayer),
            ),
          ),
        );
      },
    );
  }
}

/// "Listening with Ana" / "3 listening", or null outside a session.
String? listenStatusLabel(ListenTogether s) => switch (s.role) {
  ListenRole.none => null,
  ListenRole.guest => 'Listening with ${s.hostName ?? 'a friend'}',
  ListenRole.host => s.listeners.isEmpty ? 'Hosting' : '${s.listeners.length} listening',
};

/// Start a session, join one, or see the one you are in.
class ListenTogetherPage extends StatefulWidget {
  const ListenTogetherPage({super.key});

  @override
  State<ListenTogetherPage> createState() => _ListenTogetherPageState();
}

class _ListenTogetherPageState extends State<ListenTogetherPage> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  ListenMode _mode = ListenMode.wifi;

  StreamSubscription<List<FoundSession>>? _search;
  List<FoundSession> _nearby = const [];
  ListenTogether? _session;

  @override
  void initState() {
    super.initState();
    _name.text = _defaultName();
    SharedPreferences.getInstance()
        .then((p) {
          final saved = p.getString('listen.name');
          if (saved != null && saved.trim().isNotEmpty && mounted) _name.text = saved;
          if (p.getString('listen.mode') == 'internet' && mounted) setState(() => _mode = ListenMode.internet);
        })
        .catchError((Object _) {});
  }

  static String _defaultName() {
    try {
      final user = Platform.environment['USER'] ?? Platform.environment['USERNAME'] ?? '';
      if (user.isNotEmpty) return user[0].toUpperCase() + user.substring(1);
    } catch (_) {}
    return '';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = ListenTogether.of(PlayerScope.read(context));
    if (identical(s, _session)) return;
    _session = s;
    s.addListener(_followSession);
    _followSession();
  }

  /// Nearby sessions are searched only while idle.
  void _followSession() {
    final idle = _session!.role == ListenRole.none;
    if (idle && _search == null) {
      _search = _session!.findNearby().listen((found) {
        if (mounted) setState(() => _nearby = found);
      }, onError: (Object _) {});
    } else if (!idle && _search != null) {
      _search!.cancel();
      _search = null;
      _nearby = const [];
    }
  }

  @override
  void dispose() {
    _session?.removeListener(_followSession);
    _search?.cancel();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    try {
      (await SharedPreferences.getInstance()).setString('listen.name', _name.text.trim());
    } catch (_) {}
  }

  String get _who => _name.text.trim().isEmpty ? 'Me' : _name.text.trim();

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    await _saveName();
    try {
      await action();
    } catch (e) {
      debugPrint('Listen together: $e');
      if (mounted) setState(() => _error = _session?.problem ?? "Couldn't connect. Try again.");
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _setMode(ListenMode mode) async {
    setState(() => _mode = mode);
    try {
      (await SharedPreferences.getInstance()).setString('listen.mode', mode.name);
    } catch (_) {}
  }

  Future<void> _start() => _run(() => _session!.host(mode: _mode, name: _who));

  Future<void> _join(String code) => _run(() => _session!.join(code: code, name: _who));

  @override
  Widget build(BuildContext context) {
    final session = _session!;
    final compact = ShellScope.of(context).compact;
    final pad = compact ? 16.0 : 24.0;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final text = Theme.of(context).textTheme;
        final body = switch (session.role) {
          ListenRole.none => _idle(context),
          ListenRole.host => _hosting(context, session),
          ListenRole.guest => _guest(context, session),
        };
        final problem = session.problem ?? _error;
        return PageScaffold(
          title: 'Listen together',
          slivers: [
            SliverToBoxAdapter(
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(pad, 0, pad, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Listen together',
                                style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            if (session.role == ListenRole.host && session.mode == ListenMode.internet) ...[
                              const SizedBox(width: 10),
                              const BetaBadge(),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                        body,
                        if (problem != null) ...[
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline_rounded, size: 18, color: AppColors.textSecondary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(problem, style: text.bodyMedium?.copyWith(color: AppColors.textSecondary)),
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
        );
      },
    );
  }

  // Not in a session ------------------------------------------------------

  Widget _idle(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: AppColors.textSecondary);
    final canCode = ListenTogether.modeForCode(_code.text.trim()) != null;
    final internet = _mode == ListenMode.internet;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Play YouTube songs together with friends.', style: muted),
        const SizedBox(height: 20),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          maxLength: 24,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _saveName(),
          decoration: const InputDecoration(labelText: 'Your name', counterText: ''),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ListenMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ListenMode.wifi, label: Text('Same Wi-Fi')),
              ButtonSegment(
                value: ListenMode.internet,
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Text('Anywhere'), SizedBox(width: 8), BetaBadge()],
                ),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: _busy ? null : (v) => _setMode(v.first),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          internet
              ? "Connects through free public servers. Everything is encrypted, but it's new and can sometimes fail to connect."
              : 'Everyone needs to be on the same Wi-Fi.',
          style: muted,
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.inverse,
              foregroundColor: AppColors.onInverse,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: _busy ? null : _start,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start a session'),
          ),
        ),
        const SizedBox(height: 32),
        Text('Join', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Text('On this Wi-Fi', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (_nearby.isEmpty)
          Text('Looking for sessions on this network…', style: muted)
        else
          for (final s in _nearby)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: AppColors.hover,
                child: Icon(Icons.group_rounded, color: AppColors.textPrimary),
              ),
              title: Text(s.hostName),
              subtitle: const Text('Tap to join'),
              enabled: !_busy,
              onTap: () => _join(s.code),
            ),
        const SizedBox(height: 16),
        Text('Have a code?', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _code,
                maxLength: 11,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9-]')), _UpperCase()],
                style: const TextStyle(letterSpacing: 4, fontWeight: FontWeight.w700),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => canCode && !_busy ? _join(_code.text.trim()) : null,
                decoration: const InputDecoration(hintText: 'ABC123 or ABCDE-FGHJK', counterText: ''),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.inverse,
                foregroundColor: AppColors.onInverse,
                minimumSize: const Size(80, 48),
              ),
              onPressed: canCode && !_busy ? () => _join(_code.text.trim()) : null,
              child: const Text('Join'),
            ),
          ],
        ),
      ],
    );
  }

  // Hosting ---------------------------------------------------------------

  Widget _hosting(BuildContext context, ListenTogether s) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: AppColors.textSecondary);
    final code = s.code ?? '';
    final link = s.joinLink;
    final internet = s.mode == ListenMode.internet;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          internet ? 'Friends anywhere can join with this code.' : 'Friends on the same Wi-Fi can join with this code.',
          style: muted,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SelectableText(
                  internet ? code : _spaced(code),
                  maxLines: 1,
                  style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: internet ? 2 : 4),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Copy code',
              onPressed: () => _copy('Code copied', code),
              icon: const Icon(Icons.copy_rounded),
            ),
          ],
        ),
        if (link != null) ...[
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () => _copy('Link copied', link.toString()),
            icon: const Icon(Icons.link_rounded),
            label: const Text('Copy invite link'),
          ),
        ],
        const SizedBox(height: 24),
        Text('Listening', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (s.listeners.isEmpty)
          Text('Nobody has joined yet.', style: muted)
        else
          for (final name in s.listeners)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.person_outline_rounded),
              title: Text(name),
            ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Let friends suggest songs'),
          value: s.suggestionsAllowed,
          onChanged: (v) => s.setSuggestionsAllowed(v),
        ),
        const SizedBox(height: 16),
        Text('You pick the songs. Play any YouTube song and everyone follows.', style: muted),
        const SizedBox(height: 24),
        _leaveButton(s, 'End session'),
      ],
    );
  }

  // Guest -----------------------------------------------------------------

  Widget _guest(BuildContext context, ListenTogether s) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: AppColors.textSecondary);
    final host = s.hostName ?? 'a friend';
    final now = s.hostTrack;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                'Listening with $host',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            if (s.mode == ListenMode.internet) ...[const SizedBox(width: 8), const BetaBadge()],
          ],
        ),
        const SizedBox(height: 16),
        if (now == null)
          Text('Waiting for $host to play something.', style: muted)
        else
          _SongTile(song: now, size: 72, big: true),
        if (s.hostPlayingUnshareable) ...[
          const SizedBox(height: 12),
          Text(
            "$host is playing a song from their own files. It'll continue when they play a YouTube song.",
            style: muted,
          ),
        ],
        if (s.upNext.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Up next', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final song in s.upNext) _SongTile(song: song, size: 44),
        ],
        const SizedBox(height: 24),
        _leaveButton(s, 'Leave'),
      ],
    );
  }

  Widget _leaveButton(ListenTogether s, String label) => OutlinedButton(
    style: OutlinedButton.styleFrom(minimumSize: const Size(140, 48)),
    onPressed: () => s.leave(),
    child: Text(label),
  );

  static String _spaced(String code) => code.split('').join(' ');

  Future<void> _copy(String message, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue next) =>
      next.copyWith(text: next.text.toUpperCase());
}

class _SongTile extends StatelessWidget {
  const _SongTile({required this.song, required this.size, this.big = false});

  final SharedTrack song;
  final double size;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Artwork(track: song.toTrack(), size: size, radius: 4),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (big ? text.titleMedium : text.bodyLarge)?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A quiet outlined "Beta" pill.
class BetaBadge extends StatelessWidget {
  const BetaBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.textMuted),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Beta',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary, height: 1.3),
      ),
    );
  }
}
