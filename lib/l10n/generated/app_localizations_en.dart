// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get temporaryRadio => 'Temporary radio playlist';

  @override
  String get showHomeToolbar => 'Show Home toolbar';

  @override
  String get manageLibrary => 'Manage library';

  @override
  String get lyricsDesktopBackground => 'Desktop lyrics background';

  @override
  String get lyricsDesktopBackgroundHint => 'Choose an album cover blur or a solid colour for the desktop lyrics page';

  @override
  String get lyricsBackgroundColor => 'Solid colour';

  @override
  String get lyricsBackgroundCover => 'Blurred cover';

  @override
  String get desktopSidebarStyle => 'Desktop sidebar';

  @override
  String get desktopSidebarStyleHint => 'Show the library list or a narrow rail with shortcuts';

  @override
  String get desktopSidebarLibrary => 'Library list';

  @override
  String get desktopSidebarShortcuts => 'Shortcut rail';

  @override
  String get desktopLayout => 'Desktop layout';

  @override
  String get desktopLayoutHint =>
      'Sets the sidebar, Home, Search and the player bar at once; each can still be changed below';

  @override
  String get desktopLayoutRail => 'Rail';

  @override
  String get fullHeightRail => 'Full-height rail';

  @override
  String get fullHeightRailHint => 'The shortcut rail also runs beside the player bar';

  @override
  String get greetingChip => 'Greeting chip';

  @override
  String get greetingChipHint => 'Shows Home\'s greeting small, with an icon for the time of day';

  @override
  String get sectionIcons => 'Section icons';

  @override
  String get sectionIconsHint => 'An icon before each shelf title on Home';

  @override
  String get detailedQuickAccess => 'Detailed quick access';

  @override
  String get detailedQuickAccessHint => 'Three columns, each tile with its subtitle and a menu';

  @override
  String get centeredSearch => 'Centered search';

  @override
  String get centeredSearchHint => 'The search box above the results, centered on the page';

  @override
  String get openItem => 'Open';

  @override
  String get coverGlass => 'Glass over the cover';

  @override
  String get coverGlassHint =>
      'Panels turn to see-through glass over the song\'s blurred cover (a random one before anything plays)';

  @override
  String get glassBackground => 'Background';

  @override
  String get glassBackgroundHint => 'What shows behind the glass';

  @override
  String get glassBackgroundPlaying => 'Playing cover';

  @override
  String get glassBackgroundRandom => 'Random cover';

  @override
  String get glassBackgroundImage => 'Your image';

  @override
  String get glassChooseImage => 'Choose an image';

  @override
  String get glassBlur => 'Blur the background';

  @override
  String get glassBlurHint => 'Off shows it sharp';

  @override
  String get setupLookTitle => 'Choose your look';

  @override
  String get setupLookIntro => 'Pick a layout and a player style. Everything can be changed later in Settings.';

  @override
  String get setupLayoutClassicNote => 'The library beside your pages, the search box on top';

  @override
  String get setupLayoutRailNote => 'A slim icon rail, search in the middle, a compact player';

  @override
  String get playerStyle => 'Player';

  @override
  String get layoutLabel => 'Layout';

  @override
  String get podcasts => 'Podcasts';

  @override
  String get podcastShows => 'Shows';

  @override
  String get olderEpisodes => 'Load older episodes';

  @override
  String get podcastEpisodes => 'Episodes';

  @override
  String get styles => 'Styles';

  @override
  String get setStyle => 'Set';

  @override
  String get expandLibrary => 'Expand library';

  @override
  String get restoreLibrarySidebar => 'Return to library sidebar';

  @override
  String get searchYourLibrary => 'Search your library';

  @override
  String get noLibraryMatches => 'No matching items in your library';

  @override
  String get homeStyle => 'Home layout';

  @override
  String get homeStyleClassic => 'Classic';

  @override
  String get homeStyleCarousel => 'Artwork carousel';

  @override
  String get customizeHome => 'Customize Home';

  @override
  String get speedDial => 'Speed dial';

  @override
  String get dailyMix => 'Daily Mix';

  @override
  String get dailyMixDescription => 'Recent favorites and more from those artists';

  @override
  String get madeForYou => 'Made for you';

  @override
  String artistMix(String artist) {
    return '$artist Mix';
  }

  @override
  String artistMixDescription(String artist) {
    return '$artist and what you play with them';
  }

  @override
  String get discoveryMix => 'Discovery Mix';

  @override
  String get discoveryMixDescription => 'Artists you haven\'t played lately';

  @override
  String get artistMusicVideos => 'Music videos';

  @override
  String get artistSoloSongs => 'Solo songs';

  @override
  String get artistCollaborations => 'Collaborations';

  @override
  String get audioSource => 'Audio source';

  @override
  String get audioSourceHint =>
      'Choose audio for this song. YouTube Music keeps its cover, lyrics and video. Your choice is remembered.';

  @override
  String get audioSourceAutomatic => 'Automatic (Smart Merge)';

  @override
  String get audioSourceSearch => 'Find a recording in your library…';

  @override
  String get audioSourceSearchMonochrome => 'Search Monochrome';

  @override
  String get audioSourceEmpty => 'No recordings found. Try another title or artist.';

  @override
  String get audioSourceFailed => 'Couldn\'t switch audio. Check the source and try again.';

  @override
  String get betaFeatures => 'Beta features';

  @override
  String get betaFeaturesSummary => 'Experimental features, off by default';

  @override
  String get betaAudioVisualizerBody =>
      'Experimental: audio bars and effects may not appear on every device. Off by default.';

  @override
  String get musicFolderAlreadyAdded => 'This folder is already in your library.';

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
  String get groupLookSummary => 'Theme, language and text, Now Playing, lyrics, pages';

  @override
  String get groupLibrary => 'Library & downloads';

  @override
  String get groupLibrarySummary => 'Music folders, downloads, listening history, backups';

  @override
  String get groupAccounts => 'Accounts & services';

  @override
  String get groupAccountsSummary => 'YouTube Music, Spotify, Last.fm, Discord, extensions';

  @override
  String get topicPlayback => 'Playback';

  @override
  String get topicPlaybackSummary => 'Play similar songs automatically and choose how songs change';

  @override
  String get topicDsp => 'Sound effects';

  @override
  String get topicDspSummary => 'Adjust bass and treble, even out volume, and change how sound fills the room';

  @override
  String get topicOutput => 'Output & quality';

  @override
  String get topicOutputSummary => 'Choose where sound plays and how Riflay sends it';

  @override
  String get topicAppearance => 'Theme & colours';

  @override
  String get topicAppearanceSummary => 'Theme, mode, accent colour, cover colours, frosted glass';

  @override
  String get topicLayout => 'Pages & navigation';

  @override
  String get topicLayoutSummary => 'Choose what appears on Home and how the app looks and moves';

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
  String get topicIntegrations => 'Discord';

  @override
  String get topicIntegrationsSummary => 'Show what you play on Discord';

  @override
  String get topicLyricsServices => 'Lyrics services';

  @override
  String get topicPlaybackSummaryWeb => 'Autoplay';

  @override
  String get topicIntegrationsSummaryWeb => 'A Better Lyrics key for word-by-word lyrics';

  @override
  String get settingsPower => 'Performance & power';

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
  String radioFrom(String title) {
    return '$title radio';
  }

  @override
  String get downloadForOffline => 'Download for offline';

  @override
  String get downloadAs => 'Download as…';

  @override
  String get downloadWithMv => 'Download with MV';

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
  String get settingsPowerSummaryTray => 'Performance mode, screen timeout, sleep, background playback and the tray';

  @override
  String get settingsPowerSummary => 'Performance mode, screen timeout, sleep and background playback';

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
  String get restoringBackup => 'Restoring the backup…';

  @override
  String get savingBackup => 'Saving the backup: settings, playlists and history…';

  @override
  String get howBackup3 => 'Riflay closes; open it again and your settings, playlists and history are back.';

  @override
  String get howBackup2 => 'On a new device, or after reinstalling, choose Restore a backup and pick that file.';

  @override
  String get howBackup1 =>
      'Save a backup, and keep the file somewhere safe: cloud storage, a USB drive or another computer.';

  @override
  String get howFolder3 => 'With Keep the library up to date on, songs you put there later are added too.';

  @override
  String get howFolder2 => 'Riflay adds the songs in it to your Library, ready to play offline.';

  @override
  String get howFolder1 => 'Choose Add a folder and pick the folder your music is in.';

  @override
  String get howImport3 =>
      'Riflay finds each song and puts the playlist in your Library. Changed your mind? Undo this import takes it back.';

  @override
  String get howImport2 => 'Paste it in the box above and press Import.';

  @override
  String get howImport1 =>
      'Copy the playlist\'s link in the app or site it\'s on (Spotify, Apple Music, Deezer, TIDAL or NetEase Cloud Music), or pick an M3U file.';

  @override
  String get howItWorks => 'How it works';

  @override
  String get commandLineSubtitle =>
      'Control Riflay from a terminal with riflay-cli, or play in one with riflay-tui. Run riflay-cli --help to see the commands.';

  @override
  String get commandLine => 'Command line';

  @override
  String get homeIntro =>
      'Your songs and YouTube Music in one place. Add music from this device, search, or sign in to start.';

  @override
  String get allSongs => 'All Songs';

  @override
  String get likedMusic => 'Liked music';

  @override
  String get recentlyPlayed => 'Recently played';

  @override
  String get removeFromRecentlyPlayed => 'Remove from Recently played';

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
  String get local => 'Local';

  @override
  String get folder => 'Folder';

  @override
  String get localEmpty => 'Music folders you add and songs you download show up here.';

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
  String get addAllToPlaylist => 'Add all songs to playlist';

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
  String get discordShowWhenIdle => 'Show while browsing or idle';

  @override
  String get discordBrowsingMusic => 'Browsing music';

  @override
  String get discordBrowsingLibrary => 'Exploring library';

  @override
  String get discordSearchingMusic => 'Searching for music';

  @override
  String get discordBrowsingDownloads => 'Viewing downloads';

  @override
  String get discordViewingQueue => 'Viewing queue';

  @override
  String get discordViewingLyrics => 'Viewing lyrics';

  @override
  String get discordInSettings => 'In settings';

  @override
  String get discordListeningTogether => 'Listening together';

  @override
  String get discordViewingStats => 'Viewing music stats';

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
  String get videoQuality => 'Video quality';

  @override
  String get videoQualitySubtitle =>
      'Auto picks what this device and your connection handle. A set resolution stays, even when the connection is slow.';

  @override
  String get videoQualityAuto => 'Auto';

  @override
  String videoQualityAutoNow(String height) {
    return 'Auto ($height)';
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
  String get presetCustomNote => 'Your own preset';

  @override
  String get yourPresets => 'Your presets';

  @override
  String get riflayPresets => 'Riflay presets';

  @override
  String get saveAsPreset => 'Save this look as a preset';

  @override
  String get saveAsPresetBody => 'Keeps the player as it is set up now, to put back in one tap.';

  @override
  String get presetName => 'Preset name';

  @override
  String get presetNameBuiltIn => 'Riflay already has a preset with this name';

  @override
  String get presetNameReplaces => 'Replaces your preset with this name';

  @override
  String get presetNameTaken => 'You already have a preset with this name';

  @override
  String get renamePreset => 'Rename preset';

  @override
  String get updatePresetToCurrent => 'Save this look into it';

  @override
  String deletePresetQuestion(String preset) {
    return 'Delete $preset?';
  }

  @override
  String get deletePresetBody => 'Your player stays as it is; only the preset goes.';

  @override
  String presetSaved(String preset) {
    return 'Saved $preset';
  }

  @override
  String get autoplayKeepGoing => 'When the queue ends, keep going with similar songs';

  @override
  String get gaplessPlayback => 'Gapless playback';

  @override
  String get gaplessPlaybackSubtitle =>
      'Songs play back to back without an added gap. Find the fade between songs below.';

  @override
  String get skipSilence => 'Skip silence';

  @override
  String get offWhileBitPerfect => 'Off while bit-perfect mode is on';

  @override
  String get skipSilenceSubtitle => 'Shortens silent parts of a track while keeping quiet music intact';

  @override
  String get off => 'Off';

  @override
  String get volumeLeveling => 'Keep song volumes similar';

  @override
  String get volumeLevelingSubtitle => 'Makes quiet and loud tracks play at a more consistent volume';

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
  String get crossfade => 'Fade between songs';

  @override
  String get crossfadeSubtitle =>
      'The next song starts as the current one fades out. Unavailable in bit-perfect and exclusive modes.';

  @override
  String get fadeLength => 'How long songs overlap';

  @override
  String get skipForAlbums => 'Keep album transitions as recorded';

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
  String get bitPerfectMode => 'Bit-perfect';

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
      'Sends audio directly to the USB DAC with effects off. Other sounds are muted on the DAC. Use the DAC\'s volume control.';

  @override
  String get bitPerfectMac =>
      'Turns off audio processing in Riflay. For unchanged output, set the volume to 100% and enable Exclusive mode.';

  @override
  String get bitPerfectWindows =>
      'Turns off audio processing in Riflay. For unchanged output, set the volume to 100% and enable Exclusive mode.';

  @override
  String get bitPerfectLinux =>
      'Turns off audio processing and reserves the DAC. Set the volume to 100% for unchanged output. Other apps use another output.';

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
  String get exclusiveMac => 'Gives Riflay sole use of the output. The DAC follows each song\'s sample rate.';

  @override
  String get exclusiveWindows => 'Gives Riflay sole use of the output. The Windows volume mixer can\'t control it.';

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
  String get bufferSubtitle =>
      'Increase this if sound crackles or cuts out. A larger buffer can make controls respond more slowly.';

  @override
  String get signalPathSubtitleExact => 'See exactly what happens to the song you\'re playing';

  @override
  String get directUsbIntro => 'Send sound straight to your USB audio device instead of through Android. Experimental.';

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
      'At the top of Now Playing and its sidebar. Adaptive shows it only when the song has a music video';

  @override
  String get adaptive => 'Adaptive';

  @override
  String get qualityBadge => 'Quality badge';

  @override
  String get qualityBadgeSubtitle => 'Choose where the phone player shows audio details such as FLAC or Opus.';

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
  String get lyricsOverLockScreen => 'Lyrics over the lock screen';

  @override
  String get lyricsOverLockScreenSubtitle =>
      'When the screen goes off while a song plays, its lyrics show over the lock screen until you unlock. Needs \"Display over other apps\"; on Xiaomi also \"Show on lock screen\" in the app\'s permissions';

  @override
  String get unlockPhone => 'Unlock';

  @override
  String get youreOffline =>
      'You\'re offline. Songs that aren\'t downloaded can\'t play until you connect to the internet; downloaded songs still play.';

  @override
  String get backOnline => 'Back online.';

  @override
  String get poster => 'Poster';

  @override
  String get makePoster => 'Make a poster';

  @override
  String get choosePhoto => 'Choose a photo';

  @override
  String get posterPhoto => 'Photo';

  @override
  String get posterAddSong => 'Add song';

  @override
  String get posterDepth => 'Depth';

  @override
  String get posterLight => 'Light';

  @override
  String get posterDark => 'Dark';

  @override
  String get posterGlass => 'Frosted glass';

  @override
  String get posterCoverColour => 'Cover colour';

  @override
  String get posterSize => 'Size';

  @override
  String get posterRotate => 'Rotate';

  @override
  String get posterTilt => 'Tilt';

  @override
  String get posterTurn => 'Turn';

  @override
  String get posterThickness => 'Thickness';

  @override
  String get posterProgress => 'Progress';

  @override
  String get posterFindingYou => 'Finding you in the photo…';

  @override
  String get posterNoCutout => 'Couldn\'t find a person in this photo. The cards stay over it.';

  @override
  String get posterEmpty => 'Add a photo and some songs to start';

  @override
  String get posterHint => 'Drag a card to move it, pinch to resize and turn it, tap it for more';

  @override
  String get posterCaption => 'My songs, on Riflay';

  @override
  String get audioLab => 'Audio Lab';

  @override
  String get firewallBlocked =>
      'Windows Firewall is blocking Riflay, so friends on your Wi-Fi can\'t find or join this session. Refused it by mistake? Riflay can ask again.';

  @override
  String get firewallAllow => 'Allow through the firewall';

  @override
  String get firewallAllowed => 'Riflay is allowed through the firewall. Friends on your Wi-Fi can join now.';

  @override
  String get firewallStillBlocked =>
      'Still blocked: Windows asks for an administrator\'s permission to change this. Try again and choose Yes.';

  @override
  String get expandedMode => 'Mode';

  @override
  String get modeCover => 'Cover';

  @override
  String get modeVinyl => 'Vinyl';

  @override
  String get modeAmbient => 'Clock';

  @override
  String get modeHifi => 'Hi-Fi';

  @override
  String get labResponse => 'Frequency response';

  @override
  String get labTargetHeadphone => 'Use another headphone as the target';

  @override
  String get labNone => 'No target (equalizer only)';

  @override
  String get labFitTarget => 'Fit to target';

  @override
  String get labEqOn => 'EQ on';

  @override
  String get labExport => 'Copy as ParametricEQ.txt';

  @override
  String get labCopied => 'EQ copied as ParametricEQ.txt';

  @override
  String get labFrequency => 'Frequency';

  @override
  String get labGain => 'Gain';

  @override
  String get labBass => 'Bass';

  @override
  String get labTilt => 'Tilt';

  @override
  String get labDragHint =>
      'Drag a band\'s point on the graph: sideways for its frequency, up and down for its gain. Ctrl and the mouse wheel narrow or widen it.';

  @override
  String get audioLabTile => 'See the response graph and tune to Harman or other targets';

  @override
  String get audioLabSubtitle =>
      'Your headphone\'s measured response set against a target curve, and the equalizer fitted to match it.';

  @override
  String get labHeadphone => 'Headphone';

  @override
  String get labTarget => 'Target';

  @override
  String get labSourceFile => 'File';

  @override
  String get labPick => 'Pick a headphone';

  @override
  String get labChooseFile => 'Choose a file (.txt, .csv)';

  @override
  String get labSite => 'squig.link site';

  @override
  String get labWithEq => 'With EQ';

  @override
  String labGap(String db) {
    return 'After EQ it stays within $db dB of the target, up to 10 kHz.';
  }

  @override
  String labApplied(String name) {
    return 'Equalizer set: $name';
  }

  @override
  String get labLoadFailed => 'Couldn\'t load it. Check the address or your connection.';

  @override
  String get labKindMismatch => 'This target is made for a different kind of headphone (in-ear or over-ear).';

  @override
  String get labCredits =>
      'Measurements and targets from AutoEQ (MIT) and the squig.link site you pick, fetched only when picked. Each measurement belongs to whoever measured it.';

  @override
  String get posterDecor => 'Decor';

  @override
  String get posterStepDecor => 'Tap to add one. On the poster, drag it, pinch to size it, turn it with two fingers.';

  @override
  String get posterDecoration => 'Decoration';

  @override
  String get posterAddText => 'Add text';

  @override
  String get posterEditText => 'Edit text';

  @override
  String get posterTextHint => 'Your words';

  @override
  String get posterColour => 'Colour';

  @override
  String get posterInFront => 'Put in front of you';

  @override
  String get posterBehind => 'Put behind you';

  @override
  String get posterCutoutModel => 'Cut-out';

  @override
  String get posterModelBuiltIn => 'Built-in';

  @override
  String get posterModelBuiltInHint => 'Small and quick, on the device from the start.';

  @override
  String get posterModelModnetHint => 'Made for people: finer hair and edges.';

  @override
  String get posterModelRmbgHint => 'BRIA\'s RMBG: the sharpest edges. Non-commercial use only.';

  @override
  String posterModelDownloadTitle(String name) {
    return 'Download $name?';
  }

  @override
  String posterModelDownloadBody(int size) {
    return 'About $size MB, downloaded once and kept on this device. Your photos never leave it.';
  }

  @override
  String get posterModelRmbgLicence =>
      'RMBG-1.4 is BRIA\'s model, licensed for non-commercial use only. By downloading it you accept its licence.';

  @override
  String get posterReadLicence => 'Read the licence';

  @override
  String get posterDownload => 'Download';

  @override
  String get posterAcceptDownload => 'Accept and download';

  @override
  String posterModelDownloading(String name) {
    return 'Downloading $name…';
  }

  @override
  String get posterModelFailed => 'Couldn\'t download the model. Try again.';

  @override
  String posterPickAtLeast(int count) {
    return 'Pick at least $count songs';
  }

  @override
  String posterPickSongs(int count, int max) {
    return 'Pick songs ($count/$max)';
  }

  @override
  String get posterReplaceSong => 'Change song';

  @override
  String get posterSectionImage => 'Image';

  @override
  String get posterSectionLight => 'Light';

  @override
  String get posterSectionColor => 'Color';

  @override
  String get posterSectionEffects => 'Effects';

  @override
  String get posterSectionTransform => 'Transform';

  @override
  String get posterSectionCard => 'Card';

  @override
  String get posterWatermarkHint => 'The Riflay mark at the foot of the poster';

  @override
  String get posterLock => 'Lock';

  @override
  String get posterUnlock => 'Unlock';

  @override
  String get posterLockedHint => 'Locked: unlock it in Layers to change it';

  @override
  String get posterResume => 'Go on with your last poster?';

  @override
  String get posterContinue => 'Continue';

  @override
  String get posterStartNew => 'Start new';

  @override
  String get posterLeaveTitle => 'Leave the poster?';

  @override
  String get posterLeaveBody => 'Your edits are kept as a draft. Open Poster again to go on with it.';

  @override
  String get posterKeepEditing => 'Keep editing';

  @override
  String get posterLeave => 'Leave';

  @override
  String get redo => 'Redo';

  @override
  String get posterBrightness => 'Brightness';

  @override
  String get posterContrast => 'Contrast';

  @override
  String get posterSaturation => 'Saturation';

  @override
  String get posterWarmth => 'Warmth';

  @override
  String get posterFade => 'Fade';

  @override
  String get posterVignette => 'Vignette';

  @override
  String get posterFilterOriginal => 'Original';

  @override
  String get posterFilterVivid => 'Vivid';

  @override
  String get posterFilterWarm => 'Warm';

  @override
  String get posterFilterCool => 'Cool';

  @override
  String get posterFilterMono => 'Mono';

  @override
  String get posterFilterFaded => 'Faded';

  @override
  String get posterFilterFilm => 'Film';

  @override
  String get posterSongs => 'Songs';

  @override
  String get posterLayout => 'Layout';

  @override
  String get posterStepPhoto => 'Start with a photo of you. Riflay finds you in it, so cards can stand behind you.';

  @override
  String get posterFoundYou => 'Found you. Cards can now go behind you (Layers).';

  @override
  String get posterStepSongs => 'The songs on your poster. Add up to 8.';

  @override
  String get posterStepLayout => 'Pick a layout: every card is placed in one tap.';

  @override
  String get posterStepLayoutEmpty => 'Add a song first, then pick a layout.';

  @override
  String get posterStepLayers => 'Tap a layer to pick it. Drag the handle to change what is in front.';

  @override
  String get posterStepCanvas => 'The poster\'s size, and the Riflay mark at its foot.';

  @override
  String get posterCutOut => 'Cut out of the photo';

  @override
  String get posterBackground => 'Background';

  @override
  String get posterHide => 'Hide';

  @override
  String get posterShow => 'Show';

  @override
  String get posterOpacity => 'Opacity';

  @override
  String get posterDuplicate => 'Duplicate';

  @override
  String get posterPosition => 'Position';

  @override
  String get posterLook => 'Look';

  @override
  String get posterMore => 'More';

  @override
  String get posterFlat => 'Make flat';

  @override
  String get posterFit => 'Fit';

  @override
  String get posterPresets => 'Presets';

  @override
  String get posterWatermark => 'Watermark';

  @override
  String get posterPresetScatter => 'Scatter';

  @override
  String get posterPresetStack => 'Stack';

  @override
  String get posterPresetGrid => 'Grid';

  @override
  String get posterPresetFan => 'Fan';

  @override
  String get posterPresetSpotlight => 'Spotlight';

  @override
  String get posterPresetCascade => 'Cascade';

  @override
  String get posterPresetFloat => 'Float 3D';

  @override
  String get posterCard => 'Song card';

  @override
  String get posterYou => 'You';

  @override
  String get posterYouNone => 'Add a photo of yourself to cut you out';

  @override
  String get posterYouHint => 'Cut out of the photo. Cards above you stand in front, cards below stand behind';

  @override
  String get posterPhotoNone => 'No photo yet';

  @override
  String get posterPhotoHint => 'Drag the photo to move it, pinch or slide to zoom';

  @override
  String get posterLayers => 'Layers';

  @override
  String get posterForward => 'Bring forward';

  @override
  String get posterBackward => 'Send backward';

  @override
  String get posterZoom => 'Zoom';

  @override
  String get posterReplacePhoto => 'Replace';

  @override
  String get posterCanvas => 'Canvas';

  @override
  String get posterShapeStory => 'Story';

  @override
  String get posterShapePortrait => 'Instagram post';

  @override
  String get posterShapeSquare => 'Square';

  @override
  String get posterShapeLandscape => 'Landscape';

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
  String get desktopMiniPlayer => 'Desktop mini player';

  @override
  String get desktopMiniPlayerSubtitle =>
      'The small player that stays on top: a window with the cover, or a dynamic island at the top of the screen that opens when you point at it';

  @override
  String get miniStyleWindow => 'Window';

  @override
  String get miniStyleIsland => 'Dynamic island';

  @override
  String get kwDesktopMini => 'mini player, island, dynamic island, always on top, picture in picture, small window';

  @override
  String get miniBackToApp => 'Back to the full window';

  @override
  String get miniSwitchToIsland => 'Switch to the dynamic island';

  @override
  String get miniSwitchToWindow => 'Switch to the mini window';

  @override
  String get islandPlacement => 'Island placement';

  @override
  String get islandPlacementSubtitle =>
      'Floating sits a little below the top of the screen and can be dragged anywhere; Docked sticks to the top edge like a notch and slides sideways';

  @override
  String get islandFloating => 'Floating';

  @override
  String get islandDocked => 'Docked';

  @override
  String get islandBars => 'Island bars';

  @override
  String get islandBarsSubtitle => 'Following the music works even with the audio visualizer off';

  @override
  String get islandBarsMusic => 'Follow the music';

  @override
  String get islandBarsAnimated => 'Animated';

  @override
  String get islandOpens => 'Island opens';

  @override
  String get islandOpenHover => 'On hover';

  @override
  String get islandOpenClick => 'On click';

  @override
  String get islandWidth => 'Island width';

  @override
  String get islandWidthCompact => 'Compact';

  @override
  String get islandWidthNormal => 'Normal';

  @override
  String get islandWidthWide => 'Wide';

  @override
  String get islandColor => 'Island colour';

  @override
  String get islandColorBlack => 'Black';

  @override
  String get islandColorTinted => 'Cover tint';

  @override
  String get islandColorCover => 'Cover colour';

  @override
  String get miniOnTop => 'Mini player stays on top';

  @override
  String get miniOnTopSubtitle => 'Above other windows, for the island and the mini window';

  @override
  String get miniShows => 'In the mini window and the open island';

  @override
  String get miniShowVolume => 'Volume';

  @override
  String get miniShowShuffleRepeat => 'Shuffle and repeat';

  @override
  String get miniShowQuality => 'Quality badge';

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
  String get spMeasureOutput => 'Measure output';

  @override
  String get spMeasureOutputBody =>
      'Records 10 s of what Riflay sends to PipeWire and compares it, sample by sample, with the song itself. The recording is digital: it shows whether Riflay and the system mixer changed the samples, not what your DAC makes of them.';

  @override
  String get spMeasure => 'Measure';

  @override
  String get spMeasureAgain => 'Measure again';

  @override
  String spMeasureRecording(String seconds, String total) {
    return 'Recording… $seconds / $total s';
  }

  @override
  String get spMeasureDecoding => 'Decoding the song…';

  @override
  String get spMeasureComparing => 'Comparing…';

  @override
  String spNotBitPerfectShare(String share) {
    return 'NOT Bit Perfect $share';
  }

  @override
  String get spGain => 'Gain';

  @override
  String get spPhaseOffset => 'Phase Offset';

  @override
  String get spDifferenceRms => 'Difference (rms)';

  @override
  String get spCorrelatedNull => 'Correlated Null';

  @override
  String get spClockDrift => 'Clock Drift';

  @override
  String get spFitQuality => 'Fit Quality';

  @override
  String get spFitExcellent => 'Excellent';

  @override
  String get spFitGood => 'Good';

  @override
  String get spFitPoor => 'Poor';

  @override
  String spMeasuredAt(String seconds, String rate) {
    return '$seconds s compared at $rate, 32-bit float from PipeWire';
  }

  @override
  String get spMeasureNoRecorder => 'PipeWire\'s pw-record isn\'t installed.';

  @override
  String get spMeasureNoStream => 'None of Riflay\'s sound is playing through PipeWire. Play the song and try again.';

  @override
  String get spMeasureTwoStreams => 'Two songs are fading into each other. Try again in a moment.';

  @override
  String get spMeasureSongMoved => 'The song paused, moved or changed while recording. Let it play and try again.';

  @override
  String get spMeasureNoSource => 'Couldn\'t decode the song again to compare.';

  @override
  String get spMeasureNoMatch => 'What came out didn\'t line up with the song (silence, or something else playing).';

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
  String get adjustVideoTiming => 'Adjust video timing';

  @override
  String get adjustVideoTimingBody =>
      'Move the video earlier or later until it matches the song and lyrics. Each tap adjusts it by 0.5 seconds. Reset restores automatic timing.';

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
  String get downloadsFolderUnusable =>
      'Riflay can\'t save downloads in that folder. On Android, choose one inside Download or Documents.';

  @override
  String get openFolder => 'Open folder';

  @override
  String get ytDlp => 'YouTube downloader (yt-dlp)';

  @override
  String get ytDlpMissing => 'Not available. Install it (e.g. pacman -S yt-dlp) for YouTube downloads.';

  @override
  String get installed => 'Installed';

  @override
  String get noExtensionsYet => 'No extensions yet';

  @override
  String get available => 'Available';

  @override
  String get reading => 'Reading…';

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
    return 'Couldn\'t play $title. Check your internet connection, or that the file is still there, then try again.';
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
  String get couldntSaveChanges =>
      'Couldn\'t save the changes. Check there\'s free space on this device, then try again.';

  @override
  String get couldntSaveTags =>
      'Couldn\'t save the tags. Check that the file isn\'t read-only or open in another app, then try again.';

  @override
  String get chooseCoverArt => 'Choose cover art';

  @override
  String get noCoverFound => 'No cover found for this album';

  @override
  String get couldntReachCoverArchive => 'Couldn\'t reach the Cover Art Archive';

  @override
  String get changeCover => 'Change cover';

  @override
  String get playlistCover => 'Playlist cover';

  @override
  String get removeCover => 'Remove cover';

  @override
  String get playlistCoverUpdated => 'Cover updated';

  @override
  String get playlistCoverRemoved => 'Cover removed';

  @override
  String get couldntUsePicture => 'That picture couldn\'t be used';

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
  String get closeToTray => 'Minimize to tray';

  @override
  String get closeSettings => 'Close settings';

  @override
  String get closeWindow => 'Close window';

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
  String get pastePlaylistLink =>
      'Paste a playlist link from Spotify, Apple Music, Deezer, TIDAL or NetEase Cloud Music.';

  @override
  String get becomesYtPlaylist => 'It becomes a playlist in your YouTube Music library.';

  @override
  String get becomesRiflayPlaylist => 'It becomes a Riflay playlist of YouTube Music songs.';

  @override
  String get playlistLink => 'Playlist link';

  @override
  String get notAPlaylistLink =>
      'That isn\'t a Spotify, Apple Music, Deezer, TIDAL or NetEase Cloud Music playlist link';

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
  String get streakReminder => 'Streak reminder';

  @override
  String get streakReminderSubtitle =>
      'Once a day, if I haven\'t played anything yet, remind me before my streak ends.';

  @override
  String get streakReminderTime => 'Remind me at';

  @override
  String get streakReminderChannel => 'A daily nudge before your listening streak ends';

  @override
  String streakReminderTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Your $count-day streak ends at midnight',
      one: 'Your 1-day streak ends at midnight',
    );
    return '$_temp0';
  }

  @override
  String get streakReminderBody => 'Play a song for 30 seconds to keep it going.';

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
  String get windowsUpdateNote =>
      'Riflay will close and reopen after the update. Your library and settings will stay in place.';

  @override
  String get windowsUpdateRestart => 'Installing the update. Riflay will reopen when it’s ready…';

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
  String get reinstallLatestVersion => 'Reinstall latest version';

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
  String get setupWelcome => 'Welcome to Riflay';

  @override
  String get setupImportHint => 'Bring playlists from a link or a local M3U file.';

  @override
  String get importM3u => 'Import M3U file';

  @override
  String get m3uReadFailed => 'Could not read any local music files from this playlist.';

  @override
  String get coverCollage => 'Four-cover collage';

  @override
  String get dragCover => 'Drag to set the focal point';

  @override
  String get playlistTools => 'Playlist tools';

  @override
  String get copyThrough => 'Duplicate through song';

  @override
  String get trackNote => 'Playlist song note';

  @override
  String get compareLists => 'Compare playlists';

  @override
  String get inBoth => 'In both playlists';

  @override
  String get exportRelative => 'Export local songs as relative M3U';

  @override
  String get songBookmarks => 'Song bookmarks';

  @override
  String get addBookmark => 'Name this position';

  @override
  String get inPlaylists => 'Playlists containing this song';

  @override
  String get copyAtTime => 'Copy link at current time';

  @override
  String get insertAfter => 'Move after song';

  @override
  String get skipOnce => 'Skip once';

  @override
  String get stopAfter => 'Stop after this song';

  @override
  String get regenerateQueue => 'Regenerate upcoming queue';

  @override
  String get clearUpcomingQueue => 'Clear upcoming queue';

  @override
  String get clearUpcomingQueueBody => 'All upcoming songs will be removed. The current song stays in the player.';

  @override
  String get clearUpcomingQueueQuestion => 'Clear upcoming queue?';

  @override
  String get clearQueueFailed => 'Could not clear the queue. Try again.';

  @override
  String get queueRefreshFailed => 'Could not refresh the queue. Try again.';

  @override
  String get replaceFolder => 'Replace missing folder';

  @override
  String get replaceMatch => 'Replace a matched song';

  @override
  String get retryMissing => 'Retry unmatched songs';

  @override
  String get copyMissing => 'Copy unmatched songs';

  @override
  String get mergePlaylist => 'Save into playlist';

  @override
  String get undoImport => 'Undo this import';

  @override
  String get undoImportQuestion => 'Undo this import?';

  @override
  String get duplicatesCount => 'Duplicates';

  @override
  String get glassTint => 'Bottom bar Liquid Glass tint';

  @override
  String get followTheme => 'Follow theme';

  @override
  String get lyricsTarget => 'Lyrics translation language';

  @override
  String get systemLanguage => 'Device language';

  @override
  String get languageCode => 'Other language code';

  @override
  String get privacySearch => 'Privacy';

  @override
  String get clearSearches => 'Clear search history';

  @override
  String get clearSearchesBody => 'Remove all searches saved on this device?';

  @override
  String get musicCacheLimit => 'Music cache limit';

  @override
  String get videoCacheLimit => 'Video cache limit';

  @override
  String get imageCacheLimit => 'Image cache limit';

  @override
  String get offlineReady => 'Available offline';

  @override
  String get downloadMissing => 'Download remaining songs';

  @override
  String get spaceEstimate => 'Estimated size';

  @override
  String get availableSpace => 'Available disk space';

  @override
  String get deleteAllDownloads => 'Delete all downloaded songs';

  @override
  String get importPlaylistFile => 'Import M3U or CSV file';

  @override
  String get csvReadFailed => 'Use a CSV with title and artist columns.';

  @override
  String get loudnessTarget => 'Volume level to aim for';

  @override
  String get defaultLibraryFilter => 'Default library filter';

  @override
  String get startupTab => 'Startup tab';

  @override
  String get swipeDistance => 'Track swipe distance';

  @override
  String get varispeed => 'Change pitch with playback speed';

  @override
  String get streamQuality => 'YouTube Music streaming quality';

  @override
  String get streamSaver => 'Save data on YouTube Music';

  @override
  String get keepHistoryFor => 'Keep listening history for';

  @override
  String get noTimeLimit => 'No time limit';

  @override
  String get trimHistoryNotice => 'Older plays outside this period will be removed.';

  @override
  String daysCount(int days) {
    return '$days days';
  }

  @override
  String get storageCache => 'Storage & cache';

  @override
  String get storageCacheHint => 'Space for streamed music, videos and artwork';

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
  String get sourceMonochrome => 'Monochrome';

  @override
  String get spotiflacExtensions => 'SpotiFLAC extensions';

  @override
  String get spotiflacAbout =>
      'Install provider plugins from .sflx files or an extension repository. Enable a provider to use it in Search.';

  @override
  String get spotiflacDownloadOnly =>
      'SpotiFLAC is a download-only source, not a streaming source. Download songs first to play them from your library.';

  @override
  String get monochromePreviewSubtitle =>
      'Show it as a source on Search. Its songs play a 1-minute preview; download them to play them in full.';

  @override
  String get monochromePreviewEnded => 'Preview ended. Download the song to play it in full.';

  @override
  String get retryingDownload => 'Connection interrupted. Retrying…';

  @override
  String get qualityNotKnown => 'Quality unavailable';

  @override
  String get spotiflacMetadataCapability => 'Metadata';

  @override
  String get spotiflacMetadataOnly =>
      'Provides song information, not audio downloads. Choose another enabled download provider to save songs.';

  @override
  String get spotiflacAudioProvider => 'Provides audio downloads. Its quality settings apply to the downloaded file.';

  @override
  String get spotiflacLyricsOnly => 'Provides lyrics for songs; it does not provide audio downloads.';

  @override
  String get spotiflacNeedsDownloader =>
      'Enable a download provider in SpotiFLAC settings to save songs from this catalogue.';

  @override
  String get importSflx => 'Import .sflx';

  @override
  String get spotiflacRepository => 'Extension repository URL';

  @override
  String get spotiflacLoadRepository => 'Browse repository';

  @override
  String get spotiflacSettings => 'Provider settings';

  @override
  String get spotiflacNoSettings => 'This provider has no settings.';

  @override
  String get spotiflacInvalidSetting => 'Enter a valid value.';

  @override
  String get spotiflacFailed => 'Couldn\'t complete the extension request. Check the provider settings and try again.';

  @override
  String get spotiflacEmpty => 'No provider plugins installed yet.';

  @override
  String get spotiflacQuality => 'Provider download quality';

  @override
  String get spotiflacLocalNetwork => 'Allow plugins to connect to local servers';

  @override
  String get spotiflacOriginal => 'Original quality';

  @override
  String get spotiflacCantCast => 'Download this song before casting.';

  @override
  String noSourceResults(String source) {
    return 'No $source results.';
  }

  @override
  String enableSourceForSearch(String source) {
    return 'Enable $source in Music sources to search here.';
  }

  @override
  String get sourceSearchToggleSubtitle => 'Show as a source filter on Search; search this service when selected';

  @override
  String get noMonochromeResults => 'No Monochrome results.';

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
  String get spotifyCantCast => 'Spotify songs play on this device only.';

  @override
  String get spotifyTapToPlay => 'Tap a playlist or album to play it here with Spotify Premium. Tick the ones to copy.';

  @override
  String get spotifyCantPlay =>
      'Couldn\'t play this song. Spotify plays songs only with Premium, and it wasn\'t found on YouTube Music.';

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

  @override
  String get searchSettings => 'Search settings';

  @override
  String searchSettingsNone(String query) {
    return 'No settings match $query';
  }

  @override
  String get settingsPreview => 'Preview';

  @override
  String get settingsPreviewHint => 'Tap a setting that changes the look to see it here';

  @override
  String get closePreview => 'Close preview';

  @override
  String get homeSectionsOption => 'Home sections';

  @override
  String get previewLyrics =>
      'The line before this one\nThe line sung right now\nThe next line comes after\nAnd one more after that';

  @override
  String get kwAutoplay => 'radio, continue, keep playing, similar songs, endless';

  @override
  String get kwGapless => 'seamless, no gap, live album, continuous';

  @override
  String get kwSkipSilence => 'silence, quiet parts, trim';

  @override
  String get kwEqualizer => 'eq, bass, treble, tone, preset, autoeq, iem, headphone profile';

  @override
  String get kwVolumeLeveling => 'replaygain, normalize, loudness, same volume';

  @override
  String get kwCrossfade => 'fade, blend, transition, mix songs';

  @override
  String get kwFadeLength => 'fade time, seconds, duration';

  @override
  String get kwVirtualSpeakers => 'spatial, surround, 3d, hrtf, headphones, dolby atmos';

  @override
  String get kwCrossfeed => 'headphones, stereo width, bs2b';

  @override
  String get kwMono => 'one channel, single ear, accessibility';

  @override
  String get kwAudioPlugins => 'vst, lv2, carla, effects';

  @override
  String get kwRoomCorrection => 'convolution, impulse response, ir, speakers';

  @override
  String get kwSignalPath => 'quality, bit depth, what plays, chain';

  @override
  String get kwOutputDevice => 'speaker, headphones, dac, sound card, bluetooth';

  @override
  String get kwBitPerfect => 'hi-res, lossless, untouched, audiophile';

  @override
  String get kwDirectUsb => 'usb dac, android, bit-perfect';

  @override
  String get kwNativeDsd => 'dsd, dop, sacd';

  @override
  String get kwExclusiveMode => 'wasapi, exclusive, hog mode';

  @override
  String get kwSampleRate => 'hz, 44.1, 48, 96, resample';

  @override
  String get kwBuffer => 'latency, stutter, crackle, dropouts';

  @override
  String get kwLanguage => 'english, indonesian, japanese, translation';

  @override
  String get kwTheme => 'colors, dark mode, light mode, catppuccin, nord, dracula';

  @override
  String get kwColours => 'color, colour, custom, palette';

  @override
  String get kwMode => 'dark, light, system, night';

  @override
  String get kwCoverColours => 'dynamic, artwork colours, tint';

  @override
  String get kwHighContrast => 'contrast, readability, accessibility';

  @override
  String get kwTextSize => 'font size, bigger text, zoom, scale';

  @override
  String get kwFont => 'typeface, font family';

  @override
  String get kwPlayerBackground => 'now playing, blurred cover, black, colour';

  @override
  String get kwFrostedGlass => 'blur, transparent, acrylic, mica';

  @override
  String get kwOpacity => 'transparency, see through';

  @override
  String get kwPresets => 'whole look, style, liquid, kawaii';

  @override
  String get kwCover => 'artwork, album art, flower, square';

  @override
  String get kwPlayerHeader => 'top bar, playing from, header';

  @override
  String get kwTitleButtons => 'like, share, heart, more';

  @override
  String get kwQualityBadge => 'hi-res, flac, lossless, badge, bitrate';

  @override
  String get kwMusicVideo => 'video, mv, clip';

  @override
  String get kwVideoDecoding => 'hardware, gpu, cpu, decoder';

  @override
  String get kwVideoQuality => 'resolution, quality, 1080p, 720p, 480p, hd, video';

  @override
  String get kwLiquidGlass => 'glass, ios, frosted controls';

  @override
  String get kwSeekBar => 'progress, timeline, wavy, scrubber';

  @override
  String get kwTimeLeft => 'remaining, countdown, duration';

  @override
  String get kwTransport => 'play, pause, next, previous, buttons';

  @override
  String get kwVolumeSlider => 'volume, loudness slider';

  @override
  String get kwBottomButtons => 'queue, lyrics, chips, row';

  @override
  String get kwLyrics => 'words, lyric, karaoke';

  @override
  String get kwKaraoke => 'word by word, sing along, timing';

  @override
  String get kwLyricsSize => 'lyrics font, bigger lyrics';

  @override
  String get kwLyricsAlign => 'left, centre, center, align';

  @override
  String get kwVisualizer => 'spectrum, bars, wave, rings, audio reactive';

  @override
  String get kwAlbumHeader => 'album page, playlist page, header';

  @override
  String get kwPlayingRow => 'current song, highlight, equalizer icon';

  @override
  String get kwHomeSections => 'home, shelves, reorder, hide';

  @override
  String get kwMiniPlayer => 'mini, small player, bottom player';

  @override
  String get kwTabBar => 'navigation, bottom bar, tabs, dock, glass';

  @override
  String get kwDesktopBar => 'player bar, bottom bar, computer';

  @override
  String get kwCorners => 'rounded, radius, roundness, square edges';

  @override
  String get kwDensity => 'spacing, compact, comfortable, padding';

  @override
  String get kwCoverSize => 'grid, cards, tiles, thumbnails';

  @override
  String get kwMotion => 'animation, transitions, reduce motion, speed';

  @override
  String get kwWindowButtons => 'title bar, close, minimize, maximize';

  @override
  String get kwPerformance => 'battery, cpu, lightweight, balanced, heavy, speed';

  @override
  String get kwScreen => 'display, awake, screen timeout';

  @override
  String get kwSleep => 'standby, suspend, awake';

  @override
  String get kwTray => 'system tray, background, close button';

  @override
  String get kwBattery => 'background, screen off, battery optimization';

  @override
  String get kwMusicFolders => 'scan, watch, folders, library, rescan';

  @override
  String get kwDuplicates => 'duplicates, same song twice, cleanup';

  @override
  String get kwDownloadFormat => 'mp3, flac, opus, m4a, video, audio';

  @override
  String get kwDownloadQuality => 'bitrate, kbps, bit depth, quality';

  @override
  String get kwMobileData => 'cellular, data, wifi only';

  @override
  String get kwDownloadsFolder => 'save location, where, path';

  @override
  String get kwYtDlp => 'ffmpeg, tools, executables, downloader';

  @override
  String get kwHistory => 'listening history, privacy, recently played';

  @override
  String get kwWrap => 'stats, wrapped, year in review, top songs';

  @override
  String get kwBackup => 'export, import, restore, transfer, save';

  @override
  String get kwYoutubeAccount => 'google, sign in, login, account';

  @override
  String get kwScrobbling => 'scrobble, last.fm, listenbrainz, profile';

  @override
  String get kwLyricsServices => 'musixmatch, better lyrics, api key';

  @override
  String get kwDiscord => 'rich presence, status, activity';

  @override
  String get kwUpdates => 'new version, upgrade, update';

  @override
  String get kwVersion => 'about, licence, license, open source';

  @override
  String get discordAppButton => '\"Download Riflay\" button';

  @override
  String get topicText => 'Language & text';

  @override
  String get topicTextSummary => 'Language, text size, font';

  @override
  String get topicNowPlaying => 'Now Playing';

  @override
  String get topicNowPlayingSummary => 'Cover, controls, progress bar, Liquid Glass';

  @override
  String get topicLyrics => 'Lyrics';

  @override
  String get topicLyricsSummary => 'How lyrics look, and where they come from';

  @override
  String get losslessCheck => 'Check lossless files';

  @override
  String get losslessCheckSubtitle => 'Find FLACs made from an MP3, fake hi-res and 24-bit files padded from 16-bit';

  @override
  String get losslessCheckAbout =>
      'Reads each FLAC, WAV, AIFF, WavPack and APE once: its spectrum and the bits it really uses';

  @override
  String losslessCheckFiles(int checked, int total) {
    return '$checked of $total lossless files checked';
  }

  @override
  String get losslessCheckHow =>
      'Press Check and Riflay reads every lossless file of your library on this device (FLAC, WAV, AIFF, WavPack, APE), one after another. The ones that are probably not real lossless are listed below with the reason; tap one to hear it. Streams are not checked.';

  @override
  String get losslessCheckNoFiles =>
      'Your library has no lossless files on this device yet. Add a folder with FLAC or WAV files first.';

  @override
  String get losslessCheckNeedsFfmpeg =>
      'On Windows the check reads the files with ffmpeg: it is downloaded once when you start.';

  @override
  String get losslessCheckRun => 'Check';

  @override
  String get losslessCheckAllGood => 'Every checked file looks genuine';

  @override
  String losslessCheckFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files are probably not what they claim',
      one: '1 file is probably not what it claims',
    );
    return '$_temp0';
  }

  @override
  String losslessCheckLossyCut(String khz) {
    return 'cut at $khz kHz: made from an MP3 or AAC';
  }

  @override
  String get losslessCheckUpsampled => 'nothing above 22 kHz: upsampled from 44.1 / 48 kHz';

  @override
  String losslessCheckPadded(int bits) {
    return '$bits-bit holding only 16 bits';
  }

  @override
  String get downloadNeedsSignIn =>
      'This song needs a signed-in viewer (age-restricted). Sign in to YouTube Music in Settings › Accounts & services and try again.';

  @override
  String get kwLosslessCheck => 'fake flac, upscaled, transcoded, spectrum, genuine lossless, bit depth';

  @override
  String get dsSong => 'Song';

  @override
  String get dsSource => 'Source';

  @override
  String get dsSignal => 'Signal';

  @override
  String get dsAnalysis => 'Analysis';

  @override
  String get dsSound => 'Sound';

  @override
  String get dsOutput => 'Output';

  @override
  String get dsNetwork => 'Network';

  @override
  String get dsReading => 'Reading';

  @override
  String get dsTitle => 'Title';

  @override
  String get dsArtist => 'Artist';

  @override
  String get dsAlbum => 'Album';

  @override
  String get dsPosition => 'Position';

  @override
  String get dsPlaysFrom => 'Plays from';

  @override
  String get dsPlaysStream => 'YouTube Music stream';

  @override
  String get dsPlaysSpotifyFallback => 'YouTube Music stream (Spotify plays songs only with Premium)';

  @override
  String get dsPlaysDownloaded => 'Downloaded copy';

  @override
  String get dsPlaysFile => 'File on this device';

  @override
  String dsPlaysMerged(String source) {
    return '$source (Smart merge)';
  }

  @override
  String get dsVideoIdItag => 'Video ID / itag';

  @override
  String get dsVideoId => 'Video ID';

  @override
  String get dsFile => 'File';

  @override
  String get dsQuality => 'Quality';

  @override
  String get dsFormat => 'Format';

  @override
  String get dsSampleRate => 'Sample rate';

  @override
  String get dsBitDepth => 'Bit depth';

  @override
  String dsBits(int bits) {
    return '$bits-bit';
  }

  @override
  String get dsBitrate => 'Bitrate';

  @override
  String dsKbpsAvg(int avg) {
    return '$avg kbps (avg)';
  }

  @override
  String dsKbpsNowAvg(int now, int avg) {
    return '$now kbps (avg $avg)';
  }

  @override
  String get dsChannels => 'Channels';

  @override
  String get dsMono => 'Mono';

  @override
  String get dsStereo => 'Stereo';

  @override
  String dsChannelCount(int count) {
    return '$count channels';
  }

  @override
  String get dsContainer => 'Container';

  @override
  String get dsFileSize => 'File size';

  @override
  String get dsFrequencyRange => 'Frequency range';

  @override
  String dsUpToNyquist(String khz) {
    return 'Up to $khz (Nyquist)';
  }

  @override
  String get dsTheoreticalRange => 'Theoretical dynamic range';

  @override
  String get dsMeasuring => 'Measuring';

  @override
  String get dsReadingFile => 'Reading the whole file…';

  @override
  String get dsSpectrum => 'Spectrum';

  @override
  String dsCutLossless(String khz) {
    return 'Cut at $khz: probably made from an MP3 or AAC';
  }

  @override
  String dsCutLossy(String khz) {
    return 'Cut at $khz, as lossy files are';
  }

  @override
  String get dsUpsampled => 'Nothing above about 22 kHz: upsampled from 44.1 / 48 kHz';

  @override
  String dsFullBand(String khz) {
    return 'Full band, up to $khz';
  }

  @override
  String get dsBitsUsed => 'Bits used';

  @override
  String dsBitsPadded(int used, int stored) {
    return '$used of $stored: padded from a 16-bit file';
  }

  @override
  String dsBitsAll(int stored) {
    return 'All $stored';
  }

  @override
  String dsBitsOf(int used, int stored) {
    return '$used of $stored';
  }

  @override
  String get dsDynamicRange => 'Dynamic range';

  @override
  String get dsDrDynamic => 'dynamic';

  @override
  String get dsDrModerate => 'moderately compressed';

  @override
  String get dsDrHeavy => 'heavily compressed';

  @override
  String get dsLoudness => 'Loudness';

  @override
  String dsPeak(String db) {
    return 'peak $db dBFS';
  }

  @override
  String get dsMeasuredGain => 'Measured gain';

  @override
  String dsMeasuredGainValue(String gain) {
    return '$gain dB (leveling uses it without ReplayGain tags)';
  }

  @override
  String get dsDecoded => 'Decoded';

  @override
  String get dsEffects => 'Effects';

  @override
  String get dsNone => 'None';

  @override
  String get dsVolume => 'Volume';

  @override
  String get dsMuted => 'muted';

  @override
  String get dsLeveling => 'Leveling';

  @override
  String get dsOff => 'Off';

  @override
  String get dsOn => 'On';

  @override
  String get dsNoReplayGain => 'no ReplayGain tag';

  @override
  String dsLoudnessTarget(String lufs, String target) {
    return '$lufs LUFS (target $target LUFS)';
  }

  @override
  String get dsTempoPitch => 'Tempo / pitch';

  @override
  String dsTempoPitchValue(String tempo, String pitch) {
    return '$tempo× / $pitch semitones';
  }

  @override
  String get dsCrossfade => 'Crossfade';

  @override
  String get dsClipProtection => 'Clip protection';

  @override
  String get dsResampled => 'Resampled';

  @override
  String get dsDevice => 'Device';

  @override
  String get dsBluetooth => 'Bluetooth';

  @override
  String get dsBtAllow => 'codec: allow Nearby devices';

  @override
  String get dsBtUnknown => 'codec unknown';

  @override
  String get dsDacReceives => 'DAC receives';

  @override
  String get dsDirectUsb => 'Direct USB';

  @override
  String get dsBitPerfect => 'Bit-perfect';

  @override
  String get dsYes => 'Yes';

  @override
  String get dsNo => 'No';

  @override
  String get dsConnectionSpeed => 'Connection speed';

  @override
  String get dsReadingNow => 'Reading now';

  @override
  String get dsReceived => 'Received';

  @override
  String dsReceivedOf(String received, String total) {
    return '$received of $total';
  }

  @override
  String get dsBufferHealth => 'Buffer health';

  @override
  String get dsStreamUrlFrom => 'Stream URL from';

  @override
  String get dsSpectrogram => 'Spectrogram';

  @override
  String get surroundUpmix => 'Surround upmix';

  @override
  String get surroundUpmixSubtitle =>
      'Stereo songs fill a 7.1 room around you: the voice stays in front, the space moves to the sides and back. 5.1 / 7.1 songs, Dolby Atmos too, always get each channel in its place.';

  @override
  String get passthrough => 'Dolby Atmos';

  @override
  String get passthroughSubtitle =>
      'Sends supported Dolby and DTS audio directly to your receiver or soundbar, bypassing Riflay\'s volume and effects.';

  @override
  String get kwSurroundUpmix => 'dolby atmos, spatial audio, surround, 7.1, 3d, upmix';

  @override
  String get kwPassthrough => 'dolby atmos, hdmi, spdif, optical, receiver, soundbar, bitstream, dts, truehd';

  @override
  String get fxUpmix => 'Surround upmix';

  @override
  String dsAtmosBed(int channels) {
    return '$channels-channel bed decoded; the height objects need a receiver (passthrough)';
  }

  @override
  String get dsPassthrough => 'Passthrough';

  @override
  String dsPassthroughValue(String codec) {
    return '$codec to the receiver, undecoded';
  }

  @override
  String get dsVirtualRoom => 'Virtual speakers';

  @override
  String get dsRoomStereo => '2 speakers (stereo)';

  @override
  String get dsRoomSurround => '7.1 room, each channel in its place';

  @override
  String get dsRoomUpmix => '7.1 room, upmixed from stereo';

  @override
  String get autoEq => 'EQ for your headphones or earphones';

  @override
  String get autoEqSubtitle => 'Search for your exact model to adjust its sound using measured profiles.';

  @override
  String get autoEqPick => 'Pick your headphones or IEM';

  @override
  String get autoEqSearch => 'Search a model, e.g. KZ ZSN Pro';

  @override
  String get autoEqLoading => 'Loading the list of models…';

  @override
  String autoEqModels(int count) {
    return '$count profiles available. Search by brand and model.';
  }

  @override
  String get autoEqNoResults => 'No matching model. Try the brand and model name, without extra words.';

  @override
  String get autoEqLoadFailed => 'Couldn’t load the EQ profiles. Check your connection and try again.';

  @override
  String autoEqFailed(String error) {
    return 'Couldn\'t load AutoEQ: $error';
  }

  @override
  String autoEqApplied(String name) {
    return 'Equalizer set for $name';
  }

  @override
  String autoEqAppliedFitted(String name, String db) {
    return 'Equalizer set for $name (within ±$db dB of its profile)';
  }

  @override
  String get clearCache => 'Clear cache';

  @override
  String clearCacheSubtitle(String size) {
    return '$size of covers, lyrics found online and other things Riflay fetches again. Your music stays.';
  }

  @override
  String get clearCacheCounting => 'Counting…';

  @override
  String clearCacheConfirm(String size) {
    return 'Clear $size of cache?';
  }

  @override
  String get clearCacheConfirmBody =>
      'Covers and lyrics are downloaded again when they are needed. Your library, downloads, playlists, settings, your own lyrics and the loudness measurements stay.';

  @override
  String get clearCacheAction => 'Clear';

  @override
  String clearCacheDone(String size) {
    return 'Freed $size';
  }

  @override
  String get kwClearCache => 'cache, storage, space, free up, clean, temporary files';

  @override
  String get dsDeviceRate => 'Device sample rate';

  @override
  String get dsDeviceFormat => 'Device format';

  @override
  String get dsMixerBuffer => 'Mixer buffer';

  @override
  String dsMixerBufferValue(String ms, int frames) {
    return '$ms ms · $frames frames';
  }

  @override
  String get dsLowLatency => 'Low-latency audio';

  @override
  String get dsProAudio => 'Pro audio';

  @override
  String get dsSpatialAudio => 'Spatial audio';

  @override
  String get dsSystemVolume => 'System volume';

  @override
  String get dsSupported => 'Supported';

  @override
  String get dsNotSupported => 'Not supported';

  @override
  String get topicSources => 'Music sources';

  @override
  String get topicSourcesSummary =>
      'SoundCloud, Monochrome and SpotiFLAC extensions: more places to search and play from';

  @override
  String get sourcesAbout => 'Additional music services. Each one is off until you turn it on.';

  @override
  String get sourceMonochromeSubtitle => 'Monochrome\'s music catalog, in FLAC when available, on search\'s All';

  @override
  String get openMusicLink => 'Open a music link';

  @override
  String get monochromeCantCast => 'Download this Monochrome song before casting.';

  @override
  String get openMusicLinkBody => 'Paste a YouTube, SoundCloud or Monochrome link to play or import music.';

  @override
  String get kwSources =>
      'flac, lossless, soundcloud, monochrome, spotiflac, extensions, smart merge, best quality, sources';

  @override
  String get smartMerge => 'Smart merge';

  @override
  String get smartMergeSubtitle =>
      'Plays a YouTube Music song from a lossless file of the same recording in your library, when you have one. Keeps its cover, lyrics and video. Uses YouTube otherwise. Choose a source manually from the song menu.';

  @override
  String get smartMergeToday => 'Today';

  @override
  String smartMergeTodayStats(String lossless, String youtube, String limited, String kept) {
    return '$lossless in lossless · $youtube from YouTube Music · $limited held back by a request limit · $kept from the disk cache';
  }

  @override
  String get smartMergeCache => 'Keep played songs on disk';

  @override
  String smartMergeCacheSubtitle(String size) {
    return 'A song played again opens from here at once, without asking the source (so its request limit is spent less). Using $size now';
  }

  @override
  String get smartMergeCacheClear => 'Clear';

  @override
  String smartMergeBadge(String source) {
    return 'Audio from $source';
  }

  @override
  String smartMergeLossierBadge(String source) {
    return '$source only has this song in lower quality, so it plays from YouTube Music';
  }

  @override
  String smartMergePendingBadge(String source) {
    return 'Getting the lossless sound from $source: the song moves over to it where it is, as soon as it\'s ready';
  }

  @override
  String smartMergeLimitedBadge(String source) {
    return '$source is limiting requests right now, so this plays from YouTube Music. It moves over to $source by itself once the limit is over';
  }

  @override
  String get spotifyCanvas => 'Canvas';

  @override
  String get spotifyCanvasSubtitle =>
      'The looping video Spotify shows with a song, in Video mode instead of its music video (turn Video mode on in Beta features)';

  @override
  String sourceInSearch(String source) {
    return '$source in search';
  }

  @override
  String fromSource(String source) {
    return 'From $source';
  }

  @override
  String sourceUnavailable(String source) {
    return 'Couldn\'t reach $source. Try again.';
  }

  @override
  String addFolderNamed(String name) {
    return 'Add “$name”';
  }

  @override
  String get folderOnlyAdd => 'Only add';

  @override
  String get folderOnlyAddSubtitle => 'Its songs go into your library';

  @override
  String get folderAsPlaylist => 'Add as playlist';

  @override
  String get folderAsPlaylistSubtitle => 'A playlist that follows this folder';

  @override
  String get folderPlaylist => 'Folder playlist';

  @override
  String get makeFolderPlaylist => 'Show as a playlist';

  @override
  String get removeFolderPlaylist => 'Remove from playlists';

  @override
  String get folderPlaylistRemoved => 'Removed from playlists. The folder and its songs stay.';

  @override
  String get spotiflacDownloadToPlay => 'This song can only be played after downloading.';

  @override
  String get spotiflacVerify => 'Verify source';

  @override
  String get spotiflacVerificationRequired => 'Verify this source in your browser, then retry the download.';

  @override
  String get showPlayerClose => 'Show player close button';

  @override
  String get showPlayerCloseSubtitle =>
      'Show the top arrow in player styles other than Classic. Swipe down to close when hidden.';

  @override
  String get catalogueDownloader => 'Download provider for metadata-only catalogues';

  @override
  String get downloadSource => 'Download source';

  @override
  String downloadMatchTitle(String source) {
    return 'Find a match on $source';
  }

  @override
  String get downloadMatchReview => 'Choose the recording to download. Check the artist, version and duration.';

  @override
  String get downloadMatchFailed => 'Couldn\'t search this source. Try again or choose another source.';

  @override
  String get downloadMatchEmpty => 'No matching songs found. Try a shorter title or a different source.';

  @override
  String get introSkip => 'Skip intro';

  @override
  String get trayShuffle => 'Shuffle';

  @override
  String get trayRepeat => 'Repeat';

  @override
  String get trayRepeatOne => 'One song';

  @override
  String get roomChat => 'Room chat';

  @override
  String get roomChatEmpty => 'Say hello to everyone listening.';

  @override
  String get roomChatHint => 'Write a message…';

  @override
  String get roomChatSend => 'Send message';

  @override
  String get copySongTitle => 'Copy song title';

  @override
  String get copyFailed => 'Couldn\'t copy. Try again.';

  @override
  String get networkProxy => 'Network proxy';

  @override
  String get networkProxyAbout =>
      'Use a proxy server if your network requires it. Each music service still applies its own request limits.';

  @override
  String get networkProxyAddress => 'HTTP proxy address';

  @override
  String get networkProxyBypass => 'Bypass proxy for these domains';

  @override
  String get networkProxyBypassHint =>
      'Separate domains with commas or new lines. Includes subdomains. Local devices and LAN addresses always connect directly.';

  @override
  String get networkProxyScope =>
      'Applies to new app HTTP requests and yt-dlp. Restart playback after changing it. Sign-in browsers use their own network settings.';

  @override
  String get networkProxyInvalid => 'Enter http://host:port without a username or password, and valid bypass domains.';

  @override
  String get networkProxySaved => 'Proxy settings saved. New requests use the updated rules.';

  @override
  String get networkProxySaveFailed => 'Couldn\'t save proxy settings. Try again.';

  @override
  String get seekStep => 'Seek step';

  @override
  String get seekStepHint => 'How far Shift + Left or Right Arrow jumps within a song. Off disables those shortcuts.';

  @override
  String get scSeekBackward => 'Seek backward';

  @override
  String get scSeekForward => 'Seek forward';

  @override
  String seekStepSeconds(int seconds) {
    return '$seconds s';
  }

  @override
  String seekSkipSeconds(int seconds) {
    return '$seconds seconds';
  }

  @override
  String get coverAppLogo => 'Riflay logo';

  @override
  String get keepPhoneNavOpen => 'Keep navigation expanded';

  @override
  String get coverZoomIn => 'Zoom in';

  @override
  String get coverZoomOut => 'Zoom out';

  @override
  String get coverPreview => 'Cover thumbnail preview';

  @override
  String get coverRotate => 'Rotate right';

  @override
  String get coverFlip => 'Flip horizontally';

  @override
  String get coverReset => 'Reset crop';

  @override
  String get coverGestureHint => 'Drag to position the photo. Pinch, scroll or use the slider to zoom.';

  @override
  String get playlistOptions => 'Playlist options';

  @override
  String get pinPlaylist => 'Pin playlist';

  @override
  String get unpinPlaylist => 'Unpin playlist';

  @override
  String get movePlaylistUp => 'Move playlist up';

  @override
  String get movePlaylistDown => 'Move playlist down';

  @override
  String get sortPlaylists => 'Sort playlists';

  @override
  String get playlistLibraryOrder => 'Library order';

  @override
  String get playlistCustomOrder => 'Custom order';

  @override
  String get hidePhoneNavLabels => 'Hide bottom navigation labels';

  @override
  String removeSelectedTracksBody(int count) {
    return 'Remove $count selected songs from this playlist?';
  }

  @override
  String get editPlaylists => 'Edit playlists';

  @override
  String get pinTrack => 'Pin song';

  @override
  String get unpinTrack => 'Unpin song';

  @override
  String get miniGlassTint => 'Mini-player Liquid Glass tint';

  @override
  String get playerGlassTint => 'Now Playing Liquid Glass tint';

  @override
  String get followCover => 'Match artwork';

  @override
  String get playingFromLabel => 'Playing from';

  @override
  String get optionalTools => 'Optional tools';

  @override
  String get playlistSearch => 'Search within playlists';

  @override
  String get recentPlaylistPicker => 'Remember the last playlist';

  @override
  String get undoRemoval => 'Undo track removals';

  @override
  String get resumeLongTracks => 'Resume long tracks';

  @override
  String get playlistDownloadStatus => 'Playlist download status';

  @override
  String get jumpToPlaying => 'Jump to the playing song';

  @override
  String get copyLyricsLines => 'Copy lyric lines on long press';

  @override
  String get hideRecommendations => 'Hide songs from recommendations';

  @override
  String get noMatchingSongs => 'No matching songs';

  @override
  String get searchPlaylists => 'Search playlists';

  @override
  String get dontRecommendAgain => 'Don\'t recommend again';

  @override
  String resumeAt(String time) {
    return 'Resume at $time';
  }

  @override
  String playlistOfflineProgress(int ready, int total) {
    return '$ready of $total songs available offline';
  }

  @override
  String playlistDownloadsFailed(int count) {
    return 'Failed downloads: $count';
  }

  @override
  String get autoDownloadLiked => 'Automatically download liked songs';

  @override
  String get dailySleepTimer => 'Daily sleep timer';

  @override
  String get dailyPlaylistAlarm => 'Daily playlist alarm';

  @override
  String get scheduleWhileRunning => 'Works while Riflay is running';

  @override
  String get karaoke => 'Karaoke';

  @override
  String get karaokeHint =>
      'Turn the song\'s vocals down or off and sing along. Each song is split once, on this device.';

  @override
  String karaokeDownloadNote(int size) {
    return 'Turning it on downloads the vocal separation model once (about $size MB).';
  }

  @override
  String karaokeDownloading(int percent) {
    return 'Downloading the separation model… $percent%';
  }

  @override
  String get karaokeReading => 'Reading the song…';

  @override
  String karaokeSeparating(int percent) {
    return 'Separating the vocals… $percent%';
  }

  @override
  String get karaokeReady => 'Vocals separated. Next time this song starts at once.';

  @override
  String get karaokeUnsupported => 'This song\'s source can\'t be separated. Try it after downloading the song.';

  @override
  String get karaokeFailed => 'Couldn\'t separate this song.';

  @override
  String get karaokeUnavailable => 'Karaoke isn\'t available on iPhone and iPad yet.';

  @override
  String get karaokeVocals => 'Vocals';

  @override
  String get karaokeMusic => 'Music';
}
