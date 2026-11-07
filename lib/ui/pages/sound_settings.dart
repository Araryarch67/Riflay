import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../platform/host.dart';
import '../../services/audio_analysis.dart';
import '../../services/audio_engine.dart';
import '../../services/beta_features.dart';
import '../../services/carla_locator.dart';
import '../../services/crossfade.dart';
import '../../services/language.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/menus.dart';
import '../widgets/signal_path.dart';
import 'equalizer_page.dart';
import '../widgets/app_dialog.dart';

/// Settings > Sound > Playback: queue behavior and seamless track changes.
class PlaybackSettings extends StatelessWidget {
  const PlaybackSettings({super.key});
  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.of(context);
    return ListenableBuilder(
      listenable: c.audio,
      builder: (context, _) => SettingsCard(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.radio_rounded),
            title: Text(tr.autoplay),
            subtitle: Text(tr.autoplayKeepGoing),
            value: c.autoplay,
            onChanged: c.setAutoplay,
          ),
          if (AudioEngine.supported)
            SwitchListTile(
              secondary: const Icon(Icons.join_inner_rounded),
              title: Text(tr.gaplessPlayback),
              subtitle: Text(tr.gaplessPlaybackSubtitle),
              value: c.audio.gapless,
              onChanged: c.audio.setGapless,
            ),
          if (AudioEngine.hasSkipSilence)
            SwitchListTile(
              secondary: const Icon(Icons.fast_forward_rounded),
              title: Text(tr.skipSilence),
              subtitle: Text(c.audio.bitPerfect ? tr.offWhileBitPerfect : tr.skipSilenceSubtitle),
              value: c.audio.skipSilence && !c.audio.bitPerfect,
              onChanged: c.audio.bitPerfect ? null : c.audio.setSkipSilence,
            ),
        ],
      ),
    );
  }
}

/// Settings > Sound > Sound effects (DSP): processors and transitions, with their parameters.
class DspSettings extends StatelessWidget {
  const DspSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.of(context);
    final audio = c.audio;
    final shell = ShellScope.of(context);
    final muted = settingsMuted(context);
    return ListenableBuilder(
      listenable: audio,
      builder: (context, _) {
        final locked = audio.bitPerfect;
        final monoOn = audio.monoActive;
        final speakersOn = audio.virtualSpeakersActive;
        String lockedNote(String normal) => locked ? tr.offWhileBitPerfect : normal;
        // The web build has the equalizer, crossfeed and mono audio (Web Audio); the rest needs mpv.
        final native = AudioEngine.supported;
        return SettingsCard(
          children: [
            if (native || AudioEngine.webEffects) ...[
              ListTile(
                leading: const Icon(Icons.equalizer_rounded),
                title: Text(tr.equalizer),
                subtitle: Text(lockedNote(audio.eqActive ? eqPresetLabel(audio.eqPreset) : tr.off), style: muted),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => shell.open(const EqualizerPage()),
              ),
              if (native) ...[
                SettingTile(
                  icon: Icons.graphic_eq_rounded,
                  title: Text(tr.volumeLeveling),
                  subtitle: Text(lockedNote(tr.volumeLevelingSubtitle), style: muted),
                  control: OptionPicker<VolumeLeveling>(
                    value: audio.leveling,
                    onChanged: locked ? null : audio.setLeveling,
                    options: [for (final v in VolumeLeveling.values) (v, v.label)],
                  ),
                ),
                if (audio.leveling != VolumeLeveling.off && AudioAnalysis.supported) const _MeasureLoudness(),
                SwitchListTile(
                  secondary: const Icon(Icons.compare_arrows_rounded),
                  title: Text(tr.crossfade),
                  subtitle: Text(audio.crossfadeBlock ?? tr.crossfadeSubtitle, style: muted),
                  value: audio.crossfade,
                  onChanged: audio.crossfadeBlock != null ? null : audio.setCrossfade,
                ),
                if (audio.crossfade && audio.crossfadeBlock == null) ...[
                  SettingTile(
                    icon: Icons.timelapse_rounded,
                    title: Text(tr.fadeLength),
                    control: SizedBox(
                      width: 220,
                      child: Row(
                        children: [
                          Expanded(
                            child: Slider(
                              value: audio.crossfadeSeconds.toDouble(),
                              min: CrossfadeRules.minSeconds.toDouble(),
                              max: CrossfadeRules.maxSeconds.toDouble(),
                              divisions: CrossfadeRules.maxSeconds - CrossfadeRules.minSeconds,
                              label: '${audio.crossfadeSeconds} s',
                              onChanged: (v) => audio.setCrossfadeSeconds(v.round()),
                            ),
                          ),
                          SizedBox(width: 40, child: Text('${audio.crossfadeSeconds} s', style: muted)),
                        ],
                      ),
                    ),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.album_outlined),
                    title: Text(tr.skipForAlbums),
                    subtitle: Text(tr.skipForAlbumsSubtitle, style: muted),
                    value: audio.crossfadeSkipAlbums,
                    onChanged: audio.setCrossfadeSkipAlbums,
                  ),
                ],
                SwitchListTile(
                  secondary: const Icon(Icons.spatial_audio_rounded),
                  title: Text(tr.virtualSpeakers),
                  subtitle: Text(lockedNote(monoOn ? tr.offWhileMono : tr.virtualSpeakersSubtitle), style: muted),
                  value: speakersOn,
                  onChanged: locked || monoOn ? null : audio.setVirtualSpeakers,
                ),
                if (audio.virtualSpeakers)
                  _DspSlider(
                    title: tr.virtualSpeakerLevel,
                    description: tr.virtualSpeakerLevelBody,
                    value: audio.virtualSpeakerGain,
                    min: -12,
                    max: 6,
                    defaultValue: 0,
                    label: '${audio.virtualSpeakerGain.toStringAsFixed(1)} dB',
                    onChanged: locked || monoOn ? null : audio.setVirtualSpeakerGain,
                  ),
              ],
              SettingTile(
                icon: Icons.headphones_rounded,
                title: Text(tr.headphoneCrossfeed),
                subtitle: Text(
                  lockedNote(
                    monoOn
                        ? tr.offWhileMono
                        : speakersOn
                        ? tr.crossfeedNotNeeded
                        : tr.crossfeedSubtitle,
                  ),
                  style: muted,
                ),
                control: SizedBox(
                  width: 200,
                  child: Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: audio.crossfeed,
                          divisions: 10,
                          onChanged: locked || monoOn || speakersOn ? null : audio.setCrossfeed,
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(
                          audio.crossfeed == 0 ? tr.off : '${(audio.crossfeed * 100).round()}%',
                          style: muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (audio.crossfeed > 0)
                _DspSlider(
                  title: tr.crossfeedSoundstage,
                  description: tr.crossfeedSoundstageBody,
                  value: audio.crossfeedRange,
                  min: 0,
                  max: 1,
                  defaultValue: 0.5,
                  label: '${(audio.crossfeedRange * 100).round()}%',
                  onChanged: locked || monoOn || speakersOn ? null : audio.setCrossfeedRange,
                ),
              SettingTile(
                icon: Icons.hearing_rounded,
                title: Text(tr.monoAudio),
                subtitle: Text(lockedNote(tr.monoAudioSubtitle), style: muted),
                control: OptionPicker<MonoAudio>(
                  value: locked ? MonoAudio.off : audio.mono,
                  onChanged: locked ? null : audio.setMono,
                  options: [for (final m in MonoAudio.values) (m, m.label)],
                ),
              ),
              if (native) ...[
                if (AudioEngine.pluginBridge != null)
                  if (AudioEngine.hasPlugins)
                    SettingTile(
                      icon: Icons.extension_outlined,
                      title: Text(tr.audioPlugins),
                      subtitle: Text(locked ? tr.offWhileBitPerfect : tr.audioPluginsSubtitle, style: muted),
                      control: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(onPressed: locked ? null : audio.editPlugins, child: Text(tr.editInCarla)),
                          Switch(value: audio.plugins && !locked, onChanged: locked ? null : audio.setPlugins),
                        ],
                      ),
                    )
                  else
                    SettingTile(
                      icon: Icons.extension_outlined,
                      title: Text(tr.audioPlugins),
                      subtitle: Text(Host.isWindows ? tr.needsCarlaDownload : tr.needsCarlaInstall, style: muted),
                      control: TextButton(
                        onPressed: () => launchUrl(Uri.parse(CarlaLocator.downloadPage)),
                        child: Text(tr.installCarla),
                      ),
                    ),
                SettingTile(
                  icon: Icons.surround_sound_rounded,
                  title: Text(tr.roomCorrection),
                  subtitle: Text(
                    locked
                        ? tr.offWhileBitPerfect
                        : audio.impulseName == null
                        ? tr.roomCorrectionSubtitle
                        : audio.impulseName!,
                    style: muted,
                  ),
                  control: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: locked ? null : () => AdvancedAudioSettings._pickImpulse(context, audio),
                        child: Text(audio.impulseName == null ? tr.chooseFile : tr.change),
                      ),
                      Switch(
                        value: audio.convolution && !locked,
                        onChanged: locked || audio.impulsePath == null ? null : audio.setConvolution,
                      ),
                    ],
                  ),
                ),
                if (audio.impulsePath != null)
                  _DspSlider(
                    title: tr.roomCorrectionHeadroom,
                    description: tr.roomCorrectionHeadroomBody,
                    value: audio.convolutionGain,
                    min: -24,
                    max: 0,
                    defaultValue: 0,
                    label: '${audio.convolutionGain.toStringAsFixed(1)} dB',
                    onChanged: locked || !audio.convolution ? null : audio.setConvolutionGain,
                  ),
                ListTile(
                  leading: const Icon(Icons.account_tree_outlined),
                  title: Text(tr.signalPath),
                  subtitle: Text(tr.signalPathSubtitle),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showSignalPath(context),
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

/// A labeled DSP parameter with its current value and a one-tap default.
class _DspSlider extends StatelessWidget {
  const _DspSlider({
    required this.title,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.defaultValue,
    required this.label,
    required this.onChanged,
  });
  final String title;
  final String description;
  final double value;
  final double min;
  final double max;
  final double defaultValue;
  final String label;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) => SettingTile(
    title: Text(title),
    subtitle: Text(description, style: settingsMuted(context)),
    control: SizedBox(
      width: 280,
      child: Row(
        children: [
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: max <= 1 ? 20 : ((max - min) * 2).round(),
              label: label,
              semanticFormatterCallback: (_) => label,
              onChanged: onChanged,
            ),
          ),
          SizedBox(width: 64, child: Text(label, textAlign: TextAlign.end)),
          IconButton(
            tooltip: tr.resetNamed(title),
            onPressed: onChanged == null || value == defaultValue ? null : () => onChanged!(defaultValue),
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
    ),
  );
}

/// Settings > Sound > Output & quality: DACs and hi-fi setups, folded until opened.
class AdvancedAudioSettings extends StatefulWidget {
  const AdvancedAudioSettings({super.key});

  static Future<void> _pickImpulse(BuildContext context, AudioEngine audio) async {
    final messenger = ScaffoldMessenger.of(context);
    final file = (await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['wav', 'flac'],
      dialogTitle: tr.chooseImpulse,
    )).firstOrNull;
    final path = file?.path;
    if (file == null || path == null) return;
    try {
      await audio.setImpulse(File(path), name: file.name, into: await getApplicationSupportDirectory());
    } catch (e) {
      debugPrint('Impulse response: $e');
      messenger.showSnackBar(SnackBar(content: Text(tr.couldntUseFile)));
    }
  }

  static const _rates = [44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000];

  @override
  State<AdvancedAudioSettings> createState() => _AdvancedAudioSettingsState();
}

class _AdvancedAudioSettingsState extends State<AdvancedAudioSettings> {
  AudioEngine? _audio;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final audio = PlayerScope.read(context).audio;
    if (identical(_audio, audio)) return;
    _audio = audio;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) audio.refreshDevices();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!AudioEngine.supported) return const SizedBox.shrink();
    final audio = PlayerScope.of(context).audio;
    final muted = settingsMuted(context);
    return ListenableBuilder(
      listenable: audio,
      builder: (context, _) {
        final locked = audio.bitPerfect;
        final dopReady = audio.bitPerfect && audio.bypassesMixer;
        final android = Host.isAndroid;
        final usbName = audio.usb.device?.name;
        // Plugged in, but this phone offers no bit-perfect format for it: say so, rather than "plug in a DAC".
        final pluggedName = audio.usb.plugged?.name;
        return SettingsCard(
          children: [
            if (AudioEngine.hasRoutePicker)
              SettingTile(
                icon: Icons.speaker_rounded,
                title: Text(tr.output),
                subtitle: Text(
                  '${audio.route?.name.isNotEmpty == true ? audio.route!.name : 'iPhone'}'
                  '${audio.route == null ? '' : ' · ${SignalPath.formatRate(audio.route!.rate)}'}. '
                  '${tr.iosOutputNote}',
                  style: muted,
                ),
                control: const RoutePickerButton(),
              ),
            if (AudioEngine.hasOutputChoice)
              SettingTile(
                icon: Icons.speaker_rounded,
                title: Text(tr.outputDevice),
                subtitle: Text(
                  audio.deviceError ?? tr.directDevicesNote,
                  style: audio.deviceError == null
                      ? muted
                      : muted?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
                control: OptionPicker<String>(
                  maxWidth: 200,
                  value: audio.devices.any((d) => d.name == audio.device) ? audio.device : 'auto',
                  onChanged: audio.setDevice,
                  options: [
                    for (final d in audio.devices) (d.name, d.direct ? '${d.description} (direct)' : d.description),
                  ],
                ),
              ),
            // Android routes media to a plugged-in USB DAC by itself: say which one, no picker.
            if (android && audio.usb.supported)
              ListTile(
                leading: const Icon(Icons.speaker_rounded),
                title: Text(tr.outputDevice),
                subtitle: Text(
                  pluggedName == null ? tr.phonesOwnOutput : tr.usbDacNamed(usbName ?? pluggedName),
                  style: muted,
                ),
              ),
            if (audio.hasBitPerfect || android)
              SwitchListTile(
                secondary: const Icon(Icons.verified_outlined),
                title: Text(tr.bitPerfectMode),
                subtitle: Text(
                  android
                      ? !audio.usb.supported
                            ? tr.needsAndroid14
                            : usbName == null && pluggedName != null
                            ? (audio.usb.plugged?.bitPerfectReported ?? 0) > 0
                                  ? tr.androidFormatsUnplayable(
                                      pluggedName,
                                      audio.usb.plugged!.bitPerfectReported ?? 0,
                                      audio.usb.plugged!.reported ?? 0,
                                    )
                                  : tr.phoneNoBitPerfect(pluggedName, audio.usb.plugged?.reported ?? 0)
                            : usbName == null
                            ? tr.plugInDacForBitPerfect
                            : tr.bitPerfectAndroid
                      : Host.isMacOS
                      ? tr.bitPerfectMac
                      : AudioEngine.hasExclusiveMode
                      ? tr.bitPerfectWindows
                      : tr.bitPerfectLinux,
                  style: muted,
                ),
                value: audio.bitPerfectWanted,
                onChanged: android && usbName == null ? null : audio.setBitPerfect,
              ),
            if (android) _DirectUsbBeta(audio: audio),
            if (audio.hasBitPerfect)
              SwitchListTile(
                secondary: const Icon(Icons.graphic_eq_rounded),
                title: Text(tr.nativeDsd),
                subtitle: Text(
                  dopReady && audio.dopNote != null
                      ? audio.dopNote!
                      : dopReady
                      ? tr.nativeDsdSubtitle
                      : android
                      ? tr.needsBitPerfectAndDac
                      : AudioEngine.hasExclusiveMode
                      ? tr.needsBitPerfectAndExclusive
                      : tr.needsBitPerfect,
                  style: muted,
                ),
                value: audio.nativeDsd && dopReady,
                onChanged: dopReady ? audio.setNativeDsd : null,
              ),
            if (AudioEngine.hasExclusiveMode)
              SwitchListTile(
                secondary: const Icon(Icons.lock_outline_rounded),
                title: Text(tr.exclusiveMode),
                subtitle: Text(Host.isMacOS ? tr.exclusiveMac : tr.exclusiveWindows, style: muted),
                value: audio.exclusive,
                onChanged: audio.setExclusive,
              ),
            SettingTile(
              icon: Icons.multiline_chart_rounded,
              title: Text(tr.outputSampleRate),
              subtitle: Text(locked ? tr.followsEachSong : tr.followOrConvert, style: muted),
              control: OptionPicker<int>(
                value: locked ? 0 : audio.outputRate ?? 0,
                onChanged: locked ? null : (v) => audio.setOutputRate(v == 0 ? null : v),
                options: [
                  (0, tr.followTheSong),
                  for (final r in AdvancedAudioSettings._rates) (r, SignalPath.formatRate(r)),
                ],
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.high_quality_outlined),
              title: Text(tr.hqResampler),
              subtitle: Text(tr.hqResamplerSubtitle, style: muted),
              value: audio.hqResamplerActive,
              onChanged: locked && audio.bypassesMixer ? null : audio.setHqResampler,
            ),
            SettingTile(
              icon: Icons.timer_outlined,
              title: Text(tr.buffer),
              subtitle: Text(tr.bufferSubtitle, style: muted),
              control: OptionPicker<BufferSize>(
                value: audio.buffer,
                onChanged: audio.setBuffer,
                options: [for (final b in BufferSize.values) (b, '${b.label} (${(b.seconds * 1000).round()} ms)')],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: Text(tr.signalPath),
              subtitle: Text(tr.signalPathSubtitleExact, style: muted),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showSignalPath(context),
            ),
          ],
        );
      },
    );
  }
}

TextStyle? settingsMuted(BuildContext context) =>
    Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);

/// A titled group of settings.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        ),
        child,
      ],
    ),
  );
}

/// Rows on a rounded panel, with thin lines between them.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.elevated,
    borderRadius: LayoutPrefs.corner(12),
    clipBehavior: Clip.antiAlias,
    child: ListTileTheme(
      iconColor: AppColors.textSecondary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      child: Column(
        children: [
          for (final (i, row) in children.indexed) ...[if (i > 0) const SettingsDivider(), row],
        ],
      ),
    ),
  );
}

class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) => Divider(height: 1, thickness: 1, indent: 58, color: AppColors.divider);
}

/// A settings row whose control sits on the right, or under the text when
/// the window is too narrow for both side by side.
/// Apple's route picker (iPhone speaker, Bluetooth, AirPlay, a USB DAC): the system button, tapped as usual.
class RoutePickerButton extends StatelessWidget {
  const RoutePickerButton({super.key});

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 44,
    child: UiKitView(
      viewType: 'riflay/route-picker',
      creationParamsCodec: const StandardMessageCodec(),
      gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
    ),
  );
}

class SettingTile extends StatelessWidget {
  const SettingTile({super.key, required this.title, this.subtitle, required this.control, this.icon, this.leading});

  final IconData? icon;

  /// Instead of [icon] (e.g. an avatar).
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget control;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth >= 520
        ? ListTile(
            leading: leading ?? (icon == null ? null : Icon(icon)),
            title: title,
            subtitle: subtitle,
            trailing: control,
          )
        : ListTile(
            leading: leading ?? (icon == null ? null : Icon(icon)),
            title: title,
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ?subtitle,
                Align(alignment: Alignment.centerLeft, child: control),
              ],
            ),
          ),
  );
}

/// Android: Direct USB's beta switch ([BetaFeature.directUsb]), and the option itself once it is on. Turning the
/// beta on asks first ([confirmDirectUsb]); turning it off stops Direct USB, back to Android's output.
class _DirectUsbBeta extends StatelessWidget {
  const _DirectUsbBeta({required this.audio});

  final AudioEngine audio;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: BetaFeatures.instance,
    builder: (context, _) {
      final on = BetaFeatures.instance.isOn(BetaFeature.directUsb);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.science_outlined),
            title: Text(tr.directUsbBeta),
            subtitle: Text(tr.directUsbBetaSubtitle, style: settingsMuted(context)),
            value: on,
            onChanged: (v) async {
              if (v) {
                if (await confirmDirectUsb(context)) await BetaFeatures.instance.set(BetaFeature.directUsb, true);
              } else {
                await audio.setDirectUsb(false);
                await BetaFeatures.instance.set(BetaFeature.directUsb, false);
              }
            },
          ),
          if (on) _DirectUsbTile(audio: audio),
        ],
      );
    },
  );
}

/// The warning before Direct USB's beta goes on. True when the person chose to turn it on.
@visibleForTesting
Future<bool> confirmDirectUsb(BuildContext context) => confirmDialog(
  context,
  title: tr.directUsbWarningTitle,
  body: tr.directUsbWarningBody,
  confirmLabel: tr.directUsbWarningConfirm,
  icon: const Icon(Icons.warning_amber_rounded),
);

/// Android: Direct USB, bit-perfect to a USB DAC on any phone (`DirectUsb.kt`, libusbdac). Experimental: it says
/// what it does at every step (the DAC, the permission, where the song goes and in what format, dropouts), so a
/// screenshot is enough to tell what happened.
class _DirectUsbTile extends StatelessWidget {
  const _DirectUsbTile({required this.audio});

  final AudioEngine audio;

  @override
  Widget build(BuildContext context) {
    final d = audio.directUsb;
    final muted = settingsMuted(context);
    final text = Theme.of(context).textTheme;
    final dac = d.devices.firstOrNull?.name;
    final on = audio.directUsbWanted;
    final status = !on && d.closedWhileStarting
        ? tr.directUsbClosedWhileStarting
        : !on && d.failed
        ? tr.directUsbFailed
        : !on
        ? tr.directUsbIntro
        : dac == null
        ? tr.directUsbPlugIn
        : d.needsPermission
        ? tr.directUsbAllow(dac)
        : switch (d.route) {
            'direct' => '${tr.directUsbBitPerfectTo(dac)}${d.routeFormat == null ? '' : ': ${d.routeFormat}'}',
            'fallback' => tr.directUsbFallback(d.routeFormat == null ? '' : ' (${d.routeFormat})', dac),
            _ => tr.directUsbOnWith(dac),
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.usb_rounded),
          title: Text(tr.directUsb),
          subtitle: Text(status, style: muted),
          value: on,
          onChanged: audio.setDirectUsb,
        ),
        if (on && d.needsPermission)
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
            child: OutlinedButton(onPressed: d.requestPermission, child: Text(tr.allowUsbAccess)),
          ),
        // What stopped it, after it turned itself off.
        if (!on && d.failed && d.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
            child: Text(
              tr.problemWith('${d.error}'),
              style: (text.bodySmall ?? const TextStyle()).copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (on)
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
            child: DefaultTextStyle(
              style: (text.bodySmall ?? const TextStyle()).copyWith(
                color: AppColors.textMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr.directUsbPipe(
                      d.running ? tr.pipeOpen : tr.pipeClosed,
                      audio.directUsbActive ? tr.directUsb : 'Android',
                    ),
                  ),
                  if (d.streamFormat != null) Text(tr.fromThePlayer('${d.streamFormat}')),
                  Text(tr.directUsbRoute('${d.route}${d.routeFormat == null ? '' : ' (${d.routeFormat})'}')),
                  if (d.underruns > 0) Text(tr.dropouts('${d.underruns}')),
                  if (d.error != null)
                    Text(tr.problemWith('${d.error}'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  if (d.log.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    for (final l in d.log.take(6)) Text(l, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Leveling's helper for songs without ReplayGain tags: measures the library's files, one at a time, and says how
/// many are done. Songs that play are measured anyway (and the next one), so this is for all of them at once.
class _MeasureLoudness extends StatelessWidget {
  const _MeasureLoudness();

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.of(context);
    final muted = settingsMuted(context);
    final files = [
      for (final t in c.library)
        if (AudioAnalysis.fileOf(t) != null) t,
    ];
    if (files.isEmpty) return const SizedBox.shrink();
    return ValueListenableBuilder(
      valueListenable: AudioAnalysis.scan,
      builder: (context, progress, _) => ListTile(
        leading: const Icon(Icons.multitrack_audio_rounded),
        title: Text(tr.measureLoudness),
        subtitle: Text(
          progress == null
              ? tr.measureLoudnessSubtitle(AudioAnalysis.measuredOf(files), files.length)
              : tr.measuringLoudness(progress.$1, progress.$2),
          style: muted,
        ),
        trailing: progress == null
            ? FilledButton.tonal(onPressed: () => AudioAnalysis.scanAll(files), child: Text(tr.measure))
            : OutlinedButton(onPressed: AudioAnalysis.stopScan, child: Text(tr.stop)),
      ),
    );
  }
}
