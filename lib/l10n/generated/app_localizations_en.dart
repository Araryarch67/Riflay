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
  String searchIntro(String source) {
    return 'Searches your own music and $source together. Songs with a service icon stream online; the rest play offline.';
  }

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
  String get watchVideo => 'Watch full screen';

  @override
  String get showLyrics => 'Show lyrics';

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

  @override
  String songsLeft(int count) {
    return '$count songs left';
  }

  @override
  String get songEndShort => 'Song end';

  @override
  String get endOfSong => 'End of song';

  @override
  String get hours => 'Hours';

  @override
  String get minutes => 'Minutes';

  @override
  String get start => 'Start';

  @override
  String get thisPhone => 'This phone';

  @override
  String get thisComputer => 'This computer';

  @override
  String get playOn => 'Play on';

  @override
  String get lookingForDevices => 'Looking for TVs and speakers…';

  @override
  String get noDevicesFound => 'No TVs or speakers found. They need to be on and on the same Wi-Fi.';

  @override
  String get castWorksWith => 'Works with TVs, speakers and receivers that support DLNA or AirPlay.';

  @override
  String get searchAgain => 'Search again';

  @override
  String get discordSongCover => 'Song cover';

  @override
  String get discordTime => 'Time played and left';

  @override
  String get discordSongInList => 'Song title in the member list';

  @override
  String get discordListenButton => '\"Listen on YouTube Music\" button';

  @override
  String get discordWhilePaused => 'Keep showing while paused';

  @override
  String get discordShowQuality => 'Show the sound quality (FLAC 24/96, Opus 160 kbps)';

  @override
  String get shareLyrics => 'Share lyrics';

  @override
  String lyricCardPick(int count) {
    return 'Pick up to $count lines for the card';
  }

  @override
  String lyricCardCaption(String lines, String title, String artist) {
    return '“$lines” — $title by $artist, on Riflay';
  }

  @override
  String videoQualityLower(String height) {
    return 'Resolution adjusted to your network ($height)';
  }

  @override
  String videoQualityHigher(String height) {
    return 'Back up to $height: your network keeps up';
  }

  @override
  String get showBluetoothCodec => 'Show the Bluetooth codec';

  @override
  String get previewYourSong => 'Your song';

  @override
  String get previewItsArtist => 'Its artist';

  @override
  String get discordListeningTo => 'Listening to';

  @override
  String get paused => 'Paused';

  @override
  String get playerPresets => 'Player presets';

  @override
  String get presetsCustomMix => 'Your settings are a custom mix';

  @override
  String presetsMatch(String preset) {
    return 'Your settings match $preset';
  }

  @override
  String applyPresetQuestion(String preset) {
    return 'Apply $preset?';
  }

  @override
  String applyPresetBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'This changes $count player settings. You can still change each one after.',
      one: 'This changes 1 player setting. You can still change each one after.',
    );
    return '$_temp0';
  }

  @override
  String get apply => 'Apply';

  @override
  String get inUse => 'In use';

  @override
  String get tapToApply => 'Tap to apply';

  @override
  String get autoplayKeepGoing => 'When the queue ends, keep going with similar songs';

  @override
  String get gaplessPlayback => 'Gapless playback';

  @override
  String get gaplessPlaybackSubtitle => 'No added silence between tracks. Crossfade is under Sound effects (DSP).';

  @override
  String get skipSilence => 'Skip silence';

  @override
  String get offWhileBitPerfect => 'Off while bit-perfect mode is on';

  @override
  String get skipSilenceSubtitle => 'Silent intros, outros and gaps are cut short. Soft passages play whole';

  @override
  String get off => 'Off';

  @override
  String get volumeLeveling => 'Volume leveling';

  @override
  String get volumeLevelingSubtitle => 'Plays songs at a similar loudness, using their ReplayGain tags';

  @override
  String get measureLoudness => 'Measure songs without ReplayGain tags';

  @override
  String measureLoudnessSubtitle(int measured, int total) {
    return '$measured of $total songs on this device measured. A song without tags is leveled by what is measured';
  }

  @override
  String measuringLoudness(int done, int total) {
    return 'Measuring $done of $total…';
  }

  @override
  String get measure => 'Measure';

  @override
  String get crossfade => 'Crossfade';

  @override
  String get crossfadeSubtitle =>
      'The end of a song fades into the start of the next. Off in bit-perfect and exclusive modes';

  @override
  String get fadeLength => 'Fade length';

  @override
  String get skipForAlbums => 'Skip for albums';

  @override
  String get skipForAlbumsSubtitle =>
      'Songs that follow each other on an album play without a fade, as the artist made them';

  @override
  String get virtualSpeakers => 'Virtual speakers';

  @override
  String get offWhileMono => 'Off while Mono audio is on';

  @override
  String get virtualSpeakersSubtitle =>
      'For headphones: the music plays in front of you, like from two speakers, instead of inside your head';

  @override
  String get virtualSpeakerLevel => 'Virtual speaker level';

  @override
  String get virtualSpeakerLevelBody => 'Adjust the simulation output level to match your other listening modes.';

  @override
  String get headphoneCrossfeed => 'Headphone crossfeed';

  @override
  String get crossfeedNotNeeded => 'Not needed with Virtual speakers: they already do this';

  @override
  String get crossfeedSubtitle => 'Makes headphones sound more like speakers in a room';

  @override
  String get crossfeedSoundstage => 'Crossfeed soundstage';

  @override
  String get crossfeedSoundstageBody =>
      'Adjust the frequency range blended between the left and right channels. Default: 50%.';

  @override
  String get monoAudio => 'Mono audio';

  @override
  String get monoAudioSubtitle => 'Both sides as one sound. Handy when one side of your headphones doesn\'t work';

  @override
  String get audioPlugins => 'Audio plugins';

  @override
  String get audioPluginsSubtitle =>
      'VST, LV2 and CLAP plugins, set up in Carla: add them there and save, and they play here';

  @override
  String get editInCarla => 'Edit in Carla';

  @override
  String get needsCarlaDownload =>
      'Needs Carla, a free program that holds your VST, LV2 and CLAP plugins. Download it, unzip it in your Downloads or Program Files folder, then reopen this page.';

  @override
  String get needsCarlaInstall =>
      'Needs Carla, a free program that holds your VST, LV2 and CLAP plugins. Install it, then reopen this page.';

  @override
  String get installCarla => 'Install Carla';

  @override
  String get roomCorrection => 'Room correction';

  @override
  String get roomCorrectionSubtitle =>
      'Load an impulse response (WAV or FLAC, e.g. made with REW) to correct your room or headphones';

  @override
  String get chooseFile => 'Choose file';

  @override
  String get change => 'Change';

  @override
  String get roomCorrectionHeadroom => 'Room correction headroom';

  @override
  String get roomCorrectionHeadroomBody => 'Lower the corrected signal if the impulse response makes peaks too loud.';

  @override
  String get signalPathSubtitle => 'See which effects are actually active for the current song';

  @override
  String resetNamed(String name) {
    return 'Reset $name';
  }

  @override
  String get chooseImpulse => 'Choose an impulse response';

  @override
  String get couldntUseFile => 'Couldn\'t use that file';

  @override
  String get output => 'Output';

  @override
  String get iosOutputNote =>
      'A USB DAC follows each song\'s sample rate; the speaker and Bluetooth keep one rate. iOS always mixes the sound, so it can\'t be bit-perfect here.';

  @override
  String get outputDevice => 'Output device';

  @override
  String get directDevicesNote =>
      'Devices marked \"direct\" skip the system mixer: bit-perfect, but other apps go quiet';

  @override
  String get phonesOwnOutput => 'Your phone\'s own output';

  @override
  String usbDacNamed(String name) {
    return '$name (USB DAC)';
  }

  @override
  String get bitPerfectMode => 'Bit-perfect mode';

  @override
  String get needsAndroid14 => 'Needs Android 14 or later';

  @override
  String androidFormatsUnplayable(String dac, int bitPerfect, int total) {
    return 'Android offers $dac only in formats Riflay can\'t play bit-perfect ($bitPerfect of $total formats). Riflay still plays through your DAC, with Android mixing the sound first.';
  }

  @override
  String phoneNoBitPerfect(String dac, int count) {
    return 'This phone doesn\'t offer bit-perfect output for $dac: its maker leaves it out (Android lists $count formats for it, none bit-perfect). Riflay still plays through your DAC, with Android mixing the sound first.';
  }

  @override
  String get plugInDacForBitPerfect => 'Plug in a USB DAC to play bit-perfect';

  @override
  String get bitPerfectAndroid =>
      'Sends the file to your USB DAC untouched: no equalizer, leveling or resampling. Other apps and system sounds are muted on the DAC, and the phone\'s volume keys stop working: use your DAC\'s volume, since lowering Riflay\'s own volume changes the sound.';

  @override
  String get bitPerfectMac =>
      'No equalizer, leveling or resampling in Riflay, and your DAC follows each song\'s sample rate. Volume still works; at 100% nothing is changed. Other apps keep playing, so macOS still mixes the sound: turn on Exclusive mode too to send the file to your DAC untouched.';

  @override
  String get bitPerfectWindows =>
      'No equalizer, leveling or resampling in Riflay. Volume still works; at 100% nothing is changed. Other apps keep playing, so Windows still mixes the sound: turn on Exclusive mode too to send the file to your DAC untouched.';

  @override
  String get bitPerfectLinux =>
      'Sends the file to your DAC untouched: no equalizer, leveling or resampling. Volume still works; at 100% nothing is changed. Takes over your DAC so the system mixer can\'t resample. Meanwhile other apps play through another output.';

  @override
  String get nativeDsd => 'Native DSD (DoP)';

  @override
  String get nativeDsdSubtitle =>
      'Sends DSD files to your DAC as DSD instead of converting them. Only for DACs that support DoP: others play a faint hiss, so turn it off then. The volume stays at 100% for DSD songs; use your DAC\'s.';

  @override
  String get needsBitPerfectAndDac => 'Needs Bit-perfect mode and a USB DAC that takes 176.4 kHz or higher';

  @override
  String get needsBitPerfectAndExclusive => 'Needs Bit-perfect mode and Exclusive mode';

  @override
  String get needsBitPerfect => 'Needs Bit-perfect mode';

  @override
  String get exclusiveMode => 'Exclusive mode';

  @override
  String get exclusiveMac =>
      'Takes over the device so macOS can\'t mix or resample: the DAC switches to each song\'s sample rate. Other apps go silent while Riflay plays.';

  @override
  String get exclusiveWindows =>
      'Takes over the device so Windows\' mixer can\'t resample: the DAC switches to each song\'s sample rate. Other apps go silent while Riflay plays, and Windows\' volume mixer can\'t control it.';

  @override
  String get outputSampleRate => 'Output sample rate';

  @override
  String get followsEachSong => 'Follows each song while bit-perfect mode is on';

  @override
  String get followOrConvert => 'Follow the song, or convert everything to one rate';

  @override
  String get followTheSong => 'Follow the song';

  @override
  String get hqResampler => 'High-quality resampler';

  @override
  String get hqResamplerSubtitle => 'SoX-grade conversion whenever the rate has to change (slightly more CPU)';

  @override
  String get buffer => 'Buffer';

  @override
  String get bufferSubtitle => 'Raise it if you hear crackles or dropouts';

  @override
  String get signalPathSubtitleExact => 'See exactly what happens to the song you\'re playing';

  @override
  String get directUsbIntro =>
      'Riflay talks to your USB DAC itself, past Android, so songs reach it untouched even on phones where Bit-perfect mode can\'t. Experimental.';

  @override
  String get directUsbPlugIn => 'On. Plug in a USB DAC.';

  @override
  String directUsbAllow(String dac) {
    return 'On. Allow Riflay to use $dac.';
  }

  @override
  String directUsbBitPerfectTo(String dac) {
    return 'Bit-perfect to $dac';
  }

  @override
  String directUsbFallback(String format, String dac) {
    return 'This song$format is in a format $dac doesn\'t take, so it plays through Android.';
  }

  @override
  String directUsbOnWith(String dac) {
    return 'On, with $dac. Play a song.';
  }

  @override
  String get allowUsbAccess => 'Allow USB access';

  @override
  String problemWith(String error) {
    return 'Problem: $error';
  }

  @override
  String directUsbPipe(String state, String output) {
    return 'Pipe: $state · Output: $output';
  }

  @override
  String get pipeOpen => 'open';

  @override
  String get pipeClosed => 'closed';

  @override
  String fromThePlayer(String format) {
    return 'From the player: $format';
  }

  @override
  String directUsbRoute(String route) {
    return 'Route: $route';
  }

  @override
  String dropouts(String count) {
    return 'Dropouts: $count';
  }

  @override
  String get directUsb => 'Direct USB';

  @override
  String get styleClassic => 'Classic';

  @override
  String get styleCompact => 'Compact';

  @override
  String get styleMinimal => 'Minimal';

  @override
  String get vizWave => 'Wave';

  @override
  String get vizBars => 'Bars';

  @override
  String get vizLine => 'Line';

  @override
  String get vizDots => 'Dots';

  @override
  String get vizMirror => 'Mirror';

  @override
  String get vizTwinWaves => 'Twin waves';

  @override
  String get vizPulse => 'Pulse';

  @override
  String get vizOrbit => 'Orbit';

  @override
  String get vizPetals => 'Petals';

  @override
  String get vizPeaks => 'Peaks';

  @override
  String get shapeFlower => 'Flower';

  @override
  String get shapeSquare => 'Square';

  @override
  String get shapeRounded => 'Rounded';

  @override
  String get shapeExtraRound => 'Extra round';

  @override
  String get densityComfortable => 'Comfortable';

  @override
  String get sizeSmall => 'Small';

  @override
  String get sizeMedium => 'Medium';

  @override
  String get sizeLarge => 'Large';

  @override
  String get motionFull => 'Full';

  @override
  String get motionReduced => 'Reduced';

  @override
  String get decoderAuto => 'Automatic';

  @override
  String get decoderGpu => 'Graphics card';

  @override
  String get decoderCpu => 'Processor';

  @override
  String get decoderAutoNote => 'The graphics card when it is known to work, else the processor';

  @override
  String get decoderGpuNote => 'Always try the graphics card first. Lightest, if your drivers cope';

  @override
  String get decoderCpuNote => 'Never the graphics card. Uses more power; try it if videos look wrong';

  @override
  String get perfLight => 'Lightweight';

  @override
  String get perfBalanced => 'Balanced';

  @override
  String get perfHeavy => 'Heavy';

  @override
  String get perfLightNote => 'Fewest effects. Best for older computers and battery.';

  @override
  String get perfBalancedNote => 'Smooth animations with sensible limits.';

  @override
  String get perfHeavyNote => 'Every effect at full speed. Uses more power.';

  @override
  String get styleThin => 'Thin';

  @override
  String get styleThick => 'Thick';

  @override
  String get shapeStraight => 'Straight';

  @override
  String get shapeWavy => 'Wavy';

  @override
  String get shapePill => 'Pill';

  @override
  String get shapeThinLine => 'Thin line';

  @override
  String get shapeWaveform => 'Waveform';

  @override
  String get shapeCircle => 'Circle';

  @override
  String get shapeRoundedSquare => 'Rounded square';

  @override
  String get sizeNormal => 'Normal';

  @override
  String get coverBackground => 'Background';

  @override
  String get headerCentred => 'Centred';

  @override
  String get headerPlayingFrom => 'Playing from';

  @override
  String get styleBoxed => 'Boxed';

  @override
  String get stylePlain => 'Plain';

  @override
  String get styleChips => 'Chips';

  @override
  String get styleIcons => 'Icons';

  @override
  String get styleBottomCard => 'Bottom card';

  @override
  String get styleTopHeader => 'Top header';

  @override
  String get styleFloatingPill => 'Floating pill';

  @override
  String get styleHero => 'Hero';

  @override
  String get badgeUnderArtist => 'Under the artist';

  @override
  String get badgeTimeRow => 'In the time row';

  @override
  String get styleHighlightedCard => 'Highlighted card';

  @override
  String get sizeLargest => 'Largest';

  @override
  String get lyricsFocused => 'Focused';

  @override
  String get lyricsWordByWord => 'Word by word';

  @override
  String get lyricsLineByLine => 'Line by line';

  @override
  String get alignLeft => 'Left';

  @override
  String get alignCentre => 'Centre';

  @override
  String get styleMaterial => 'Material';

  @override
  String get styleUnderline => 'Underline';

  @override
  String get styleTextOnly => 'Text only';

  @override
  String get styleFloating => 'Floating';

  @override
  String get styleCapsule => 'Capsule';

  @override
  String get styleDock => 'Dock';

  @override
  String get styleCentreButton => 'Centre button';

  @override
  String get styleLiquidGlass => 'Liquid glass';

  @override
  String get quickPicks => 'Quick picks';

  @override
  String get fromYoutubeMusic => 'From YouTube Music';

  @override
  String get presets => 'Presets';

  @override
  String get custom => 'Custom';

  @override
  String matchesPreset(String preset) {
    return 'Matches $preset';
  }

  @override
  String get fullScreenPlayerHint => 'The full-screen player';

  @override
  String get cover => 'Cover';

  @override
  String get coverSubtitle =>
      'Square or flower frame the cover. Background has no frame: it fills the top and fades into the page';

  @override
  String get coverSizeOnPhones => 'Cover size on phones';

  @override
  String get coverSizeOnPhonesSubtitle => 'Large reaches nearly the edges of the screen';

  @override
  String get topOfPlayer => 'Top of the player';

  @override
  String get topOfPlayerSubtitle => 'What the top shows beside the close arrow, or above the song on desktop';

  @override
  String get buttonsByTitle => 'Buttons by the title';

  @override
  String get buttonsByTitleSubtitle =>
      'Like and More as they are, a joined Share and heart pair, or plain icons. The song menu stays on desktop';

  @override
  String get showSoundQuality => 'Show sound quality';

  @override
  String get showSoundQualitySubtitle => 'The small label under the song title, such as FLAC or Hi-Res';

  @override
  String get songVideoSwitch => 'Song / Video switch';

  @override
  String get songVideoSwitchSubtitle =>
      'At the top of Now Playing. Adaptive shows it only when the song has a music video';

  @override
  String get adaptive => 'Adaptive';

  @override
  String get qualityBadge => 'Quality badge';

  @override
  String get qualityBadgeSubtitle =>
      'Where FLAC or Opus 130 kbps sits on the phone player: under the artist, or between the two times';

  @override
  String get background => 'Background';

  @override
  String get backgroundSubtitle => 'What fills the page behind the player. Cover: Background replaces it';

  @override
  String get videoMode => 'Video mode';

  @override
  String get videoModeSubtitle => 'Watch music videos in sync with the song';

  @override
  String get videoDecoding => 'Video decoding';

  @override
  String decoderNow(String decoder) {
    return 'Now: $decoder';
  }

  @override
  String get decoderNowCpu => 'the processor';

  @override
  String decoderNowGpu(String hwdec) {
    return 'graphics card ($hwdec)';
  }

  @override
  String get playbackControls => 'Playback controls';

  @override
  String get playbackControlsHint => 'The progress bar, the buttons and the row under them';

  @override
  String get progressBarShape => 'Progress bar shape';

  @override
  String get progressBar => 'Progress bar';

  @override
  String get progressBarSubtitle => 'How thick the bar you drag to skip around is';

  @override
  String get showTimeLeft => 'Show time left';

  @override
  String get showTimeLeftSubtitle => 'The right time counts down instead of showing the total, also on the desktop bar';

  @override
  String get controls => 'Controls';

  @override
  String get controlsSubtitle =>
      'Previous, play and next as circles, a wide Play pill, or plain big icons, also on the desktop bar';

  @override
  String get playButton => 'Play button';

  @override
  String get playButtonSubtitle => 'The shape of the big play and pause button';

  @override
  String get volumeSlider => 'Volume slider';

  @override
  String get volumeSliderSubtitle =>
      'At the very bottom of the phone player. Off, it opens from the speaker button (Icons) or the desktop bar button';

  @override
  String get sliderLook => 'Slider look';

  @override
  String get sliderLookSubtitle =>
      'Every slider: volume, the equalizer and settings. Classic, a thin line, or a thick pill with a bar handle';

  @override
  String get bottomButtons => 'Bottom buttons';

  @override
  String get bottomButtonsSubtitle =>
      'Lyrics and Queue; a joined row of icon buttons; or Lyrics, a speaker and person capsule and Queue. Icons only, Lyrics is always there';

  @override
  String get lyricsHint => 'The lyrics page, and the lyrics beside the cover on desktop';

  @override
  String get lyricsPage => 'Lyrics page';

  @override
  String get lyricsPageSubtitle =>
      'Where the player sits on the lyrics page. Desktop gets a song card on top or at the bottom';

  @override
  String get linesShown => 'Lines shown';

  @override
  String get linesShownSubtitle =>
      'All keeps the whole song in view. Focused shows only the previous, the current and the next line';

  @override
  String get sync => 'Sync';

  @override
  String get syncSubtitle =>
      'Word by word fills each word as it is sung, where the lyrics have word timings. Line by line lights the whole line';

  @override
  String get textSize => 'Text size';

  @override
  String get lyricsTextSizeSubtitle => 'How big the lyrics are';

  @override
  String get alignment => 'Alignment';

  @override
  String get alignmentSubtitle => 'Lines start at the left edge, or sit in the middle';

  @override
  String get dimUnsung => 'Dim lines not yet sung';

  @override
  String get dimUnsungSubtitle => 'Only the line being sung and the ones before it stay bright';

  @override
  String get highlightLyricLine => 'Highlight the line being sung';

  @override
  String get highlightLyricLineSubtitle => 'A faint pane of dark frosted glass behind the whole line';

  @override
  String get lockScreenLyrics => 'Lyrics on the lock screen';

  @override
  String get lockScreenLyricsSubtitle =>
      'The line being sung takes the artist\'s place in the notification, on the lock screen and on a car\'s display. With Pronunciation on in the lyrics, a line in another script shows how it\'s read too';

  @override
  String get visualizer => 'Visualizer';

  @override
  String get visualizerHint => 'Shapes that move with the music';

  @override
  String get pages => 'Pages';

  @override
  String get pagesHint => 'Album, playlist and artist pages, song lists and Home';

  @override
  String get albumPlaylistTop => 'Album and playlist top';

  @override
  String get albumPlaylistTopSubtitle =>
      'Hero: a big cover fading behind the title, round buttons around a Play pill. Also on artist pages';

  @override
  String get songThatIsPlaying => 'Song that is playing';

  @override
  String get songThatIsPlayingSubtitle => 'In a list of songs: coloured text, or a filled rounded card with the bars';

  @override
  String get bars => 'Bars';

  @override
  String get barsHint => 'The mini player and the bars that hold the controls';

  @override
  String get miniPlayerSubtitle =>
      'The bar above the tabs when a song plays, on phones. Floating pill has a flower cover and round buttons';

  @override
  String get tabBarOnPhones => 'Tab bar on phones';

  @override
  String get tabBarOnPhonesSubtitle => 'Classic sits at the bottom edge; Floating and Liquid glass hover above it';

  @override
  String get desktopPlayerBar => 'Desktop player bar';

  @override
  String get desktopPlayerBarSubtitle =>
      'Along the window\'s foot: full-width controls, a compact row beside the song, or a minimal strip';

  @override
  String get shapesAndMotion => 'Shapes and motion';

  @override
  String get motionOffLightweight => 'Performance is set to Lightweight, so the motion settings stay off.';

  @override
  String get corners => 'Corners';

  @override
  String get cornersSubtitle => 'Covers, cards, menus, dialogs and the mini player';

  @override
  String get spacing => 'Spacing';

  @override
  String get spacingSubtitle => 'Compact fits more songs and cards on screen';

  @override
  String get coverSizeInGrids => 'Cover size in grids';

  @override
  String get coverSizeInGridsSubtitle => 'The albums and playlists on Home and in \"Show all\"';

  @override
  String get transitionStyle => 'Transition style';

  @override
  String get transitionStyleSubtitle => 'Coordinated page, tab and player transitions';

  @override
  String get transitionSpeed => 'Transition speed';

  @override
  String get transitionSpeedSubtitle => 'Choose a brisk or more relaxed pace';

  @override
  String get animations => 'Animations';

  @override
  String get animationsSubtitle =>
      'Reduced keeps quick fades only. Full follows your system when it asks for less motion';

  @override
  String get window => 'Window';

  @override
  String get desktopOnly => 'Desktop only';

  @override
  String get windowButtons => 'Window buttons';

  @override
  String get windowButtonsSubtitle =>
      'Minimize, maximize and close in the title bar. Turn off with a tiling window manager';

  @override
  String get resetLayout => 'Reset layout to default';

  @override
  String get dragToReorderSections => 'Drag the handle to put sections in a different order';

  @override
  String get audioVisualizer => 'Audio visualizer';

  @override
  String get audioVisualizerSubtitle => 'Shapes that move with the music around the cover and under it';

  @override
  String get visualizerStyle => 'Visualizer style';

  @override
  String get visualizerStyleBackground =>
      'A strip under the song. Pulse, Orbit and Petals ring the cover: pick Square or Flower for them';

  @override
  String get visualizerStyleRings => 'Rings the cover';

  @override
  String get visualizerStyleEdge => 'Moves along the cover\'s edge, with a strip under the song';

  @override
  String get radiusMovement => 'Radius movement';

  @override
  String radiusMovementSubtitle(String percent) {
    return '$percent% · How far the shape expands with the music';
  }

  @override
  String get lineThickness => 'Line thickness';

  @override
  String signedInAs(String name) {
    return 'Signed in as $name';
  }

  @override
  String get ytSignedInBody => 'Signed in. Your likes, playlists and followed artists are here.';

  @override
  String get ytSignedOutBody => 'Not signed in. Search and the public home work without an account.';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get addToYtHistory => 'Add songs you play to your YouTube Music history';

  @override
  String get addToYtHistorySubtitle => 'Like the official app, so YouTube Music keeps learning what you like.';

  @override
  String get musixmatchLyrics => 'Musixmatch lyrics';

  @override
  String get musixmatchLyricsSubtitle => 'Find word-by-word lyrics when other sources have none';

  @override
  String get discordRichPresence => 'Discord Rich Presence';

  @override
  String get discordRichPresenceSubtitle => 'Show what you\'re listening to on your Discord profile';

  @override
  String get betterLyricsKey => 'Better Lyrics API key';

  @override
  String get betterLyricsKeyOptional =>
      'Optional. Lets Better Lyrics find lyrics it hasn\'t saved yet, if you have a key.';

  @override
  String get betterLyricsKeyAdded => 'Added. Better Lyrics can find lyrics it hasn\'t saved yet.';

  @override
  String crumbsThen(String crumbs, String current) {
    return '$crumbs, then $current';
  }

  @override
  String get crumbsJoin => ', then ';

  @override
  String get betterLyricsKeyInvalid => 'Better Lyrics says this key isn\'t valid.';

  @override
  String get betterLyricsUnreachable => 'Couldn\'t reach Better Lyrics to check the key. Try again.';

  @override
  String get betterLyricsKeyBody =>
      'Without a key, lyrics from Better Lyrics still work for every song it has saved. Better Lyrics isn\'t giving out new keys right now.';

  @override
  String get apiKey => 'API key';

  @override
  String get checking => 'Checking…';

  @override
  String get save => 'Save';

  @override
  String get statsNothingPlaying => 'Nothing is playing.';

  @override
  String get statsOtherDevice => 'Playing on another device: the stats come from the device playing.';

  @override
  String get waitingForAudio => 'Waiting for audio…';

  @override
  String get statsCopied => 'Stats copied';

  @override
  String get copyStats => 'Copy stats';

  @override
  String get statsHint => 'Updates every second. Copy them to paste into a bug report.';

  @override
  String get themeLegacy => 'Legacy';

  @override
  String get themeDefault => 'Default';

  @override
  String get themeMonochrome => 'Monochrome';

  @override
  String get modeDark => 'Dark';

  @override
  String get modeLight => 'Light';

  @override
  String get modeBlack => 'Black';

  @override
  String get modeSystem => 'Match system';

  @override
  String get accentTheme => 'Theme';

  @override
  String get accentTeal => 'Teal';

  @override
  String get accentGreen => 'Green';

  @override
  String get accentBlue => 'Blue';

  @override
  String get accentViolet => 'Violet';

  @override
  String get accentPink => 'Pink';

  @override
  String get accentOrange => 'Orange';

  @override
  String get accentWhite => 'White';

  @override
  String get customEllipsis => 'Custom…';

  @override
  String get coverColorPlayer => 'Player only';

  @override
  String get coverColorApp => 'Whole app';

  @override
  String get npBgSimple => 'Simple';

  @override
  String get npBgBlurredCover => 'Blurred cover';

  @override
  String get npBgMusicVideo => 'Music video';

  @override
  String get npBgMusicVideoHint => 'The song\'s music video, when it has one';

  @override
  String get theme => 'Theme';

  @override
  String get matugenColors => 'Matugen colors';

  @override
  String get matugenChoose => 'Choose a generated JSON file. Colors update automatically.';

  @override
  String get matugenFollowing => 'Following generated colors automatically';

  @override
  String get matugenFind => 'Find generated colors automatically';

  @override
  String get coloursFromCover => 'Colours come from the cover of what\'s playing';

  @override
  String get backgroundColour => 'Background colour';

  @override
  String get backgroundColourSubtitle => 'Panels, cards and menus are worked out from it';

  @override
  String get textColour => 'Text colour';

  @override
  String get textColourAuto => 'Chosen to suit the background';

  @override
  String get textColourAdjusted => 'Lightened or darkened where it would be hard to read';

  @override
  String get automatic => 'Automatic';

  @override
  String get mode => 'Mode';

  @override
  String get modeSubtitle => 'Light or dark, for every theme';

  @override
  String get accentColour => 'Accent colour';

  @override
  String get coloursFromCoverArt => 'Colours from cover art';

  @override
  String get coverColorOffNote => 'Colours stay as the theme has them';

  @override
  String get coverColorPlayerNote => 'Tint the player and pages with the colour of what\'s playing';

  @override
  String get coverColorAppNote => 'The whole app takes the colour of what\'s playing';

  @override
  String get colourStrength => 'Colour strength';

  @override
  String get colourStrengthSubtitle => 'How much of the cover\'s colour shows in backgrounds and panels';

  @override
  String get strengthSubtle => 'Subtle';

  @override
  String get strengthStrong => 'Strong';

  @override
  String get highContrast => 'High contrast';

  @override
  String get highContrastSubtitle => 'Brighter text and clearer edges, easier to read';

  @override
  String textSizeSubtitle(int size) {
    return 'Body text, in pixels; titles and labels grow with it. $size px is the default';
  }

  @override
  String get font => 'Font';

  @override
  String get openFontsFolder => 'Open the fonts folder (put .ttf or .otf files here)';

  @override
  String get nowPlayingBackground => 'Now playing background';

  @override
  String get nowPlayingBackgroundSubtitle => 'Only the Now Playing and expanded player pages';

  @override
  String get frostedGlass => 'Frosted glass';

  @override
  String get frostedGlassSubtitle => 'See-through, blurred mini player and tab bar. Uses a little more GPU';

  @override
  String get blurStrength => 'Blur strength';

  @override
  String get componentOpacity => 'Component opacity';

  @override
  String get componentOpacitySubtitle =>
      'See-through backgrounds with the desktop blurred behind them. Text, covers and controls stay solid';

  @override
  String get backgroundOpacity => 'Background opacity';

  @override
  String get backgroundOpacityAndroid => 'Below 100% your wallpaper shows through';

  @override
  String get backgroundOpacityDesktop =>
      'Below 100% the desktop shows through, blurred where the system can (Windows 11, macOS, Hyprland, KDE)';

  @override
  String get resetToDefault => 'Reset to default';

  @override
  String couldntLoadFont(String font) {
    return 'Couldn\'t load $font.';
  }

  @override
  String get searchFonts => 'Search fonts on this device';

  @override
  String get riflaysOwnFont => 'Riflay\'s own font';

  @override
  String fontFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files (weights and styles)',
      one: '1 file',
    );
    return '$_temp0';
  }

  @override
  String get defaultThemeFollows => 'Default theme, follows the song that is playing';

  @override
  String themeNamed(String name) {
    return '$name theme';
  }

  @override
  String get smaller => 'Smaller';

  @override
  String get larger => 'Larger';

  @override
  String get levelingPerSong => 'Per song';

  @override
  String get levelingPerAlbum => 'Per album';

  @override
  String get bufferLow => 'Low latency';

  @override
  String get bufferStable => 'Extra stable';

  @override
  String get monoOff => 'Off (stereo)';

  @override
  String get monoBoth => 'Both ears';

  @override
  String get monoLeft => 'Left ear only';

  @override
  String get monoRight => 'Right ear only';

  @override
  String get eqFlat => 'Flat';

  @override
  String get eqBassBoost => 'Bass boost';

  @override
  String get eqBassCut => 'Bass cut';

  @override
  String get eqTrebleBoost => 'Treble boost';

  @override
  String get eqVocal => 'Vocal';

  @override
  String get eqRock => 'Rock';

  @override
  String get eqPop => 'Pop';

  @override
  String get eqJazz => 'Jazz';

  @override
  String get eqClassical => 'Classical';

  @override
  String get eqElectronic => 'Electronic';

  @override
  String get eqLoudness => 'Loudness';

  @override
  String dopNote(String rate) {
    return 'Your DAC takes up to $rate, and DoP needs 176.4 kHz, so DSD files play as PCM on it';
  }

  @override
  String get systemDefault => 'System default';

  @override
  String get outputNotConnected =>
      'The chosen output isn\'t connected, so it plays through the system default for now.';

  @override
  String cardBusy(String card) {
    return '$card is busy, so it plays through the system mixer for now.';
  }

  @override
  String fxRoomCorrection(String name) {
    return 'Room correction ($name)';
  }

  @override
  String get fxEqHeadroom => 'Equalizer headroom';

  @override
  String get fxHrtf => 'Virtual speakers (HRTF)';

  @override
  String get fxMonoBoth => 'Mono (both ears)';

  @override
  String get fxMonoLeft => 'Mono (left ear only)';

  @override
  String get fxMonoRight => 'Mono (right ear only)';

  @override
  String get fxPlugins => 'Audio plugins (Carla)';

  @override
  String get removedFromLiked => 'Removed from Liked music';

  @override
  String get addedToLiked => 'Added to Liked music';

  @override
  String get renamePlaylist => 'Rename playlist';

  @override
  String get name => 'Name';

  @override
  String get playlistOnDeviceNote => 'Kept on this device. Can mix your own files and YouTube Music songs.';

  @override
  String get playlistOnYtNote => 'Saved to your YouTube Music account, on all your devices.';

  @override
  String get privacyPrivate => 'Only you can see it.';

  @override
  String get privacyUnlisted => 'Anyone with the link can see it.';

  @override
  String get privacyPublic => 'Anyone can find and see it.';

  @override
  String get create => 'Create';

  @override
  String createdInYt(String title) {
    return 'Created \"$title\" in YouTube Music';
  }

  @override
  String createdPlaylistWith(String title, int count) {
    return 'Created \"$title\" with $count songs';
  }

  @override
  String createdPlaylist(String title) {
    return 'Created \"$title\"';
  }

  @override
  String get removedFromThisPlaylist => 'Removed from this playlist';

  @override
  String get makeUnlistedQuestion => 'Make it unlisted?';

  @override
  String get makeUnlistedBody =>
      'Friends can only join a playlist that isn\'t private. It will become unlisted: hidden from search, but anyone with the link can see it.';

  @override
  String get makeUnlisted => 'Make unlisted';

  @override
  String get inviteFriends => 'Invite friends';

  @override
  String get inviteLinkCopied => 'The link is copied. Send it to your friends: anyone who opens it can add songs.';

  @override
  String get copyAgain => 'Copy again';

  @override
  String get done => 'Done';

  @override
  String get stopSharingQuestion => 'Stop sharing?';

  @override
  String get stopSharingBody => 'Friends won\'t be able to add songs any more, and old invite links stop working.';

  @override
  String get stopSharing => 'Stop sharing';

  @override
  String get onlyYouCanAdd => 'Only you can add songs now';

  @override
  String get joinSharedPlaylistBody => 'Paste the invite link a friend sent you. You\'ll both be able to add songs.';

  @override
  String get inviteLink => 'Invite link';

  @override
  String get notAnInviteLink => 'That isn\'t an invite link';

  @override
  String get join => 'Join';

  @override
  String unfollowedName(String name) {
    return 'Unfollowed $name';
  }

  @override
  String followingName(String name) {
    return 'Following $name';
  }

  @override
  String get downloadFailedTryAgain => 'Download failed, try again';

  @override
  String downloadHoldTooltip(String format) {
    return 'Download\nHold to download now as $format';
  }

  @override
  String downloadingIn(String format) {
    return 'Downloading in $format…';
  }

  @override
  String downloadingTitle(String title) {
    return 'Downloading $title…';
  }

  @override
  String get thisMonth => 'This month';

  @override
  String get thisYear => 'This year';

  @override
  String get allTime => 'All time';

  @override
  String get monthJanuary => 'January';

  @override
  String get monthFebruary => 'February';

  @override
  String get monthMarch => 'March';

  @override
  String get monthApril => 'April';

  @override
  String get monthMay => 'May';

  @override
  String get monthJune => 'June';

  @override
  String get monthJuly => 'July';

  @override
  String get monthAugust => 'August';

  @override
  String get monthSeptember => 'September';

  @override
  String get monthOctober => 'October';

  @override
  String get monthNovember => 'November';

  @override
  String get monthDecember => 'December';

  @override
  String get monthInitials => 'J F M A M J J A S O N D';

  @override
  String monthYear(String month, String year) {
    return '$month $year';
  }

  @override
  String monthDay(String month, String day) {
    return '$month $day';
  }

  @override
  String get durZero => '0 min';

  @override
  String get durOneMin => '1 min';

  @override
  String durMin(String m) {
    return '$m min';
  }

  @override
  String durHours(String h) {
    return '$h h';
  }

  @override
  String durHoursMin(String h, String m) {
    return '$h h $m min';
  }

  @override
  String wrapSoFar(String month) {
    return '$month so far';
  }

  @override
  String get playFewSongsWrap => 'Play a few songs to see your Wrap.';

  @override
  String notEnoughForWrap(String month) {
    return 'There is not enough listening in $month for a Wrap.';
  }

  @override
  String wrapCaption(String month, String listened, String song, String artist) {
    return 'My $month on Riflay: $listened of music. Top song: $song. Top artist: $artist.';
  }

  @override
  String wrapCaptionStreak(int count) {
    return '🔥 $count days in a row.';
  }

  @override
  String savedFile(String file) {
    return 'Saved $file';
  }

  @override
  String get couldntSaveImage => 'Couldn\'t save the image';

  @override
  String savedCaptionCopied(String file) {
    return 'Saved $file; the caption is copied';
  }

  @override
  String get saveImage => 'Save image';

  @override
  String get weekdayMonday => 'Monday';

  @override
  String get weekdayTuesday => 'Tuesday';

  @override
  String get weekdayWednesday => 'Wednesday';

  @override
  String get weekdayThursday => 'Thursday';

  @override
  String get weekdayFriday => 'Friday';

  @override
  String get weekdaySaturday => 'Saturday';

  @override
  String get weekdaySunday => 'Sunday';

  @override
  String weekdayMonthDay(String weekday, String month, String day) {
    return '$weekday, $month $day';
  }

  @override
  String get wrapSoFarKicker => 'Your Wrap so far';

  @override
  String get wrapMonthlyKicker => 'Your monthly Wrap';

  @override
  String wrapMonthInMusic(String month) {
    return 'Your $month in music';
  }

  @override
  String wrapUpTo(String day) {
    return 'Up to $day';
  }

  @override
  String get wrapListenedFor => 'You listened for';

  @override
  String wrapAcross(int count, String month) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'across $count plays in $month.',
      one: 'across 1 play in $month.',
    );
    return '$_temp0';
  }

  @override
  String wrapAcrossSoFar(int count, String month) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'across $count plays so far in $month.',
      one: 'across 1 play so far in $month.',
    );
    return '$_temp0';
  }

  @override
  String wrapSummary(int songs, int artists, String song, String artist) {
    String _temp0 = intl.Intl.pluralLogic(songs, locale: localeName, other: '$songs songs', one: '1 song');
    String _temp1 = intl.Intl.pluralLogic(artists, locale: localeName, other: '$artists artists', one: '1 artist');
    return 'Top song: $song\nTop artist: $artist\n$_temp0, $_temp1';
  }

  @override
  String get wrapYouPlayed => 'You played';

  @override
  String songsPlural(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count songs', one: '1 song');
    return '$_temp0';
  }

  @override
  String wrapByArtists(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'by $count artists.', one: 'by 1 artist.');
    return '$_temp0';
  }

  @override
  String get wrapTopSong => 'Your top song';

  @override
  String playsPlural(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count plays', one: '1 play');
    return '$_temp0';
  }

  @override
  String get wrapTopSongs => 'Your top songs';

  @override
  String get wrapTopArtist => 'Your top artist';

  @override
  String get wrapTopArtists => 'Your top artists';

  @override
  String get wrapTopAlbum => 'Your top album';

  @override
  String get wrapBiggestDay => 'Your biggest day';

  @override
  String wrapOfMusic(String listened) {
    return '$listened of music.';
  }

  @override
  String get wrapStreakGoing => 'Your streak, still going';

  @override
  String get wrapLongestStreak => 'Your longest streak';

  @override
  String daysInARow(int count) {
    return '$count days in a row';
  }

  @override
  String wrapListenedOnDays(int listened, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'You listened on $listened of $count days.',
      one: 'You listened on $listened of 1 day.',
    );
    return '$_temp0';
  }

  @override
  String wrapListenedOnDaysSoFar(int listened, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'You listened on $listened of $count days so far.',
      one: 'You listened on $listened of 1 day so far.',
    );
    return '$_temp0';
  }

  @override
  String get wrapMostReplayed => 'Most replayed';

  @override
  String wrapPlayedTimesOn(String artist, int count, String day) {
    return '$artist\nPlayed $count times on $day.';
  }

  @override
  String get wrapNewThisMonth => 'New this month';

  @override
  String get wrapYearlyKicker => 'Your yearly Wrap';

  @override
  String get wrapNewThisYear => 'New this year';

  @override
  String wrapLongestStreakOf(String year) {
    return 'Your longest streak of $year';
  }

  @override
  String get yourYearlyWraps => 'Your yearly Wraps';

  @override
  String get thisYearUpToNow => 'This year, up to now';

  @override
  String newSongsPlural(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count new songs', one: '1 new song');
    return '$_temp0';
  }

  @override
  String get wrapStayedWithKnown => 'You stayed with the songs you know.';

  @override
  String get wrapNeverPlayed => 'Songs you had never played before.';

  @override
  String wrapNewCount(int count) {
    return ', $count new';
  }

  @override
  String get madeWithRiflay => 'Made with Riflay';

  @override
  String get yourListening => 'Your listening';

  @override
  String get yourListeningBody => 'Worked out from songs you played for 30 seconds or more. It stays on this device.';

  @override
  String get listeningTime => 'Listening time';

  @override
  String get topSongs => 'Top songs';

  @override
  String get topArtists => 'Top artists';

  @override
  String get topAlbums => 'Top albums';

  @override
  String get yourMonthlyWraps => 'Your monthly Wraps';

  @override
  String get thisMonthUpToNow => 'This month up to now';

  @override
  String get playFewSongsWrapShort => 'Play a few songs to see your Wrap';

  @override
  String couldntFindSong(String title) {
    return 'Couldn\'t find $title';
  }

  @override
  String get statsNothingYet => 'Nothing here yet. Songs you listen to for 30 seconds or more will show up.';

  @override
  String get historyOff =>
      'Your listening history is off. Turn it on in Settings › Library & downloads › Listening history & Wrap.';

  @override
  String listeningTimeChart(String bars) {
    return 'Listening time chart. $bars';
  }

  @override
  String listeningWith(String host) {
    return 'Listening with $host';
  }

  @override
  String get aFriend => 'a friend';

  @override
  String get hosting => 'Hosting';

  @override
  String listeningCount(int count) {
    return '$count listening';
  }

  @override
  String get couldntConnect => 'Couldn\'t connect. Try again.';

  @override
  String get listenTogetherIntro => 'Play YouTube songs together with friends.';

  @override
  String get yourName => 'Your name';

  @override
  String get yourNameHelper => 'Friends see it when you join or start a session';

  @override
  String get enterNameFirst => 'Enter your name first';

  @override
  String get sameWifi => 'Same Wi-Fi';

  @override
  String get anywhere => 'Anywhere';

  @override
  String get anywhereNote =>
      'Connects through free public servers. Everything is encrypted, but it\'s new and can sometimes fail to connect.';

  @override
  String get sameWifiNote => 'Everyone needs to be on the same Wi-Fi.';

  @override
  String get startSession => 'Start a session';

  @override
  String get scanQr => 'Scan QR code';

  @override
  String get onThisWifi => 'On this Wi-Fi';

  @override
  String get lookingForSessions => 'Looking for sessions on this network…';

  @override
  String get tapToJoin => 'Tap to join';

  @override
  String get haveACode => 'Have a code?';

  @override
  String get joinCodeAnywhere => 'Friends anywhere can join with this code.';

  @override
  String get joinCodeWifi => 'Friends on the same Wi-Fi can join with this code.';

  @override
  String get showQr => 'Show QR code';

  @override
  String get listening => 'Listening';

  @override
  String get nobodyJoined => 'Nobody has joined yet.';

  @override
  String get letFriendsAdd => 'Let friends add songs';

  @override
  String get letFriendsAddSubtitle => 'A song a friend plays goes into your queue, in the order they come';

  @override
  String get letFriendsSeek => 'Let friends seek within songs';

  @override
  String get letFriendsSeekSubtitle => 'Changes playback position for everyone';

  @override
  String get youPickSongs => 'You pick the songs. Play any YouTube song and everyone follows.';

  @override
  String get endSession => 'End session';

  @override
  String waitingForHost(String host) {
    return 'Waiting for $host to play something.';
  }

  @override
  String hostPlayingOwnFiles(String host) {
    return '$host is playing a song from their own files. It\'ll continue when they play a YouTube song.';
  }

  @override
  String playGoesToHostQueue(String host) {
    return 'Play any YouTube song and it goes into $host\'s queue.';
  }

  @override
  String hostNotTakingSongs(String host) {
    return '$host isn\'t taking songs right now.';
  }

  @override
  String get host => 'Host';

  @override
  String get upNext => 'Up next';

  @override
  String get seekForEveryone => 'Use the player timeline to seek for everyone.';

  @override
  String get onlyHostSeeks => 'Only the host can seek within songs.';

  @override
  String get leave => 'Leave';

  @override
  String spMixerResamples(String dacRate, String songRate) {
    return 'Riflay leaves the sound alone, but the system mixer runs your DAC at $dacRate instead of $songRate.';
  }

  @override
  String get spFixedRateOutputs =>
      'iPhone, iPad and Bluetooth outputs run at one fixed rate; a USB DAC usually follows each song.';

  @override
  String get spTurnOnBitPerfect =>
      'Turn on Bit-perfect mode in Settings › Sound › Output & quality to send it as it is.';

  @override
  String get spMixerMayResample => 'Nothing in Riflay changes the sound, but the system mixer may resample it.';

  @override
  String get spIosAlwaysMixes => 'iOS always mixes the sound, so it is never bit-perfect here.';

  @override
  String get spForBitPerfectExclusive =>
      'For bit-perfect, turn on Bit-perfect mode and Exclusive mode in Settings › Sound › Output & quality (other apps go silent meanwhile).';

  @override
  String get spForBitPerfect => 'For bit-perfect, turn on Bit-perfect mode in Settings › Sound › Output & quality.';

  @override
  String get spDsdToPcmExclusive =>
      'DSD is decoded to high-rate PCM. To send it to your DAC as DSD, turn on Bit-perfect mode, Exclusive mode and Native DSD (DoP) in Settings › Sound › Output & quality.';

  @override
  String get spDsdToPcmHowTo =>
      'DSD is decoded to high-rate PCM. To send it to your DAC as DSD, turn on Bit-perfect mode and Native DSD (DoP) in Settings › Sound › Output & quality.';

  @override
  String spUsbDacRateUnsupported(String dac, String songRate, String outRate) {
    return '$dac doesn\'t take $songRate, so Android plays it at $outRate instead.';
  }

  @override
  String get qualityLossy => 'Lossy';

  @override
  String get qualityLossless => 'Lossless';

  @override
  String get nativeDsd2 => 'Native DSD';

  @override
  String get spNativeDsdBody =>
      'The DSD stream reaches your DAC as it is, packed as DoP. A DAC that supports DoP shows DSD; one that doesn\'t plays a faint hiss (then turn off Native DSD).';

  @override
  String get spDopChanged => 'DoP is being changed';

  @override
  String get spDopChangedBody =>
      'Something between Riflay and your DAC changes the samples, so the DAC can\'t see the DSD. Choose a direct output in Settings › Sound › Output & quality.';

  @override
  String spUsbBitPerfect(String dac) {
    return 'USB DAC, bit-perfect (Android 14): every sample reaches $dac exactly as it is stored in the file.';
  }

  @override
  String get spNotBitPerfect => 'Not bit-perfect';

  @override
  String get spBitPerfectBody => 'Every sample reaches your DAC exactly as it is stored in the file.';

  @override
  String get spResampledByMixer => 'Resampled by the system mixer';

  @override
  String get spLosslessToMixer => 'Lossless to the system mixer';

  @override
  String get spDsdConverted => 'DSD converted to PCM';

  @override
  String get spDsdIos => 'DSD is decoded to high-rate PCM. iOS can\'t send DSD to a DAC as DSD.';

  @override
  String get spProcessed => 'Processed';

  @override
  String get spProcessedBody => 'Something below changes the samples. That is fine if it is what you want.';

  @override
  String get spSource => 'Source';

  @override
  String get spLosslessParen => '(lossless)';

  @override
  String get spDecoded => 'Decoded';

  @override
  String spPadded(int bits) {
    return '($bits-bit, padded losslessly)';
  }

  @override
  String get spUntouched => '100% (untouched)';

  @override
  String get spMuted => 'Muted';

  @override
  String get spClipProtection => 'Clip protection';

  @override
  String get spClipProtectionBody => 'Softens any peak past full scale instead of cutting it off';

  @override
  String get spResampled => 'Resampled';

  @override
  String get spDacReceives => 'DAC receives';

  @override
  String get spMono => 'mono';

  @override
  String get spStereo => 'stereo';

  @override
  String spChannels(String count) {
    return '$count channels';
  }

  @override
  String get spPipewire => 'PipeWire (system mixer)';

  @override
  String get spPulse => 'PulseAudio (system mixer)';

  @override
  String get spAlsaDirect => 'ALSA, direct to hardware';

  @override
  String get spWasapiExclusive => 'WASAPI exclusive';

  @override
  String get spWasapiShared => 'WASAPI shared';

  @override
  String get spAndroidMixer => 'Android mixer';

  @override
  String get spAndroidMixerParen => '(Android mixer)';

  @override
  String get spIosSession => 'iOS audio session (system mixer)';

  @override
  String get couldntOpenBrowser => 'Couldn\'t open the browser.';

  @override
  String versionNamed(String version) {
    return 'Version $version';
  }

  @override
  String get version => 'Version';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get whatsNew => 'What\'s new';

  @override
  String get whatsNewSubtitle => 'Release notes and downloads for every platform';

  @override
  String get reportProblem => 'Report a problem';

  @override
  String get reportProblemSubtitle => 'Opens a new issue; paste the version details in it';

  @override
  String get supportArtists => 'Support the artists';

  @override
  String get supportArtistsSubtitle => 'Enjoying the music? YouTube Music Premium pays the people who make it';

  @override
  String get supportRiflay => 'Support Riflay';

  @override
  String get supportRiflaySubtitle => 'Send a gift on Tako to keep it going';

  @override
  String get sourceCode => 'Source code';

  @override
  String get sourceCodeSubtitle => 'Riflay is open source, on GitHub';

  @override
  String get licence => 'Licence';

  @override
  String get openSourceLicences => 'Open-source licences';

  @override
  String get openSourceLicencesSubtitle => 'The libraries Riflay is built with';

  @override
  String get scrobbleBody =>
      'Songs you listen to past the halfway mark (or 4 minutes) are added to your profile there. Listens made offline are sent once you\'re back online.';

  @override
  String get connect => 'Connect';

  @override
  String get notConnected => 'Not connected';

  @override
  String connectedAs(String user) {
    return 'Connected as $user';
  }

  @override
  String get connected => 'Connected';

  @override
  String get noNewListens => 'No new listens to bring in';

  @override
  String listensAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count listens added to your history',
      one: '1 listen added to your history',
    );
    return '$_temp0';
  }

  @override
  String serviceSignedOut(String service) {
    return '$service signed you out. Connect it again.';
  }

  @override
  String couldntReachService(String service) {
    return 'Couldn\'t reach $service. Try again.';
  }

  @override
  String readingListens(String count) {
    return 'Reading your listens: $count so far';
  }

  @override
  String get turnOnHistoryFirst => 'Turn on the listening history in Library & downloads first.';

  @override
  String get bringInBody =>
      'Adds the songs you played elsewhere to your stats, Wraps and Most played. Ones already here are skipped.';

  @override
  String bringInHistory(String service) {
    return 'Bring in your $service history';
  }

  @override
  String get stop => 'Stop';

  @override
  String get bringIn => 'Bring in';

  @override
  String connectService(String service) {
    return 'Connect $service';
  }

  @override
  String get listenBrainzTokenBody => 'Copy your user token from your ListenBrainz settings and paste it here.';

  @override
  String get openListenBrainzSettings => 'Open ListenBrainz settings';

  @override
  String get userToken => 'User token';

  @override
  String get signInTooLong => 'The sign-in took too long. Try again.';

  @override
  String get lastfmDidntFinish => 'Last.fm didn\'t finish the sign-in. Try again.';

  @override
  String get lastfmAllowBody =>
      'Allow Riflay on the Last.fm page that opened in your browser. This closes by itself once you have.';

  @override
  String get openLastfmAgain => 'Open Last.fm again';

  @override
  String get spotifyReadFailed => 'Couldn\'t read your Spotify library right now. Try again later.';

  @override
  String get needsWebkit => 'Signing in needs WebKitGTK (webkit2gtk-4.1). Install it and restart Riflay.';

  @override
  String get spotifySignInUnavailable => 'Signing in to Spotify isn\'t available here.';

  @override
  String get spotifyIntro => 'Copy your Spotify playlists, Liked Songs and albums into Riflay.';

  @override
  String get spotifyReadOnly => 'Riflay only reads your library. It never changes your Spotify account.';

  @override
  String get signInWithSpotify => 'Sign in with Spotify';

  @override
  String get playlistsGoToYt => 'Playlists go to your YouTube Music library.';

  @override
  String get playlistsBecomeRiflay => 'Playlists become Riflay playlists.';

  @override
  String get signedInToSpotify => 'Signed in to Spotify';

  @override
  String get signOut => 'Sign out';

  @override
  String get nothingHereYet => 'Nothing here yet.';

  @override
  String get imported => 'Imported';

  @override
  String get importAll => 'Import all';

  @override
  String importCount(String count) {
    return 'Import $count';
  }

  @override
  String get import => 'Import';

  @override
  String get importing => 'Importing';

  @override
  String get stopping => 'Stopping…';

  @override
  String findingSongsInYt(String matched, String total) {
    return 'Finding songs in YouTube Music: $matched of $total';
  }

  @override
  String get findingArtistInYt => 'Finding the artist in YouTube Music…';

  @override
  String get readingTheSongs => 'Reading the songs…';

  @override
  String importedOf(String done, String total) {
    return 'Imported $done of $total';
  }

  @override
  String get youStoppedImport => 'You stopped the import.';

  @override
  String get pronunciation => 'Pronunciation';

  @override
  String get translation => 'Translation';

  @override
  String get copyLyrics => 'Copy lyrics';

  @override
  String get adjustTiming => 'Adjust timing';

  @override
  String get removeMyLyrics => 'Remove my lyrics';

  @override
  String get playerOptions => 'Player options';

  @override
  String get chooseLyricsFile => 'Choose a lyrics file';

  @override
  String get lyricsFileTooBig => 'That file is too big to be lyrics.';

  @override
  String get yourLyricsInUse => 'Your lyrics are in use';

  @override
  String get couldntReadFile => 'Couldn\'t read that file.';

  @override
  String get couldntRemoveLyrics => 'Couldn\'t remove your lyrics.';

  @override
  String get onTime => 'On time';

  @override
  String secondsEarlier(String seconds) {
    return '$seconds s earlier';
  }

  @override
  String secondsLater(String seconds) {
    return '$seconds s later';
  }

  @override
  String get adjustTimingBody => 'If the lyrics come too early or too late, move them until they match the song.';

  @override
  String get earlier => 'Earlier';

  @override
  String get later => 'Later';

  @override
  String get lyricsCopied => 'Lyrics copied';

  @override
  String get couldntTranslateLyrics => 'Couldn\'t translate these lyrics. Check your internet connection.';

  @override
  String get privacyPublicLabel => 'Public';

  @override
  String get privacyUnlistedLabel => 'Unlisted';

  @override
  String get privacyPrivateLabel => 'Private';

  @override
  String joinedPlaylist(String title) {
    return 'Joined \"$title\"';
  }

  @override
  String get thePlaylist => 'the playlist';

  @override
  String get sharedPlaylist => 'Shared playlist';

  @override
  String get ytSignInPrompt => 'Sign in to YouTube Music to add your liked songs, playlists and history.';

  @override
  String get signingIn => 'Signing in…';

  @override
  String get ytLoadFailed => 'Couldn\'t load YouTube Music. Check your internet connection.';

  @override
  String get playlistLoadFailed => 'Couldn\'t load this playlist. Check your internet connection.';

  @override
  String playlistIsNow(String privacy) {
    return 'Playlist is now $privacy';
  }

  @override
  String deleteYtPlaylistBody(String title) {
    return '\"$title\" will be deleted from your YouTube Music library. This can\'t be undone.';
  }

  @override
  String get shared => 'Shared';

  @override
  String makePrivacy(String privacy) {
    return 'Make $privacy';
  }

  @override
  String get chooseDownloadsFolder => 'Choose where downloads are saved';

  @override
  String get bestSoundNote => 'The best sound YouTube has for each song.';

  @override
  String get smallerFilesNote => 'Smaller files, with a little less full sound.';

  @override
  String closestVersionNote(String base) {
    return '$base Uses the closest version YouTube offers.';
  }

  @override
  String get whatToSave => 'What to save';

  @override
  String get saveAs => 'Save as';

  @override
  String get saveAsVideoNote => 'The music video, with its sound. Songs without a music video are saved as audio.';

  @override
  String get saveAsAudioNote => 'Just the sound. Choose Video to keep the music video too.';

  @override
  String get videoFormat => 'Video format';

  @override
  String get size => 'Size';

  @override
  String get videoSizeNote =>
      'The tallest picture the video has, up to the one you choose. 1080p is a sharp picture without a huge file.';

  @override
  String get bestAvailable => 'Best available';

  @override
  String heightRecommended(String height) {
    return '${height}p (Recommended)';
  }

  @override
  String get format => 'Format';

  @override
  String flacUnavailable(String about) {
    return '$about\nFLAC isn\'t available on this device.';
  }

  @override
  String get bitDepthSampleRate => 'Bit depth and sample rate';

  @override
  String get bitrate => 'Bitrate';

  @override
  String get askEveryTime => 'Ask every time';

  @override
  String get askEveryTimeSubtitle => 'Choose the format and quality each time you download a song.';

  @override
  String get where => 'Where';

  @override
  String get downloadOverMobile => 'Download over mobile data';

  @override
  String get downloadOverMobileOn => 'Songs download on mobile data as well as Wi-Fi.';

  @override
  String get downloadOverMobileOff => 'Songs wait for Wi-Fi, so they don\'t use your data plan.';

  @override
  String get downloadsFolder => 'Downloads folder';

  @override
  String phoneDownloadsFixed(String path) {
    return '$path\nPhones keep downloads in Riflay\'s own storage, so this can\'t be changed.';
  }

  @override
  String get openFolder => 'Open folder';

  @override
  String get ytDlp => 'YouTube downloader (yt-dlp)';

  @override
  String get ytDlpMissing => 'Not available. Install it (e.g. pacman -S yt-dlp) for YouTube downloads.';

  @override
  String removeNamedQuestion(String name) {
    return 'Remove $name?';
  }

  @override
  String get removeExtensionBody => 'Its files and what it saved on this device are deleted.';

  @override
  String couldntRemoveNamed(String name) {
    return 'Couldn\'t remove $name';
  }

  @override
  String get extensionsIntro =>
      'Extensions written for SpotiFLAC add more places to search, such as Apple Music, SoundCloud and JioSaavn. Their songs play from YouTube Music. Only add repositories you trust: an extension runs its own code and can reach the sites its manifest lists.';

  @override
  String get repositories => 'Repositories';

  @override
  String get installed => 'Installed';

  @override
  String get noExtensionsYet => 'No extensions yet';

  @override
  String get installFromRepo => 'Install one from a repository below';

  @override
  String get available => 'Available';

  @override
  String get repositoryAddress => 'Repository address';

  @override
  String get reading => 'Reading…';

  @override
  String couldntReadIt(String error) {
    return 'Couldn\'t read it: $error';
  }

  @override
  String get notReadYet => 'Not read yet';

  @override
  String extensionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count extensions', one: '1 extension');
    return '$_temp0';
  }

  @override
  String get removeRepository => 'Remove repository';

  @override
  String get addsToSearch => 'Adds results to Search';

  @override
  String get downloadsUnsupported => 'downloads not supported yet';

  @override
  String get lyricsUnsupported => 'lyrics not supported yet';

  @override
  String get needsSpotiflacFeatures => 'needs SpotiFLAC features Riflay lacks, so it may not work';

  @override
  String updateTo(String version) {
    return 'Update to $version';
  }

  @override
  String couldntUpdateNamed(String name) {
    return 'Couldn\'t update $name';
  }

  @override
  String couldntInstallNamed(String name) {
    return 'Couldn\'t install $name';
  }

  @override
  String get install => 'Install';

  @override
  String get scPlayPause => 'Play or pause';

  @override
  String get scNext => 'Next song';

  @override
  String get scPrevious => 'Previous song';

  @override
  String get scVolumeUp => 'Volume up';

  @override
  String get scVolumeDown => 'Volume down';

  @override
  String get scBack => 'Go back';

  @override
  String get scForward => 'Go forward';

  @override
  String get scPasteLink => 'Import a copied YouTube link';

  @override
  String get scFullScreen => 'Full screen player';

  @override
  String get scHelp => 'Show this list';

  @override
  String get scSlashOr => '? or Ctrl+/';

  @override
  String get saveABackup => 'Save a backup';

  @override
  String get backupSaved => 'Backup saved';

  @override
  String get couldntSaveBackup => 'Couldn\'t save the backup.';

  @override
  String get chooseBackup => 'Choose a Riflay backup';

  @override
  String get backupNeedsNewer => 'This backup needs a newer Riflay.';

  @override
  String get notABackup => 'That file isn\'t a Riflay backup.';

  @override
  String get restoreBackupQuestion => 'Restore this backup?';

  @override
  String restoreBackupBody(int playlists, int plays, int lyrics, String made) {
    String _temp0 = intl.Intl.pluralLogic(
      playlists,
      locale: localeName,
      other: '$playlists playlists',
      one: '1 playlist',
    );
    String _temp1 = intl.Intl.pluralLogic(plays, locale: localeName, other: '$plays plays', one: '1 play');
    String _temp2 = intl.Intl.pluralLogic(
      lyrics,
      locale: localeName,
      other: '$lyrics lyrics files',
      one: '1 lyrics file',
    );
    return '${made}It has $_temp0, $_temp1 of listening history and $_temp2. They replace the settings, playlists and history on this device. Your sign-ins stay.';
  }

  @override
  String get restore => 'Restore';

  @override
  String get couldntRestoreBackup => 'Couldn\'t restore the backup.';

  @override
  String get backupRestored => 'Backup restored';

  @override
  String get backupRestoredIos => 'Close Riflay from the app switcher and open it again to finish.';

  @override
  String get backupRestoredDesktop => 'Riflay closes now. Open it again to finish.';

  @override
  String get closeRiflay => 'Close Riflay';

  @override
  String madeOn(String date) {
    return 'Made on $date.';
  }

  @override
  String get saveABackupSubtitle =>
      'Your settings, playlists, listening history and your own lyrics, in one file. Sign-ins are left out.';

  @override
  String get restoreABackup => 'Restore a backup';

  @override
  String get restoreABackupSubtitle => 'Bring them back on this device or a new one.';

  @override
  String dupRemovedSomeFailed(int removed, int failed) {
    return 'Removed $removed copies. $failed files couldn\'t be deleted.';
  }

  @override
  String dupRemovedAndDeleted(int removed, int deleted, String size) {
    return 'Removed $removed copies and deleted $deleted files, freeing $size.';
  }

  @override
  String dupRemovedFromLibrary(int removed) {
    return 'Removed $removed copies from your library.';
  }

  @override
  String get songsYouHaveTwice => 'Songs you have twice';

  @override
  String get lookingThroughLibrary => 'Looking through your library...';

  @override
  String get noDuplicates => 'No song is in your library twice.';

  @override
  String get duplicatesBody =>
      'These are the same song in more than one file. The best copy is chosen for each; pick another if you like, then remove the rest.';

  @override
  String get nothingToRemove => 'Nothing to remove';

  @override
  String removeExtraCopies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Remove $count extra copies',
      one: 'Remove 1 extra copy',
    );
    return '$_temp0';
  }

  @override
  String upToCanBeFreed(String size) {
    return 'Up to $size can be freed.';
  }

  @override
  String get chooseOne => 'Choose one';

  @override
  String get keepAll => 'Keep all';

  @override
  String get bestQuality => 'best quality';

  @override
  String get downloadedByRiflay => 'Downloaded by Riflay';

  @override
  String get yourFile => 'Your file';

  @override
  String get keep => 'Keep';

  @override
  String removeCopiesQuestion(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Remove $count copies?',
      one: 'Remove 1 copy?',
    );
    return '$_temp0';
  }

  @override
  String get removeCopiesBody =>
      'They are taken out of your library, and the copy you keep stays. Playlists that had a removed copy use the one you keep.';

  @override
  String get alsoDeleteFiles => 'Also delete the files from this device';

  @override
  String freesSize(String size) {
    return 'Frees $size. Deleted files can\'t be brought back.';
  }

  @override
  String ownFilesCount(int count) {
    return '$count of your own files';
  }

  @override
  String downloadsRiflaySaved(int count) {
    return '$count downloads Riflay saved';
  }

  @override
  String get listAnd => 'and';

  @override
  String filesUsedElsewhere(int count) {
    return '$count files are used by other songs and stay.';
  }

  @override
  String get deleteFiles => 'Delete files';

  @override
  String couldntPlay(String title) {
    return 'Couldn\'t play $title';
  }

  @override
  String get ytSearchFailed => 'YouTube search failed. Check your connection.';

  @override
  String get noYtResults => 'No YouTube results.';

  @override
  String get ytSearchSource => 'YouTube search';

  @override
  String get topResult => 'Top result';

  @override
  String get nothingFound => 'Nothing found.';

  @override
  String get noYtVideos => 'No YouTube videos found.';

  @override
  String get ytVideosSource => 'YouTube videos';

  @override
  String get couldntReadSongInfo => 'Couldn\'t read this song\'s info';

  @override
  String get saved => 'Saved';

  @override
  String get couldntSaveChanges => 'Couldn\'t save the changes';

  @override
  String get chooseCoverArt => 'Choose cover art';

  @override
  String get noCoverFound => 'No cover found for this album';

  @override
  String get couldntReachCoverArchive => 'Couldn\'t reach the Cover Art Archive';

  @override
  String get changeCover => 'Change cover';

  @override
  String get searching => 'Searching…';

  @override
  String get findOnline => 'Find online';

  @override
  String get largeImageHint => 'Use a large image (1000 px or more) for sharp artwork.';

  @override
  String get trackNumber => 'Track';

  @override
  String get discNumber => 'Disc';

  @override
  String get year => 'Year';

  @override
  String get genre => 'Genre';

  @override
  String get ytSignInAgain => 'Please sign in to YouTube Music again.';

  @override
  String get ytBusy => 'YouTube Music is busy. Try again in a minute.';

  @override
  String get ytNotAnswering => 'YouTube Music isn\'t answering right now. Try again later.';

  @override
  String get couldntFinishSignIn => 'Couldn\'t finish signing in. Try again.';

  @override
  String get signInDidntFinish => 'Signing in didn\'t finish. Try again.';

  @override
  String get moodsAndGenres => 'Moods & genres';

  @override
  String get performance => 'Performance';

  @override
  String get keepScreenOn => 'Keep screen on';

  @override
  String get keepScreenOnPhone => 'Stops the screen from turning off by itself. Costs battery';

  @override
  String get keepScreenOnDesktop => 'Stops the screen from turning off and locking by itself';

  @override
  String get dontSleepWhilePlaying => 'Don\'t sleep while playing';

  @override
  String get dontSleepSubtitle => 'The computer stays awake while music plays. The screen can still turn off';

  @override
  String get closeToTray => 'Close to tray';

  @override
  String get noTrayIcons => 'Your desktop doesn\'t show tray icons, so closing the window quits Riflay';

  @override
  String get closeToTraySubtitle => 'Closing the window keeps Riflay playing in the tray. Quit it from the tray icon';

  @override
  String get keepPlayingScreenOff => 'Keep playing with the screen off';

  @override
  String get batteryExemptOn => 'On. Your phone won\'t put Riflay to sleep';

  @override
  String get batteryExemptOff => 'Off. Your phone may stop the music after a while';

  @override
  String get allow => 'Allow';

  @override
  String get openBatterySettings => 'Open battery settings';

  @override
  String get keepMusicPlaying => 'Keep the music playing';

  @override
  String get keepMusicPlayingBody =>
      'Some phones stop music when the screen has been off for a while. Allowing Riflay to run in the background keeps it playing. You can change this later in Settings.';

  @override
  String get notNow => 'Not now';

  @override
  String get couldntSaveChangesRetry => 'Couldn\'t save the changes. Try again.';

  @override
  String get editSong => 'Edit song';

  @override
  String get artistNamesStay => 'Artist names stay as the artist released them.';

  @override
  String get yourLyrics => 'Your lyrics';

  @override
  String get yourLyricsBody =>
      'Shown instead of lyrics found online. Start lines with a time like [01:23.45] to have them follow the song.';

  @override
  String get pasteLyricsHere => 'Paste lyrics here';

  @override
  String get addFromFile => 'Add from a file';

  @override
  String importedNamed(String title) {
    return 'Imported \"$title\"';
  }

  @override
  String get pastePlaylistLink => 'Paste a playlist link from Spotify, Apple Music or Deezer.';

  @override
  String get becomesYtPlaylist => 'It becomes a playlist in your YouTube Music library.';

  @override
  String get becomesRiflayPlaylist => 'It becomes a Riflay playlist of YouTube Music songs.';

  @override
  String get playlistLink => 'Playlist link';

  @override
  String get notAPlaylistLink => 'That isn\'t a Spotify, Apple Music or Deezer playlist link';

  @override
  String get readingPlaylist => 'Reading the playlist…';

  @override
  String get saving => 'Saving…';

  @override
  String songsAddedOf(String saved, String total) {
    return '$saved of $total songs added.';
  }

  @override
  String songsAddedOfYt(String saved, String total) {
    return '$saved of $total songs added to your YouTube Music library.';
  }

  @override
  String firstSongsOnly(int count, String service) {
    return '$service only shows the first $count songs without signing in, so the rest were left out.';
  }

  @override
  String songsNotOnYt(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs aren\'t on YouTube Music:',
      one: '1 song isn\'t on YouTube Music:',
    );
    return '$_temp0';
  }

  @override
  String get openPlaylist => 'Open playlist';

  @override
  String get fmtOpusAbout => 'Smallest files for the same sound. Plays in Riflay and most players.';

  @override
  String get fmtM4aAbout => 'The most widely supported. Plays on nearly every phone, TV and speaker.';

  @override
  String get fmtFlacAbout =>
      'Lossless file for players and libraries that want FLAC. YouTube\'s sound is kept exactly; it gets no better.';

  @override
  String get fmtMp3About =>
      'For older players and car stereos. Made from YouTube\'s audio, so it never sounds better than Opus or M4A.';

  @override
  String get kindAudio => 'Audio';

  @override
  String get kindVideo => 'Video';

  @override
  String get vidMp4About => 'H.264 picture and AAC sound. Plays on nearly every phone, TV and computer.';

  @override
  String get vidWebmAbout =>
      'VP9 picture and Opus sound. Smaller files, and the tallest sizes; plays in Riflay and most computers.';

  @override
  String get flacStandardAbout => 'Same sample rate as YouTube\'s audio. Plays everywhere.';

  @override
  String get flacCdAbout => 'CD quality, for players and burners that want exactly that.';

  @override
  String get flacHiResAbout => 'Larger files, for libraries kept at 24-bit.';

  @override
  String kbpsBest(String kbps) {
    return '$kbps kbps (best)';
  }

  @override
  String videoChoice(String container, String height) {
    return 'Video · $container · $height';
  }

  @override
  String get bestAvailableLower => 'best available';

  @override
  String get waitingToStart => 'Waiting to start';

  @override
  String get noteDownloading => 'Downloading';

  @override
  String downloadedTitle(String title) {
    return 'Downloaded $title';
  }

  @override
  String get savedToLibrary => 'Saved to your library';

  @override
  String couldntDownloadTitle(String title) {
    return 'Couldn\'t download $title';
  }

  @override
  String get tapRetry => 'Tap Retry to try again.';

  @override
  String downloadingSongsNote(int count) {
    return 'Downloading $count songs';
  }

  @override
  String get openRiflay => 'Open Riflay';

  @override
  String get downloadsChannelDescription => 'Progress of songs being downloaded';

  @override
  String servicePlaylist(String service) {
    return '$service playlist';
  }

  @override
  String get clearHistoryQuestion => 'Clear listening history?';

  @override
  String clearHistoryBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'This deletes $count plays from this device. Your library and playlists stay as they are, but your stats, Wraps and lists like Most played start over.',
      one: 'This deletes 1 play from this device. Your library and playlists stay as they are, but your stats, Wraps and lists like Most played start over.',
    );
    return '$_temp0';
  }

  @override
  String get historyCleared => 'Listening history cleared';

  @override
  String get keepHistory => 'Keep a listening history on this device';

  @override
  String get keepHistorySubtitle =>
      'Powers Your listening stats, monthly Wraps and lists like Most played. It is never sent anywhere. Turning it off stops recording; what is saved stays until you clear it.';

  @override
  String get wrapNotification => 'Monthly Wrap notification';

  @override
  String get wrapNotificationSubtitle => 'On the 1st, tell me when last month\'s Wrap is ready.';

  @override
  String get clearHistory => 'Clear listening history';

  @override
  String get nothingSavedYet => 'Nothing saved yet';

  @override
  String playsSaved(int count) {
    return '$count plays saved on this device';
  }

  @override
  String get lyricsFile => 'Lyrics file';

  @override
  String get embeddedInFile => 'Embedded in the file';

  @override
  String get addLyricsFirst => 'Add some lyrics first.';

  @override
  String get lrcTimesWrong =>
      'Some of the times in these lyrics aren\'t written correctly. Start each line with a time like [01:23.45].';

  @override
  String get lrcTimesPastEnd => 'These times run past the end of the song. Check that the lyrics belong to it.';

  @override
  String get couldntStartSession => 'Couldn\'t start a session. Check that you\'re connected to Wi-Fi.';

  @override
  String get sessionStopped => 'The session stopped. Start it again to keep listening together.';

  @override
  String nameLeft(String name) {
    return '$name left';
  }

  @override
  String get someone => 'Someone';

  @override
  String nameAddedToQueue(String name, String title) {
    return '$name added $title to the queue';
  }

  @override
  String get sessionNotFound => 'Couldn\'t find that session. Check the code and that you\'re on the same Wi-Fi.';

  @override
  String get sessionNotAnswering => 'That session isn\'t answering. Try again in a moment.';

  @override
  String get theHostCap => 'The host';

  @override
  String hostEndedSession(String host) {
    return '$host ended the listening session';
  }

  @override
  String get sessionEndedOrDropped => 'The session ended or the connection dropped.';

  @override
  String get lostHostConnection => 'Lost the connection to the host. Join again to keep listening.';

  @override
  String get listeningTogetherSource => 'Listening together';

  @override
  String get youLeftSession => 'You left the listening session';

  @override
  String onlyYtToHostQueue(String host) {
    return 'Only songs from YouTube Music can be added to $host\'s queue.';
  }

  @override
  String get checkGithubUpdate => 'Check GitHub for a newer version of Riflay';

  @override
  String get checkingUpdates => 'Checking for updates…';

  @override
  String get latestVersion => 'You\'re using the latest version';

  @override
  String versionAvailable(String version) {
    return 'Version $version is available';
  }

  @override
  String downloadingVersion(String version) {
    return 'Downloading version $version…';
  }

  @override
  String versionReady(String version) {
    return 'Version $version is ready to install';
  }

  @override
  String get openingInstaller => 'Opening the Android installer…';

  @override
  String get completeInInstaller => 'Complete the update in the Android installer';

  @override
  String get allowInstallUpdates => 'Allow Riflay to install updates, then try again';

  @override
  String get differentSigningKey =>
      'This copy uses a different signing key. Back up your data before installing the release';

  @override
  String get couldntVerifyUpdate => 'Couldn\'t verify the update. Try downloading it again';

  @override
  String get couldntCheckUpdates => 'Couldn\'t check for updates. Try again';

  @override
  String get couldntUpdateRiflay => 'Couldn\'t update Riflay. Try again';

  @override
  String get installUpdate => 'Install update';

  @override
  String get checkForUpdates => 'Check for updates';

  @override
  String get downloadUpdate => 'Download update';

  @override
  String get getUpdate => 'Get update';

  @override
  String get spotifySignInExpired => 'Your Spotify sign-in has expired. Sign in again.';

  @override
  String get recommended => 'Recommended';

  @override
  String bestAvailableWith(String label) {
    return 'Best available ($label)';
  }

  @override
  String get downloadAsTitle => 'Download as';

  @override
  String get downloadTrackTitle => 'Download track';

  @override
  String get audioFormat => 'Audio format';

  @override
  String get bitrateQuality => 'Bitrate quality';

  @override
  String get fmtTagUniversal => 'Universal';

  @override
  String get fmtTagModern => 'Modern';

  @override
  String downloadFormatAction(String format) {
    return 'Download $format';
  }

  @override
  String savedToFolder(String folder) {
    return 'Saved to $folder';
  }

  @override
  String get couldntLookUpSizes => 'Couldn\'t look up video sizes.';

  @override
  String get smallerFilesClosest =>
      'Smaller files, with a little less full sound. Uses the closest version YouTube offers.';

  @override
  String get musicFolders => 'Music folders';

  @override
  String get keepLibraryUpToDate => 'Keep the library up to date';

  @override
  String get keepLibraryOpen =>
      'New songs in your music folders are added, and songs you delete or move are taken out, each time you open Riflay.';

  @override
  String get keepLibraryWatch =>
      'New songs in your music folders are added, and songs you delete or move are taken out, without adding the folder again.';

  @override
  String get checkNow => 'Check now';

  @override
  String get addFolderFirst => 'Add a music folder from the library first.';

  @override
  String get checkingDots => 'Checking...';

  @override
  String lookAtFoldersAgain(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Look at your $count music folders again.',
      one: 'Look at your music folder again.',
    );
    return '$_temp0';
  }

  @override
  String get stopWatching => 'Stop watching';

  @override
  String get tidyUp => 'Tidy up';

  @override
  String get findDuplicates => 'Find songs you have twice';

  @override
  String get findDuplicatesSubtitle => 'The same song in different files, so you can keep the best one.';

  @override
  String get sessionQr => 'Session QR code';

  @override
  String get sessionQrSemantics => 'Listening session QR code';

  @override
  String get sessionQrHowTo => 'In Riflay on another device, open Listen together and choose Scan QR code.';

  @override
  String get notASessionQr => 'That QR code is not a Riflay session code.';

  @override
  String get noSessionInImage => 'Couldn\'t find a Riflay session code in that image.';

  @override
  String get couldntReadImage => 'Couldn\'t read that image. Try another one.';

  @override
  String get cameraUnavailable =>
      'Camera unavailable. Allow camera access in your device settings, or open a QR image.';

  @override
  String get openQrImageToJoin => 'Open an image of the session QR code to join.';

  @override
  String get pointCamera => 'Point the camera at the session QR code shown in Riflay.';

  @override
  String get readingImage => 'Reading image…';

  @override
  String get openQrImage => 'Open QR image';

  @override
  String get motionGlide => 'Glide';

  @override
  String get motionFadeThrough => 'Fade through';

  @override
  String get motionSoftZoom => 'Soft zoom';

  @override
  String get motionSlide => 'Slide';

  @override
  String get motionCurtain => 'Curtain reveal';

  @override
  String get motionCircular => 'Circular reveal';

  @override
  String get motionSide => 'Side reveal';

  @override
  String get motionDiamond => 'Diamond reveal';

  @override
  String get speedFast => 'Fast';

  @override
  String get speedRelaxed => 'Relaxed';

  @override
  String serviceSignedOutSettings(String service) {
    return '$service signed you out. Connect it again in Settings.';
  }

  @override
  String lostConnectionTo(String device) {
    return 'Lost connection to $device';
  }

  @override
  String couldntPlayOn(String device) {
    return 'Couldn\'t play on $device';
  }

  @override
  String get pasteYtLink => 'Paste a YouTube link to a video or playlist.';

  @override
  String get linkLoadFailed => 'Couldn\'t load that link. It may be private, removed or region-locked.';

  @override
  String get importFromYtBody => 'Downloads the audio track and adds it to your library.';

  @override
  String get paste => 'Paste';

  @override
  String get bestQualityNote =>
      'Saved in the best quality YouTube offers (up to ~160 kbps Opus/AAC), without re-encoding.';

  @override
  String downloadCount(String count) {
    return 'Download $count';
  }

  @override
  String aboutSize(String size) {
    return 'About $size';
  }

  @override
  String aboutSizeTotal(String size) {
    return 'About $size total';
  }

  @override
  String ytPlaylistLine(int count, String author) {
    return 'Playlist • $author • $count videos';
  }

  @override
  String get checkingSize => 'Checking size…';

  @override
  String get eqBitPerfectNote =>
      'Bit-perfect mode is on, so the equalizer is bypassed. Turn it off in Settings › Sound › Output & quality.';

  @override
  String get eqHint => 'Pick a preset or drag the sliders. Tap a frequency to fine-tune it.';

  @override
  String eqHeadroom(String db) {
    return 'Headroom $db dB, so boosted bands never distort.';
  }

  @override
  String get changeFrequency => 'Change frequency and width';

  @override
  String bandNumber(String number) {
    return 'Band $number';
  }

  @override
  String get defaultLabel => 'Default';

  @override
  String get newReleases => 'New releases';

  @override
  String get couldntLoadPage => 'Couldn\'t load this page. Check your internet connection.';

  @override
  String get removedFromLibrary => 'Removed from your library';

  @override
  String get saveToLibrary => 'Save to library';

  @override
  String get phaseDownloading => 'Downloading';

  @override
  String get converting => 'Converting…';

  @override
  String get finishing => 'Finishing…';

  @override
  String get needsFfmpegMp3 =>
      'MP3 downloads need ffmpeg, which isn\'t available here. Pick another format in Settings › Library & downloads › Downloads.';

  @override
  String get noFlacHere =>
      'FLAC downloads aren\'t available on this device. Pick another format in Settings › Library & downloads › Downloads.';

  @override
  String get mobileDataOff =>
      'Mobile data downloads are off. Connect to Wi-Fi, or allow them in Settings › Library & downloads › Downloads.';

  @override
  String get couldntDownloadSong => 'Couldn\'t download this song. Try again later.';

  @override
  String spotifyLinePlaylist(String name, String found, String total) {
    return '$name: $found of $total songs';
  }

  @override
  String spotifyLineAlbumSaved(String name) {
    return '$name: saved to your library';
  }

  @override
  String spotifyLineFollowed(String name) {
    return '$name: followed';
  }

  @override
  String spotifyLineArtistMissing(String name) {
    return '$name: not found on YouTube Music';
  }

  @override
  String spotifyLineNoSongs(String name) {
    return '$name: no songs found on YouTube Music';
  }

  @override
  String spotifyLineFailed(String name, String problem) {
    return '$name: $problem';
  }

  @override
  String get somethingWentWrong => 'something went wrong';

  @override
  String positionOf(String kind, String position, String count) {
    return '$kind $position of $count';
  }

  @override
  String get signInYtFirst => 'sign in to YouTube Music first';

  @override
  String get hideRiflay => 'Hide Riflay';

  @override
  String get showRiflay => 'Show Riflay';

  @override
  String get quitRiflay => 'Quit Riflay';

  @override
  String convertingToFlac(String title) {
    return 'Converting $title to FLAC…';
  }

  @override
  String convertingSongsToFlac(int count) {
    return 'Converting $count songs to FLAC…';
  }

  @override
  String convertedToFlac(String title) {
    return 'Converted $title to FLAC';
  }

  @override
  String alreadyLossless(String title) {
    return '$title is already lossless';
  }

  @override
  String couldntConvert(String title) {
    return 'Couldn\'t convert $title';
  }

  @override
  String convertedSongsToFlac(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Converted $count songs to FLAC',
      one: 'Converted 1 song to FLAC',
    );
    return '$_temp0';
  }

  @override
  String convertedSomeFailed(int count, int failed) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Converted $count songs to FLAC, $failed couldn\'t be converted',
      one: 'Converted 1 song to FLAC, $failed couldn\'t be converted',
    );
    return '$_temp0';
  }

  @override
  String get couldntConvertThese => 'Couldn\'t convert these songs';

  @override
  String addedSongsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'Added $count songs', one: 'Added 1 song');
    return '$_temp0';
  }

  @override
  String get allowReadMusic => 'Allow Riflay to read your music to add a folder';

  @override
  String get couldntAddMusic => 'Couldn\'t add that music';

  @override
  String get pressBackToExit => 'Press back again to exit';

  @override
  String get downloadingAudio => 'Downloading audio…';

  @override
  String get view => 'View';

  @override
  String get resizeSidebar => 'Resize sidebar';

  @override
  String get resizeSidePanel => 'Resize side panel';

  @override
  String get signInToSpotify => 'Sign in to Spotify';

  @override
  String get checkingSession => 'Checking the session…';

  @override
  String get spotifyHandlesSignIn => 'Spotify handles the sign-in. Riflay only reads your library.';

  @override
  String get couldntLoadSignIn => 'Couldn\'t load the sign-in page. Check your internet connection.';

  @override
  String get noSessionYet => 'No signed-in session on this page yet. Finish signing in above, then tap Try again.';

  @override
  String get couldntReadSpotifySession => 'Couldn\'t read the Spotify session. Try again.';

  @override
  String get signInToYt => 'Sign in to YouTube Music';

  @override
  String get googleHandlesSignIn => 'Google handles the sign-in. Riflay only keeps the session.';

  @override
  String get couldNotUseSignIn => 'Could not use that sign-in.';

  @override
  String get nothingIsPlaying => 'Nothing is playing';

  @override
  String get pressEscToExit => 'Press Esc to exit full screen';

  @override
  String get hideEqualizer => 'Hide equalizer';

  @override
  String get videoUnavailable => 'This video is unavailable.';

  @override
  String get videoUnplayable => 'This video can\'t be played (private, age-restricted or region-locked).';

  @override
  String get muxFailed =>
      'Couldn\'t combine the picture and the sound. Try again, or pick another size in Settings › Library & downloads › Downloads.';

  @override
  String get noInternetTryAgain => 'No internet connection. Try again.';

  @override
  String extAnsweredUnreadable(String name) {
    return '$name answered something unreadable';
  }

  @override
  String extStopped(String name) {
    return '$name was stopped';
  }

  @override
  String get flacBiggerOne =>
      'The FLAC file will be bigger than the original. The sound stays the same: FLAC can\'t bring back what the original already lost.';

  @override
  String get flacBiggerEach =>
      'Each FLAC file will be bigger than the original. The sound stays the same: FLAC can\'t bring back what the original already lost.';

  @override
  String get ownSongsStay => 'Songs you added yourself stay as they are, next to their FLAC.';

  @override
  String get quality => 'Quality';

  @override
  String get convert => 'Convert';

  @override
  String get betaMusixmatchBody => 'Look for word-by-word lyrics on Musixmatch when other sources have none.';

  @override
  String get betaVideoModeBody => 'Watch a song\'s music video in the player, in step with the song.';

  @override
  String get betaDirectUsbBody => 'Play straight to a USB DAC, past Android. Experimental.';

  @override
  String get mostPlayed => 'Most played';

  @override
  String get notPlayedForAWhile => 'Not played for a while';

  @override
  String get thisSong => 'this song';

  @override
  String get addMusicFolder => 'Add music folder';

  @override
  String couldntReachDevice(String device) {
    return 'Couldn\'t reach $device';
  }

  @override
  String get presetClassicNote => 'The player as it has always been, the cover pulsing with the music';

  @override
  String get presetStackedNote => 'The cover as the page, joined buttons, a thick bar and a wide Play button';

  @override
  String get presetKawaiiNote =>
      'The cover fades into the page, with plain icons, a wavy line and the volume behind a button';

  @override
  String get useThisColour => 'Use this colour';

  @override
  String get saturationBrightness => 'Saturation and brightness';

  @override
  String get hue => 'Hue';

  @override
  String wrapReadyTitle(String month) {
    return 'Your $month in music is ready';
  }

  @override
  String get monthlyWrap => 'Monthly Wrap';

  @override
  String get monthlyWrapChannel => 'Your month in music, once it is over';

  @override
  String get tapToSeeListened => 'Tap to see what you listened to.';

  @override
  String get vizOffBitPerfect => 'Off while Bit-perfect is on: nothing may change the sound on its way to your DAC';

  @override
  String get vizOffLightweight => 'Off in the Lightweight performance mode';

  @override
  String get vizOffReducedMotion => 'Off while Motion is reduced';

  @override
  String get vizHiddenDop => 'Hidden while this song plays as DSD over DoP';

  @override
  String get vizHiddenCasting => 'Hidden while playing on another device';

  @override
  String get minimize => 'Minimize';

  @override
  String get maximize => 'Maximize';

  @override
  String get windowRestore => 'Restore';

  @override
  String get whilePlaying => 'While playing';

  @override
  String get whileRiflayOpen => 'While Riflay is open';

  @override
  String couldntFindOnYt(String title) {
    return 'Couldn\'t find $title on YouTube Music';
  }

  @override
  String fromNamed(String name) {
    return 'From $name';
  }

  @override
  String extCouldntSearch(String name, String error) {
    return '$name couldn\'t search: $error';
  }

  @override
  String moreOptionsFor(String title) {
    return 'More options for $title';
  }

  @override
  String get removedFileNotDeleted => 'Removed from your library; the file couldn\'t be deleted.';

  @override
  String couldntPlayOnDevice(String title, String device) {
    return 'Couldn\'t play $title on $device';
  }

  @override
  String tallerAsWebm(String size) {
    return '$size is available as WebM.';
  }

  @override
  String get dsdUseDacVolume => 'DSD goes to your DAC as it is: use the DAC\'s volume';

  @override
  String get streamsOnline => 'YouTube Music: needs internet';

  @override
  String get playsOfflineHere => 'On this device: plays offline';

  @override
  String get showAll => 'Show all';

  @override
  String get offWhileDirect => 'Off while the sound goes straight to your DAC';

  @override
  String get ffmpegOneTime => 'Getting this ready: a one-time download (about 40 MB)…';

  @override
  String get matugenInvalid => 'Choose a valid Matugen JSON color file. Keeping the last working colors.';

  @override
  String get couldntSignInSpotify => 'Couldn\'t sign in to Spotify. Try again.';

  @override
  String get somethingWentWrongRetry => 'Something went wrong. Try again.';

  @override
  String get videoCouldntLoad => 'The video couldn\'t load, so the song plays on its own.';

  @override
  String get keySpace => 'Space';

  @override
  String get forward => 'Forward';

  @override
  String deletePlaylistBody(String name) {
    return '\"$name\" will be deleted. The songs stay in your library.';
  }

  @override
  String get lyricsOtherVersion =>
      'These lyrics are from a different recording of the same song (for example, the studio version instead of a live performance). The words may be correct, but their timing may not match. Open the lyrics menu > Adjust timing to shift them.';

  @override
  String get backToCurrentLine => 'Back to current line';

  @override
  String get signInWindowClosed => 'The sign-in window closed unexpectedly. Try again.';

  @override
  String get spotifySignInWindowClosed => 'The Spotify sign-in window closed unexpectedly. Try again.';

  @override
  String deviceDidntRespond(String device) {
    return '$device didn\'t respond';
  }

  @override
  String get theDevice => 'The device';

  @override
  String get ytReturnedNothing => 'YouTube Music returned nothing. Check your connection.';

  @override
  String get signInToChangeYt => 'Sign in with Google to change your YouTube Music library.';

  @override
  String get notYtInvite => 'That isn\'t a YouTube Music invite link.';

  @override
  String get noInternetCheck => 'No internet connection. Check it and try again.';

  @override
  String get ytDidntCreatePlaylist => 'YouTube Music did not create the playlist.';

  @override
  String get ytDidntTakeChange => 'YouTube Music didn\'t take that change. Try again.';

  @override
  String get ytDidntMakeInvite => 'YouTube Music did not make an invite link.';

  @override
  String notPlaylistLinkFrom(String services) {
    return 'That isn\'t a playlist link from $services.';
  }

  @override
  String get playlistEmptyOrPrivate => 'That playlist is empty, or it\'s private.';

  @override
  String get playlistMissingOrPrivate => 'That playlist doesn\'t exist, or it\'s private.';

  @override
  String get spotifyPageChanged => 'Spotify changed its page; this link can\'t be read right now.';

  @override
  String get unexpectedDeezerReply => 'Unexpected reply from Deezer.';

  @override
  String get lbTokenInvalid => 'ListenBrainz says this token isn\'t valid.';

  @override
  String get noneOfItsSongsOnYt => 'None of its songs are on YouTube Music.';

  @override
  String accentNamed(String name) {
    return '$name accent';
  }

  @override
  String frequencyHz(String hz) {
    return 'Frequency: ${hz}Hz';
  }

  @override
  String deletedNamed(String title) {
    return 'Deleted \"$title\"';
  }

  @override
  String spotifySongsNotFound(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$name: $count songs not found',
      one: '$name: 1 song not found',
    );
    return '$_temp0';
  }

  @override
  String get statsListened => 'listened';

  @override
  String statsSongsUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'songs', one: 'song');
    return '$_temp0';
  }

  @override
  String statsPlaysUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'plays', one: 'play');
    return '$_temp0';
  }

  @override
  String albumsPlural(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count albums', one: '1 album');
    return '$_temp0';
  }

  @override
  String listensWaiting(int count, String who) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$who. $count listens waiting to be sent.',
      one: '$who. 1 listen waiting to be sent.',
    );
    return '$_temp0';
  }

  @override
  String get sessionCodeHint => 'ABC123 or ABCDE-FGHJK';

  @override
  String get downloadedTools => 'Downloaded tools';

  @override
  String get deleteExecutables => 'Delete executables';

  @override
  String get downloadedToolsSubtitle => 'Find and delete FFmpeg and yt-dlp downloaded by Riflay.';

  @override
  String get downloadedToolsIntro =>
      'Only tools downloaded by Riflay are listed here. System-installed tools are managed separately.';

  @override
  String get noDownloadedTools => 'No downloaded executables found.';

  @override
  String get deleteAllExecutables => 'Delete all executables';

  @override
  String get deleteExecutablesQuestion => 'Delete downloaded executables?';

  @override
  String get deleteExecutablesBody =>
      'Riflay will download these tools again when needed. Your music and settings will stay.';

  @override
  String get executablesDeleted => 'Downloaded executables deleted.';

  @override
  String get couldntFindExecutables => 'Couldn\'t find downloaded executables. Try again.';

  @override
  String get couldntDeleteExecutables => 'Some executables couldn\'t be deleted. Try again.';

  @override
  String get presetLiquidStackedNote => 'Stacked, with Liquid Glass controls and glass tabs on phones';

  @override
  String get presetLiquidKawaiiNote => 'Kawaii, with Liquid Glass controls and glass tabs on phones';

  @override
  String get liquidGlassControls => 'Liquid Glass controls';

  @override
  String get liquidGlassControlsSubtitle => 'Frost the player’s buttons. Choose below which other parts are glass too.';

  @override
  String get glassSeekBar => 'Glass progress bar';

  @override
  String get glassTransport => 'Glass playback buttons';

  @override
  String get glassTransportSubtitle => 'Previous, play/pause and next';

  @override
  String get glassVolume => 'Glass volume';

  @override
  String get deviceSetupTitle => 'Set up Riflay for this computer';

  @override
  String get deviceSetupIntro =>
      'Riflay looked at this computer and picked the look that suits it: fewer effects for older computers and little memory, more for powerful ones. You can change it any time in Settings › Power & background.';

  @override
  String deviceSetupThreads(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count processor threads',
      one: '1 processor thread',
    );
    return '$_temp0';
  }

  @override
  String deviceSetupMemory(String size) {
    return '$size GB of memory';
  }

  @override
  String get deviceSetupLaptop => 'Laptop, runs on battery';

  @override
  String get deviceSetupDesktop => 'Desktop, no battery';

  @override
  String deviceSetupCost(String percent) {
    return 'About $percent% of the processor while a song plays';
  }

  @override
  String get deviceSetupRecommended => 'Recommended';

  @override
  String get deviceSetupContinue => 'Continue';

  @override
  String get deviceSetupKeep => 'Keep my settings';

  @override
  String get deviceSetupAgain => 'Check this computer';

  @override
  String get deviceSetupAgainNote => 'Looks at this computer again and suggests the look that suits it';

  @override
  String get sourceYoutubeMusic => 'YouTube Music';

  @override
  String get sourceSoundcloud => 'SoundCloud';

  @override
  String get streamsFromSoundcloud => 'SoundCloud: needs internet';

  @override
  String get soundcloudSearchSource => 'SoundCloud search';

  @override
  String get onSoundcloud => 'On SoundCloud';

  @override
  String get soundcloudSearchFailed => 'SoundCloud search failed. Check your connection.';

  @override
  String get noSoundcloudResults => 'No SoundCloud results.';

  @override
  String get soundcloudCantCast => 'SoundCloud songs play on this device only.';

  @override
  String get pasteYtOrScLink => 'Paste a YouTube or SoundCloud link.';

  @override
  String get soundcloudUnplayable => 'SoundCloud doesn\'t let this track play here.';

  @override
  String get soundcloudImportNote => 'SoundCloud tracks stream: play them now or save them to your library.';

  @override
  String soundcloudLine(int count, String author) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count tracks', one: '1 track');
    return 'SoundCloud • $author • $_temp0';
  }

  @override
  String saveCountToLibrary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Save $count to library',
      one: 'Save to library',
    );
    return '$_temp0';
  }

  @override
  String get soundcloudArtists => 'Artists on SoundCloud';

  @override
  String get soundcloudPlaylists => 'Playlists on SoundCloud';

  @override
  String get linkNotSupported => 'There\'s no YouTube or SoundCloud link in what was shared.';

  @override
  String searchOnSource(String source) {
    return 'Search on $source';
  }
}
