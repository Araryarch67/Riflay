import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/language.dart';
import '../../../services/player_controller.dart';
import '../../../services/youtube_music_account.dart';
import '../../../services/ytmusic_web.dart' show WebResultKind;
import '../../../services/layout_prefs.dart';
import '../../theme.dart';
import '../../widgets/controls.dart';
import 'remote_results.dart' show openSearchHit;
import 'search_input.dart';
import 'search_parts.dart' show searchSurfaceCorners;
import 'soundcloud_results.dart' show SearchSource, SearchSourceButton;

/// The search field, with a dropdown of suggestions under it while typing
/// (completed searches, then artists / songs / albums to open directly) and
/// recent searches while it's empty. Arrow keys move, Enter picks, Esc closes.
class SearchBox extends StatefulWidget {
  const SearchBox({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    this.focusNode,
    this.onBar = false,
    this.onSourceSelected,
    this.flat = false,
  });

  /// On the centred search's card: no fill or pill of its own, the card being its shape.
  final bool flat;

  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<SearchSource>? onSourceSelected;

  /// In the title bar: a slimmer pill with a ring while typing. On the page it is a Material 3 search bar instead
  /// (56 high, a tonal fill, no outline).
  final bool onBar;

  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  Timer? _debounce;
  int _request = 0;

  List<String> _recent = const [];
  void _forgetSearches() {
    if (mounted) setState(() => _recent = const []);
  }

  List<String> _queries = const [];
  List<SearchHit> _hits = const [];

  /// Keyboard highlight across queries, then hits; -1 is none.
  int _highlight = -1;

  /// Closed by Esc / a pick until the next keystroke.
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    RecentSearches.cleared.addListener(_forgetSearches);
    _focus.addListener(_sync);
    SearchSource.current.addListener(_sourceChanged);
    RecentSearches.load().then((r) {
      if (!mounted) return;
      _recent = r;
      _sync(); // the field may have had focus before these loaded
    });
  }

  @override
  void dispose() {
    RecentSearches.cleared.removeListener(_forgetSearches);
    _debounce?.cancel();
    _focus.removeListener(_sync);
    SearchSource.current.removeListener(_sourceChanged);
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  String get _text => widget.controller.text.trim();

  void _sourceChanged() {
    _request++;
    _debounce?.cancel();
    _queries = const [];
    _hits = const [];
    _sync();
  }

  /// In the title bar the results page updates as you type (like the
  /// streaming apps), so suggestions would only cover it: just recent
  /// searches, while the box is empty.
  // The centred search drops nothing down: its results (and filters) show right under the box.
  int get _count => widget.flat
      ? 0
      : SearchSource.commandSuggestions(_text).isNotEmpty
      ? SearchSource.commandSuggestions(_text).length
      : _text.isEmpty
      ? _recent.length
      // The title bar's box shows results as you type; only recent searches (while empty) and source commands drop
      // down there.
      : widget.onBar
      ? 0
      : _queries.length + _hits.length;

  /// Shows the dropdown when there's something in it and the field has focus.
  void _sync() {
    final show = _focus.hasFocus && !_dismissed && _count > 0;
    if (show != _portal.isShowing) show ? _portal.show() : _portal.hide();
    if (mounted) setState(() {});
  }

  void _changed(String value) {
    widget.onChanged(value);
    _dismissed = false;
    _highlight = -1;
    _debounce?.cancel();
    final q = value.trim();
    if (q.startsWith(':')) {
      _request++;
      _queries = const [];
      _hits = const [];
      _sync();
      return;
    }
    if (q.isEmpty) {
      _queries = const [];
      _hits = const [];
      RecentSearches.load().then((r) {
        _recent = r;
        _sync();
      });
      _sync();
      return;
    }
    if (SearchSource.current.value != SearchSource.youtubeMusic) {
      _sourceChanged();
      return;
    }
    // The centred search drops no suggestions down while typing (its results show at once): nothing to fetch.
    if (widget.flat) return _sync();
    _debounce = Timer(const Duration(milliseconds: 120), () async {
      final id = ++_request;
      try {
        final s = await PlayerScope.read(context).ytMusic.suggestions(q);
        if (!mounted || id != _request) return;
        _queries = s.queries.take(6).toList();
        _hits = s.hits.take(5).toList();
      } catch (_) {
        if (id != _request) return;
        _queries = const [];
        _hits = const [];
      }
      _sync();
    });
  }

  void _close() {
    _dismissed = true;
    _highlight = -1;
    _sync();
  }

  void _pickQuery(String q) {
    widget.controller
      ..text = q
      ..selection = TextSelection.collapsed(offset: q.length);
    _close();
    widget.onSubmitted(q);
    RecentSearches.load().then((r) => _recent = r);
  }

  void _pickHit(SearchHit hit) {
    if (_text.isNotEmpty) RecentSearches.add(_text);
    _close();
    openSearchHit(context, hit);
  }

  void _pick(int i) {
    final commands = SearchSource.commandSuggestions(_text);
    if (commands.isNotEmpty) return _pickSource(commands[i]);
    if (_text.isEmpty) return _pickQuery(_recent[i]);
    if (i < _queries.length) return _pickQuery(_queries[i]);
    _pickHit(_hits[i - _queries.length]);
  }

  void _pickSource(SearchSource source) {
    final value = '${source.command} ';
    widget.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    widget.onChanged(value);
    _focus.requestFocus();
    _close();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (!_portal.isShowing) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
      final step = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      setState(() => _highlight = (_highlight + step).clamp(-1, _count - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter && _highlight >= 0) {
      _pick(_highlight);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final onBar = widget.onBar;
    final soft = onBar ? AppColors.textSecondary : scheme.onSurfaceVariant;
    return LayoutBuilder(
      builder: (context, box) => TapRegion(
        groupId: _link,
        onTapOutside: (_) => _close(),
        child: CompositedTransformTarget(
          link: _link,
          child: OverlayPortal(
            controller: _portal,
            overlayChildBuilder: (context) => CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.bottomLeft,
              offset: widget.flat ? const Offset(-8, 12) : const Offset(0, 6),
              child: Align(
                alignment: Alignment.topLeft,
                child: TapRegion(
                  groupId: _link,
                  child: SizedBox(width: box.maxWidth + (widget.flat ? 16 : 0), child: _dropdown(context)),
                ),
              ),
            ),
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _onKey,
              child: TextField(
                // Keep clicks in the suggestions inside the field's tap region.
                // Otherwise a mouse-down unfocuses it and removes the dropdown
                // before the suggestion receives mouse-up.
                groupId: _link,
                controller: widget.controller,
                focusNode: _focus,
                onChanged: _changed,
                // Clicking the field again brings the dropdown back after Esc / a pick.
                onTap: () {
                  _dismissed = false;
                  _sync();
                },
                textInputAction: TextInputAction.search,
                onSubmitted: (v) {
                  _close();
                  widget.onSubmitted(v);
                  if (v.trim().isNotEmpty) RecentSearches.load().then((r) => _recent = r);
                },
                style: text.bodyLarge?.copyWith(
                  color: onBar ? AppColors.textPrimary : scheme.onSurface,
                  fontWeight: onBar ? FontWeight.w500 : null,
                ),
                cursorColor: onBar ? AppColors.textPrimary : scheme.primary,
                decoration: InputDecoration(
                  hintText: tr.searchHint,
                  hintStyle: text.bodyLarge?.copyWith(color: soft),
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(left: onBar ? 0 : 4),
                    child: Icon(Icons.search_rounded, color: onBar ? soft : scheme.onSurface),
                  ),
                  suffixIcon: Padding(
                    padding: EdgeInsets.only(right: onBar ? 0 : 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.controller.text.isNotEmpty)
                          IconButton(
                            tooltip: tr.clear,
                            color: soft,
                            onPressed: () {
                              widget.controller.clear();
                              _changed('');
                              _focus.requestFocus();
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                        SearchSourceButton(
                          color: soft,
                          onSelected: (source) {
                            _close();
                            final select = widget.onSourceSelected;
                            if (select == null) {
                              source.choose();
                            } else {
                              select(source);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  filled: !widget.flat,
                  fillColor: onBar || AppColors.glass ? AppColors.tile : scheme.surfaceContainerHigh,
                  // On the page: Material 3's hover state layer over the tonal fill.
                  hoverColor: onBar ? AppColors.hover : scheme.onSurface.withValues(alpha: 0.08),
                  contentPadding: EdgeInsets.symmetric(vertical: onBar ? 12 : 16),
                  border: widget.flat
                      ? InputBorder.none
                      : OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppColors.glass ? 10 : 500),
                          borderSide: BorderSide.none,
                        ),
                  // A pill when idle too: the theme's enabled border (a small radius) would otherwise win.
                  enabledBorder: widget.flat
                      ? InputBorder.none
                      : OutlineInputBorder(borderRadius: BorderRadius.circular(500), borderSide: BorderSide.none),
                  // Focused in the bar: a light ring, like the streaming apps.
                  focusedBorder: widget.flat
                      ? InputBorder.none
                      : OutlineInputBorder(
                          borderRadius: BorderRadius.circular(500),
                          borderSide: onBar ? BorderSide(color: AppColors.textPrimary, width: 2) : BorderSide.none,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dropdown(BuildContext context) {
    final rows = suggestionRows(
      context,
      typed: _text,
      recent: _recent,
      queries: _queries,
      hits: _hits,
      highlight: _highlight,
      onQuery: _pickQuery,
      onHit: _pickHit,
      onSource: _pickSource,
      onRemoveRecent: (q) async {
        await RecentSearches.remove(q);
        _recent = await RecentSearches.load();
        _sync();
      },
      compact: widget.flat,
    );
    // The centred search: the same solid panel, small corners and tight rows as its box and results.
    if (widget.flat) {
      return Material(
        color: Color.alphaBlend(AppColors.tile, AppColors.panel),
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.45),
        borderRadius: LayoutPrefs.corner(10),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: ListView(padding: const EdgeInsets.symmetric(vertical: 6), shrinkWrap: true, children: rows),
        ),
      );
    }
    // A Material 3 search view: the bar's own tone, extra-large corners, a low shadow.
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shadowColor: Theme.of(context).colorScheme.shadow,
      borderRadius: searchSurfaceCorners(),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 460),
        child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), shrinkWrap: true, children: rows),
      ),
    );
  }
}

/// The rows of the suggestions under a search field ([SearchBox]'s dropdown, and the Liquid glass bar's, drawn on
/// the search page): recent searches while [typed] is empty; else completed searches (what was typed plain, the
/// rest bold), then artists, songs and albums to open. [highlight] is the keyboard's row, -1 for none.
List<Widget> suggestionRows(
  BuildContext context, {
  required String typed,
  required List<String> recent,
  required List<String> queries,
  required List<SearchHit> hits,
  int highlight = -1,
  required ValueChanged<String> onQuery,
  required ValueChanged<SearchHit> onHit,
  ValueChanged<SearchSource>? onSource,
  required ValueChanged<String> onRemoveRecent,
  bool compact = false,
}) {
  final text = Theme.of(context).textTheme;
  final scheme = Theme.of(context).colorScheme;
  final rows = <Widget>[];
  var i = 0;
  // Compact (the centred search): rows as tight as its results, in the app's own greys.
  final iconSize = compact ? 20.0 : 24.0;
  final soft = compact ? AppColors.textSecondary : scheme.onSurfaceVariant;
  final line = compact ? text.bodyMedium : text.bodyLarge;
  final sub = compact ? text.bodySmall : text.bodyMedium;
  // Material 3 list items: 56 high, 16 at the sides and between the leading icon and the text.
  Widget row({
    required Widget leading,
    required Widget title,
    Widget? subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    final index = i++;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: index == highlight ? (compact ? AppColors.hover : scheme.onSurface.withValues(alpha: 0.08)) : null,
        constraints: BoxConstraints(minHeight: compact ? 44 : 56),
        padding: compact
            ? EdgeInsets.only(left: 14, right: trailing == null ? 14 : 6, top: 4, bottom: 4)
            : EdgeInsets.only(left: 16, right: trailing == null ? 16 : 8, top: 6, bottom: 6),
        child: Row(
          children: [
            leading,
            SizedBox(width: compact ? 12 : 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [title, ?subtitle],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }

  final commands = SearchSource.commandSuggestions(typed);
  if (commands.isNotEmpty && onSource != null) {
    return [
      for (final source in commands)
        row(
          leading: Text(source.command, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          title: Text(source.label, style: line),
          onTap: () => onSource(source),
        ),
    ];
  }
  if (typed.isEmpty) {
    rows.add(
      Padding(
        padding: compact ? const EdgeInsets.fromLTRB(14, 8, 14, 4) : const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text(tr.recentSearches, style: text.labelLarge?.copyWith(color: soft)),
      ),
    );
    for (final q in recent) {
      rows.add(
        row(
          leading: Icon(Icons.history_rounded, color: soft, size: iconSize),
          title: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis, style: line),
          trailing: IconButton(
            tooltip: tr.remove,
            iconSize: compact ? 18 : 20,
            color: soft,
            onPressed: () => onRemoveRecent(q),
            icon: const Icon(Icons.close_rounded),
          ),
          onTap: () => onQuery(q),
        ),
      );
    }
  } else {
    for (final q in queries) {
      // What you typed stays plain; the completion is bold, as in YouTube Music.
      final match = q.toLowerCase().startsWith(typed.toLowerCase());
      rows.add(
        row(
          leading: Icon(Icons.search_rounded, color: soft, size: iconSize),
          title: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: match ? q.substring(0, typed.length) : ''),
                TextSpan(
                  text: match ? q.substring(typed.length) : q,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: line,
          ),
          onTap: () => onQuery(q),
        ),
      );
    }
    if (queries.isNotEmpty && hits.isNotEmpty) {
      rows.add(
        compact
            ? Divider(height: 9, indent: 14, endIndent: 14, color: AppColors.hover)
            : Divider(height: 17, indent: 16, endIndent: 16, color: scheme.outlineVariant),
      );
    }
    for (final h in hits) {
      rows.add(
        row(
          leading: Artwork(
            track: h.cover,
            size: compact ? 36 : 44,
            radius: compact ? 3 : 4,
            circle: h.kind == WebResultKind.artist,
          ),
          title: Text(
            h.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: line?.copyWith(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            h.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sub?.copyWith(color: soft),
          ),
          onTap: () => onHit(h),
        ),
      );
    }
  }
  return rows;
}

/// [SearchBox]'s suggestions for a field that isn't on the page: the Liquid glass bar carries the search field at the
/// bottom, over the keyboard, so these are drawn on the search page instead of in a dropdown under it, while that
/// field has the focus. A picked search runs through [input]'s submit, as Enter does; a picked artist, song or album
/// opens.
class SearchSuggestions extends StatefulWidget {
  const SearchSuggestions({super.key, required this.input});

  final SearchInput input;

  @override
  State<SearchSuggestions> createState() => _SearchSuggestionsState();
}

class _SearchSuggestionsState extends State<SearchSuggestions> {
  Timer? _debounce;
  int _request = 0;
  List<String> _recent = const [];
  void _forgetSearches() {
    if (mounted) setState(() => _recent = const []);
  }

  List<String> _queries = const [];
  List<SearchHit> _hits = const [];
  String _typed = '';

  /// Closed by a pick until the next keystroke.
  bool _dismissed = false;

  SearchInput get _input => widget.input;

  @override
  void initState() {
    super.initState();
    RecentSearches.cleared.addListener(_forgetSearches);
    _typed = _input.controller.text.trim();
    _input.controller.addListener(_changed);
    SearchSource.current.addListener(_sourceChanged);
    _input.focus.addListener(_refresh);
    _input.submitted.addListener(_submitted);
    _loadRecent();
    if (_typed.isNotEmpty) _fetch(_typed);
  }

  @override
  void dispose() {
    RecentSearches.cleared.removeListener(_forgetSearches);
    _debounce?.cancel();
    _input.controller.removeListener(_changed);
    SearchSource.current.removeListener(_sourceChanged);
    _input.focus.removeListener(_refresh);
    _input.submitted.removeListener(_submitted);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _sourceChanged() {
    _request++;
    _debounce?.cancel();
    if (mounted) {
      setState(() {
        _queries = const [];
        _hits = const [];
      });
    }
  }

  Future<void> _loadRecent() async {
    final r = await RecentSearches.load();
    if (!mounted) return;
    setState(() => _recent = r);
  }

  void _submitted() {
    _dismissed = true;
    _loadRecent();
  }

  void _changed() {
    final q = _input.controller.text.trim();
    if (q == _typed) return;
    _typed = q;
    _dismissed = false;
    _debounce?.cancel();
    if (q.isEmpty) {
      _queries = const [];
      _hits = const [];
      _loadRecent();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 120), () => _fetch(q));
  }

  Future<void> _fetch(String q) async {
    if (q.startsWith(':')) {
      _sourceChanged();
      return;
    }
    if (SearchSource.current.value != SearchSource.youtubeMusic) return;
    final id = ++_request;
    try {
      final s = await PlayerScope.read(context).ytMusic.suggestions(q);
      if (!mounted || id != _request) return;
      setState(() {
        _queries = s.queries.take(6).toList();
        _hits = s.hits.take(5).toList();
      });
    } catch (_) {
      if (!mounted || id != _request) return;
      setState(() {
        _queries = const [];
        _hits = const [];
      });
    }
  }

  void _pickQuery(String q) {
    _input.controller
      ..text = q
      ..selection = TextSelection.collapsed(offset: q.length);
    _input.focus.unfocus();
    _input.submit(q);
  }

  void _pickHit(SearchHit hit) {
    if (_typed.isNotEmpty) RecentSearches.add(_typed);
    setState(() => _dismissed = true);
    _input.focus.unfocus();
    openSearchHit(context, hit);
  }

  void _pickSource(SearchSource source) {
    final value = '${source.command} ';
    _input.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _input.focus.requestFocus();
    setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    final commands = SearchSource.commandSuggestions(_typed);
    final count = commands.isNotEmpty
        ? commands.length
        : _typed.isEmpty
        ? _recent.length
        : _queries.length + _hits.length;
    if (!_input.focus.hasFocus || _dismissed || count == 0) return const SizedBox.shrink();
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: searchSurfaceCorners(),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: suggestionRows(
            context,
            typed: _typed,
            recent: _recent,
            queries: _queries,
            hits: _hits,
            onQuery: _pickQuery,
            onHit: _pickHit,
            onSource: _pickSource,
            onRemoveRecent: (q) async {
              await RecentSearches.remove(q);
              await _loadRecent();
            },
          ),
        ),
      ),
    );
  }
}
