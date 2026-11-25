import 'dart:async';

import 'package:flutter/material.dart';

import '../../platform/features.dart';
import '../../platform/host.dart';
import '../widgets/discord_preview.dart';
import '../widgets/power_settings.dart';
import '../../services/beta_features.dart';
import '../../services/language.dart';
import '../../services/discord_presence.dart';
import '../../services/lyrics.dart';
import '../../services/player_controller.dart';
import '../../services/system_tray.dart';
import '../navigation.dart';
import '../shell_scope.dart';
import '../shortcuts.dart';
import '../theme.dart';
import '../widgets/page_scaffold.dart';
import '../../services/audio_engine.dart';
import '../../services/layout_prefs.dart';
import 'appearance_settings.dart';
import 'settings_index.dart';
import 'backup_settings.dart';
import 'storage_settings.dart';
import 'search/search_input.dart';
import 'about_settings.dart';
import 'listen_together_page.dart';
import 'layout_settings.dart';
import 'library_settings.dart';
import 'download_settings.dart';
import 'music_sources_settings.dart';
import 'privacy_settings.dart';
import 'scrobble_settings.dart';
import 'sound_settings.dart';
import 'spotify_page.dart';
import 'youtube_music_page.dart';
import '../widgets/app_dialog.dart';

/// The few groups on the first Settings page; each opens a page that lists its [SettingsTopic]s.
enum SettingsGroup {
  sound('sound', 'Sound', Icons.graphic_eq_rounded, 'Playback, sound effects (DSP), output and quality'),
  look('look', 'Look & feel', Icons.palette_outlined, 'Themes, colours, text size, what the screens show'),
  library(
    'library',
    'Library & downloads',
    Icons.library_music_outlined,
    'Music folders, downloads, listening history, backups',
  ),
  accounts(
    'accounts',
    'Accounts & services',
    Icons.manage_accounts_outlined,
    'YouTube Music, Spotify, Last.fm, Discord, lyrics, music sources',
  );

  const SettingsGroup(this.id, this._english, this.icon, this._englishSummary);
  final String id;
  // The English words, as a reading aid here; [label] and [summary] are in the language shown.
  // ignore: unused_field
  final String _english;
  final IconData icon;
  // ignore: unused_field
  final String _englishSummary;

  String get label => switch (this) {
    sound => tr.groupSound,
    look => tr.groupLook,
    library => tr.groupLibrary,
    accounts => tr.groupAccounts,
  };

  String get _summary => switch (this) {
    sound => tr.groupSoundSummary,
    look => tr.groupLookSummary,
    library => tr.groupLibrarySummary,
    accounts => tr.groupAccountsSummary,
  };

  /// One plain line; where this build leaves sections out (the web build), the names of those it shows.
  String get summary => sections.length == SettingsTopic.values.where((s) => s.group == this).length
      ? _summary
      : sections.map((s) => s.label).join(', ');

  String get location => Locations.settingsTopic(id);

  /// The sections shown on this group's page, in order, for what this device allows.
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
    'Autoplay and gapless playback',
  ),
  dsp(
    SettingsGroup.sound,
    'dsp',
    'Sound effects (DSP)',
    Icons.equalizer_rounded,
    'Equalizer, volume leveling, crossfade, spatial audio and room correction',
  ),
  advanced(
    SettingsGroup.sound,
    'hifi',
    'Output & quality',
    Icons.tune_rounded,
    'Output device, bit-perfect mode, sample rate',
  ),
  appearance(
    SettingsGroup.look,
    'appearance',
    'Theme & colours',
    Icons.palette_outlined,
    'Theme, mode, accent colour, cover colours, frosted glass',
  ),
  text(SettingsGroup.look, 'text', 'Language & text', Icons.translate_rounded, 'Language, text size, font'),
  nowPlaying(
    SettingsGroup.look,
    'now-playing',
    'Now Playing',
    Icons.play_circle_outline_rounded,
    'Cover, controls, progress bar, Liquid Glass, visualizer',
  ),
  lyrics(SettingsGroup.look, 'lyrics', 'Lyrics', Icons.lyrics_outlined, 'How lyrics look, and where they come from'),
  layout(
    SettingsGroup.look,
    'layout',
    'Pages & navigation',
    Icons.dashboard_customize_outlined,
    'Home, the bars, corners, spacing, cover size, motion',
  ),
  beta(SettingsGroup.look, 'beta', 'Beta features', Icons.science_outlined, 'Experimental features, off by default'),
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
  storage(SettingsGroup.library, 'storage', 'Storage & cache', Icons.storage, 'Offline cache sizes'),
  privacy(SettingsGroup.library, 'privacy', 'Privacy', Icons.privacy_tip_outlined, 'Search history on this device'),
  history(
    SettingsGroup.library,
    'history',
    'Listening history & Wrap',
    Icons.history_rounded,
    'The history behind your stats, kept on this device',
  ),
  backup(
    SettingsGroup.library,
    'backup',
    'Backup & restore',
    Icons.settings_backup_restore_rounded,
    'Your settings, playlists and history in one file',
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
  scrobbling(
    SettingsGroup.accounts,
    'scrobbling',
    'Last.fm & ListenBrainz',
    Icons.query_stats_rounded,
    'Add the songs you play to your profile there',
  ),
  integrations(SettingsGroup.accounts, 'services', 'Discord', Icons.discord, 'Show what you play on Discord'),
  sources(
    SettingsGroup.accounts,
    'sources',
    'Music sources',
    Icons.library_music_outlined,
    'SoundCloud, Monochrome and SpotiFLAC extensions: more places to search and play from',
  );

  const SettingsTopic(this.group, this.id, this._english, this.icon, this._englishSummary);
  final SettingsGroup group;
  final String id;
  // The English name, as a reading aid here; [label] is in the language shown.
  // ignore: unused_field
  final String _english;

  String get label => switch (this) {
    playback => tr.topicPlayback,
    dsp => tr.topicDsp,
    advanced => tr.topicOutput,
    appearance => tr.topicAppearance,
    text => tr.topicText,
    nowPlaying => tr.topicNowPlaying,
    lyrics => tr.topicLyrics,
    layout => tr.topicLayout,
    beta => tr.betaFeatures,
    library => tr.topicLibrary,
    downloads => tr.topicDownloads,
    storage => tr.storageCache,
    privacy => tr.privacySearch,
    history => tr.topicHistory,
    backup => tr.topicBackup,
    account => tr.topicAccount,
    spotify => tr.topicSpotify,
    scrobbling => tr.topicScrobbling,
    integrations => tr.topicIntegrations,
    sources => tr.topicSources,
  };
  final IconData icon;
  // ignore: unused_field
  final String _englishSummary;

  /// One plain line. Without the sound engine (the web build) Playback has only Autoplay.
  String get summary => switch (this) {
    playback when !AudioEngine.supported => tr.topicPlaybackSummaryWeb,
    playback => tr.topicPlaybackSummary,
    dsp => tr.topicDspSummary,
    advanced => tr.topicOutputSummary,
    appearance => tr.topicAppearanceSummary,
    text => tr.topicTextSummary,
    nowPlaying => tr.topicNowPlayingSummary,
    lyrics => tr.topicLyricsSummary,
    layout => tr.topicLayoutSummary,
    beta => tr.betaFeaturesSummary,
    library => tr.topicLibrarySummary,
    downloads => tr.topicDownloadsSummary,
    storage => tr.storageCacheHint,
    privacy => tr.clearSearches,
    history => tr.topicHistorySummary,
    backup => tr.topicBackupSummary,
    account => tr.topicAccountSummary,
    spotify => tr.topicSpotifySummary,
    scrobbling => tr.topicScrobblingSummary,
    integrations => tr.topicIntegrationsSummary,
    sources => tr.topicSourcesSummary,
  };

  bool get available => switch (this) {
    beta => Features.audioVisualizer,
    advanced => AudioEngine.supported,
    dsp => AudioEngine.supported || AudioEngine.webEffects,
    library => Features.localLibrary,
    storage => !Host.isWeb,
    downloads => Features.downloads,
    history => Features.listeningHistory,
    account => Features.youtubeSignIn,
    spotify => Features.playlistImport,
    scrobbling => Features.scrobbling,
    backup => Features.backup,
    integrations => DiscordPresence.supported,
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

_Crumb get _settingsCrumb => _Crumb(tr.navSettings, const SettingsPage(), Locations.settings);

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
    // Material 3: the destination's icon on a tonal circle.
    leading: leading ?? SettingsIcon(icon),
    title: Text(title),
    subtitle: Text(summary, style: settingsMuted(context)),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

/// The first page of settings: a search over every option, then a handful of groups, Listen together and About.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  static const searchKey = ValueKey('settings-search');

  /// The light over an option a search result opened.
  static const highlightKey = ValueKey('settings-highlight');

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SettingsFrame(
    title: tr.navSettings,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SearchField(controller: _query, onSubmitted: _openFirst),
        const SizedBox(height: 16),
        ListenableBuilder(
          listenable: _query,
          builder: (context, _) =>
              _query.text.trim().isEmpty ? const _SettingsGroups() : _SearchResults(query: _query.text),
        ),
      ],
    ),
  );

  void _openFirst(String query) {
    final first = searchSettings(query).firstOrNull;
    if (first != null) openSettingsOption(ShellScope.of(context), first);
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onSubmitted});

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // On glass: the glass's own haze and small corners, as the panels around it.
    final glass = AppColors.glass;
    final pill = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(glass ? 10 : 500)),
      borderSide: BorderSide.none,
    );
    // A Material 3 search bar, as on the Search page: 56 high, a tonal pill with no outline.
    return TextField(
      key: SettingsPage.searchKey,
      controller: controller,
      textInputAction: TextInputAction.search,
      onSubmitted: onSubmitted,
      style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
      decoration: InputDecoration(
        hintText: tr.searchSettings,
        hintStyle: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Icon(Icons.search_rounded, color: scheme.onSurface),
        ),
        suffixIcon: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => controller.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(tooltip: tr.clear, onPressed: controller.clear, icon: const Icon(Icons.close_rounded)),
        ),
        filled: true,
        fillColor: glass ? AppColors.tile : scheme.surfaceContainerHigh,
        hoverColor: scheme.onSurface.withValues(alpha: 0.08),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: pill,
        enabledBorder: pill,
        focusedBorder: pill,
      ),
    );
  }
}

/// The options matching [query], each opening its page at the option.
class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final found = searchSettings(query);
    if (found.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Text(tr.searchSettingsNone('“${query.trim()}”'), style: settingsMuted(context)),
      );
    }
    final shell = ShellScope.of(context);
    return SettingsCard(
      children: [
        for (final o in found.take(40))
          _SettingsRow(
            icon:
                o.place.topic?.icon ??
                (o.place == SettingsPlace.power ? Icons.battery_saver_outlined : Icons.info_outline_rounded),
            title: o.title(tr),
            summary: o.place.trail,
            onTap: () => openSettingsOption(shell, o),
          ),
      ],
    );
  }
}

/// The groups, Performance & power, Listen together, Keyboard shortcuts and About.
class _SettingsGroups extends StatelessWidget {
  const _SettingsGroups();

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    return SettingsCard(
      children: [
        for (final g in SettingsGroup.values)
          if (g.sections.isNotEmpty)
            _SettingsRow(
              icon: g.icon,
              title: g.label,
              summary: g.summary,
              onTap: () => shell.open(SettingsGroupPage(group: g), location: g.location),
            ),
        if (!Host.isWeb)
          _SettingsRow(
            icon: Icons.battery_saver_outlined,
            title: tr.settingsPower,
            summary: SystemTray.offered ? tr.settingsPowerSummaryTray : tr.settingsPowerSummary,
            onTap: () => shell.open(const SettingsPowerPage(), location: Locations.settingsTopic('power')),
          ),
        _SettingsRow(
          icon: Icons.group_outlined,
          title: tr.listenTogether,
          summary: tr.listenTogetherSummary,
          onTap: () => shell.open(const ListenTogetherPage(), location: Locations.listen),
        ),
        if (hasKeyboardShortcuts)
          _SettingsRow(
            icon: Icons.keyboard_outlined,
            title: tr.keyboardShortcuts,
            summary: tr.keyboardShortcutsSummary,
            onTap: () => showShortcutsDialog(context),
          ),
        _SettingsRow(
          icon: Icons.info_outline_rounded,
          title: tr.about,
          summary: tr.aboutSummary,
          onTap: () => shell.open(const SettingsAboutPage(), location: Locations.settingsTopic('about')),
        ),
      ],
    );
  }
}

/// Opens the page [option] is on, scrolled to it and lit up for a moment; a part hidden until its switch is on
/// shows that switch instead.
void openSettingsOption(ShellScope shell, SettingsOption option) {
  final open = _SettingsFrameState._live[option.place];
  if (open != null && open.mounted && (ModalRoute.isCurrentOf(open.context) ?? false)) {
    open._jumpTo(option);
    return;
  }
  _SettingsFrameState._pending = option;
  option.place.open(shell);
  // Taken by the page as it is built; never left for a page opened later some other way.
  WidgetsBinding.instance.addPostFrameCallback((_) => _SettingsFrameState._pending = null);
}

/// Power settings have their own destination, separate from sound processing.
class SettingsPowerPage extends StatelessWidget {
  const SettingsPowerPage({super.key});
  @override
  Widget build(BuildContext context) => _SettingsFrame(
    title: tr.settingsPower,
    crumbs: [_settingsCrumb],
    place: SettingsPlace.power,
    child: Column(
      children: [
        SettingsCard(children: PowerSettings.rows(context)),
        if (SystemTray.offered) ...[const SizedBox(height: 28), const CloseWindowSection()],
      ],
    ),
  );
}

/// About: one page straight under Settings.
class SettingsAboutPage extends StatelessWidget {
  const SettingsAboutPage({super.key});

  @override
  Widget build(BuildContext context) => _SettingsFrame(
    title: tr.about,
    crumbs: [_settingsCrumb],
    place: SettingsPlace.about,
    child: const AboutSettings(),
  );
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
      crumbs: [_settingsCrumb],
      child: ListenableBuilder(
        listenable: Listenable.merge([c.ytMusic, BetaFeatures.instance]),
        builder: (context, _) => SettingsCard(
          children: [
            for (final s in group.sections)
              if (s == SettingsTopic.account)
                _SettingsRow(
                  icon: s.icon,
                  title: s.label,
                  summary: c.ytMusic.isSignedIn ? tr.signedInAs(c.ytMusic.accountName ?? 'YouTube Music') : s.summary,
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.hover,
                    // Decoded at the avatar's size, not whatever resolution the account photo is served at.
                    foregroundImage: c.ytMusic.avatarUrl == null
                        ? null
                        : ResizeImage(NetworkImage(c.ytMusic.avatarUrl!), width: 72, allowUpscaling: false),
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
      SettingsTopic.text => const TextSettings(),
      SettingsTopic.nowPlaying => const NowPlayingSettings(),
      SettingsTopic.lyrics => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [LyricsSettings(), SizedBox(height: 22), _LyricsServices()],
      ),
      SettingsTopic.layout => const LayoutSettings(),
      SettingsTopic.beta => const BetaSettings(),
      SettingsTopic.playback => const PlaybackSettings(),
      SettingsTopic.dsp => const DspSettings(),
      SettingsTopic.advanced => const AdvancedAudioSettings(),
      SettingsTopic.library => const LibrarySettings(),
      SettingsTopic.storage => const StorageSettings(),
      SettingsTopic.downloads => const DownloadSettings(),
      SettingsTopic.privacy => SettingsCard(
        children: [
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(tr.clearSearches),
            onTap: () async {
              if (!await confirmDialog(
                context,
                title: tr.clearSearches,
                body: tr.clearSearchesBody,
                confirmLabel: tr.clear,
                destructive: true,
              )) {
                return;
              }
              await RecentSearches.clear();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.historyCleared)));
              }
            },
          ),
        ],
      ),
      SettingsTopic.history => const PrivacySettings(),
      SettingsTopic.backup => const BackupSettings(),
      SettingsTopic.integrations => const _IntegrationsSettings(),
      SettingsTopic.scrobbling => const ScrobbleSettings(),
      SettingsTopic.sources => const MusicSourcesSettings(),
      // Opened from its row as the Spotify page itself, so this body is never shown.
      SettingsTopic.spotify => const SizedBox.shrink(),
    };
    return _SettingsFrame(
      title: section.label,
      crumbs: [
        _settingsCrumb,
        _Crumb(section.group.label, SettingsGroupPage(group: section.group), section.group.location),
      ],
      place: SettingsPlace.values.where((p) => p.topic == section).firstOrNull,
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
              foregroundImage: account.avatarUrl == null
                  ? null
                  : ResizeImage(NetworkImage(account.avatarUrl!), width: 80, allowUpscaling: false),
              child: Icon(Icons.person_rounded, color: AppColors.textSecondary),
            ),
            title: Text(account.isSignedIn ? account.accountName ?? 'YouTube Music' : 'YouTube Music'),
            subtitle: Text(account.isSignedIn ? tr.ytSignedInBody : tr.ytSignedOutBody, style: muted),
            control: account.isSignedIn
                ? TextButton(onPressed: account.signOut, child: Text(tr.disconnect))
                : FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.inverse,
                      foregroundColor: AppColors.onInverse,
                    ),
                    onPressed: account.connecting ? null : () => signInToYoutubeMusic(context),
                    child: Text(tr.signInWithGoogle),
                  ),
          ),
          if (account.isSignedIn)
            SwitchListTile(
              title: Text(tr.addToYtHistory),
              subtitle: Text(tr.addToYtHistorySubtitle, style: muted),
              value: account.reportPlays,
              onChanged: account.setReportPlays,
            ),
        ],
      ),
    );
  }
}

/// Discord: the switch, then what it shows and a preview of the profile card.
class _IntegrationsSettings extends StatelessWidget {
  const _IntegrationsSettings();

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.of(context);
    return SettingsCard(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.discord),
          title: Text(tr.discordRichPresence),
          subtitle: Text(tr.discordRichPresenceSubtitle, style: settingsMuted(context)),
          value: c.discordEnabled,
          onChanged: c.setDiscordEnabled,
        ),
        if (c.discordEnabled) const DiscordPresenceSettings(),
      ],
    );
  }
}

/// Where lyrics come from: Musixmatch, and a Better Lyrics key for word-by-word lyrics.
class _LyricsServices extends StatefulWidget {
  const _LyricsServices();

  @override
  State<_LyricsServices> createState() => _LyricsServicesState();
}

class _LyricsServicesState extends State<_LyricsServices> {
  @override
  Widget build(BuildContext context) {
    final muted = settingsMuted(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(tr.topicLyricsServices, style: settingsHeading(context)),
        ),
        SettingsCard(
          children: [
            SwitchListTile(
              title: Text(tr.musixmatchLyrics),
              subtitle: Text(tr.musixmatchLyricsSubtitle),
              value: BetaFeatures.instance.isOn(BetaFeature.musixmatch),
              onChanged: (value) async {
                await BetaFeatures.instance.set(BetaFeature.musixmatch, value);
                if (mounted) setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.key_rounded),
              title: Text(tr.betterLyricsKey),
              subtitle: Text(
                LyricsService.betterLyricsKey == null ? tr.betterLyricsKeyOptional : tr.betterLyricsKeyAdded,
                style: muted,
              ),
              trailing: TextButton(
                onPressed: () async {
                  await showDialog<void>(context: context, builder: (_) => const _BetterLyricsKeyDialog());
                  if (mounted) setState(() {});
                },
                child: Text(LyricsService.betterLyricsKey == null ? tr.add : tr.change),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A settings page: on inner pages a "Settings › Sound › Playback" trail, then the heading and [child].
///
/// On a page of options ([place]) it finds an option again by the words its row shows ([SettingsOption.marker]):
/// to scroll to it and light it up after a search.
class _SettingsFrame extends StatefulWidget {
  const _SettingsFrame({required this.title, required this.child, this.crumbs = const [], this.place});

  final String title;
  final List<_Crumb> crumbs;
  final Widget child;
  final SettingsPlace? place;

  @override
  State<_SettingsFrame> createState() => _SettingsFrameState();
}

class _SettingsFrameState extends State<_SettingsFrame> with SingleTickerProviderStateMixin {
  /// The page of each place that is open, for a search result on the page shown.
  static final _live = <SettingsPlace, _SettingsFrameState>{};

  /// The option a search result opens; its page takes it as it is built.
  static SettingsOption? _pending;

  final _content = GlobalKey();

  /// The lit row, while it fades.
  Rect? _flashRect;
  late final _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  Timer? _flashOff;

  @override
  void initState() {
    super.initState();
    final place = widget.place;
    if (place == null) return;
    _live[place] = this;
    final pending = _pending;
    if (pending != null && pending.place == place) {
      _pending = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _whenSettled(() => _jumpTo(pending)));
    }
  }

  @override
  void dispose() {
    if (identical(_live[widget.place], this)) _live.remove(widget.place);
    _flashOff?.cancel();
    _flash.dispose();
    super.dispose();
  }

  /// After the page has slid in: rows found before then can still move.
  void _whenSettled(VoidCallback then) {
    if (!mounted) return;
    final anim = ModalRoute.of(context)?.animation;
    if (anim == null || anim.status != AnimationStatus.forward) return then();
    void done(AnimationStatus s) {
      if (s == AnimationStatus.forward) return;
      anim.removeStatusListener(done);
      if (mounted) then();
    }

    anim.addStatusListener(done);
  }

  /// The rows marked by [markers], found in one walk: the [ListTile] around the words, or the words themselves
  /// (a section's heading).
  Map<String, Element> _locate(Set<String> markers) {
    final root = _content.currentContext as Element?;
    final found = <String, Element>{};
    if (root == null || markers.isEmpty) return found;
    final loose = <String, Element>{};
    void visit(Element e) {
      final w = e.widget;
      if (w is Text && markers.contains(w.data) && !found.containsKey(w.data)) {
        Element? tile;
        e.visitAncestorElements((a) {
          if (a.widget is ListTile) tile = a;
          return tile == null && !identical(a, root);
        });
        if (tile != null) {
          found[w.data!] = tile!;
        } else {
          loose.putIfAbsent(w.data!, () => e);
        }
      }
      e.visitChildren(visit);
    }

    root.visitChildren(visit);
    return {...loose, ...found};
  }

  /// [e]'s box within the page's content.
  Rect? _rectOf(Element e) {
    final box = e.renderObject, page = _content.currentContext?.findRenderObject();
    if (box is! RenderBox || page is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero, ancestor: page) & box.size;
  }

  /// Scrolls to [option] (or the switch that shows it) and lights it up.
  void _jumpTo(SettingsOption option) {
    SettingsOption? target = option;
    Element? row;
    while (target != null) {
      row = _locate({target.marker})[target.marker];
      if (row != null) break;
      target = target.parent == null ? null : SettingsOptions.byId(target.parent!);
    }
    if (row == null || target == null) return;
    Scrollable.ensureVisible(row, alignment: 0.3, duration: LayoutPrefs.dur(const Duration(milliseconds: 300)));
    final rect = _rectOf(row);
    if (rect == null) return;
    setState(() => _flashRect = rect);
    _flashOff?.cancel();
    if (LayoutPrefs.moves) {
      _flash.forward(from: 0).whenComplete(() {
        if (mounted) setState(() => _flashRect = null);
      });
    } else {
      // Without motion: lit, then not, with no frames in between.
      _flash.value = 0;
      _flashOff = Timer(_flash.duration!, () {
        if (mounted) setState(() => _flashRect = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final text = Theme.of(context).textTheme;
    final pad = shell.compact ? 16.0 : 24.0;
    final colors = AppColors.of(context);
    return PageScaffold(
      title: widget.title,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 28),
            child: Align(
              alignment: AlignmentDirectional.topStart,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Stack(
                  key: _content,
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.crumbs.isNotEmpty) _Breadcrumb(crumbs: widget.crumbs, current: widget.title),
                        Text(widget.title, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 24),
                        widget.child,
                      ],
                    ),
                    if (_flashRect case final r?)
                      Positioned.fromRect(
                        rect: r,
                        child: IgnorePointer(
                          key: SettingsPage.highlightKey,
                          child: FadeTransition(
                            opacity: ReverseAnimation(CurvedAnimation(parent: _flash, curve: Curves.easeInCubic)),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.accent.withValues(alpha: 0.16),
                                border: Border.all(color: colors.accent, width: 2),
                                borderRadius: LayoutPrefs.corner(12),
                              ),
                            ),
                          ),
                        ),
                      ),
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
        label: tr.crumbsThen([for (final c in crumbs) c.label].join(tr.crumbsJoin), current),
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
      setState(() => _error = tr.betterLyricsKeyInvalid);
    } catch (_) {
      if (mounted) setState(() => _error = tr.betterLyricsUnreachable);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: Text(tr.betterLyricsKey),
    width: DialogWidth.regular,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr.betterLyricsKeyBody,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _key,
          autofocus: true,
          obscureText: true,
          enabled: !_checking,
          decoration: InputDecoration(
            labelText: tr.apiKey,
            border: const OutlineInputBorder(),
            isDense: true,
            errorText: _error,
            errorMaxLines: 2,
          ),
          onSubmitted: (v) => _save(v),
        ),
      ],
    ),
    actions: [
      if (LyricsService.betterLyricsKey != null)
        TextButton(onPressed: _checking ? null : () => _save(null), child: Text(tr.remove)),
      TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.cancel)),
      ListenableBuilder(
        listenable: _key,
        builder: (context, _) => FilledButton(
          onPressed: _checking || _key.text.trim().isEmpty ? null : () => _save(_key.text),
          child: Text(_checking ? tr.checking : tr.save),
        ),
      ),
    ],
  );
}
