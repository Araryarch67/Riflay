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
  String get groupSoundSummary => 'Playback, sound effects (DSP), output and quality';

  @override
  String get groupLook => 'Look & feel';

  @override
  String get groupLookSummary => 'Themes, colours, text size, what the screens show';

  @override
  String get groupLibrary => 'Library & downloads';

  @override
  String get groupLibrarySummary => 'Music folders, downloads, listening history, backups';

  @override
  String get groupAccounts => 'Accounts & services';

  @override
  String get groupAccountsSummary => 'YouTube Music, Spotify, Last.fm, Discord, lyrics, extensions';

  @override
  String get topicPlayback => 'Playback';

  @override
  String get topicPlaybackSummary => 'Autoplay and gapless playback';

  @override
  String get topicDsp => 'Sound effects (DSP)';

  @override
  String get topicDspSummary => 'Equalizer, volume leveling, crossfade, spatial audio and room correction';

  @override
  String get topicOutput => 'Output & quality';

  @override
  String get topicOutputSummary => 'Output device, bit-perfect mode, sample rate';

  @override
  String get topicAppearance => 'Appearance';

  @override
  String get topicAppearanceSummary => 'Theme, accent colour, background, text size, font';

  @override
  String get topicLayout => 'Layout';

  @override
  String get topicLayoutSummary => 'Shapes, sizes, what the player shows';

  @override
  String get topicLibrary => 'Library';

  @override
  String get topicLibrarySummary => 'Keep music folders up to date, find songs you have twice';

  @override
  String get topicDownloads => 'Downloads';

  @override
  String get topicDownloadsSummary => 'Format, quality, where songs are saved';

  @override
  String get topicHistory => 'Listening history & Wrap';

  @override
  String get topicHistorySummary => 'The history behind your stats, kept on this device';

  @override
  String get topicBackup => 'Backup & restore';

  @override
  String get topicBackupSummary => 'Your settings, playlists and history in one file';

  @override
  String get topicAccount => 'YouTube Music account';

  @override
  String get topicAccountSummary => 'Sign in with Google';

  @override
  String get topicSpotify => 'Spotify';

  @override
  String get topicSpotifySummary => 'Bring your playlists, Liked Songs and albums over';

  @override
  String get topicScrobbling => 'Last.fm & ListenBrainz';

  @override
  String get topicScrobblingSummary => 'Add the songs you play to your profile there';

  @override
  String get topicIntegrations => 'Discord & lyrics services';

  @override
  String get topicIntegrationsSummary => 'Show what you play on Discord, lyrics services';

  @override
  String get topicExtensions => 'Extensions';

  @override
  String get topicExtensionsSummary => 'SpotiFLAC extension repositories: more places to search';

  @override
  String get topicLyricsServices => 'Lyrics services';

  @override
  String get topicPlaybackSummaryWeb => 'Autoplay';

  @override
  String get topicIntegrationsSummaryWeb => 'A Better Lyrics key for word-by-word lyrics';

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
  String get saveToDevice => 'Save to device';

  @override
  String savingToDevice(Object title) {
    return '$title is downloading in your browser';
  }

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
  String get stopsAfterOneMore => 'The music stops after this song and one more';

  @override
  String stopsAfterMore(int count) {
    return 'The music stops after this song and $count more';
  }

  @override
  String get settingsPowerSummaryTray => 'Screen timeout, sleep, background playback and closing to the tray';

  @override
  String get settingsPowerSummary => 'Screen timeout, sleep and background playback';

  @override
  String get listenTogetherSummary => 'Host a session or join friends and manage sharing permissions';

  @override
  String get keyboardShortcutsSummary => 'Play, skip, search and more without the mouse';

  @override
  String get aboutSummary => 'Version, what\'s new, reporting a problem, licences';

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
  String get tempoPitchOff => 'Off while bit-perfect mode is on or listening together';

  @override
  String get greetingNight => 'Good night';

  @override
  String get greetingMorning => 'Good morning';

  @override
  String get greetingAfternoon => 'Good afternoon';

  @override
  String get greetingEvening => 'Good evening';

  @override
  String get allSongs => 'All Songs';

  @override
  String get likedMusic => 'Liked music';

  @override
  String get recentlyPlayed => 'Recently played';

  @override
  String get yourPlaylists => 'Your playlists';

  @override
  String get yourAlbums => 'Your albums';

  @override
  String get yourArtists => 'Your artists';

  @override
  String get artists => 'Artists';

  @override
  String get artist => 'Artist';

  @override
  String get albums => 'Albums';

  @override
  String get album => 'Album';

  @override
  String get playlists => 'Playlists';

  @override
  String get playlist => 'Playlist';

  @override
  String get smartPlaylist => 'Smart playlist';

  @override
  String get recentlyAdded => 'Recently added';

  @override
  String get refresh => 'Refresh';

  @override
  String get addMusicOffline => 'Add music from this device to play it offline.';

  @override
  String get addSongs => 'Add songs';

  @override
  String get addFolder => 'Add a folder';

  @override
  String get addMusic => 'Add music';

  @override
  String get addFiles => 'Add files';

  @override
  String get add => 'Add';

  @override
  String get importFromYouTube => 'Import from YouTube';

  @override
  String get fromYouTube => 'From YouTube';

  @override
  String get noMusicYet => 'No music yet';

  @override
  String get noMusicYetBody =>
      'Add audio files from this device. Albums, artists and cover art come from the files\' tags.';

  @override
  String get newPlaylist => 'New playlist';

  @override
  String get newPlaylistSubtitle => 'Mix your own songs and YouTube Music';

  @override
  String get yourListeningStats => 'Your listening stats';

  @override
  String get yourListeningStatsSubtitle => 'Top songs, artists and albums';

  @override
  String get yourYouTubeMusic => 'Your YouTube Music';

  @override
  String get yourYouTubeMusicBody => 'Sign in to see your liked songs and playlists here.';

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get musicOnDevice => 'Music on this device';

  @override
  String get musicOnDeviceBody => 'Add audio files to play them offline.';

  @override
  String get joinSharedPlaylist => 'Join a shared playlist';

  @override
  String get importPlaylist => 'Import a playlist';

  @override
  String get spotifyLibrary => 'Spotify library';

  @override
  String get libraryEmpty => 'Add songs or a playlist to start your library.';

  @override
  String get all => 'All';

  @override
  String get songs => 'Songs';

  @override
  String get videos => 'Videos';

  @override
  String get searchIntro =>
      'Searches your own music and all of YouTube Music together. Songs with a cloud stream online; the rest play offline.';

  @override
  String get browseArtists => 'Browse artists';

  @override
  String get inYourLibrary => 'In your library';

  @override
  String get searchHint => 'What do you want to play?';

  @override
  String get clear => 'Clear';

  @override
  String get recentSearches => 'Recent searches';

  @override
  String get remove => 'Remove';

  @override
  String get clearFinished => 'Clear finished';

  @override
  String get nothingDownloading =>
      'Nothing downloading. Paste a YouTube video or playlist link to add its audio to your library.';

  @override
  String downloadsUse(Object size) {
    return 'Downloads use $size';
  }

  @override
  String get missingFiles => 'Missing files';

  @override
  String get downloadAllAgain => 'Download all again';

  @override
  String get removeAllFromLibrary => 'Remove all from library';

  @override
  String get missingFilesBody => 'These songs are in your library, but their files aren\'t on this device any more.';

  @override
  String get downloadAgain => 'Download again';

  @override
  String get waiting => 'Waiting…';

  @override
  String get preparing => 'Preparing…';

  @override
  String bytesOf(Object received, Object total) {
    return '$received of $total';
  }

  @override
  String get addedToLibrary => 'Added to library';

  @override
  String get failed => 'Failed';

  @override
  String get cancelled => 'Cancelled';

  @override
  String get cancel => 'Cancel';

  @override
  String get retry => 'Retry';

  @override
  String downloadingCount(int count) {
    return 'Downloading $count';
  }

  @override
  String get saveAsPlaylist => 'Save as playlist';

  @override
  String get queueEmpty => 'Nothing playing yet. Pick an album, artist or song to fill the queue.';

  @override
  String get nowPlaying => 'Now playing';

  @override
  String get nowPlayingTitle => 'Now Playing';

  @override
  String get nextUp => 'Next up';

  @override
  String nextFrom(Object source) {
    return 'Next from: $source';
  }

  @override
  String get autoplay => 'Autoplay';

  @override
  String get autoplaySubtitle => 'When the queue ends, keep playing similar songs from YouTube Music';

  @override
  String get autoplaySimilar => 'Autoplay: similar to what you\'re playing';

  @override
  String get removeFromQueue => 'Remove from queue';

  @override
  String get dragToMove => 'Drag to move';

  @override
  String get shufflePlay => 'Shuffle play';

  @override
  String get addAllToPlaylist => 'Add all to playlist';

  @override
  String get select => 'Select';

  @override
  String get unselect => 'Unselect';

  @override
  String get selectAll => 'Select all';

  @override
  String get cancelSelection => 'Cancel selection';

  @override
  String selectedCount(int count) {
    return '$count selected';
  }

  @override
  String playlistOnRiflay(int count) {
    return 'Riflay • $count songs';
  }

  @override
  String playlistOnYoutubeMusic(int count) {
    return 'YouTube Music • $count songs';
  }

  @override
  String addedTo(String name) {
    return 'Added to $name';
  }

  @override
  String addedSongsTo(int count, String name) {
    return 'Added $count songs to $name';
  }

  @override
  String alreadyIn(String name) {
    return 'Already in $name';
  }

  @override
  String get notOnYoutubeMusic => 'This song isn\'t on YouTube Music';

  @override
  String get noneOnYoutubeMusic => 'None of these songs are on YouTube Music';

  @override
  String skippedNotOnYoutubeMusic(int count) {
    return '$count not on YouTube Music, skipped';
  }

  @override
  String get addAllToQueue => 'Add all to queue';

  @override
  String get downloadAllOffline => 'Download all for offline';

  @override
  String get alreadyDownloaded => 'Already downloaded';

  @override
  String downloadingSongs(int count) {
    return 'Downloading $count songs…';
  }

  @override
  String disc(Object number) {
    return 'Disc $number';
  }

  @override
  String removedFrom(Object playlist) {
    return 'Removed from $playlist';
  }

  @override
  String get undo => 'Undo';

  @override
  String get title => 'Title';

  @override
  String get editPlaylist => 'Edit playlist';

  @override
  String get rename => 'Rename';

  @override
  String get convertAllToFlac => 'Convert all to FLAC';

  @override
  String get deletePlaylistQuestion => 'Delete playlist?';

  @override
  String get deletePlaylist => 'Delete playlist';

  @override
  String get close => 'Close';

  @override
  String get playingFromCaps => 'PLAYING FROM';

  @override
  String get yourLibrarySource => 'Your library';

  @override
  String get yourLibraryInline => 'your library';

  @override
  String playingFrom(Object source) {
    return 'Playing from $source';
  }

  @override
  String get nothingPlaying => 'Nothing playing';

  @override
  String get quieter => 'Quieter';

  @override
  String get louder => 'Louder';

  @override
  String get linkCopied => 'Link copied';

  @override
  String get songNameCopied => 'Song name copied';

  @override
  String sleepTimerWith(Object time) {
    return 'Sleep timer: $time';
  }

  @override
  String get volume => 'Volume';

  @override
  String get speaker => 'Speaker';

  @override
  String get expandedPlayer => 'Expanded player';

  @override
  String get closeExpandedPlayer => 'Close expanded player';

  @override
  String get hideLyrics => 'Hide lyrics';

  @override
  String get nowPlayingView => 'Now playing view';

  @override
  String get hideNowPlayingView => 'Hide now playing view';

  @override
  String get moreOptions => 'More options';

  @override
  String get miniPlayer => 'Mini player';

  @override
  String get fullScreen => 'Full screen';

  @override
  String get exitFullScreen => 'Exit full screen';

  @override
  String get sidePanelEmpty => 'Play something and it will show up here.';

  @override
  String get nextInQueue => 'Next in queue';

  @override
  String get openQueue => 'Open queue';

  @override
  String get nothingAfterThisSong => 'Nothing after this song';

  @override
  String get lyricsLoadFailed => 'Couldn\'t load lyrics. Check your internet connection.';

  @override
  String get tryAgain => 'Try again';

  @override
  String get lyricsInstrumental => 'This song is instrumental. Enjoy the music.';

  @override
  String get noLyricsFound => 'No lyrics found for this song.';

  @override
  String get useMyLyricsFile => 'Use my lyrics file';

  @override
  String get loadingLyrics => 'Loading lyrics';

  @override
  String lyricsFrom(Object source) {
    return 'Lyrics from $source';
  }

  @override
  String get lyricsUntimed => 'These lyrics don\'t follow the song.';

  @override
  String get back => 'Back';

  @override
  String get playToSeeLyrics => 'Play a song to see its lyrics here.';

  @override
  String get directUsbFailed => 'Direct USB couldn\'t run, so songs play through Android. Turn it on to try again.';

  @override
  String get directUsbClosedWhileStarting =>
      'Direct USB was turned off because Riflay closed while starting it. Turn it on to try again.';

  @override
  String get directUsbBeta => 'Direct USB (beta)';

  @override
  String get directUsbBetaSubtitle =>
      'Offers Direct USB below: Riflay plays straight to your USB DAC, past Android. Experimental.';

  @override
  String get directUsbWarningTitle => 'Turn on Direct USB?';

  @override
  String get directUsbWarningBody =>
      'Direct USB is experimental. It may freeze or close Riflay, and it may not work with every phone or DAC. Your DAC can get the sound at full volume, so turn your DAC\'s volume down and take your earphones out before you play. Turning it off goes back to normal output.';

  @override
  String get directUsbWarningConfirm => 'Turn on';

  @override
  String get linkNotYoutube => 'There\'s no YouTube link in what was shared.';

  @override
  String get linkOpening => 'Opening the link…';

  @override
  String get linkFailed => 'Couldn\'t open that link. It may be private, removed or region-locked.';

  @override
  String get streakTitle => 'Listening streak';

  @override
  String streakDays(int count) {
    return '$count-day streak';
  }

  @override
  String streakTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Listening streak: $count days',
      one: 'Listening streak: 1 day',
    );
    return '$_temp0';
  }

  @override
  String get streakSafe => 'You\'ve listened today. See you tomorrow!';

  @override
  String get streakKeepGoing => 'Play a song today to keep your streak';

  @override
  String get streakStart => 'Play a song to start a streak';

  @override
  String streakLongest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Longest: $count days',
      one: 'Longest: 1 day',
    );
    return '$_temp0';
  }

  @override
  String streakToNext(int count, Object flame) {
    return '$count more days to the $flame';
  }

  @override
  String get streakTop => 'The highest flame there is';

  @override
  String get flameRed => 'red flame';

  @override
  String get flameGold => 'gold flame';

  @override
  String get flameBlue => 'blue flame';

  @override
  String get flamePurple => 'purple flame';

  @override
  String get flameRainbow => 'rainbow flame';

  @override
  String get streakRule =>
      'A day counts once you play a song for 30 seconds or more. Your history stays on this device.';
}
