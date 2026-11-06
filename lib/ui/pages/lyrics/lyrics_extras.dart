// The page's extras: Pronunciation / Translation, my lyrics file, Adjust timing, Copy lyrics.
part of '../lyrics_page.dart';

/// "Pronunciation" and "Translation" toggles, shown once the song has lyrics.
class LyricsExtrasButtons extends StatefulWidget {
  const LyricsExtrasButtons({super.key, required this.track});

  final Track track;

  @override
  State<LyricsExtrasButtons> createState() => LyricsExtrasButtonsState();
}

class LyricsExtrasButtonsState extends State<LyricsExtrasButtons> {
  late Future<Lyrics> _lyrics = LyricsService.forTrack(widget.track);

  @override
  void initState() {
    super.initState();
    _lyricsChanged.addListener(_reload);
  }

  @override
  void dispose() {
    _lyricsChanged.removeListener(_reload);
    super.dispose();
  }

  void _reload() => setState(() {
    _lyrics = LyricsService.forTrack(widget.track);
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<Lyrics>(
    future: _lyrics,
    builder: (context, snap) {
      final l = snap.data;
      if (l == null) return const SizedBox.shrink();
      final has = !l.isEmpty && !l.instrumental;
      Widget toggle(ValueNotifier<bool> option, IconData icon, String tooltip) => ValueListenableBuilder(
        valueListenable: option,
        builder: (context, on, _) =>
            LyricsToggleButton(on: on, icon: icon, tooltip: tooltip, onPressed: () => option.value = !on),
      );
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (has && LyricsTranslation.hasNonLatin(_lyricLines(l).join('\n')))
            toggle(LyricsTranslation.romanize, Icons.abc_rounded, tr.pronunciation),
          if (has) ...[
            const SizedBox(width: 4),
            toggle(LyricsTranslation.translate, Icons.translate_rounded, tr.translation),
          ],
          PopupMenuButton<String>(
            tooltip: tr.more,
            iconSize: 20,
            iconColor: AppColors.textSecondary,
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) => switch (v) {
              'copy' => copyLyrics(context, l),
              'timing' => showLyricsTiming(context, widget.track),
              'use' => useMyLyricsFile(context, widget.track),
              _ => removeMyLyrics(context, widget.track),
            },
            itemBuilder: (_) => [
              if (has) PopupMenuItem(value: 'copy', child: Text(tr.copyLyrics)),
              if (l.synced) PopupMenuItem(value: 'timing', child: Text(tr.adjustTiming)),
              if (Features.userLyrics) PopupMenuItem(value: 'use', child: Text(tr.useMyLyricsFile)),
              if (l.source == _userLyricsSource) PopupMenuItem(value: 'remove', child: Text(tr.removeMyLyrics)),
            ],
          ),
        ],
      );
    },
  );
}

/// A round ⋯ button for the lyrics page's header on a phone: Pronunciation, Translation, Copy, timing, my own lyrics
/// file, and the player's own options, so the header needs no second row.
class LyricsMoreMenu extends StatefulWidget {
  const LyricsMoreMenu({super.key, required this.track});

  final Track track;

  @override
  State<LyricsMoreMenu> createState() => _LyricsMoreMenuState();
}

class _LyricsMoreMenuState extends State<LyricsMoreMenu> {
  late Future<Lyrics> _lyrics = LyricsService.forTrack(widget.track);

  @override
  void initState() {
    super.initState();
    _lyricsChanged.addListener(_reload);
  }

  @override
  void dispose() {
    _lyricsChanged.removeListener(_reload);
    super.dispose();
  }

  void _reload() => setState(() {
    _lyrics = LyricsService.forTrack(widget.track);
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<Lyrics>(
    future: _lyrics,
    builder: (context, snap) {
      final l = snap.data;
      final has = l != null && !l.isEmpty && !l.instrumental;
      PopupMenuItem<String> option(String value, IconData icon, String label, {bool? on}) => PopupMenuItem(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(label)),
            if (on ?? false) Icon(Icons.check_rounded, size: 18, color: AppColors.accent),
          ],
        ),
      );
      return PopupMenuButton<String>(
        tooltip: tr.more,
        useRootNavigator: true,
        style: IconButton.styleFrom(
          backgroundColor: AppColors.textPrimary.withValues(alpha: 0.1),
          foregroundColor: AppColors.textPrimary,
          fixedSize: const Size.square(44),
          shape: const CircleBorder(),
        ),
        icon: const Icon(Icons.more_horiz_rounded),
        onSelected: (v) => switch (v) {
          'romanize' => LyricsTranslation.romanize.value = !LyricsTranslation.romanize.value,
          'translate' => LyricsTranslation.translate.value = !LyricsTranslation.translate.value,
          'copy' => copyLyrics(context, l!),
          'timing' => showLyricsTiming(context, widget.track),
          'use' => useMyLyricsFile(context, widget.track),
          'remove' => removeMyLyrics(context, widget.track),
          _ => showPlayerMore(context, closePlayer: true),
        },
        itemBuilder: (_) => [
          if (has && LyricsTranslation.hasNonLatin(_lyricLines(l).join('\n')))
            option('romanize', Icons.abc_rounded, tr.pronunciation, on: LyricsTranslation.romanize.value),
          if (has) option('translate', Icons.translate_rounded, tr.translation, on: LyricsTranslation.translate.value),
          if (has) option('copy', Icons.copy_rounded, tr.copyLyrics),
          if (l != null && l.synced) option('timing', Icons.timer_outlined, tr.adjustTiming),
          if (Features.userLyrics) option('use', Icons.upload_file_rounded, tr.useMyLyricsFile),
          if (l != null && l.source == _userLyricsSource)
            option('remove', Icons.delete_outline_rounded, tr.removeMyLyrics),
          option('player', Icons.tune_rounded, tr.playerOptions),
        ],
      );
    },
  );
}

/// A small on/off button over lyrics: a soft light backdrop when on, so it
/// stays quiet next to the title on a phone.
class LyricsToggleButton extends StatelessWidget {
  const LyricsToggleButton({
    super.key,
    required this.on,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final bool on;
  final IconData icon;
  final String tooltip;

  /// Null greys the button out.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    isSelected: on,
    visualDensity: VisualDensity.compact,
    iconSize: 20,
    color: AppColors.textSecondary,
    selectedIcon: Icon(icon, color: AppColors.textPrimary),
    style: IconButton.styleFrom(backgroundColor: on ? AppColors.textPrimary.withValues(alpha: 0.18) : null),
    onPressed: onPressed,
    icon: Icon(icon),
  );
}

/// The source name of lyrics the person added themselves.
const _userLyricsSource = 'Your lyrics';

/// Bumped when the person's own lyrics change, so the shown lyrics are fetched again.
final _lyricsChanged = ValueNotifier<int>(0);

/// Lets the person pick an .lrc / .txt file as the lyrics of [track].
Future<void> useMyLyricsFile(BuildContext context, Track track) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  void say(String m) => messenger?.showSnackBar(SnackBar(content: Text(m)));
  try {
    final file = (await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['lrc', 'txt'],
      dialogTitle: tr.chooseLyricsFile,
    )).firstOrNull;
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 1 << 20) return say(tr.lyricsFileTooBig);
    final text = utf8.decode(bytes, allowMalformed: true).replaceFirst('\u{feff}', '');
    final check = Lyrics.check(text, length: track.duration);
    if (!check.ok) return say(check.problem!);
    await UserLyrics.save(track, text);
    _lyricsChanged.value++;
    say(tr.yourLyricsInUse);
  } catch (e) {
    debugPrint('Lyrics file: $e');
    say(tr.couldntReadFile);
  }
}

/// Goes back to the lyrics found online (or none).
Future<void> removeMyLyrics(BuildContext context, Track track) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await UserLyrics.remove(track);
    _lyricsChanged.value++;
  } catch (e) {
    debugPrint('Remove lyrics: $e');
    messenger?.showSnackBar(SnackBar(content: Text(tr.couldntRemoveLyrics)));
  }
}

/// "Earlier" / "Later" for a song's timed lyrics, saved for that song.
Future<void> showLyricsTiming(BuildContext context, Track track) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  useSafeArea: true,
  backgroundColor: AppColors.elevated,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
  builder: (context) => LyricsTimingSheet(track: track),
);

/// The controls of [showLyricsTiming]: half a second a step.
class LyricsTimingSheet extends StatelessWidget {
  const LyricsTimingSheet({super.key, required this.track});

  final Track track;

  static const step = Duration(milliseconds: 500);

  /// "On time", "1.5 s later", "0.5 s earlier".
  static String describe(Duration shift) {
    if (shift == Duration.zero) return tr.onTime;
    final seconds = (shift.inMilliseconds.abs() / 1000).toStringAsFixed(1);
    return shift.isNegative ? tr.secondsEarlier(seconds) : tr.secondsLater(seconds);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final shift = LyricsTiming.of(track);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: ValueListenableBuilder<Duration>(
        valueListenable: shift,
        builder: (context, now, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr.adjustTiming, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(tr.adjustTimingBody, style: text.bodySmall?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => LyricsTiming.set(track, shift.value - step),
                    child: Text(tr.earlier),
                  ),
                ),
                Expanded(
                  child: Text(
                    describe(now),
                    key: const ValueKey('lyrics-timing'),
                    textAlign: TextAlign.center,
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => LyricsTiming.set(track, shift.value + step),
                    child: Text(tr.later),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              child: TextButton(
                onPressed: now == Duration.zero ? null : () => LyricsTiming.set(track, Duration.zero),
                child: Text(tr.reset),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Puts the lyrics on the clipboard as plain text: one line each, no timestamps.
/// Lyrics can't be selected by touch (a long press would light every line), so
/// this is the way to take them.
Future<void> copyLyrics(BuildContext context, Lyrics l) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  await Clipboard.setData(ClipboardData(text: _lyricLines(l).join('\n')));
  messenger?.showSnackBar(SnackBar(content: Text(tr.lyricsCopied)));
}

List<String> _lyricLines(Lyrics l) => l.synced ? [for (final line in l.lines) line.text] : l.plain!.split('\n');

/// Fetches pronunciation / translation for [lyrics] once either is switched on.
mixin _Extras<T extends StatefulWidget> on State<T> {
  Lyrics get lyrics;
  List<LineExtras>? extras;
  bool _asked = false;

  bool get showRomanized => LyricsTranslation.romanize.value;
  bool get showTranslation => LyricsTranslation.translate.value;

  @override
  void initState() {
    super.initState();
    LyricsTranslation.romanize.addListener(_changed);
    LyricsTranslation.translate.addListener(_changed);
    _fetch();
  }

  @override
  void dispose() {
    LyricsTranslation.romanize.removeListener(_changed);
    LyricsTranslation.translate.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    setState(() {});
    _fetch();
  }

  void _fetch() {
    if (_asked || !(showRomanized || showTranslation)) return;
    _asked = true;
    LyricsTranslation.of(_lyricLines(lyrics)).then(
      (e) {
        if (mounted) setState(() => extras = e);
      },
      onError: (Object _) {
        _asked = false; // switching it off and on again retries
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr.couldntTranslateLyrics)));
      },
    );
  }

  /// The lines to show under line [i], or null.
  String? extraFor(int i) {
    final e = extras;
    if (e == null || i >= e.length) return null;
    final parts = [if (showRomanized) e[i].romanized, if (showTranslation) e[i].translation].nonNulls;
    return parts.isEmpty ? null : parts.join('\n');
  }
}

TextStyle? _extraStyle(BuildContext context) =>
    Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.3);
