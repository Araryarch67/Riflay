import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../platform/host.dart';
import '../../services/download_prefs.dart';
import '../../services/ios_folders.dart';
import '../../services/video_download.dart';
import '../../services/youtube_importer.dart';
import '../../services/ytdlp.dart';
import '../theme.dart';
import '../widgets/menus.dart';
import 'sound_settings.dart';
import '../../services/language.dart';

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

  /// Phones kept downloads in Riflay's own storage; `RIFLAY_NO_PHONE_DOWNLOADS_FOLDER` keeps them there.
  static bool get _fixed => _phone && !DownloadPrefs.phoneFolders;

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
    try {
      // iOS: through Files, which keeps Riflay's access to the folder after a restart (FolderAccess.swift).
      final chosen = Host.isIOS
          ? await IosFolders.pick()
          : await FilePicker.getDirectoryPath(
              dialogTitle: tr.chooseDownloadsFolder,
              initialDirectory: _phone ? null : (await _folder).path,
            );
      if (chosen == null || !mounted) return;
      if (!await YoutubeImporter.canSaveIn(chosen)) {
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr.downloadsFolderUnusable)));
        }
        return;
      }
      await _prefs.setFolder(chosen);
      if (mounted) {
        setState(() {
          _folder = YoutubeImporter.downloadsDir();
        });
      }
    } catch (e) {
      debugPrint('Choosing downloads folder failed: $e');
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr.downloadsFolderUnusable)));
      }
    }
  }

  static String _bitrateAbout(int? kbps) {
    if (kbps == null) return tr.bestSoundNote;
    final base = tr.smallerFilesNote;
    return YoutubeImporter.canReencode ? base : tr.closestVersionNote(base);
  }

  @override
  Widget build(BuildContext context) {
    final muted = settingsMuted(context);
    return ListenableBuilder(
      listenable: _prefs,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(context, tr.whatToSave),
          SettingsCard(
            children: [
              SettingTile(
                icon: Icons.movie_outlined,
                title: Text(tr.saveAs),
                subtitle: Text(
                  _prefs.kind == DownloadKind.video ? tr.saveAsVideoNote : tr.saveAsAudioNote,
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
                  title: Text(tr.videoFormat),
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
                  title: Text(tr.size),
                  subtitle: Text(tr.videoSizeNote, style: muted),
                  control: OptionPicker<int?>(
                    value: _prefs.heightFor(_prefs.videoContainer),
                    options: [
                      (null, tr.bestAvailable),
                      for (final h in standardVideoHeights(_prefs.videoContainer))
                        (h, h == recommendedVideoHeight ? tr.heightRecommended('$h') : '${h}p'),
                    ],
                    onChanged: (h) => _prefs.setVideoHeight(_prefs.videoContainer, h),
                  ),
                ),
              ] else ...[
                SettingTile(
                  icon: Icons.audio_file_outlined,
                  title: Text(tr.format),
                  subtitle: Text(
                    YoutubeImporter.canMakeFlac || _prefs.format.lossless
                        ? _prefs.format.about
                        : tr.flacUnavailable(_prefs.format.about),
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
                    title: Text(tr.bitDepthSampleRate),
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
                    title: Text(tr.bitrate),
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
                title: Text(tr.askEveryTime),
                subtitle: Text(tr.askEveryTimeSubtitle, style: muted),
                value: _prefs.askEveryTime,
                onChanged: _prefs.setAskEveryTime,
              ),
            ],
          ),
          _heading(context, tr.where),
          SettingsCard(
            children: [
              if (_phone)
                SwitchListTile(
                  secondary: const Icon(Icons.signal_cellular_alt_rounded),
                  title: Text(tr.downloadOverMobile),
                  subtitle: Text(_prefs.mobileData ? tr.downloadOverMobileOn : tr.downloadOverMobileOff, style: muted),
                  value: _prefs.mobileData,
                  onChanged: _prefs.setMobileData,
                ),
              FutureBuilder<Directory>(
                future: _folder,
                builder: (context, snap) => ListTile(
                  leading: const Icon(Icons.folder_rounded),
                  title: Text(tr.downloadsFolder),
                  onTap: _fixed || !snap.hasData ? null : _chooseFolder,
                  subtitle: Text(
                    _fixed ? tr.phoneDownloadsFixed(snap.data?.path ?? '…') : snap.data?.path ?? '…',
                    style: muted,
                  ),
                  isThreeLine: _phone,
                  trailing: _fixed || !snap.hasData
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // A phone has no file manager to hand a folder to.
                            if (!_phone)
                              IconButton(
                                tooltip: tr.openFolder,
                                onPressed: () => launchUrl(Uri.directory(snap.data!.path)),
                                icon: const Icon(Icons.folder_open_rounded),
                              ),
                            TextButton(onPressed: _chooseFolder, child: Text(tr.change)),
                            if (_prefs.folder != null)
                              TextButton(
                                onPressed: () async {
                                  await _prefs.setFolder(null);
                                  if (mounted) {
                                    setState(() {
                                      _folder = YoutubeImporter.downloadsDir();
                                    });
                                  }
                                },
                                child: Text(tr.reset),
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
                    title: Text(tr.ytDlp),
                    subtitle: Text(
                      snap.connectionState != ConnectionState.done ? tr.checking : snap.data ?? tr.ytDlpMissing,
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
