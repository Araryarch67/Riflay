import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/audio_analysis.dart';
import '../../platform/host.dart';
import '../../services/ffmpeg.dart';
import '../../services/flac_convert.dart';
import '../../services/language.dart';
import '../player_scope.dart';
import '../widgets/controls.dart' show Artwork;
import 'settings_page.dart' show SettingsSubpage, SettingsTopic;
import 'sound_settings.dart' show SettingsCard, SettingsIcon, SettingsSection, settingsMuted;

/// Settings › Sound › Check lossless files: measures every FLAC / WAV / AIFF… on this device and lists the ones
/// that aren't what they claim: made from an MP3 or AAC (a wall in the spectrum), "hi-res" upsampled from 44.1 /
/// 48 kHz, or 24-bit holding only 16 bits. The measuring is [AudioAnalysis]'s, shared with Detail stats and
/// loudness leveling, so a song measured once isn't decoded again.
class LosslessCheckPage extends StatelessWidget {
  const LosslessCheckPage({super.key});

  /// What was found in [r], in a line.
  static String reasonOf(AudioReport r) {
    String khz(double hz) => (hz / 1000).toStringAsFixed(1);
    return [
      switch (r.verdict) {
        SourceVerdict.lossyCut => tr.losslessCheckLossyCut(khz(r.cutoffHz!)),
        SourceVerdict.upsampled => tr.losslessCheckUpsampled,
        SourceVerdict.fullBand => null,
      },
      if (r.paddedBits) tr.losslessCheckPadded(r.storedBits!),
    ].whereType<String>().join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.of(context);
    final muted = settingsMuted(context);
    final files = [
      for (final t in c.library)
        if (FlacConvert.isLosslessFile(t) && AudioAnalysis.fileOf(t) != null) t,
    ];
    return SettingsSubpage(
      topic: SettingsTopic.advanced,
      title: tr.losslessCheck,
      child: ValueListenableBuilder(
        valueListenable: AudioAnalysis.scan,
        builder: (context, progress, _) {
          final found = progress == null ? AudioAnalysis.suspiciousOf(files) : const <(Track, AudioReport)>[];
          final checked = AudioAnalysis.checkedOf(files);
          // Windows reads the files with ffmpeg: fetched once, on Check, where it isn't here yet.
          final fetchesFfmpeg = !AudioAnalysis.supported && Host.isWindows && Ffmpeg.available;
          final canRun = files.isNotEmpty && (AudioAnalysis.supported || fetchesFfmpeg);
          Future<void> run() async {
            if (fetchesFfmpeg) {
              try {
                await Ffmpeg.executable();
              } catch (e) {
                debugPrint('Lossless check: no ffmpeg: $e');
                return;
              }
            }
            await AudioAnalysis.scanAll(files, bits: true);
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // What it does and how to use it, before anything is pressed: plain text, not a row to tap.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Text(tr.losslessCheckHow, style: muted),
              ),
              SettingsCard(
                children: [
                  ListTile(
                    leading: const SettingsIcon(Icons.verified_outlined),
                    title: Text(tr.losslessCheckFiles(checked, files.length)),
                    subtitle: Text(
                      progress == null ? tr.losslessCheckAbout : tr.measuringLoudness(progress.$1, progress.$2),
                      style: muted,
                    ),
                    trailing: progress == null
                        ? FilledButton.tonal(onPressed: canRun ? run : null, child: Text(tr.losslessCheckRun))
                        : OutlinedButton(onPressed: AudioAnalysis.stopScan, child: Text(tr.stop)),
                  ),
                  if (progress != null)
                    LinearProgressIndicator(value: progress.$2 == 0 ? null : progress.$1 / progress.$2),
                  if (files.isEmpty)
                    ListTile(
                      leading: const SettingsIcon(Icons.library_music_outlined),
                      title: Text(tr.losslessCheckNoFiles),
                    )
                  else if (fetchesFfmpeg)
                    ListTile(
                      leading: const SettingsIcon(Icons.download_outlined),
                      title: Text(tr.losslessCheckNeedsFfmpeg, style: muted),
                    ),
                ],
              ),
              const SizedBox(height: 28),
              if (progress == null && checked > 0)
                if (found.isEmpty)
                  SettingsCard(
                    children: [
                      ListTile(
                        leading: const SettingsIcon(Icons.check_circle_outline_rounded),
                        title: Text(tr.losslessCheckAllGood),
                      ),
                    ],
                  )
                else
                  SettingsSection(
                    title: tr.losslessCheckFound(found.length),
                    child: SettingsCard(
                      children: [
                        for (final (t, r) in found)
                          ListTile(
                            leading: Artwork(track: t, size: 44, radius: 8),
                            title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              '${t.artist}\n${reasonOf(r)}',
                              style: muted,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.play_arrow_rounded),
                            onTap: () =>
                                c.playList([for (final (t, _) in found) t], found.indexWhere((e) => e.$1 == t)),
                          ),
                      ],
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
