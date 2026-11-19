import 'package:flutter/material.dart';

import '../../services/language.dart';
import 'app_dialog.dart';

Future<T?> pickListItem<T>(
  BuildContext context,
  String title,
  List<T> items,
  String Function(T) label, {
  String Function(T)? subtitle,
}) => showDialog<T>(
  context: context,
  builder: (dialog) => AppDialog(
    title: title,
    scrollable: false,
    content: SizedBox(
      height: 340,
      child: ListView.builder(
        itemCount: items.length,
        itemBuilder: (_, i) => ListTile(
          title: Text(label(items[i])),
          subtitle: subtitle == null ? null : Text(subtitle(items[i])),
          onTap: () => Navigator.pop(dialog, items[i]),
        ),
      ),
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: Text(tr.cancel))],
  ),
);
