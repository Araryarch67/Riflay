import 'package:flutter/material.dart';

import '../../services/folder_watch.dart';
import '../navigation.dart';
import '../shell_scope.dart';
import 'duplicates_page.dart';
import 'sound_settings.dart';
import '../../services/language.dart';

/// Settings › Library & downloads › Library: keeping the music folders up to date, and finding songs you have twice.
class LibrarySettings extends StatelessWidget {
  const LibrarySettings({super.key});

  @override
  Widget build(BuildContext context) {
    final watch = FolderWatch.instance;
    final shell = ShellScope.of(context);
    final muted = settingsMuted(context);
    return ListenableBuilder(
      listenable: watch,
      builder: (context, _) {
        final folders = watch.folders;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsSection(
              title: tr.musicFolders,
              child: SettingsCard(
                children: [
                  if (shell.addFolder != null)
                    ListTile(
                      leading: const Icon(Icons.create_new_folder_outlined),
                      title: Text(tr.addFolder),
                      onTap: shell.addFolder,
                    ),
                  SwitchListTile(
                    secondary: const Icon(Icons.sync_rounded),
                    title: Text(tr.keepLibraryUpToDate),
                    subtitle: Text(FolderWatch.isPhone ? tr.keepLibraryOpen : tr.keepLibraryWatch, style: muted),
                    value: watch.keepUpToDate,
                    onChanged: watch.setKeepUpToDate,
                  ),
                  ListTile(
                    leading: const Icon(Icons.refresh_rounded),
                    title: Text(tr.checkNow),
                    subtitle: Text(
                      folders.isEmpty
                          ? tr.addFolderFirst
                          : watch.checking
                          ? tr.checkingDots
                          : tr.lookAtFoldersAgain(folders.length),
                      style: muted,
                    ),
                    enabled: folders.isNotEmpty && !watch.checking,
                    onTap: watch.checkNow,
                  ),
                  for (final dir in folders)
                    ListTile(
                      leading: const Icon(Icons.folder_rounded),
                      title: Text(dir, maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: TextButton(onPressed: () => watch.forget(dir), child: Text(tr.stopWatching)),
                    ),
                ],
              ),
            ),
            SettingsSection(
              title: tr.tidyUp,
              child: SettingsCard(
                children: [
                  ListTile(
                    leading: const Icon(Icons.library_music_outlined),
                    title: Text(tr.findDuplicates),
                    subtitle: Text(tr.findDuplicatesSubtitle, style: muted),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    // Its own location: the shell skips opening a page at the location already on screen.
                    onTap: () => shell.open(
                      const DuplicatesPage(),
                      location: Locations.settingsTopic('library/library/duplicates'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
