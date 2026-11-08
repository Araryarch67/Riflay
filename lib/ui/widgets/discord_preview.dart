import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/discord_presence.dart';
import '../../services/player_controller.dart';
import 'app_logo.dart';
import '../../services/language.dart';

/// Settings › Discord: what the presence looks like on a Discord profile, and what it shows. The card draws
/// [DiscordPresence.activity] itself, the map sent to Discord, for the song playing (or a sample).
class DiscordPresenceSettings extends StatelessWidget {
  const DiscordPresenceSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.of(context);
    final o = c.discordOptions;
    Widget option(String title, bool value, DiscordOptions Function(bool v) change) => SwitchListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(title),
      value: value,
      onChanged: (v) => c.setDiscordOptions(change(v)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 12), child: DiscordPreview()),
        option(tr.discordSongCover, o.cover, (v) => o.copyWith(cover: v)),
        option(tr.discordTime, o.time, (v) => o.copyWith(time: v)),
        option(tr.discordSongInList, o.songInList, (v) => o.copyWith(songInList: v)),
        option(tr.discordListenButton, o.listenButton, (v) => o.copyWith(listenButton: v)),
        option(tr.discordAppButton, o.appButton, (v) => o.copyWith(appButton: v)),
        option(tr.discordWhilePaused, o.whilePaused, (v) => o.copyWith(whilePaused: v)),
        option(tr.discordShowQuality, o.quality, (v) => o.copyWith(quality: v)),
      ],
    );
  }
}

/// A Discord profile's "Listening to" card, drawn from the activity Riflay sends.
class DiscordPreview extends StatefulWidget {
  const DiscordPreview({super.key});

  @override
  State<DiscordPreview> createState() => _DiscordPreviewState();
}

class _DiscordPreviewState extends State<DiscordPreview> {
  // Discord's own dark colours: this is a picture of Discord, not of Riflay.
  static const _card = Color(0xFF232428);
  static const _text = Color(0xFFF2F3F5);
  static const _muted = Color(0xFFB5BAC1);
  static const _button = Color(0xFF4E5058);

  /// Shown when nothing plays, so the options can still be tried.
  static final _sample = Track.youtube(
    videoId: 'sample',
    title: tr.previewYourSong,
    artist: tr.previewItsArtist,
    duration: const Duration(minutes: 3, seconds: 30),
  );

  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // The time on the card moves, as it does on Discord.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String _clock(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.of(context);
    final track = c.currentTrack ?? _sample;
    final playing = c.currentTrack == null || c.isPlaying;
    final a = c.discord.activity(
      track,
      position: c.currentTrack == null ? const Duration(minutes: 1, seconds: 12) : c.position,
      duration: c.duration ?? track.duration,
      playing: playing,
      // The song's own once mpv has read it; a sample while nothing plays.
      quality: c.currentTrack == null ? 'FLAC · 24-bit / 96 kHz' : c.presenceQuality,
    );
    final text = Theme.of(context).textTheme;
    final assets = (a['assets'] as Map).cast<String, Object?>();
    final image = assets['large_image'] as String?;
    final times = (a['timestamps'] as Map?)?.cast<String, Object?>();
    final buttons = [for (final b in a['buttons'] as List) (b as Map)['label'] as String];
    final now = DateTime.now().millisecondsSinceEpoch;
    final start = times?['start'] as int?;
    final end = times?['end'] as int?;
    final elapsed = start == null ? null : Duration(milliseconds: now - start);
    final total = start == null || end == null ? null : Duration(milliseconds: end - start);
    Widget picture() => ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.square(
        dimension: 72,
        child: image != null && image.startsWith('http')
            ? Image.network(image, fit: BoxFit.cover, errorBuilder: (_, _, _) => const _Logo())
            : const _Logo(),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // How the member list reads it.
        Row(
          children: [
            const CircleAvatar(radius: 12, backgroundColor: _button, child: Icon(Icons.person, size: 14)),
            const SizedBox(width: 8),
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '${tr.discordListeningTo} '),
                    TextSpan(
                      text: a['status_display_type'] == 2 ? a['details'] as String : 'Riflay',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(8)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'LISTENING TO RIFLAY',
                style: text.labelSmall?.copyWith(color: _text, fontWeight: FontWeight.w800, letterSpacing: 0.4),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      picture(),
                      if (assets['small_image'] != null)
                        Positioned(
                          right: -4,
                          bottom: -4,
                          child: Tooltip(
                            message: assets['small_text'] as String? ?? '',
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(color: _card, shape: BoxShape.circle),
                              child: const ClipOval(child: SizedBox.square(dimension: 22, child: _Logo())),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a['details'] as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(color: _text, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          a['state'] as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(color: _muted),
                        ),
                        Text(
                          assets['large_text'] as String? ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(color: _muted),
                        ),
                        if (!playing)
                          Text(
                            tr.paused,
                            style: text.bodySmall?.copyWith(color: _muted, fontStyle: FontStyle.italic),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (elapsed != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: total == null || total.inMilliseconds == 0
                        ? null
                        : (elapsed.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0),
                    minHeight: 4,
                    color: _text,
                    backgroundColor: _button,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_clock(elapsed), style: text.labelSmall?.copyWith(color: _muted)),
                    if (total != null) Text(_clock(total), style: text.labelSmall?.copyWith(color: _muted)),
                  ],
                ),
              ],
              for (final b in buttons) ...[
                const SizedBox(height: 8),
                Container(
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _button, borderRadius: BorderRadius.circular(4)),
                  child: Text(
                    b,
                    style: text.bodySmall?.copyWith(color: _text, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0xFF1E1F22),
    child: Padding(
      padding: EdgeInsets.all(8),
      child: FittedBox(child: AppLogo(size: 48)),
    ),
  );
}
