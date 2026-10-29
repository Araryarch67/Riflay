import 'package:flutter/material.dart';

import '../../services/folder_watch.dart';
import '../navigation.dart';
import '../shell_scope.dart';
import 'duplicates_page.dart';
import 'sound_settings.dart';

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
              title: 'Music folders',
              child: SettingsCard(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.sync_rounded),
                    title: const Text('Keep the library up to date'),
                    subtitle: Text(
                      FolderWatch.isPhone
                          ? 'New songs in your music folders are added, and songs you delete or move are taken out, '
                                'each time you open Riflay.'
                          : 'New songs in your music folders are added, and songs you delete or move are taken out, '
                                'without adding the folder again.',
                      style: muted,
                    ),
                    value: watch.keepUpToDate,
                    onChanged: watch.setKeepUpToDate,
                  ),
                  ListTile(
                    leading: const Icon(Icons.refresh_rounded),
                    title: const Text('Check now'),
                    subtitle: Text(
                      folders.isEmpty
                          ? 'Add a music folder from the library first.'
                          : watch.checking
                          ? 'Checking...'
                          : 'Look at ${folders.length == 1 ? 'your music folder' : 'your ${folders.length} music folders'} again.',
                      style: muted,
                    ),
                    enabled: folders.isNotEmpty && !watch.checking,
                    onTap: watch.checkNow,
                  ),
                  for (final dir in folders)
                    ListTile(
                      leading: const Icon(Icons.folder_rounded),
                      title: Text(dir, maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: TextButton(onPressed: () => watch.forget(dir), child: const Text('Stop watching')),
                    ),
                ],
              ),
            ),
            SettingsSection(
              title: 'Tidy up',
              child: SettingsCard(
                children: [
                  ListTile(
                    leading: const Icon(Icons.library_music_outlined),
                    title: const Text('Find songs you have twice'),
                    subtitle: Text('The same song in different files, so you can keep the best one.', style: muted),
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
