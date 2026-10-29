import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/player_controller.dart';
import '../../../services/youtube_music_account.dart';
import '../../../services/ytmusic_web.dart' show WebResultKind;
import '../../theme.dart';
import '../../widgets/controls.dart';
import 'remote_results.dart' show openSearchHit;
import 'search_input.dart';

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
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  /// In the dark title bar: a dark pill instead of the white one.
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
  List<String> _queries = const [];
  List<SearchHit> _hits = const [];

  /// Keyboard highlight across queries, then hits; -1 is none.
  int _highlight = -1;

  /// Closed by Esc / a pick until the next keystroke.
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_sync);
    RecentSearches.load().then((r) {
      if (!mounted) return;
      _recent = r;
      _sync(); // the field may have had focus before these loaded
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.removeListener(_sync);
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  String get _text => widget.controller.text.trim();

  Color get _ink => widget.onBar ? AppColors.textPrimary : AppColors.onInverse;

  /// In the title bar the results page updates as you type (like the
  /// streaming apps), so suggestions would only cover it: just recent
  /// searches, while the box is empty.
  int get _count => _text.isEmpty
      ? _recent.length
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
    if (_text.isEmpty) return _pickQuery(_recent[i]);
    if (i < _queries.length) return _pickQuery(_queries[i]);
    _pickHit(_hits[i - _queries.length]);
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
    final text = Theme.of(context).textTheme;
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
              offset: const Offset(0, 6),
              child: Align(
                alignment: Alignment.topLeft,
                child: TapRegion(
                  groupId: _link,
                  child: SizedBox(width: box.maxWidth, child: _dropdown(context)),
                ),
              ),
            ),
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _onKey,
              child: TextField(
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
                style: text.bodyLarge?.copyWith(color: _ink, fontWeight: FontWeight.w500),
                cursorColor: _ink,
                decoration: InputDecoration(
                  hintText: 'What do you want to play?',
                  hintStyle: text.bodyLarge?.copyWith(
                    color: widget.onBar ? AppColors.textSecondary : AppColors.onInverse.withValues(alpha: 0.54),
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: widget.onBar ? AppColors.textSecondary : AppColors.onInverse.withValues(alpha: 0.87),
                  ),
                  suffixIcon: widget.controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          color: widget.onBar ? AppColors.textSecondary : AppColors.onInverse.withValues(alpha: 0.87),
                          onPressed: () {
                            widget.controller.clear();
                            _changed('');
                            _focus.requestFocus();
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  fillColor: widget.onBar ? AppColors.tile : AppColors.inverse,
                  hoverColor: widget.onBar ? AppColors.hover : null,
                  contentPadding: EdgeInsets.symmetric(vertical: widget.onBar ? 12 : 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(500), borderSide: BorderSide.none),
                  // Focused in the bar: a light ring, like the streaming apps.
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(500),
                    borderSide: widget.onBar ? BorderSide(color: AppColors.textPrimary, width: 2) : BorderSide.none,
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
    final text = Theme.of(context).textTheme;
    final typed = _text;
    final rows = <Widget>[];
    var i = 0;
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
          color: index == _highlight ? AppColors.tile : null,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 14),
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

    if (typed.isEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Text('Recent searches', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        ),
      );
      for (final q in _recent) {
        rows.add(
          row(
            leading: Icon(Icons.history_rounded, color: AppColors.textSecondary, size: 22),
            title: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyLarge),
            trailing: IconButton(
              tooltip: 'Remove',
              iconSize: 18,
              color: AppColors.textSecondary,
              onPressed: () async {
                await RecentSearches.remove(q);
                _recent = await RecentSearches.load();
                _sync();
              },
              icon: const Icon(Icons.close_rounded),
            ),
            onTap: () => _pickQuery(q),
          ),
        );
      }
    } else {
      for (final q in _queries) {
        // What you typed stays plain; the completion is bold, as in YouTube Music.
        final match = q.toLowerCase().startsWith(typed.toLowerCase());
        rows.add(
          row(
            leading: Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 22),
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
              style: text.bodyLarge,
            ),
            onTap: () => _pickQuery(q),
          ),
        );
      }
      if (_queries.isNotEmpty && _hits.isNotEmpty) rows.add(Divider(height: 9, color: AppColors.hover));
      for (final h in _hits) {
        rows.add(
          row(
            leading: Artwork(track: h.cover, size: 44, radius: 4, circle: h.kind == WebResultKind.artist),
            title: Text(
              h.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              h.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            onTap: () => _pickHit(h),
          ),
        );
      }
    }
    return Material(
      color: AppColors.elevated,
      elevation: 12,
      shadowColor: Colors.black,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 460),
        child: ListView(padding: const EdgeInsets.symmetric(vertical: 6), shrinkWrap: true, children: rows),
      ),
    );
  }
}
