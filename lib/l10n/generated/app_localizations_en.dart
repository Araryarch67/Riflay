// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get language => 'Language';

  @override
  String get languageSubtitle => 'The language of Riflay\'s screens';

  @override
  String get languageSystem => 'Device language';

  @override
  String get navHome => 'Home';

  @override
  String get navLibrary => 'Library';

  @override
  String get navSearch => 'Search';

  @override
  String get navDownloads => 'Downloads';

  @override
  String get navSettings => 'Settings';

  @override
  String get yourLibrary => 'Your Library';

  @override
  String get more => 'More';

  @override
  String get groupSound => 'Sound';

  @override
  String get groupSoundSummary =>
      'Playback, sound effects (DSP), output and quality';

  @override
  String get groupLook => 'Look & feel';

  @override
  String get groupLookSummary =>
      'Themes, colours, text size, what the screens show';

  @override
  String get groupLibrary => 'Library & downloads';

  @override
  String get groupLibrarySummary =>
      'Music folders, downloads, listening history, backups';

  @override
  String get groupAccounts => 'Accounts & services';

  @override
  String get groupAccountsSummary =>
      'YouTube Music, Spotify, Last.fm, Discord, lyrics, extensions';

  @override
  String get topicPlayback => 'Playback';

  @override
  String get topicPlaybackSummary => 'Autoplay and gapless playback';

  @override
  String get topicDsp => 'Sound effects (DSP)';

  @override
  String get topicDspSummary =>
      'Equalizer, volume leveling, crossfade, spatial audio and room correction';

  @override
  String get topicOutput => 'Output & quality';

  @override
  String get topicOutputSummary =>
      'Output device, bit-perfect mode, sample rate';

  @override
  String get topicAppearance => 'Appearance';

  @override
  String get topicAppearanceSummary =>
      'Theme, accent colour, background, text size, font';

  @override
  String get topicLayout => 'Layout';

  @override
  String get topicLayoutSummary => 'Shapes, sizes, what the player shows';

  @override
  String get topicLibrary => 'Library';

  @override
  String get topicLibrarySummary =>
      'Keep music folders up to date, find songs you have twice';

  @override
  String get topicDownloads => 'Downloads';

  @override
  String get topicDownloadsSummary => 'Format, quality, where songs are saved';

  @override
  String get topicHistory => 'Listening history & Wrap';

  @override
  String get topicHistorySummary =>
      'The history behind your stats, kept on this device';

  @override
  String get topicBackup => 'Backup & restore';

  @override
  String get topicBackupSummary =>
      'Your settings, playlists and history in one file';

  @override
  String get topicAccount => 'YouTube Music account';

  @override
  String get topicAccountSummary => 'Sign in with Google';

  @override
  String get topicSpotify => 'Spotify';

  @override
  String get topicSpotifySummary =>
      'Bring your playlists, Liked Songs and albums over';

  @override
  String get topicScrobbling => 'Last.fm & ListenBrainz';

  @override
  String get topicScrobblingSummary =>
      'Add the songs you play to your profile there';

  @override
  String get topicIntegrations => 'Discord & lyrics services';

  @override
  String get topicIntegrationsSummary =>
      'Show what you play on Discord, lyrics services';

  @override
  String get topicExtensions => 'Extensions';

  @override
  String get topicExtensionsSummary =>
      'SpotiFLAC extension repositories: more places to search';

  @override
  String get topicLyricsServices => 'Lyrics services';

  @override
  String get topicPlaybackSummaryWeb => 'Autoplay';

  @override
  String get topicIntegrationsSummaryWeb =>
      'A Better Lyrics key for word-by-word lyrics';

  @override
  String get settingsPower => 'Power & background';

  @override
  String get listenTogether => 'Listen together';

  @override
  String get keyboardShortcuts => 'Keyboard shortcuts';

  @override
  String get about => 'About';

  @override
  String get sectionPlayer => 'Player';

  @override
  String get queue => 'Queue';

  @override
  String get lyrics => 'Lyrics';

  @override
  String get closePlayer => 'Close player';

  @override
  String get sectionSong => 'Song';

  @override
  String get share => 'Share';

  @override
  String get addToPlaylist => 'Add to playlist';

  @override
  String get downloaded => 'Downloaded';

  @override
  String get stopDownload => 'Stop download';

  @override
  String get download => 'Download';

  @override
  String get playsOffline => 'Plays offline';

  @override
  String get downloading => 'Downloading…';

  @override
  String get sectionListen => 'Listen';

  @override
  String get sleepTimer => 'Sleep timer';

  @override
  String get playOnDevice => 'Play on a device';

  @override
  String playingOn(Object device) {
    return 'Playing on $device';
  }

  @override
  String get sectionSound => 'Sound';

  @override
  String get equalizer => 'Equalizer';

  @override
  String get signalPath => 'Signal path';

  @override
  String get detailStats => 'Detail stats';

  @override
  String get hideDetailStats => 'Hide detail stats';

  @override
  String get playNext => 'Play next';

  @override
  String get addToQueue => 'Add to queue';

  @override
  String get goToArtist => 'Go to artist';

  @override
  String get goToAlbum => 'Go to album';

  @override
  String get removeFromThisPlaylist => 'Remove from this playlist';

  @override
  String get addToLiked => 'Add to Liked music';

  @override
  String get removeFromLiked => 'Remove from Liked music';

  @override
  String get startRadio => 'Start radio';

  @override
  String get downloadForOffline => 'Download for offline';

  @override
  String get downloadAs => 'Download as…';

  @override
  String get edit => 'Edit';

  @override
  String get editInfo => 'Edit info';

  @override
  String get removeFromLibrary => 'Remove from library';

  @override
  String get deleteDownload => 'Delete download';

  @override
  String get deleteDownloadQuestion => 'Delete this download?';

  @override
  String deleteDownloadBody(String title) {
    return '$title is removed from your library and its file is deleted from this device.';
  }

  @override
  String get delete => 'Delete';

  @override
  String get downloadDeleted => 'Download deleted';

  @override
  String get convertToFlac => 'Convert to FLAC';

  @override
  String get toastPlaysNext => 'Plays next';

  @override
  String get toastAddedToQueue => 'Added to queue';

  @override
  String get toastRequestedNext => 'Requested next song';

  @override
  String get play => 'Play';

  @override
  String get pause => 'Pause';

  @override
  String get previous => 'Previous';

  @override
  String get next => 'Next';

  @override
  String get enableShuffle => 'Enable shuffle';

  @override
  String get disableShuffle => 'Disable shuffle';

  @override
  String get enableRepeat => 'Enable repeat';

  @override
  String get enableRepeatOne => 'Enable repeat one';

  @override
  String get disableRepeat => 'Disable repeat';

  @override
  String get mute => 'Mute';

  @override
  String get unmute => 'Unmute';

  @override
  String get sleepTimerFades => 'The music fades out, then stops';

  @override
  String get afterAWhile => 'After a while';

  @override
  String get afterSongs => 'After songs';

  @override
  String minutesCount(int count) {
    return '$count minutes';
  }

  @override
  String songsCount(int count) {
    return '$count songs';
  }

  @override
  String get endOfThisSong => 'End of this song';

  @override
  String get customTime => 'Custom time';

  @override
  String get add10Minutes => 'Add 10 minutes';

  @override
  String get cancelTimer => 'Cancel timer';

  @override
  String stopsIn(Object time) {
    return 'The music stops in $time';
  }

  @override
  String get stopsWhenSongEnds => 'The music stops when this song ends';

  @override
  String get stopsAfterOneMore =>
      'The music stops after this song and one more';

  @override
  String stopsAfterMore(int count) {
    return 'The music stops after this song and $count more';
  }

  @override
  String get settingsPowerSummaryTray =>
      'Screen timeout, sleep, background playback and closing to the tray';

  @override
  String get settingsPowerSummary =>
      'Screen timeout, sleep and background playback';

  @override
  String get listenTogetherSummary =>
      'Host a session or join friends and manage sharing permissions';

  @override
  String get keyboardShortcutsSummary =>
      'Play, skip, search and more without the mouse';

  @override
  String get aboutSummary =>
      'Version, what\'s new, reporting a problem, licences';

  @override
  String addToHostQueue(Object host) {
    return 'Add to $host\'s queue';
  }

  @override
  String get theHost => 'the host';

  @override
  String goToNamedArtist(Object artist) {
    return 'Go to $artist';
  }

  @override
  String get aboutTheArtist => 'About the artist';

  @override
  String get follow => 'Follow';

  @override
  String get following => 'Following';

  @override
  String get showMore => 'Show more';

  @override
  String get showLess => 'Show less';

  @override
  String get tempoPitch => 'Tempo & pitch';

  @override
  String get tempo => 'Tempo';

  @override
  String get pitch => 'Pitch';

  @override
  String semitones(int count) {
    return '$count semitones';
  }

  @override
  String get reset => 'Reset';

  @override
  String get asRecorded => 'As recorded';

  @override
  String get tempoPitchOff =>
      'Off while bit-perfect mode is on or listening together';
}
