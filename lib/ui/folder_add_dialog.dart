import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/language.dart';
import 'widgets/app_dialog.dart';

/// How a picked music folder joins the library.
enum FolderAddChoice {
  /// Its songs go into the library, as adding a folder always did.
  onlyAdd,

  /// The same, and the folder also shows in Playlists, its songs always what is in the folder now.
  asPlaylist,
}

/// Asks whether [folder] is only added or added as a playlist too; null when the person cancelled.
Future<FolderAddChoice?> askFolderAddChoice(BuildContext context, String folder) => showDialog<FolderAddChoice>(
  context: context,
  useRootNavigator: true,
  builder: (_) => FolderAddDialog(folder: folder),
);

/// "Add “Folder”": Only add, or Add as playlist.
class FolderAddDialog extends StatefulWidget {
  const FolderAddDialog({super.key, required this.folder});

  final String folder;

  @override
  State<FolderAddDialog> createState() => _FolderAddDialogState();
}

class _FolderAddDialogState extends State<FolderAddDialog> {
  var _choice = FolderAddChoice.onlyAdd;

  @override
  Widget build(BuildContext context) {
    final name = p.basename(widget.folder);
    return AppDialog(
      title: tr.addFolderNamed(name.isEmpty ? widget.folder : name),
      width: DialogWidth.compact,
      content: ChoiceTileGrid(
        columns: 2,
        children: [
          ChoiceTile(
            title: tr.folderOnlyAdd,
            subtitle: Text(tr.folderOnlyAddSubtitle),
            selected: _choice == FolderAddChoice.onlyAdd,
            onTap: () => setState(() => _choice = FolderAddChoice.onlyAdd),
          ),
          ChoiceTile(
            title: tr.folderAsPlaylist,
            subtitle: Text(tr.folderAsPlaylistSubtitle),
            selected: _choice == FolderAddChoice.asPlaylist,
            onTap: () => setState(() => _choice = FolderAddChoice.asPlaylist),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, _choice), child: Text(tr.add)),
      ],
    );
  }
}
