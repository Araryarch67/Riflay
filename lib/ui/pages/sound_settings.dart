import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../platform/host.dart';
import '../../services/audio_engine.dart';
import '../../services/carla_locator.dart';
import '../../services/crossfade.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/menus.dart';
import '../widgets/signal_path.dart';
import 'equalizer_page.dart';

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
            title: const Text('Autoplay'),
            subtitle: const Text('When the queue ends, keep going with similar songs'),
            value: c.autoplay,
            onChanged: c.setAutoplay,
          ),
          if (AudioEngine.supported)
            SwitchListTile(
              secondary: const Icon(Icons.join_inner_rounded),
              title: const Text('Gapless playback'),
              subtitle: const Text('No added silence between tracks. Crossfade is under Sound effects (DSP).'),
              value: c.audio.gapless,
              onChanged: c.audio.setGapless,
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
        String lockedNote(String normal) => locked ? 'Off while bit-perfect mode is on' : normal;
        return SettingsCard(
          children: [
            if (AudioEngine.supported) ...[
              ListTile(
                leading: const Icon(Icons.equalizer_rounded),
                title: const Text('Equalizer'),
                subtitle: Text(lockedNote(audio.eqActive ? audio.eqPreset : 'Off'), style: muted),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => shell.open(const EqualizerPage()),
              ),
              SettingTile(
                icon: Icons.graphic_eq_rounded,
                title: const Text('Volume leveling'),
                subtitle: Text(
                  lockedNote('Plays songs at a similar loudness, using their ReplayGain tags'),
                  style: muted,
                ),
                control: OptionPicker<VolumeLeveling>(
                  value: audio.leveling,
                  onChanged: locked ? null : audio.setLeveling,
                  options: [for (final v in VolumeLeveling.values) (v, v.label)],
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.compare_arrows_rounded),
                title: const Text('Crossfade'),
                subtitle: Text(
                  audio.crossfadeBlock ??
                      'The end of a song fades into the start of the next. Off in bit-perfect and exclusive modes',
                  style: muted,
                ),
                value: audio.crossfade,
                onChanged: audio.crossfadeBlock != null ? null : audio.setCrossfade,
              ),
              if (audio.crossfade && audio.crossfadeBlock == null) ...[
                SettingTile(
                  icon: Icons.timelapse_rounded,
                  title: const Text('Fade length'),
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
                  title: const Text('Skip for albums'),
                  subtitle: Text(
                    'Songs that follow each other on an album play without a fade, as the artist made them',
                    style: muted,
                  ),
                  value: audio.crossfadeSkipAlbums,
                  onChanged: audio.setCrossfadeSkipAlbums,
                ),
              ],
              SwitchListTile(
                secondary: const Icon(Icons.spatial_audio_rounded),
                title: const Text('Virtual speakers'),
                subtitle: Text(
                  lockedNote(
                    monoOn ? 'Off while Mono audio is on' : 'For headphones: the music plays in front of you, like from two speakers, instead of inside your head',
                  ),
                  style: muted,
                ),
                value: speakersOn,
                onChanged: locked || monoOn ? null : audio.setVirtualSpeakers,
              ),
              if (audio.virtualSpeakers)
                _DspSlider(
                  title: 'Virtual speaker level',
                  description: 'Adjust the simulation output level to match your other listening modes.',
                  value: audio.virtualSpeakerGain,
                  min: -12,
                  max: 6,
                  defaultValue: 0,
                  label: '${audio.virtualSpeakerGain.toStringAsFixed(1)} dB',
                  onChanged: locked || monoOn ? null : audio.setVirtualSpeakerGain,
                ),
              SettingTile(
                icon: Icons.headphones_rounded,
                title: const Text('Headphone crossfeed'),
                subtitle: Text(
                  lockedNote(
                    monoOn
                        ? 'Off while Mono audio is on'
                        : speakersOn
                        ? 'Not needed with Virtual speakers: they already do this'
                        : 'Makes headphones sound more like speakers in a room',
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
                        child: Text(audio.crossfeed == 0 ? 'Off' : '${(audio.crossfeed * 100).round()}%', style: muted),
                      ),
                    ],
                  ),
                ),
              ),
              if (audio.crossfeed > 0)
                _DspSlider(
                  title: 'Crossfeed soundstage',
                  description: 'Adjust the frequency range blended between the left and right channels. Default: 50%.',
                  value: audio.crossfeedRange,
                  min: 0,
                  max: 1,
                  defaultValue: 0.5,
                  label: '${(audio.crossfeedRange * 100).round()}%',
                  onChanged: locked || monoOn || speakersOn ? null : audio.setCrossfeedRange,
                ),
              SettingTile(
                icon: Icons.hearing_rounded,
                title: const Text('Mono audio'),
                subtitle: Text(
                  lockedNote('Both sides as one sound. Handy when one side of your headphones doesn\'t work'),
                  style: muted,
                ),
                control: OptionPicker<MonoAudio>(
                  value: locked ? MonoAudio.off : audio.mono,
                  onChanged: locked ? null : audio.setMono,
                  options: [for (final m in MonoAudio.values) (m, m.label)],
                ),
              ),
              if (AudioEngine.pluginBridge != null)
                if (AudioEngine.hasPlugins)
                  SettingTile(
                    icon: Icons.extension_outlined,
                    title: const Text('Audio plugins'),
                    subtitle: Text(
                      locked
                          ? 'Off while bit-perfect mode is on'
                          : 'VST, LV2 and CLAP plugins, set up in Carla: add them there and save, and they play here',
                      style: muted,
                    ),
                    control: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(onPressed: locked ? null : audio.editPlugins, child: const Text('Edit in Carla')),
                        Switch(value: audio.plugins && !locked, onChanged: locked ? null : audio.setPlugins),
                      ],
                    ),
                  )
                else
                  SettingTile(
                    icon: Icons.extension_outlined,
                    title: const Text('Audio plugins'),
                    subtitle: Text(
                      Host.isWindows
                          ? 'Needs Carla, a free program that holds your VST, LV2 and CLAP plugins. Download it, unzip it in your '
                                'Downloads or Program Files folder, then reopen this page.'
                          : 'Needs Carla, a free program that holds your VST, LV2 and CLAP plugins. Install it, then reopen this page.',
                      style: muted,
                    ),
                    control: TextButton(
                      onPressed: () => launchUrl(Uri.parse(CarlaLocator.downloadPage)),
                      child: const Text('Install Carla'),
                    ),
                  ),
              SettingTile(
                icon: Icons.surround_sound_rounded,
                title: const Text('Room correction'),
                subtitle: Text(
                  locked
                      ? 'Off while bit-perfect mode is on'
                      : audio.impulseName == null
                      ? 'Load an impulse response (WAV or FLAC, e.g. made with REW) to correct your room or headphones'
                      : audio.impulseName!,
                  style: muted,
                ),
                control: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: locked ? null : () => AdvancedAudioSettings._pickImpulse(context, audio),
                      child: Text(audio.impulseName == null ? 'Choose file' : 'Change'),
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
                  title: 'Room correction headroom',
                  description: 'Lower the corrected signal if the impulse response makes peaks too loud.',
                  value: audio.convolutionGain,
                  min: -24,
                  max: 0,
                  defaultValue: 0,
                  label: '${audio.convolutionGain.toStringAsFixed(1)} dB',
                  onChanged: locked || !audio.convolution ? null : audio.setConvolutionGain,
                ),
              ListTile(
                leading: const Icon(Icons.account_tree_outlined),
                title: const Text('Signal path'),
                subtitle: const Text('See which effects are actually active for the current song'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showSignalPath(context),
              ),
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
            tooltip: 'Reset $title',
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
      dialogTitle: 'Choose an impulse response',
    )).firstOrNull;
    final path = file?.path;
    if (file == null || path == null) return;
    try {
      await audio.setImpulse(File(path), name: file.name, into: await getApplicationSupportDirectory());
    } catch (e) {
      debugPrint('Impulse response: $e');
      messenger.showSnackBar(const SnackBar(content: Text('Couldn\'t use that file')));
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
                title: const Text('Output'),
                subtitle: Text(
                  '${audio.route?.name.isNotEmpty == true ? audio.route!.name : 'iPhone'}'
                  '${audio.route == null ? '' : ' · ${SignalPath.formatRate(audio.route!.rate)}'}. '
                  'A USB DAC follows each song\'s sample rate; the speaker and Bluetooth keep one rate. '
                  'iOS always mixes the sound, so it can\'t be bit-perfect here.',
                  style: muted,
                ),
                control: const RoutePickerButton(),
              ),
            if (AudioEngine.hasOutputChoice)
              SettingTile(
                icon: Icons.speaker_rounded,
                title: const Text('Output device'),
                subtitle: Text(
                  audio.deviceError ??
                      'Devices marked "direct" skip the system mixer: bit-perfect, but other apps go quiet',
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
                title: const Text('Output device'),
                subtitle: Text(
                  pluggedName == null ? 'Your phone\'s own output' : '${usbName ?? pluggedName} (USB DAC)',
                  style: muted,
                ),
              ),
            if (audio.hasBitPerfect || android)
              SwitchListTile(
                secondary: const Icon(Icons.verified_outlined),
                title: const Text('Bit-perfect mode'),
                subtitle: Text(
                  android
                      ? !audio.usb.supported
                            ? 'Needs Android 14 or later'
                            : usbName == null && pluggedName != null
                            ? (audio.usb.plugged?.bitPerfectReported ?? 0) > 0
                                  ? 'Android offers $pluggedName only in formats Riflay can\'t play bit-perfect '
                                        '(${audio.usb.plugged!.bitPerfectReported} of ${audio.usb.plugged!.reported} formats). '
                                        'Riflay still plays through your DAC, with Android mixing the sound first.'
                                  : 'This phone doesn\'t offer bit-perfect output for $pluggedName: its maker leaves it out '
                                        '(Android lists ${audio.usb.plugged?.reported ?? 0} formats for it, none bit-perfect). '
                                        'Riflay still plays through your DAC, with Android mixing the sound first.'
                            : usbName == null
                            ? 'Plug in a USB DAC to play bit-perfect'
                            : 'Sends the file to your USB DAC untouched: no equalizer, leveling or resampling. '
                                  'Other apps and system sounds are muted on the DAC, and the phone\'s volume keys stop working: '
                                  'use your DAC\'s volume, since lowering Riflay\'s own volume changes the sound.'
                      : Host.isMacOS
                      ? 'No equalizer, leveling or resampling in Riflay, and your DAC follows each song\'s sample rate. '
                            'Volume still works; at 100% nothing is changed. Other apps keep playing, so macOS still mixes the sound: '
                            'turn on Exclusive mode too to send the file to your DAC untouched.'
                      : AudioEngine.hasExclusiveMode
                      ? 'No equalizer, leveling or resampling in Riflay. Volume still works; at 100% nothing is changed. '
                            'Other apps keep playing, so Windows still mixes the sound: turn on Exclusive mode too to send the file to your DAC untouched.'
                      : 'Sends the file to your DAC untouched: no equalizer, leveling or resampling. Volume still works; at 100% nothing is changed. '
                            'Takes over your DAC so the system mixer can\'t resample. Meanwhile other apps play through another output.',
                  style: muted,
                ),
                value: audio.bitPerfectWanted,
                onChanged: android && usbName == null ? null : audio.setBitPerfect,
              ),
            if (audio.hasBitPerfect)
              SwitchListTile(
                secondary: const Icon(Icons.graphic_eq_rounded),
                title: const Text('Native DSD (DoP)'),
                subtitle: Text(
                  dopReady && audio.dopNote != null
                      ? audio.dopNote!
                      : dopReady
                      ? 'Sends DSD files to your DAC as DSD instead of converting them. '
                            'Only for DACs that support DoP: others play a faint hiss, so turn it off then. '
                            'The volume stays at 100% for DSD songs; use your DAC\'s.'
                      : android
                      ? 'Needs Bit-perfect mode and a USB DAC that takes 176.4 kHz or higher'
                      : AudioEngine.hasExclusiveMode
                      ? 'Needs Bit-perfect mode and Exclusive mode'
                      : 'Needs Bit-perfect mode',
                  style: muted,
                ),
                value: audio.nativeDsd && dopReady,
                onChanged: dopReady ? audio.setNativeDsd : null,
              ),
            if (AudioEngine.hasExclusiveMode)
              SwitchListTile(
                secondary: const Icon(Icons.lock_outline_rounded),
                title: const Text('Exclusive mode'),
                subtitle: Text(
                  Host.isMacOS
                      ? 'Takes over the device so macOS can\'t mix or resample: the DAC switches to each song\'s sample rate. '
                            'Other apps go silent while Riflay plays.'
                      : 'Takes over the device so Windows\' mixer can\'t resample: the DAC switches to each song\'s sample rate. '
                            'Other apps go silent while Riflay plays, and Windows\' volume mixer can\'t control it.',
                  style: muted,
                ),
                value: audio.exclusive,
                onChanged: audio.setExclusive,
              ),
            SettingTile(
              icon: Icons.multiline_chart_rounded,
              title: const Text('Output sample rate'),
              subtitle: Text(
                locked
                    ? 'Follows each song while bit-perfect mode is on'
                    : 'Follow the song, or convert everything to one rate',
                style: muted,
              ),
              control: OptionPicker<int>(
                value: locked ? 0 : audio.outputRate ?? 0,
                onChanged: locked ? null : (v) => audio.setOutputRate(v == 0 ? null : v),
                options: [
                  (0, 'Follow the song'),
                  for (final r in AdvancedAudioSettings._rates) (r, SignalPath.formatRate(r)),
                ],
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.high_quality_outlined),
              title: const Text('High-quality resampler'),
              subtitle: Text('SoX-grade conversion whenever the rate has to change (slightly more CPU)', style: muted),
              value: audio.hqResamplerActive,
              onChanged: locked && audio.bypassesMixer ? null : audio.setHqResampler,
            ),
            SettingTile(
              icon: Icons.timer_outlined,
              title: const Text('Buffer'),
              subtitle: Text('Raise it if you hear crackles or dropouts', style: muted),
              control: OptionPicker<BufferSize>(
                value: audio.buffer,
                onChanged: audio.setBuffer,
                options: [for (final b in BufferSize.values) (b, '${b.label} (${(b.seconds * 1000).round()} ms)')],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: const Text('Signal path'),
              subtitle: Text('See exactly what happens to the song you\'re playing', style: muted),
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
