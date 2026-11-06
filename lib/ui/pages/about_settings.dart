import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_version.dart';
import '../../platform/features.dart';
import '../../platform/host.dart';
import '../theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_update_tile.dart';
import '../../services/language.dart';
import 'sound_settings.dart' show SettingsCard, settingsMuted;

const _repo = 'https://github.com/Araryarch67/Riflay';

/// Where to support Riflay (the same link as the repository's Sponsor button, `.github/FUNDING.yml`).
const donateUrl = 'https://tako.id/ararya/gift';

/// What a bug report needs to say about this copy of Riflay: the version and the system it runs on.
String aboutDetails() => [
  'Riflay $appVersion',
  debugSystem ?? _system(),
  if (Host.dartVersion.isNotEmpty) 'Dart ${Host.dartVersion}',
].join(' · ');

/// Stands in for the system in [aboutDetails] (screenshots show no real computer).
@visibleForTesting
String? debugSystem;

/// "Linux 6.12.1-arch1-1", "Windows 11 Home 10.0 (Build 26100)", "Android 15": what the platform says, without
/// Linux's build date and flags.
String _system() {
  final v = systemVersionLabel(Host.operatingSystem, Host.operatingSystemVersion).split(' #').first.trim();
  final name = switch (Host.operatingSystem) {
    'linux' => 'Linux',
    'windows' => 'Windows',
    'macos' => 'macOS',
    'ios' => 'iOS',
    'android' => 'Android',
    'web' => 'Web browser',
    final other => other,
  };
  if (v.isEmpty) return name;
  return v.startsWith(name) || v.startsWith('"') ? v : '$name $v';
}

/// Windows 11 retains NT 10.0; client builds from 22000 identify Windows 11.
@visibleForTesting
String systemVersionLabel(String os, String version) {
  if (os != 'windows' || version.toLowerCase().contains('server')) return version;
  final match = RegExp(r'(?:[Bb]uild[ .:]*(\d+)|10\.0\.(\d+))').firstMatch(version);
  final build = int.tryParse(match?.group(1) ?? match?.group(2) ?? '');
  if (build == null || build < 22000) return version;
  if (version.contains('Windows 10')) return version.replaceFirst('Windows 10', 'Windows 11');
  if (version.contains('Windows 11')) return version;
  return 'Windows 11 ($version)';
}

/// Settings › About: the version, where the code and releases are, the licence, and the details for a bug report.
class AboutSettings extends StatelessWidget {
  const AboutSettings({super.key});

  Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.couldntOpenBrowser)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = settingsMuted(context);
    Widget link(IconData icon, String title, String subtitle, VoidCallback onTap) => ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle, style: muted),
      trailing: const Icon(Icons.open_in_new_rounded, size: 18),
      onTap: onTap,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 20),
          child: Row(
            children: [
              const AppLogo(size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Riflay', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(tr.versionNamed(appVersion), style: text.bodyMedium?.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
        SettingsCard(
          children: [
            if (Features.appUpdates) const AppUpdateTile(),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(tr.version),
              subtitle: Text(aboutDetails(), style: muted),
              trailing: IconButton(
                tooltip: tr.copy,
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: aboutDetails()));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.copied)));
                  }
                },
              ),
            ),
            link(
              Icons.new_releases_outlined,
              tr.whatsNew,
              tr.whatsNewSubtitle,
              () => _open(context, '$_repo/releases'),
            ),
            link(
              Icons.bug_report_outlined,
              tr.reportProblem,
              tr.reportProblemSubtitle,
              () => _open(context, '$_repo/issues/new'),
            ),
            // Songs streamed here earn their makers next to nothing: Premium is how listening pays them.
            link(
              Icons.music_note_rounded,
              tr.supportArtists,
              tr.supportArtistsSubtitle,
              () => _open(context, 'https://www.youtube.com/musicpremium'),
            ),
            link(
              Icons.favorite_outline_rounded,
              tr.supportRiflay,
              tr.supportRiflaySubtitle,
              () => _open(context, donateUrl),
            ),
            link(Icons.code_rounded, tr.sourceCode, tr.sourceCodeSubtitle, () => _open(context, _repo)),
            ListTile(
              leading: const Icon(Icons.gavel_rounded),
              title: Text(tr.licence),
              subtitle: Text('GNU AGPL v3.0', style: muted),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () => _open(context, '$_repo/blob/main/LICENSE'),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(tr.openSourceLicences),
              subtitle: Text(tr.openSourceLicencesSubtitle, style: muted),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Riflay',
                applicationVersion: appVersion,
                useRootNavigator: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
