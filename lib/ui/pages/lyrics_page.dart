import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../models/track.dart';
import '../../services/layout_prefs.dart';
import '../../services/lyrics.dart';
import '../../services/lyrics_translation.dart';
import '../../services/player_controller.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/smooth_scroll.dart';

/// Lyrics of whatever is playing, following the song line by line.
///
/// Lives in the content area on desktop and full screen on phones. The
/// background is the cover's own colour, like the now-playing view.
class LyricsPage extends StatelessWidget {
  const LyricsPage({super.key, this.fullScreen = false});

  /// Phone: pushed over everything, with its own close button and mini controls.
  final bool fullScreen;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.of(context);
    final track = c.currentTrack;
    final text = Theme.of(context).textTheme;
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return AccentBuilder(
      track: track,
      builder: (context, accent) => Material(
        color: track == null ? AppColors.panel : Color.lerp(accent, Colors.black, 0.25),
        child: SafeArea(
          bottom: fullScreen,
          top: fullScreen || ShellScope.of(context).compact,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    if (ShellScope.of(context).history != null && !fullScreen)
                      const SizedBox(width: 8)
                    else if (canPop)
                      IconButton(
                        tooltip: fullScreen ? 'Close' : 'Back',
                        color: Colors.white,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(fullScreen ? Icons.keyboard_arrow_down_rounded : Icons.arrow_back_rounded),
                      )
                    else
                      const SizedBox(width: 8),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Lyrics', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          if (track != null)
                            Text(
                              '${track.title} · ${track.artist}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall?.copyWith(color: Colors.white70),
                            ),
                        ],
                      ),
                    ),
                    if (track != null) LyricsExtrasButtons(key: ValueKey(track.id), track: track),
                  ],
                ),
              ),
              Expanded(
                child: track == null ? const _Message('Play a song to see its lyrics here.') : LyricsView(track: track),
              ),
              if (fullScreen && track != null) ...[
                const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: SeekBar()),
                const TransportControls(large: true),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The lyrics of [track] following the song, without a header or background:
/// the lyrics page and the full-screen player both show it.
class LyricsView extends StatelessWidget {
  const LyricsView({super.key, required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) => ShaderMask(
    // Lines fade out at the edges instead of being cut off.
    blendMode: BlendMode.dstIn,
    shaderCallback: (rect) => const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
      stops: [0, 0.08, 0.92, 1],
    ).createShader(rect),
    child: _LyricsLoader(key: ValueKey(track.id), track: track),
  );
}

class _LyricsLoader extends StatefulWidget {
  const _LyricsLoader({super.key, required this.track});

  final Track track;

  @override
  State<_LyricsLoader> createState() => _LyricsLoaderState();
}

class _LyricsLoaderState extends State<_LyricsLoader> {
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
      if (snap.hasError) {
        return _Message(
          'Couldn\'t load lyrics. Check your internet connection.',
          action: TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => setState(() => _lyrics = LyricsService.forTrack(widget.track)),
            child: const Text('Try again'),
          ),
        );
      }
      final lyrics = snap.data;
      if (lyrics == null) return const Center(child: CircularProgressIndicator(color: Colors.white));
      if (lyrics.instrumental) return const _Message('This song is instrumental. Enjoy the music.');
      if (lyrics.isEmpty) {
        return _Message(
          'No lyrics found for this song.',
          action: TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => useMyLyricsFile(context, widget.track),
            child: const Text('Use my lyrics file'),
          ),
        );
      }
      return FadeIn(
        child: lyrics.synced ? _SyncedLyrics(lyrics: lyrics) : _PlainLyrics(lyrics: lyrics),
      );
    },
  );
}

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
            toggle(LyricsTranslation.romanize, Icons.abc_rounded, 'Pronunciation'),
          if (has) ...[
            const SizedBox(width: 4),
            toggle(LyricsTranslation.translate, Icons.translate_rounded, 'Translation'),
          ],
          PopupMenuButton<String>(
            tooltip: 'More',
            iconSize: 20,
            iconColor: Colors.white60,
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) => switch (v) {
              'copy' => copyLyrics(context, l),
              'use' => useMyLyricsFile(context, widget.track),
              _ => removeMyLyrics(context, widget.track),
            },
            itemBuilder: (_) => [
              if (has) const PopupMenuItem(value: 'copy', child: Text('Copy lyrics')),
              const PopupMenuItem(value: 'use', child: Text('Use my lyrics file')),
              if (l.source == _userLyricsSource) const PopupMenuItem(value: 'remove', child: Text('Remove my lyrics')),
            ],
          ),
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
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    isSelected: on,
    visualDensity: VisualDensity.compact,
    iconSize: 20,
    color: Colors.white60,
    selectedIcon: Icon(icon, color: Colors.white),
    style: IconButton.styleFrom(backgroundColor: on ? Colors.white.withValues(alpha: 0.18) : null),
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
      dialogTitle: 'Choose a lyrics file',
    )).firstOrNull;
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 1 << 20) return say('That file is too big to be lyrics.');
    final text = utf8.decode(bytes, allowMalformed: true).replaceFirst('\u{feff}', '');
    final check = Lyrics.check(text, length: track.duration);
    if (!check.ok) return say(check.problem!);
    await UserLyrics.save(track, text);
    _lyricsChanged.value++;
    say('Your lyrics are in use');
  } catch (e) {
    debugPrint('Lyrics file: $e');
    say('Couldn\'t read that file.');
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
    messenger?.showSnackBar(const SnackBar(content: Text('Couldn\'t remove your lyrics.')));
  }
}

/// Puts the lyrics on the clipboard as plain text: one line each, no timestamps.
/// Lyrics can't be selected by touch (a long press would light every line), so
/// this is the way to take them.
Future<void> copyLyrics(BuildContext context, Lyrics l) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  await Clipboard.setData(ClipboardData(text: _lyricLines(l).join('\n')));
  messenger?.showSnackBar(const SnackBar(content: Text('Lyrics copied')));
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
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Couldn\'t translate these lyrics. Check your internet connection.')),
        );
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

class _Message extends StatelessWidget {
  const _Message(this.message, {this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white70),
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    ),
  );
}

/// Phone layout? Lyrics also work without the app shell around them (tests).
bool _isCompact(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ShellScope>()?.compact ?? false;

TextStyle? _lineStyle(BuildContext context) {
  final compact = _isCompact(context);
  final base = compact ? Theme.of(context).textTheme.headlineSmall : Theme.of(context).textTheme.headlineMedium;
  final scale = LayoutPrefs.instance.lyricsSize.scale;
  return base?.copyWith(
    fontSize: scale == 1 || base.fontSize == null ? null : base.fontSize! * scale,
    fontWeight: FontWeight.w800,
    height: 1.25,
    letterSpacing: -0.3,
  );
}

bool get _centred => LayoutPrefs.instance.lyricsAlign == LyricsAlign.centre;
TextAlign get _textAlign => _centred ? TextAlign.center : TextAlign.start;

class _Source extends StatelessWidget {
  const _Source(this.lyrics);

  final Lyrics lyrics;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 32, bottom: 48),
    child: Text(
      'Lyrics from ${lyrics.source}',
      textAlign: _textAlign,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
    ),
  );
}

class _PlainLyrics extends StatefulWidget {
  const _PlainLyrics({required this.lyrics});

  final Lyrics lyrics;

  @override
  State<_PlainLyrics> createState() => _PlainLyricsState();
}

class _PlainLyricsState extends State<_PlainLyrics> with _Extras {
  @override
  Lyrics get lyrics => widget.lyrics;

  @override
  Widget build(BuildContext context) {
    // Softer than a sung line: untimed lyrics all lit in white read as if every line were selected.
    final style = _lineStyle(context)?.copyWith(color: Colors.white.withValues(alpha: 0.8));
    final lines = lyrics.plain!.split('\n');
    return SmoothScroll(
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.symmetric(horizontal: _isCompact(context) ? 24 : 40, vertical: 24),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'These lyrics don\'t follow the song.',
              key: const ValueKey('lyrics-untimed'),
              textAlign: _textAlign,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
            ),
          ),
          if (extras == null)
            Text(lyrics.plain!, style: style, textAlign: _textAlign)
          else
            for (var i = 0; i < lines.length; i++) ...[
              Text(lines[i], style: style, textAlign: _textAlign),
              if (extraFor(i) case final extra?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    extra,
                    style: _extraStyle(context)?.copyWith(color: Colors.white70),
                    textAlign: _textAlign,
                  ),
                ),
            ],
          _Source(lyrics),
        ],
      ),
    );
  }
}

/// The synced lyrics of the playing song, wired to the player.
class _SyncedLyrics extends StatefulWidget {
  const _SyncedLyrics({required this.lyrics});

  final Lyrics lyrics;

  @override
  State<_SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends State<_SyncedLyrics> {
  late final PlayerController _c = PlayerScope.read(context);
  late final Stream<Duration> _ticks = _c.positionUpdates();
  late final Stream<Duration> _smooth = _c.smoothPosition();

  @override
  Widget build(BuildContext context) => SyncedLyricsView(
    lyrics: widget.lyrics,
    ticks: _ticks,
    smoothTicks: _smooth,
    position: () => _c.position,
    length: () => _c.currentTrack?.duration ?? _c.duration,
    onSeek: (to) {
      _c.seek(to);
      if (!_c.isPlaying) _c.play();
    },
  );
}

/// Lines that follow [ticks], the current one lit. A line with timed words
/// fills word by word, driven by [smoothTicks] (only that line listens to them).
/// Not selectable: a tap seeks, and nothing else happens on a long press.
class SyncedLyricsView extends StatefulWidget {
  const SyncedLyricsView({
    super.key,
    required this.lyrics,
    required this.ticks,
    required this.smoothTicks,
    this.position = _zero,
    this.length,
    required this.onSeek,
  });

  final Lyrics lyrics;

  /// The position a few times a second; the current line changes from it.
  final Stream<Duration> ticks;

  /// The position often enough to glide a word's fill.
  final Stream<Duration> smoothTicks;

  /// Where the song is right now, read when the view opens.
  final Duration Function() position;

  /// How long the song is. A position past it is a stale or bogus value
  /// (the last song's, or a stream still buffering): nothing is sung yet.
  final Duration? Function()? length;

  /// A line was tapped.
  final ValueChanged<Duration> onSeek;

  static Duration _zero() => Duration.zero;

  @override
  State<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<SyncedLyricsView> with _Extras {
  @override
  Lyrics get lyrics => widget.lyrics;

  late final List<GlobalKey> _keys = [for (final _ in widget.lyrics.lines) GlobalKey()];
  final _scroll = SmoothScrollController();
  StreamSubscription<Duration>? _sub;

  /// The line being sung. Rebuilt when it changes, not on every position tick.
  int _at = -1;

  /// The position as a line is picked for it; null when it can't be trusted.
  Duration? _trusted(Duration p) {
    final end = widget.length?.call();
    if (p < Duration.zero || (end != null && end > Duration.zero && p > end + const Duration(seconds: 2))) return null;
    return p;
  }

  // A little early: a line should light up as it starts, not after.
  int _lineAt(Duration position) {
    final p = _trusted(position);
    return p == null ? -1 : widget.lyrics.lineAt(p + const Duration(milliseconds: 150));
  }

  @override
  void initState() {
    super.initState();
    _at = _lineAt(widget.position());
    _sub = widget.ticks.listen((p) {
      final at = _lineAt(p);
      if (at != _at && mounted) setState(() => _at = at);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _showBack.dispose();
    _scroll.dispose();
    super.dispose();
  }

  int _current = -2;

  /// Follow the current line as it changes. Switched off when the person
  /// scrolls by hand; the "Back to current line" button (or a tap on a line)
  /// switches it on again.
  bool _following = true;

  /// The current line is out of view while not following: shows the button.
  final _showBack = ValueNotifier<bool>(false);

  void _scrollToCurrent() {
    final ctx = _current < 0 ? null : _keys[_current].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.35,
      duration: LayoutPrefs.dur(const Duration(milliseconds: 350)),
      curve: Curves.easeOutCubic,
    );
  }

  void _follow(int index) {
    if (index == _current) return;
    _current = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_following) {
        _scrollToCurrent();
      } else {
        _checkVisible();
      }
    });
  }

  /// Whether the current line is on screen, for the button.
  void _checkVisible() {
    final ro = _current < 0 ? null : _keys[_current].currentContext?.findRenderObject();
    final viewport = ro == null ? null : RenderAbstractViewport.maybeOf(ro);
    if (_following || !_scroll.hasClients || ro == null || viewport == null) {
      _showBack.value = false;
      return;
    }
    final top = viewport.getOffsetToReveal(ro, 0).offset;
    final bottom = viewport.getOffsetToReveal(ro, 1).offset;
    final pixels = _scroll.position.pixels;
    _showBack.value = pixels > top + 1 || pixels < bottom - 1;
  }

  void _pauseFollowing() {
    _following = false;
    _checkVisible();
  }

  void _resume() {
    _following = true;
    _showBack.value = false;
    _scrollToCurrent();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lyrics.lines;
    final style = _lineStyle(context);
    final pad = _isCompact(context) ? 24.0 : 40.0;
    final dim = LayoutPrefs.instance.dimUnsungLyrics;
    final unsung = dim ? Colors.black.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.75);
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is UserScrollNotification && n.direction != ScrollDirection.idle) {
          _pauseFollowing();
        } else if (!_following) {
          _checkVisible();
        }
        return false;
      },
      child: Listener(
        // A mouse wheel isn't a drag; it pauses following too.
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) _pauseFollowing();
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: Builder(
                builder: (context) {
                  final at = _at;
                  _follow(at);
                  return SingleChildScrollView(
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(pad, 24, pad, 0),
                    child: Column(
                      crossAxisAlignment: _centred ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < lines.length; i++)
                          _Line(
                            key: _keys[i],
                            text: lines[i].text.isEmpty ? '♪' : lines[i].text,
                            extra: extraFor(i),
                            style: style,
                            karaoke: i == at && lines[i].words.isNotEmpty
                                ? KaraokeLine(
                                    words: lines[i].words,
                                    sungColor: Colors.white,
                                    position: widget.position,
                                    ticks: widget.smoothTicks,
                                    trusted: _trusted,
                                  )
                                : null,
                            color: i == at && lines[i].words.isNotEmpty
                                ? unsung
                                : i == at
                                ? Colors.white
                                : i < at
                                ? Colors.white.withValues(alpha: 0.75)
                                : unsung,
                            onTap: () {
                              _following = true;
                              _showBack.value = false;
                              widget.onSeek(lines[i].time);
                            },
                          ),
                        _Source(widget.lyrics),
                      ],
                    ),
                  );
                },
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                child: ValueListenableBuilder<bool>(
                  valueListenable: _showBack,
                  builder: (context, show, _) => IgnorePointer(
                    ignoring: !show,
                    child: AnimatedOpacity(
                      duration: LayoutPrefs.dur(const Duration(milliseconds: 200)),
                      opacity: show ? 1 : 0,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.black.withValues(alpha: 0.6),
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        onPressed: _resume,
                        icon: const Icon(Icons.my_location_rounded, size: 18),
                        label: const Text('Back to current line'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How far a word-timed line has been sung at [position]: [sung] whole words,
/// then [fill] (0 to 1) of the next one.
({int sung, double fill}) karaokeProgress(List<LyricWord> words, Duration position) {
  var sung = 0;
  var fill = 0.0;
  for (final w in words) {
    if (position >= w.end) {
      sung++;
    } else {
      final span = (w.end - w.start).inMicroseconds;
      if (position > w.start && span > 0) fill = (position - w.start).inMicroseconds / span;
      break;
    }
  }
  return (sung: sung, fill: fill);
}

/// The current line of word-timed lyrics. The line is drawn once in the dim
/// colour (a plain [Text]); on top, a painter lays out the same text in the
/// sung colour and clips it to the sung part: whole words, then the left part
/// of the word being sung. The only thing that changes per frame is that clip,
/// so no widget rebuilds, no relayout, and the text is measured once per width.
class KaraokeLine extends StatefulWidget {
  const KaraokeLine({
    super.key,
    required this.words,
    required this.sungColor,
    required this.position,
    required this.ticks,
    required this.trusted,
  });

  final List<LyricWord> words;
  final Color sungColor;
  final Duration Function() position;
  final Stream<Duration> ticks;

  /// The position if it can be trusted, else null (nothing sung).
  final Duration? Function(Duration) trusted;

  @override
  State<KaraokeLine> createState() => KaraokeLineState();
}

class KaraokeLineState extends State<KaraokeLine> {
  late final ValueNotifier<({int sung, double fill})> _progress = ValueNotifier(_at(widget.position()));
  StreamSubscription<Duration>? _sub;

  ({int sung, double fill}) _at(Duration p) {
    final t = widget.trusted(p);
    return t == null ? (sung: 0, fill: 0.0) : karaokeProgress(widget.words, t);
  }

  /// Whole words sung and the fill (0 to 1) of the next one.
  @visibleForTesting
  ({int sung, double fill}) get progress => _progress.value;

  @override
  void initState() {
    super.initState();
    _sub = widget.ticks.listen((p) => _progress.value = _at(p));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.words.map((w) => w.text).join();
    final style = DefaultTextStyle.of(context).style;
    return CustomPaint(
      foregroundPainter: _KaraokePainter(
        words: widget.words,
        text: text,
        style: style.copyWith(color: widget.sungColor),
        align: _textAlign,
        direction: Directionality.of(context),
        scaler: MediaQuery.textScalerOf(context),
        progress: _progress,
      ),
      child: Text(text, textAlign: _textAlign),
    );
  }
}

class _KaraokePainter extends CustomPainter {
  _KaraokePainter({
    required this.words,
    required this.text,
    required this.style,
    required this.align,
    required this.direction,
    required this.scaler,
    required this.progress,
  }) : super(repaint: progress);

  final List<LyricWord> words;
  final String text;
  final TextStyle style;
  final TextAlign align;
  final TextDirection direction;
  final TextScaler scaler;
  final ValueListenable<({int sung, double fill})> progress;

  TextPainter? _tp;
  double _width = -1;

  /// Each word's boxes (more than one when it wraps), measured with the layout.
  final _boxes = <List<TextBox>>[];

  void _layout(double width) {
    if (_tp != null && width == _width) return;
    _width = width;
    final tp = _tp ??= TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: align,
      textDirection: direction,
      textScaler: scaler,
    );
    tp.layout(minWidth: width, maxWidth: width);
    _boxes.clear();
    var start = 0;
    for (final w in words) {
      final end = start + w.text.length;
      // Not the trailing space: a fill that stops at the letters looks right.
      final trimmed = start + w.text.trimRight().length;
      _boxes.add(
        trimmed > start ? tp.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: trimmed)) : const [],
      );
      start = end;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.value;
    if (p.sung == 0 && p.fill <= 0) return;
    _layout(size.width);
    final clip = Path();
    for (var i = 0; i < p.sung && i < _boxes.length; i++) {
      for (final b in _boxes[i]) {
        clip.addRect(b.toRect());
      }
    }
    if (p.fill > 0 && p.sung < _boxes.length) {
      final boxes = _boxes[p.sung];
      var left = boxes.fold<double>(0, (sum, b) => sum + (b.right - b.left)) * p.fill;
      for (final b in boxes) {
        final w = b.right - b.left;
        if (left <= 0) break;
        final part = left.clamp(0, w).toDouble();
        clip.addRect(
          b.direction == TextDirection.rtl
              ? Rect.fromLTRB(b.right - part, b.top, b.right, b.bottom)
              : Rect.fromLTRB(b.left, b.top, b.left + part, b.bottom),
        );
        left -= w;
      }
    }
    canvas
      ..save()
      ..clipPath(clip);
    _tp!.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_KaraokePainter old) =>
      old.text != text || old.style != style || old.align != align || old.scaler != scaler;
}

class _Line extends StatefulWidget {
  const _Line({
    super.key,
    required this.text,
    this.extra,
    required this.style,
    required this.color,
    this.karaoke,
    required this.onTap,
  });

  final String text;

  /// Pronunciation / translation, smaller, under the line.
  final String? extra;
  final TextStyle? style;
  final Color color;

  /// Stands in for the plain text while a word-timed line is being sung.
  final Widget? karaoke;
  final VoidCallback onTap;

  @override
  State<_Line> createState() => _LineState();
}

class _LineState extends State<_Line> {
  bool _hover = false;

  /// Only a real mouse lights a line it passes over; a stylus or finger can
  /// leave "hovering" stuck on a phone, which lit lines for no reason.
  void _hovered(PointerEvent e, bool on) {
    if (e.kind != PointerDeviceKind.mouse || _hover == on) return;
    setState(() => _hover = on);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (e) => _hovered(e, true),
    onExit: (e) => _hovered(e, false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: _centred ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
          children: [
            AnimatedDefaultTextStyle(
              duration: LayoutPrefs.dur(const Duration(milliseconds: 200)),
              style: (widget.style ?? const TextStyle()).copyWith(
                color: _hover && widget.karaoke == null ? Colors.white : widget.color,
              ),
              child: widget.karaoke ?? Text(widget.text, textAlign: _textAlign),
            ),
            if (widget.extra case final extra?)
              AnimatedDefaultTextStyle(
                duration: LayoutPrefs.dur(const Duration(milliseconds: 200)),
                style: (_extraStyle(context) ?? const TextStyle()).copyWith(
                  color: (_hover ? Colors.white : widget.color).withValues(alpha: 0.8),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(extra, textAlign: _textAlign),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
