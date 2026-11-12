import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/audio_analysis.dart';
import '../../services/flac_convert.dart';
import '../../services/language.dart';
import '../player_scope.dart';
import '../widgets/page_scaffold.dart';
import 'sound_settings.dart' show SettingsCard, settingsMuted;

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
    return PageScaffold(
      title: tr.losslessCheck,
      slivers: [
        SliverToBoxAdapter(
          child: ValueListenableBuilder(
            valueListenable: AudioAnalysis.scan,
            builder: (context, progress, _) {
              final found = progress == null ? AudioAnalysis.suspiciousOf(files) : const <(Track, AudioReport)>[];
              final checked = AudioAnalysis.checkedOf(files);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsCard(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.verified_outlined),
                        title: Text(tr.losslessCheckFiles(checked, files.length)),
                        subtitle: Text(
                          progress == null ? tr.losslessCheckAbout : tr.measuringLoudness(progress.$1, progress.$2),
                          style: muted,
                        ),
                        trailing: progress == null
                            ? FilledButton.tonal(
                                onPressed: files.isEmpty || !AudioAnalysis.supported
                                    ? null
                                    : () => AudioAnalysis.scanAll(files, bits: true),
                                child: Text(tr.losslessCheckRun),
                              )
                            : OutlinedButton(onPressed: AudioAnalysis.stopScan, child: Text(tr.stop)),
                      ),
                      if (progress != null)
                        LinearProgressIndicator(value: progress.$2 == 0 ? null : progress.$1 / progress.$2),
                    ],
                  ),
                  if (progress == null && checked > 0)
                    SettingsCard(
                      children: [
                        if (found.isEmpty)
                          ListTile(
                            leading: const Icon(Icons.check_circle_outline_rounded),
                            title: Text(tr.losslessCheckAllGood),
                          )
                        else ...[
                          ListTile(
                            leading: const Icon(Icons.report_outlined),
                            title: Text(tr.losslessCheckFound(found.length)),
                          ),
                          for (final (t, r) in found)
                            ListTile(
                              title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text('${t.artist} · ${reasonOf(r)}', style: muted),
                              onTap: () =>
                                  c.playList([for (final (t, _) in found) t], found.indexWhere((e) => e.$1 == t)),
                            ),
                        ],
                      ],
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
