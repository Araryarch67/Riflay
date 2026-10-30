import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_version.dart';
import '../../platform/host.dart';
import '../theme.dart';
import '../widgets/app_logo.dart';
import 'sound_settings.dart' show SettingsCard, settingsMuted;

const _repo = 'https://github.com/Araryarch67/Riflay';

/// What a bug report needs to say about this copy of Riflay: the version and the system it runs on.
String aboutDetails() => 'Riflay $appVersion · ${debugSystem ?? _system()} · Dart ${Platform.version.split(' ').first}';

/// Stands in for the system in [aboutDetails] (screenshots show no real computer).
@visibleForTesting
String? debugSystem;

/// "Linux 6.12.1-arch1-1", "Windows 11 Home 10.0 (Build 26100)", "Android 15": what the platform says, without
/// Linux's build date and flags.
String _system() {
  final v = Platform.operatingSystemVersion.split(' #').first.trim();
  final name = switch (Host.operatingSystem) {
    'linux' => 'Linux',
    'windows' => 'Windows',
    'macos' => 'macOS',
    'ios' => 'iOS',
    'android' => 'Android',
    final other => other,
  };
  return v.startsWith(name) || v.startsWith('"') ? v : '$name $v';
}

/// Settings › About: the version, where the code and releases are, the licence, and the details for a bug report.
class AboutSettings extends StatelessWidget {
  const AboutSettings({super.key});

  Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't open the browser.")));
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
                    Text('Version $appVersion', style: text.bodyMedium?.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
        SettingsCard(
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Version'),
              subtitle: Text(aboutDetails(), style: muted),
              trailing: IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: aboutDetails()));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                  }
                },
              ),
            ),
            link(
              Icons.new_releases_outlined,
              "What's new",
              'Release notes and downloads for every platform',
              () => _open(context, '$_repo/releases'),
            ),
            link(
              Icons.bug_report_outlined,
              'Report a problem',
              'Opens a new issue; paste the version details in it',
              () => _open(context, '$_repo/issues/new'),
            ),
            link(Icons.code_rounded, 'Source code', 'Riflay is open source, on GitHub', () => _open(context, _repo)),
            ListTile(
              leading: const Icon(Icons.gavel_rounded),
              title: const Text('Licence'),
              subtitle: Text('GNU AGPL v3.0', style: muted),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () => _open(context, '$_repo/blob/main/LICENSE'),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Open-source licences'),
              subtitle: Text('The libraries Riflay is built with', style: muted),
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
