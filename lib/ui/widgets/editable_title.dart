import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// A page title that can be renamed in place: tap it (or the small pencil
/// beside it) and it becomes a text box. Enter saves, Esc cancels; leaving
/// the box saves too. An empty or unchanged name changes nothing.
class EditableTitle extends StatefulWidget {
  const EditableTitle({
    super.key,
    required this.title,
    required this.style,
    required this.onRename,
    this.textAlign = TextAlign.start,
    this.maxLines = 2,
  });

  final String title;
  final TextStyle? style;
  final TextAlign textAlign;
  final int maxLines;

  /// Called with the new, trimmed name.
  final FutureOr<void> Function(String name) onRename;

  @override
  State<EditableTitle> createState() => _EditableTitleState();
}

class _EditableTitleState extends State<EditableTitle> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_editing && !_focus.hasFocus) _commit();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _start() {
    setState(() {
      _editing = true;
      _controller.value = TextEditingValue(
        text: widget.title,
        selection: TextSelection(baseOffset: 0, extentOffset: widget.title.length),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _cancel() {
    if (!_editing) return;
    setState(() => _editing = false);
  }

  void _commit() {
    if (!_editing) return;
    final name = _controller.text.trim();
    setState(() => _editing = false);
    if (name.isNotEmpty && name != widget.title) widget.onRename(name);
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
            _cancel();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          key: const ValueKey('rename-field'),
          controller: _controller,
          focusNode: _focus,
          style: widget.style,
          textAlign: widget.textAlign,
          maxLines: 1,
          textInputAction: TextInputAction.done,
          cursorColor: AppColors.textPrimary,
          decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
          onSubmitted: (_) => _commit(),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: InkWell(
            key: const ValueKey('rename-title'),
            borderRadius: BorderRadius.circular(6),
            hoverColor: Colors.transparent,
            onTap: _start,
            child: Text(
              widget.title,
              maxLines: widget.maxLines,
              overflow: TextOverflow.ellipsis,
              textAlign: widget.textAlign,
              style: widget.style,
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('rename-pencil'),
          tooltip: 'Rename',
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          color: AppColors.textSecondary,
          onPressed: _start,
          icon: const Icon(Icons.edit_outlined),
        ),
      ],
    );
  }
}
