import 'package:flutter/material.dart';

import '../../services/folder_watch.dart';
import '../../platform/features.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../widgets/menus.dart';
import '../navigation.dart';
import '../shell_scope.dart';
import 'duplicates_page.dart';
import 'sound_settings.dart';
import 'spotify_page.dart';
import 'youtube_music_page.dart';
import '../../services/language.dart';
import '../widgets/how_to_steps.dart';

/// Settings › Library & downloads › Library: keeping the music folders up to date, and finding songs you have twice.
class LibrarySettings extends StatelessWidget {
  const LibrarySettings({super.key});

  @override
  Widget build(BuildContext context) {
    final watch = FolderWatch.instance;
    final shell = ShellScope.of(context);
    final account = PlayerScope.read(context).ytMusic;
    final muted = settingsMuted(context);
    return ListenableBuilder(
      listenable: Listenable.merge([watch, LayoutPrefs.instance, account]),
      builder: (context, _) {
        final folders = watch.folders;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsSection(
              title: tr.addMusic,
              child: SettingsCard(
                children: [
                  if (Features.playlistImport) ...[
                    ListTile(
                      leading: const Icon(Icons.file_upload_outlined),
                      title: Text(tr.importPlaylist),
                      onTap: () => importPlaylist(context),
                    ),
                    if (Features.playlistFileImport)
                      ListTile(
                        leading: const Icon(Icons.file_open_outlined),
                        title: Text(tr.importPlaylistFile),
                        onTap: () => importPlaylist(context, fromFile: true),
                      ),
                    ListTile(
                      leading: const Icon(Icons.library_music_outlined),
                      title: Text(tr.spotifyLibrary),
                      onTap: () => shell.open(const SpotifyPage(), location: Locations.spotify),
                    ),
                  ],
                  if (account.canEdit)
                    ListTile(
                      leading: const Icon(Icons.group_add_outlined),
                      title: Text(tr.joinSharedPlaylist),
                      onTap: () => joinSharedPlaylist(context),
                    ),
                  ListTile(
                    leading: const Icon(Icons.audio_file_outlined),
                    title: Text(tr.addSongs),
                    onTap: shell.addFiles,
                  ),
                  ListTile(
                    leading: const Icon(Icons.add_link_rounded),
                    title: Text(tr.importFromYouTube),
                    onTap: shell.importFromYoutube,
                  ),
                ],
              ),
            ),
            SettingsCard(
              children: [
                SettingTile(
                  icon: Icons.filter_list,
                  title: Text(tr.defaultLibraryFilter),
                  control: OptionPicker<String>(
                    value: LayoutPrefs.instance.libraryChip,
                    onChanged: LayoutPrefs.instance.setLibraryChip,
                    options: [
                      ('', tr.all),
                      ('playlists', tr.playlists),
                      ('downloaded', tr.downloaded),
                      ('albums', tr.albums),
                      ('artists', tr.artists),
                      ('local', tr.local),
                    ],
                  ),
                ),
                for (final (id, label) in [
                  ('liked', tr.likedMusic),
                  ('downloaded', tr.downloaded),
                  ('top', tr.mostPlayed),
                ])
                  SwitchListTile(
                    title: Text(label),
                    value: !LayoutPrefs.instance.hiddenCollections.contains(id),
                    onChanged: (on) => LayoutPrefs.instance.showCollection(id, on),
                  ),
              ],
            ),
            SettingsSection(
              title: tr.musicFolders,
              child: SettingsCard(
                children: [
                  if (shell.addFolder != null) HowToSteps(steps: [tr.howFolder1, tr.howFolder2, tr.howFolder3]),
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
            SettingsSection(
              title: tr.optionalTools,
              child: SettingsCard(
                children: [
                  for (final feature in ExtraFeature.values)
                    if (feature != ExtraFeature.playlistDownloadStatus || Features.downloads)
                      SwitchListTile(
                        title: Text(feature.label),
                        value: feature.enabled,
                        onChanged: (value) => LayoutPrefs.instance.setExtraFeature(feature, value),
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
