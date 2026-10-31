import 'package:flutter/material.dart';

import '../../platform/features.dart';
import '../../services/beta_features.dart';
import '../../services/discord_presence.dart';
import '../../services/lyrics.dart';
import '../../services/player_controller.dart';
import '../navigation.dart';
import '../shell_scope.dart';
import '../shortcuts.dart';
import '../theme.dart';
import '../widgets/page_scaffold.dart';
import '../../services/audio_engine.dart';
import 'appearance_settings.dart';
import 'about_settings.dart';
import 'beta_settings.dart';
import 'layout_settings.dart';
import 'library_settings.dart';
import 'download_settings.dart';
import 'privacy_settings.dart';
import 'sound_settings.dart';
import 'spotify_page.dart';
import 'youtube_music_page.dart';

/// The few groups on the first Settings page; each opens a page that lists its [SettingsTopic]s.
enum SettingsGroup {
  sound('sound', 'Sound', Icons.graphic_eq_rounded, 'Equalizer, volume leveling, crossfade, hi-fi output'),
  look('look', 'Look & feel', Icons.palette_outlined, 'Themes, colours, text size, what the screens show'),
  library(
    'library',
    'Library & downloads',
    Icons.library_music_outlined,
    'Music folders, downloads, listening history',
  ),
  accounts(
    'accounts',
    'Accounts & services',
    Icons.manage_accounts_outlined,
    'YouTube Music, Spotify, Discord, lyrics',
  );

  const SettingsGroup(this.id, this.label, this.icon, this._summary);
  final String id;
  final String label;
  final IconData icon;
  final String _summary;

  /// One plain line; where this build leaves sections out (the web build), the names of those it shows.
  String get summary => sections.length == SettingsTopic.values.where((s) => s.group == this).length
      ? _summary
      : sections.map((s) => s.label).join(', ');

  /// This group's own page.
  String get location => Locations.settingsTopic(id);

  /// The sections shown on this group's page, in order, for what this device and the Beta switches allow.
  List<SettingsTopic> get sections => [
    for (final s in SettingsTopic.values)
      if (s.group == this && s.available) s,
  ];
}

/// One page of settings, opened from the list on a [SettingsGroup] page.
enum SettingsTopic {
  playback(
    SettingsGroup.sound,
    'playback',
    'Playback',
    Icons.play_circle_outline_rounded,
    'Equalizer, volume leveling, crossfade, Virtual speakers, mono audio',
  ),
  advanced(
    SettingsGroup.sound,
    'hifi',
    'Hi-fi audio',
    Icons.tune_rounded,
    'Output device, bit-perfect mode, sample rate',
  ),
  appearance(
    SettingsGroup.look,
    'appearance',
    'Appearance',
    Icons.palette_outlined,
    'Theme, accent colour, background, text size, font',
  ),
  layout(
    SettingsGroup.look,
    'layout',
    'Layout',
    Icons.dashboard_customize_outlined,
    'Shapes, sizes, what the player shows',
  ),
  library(
    SettingsGroup.library,
    'library',
    'Library',
    Icons.folder_outlined,
    'Keep music folders up to date, find songs you have twice',
  ),
  downloads(
    SettingsGroup.library,
    'downloads',
    'Downloads',
    Icons.download_rounded,
    'Format, quality, where songs are saved',
  ),
  history(
    SettingsGroup.library,
    'history',
    'Listening history & Wrap',
    Icons.history_rounded,
    'The history behind your stats, kept on this device',
  ),
  account(
    SettingsGroup.accounts,
    'youtube-music',
    'YouTube Music account',
    Icons.person_outline_rounded,
    'Sign in with Google',
  ),
  spotify(
    SettingsGroup.accounts,
    'spotify',
    'Spotify',
    Icons.library_music_outlined,
    'Bring your playlists, Liked Songs and albums over',
  ),
  integrations(
    SettingsGroup.accounts,
    'services',
    'Discord & lyrics services',
    Icons.extension_outlined,
    'Show what you play on Discord, lyrics services',
  );

  const SettingsTopic(this.group, this.id, this._label, this.icon, this._summary);
  final SettingsGroup group;
  final String id;
  final String _label;

  /// The section's name; without Discord (the web build) the services section is about lyrics alone.
  String get label => this == integrations && !DiscordPresence.supported ? 'Lyrics services' : _label;
  final IconData icon;
  final String _summary;

  /// One plain line. Without the sound engine (the web build) Playback has only Autoplay.
  String get summary => switch (this) {
    playback when !AudioEngine.supported => 'Autoplay',
    integrations when !DiscordPresence.supported => 'A Better Lyrics key for word-by-word lyrics',
    _ => _summary,
  };

  bool get available => switch (this) {
    advanced => AudioEngine.supported,
    library => Features.localLibrary,
    downloads => Features.downloads,
    history => Features.listeningHistory,
    account => Features.youtubeSignIn,
    spotify => Features.playlistImport,
    _ => true,
  };

  /// This section's own page, such as `settings:sound/playback`.
  String get location => Locations.settingsTopic('${group.id}/$id');
}

/// Where each page of settings sits, to draw the "Settings › Sound › Playback" trail.
class _Crumb {
  const _Crumb(this.label, this.page, this.location);
  final String label;
  final Widget page;
  final String location;
}

const _settingsCrumb = _Crumb('Settings', SettingsPage(), Locations.settings);

/// A row that opens another page of settings: icon, title, one plain line, chevron.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.summary,
    required this.onTap,
    this.leading,
  });

  final IconData icon;
  final String title;
  final String summary;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: leading ?? SizedBox.square(dimension: 36, child: Icon(icon)),
    title: Text(title),
    subtitle: Text(summary, style: settingsMuted(context)),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

/// The first page of settings: a handful of groups, then Beta features and About.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    return _SettingsFrame(
      title: 'Settings',
      child: SettingsCard(
        children: [
          for (final g in SettingsGroup.values)
            if (g.sections.isNotEmpty)
              _SettingsRow(
                icon: g.icon,
                title: g.label,
                summary: g.summary,
                onTap: () => shell.open(SettingsGroupPage(group: g), location: g.location),
              ),
          _SettingsRow(
            icon: Icons.science_outlined,
            title: 'Beta features',
            summary: 'Switch features that are still being tested on or off',
            onTap: () => shell.open(const SettingsBetaPage(), location: Locations.settingsTopic('beta')),
          ),
          if (hasKeyboardShortcuts)
            _SettingsRow(
              icon: Icons.keyboard_outlined,
              title: 'Keyboard shortcuts',
              summary: 'Play, skip, search and more without the mouse',
              onTap: () => showShortcutsDialog(context),
            ),
          _SettingsRow(
            icon: Icons.info_outline_rounded,
            title: 'About',
            summary: 'Version, what\'s new, reporting a problem, licences',
            onTap: () => shell.open(const SettingsAboutPage(), location: Locations.settingsTopic('about')),
          ),
        ],
      ),
    );
  }
}

/// Beta features: one page straight under Settings.
class SettingsBetaPage extends StatelessWidget {
  const SettingsBetaPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _SettingsFrame(title: 'Beta features', crumbs: [_settingsCrumb], child: BetaSettings());
}

/// About: one page straight under Settings.
class SettingsAboutPage extends StatelessWidget {
  const SettingsAboutPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _SettingsFrame(title: 'About', crumbs: [_settingsCrumb], child: AboutSettings());
}

/// One group: its sections as rows, each opening its page.
class SettingsGroupPage extends StatelessWidget {
  const SettingsGroupPage({super.key, required this.group});

  final SettingsGroup group;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.of(context);
    final shell = ShellScope.of(context);
    return _SettingsFrame(
      title: group.label,
      crumbs: const [_settingsCrumb],
      child: ListenableBuilder(
        listenable: Listenable.merge([c.ytMusic, BetaFeatures.instance]),
        builder: (context, _) => SettingsCard(
          children: [
            for (final s in group.sections)
              if (s == SettingsTopic.account)
                _SettingsRow(
                  icon: s.icon,
                  title: s.label,
                  summary: c.ytMusic.isSignedIn
                      ? 'Signed in as ${c.ytMusic.accountName ?? 'YouTube Music'}'
                      : s.summary,
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.hover,
                    foregroundImage: c.ytMusic.avatarUrl == null ? null : NetworkImage(c.ytMusic.avatarUrl!),
                    child: Icon(s.icon, color: AppColors.textSecondary, size: 20),
                  ),
                  onTap: () => shell.open(SettingsTopicPage(section: s), location: s.location),
                )
              else if (s == SettingsTopic.spotify)
                // Spotify has its own page (sign-in and import); this opens the same one as the Library tab.
                _SettingsRow(
                  icon: s.icon,
                  title: s.label,
                  summary: s.summary,
                  onTap: () => shell.open(const SpotifyPage(), location: Locations.spotify),
                )
              else
                _SettingsRow(
                  icon: s.icon,
                  title: s.label,
                  summary: s.summary,
                  onTap: () => shell.open(SettingsTopicPage(section: s), location: s.location),
                ),
          ],
        ),
      ),
    );
  }
}

/// One section of settings on its own page.
class SettingsTopicPage extends StatelessWidget {
  const SettingsTopicPage({super.key, required this.section});

  final SettingsTopic section;

  @override
  Widget build(BuildContext context) {
    final body = switch (section) {
      SettingsTopic.account => const _AccountSettings(),
      SettingsTopic.appearance => const AppearanceSettings(),
      SettingsTopic.layout => const LayoutSettings(),
      SettingsTopic.playback => const PlaybackSettings(),
      SettingsTopic.advanced => const AdvancedAudioSettings(),
      SettingsTopic.library => const LibrarySettings(),
      SettingsTopic.downloads => const DownloadSettings(),
      SettingsTopic.history => const PrivacySettings(),
      SettingsTopic.integrations => const _IntegrationsSettings(),
      // Opened from its row as the Spotify page itself, so this body is never shown.
      SettingsTopic.spotify => const SizedBox.shrink(),
    };
    return _SettingsFrame(
      title: section.label,
      crumbs: [
        _settingsCrumb,
        _Crumb(section.group.label, SettingsGroupPage(group: section.group), section.group.location),
      ],
      child: body,
    );
  }
}

class _AccountSettings extends StatelessWidget {
  const _AccountSettings();

  @override
  Widget build(BuildContext context) {
    final account = PlayerScope.of(context).ytMusic;
    final muted = settingsMuted(context);
    return ListenableBuilder(
      listenable: account,
      builder: (context, _) => SettingsCard(
        children: [
          // Stacks the button under the text on narrow windows.
          SettingTile(
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.hover,
              foregroundImage: account.avatarUrl == null ? null : NetworkImage(account.avatarUrl!),
              child: Icon(Icons.person_rounded, color: AppColors.textSecondary),
            ),
            title: Text(account.isSignedIn ? account.accountName ?? 'YouTube Music' : 'YouTube Music'),
            subtitle: Text(
              account.isSignedIn
                  ? 'Signed in. Your likes, playlists and followed artists are here.'
                  : 'Not signed in. Search and the public home work without an account.',
              style: muted,
            ),
            control: account.isSignedIn
                ? TextButton(onPressed: account.signOut, child: const Text('Disconnect'))
                : FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.inverse,
                      foregroundColor: AppColors.onInverse,
                    ),
                    onPressed: account.connecting ? null : () => signInToYoutubeMusic(context),
                    child: const Text('Sign in with Google'),
                  ),
          ),
          if (account.isSignedIn)
            SwitchListTile(
              title: const Text('Add songs you play to your YouTube Music history'),
              subtitle: Text('Like the official app, so YouTube Music keeps learning what you like.', style: muted),
              value: account.reportPlays,
              onChanged: account.setReportPlays,
            ),
        ],
      ),
    );
  }
}

class _IntegrationsSettings extends StatefulWidget {
  const _IntegrationsSettings();

  @override
  State<_IntegrationsSettings> createState() => _IntegrationsSettingsState();
}

class _IntegrationsSettingsState extends State<_IntegrationsSettings> {
  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.of(context);
    final muted = settingsMuted(context);
    return SettingsCard(
      children: [
        if (DiscordPresence.supported)
          SwitchListTile(
            secondary: const Icon(Icons.discord),
            title: const Text('Discord Rich Presence'),
            subtitle: Text('Show what you\'re listening to on your Discord profile', style: muted),
            value: c.discordEnabled,
            onChanged: c.setDiscordEnabled,
          ),
        ListTile(
          leading: const Icon(Icons.key_rounded),
          title: const Text('Better Lyrics API key'),
          subtitle: Text(
            LyricsService.betterLyricsKey == null
                ? 'Optional. Lets Better Lyrics find lyrics it hasn\'t saved yet, if you have a key.'
                : 'Added. Better Lyrics can find lyrics it hasn\'t saved yet.',
            style: muted,
          ),
          trailing: TextButton(
            onPressed: () async {
              await showDialog<void>(context: context, builder: (_) => const _BetterLyricsKeyDialog());
              if (mounted) setState(() {});
            },
            child: Text(LyricsService.betterLyricsKey == null ? 'Add' : 'Change'),
          ),
        ),
      ],
    );
  }
}

/// A settings page: on inner pages a "Settings › Sound › Playback" trail, then the heading and [child].
class _SettingsFrame extends StatelessWidget {
  const _SettingsFrame({required this.title, required this.child, this.crumbs = const []});

  final String title;
  final List<_Crumb> crumbs;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final text = Theme.of(context).textTheme;
    final pad = shell.compact ? 16.0 : 24.0;
    return PageScaffold(
      title: title,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 28),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (crumbs.isNotEmpty) _Breadcrumb(crumbs: crumbs, current: title),
                    Text(title, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 24),
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Settings › Sound › Playback": every crumb but the last opens that page.
class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.crumbs, required this.current});

  final List<_Crumb> crumbs;
  final String current;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700);
    final chevron = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textMuted),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        label: '${[for (final c in crumbs) c.label].join(', then ')}, then $current',
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final c in crumbs) ...[
              _CrumbLink(
                label: c.label,
                style: style,
                onTap: () => ShellScope.of(context).open(c.page, location: c.location),
              ),
              chevron,
            ],
            Text(
              current,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style?.copyWith(color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// A crumb that underlines on hover, like a link.
class _CrumbLink extends StatefulWidget {
  const _CrumbLink({required this.label, required this.style, required this.onTap});

  final String label;
  final TextStyle? style;
  final VoidCallback onTap;

  @override
  State<_CrumbLink> createState() => _CrumbLinkState();
}

class _CrumbLinkState extends State<_CrumbLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: Text(
        widget.label,
        style: widget.style?.copyWith(
          color: _hover ? AppColors.textPrimary : AppColors.textSecondary,
          decoration: _hover ? TextDecoration.underline : null,
          decorationColor: AppColors.textPrimary,
        ),
      ),
    ),
  );
}

/// Paste, check and save (or remove) a Better Lyrics API key.
class _BetterLyricsKeyDialog extends StatefulWidget {
  const _BetterLyricsKeyDialog();

  @override
  State<_BetterLyricsKeyDialog> createState() => _BetterLyricsKeyDialogState();
}

class _BetterLyricsKeyDialogState extends State<_BetterLyricsKeyDialog> {
  late final _key = TextEditingController(text: LyricsService.betterLyricsKey ?? '');
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _save(String? key) async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final ok = await LyricsService.setBetterLyricsKey(key);
      if (!mounted) return;
      if (ok) return Navigator.pop(context);
      setState(() => _error = 'Better Lyrics says this key isn\'t valid.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn\'t reach Better Lyrics to check the key. Try again.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Better Lyrics API key'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Without a key, lyrics from Better Lyrics still work for every song it has saved. '
            'Better Lyrics isn\'t giving out new keys right now.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _key,
            autofocus: true,
            obscureText: true,
            enabled: !_checking,
            decoration: InputDecoration(
              labelText: 'API key',
              border: const OutlineInputBorder(),
              isDense: true,
              errorText: _error,
              errorMaxLines: 2,
            ),
            onSubmitted: (v) => _save(v),
          ),
        ],
      ),
    ),
    actions: [
      if (LyricsService.betterLyricsKey != null)
        TextButton(onPressed: _checking ? null : () => _save(null), child: const Text('Remove')),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ListenableBuilder(
        listenable: _key,
        builder: (context, _) => FilledButton(
          onPressed: _checking || _key.text.trim().isEmpty ? null : () => _save(_key.text),
          child: Text(_checking ? 'Checking…' : 'Save'),
        ),
      ),
    ],
  );
}
