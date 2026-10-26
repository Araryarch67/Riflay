import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/download_prefs.dart';
import '../../services/youtube_importer.dart';
import '../../services/ytdlp.dart';
import '../theme.dart';
import '../widgets/menus.dart';
import 'sound_settings.dart';

/// Settings › Downloads: what a download is saved as, and where.
class DownloadSettings extends StatefulWidget {
  const DownloadSettings({super.key});

  @override
  State<DownloadSettings> createState() => _DownloadSettingsState();
}

class _DownloadSettingsState extends State<DownloadSettings> {
  final _prefs = DownloadPrefs.instance;
  late Future<Directory> _folder = YoutubeImporter.downloadsDir();
  late final Future<String?> _ytdlp = _ytdlpVersion();

  static bool get _phone => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _prefs.load();
  }

  static Future<String?> _ytdlpVersion() async {
    final exe = await YtDlp.executable();
    if (exe == null) return null;
    final r = await Process.run(exe, ['--version']);
    return r.exitCode == 0 ? '${(r.stdout as String).trim()} ($exe)' : null;
  }

  Future<void> _chooseFolder() async {
    final chosen = await FilePicker.getDirectoryPath(dialogTitle: 'Choose where downloads are saved');
    if (chosen == null) return;
    await _prefs.setFolder(chosen);
    if (mounted) setState(() => _folder = YoutubeImporter.downloadsDir());
  }

  @override
  Widget build(BuildContext context) {
    final muted = settingsMuted(context);
    return ListenableBuilder(
      listenable: _prefs,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(context, 'What to save'),
          SettingsCard(
            children: [
              SettingTile(
                icon: Icons.audio_file_outlined,
                title: const Text('Format'),
                subtitle: Text(_prefs.format.about, style: muted),
                control: OptionPicker<DownloadFormat>(
                  value: _prefs.format,
                  options: [for (final f in DownloadFormat.values) (f, f.label)],
                  onChanged: _prefs.setFormat,
                ),
              ),
              SettingTile(
                icon: Icons.high_quality_outlined,
                title: const Text('Quality'),
                subtitle: Text(_prefs.quality.about, style: muted),
                control: OptionPicker<DownloadQuality>(
                  value: _prefs.quality,
                  options: [for (final q in DownloadQuality.values) (q, q.label)],
                  onChanged: _prefs.setQuality,
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.help_outline_rounded),
                title: const Text('Ask every time'),
                subtitle: Text('Choose the format and quality each time you download a song.', style: muted),
                value: _prefs.askEveryTime,
                onChanged: _prefs.setAskEveryTime,
              ),
            ],
          ),
          _heading(context, 'Where'),
          SettingsCard(
            children: [
              if (_phone)
                SwitchListTile(
                  secondary: const Icon(Icons.signal_cellular_alt_rounded),
                  title: const Text('Download over mobile data'),
                  subtitle: Text(
                    _prefs.mobileData
                        ? 'Songs download on mobile data as well as Wi-Fi.'
                        : 'Songs wait for Wi-Fi, so they don\'t use your data plan.',
                    style: muted,
                  ),
                  value: _prefs.mobileData,
                  onChanged: _prefs.setMobileData,
                ),
              FutureBuilder<Directory>(
                future: _folder,
                builder: (context, snap) => ListTile(
                  leading: const Icon(Icons.folder_rounded),
                  title: const Text('Downloads folder'),
                  subtitle: Text(
                    _phone
                        ? '${snap.data?.path ?? '…'}\nPhones keep downloads in Riflay\'s own storage, so this can\'t be changed.'
                        : snap.data?.path ?? '…',
                    style: muted,
                  ),
                  isThreeLine: _phone,
                  trailing: _phone || !snap.hasData
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Open folder',
                              onPressed: () => launchUrl(Uri.directory(snap.data!.path)),
                              icon: const Icon(Icons.folder_open_rounded),
                            ),
                            TextButton(onPressed: _chooseFolder, child: const Text('Change')),
                            if (_prefs.folder != null)
                              TextButton(
                                onPressed: () async {
                                  await _prefs.setFolder(null);
                                  if (mounted) setState(() => _folder = YoutubeImporter.downloadsDir());
                                },
                                child: const Text('Reset'),
                              ),
                          ],
                        ),
                ),
              ),
              if (YtDlp.supported)
                FutureBuilder<String?>(
                  future: _ytdlp,
                  builder: (context, snap) => ListTile(
                    leading: const Icon(Icons.download_rounded),
                    title: const Text('YouTube downloader (yt-dlp)'),
                    subtitle: Text(
                      snap.connectionState != ConnectionState.done
                          ? 'Checking…'
                          : snap.data ?? 'Not available. Install it (e.g. pacman -S yt-dlp) for YouTube downloads.',
                      style: muted,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _heading(BuildContext context, String label) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
    child: Text(
      label,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w700),
    ),
  );
}
