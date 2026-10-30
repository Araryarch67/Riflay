import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../platform/host.dart';
import '../../services/download_prefs.dart';
import '../../services/video_download.dart';
import '../../services/youtube_importer.dart';
import '../../services/ytdlp.dart';
import '../theme.dart';
import '../widgets/menus.dart';
import 'sound_settings.dart';

/// Settings › Library & downloads › Downloads: what a download is saved as, and where.
class DownloadSettings extends StatefulWidget {
  const DownloadSettings({super.key});

  @override
  State<DownloadSettings> createState() => _DownloadSettingsState();
}

class _DownloadSettingsState extends State<DownloadSettings> {
  final _prefs = DownloadPrefs.instance;
  late Future<Directory> _folder = YoutubeImporter.downloadsDir();
  late final Future<String?> _ytdlp = _ytdlpVersion();

  static bool get _phone => Host.isAndroid || Host.isIOS;

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

  static String _bitrateAbout(int? kbps) {
    if (kbps == null) return 'The best sound YouTube has for each song.';
    final base = 'Smaller files, with a little less full sound.';
    return YoutubeImporter.canReencode ? base : '$base Uses the closest version YouTube offers.';
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
                icon: Icons.movie_outlined,
                title: const Text('Save as'),
                subtitle: Text(
                  _prefs.kind == DownloadKind.video
                      ? 'The music video, with its sound. Songs without a music video are saved as audio.'
                      : 'Just the sound. Choose Video to keep the music video too.',
                  style: muted,
                ),
                control: OptionPicker<DownloadKind>(
                  value: _prefs.kind,
                  options: [for (final k in DownloadKind.values) (k, k.label)],
                  onChanged: _prefs.setKind,
                ),
              ),
              if (_prefs.kind == DownloadKind.video) ...[
                SettingTile(
                  icon: Icons.video_file_outlined,
                  title: const Text('Video format'),
                  subtitle: Text(_prefs.videoContainer.about, style: muted),
                  control: OptionPicker<VideoContainer>(
                    value: _prefs.videoContainer,
                    options: [
                      for (final c in VideoContainer.values)
                        (c, c == VideoContainer.mp4 ? '${c.label} (Recommended)' : c.label),
                    ],
                    onChanged: _prefs.setVideoContainer,
                  ),
                ),
                SettingTile(
                  icon: Icons.high_quality_outlined,
                  title: const Text('Size'),
                  subtitle: Text(
                    'The tallest picture the video has, up to the one you choose. 1080p is a sharp picture without a huge file.',
                    style: muted,
                  ),
                  control: OptionPicker<int?>(
                    value: _prefs.heightFor(_prefs.videoContainer),
                    options: [
                      (null, 'Best available'),
                      for (final h in standardVideoHeights(_prefs.videoContainer))
                        (h, h == recommendedVideoHeight ? '${h}p (Recommended)' : '${h}p'),
                    ],
                    onChanged: (h) => _prefs.setVideoHeight(_prefs.videoContainer, h),
                  ),
                ),
              ] else ...[
                SettingTile(
                  icon: Icons.audio_file_outlined,
                  title: const Text('Format'),
                  subtitle: Text(
                    YoutubeImporter.canMakeFlac || _prefs.format.lossless
                        ? _prefs.format.about
                        : '${_prefs.format.about}\nFLAC isn\'t available on this device.',
                    style: muted,
                  ),
                  control: OptionPicker<DownloadFormat>(
                    value: _prefs.format,
                    options: [
                      for (final f in DownloadFormat.values)
                        if (switch (f) {
                          DownloadFormat.flac => YoutubeImporter.canMakeFlac || _prefs.format == f,
                          DownloadFormat.mp3 => YoutubeImporter.canMakeMp3 || _prefs.format == f,
                          _ => true,
                        })
                          (f, f.label),
                    ],
                    onChanged: _prefs.setFormat,
                  ),
                ),
                if (_prefs.format.lossless)
                  SettingTile(
                    icon: Icons.high_quality_outlined,
                    title: const Text('Bit depth and sample rate'),
                    subtitle: Text(_prefs.flac.about, style: muted),
                    control: OptionPicker<FlacQuality>(
                      value: _prefs.flac,
                      options: [for (final q in FlacQuality.values) (q, q.label)],
                      onChanged: _prefs.setFlac,
                    ),
                  )
                else
                  SettingTile(
                    icon: Icons.high_quality_outlined,
                    title: const Text('Bitrate'),
                    subtitle: Text(_bitrateAbout(_prefs.kbpsFor(_prefs.format)), style: muted),
                    control: OptionPicker<int?>(
                      value: _prefs.kbpsFor(_prefs.format),
                      options: [for (final k in _prefs.format.bitrates) (k, bitrateLabelFor(_prefs.format, k))],
                      onChanged: (k) => _prefs.setKbps(_prefs.format, k),
                    ),
                  ),
              ],
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
