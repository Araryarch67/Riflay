import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_id.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('id')];

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The language of Riflay\'s screens'**
  String get languageSubtitle;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'Device language'**
  String get languageSystem;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get navLibrary;

  /// No description provided for @navSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// No description provided for @navDownloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get navDownloads;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @yourLibrary.
  ///
  /// In en, this message translates to:
  /// **'Your Library'**
  String get yourLibrary;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @groupSound.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get groupSound;

  /// No description provided for @groupSoundSummary.
  ///
  /// In en, this message translates to:
  /// **'Playback, sound effects (DSP), output and quality'**
  String get groupSoundSummary;

  /// No description provided for @groupLook.
  ///
  /// In en, this message translates to:
  /// **'Look & feel'**
  String get groupLook;

  /// No description provided for @groupLookSummary.
  ///
  /// In en, this message translates to:
  /// **'Themes, colours, text size, what the screens show'**
  String get groupLookSummary;

  /// No description provided for @groupLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library & downloads'**
  String get groupLibrary;

  /// No description provided for @groupLibrarySummary.
  ///
  /// In en, this message translates to:
  /// **'Music folders, downloads, listening history, backups'**
  String get groupLibrarySummary;

  /// No description provided for @groupAccounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts & services'**
  String get groupAccounts;

  /// No description provided for @groupAccountsSummary.
  ///
  /// In en, this message translates to:
  /// **'YouTube Music, Spotify, Last.fm, Discord, lyrics, extensions'**
  String get groupAccountsSummary;

  /// No description provided for @topicPlayback.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get topicPlayback;

  /// No description provided for @topicPlaybackSummary.
  ///
  /// In en, this message translates to:
  /// **'Autoplay and gapless playback'**
  String get topicPlaybackSummary;

  /// No description provided for @topicDsp.
  ///
  /// In en, this message translates to:
  /// **'Sound effects (DSP)'**
  String get topicDsp;

  /// No description provided for @topicDspSummary.
  ///
  /// In en, this message translates to:
  /// **'Equalizer, volume leveling, crossfade, spatial audio and room correction'**
  String get topicDspSummary;

  /// No description provided for @topicOutput.
  ///
  /// In en, this message translates to:
  /// **'Output & quality'**
  String get topicOutput;

  /// No description provided for @topicOutputSummary.
  ///
  /// In en, this message translates to:
  /// **'Output device, bit-perfect mode, sample rate'**
  String get topicOutputSummary;

  /// No description provided for @topicAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get topicAppearance;

  /// No description provided for @topicAppearanceSummary.
  ///
  /// In en, this message translates to:
  /// **'Theme, accent colour, background, text size, font'**
  String get topicAppearanceSummary;

  /// No description provided for @topicLayout.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get topicLayout;

  /// No description provided for @topicLayoutSummary.
  ///
  /// In en, this message translates to:
  /// **'Shapes, sizes, what the player shows'**
  String get topicLayoutSummary;

  /// No description provided for @topicLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get topicLibrary;

  /// No description provided for @topicLibrarySummary.
  ///
  /// In en, this message translates to:
  /// **'Keep music folders up to date, find songs you have twice'**
  String get topicLibrarySummary;

  /// No description provided for @topicDownloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get topicDownloads;

  /// No description provided for @topicDownloadsSummary.
  ///
  /// In en, this message translates to:
  /// **'Format, quality, where songs are saved'**
  String get topicDownloadsSummary;

  /// No description provided for @topicHistory.
  ///
  /// In en, this message translates to:
  /// **'Listening history & Wrap'**
  String get topicHistory;

  /// No description provided for @topicHistorySummary.
  ///
  /// In en, this message translates to:
  /// **'The history behind your stats, kept on this device'**
  String get topicHistorySummary;

  /// No description provided for @topicBackup.
  ///
  /// In en, this message translates to:
  /// **'Backup & restore'**
  String get topicBackup;

  /// No description provided for @topicBackupSummary.
  ///
  /// In en, this message translates to:
  /// **'Your settings, playlists and history in one file'**
  String get topicBackupSummary;

  /// No description provided for @topicAccount.
  ///
  /// In en, this message translates to:
  /// **'YouTube Music account'**
  String get topicAccount;

  /// No description provided for @topicAccountSummary.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get topicAccountSummary;

  /// No description provided for @topicSpotify.
  ///
  /// In en, this message translates to:
  /// **'Spotify'**
  String get topicSpotify;

  /// No description provided for @topicSpotifySummary.
  ///
  /// In en, this message translates to:
  /// **'Bring your playlists, Liked Songs and albums over'**
  String get topicSpotifySummary;

  /// No description provided for @topicScrobbling.
  ///
  /// In en, this message translates to:
  /// **'Last.fm & ListenBrainz'**
  String get topicScrobbling;

  /// No description provided for @topicScrobblingSummary.
  ///
  /// In en, this message translates to:
  /// **'Add the songs you play to your profile there'**
  String get topicScrobblingSummary;

  /// No description provided for @topicIntegrations.
  ///
  /// In en, this message translates to:
  /// **'Discord & lyrics services'**
  String get topicIntegrations;

  /// No description provided for @topicIntegrationsSummary.
  ///
  /// In en, this message translates to:
  /// **'Show what you play on Discord, lyrics services'**
  String get topicIntegrationsSummary;

  /// No description provided for @topicExtensions.
  ///
  /// In en, this message translates to:
  /// **'Extensions'**
  String get topicExtensions;

  /// No description provided for @topicExtensionsSummary.
  ///
  /// In en, this message translates to:
  /// **'SpotiFLAC extension repositories: more places to search'**
  String get topicExtensionsSummary;

  /// No description provided for @topicLyricsServices.
  ///
  /// In en, this message translates to:
  /// **'Lyrics services'**
  String get topicLyricsServices;

  /// No description provided for @topicPlaybackSummaryWeb.
  ///
  /// In en, this message translates to:
  /// **'Autoplay'**
  String get topicPlaybackSummaryWeb;

  /// No description provided for @topicIntegrationsSummaryWeb.
  ///
  /// In en, this message translates to:
  /// **'A Better Lyrics key for word-by-word lyrics'**
  String get topicIntegrationsSummaryWeb;

  /// No description provided for @settingsPower.
  ///
  /// In en, this message translates to:
  /// **'Power & background'**
  String get settingsPower;

  /// No description provided for @listenTogether.
  ///
  /// In en, this message translates to:
  /// **'Listen together'**
  String get listenTogether;

  /// No description provided for @keyboardShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get keyboardShortcuts;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @sectionPlayer.
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get sectionPlayer;

  /// No description provided for @queue.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get queue;

  /// No description provided for @lyrics.
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get lyrics;

  /// No description provided for @closePlayer.
  ///
  /// In en, this message translates to:
  /// **'Close player'**
  String get closePlayer;

  /// No description provided for @sectionSong.
  ///
  /// In en, this message translates to:
  /// **'Song'**
  String get sectionSong;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @addToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Add to playlist'**
  String get addToPlaylist;

  /// No description provided for @downloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get downloaded;

  /// No description provided for @stopDownload.
  ///
  /// In en, this message translates to:
  /// **'Stop download'**
  String get stopDownload;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @playsOffline.
  ///
  /// In en, this message translates to:
  /// **'Plays offline'**
  String get playsOffline;

  /// No description provided for @downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get downloading;

  /// No description provided for @sectionListen.
  ///
  /// In en, this message translates to:
  /// **'Listen'**
  String get sectionListen;

  /// No description provided for @sleepTimer.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer'**
  String get sleepTimer;

  /// No description provided for @playOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Play on a device'**
  String get playOnDevice;

  /// No description provided for @playingOn.
  ///
  /// In en, this message translates to:
  /// **'Playing on {device}'**
  String playingOn(Object device);

  /// No description provided for @sectionSound.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get sectionSound;

  /// No description provided for @equalizer.
  ///
  /// In en, this message translates to:
  /// **'Equalizer'**
  String get equalizer;

  /// No description provided for @signalPath.
  ///
  /// In en, this message translates to:
  /// **'Signal path'**
  String get signalPath;

  /// No description provided for @detailStats.
  ///
  /// In en, this message translates to:
  /// **'Detail stats'**
  String get detailStats;

  /// No description provided for @playNext.
  ///
  /// In en, this message translates to:
  /// **'Play next'**
  String get playNext;

  /// No description provided for @addToQueue.
  ///
  /// In en, this message translates to:
  /// **'Add to queue'**
  String get addToQueue;

  /// No description provided for @goToArtist.
  ///
  /// In en, this message translates to:
  /// **'Go to artist'**
  String get goToArtist;

  /// No description provided for @goToAlbum.
  ///
  /// In en, this message translates to:
  /// **'Go to album'**
  String get goToAlbum;

  /// No description provided for @removeFromThisPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Remove from this playlist'**
  String get removeFromThisPlaylist;

  /// No description provided for @addToLiked.
  ///
  /// In en, this message translates to:
  /// **'Add to Liked music'**
  String get addToLiked;

  /// No description provided for @removeFromLiked.
  ///
  /// In en, this message translates to:
  /// **'Remove from Liked music'**
  String get removeFromLiked;

  /// No description provided for @startRadio.
  ///
  /// In en, this message translates to:
  /// **'Start radio'**
  String get startRadio;

  /// No description provided for @downloadForOffline.
  ///
  /// In en, this message translates to:
  /// **'Download for offline'**
  String get downloadForOffline;

  /// No description provided for @downloadAs.
  ///
  /// In en, this message translates to:
  /// **'Download as…'**
  String get downloadAs;

  /// No description provided for @saveToDevice.
  ///
  /// In en, this message translates to:
  /// **'Save to device'**
  String get saveToDevice;

  /// No description provided for @savingToDevice.
  ///
  /// In en, this message translates to:
  /// **'{title} is downloading in your browser'**
  String savingToDevice(Object title);

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @editInfo.
  ///
  /// In en, this message translates to:
  /// **'Edit info'**
  String get editInfo;

  /// No description provided for @removeFromLibrary.
  ///
  /// In en, this message translates to:
  /// **'Remove from library'**
  String get removeFromLibrary;

  /// No description provided for @deleteDownload.
  ///
  /// In en, this message translates to:
  /// **'Delete download'**
  String get deleteDownload;

  /// No description provided for @deleteDownloadQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete this download?'**
  String get deleteDownloadQuestion;

  /// No description provided for @deleteDownloadBody.
  ///
  /// In en, this message translates to:
  /// **'{title} is removed from your library and its file is deleted from this device.'**
  String deleteDownloadBody(String title);

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @downloadDeleted.
  ///
  /// In en, this message translates to:
  /// **'Download deleted'**
  String get downloadDeleted;

  /// No description provided for @convertToFlac.
  ///
  /// In en, this message translates to:
  /// **'Convert to FLAC'**
  String get convertToFlac;

  /// No description provided for @toastPlaysNext.
  ///
  /// In en, this message translates to:
  /// **'Plays next'**
  String get toastPlaysNext;

  /// No description provided for @toastAddedToQueue.
  ///
  /// In en, this message translates to:
  /// **'Added to queue'**
  String get toastAddedToQueue;

  /// No description provided for @toastRequestedNext.
  ///
  /// In en, this message translates to:
  /// **'Requested next song'**
  String get toastRequestedNext;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @previous.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @enableShuffle.
  ///
  /// In en, this message translates to:
  /// **'Enable shuffle'**
  String get enableShuffle;

  /// No description provided for @disableShuffle.
  ///
  /// In en, this message translates to:
  /// **'Disable shuffle'**
  String get disableShuffle;

  /// No description provided for @enableRepeat.
  ///
  /// In en, this message translates to:
  /// **'Enable repeat'**
  String get enableRepeat;

  /// No description provided for @enableRepeatOne.
  ///
  /// In en, this message translates to:
  /// **'Enable repeat one'**
  String get enableRepeatOne;

  /// No description provided for @disableRepeat.
  ///
  /// In en, this message translates to:
  /// **'Disable repeat'**
  String get disableRepeat;

  /// No description provided for @mute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get mute;

  /// No description provided for @unmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmute;

  /// No description provided for @sleepTimerFades.
  ///
  /// In en, this message translates to:
  /// **'The music fades out, then stops'**
  String get sleepTimerFades;

  /// No description provided for @afterAWhile.
  ///
  /// In en, this message translates to:
  /// **'After a while'**
  String get afterAWhile;

  /// No description provided for @afterSongs.
  ///
  /// In en, this message translates to:
  /// **'After songs'**
  String get afterSongs;

  /// No description provided for @minutesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} minutes'**
  String minutesCount(int count);

  /// No description provided for @songsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} songs'**
  String songsCount(int count);

  /// No description provided for @endOfThisSong.
  ///
  /// In en, this message translates to:
  /// **'End of this song'**
  String get endOfThisSong;

  /// No description provided for @customTime.
  ///
  /// In en, this message translates to:
  /// **'Custom time'**
  String get customTime;

  /// No description provided for @add10Minutes.
  ///
  /// In en, this message translates to:
  /// **'Add 10 minutes'**
  String get add10Minutes;

  /// No description provided for @cancelTimer.
  ///
  /// In en, this message translates to:
  /// **'Cancel timer'**
  String get cancelTimer;

  /// No description provided for @stopsIn.
  ///
  /// In en, this message translates to:
  /// **'The music stops in {time}'**
  String stopsIn(Object time);

  /// No description provided for @stopsWhenSongEnds.
  ///
  /// In en, this message translates to:
  /// **'The music stops when this song ends'**
  String get stopsWhenSongEnds;

  /// No description provided for @stopsAfterOneMore.
  ///
  /// In en, this message translates to:
  /// **'The music stops after this song and one more'**
  String get stopsAfterOneMore;

  /// No description provided for @stopsAfterMore.
  ///
  /// In en, this message translates to:
  /// **'The music stops after this song and {count} more'**
  String stopsAfterMore(int count);

  /// No description provided for @settingsPowerSummaryTray.
  ///
  /// In en, this message translates to:
  /// **'Screen timeout, sleep, background playback and closing to the tray'**
  String get settingsPowerSummaryTray;

  /// No description provided for @settingsPowerSummary.
  ///
  /// In en, this message translates to:
  /// **'Screen timeout, sleep and background playback'**
  String get settingsPowerSummary;

  /// No description provided for @listenTogetherSummary.
  ///
  /// In en, this message translates to:
  /// **'Host a session or join friends and manage sharing permissions'**
  String get listenTogetherSummary;

  /// No description provided for @keyboardShortcutsSummary.
  ///
  /// In en, this message translates to:
  /// **'Play, skip, search and more without the mouse'**
  String get keyboardShortcutsSummary;

  /// No description provided for @aboutSummary.
  ///
  /// In en, this message translates to:
  /// **'Version, what\'s new, reporting a problem, licences'**
  String get aboutSummary;

  /// No description provided for @addToHostQueue.
  ///
  /// In en, this message translates to:
  /// **'Add to {host}\'s queue'**
  String addToHostQueue(Object host);

  /// No description provided for @theHost.
  ///
  /// In en, this message translates to:
  /// **'the host'**
  String get theHost;

  /// No description provided for @goToNamedArtist.
  ///
  /// In en, this message translates to:
  /// **'Go to {artist}'**
  String goToNamedArtist(Object artist);

  /// No description provided for @aboutTheArtist.
  ///
  /// In en, this message translates to:
  /// **'About the artist'**
  String get aboutTheArtist;

  /// No description provided for @follow.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get follow;

  /// No description provided for @following.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get following;

  /// No description provided for @showMore.
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get showMore;

  /// No description provided for @showLess.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get showLess;

  /// No description provided for @tempoPitch.
  ///
  /// In en, this message translates to:
  /// **'Tempo & pitch'**
  String get tempoPitch;

  /// No description provided for @tempo.
  ///
  /// In en, this message translates to:
  /// **'Tempo'**
  String get tempo;

  /// No description provided for @pitch.
  ///
  /// In en, this message translates to:
  /// **'Pitch'**
  String get pitch;

  /// No description provided for @semitones.
  ///
  /// In en, this message translates to:
  /// **'{count} semitones'**
  String semitones(int count);

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @asRecorded.
  ///
  /// In en, this message translates to:
  /// **'As recorded'**
  String get asRecorded;

  /// No description provided for @tempoPitchOff.
  ///
  /// In en, this message translates to:
  /// **'Off while bit-perfect mode is on or listening together'**
  String get tempoPitchOff;

  /// No description provided for @greetingNight.
  ///
  /// In en, this message translates to:
  /// **'Good night'**
  String get greetingNight;

  /// No description provided for @greetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get greetingMorning;

  /// No description provided for @greetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get greetingAfternoon;

  /// No description provided for @greetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get greetingEvening;

  /// No description provided for @allSongs.
  ///
  /// In en, this message translates to:
  /// **'All Songs'**
  String get allSongs;

  /// No description provided for @likedMusic.
  ///
  /// In en, this message translates to:
  /// **'Liked music'**
  String get likedMusic;

  /// No description provided for @recentlyPlayed.
  ///
  /// In en, this message translates to:
  /// **'Recently played'**
  String get recentlyPlayed;

  /// No description provided for @yourPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Your playlists'**
  String get yourPlaylists;

  /// No description provided for @yourAlbums.
  ///
  /// In en, this message translates to:
  /// **'Your albums'**
  String get yourAlbums;

  /// No description provided for @yourArtists.
  ///
  /// In en, this message translates to:
  /// **'Your artists'**
  String get yourArtists;

  /// No description provided for @artists.
  ///
  /// In en, this message translates to:
  /// **'Artists'**
  String get artists;

  /// No description provided for @artist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get artist;

  /// No description provided for @albums.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get albums;

  /// No description provided for @album.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get album;

  /// No description provided for @playlists.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get playlists;

  /// No description provided for @playlist.
  ///
  /// In en, this message translates to:
  /// **'Playlist'**
  String get playlist;

  /// No description provided for @smartPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Smart playlist'**
  String get smartPlaylist;

  /// No description provided for @recentlyAdded.
  ///
  /// In en, this message translates to:
  /// **'Recently added'**
  String get recentlyAdded;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @addMusicOffline.
  ///
  /// In en, this message translates to:
  /// **'Add music from this device to play it offline.'**
  String get addMusicOffline;

  /// No description provided for @addSongs.
  ///
  /// In en, this message translates to:
  /// **'Add songs'**
  String get addSongs;

  /// No description provided for @addFolder.
  ///
  /// In en, this message translates to:
  /// **'Add a folder'**
  String get addFolder;

  /// No description provided for @addMusic.
  ///
  /// In en, this message translates to:
  /// **'Add music'**
  String get addMusic;

  /// No description provided for @addFiles.
  ///
  /// In en, this message translates to:
  /// **'Add files'**
  String get addFiles;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @importFromYouTube.
  ///
  /// In en, this message translates to:
  /// **'Import from YouTube'**
  String get importFromYouTube;

  /// No description provided for @fromYouTube.
  ///
  /// In en, this message translates to:
  /// **'From YouTube'**
  String get fromYouTube;

  /// No description provided for @noMusicYet.
  ///
  /// In en, this message translates to:
  /// **'No music yet'**
  String get noMusicYet;

  /// No description provided for @noMusicYetBody.
  ///
  /// In en, this message translates to:
  /// **'Add audio files from this device. Albums, artists and cover art come from the files\' tags.'**
  String get noMusicYetBody;

  /// No description provided for @newPlaylist.
  ///
  /// In en, this message translates to:
  /// **'New playlist'**
  String get newPlaylist;

  /// No description provided for @newPlaylistSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Mix your own songs and YouTube Music'**
  String get newPlaylistSubtitle;

  /// No description provided for @yourListeningStats.
  ///
  /// In en, this message translates to:
  /// **'Your listening stats'**
  String get yourListeningStats;

  /// No description provided for @yourListeningStatsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Top songs, artists and albums'**
  String get yourListeningStatsSubtitle;

  /// No description provided for @yourYouTubeMusic.
  ///
  /// In en, this message translates to:
  /// **'Your YouTube Music'**
  String get yourYouTubeMusic;

  /// No description provided for @yourYouTubeMusicBody.
  ///
  /// In en, this message translates to:
  /// **'Sign in to see your liked songs and playlists here.'**
  String get yourYouTubeMusicBody;

  /// No description provided for @signInWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get signInWithGoogle;

  /// No description provided for @musicOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Music on this device'**
  String get musicOnDevice;

  /// No description provided for @musicOnDeviceBody.
  ///
  /// In en, this message translates to:
  /// **'Add audio files to play them offline.'**
  String get musicOnDeviceBody;

  /// No description provided for @joinSharedPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Join a shared playlist'**
  String get joinSharedPlaylist;

  /// No description provided for @importPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Import a playlist'**
  String get importPlaylist;

  /// No description provided for @spotifyLibrary.
  ///
  /// In en, this message translates to:
  /// **'Spotify library'**
  String get spotifyLibrary;

  /// No description provided for @libraryEmpty.
  ///
  /// In en, this message translates to:
  /// **'Add songs or a playlist to start your library.'**
  String get libraryEmpty;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @songs.
  ///
  /// In en, this message translates to:
  /// **'Songs'**
  String get songs;

  /// No description provided for @videos.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get videos;

  /// No description provided for @searchIntro.
  ///
  /// In en, this message translates to:
  /// **'Searches your own music and all of YouTube Music together. Songs with a cloud stream online; the rest play offline.'**
  String get searchIntro;

  /// No description provided for @browseArtists.
  ///
  /// In en, this message translates to:
  /// **'Browse artists'**
  String get browseArtists;

  /// No description provided for @inYourLibrary.
  ///
  /// In en, this message translates to:
  /// **'In your library'**
  String get inYourLibrary;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'What do you want to play?'**
  String get searchHint;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @recentSearches.
  ///
  /// In en, this message translates to:
  /// **'Recent searches'**
  String get recentSearches;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @clearFinished.
  ///
  /// In en, this message translates to:
  /// **'Clear finished'**
  String get clearFinished;

  /// No description provided for @nothingDownloading.
  ///
  /// In en, this message translates to:
  /// **'Nothing downloading. Paste a YouTube video or playlist link to add its audio to your library.'**
  String get nothingDownloading;

  /// No description provided for @downloadsUse.
  ///
  /// In en, this message translates to:
  /// **'Downloads use {size}'**
  String downloadsUse(Object size);

  /// No description provided for @missingFiles.
  ///
  /// In en, this message translates to:
  /// **'Missing files'**
  String get missingFiles;

  /// No description provided for @downloadAllAgain.
  ///
  /// In en, this message translates to:
  /// **'Download all again'**
  String get downloadAllAgain;

  /// No description provided for @removeAllFromLibrary.
  ///
  /// In en, this message translates to:
  /// **'Remove all from library'**
  String get removeAllFromLibrary;

  /// No description provided for @missingFilesBody.
  ///
  /// In en, this message translates to:
  /// **'These songs are in your library, but their files aren\'t on this device any more.'**
  String get missingFilesBody;

  /// No description provided for @downloadAgain.
  ///
  /// In en, this message translates to:
  /// **'Download again'**
  String get downloadAgain;

  /// No description provided for @waiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting…'**
  String get waiting;

  /// No description provided for @preparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get preparing;

  /// No description provided for @bytesOf.
  ///
  /// In en, this message translates to:
  /// **'{received} of {total}'**
  String bytesOf(Object received, Object total);

  /// No description provided for @addedToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Added to library'**
  String get addedToLibrary;

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failed;

  /// No description provided for @cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get cancelled;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @downloadingCount.
  ///
  /// In en, this message translates to:
  /// **'Downloading {count}'**
  String downloadingCount(int count);

  /// No description provided for @saveAsPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Save as playlist'**
  String get saveAsPlaylist;

  /// No description provided for @queueEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing playing yet. Pick an album, artist or song to fill the queue.'**
  String get queueEmpty;

  /// No description provided for @nowPlaying.
  ///
  /// In en, this message translates to:
  /// **'Now playing'**
  String get nowPlaying;

  /// No description provided for @nowPlayingTitle.
  ///
  /// In en, this message translates to:
  /// **'Now Playing'**
  String get nowPlayingTitle;

  /// No description provided for @nextUp.
  ///
  /// In en, this message translates to:
  /// **'Next up'**
  String get nextUp;

  /// No description provided for @nextFrom.
  ///
  /// In en, this message translates to:
  /// **'Next from: {source}'**
  String nextFrom(Object source);

  /// No description provided for @autoplay.
  ///
  /// In en, this message translates to:
  /// **'Autoplay'**
  String get autoplay;

  /// No description provided for @autoplaySubtitle.
  ///
  /// In en, this message translates to:
  /// **'When the queue ends, keep playing similar songs from YouTube Music'**
  String get autoplaySubtitle;

  /// No description provided for @autoplaySimilar.
  ///
  /// In en, this message translates to:
  /// **'Autoplay: similar to what you\'re playing'**
  String get autoplaySimilar;

  /// No description provided for @removeFromQueue.
  ///
  /// In en, this message translates to:
  /// **'Remove from queue'**
  String get removeFromQueue;

  /// No description provided for @dragToMove.
  ///
  /// In en, this message translates to:
  /// **'Drag to move'**
  String get dragToMove;

  /// No description provided for @shufflePlay.
  ///
  /// In en, this message translates to:
  /// **'Shuffle play'**
  String get shufflePlay;

  /// No description provided for @addAllToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Add all to playlist'**
  String get addAllToPlaylist;

  /// No description provided for @select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// No description provided for @unselect.
  ///
  /// In en, this message translates to:
  /// **'Unselect'**
  String get unselect;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @cancelSelection.
  ///
  /// In en, this message translates to:
  /// **'Cancel selection'**
  String get cancelSelection;

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCount(int count);

  /// No description provided for @playlistOnRiflay.
  ///
  /// In en, this message translates to:
  /// **'Riflay • {count} songs'**
  String playlistOnRiflay(int count);

  /// No description provided for @playlistOnYoutubeMusic.
  ///
  /// In en, this message translates to:
  /// **'YouTube Music • {count} songs'**
  String playlistOnYoutubeMusic(int count);

  /// No description provided for @addedTo.
  ///
  /// In en, this message translates to:
  /// **'Added to {name}'**
  String addedTo(String name);

  /// No description provided for @addedSongsTo.
  ///
  /// In en, this message translates to:
  /// **'Added {count} songs to {name}'**
  String addedSongsTo(int count, String name);

  /// No description provided for @alreadyIn.
  ///
  /// In en, this message translates to:
  /// **'Already in {name}'**
  String alreadyIn(String name);

  /// No description provided for @notOnYoutubeMusic.
  ///
  /// In en, this message translates to:
  /// **'This song isn\'t on YouTube Music'**
  String get notOnYoutubeMusic;

  /// No description provided for @noneOnYoutubeMusic.
  ///
  /// In en, this message translates to:
  /// **'None of these songs are on YouTube Music'**
  String get noneOnYoutubeMusic;

  /// No description provided for @skippedNotOnYoutubeMusic.
  ///
  /// In en, this message translates to:
  /// **'{count} not on YouTube Music, skipped'**
  String skippedNotOnYoutubeMusic(int count);

  /// No description provided for @addAllToQueue.
  ///
  /// In en, this message translates to:
  /// **'Add all to queue'**
  String get addAllToQueue;

  /// No description provided for @downloadAllOffline.
  ///
  /// In en, this message translates to:
  /// **'Download all for offline'**
  String get downloadAllOffline;

  /// No description provided for @alreadyDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Already downloaded'**
  String get alreadyDownloaded;

  /// No description provided for @downloadingSongs.
  ///
  /// In en, this message translates to:
  /// **'Downloading {count} songs…'**
  String downloadingSongs(int count);

  /// No description provided for @disc.
  ///
  /// In en, this message translates to:
  /// **'Disc {number}'**
  String disc(Object number);

  /// No description provided for @removedFrom.
  ///
  /// In en, this message translates to:
  /// **'Removed from {playlist}'**
  String removedFrom(Object playlist);

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @editPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Edit playlist'**
  String get editPlaylist;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @convertAllToFlac.
  ///
  /// In en, this message translates to:
  /// **'Convert all to FLAC'**
  String get convertAllToFlac;

  /// No description provided for @deletePlaylistQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete playlist?'**
  String get deletePlaylistQuestion;

  /// No description provided for @deletePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Delete playlist'**
  String get deletePlaylist;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @playingFromCaps.
  ///
  /// In en, this message translates to:
  /// **'PLAYING FROM'**
  String get playingFromCaps;

  /// No description provided for @yourLibrarySource.
  ///
  /// In en, this message translates to:
  /// **'Your library'**
  String get yourLibrarySource;

  /// No description provided for @yourLibraryInline.
  ///
  /// In en, this message translates to:
  /// **'your library'**
  String get yourLibraryInline;

  /// No description provided for @playingFrom.
  ///
  /// In en, this message translates to:
  /// **'Playing from {source}'**
  String playingFrom(Object source);

  /// No description provided for @nothingPlaying.
  ///
  /// In en, this message translates to:
  /// **'Nothing playing'**
  String get nothingPlaying;

  /// No description provided for @quieter.
  ///
  /// In en, this message translates to:
  /// **'Quieter'**
  String get quieter;

  /// No description provided for @louder.
  ///
  /// In en, this message translates to:
  /// **'Louder'**
  String get louder;

  /// No description provided for @linkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get linkCopied;

  /// No description provided for @songNameCopied.
  ///
  /// In en, this message translates to:
  /// **'Song name copied'**
  String get songNameCopied;

  /// No description provided for @sleepTimerWith.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer: {time}'**
  String sleepTimerWith(Object time);

  /// No description provided for @volume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get volume;

  /// No description provided for @speaker.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get speaker;

  /// No description provided for @expandedPlayer.
  ///
  /// In en, this message translates to:
  /// **'Expanded player'**
  String get expandedPlayer;

  /// No description provided for @closeExpandedPlayer.
  ///
  /// In en, this message translates to:
  /// **'Close expanded player'**
  String get closeExpandedPlayer;

  /// No description provided for @hideLyrics.
  ///
  /// In en, this message translates to:
  /// **'Hide lyrics'**
  String get hideLyrics;

  /// No description provided for @nowPlayingView.
  ///
  /// In en, this message translates to:
  /// **'Now playing view'**
  String get nowPlayingView;

  /// No description provided for @hideNowPlayingView.
  ///
  /// In en, this message translates to:
  /// **'Hide now playing view'**
  String get hideNowPlayingView;

  /// No description provided for @moreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptions;

  /// No description provided for @miniPlayer.
  ///
  /// In en, this message translates to:
  /// **'Mini player'**
  String get miniPlayer;

  /// No description provided for @fullScreen.
  ///
  /// In en, this message translates to:
  /// **'Full screen'**
  String get fullScreen;

  /// No description provided for @exitFullScreen.
  ///
  /// In en, this message translates to:
  /// **'Exit full screen'**
  String get exitFullScreen;

  /// No description provided for @sidePanelEmpty.
  ///
  /// In en, this message translates to:
  /// **'Play something and it will show up here.'**
  String get sidePanelEmpty;

  /// No description provided for @nextInQueue.
  ///
  /// In en, this message translates to:
  /// **'Next in queue'**
  String get nextInQueue;

  /// No description provided for @openQueue.
  ///
  /// In en, this message translates to:
  /// **'Open queue'**
  String get openQueue;

  /// No description provided for @nothingAfterThisSong.
  ///
  /// In en, this message translates to:
  /// **'Nothing after this song'**
  String get nothingAfterThisSong;

  /// No description provided for @lyricsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load lyrics. Check your internet connection.'**
  String get lyricsLoadFailed;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @lyricsInstrumental.
  ///
  /// In en, this message translates to:
  /// **'This song is instrumental. Enjoy the music.'**
  String get lyricsInstrumental;

  /// No description provided for @noLyricsFound.
  ///
  /// In en, this message translates to:
  /// **'No lyrics found for this song.'**
  String get noLyricsFound;

  /// No description provided for @useMyLyricsFile.
  ///
  /// In en, this message translates to:
  /// **'Use my lyrics file'**
  String get useMyLyricsFile;

  /// No description provided for @loadingLyrics.
  ///
  /// In en, this message translates to:
  /// **'Loading lyrics'**
  String get loadingLyrics;

  /// No description provided for @lyricsFrom.
  ///
  /// In en, this message translates to:
  /// **'Lyrics from {source}'**
  String lyricsFrom(Object source);

  /// No description provided for @lyricsUntimed.
  ///
  /// In en, this message translates to:
  /// **'These lyrics don\'t follow the song.'**
  String get lyricsUntimed;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @playToSeeLyrics.
  ///
  /// In en, this message translates to:
  /// **'Play a song to see its lyrics here.'**
  String get playToSeeLyrics;

  /// No description provided for @directUsbFailed.
  ///
  /// In en, this message translates to:
  /// **'Direct USB couldn\'t run, so songs play through Android. Turn it on to try again.'**
  String get directUsbFailed;

  /// No description provided for @directUsbClosedWhileStarting.
  ///
  /// In en, this message translates to:
  /// **'Direct USB was turned off because Riflay closed while starting it. Turn it on to try again.'**
  String get directUsbClosedWhileStarting;

  /// No description provided for @directUsbBeta.
  ///
  /// In en, this message translates to:
  /// **'Direct USB (beta)'**
  String get directUsbBeta;

  /// No description provided for @directUsbBetaSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Offers Direct USB below: Riflay plays straight to your USB DAC, past Android. Experimental.'**
  String get directUsbBetaSubtitle;

  /// No description provided for @directUsbWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn on Direct USB?'**
  String get directUsbWarningTitle;

  /// No description provided for @directUsbWarningBody.
  ///
  /// In en, this message translates to:
  /// **'Direct USB is experimental. It may freeze or close Riflay, and it may not work with every phone or DAC. Your DAC can get the sound at full volume, so turn your DAC\'s volume down and take your earphones out before you play. Turning it off goes back to normal output.'**
  String get directUsbWarningBody;

  /// No description provided for @directUsbWarningConfirm.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get directUsbWarningConfirm;

  /// No description provided for @linkNotYoutube.
  ///
  /// In en, this message translates to:
  /// **'There\'s no YouTube link in what was shared.'**
  String get linkNotYoutube;

  /// No description provided for @linkOpening.
  ///
  /// In en, this message translates to:
  /// **'Opening the link…'**
  String get linkOpening;

  /// No description provided for @linkFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open that link. It may be private, removed or region-locked.'**
  String get linkFailed;

  /// No description provided for @streakTitle.
  ///
  /// In en, this message translates to:
  /// **'Listening streak'**
  String get streakTitle;

  /// No description provided for @streakDays.
  ///
  /// In en, this message translates to:
  /// **'{count}-day streak'**
  String streakDays(int count);

  /// No description provided for @streakTooltip.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Listening streak: 1 day} other{Listening streak: {count} days}}'**
  String streakTooltip(int count);

  /// No description provided for @streakSafe.
  ///
  /// In en, this message translates to:
  /// **'You\'ve listened today. See you tomorrow!'**
  String get streakSafe;

  /// No description provided for @streakKeepGoing.
  ///
  /// In en, this message translates to:
  /// **'Play a song today to keep your streak'**
  String get streakKeepGoing;

  /// No description provided for @streakStart.
  ///
  /// In en, this message translates to:
  /// **'Play a song to start a streak'**
  String get streakStart;

  /// No description provided for @streakLongest.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Longest: 1 day} other{Longest: {count} days}}'**
  String streakLongest(int count);

  /// No description provided for @streakToNext.
  ///
  /// In en, this message translates to:
  /// **'{count} more days to the {flame}'**
  String streakToNext(int count, Object flame);

  /// No description provided for @streakTop.
  ///
  /// In en, this message translates to:
  /// **'The highest flame there is'**
  String get streakTop;

  /// No description provided for @flameRed.
  ///
  /// In en, this message translates to:
  /// **'red flame'**
  String get flameRed;

  /// No description provided for @flameGold.
  ///
  /// In en, this message translates to:
  /// **'gold flame'**
  String get flameGold;

  /// No description provided for @flameBlue.
  ///
  /// In en, this message translates to:
  /// **'blue flame'**
  String get flameBlue;

  /// No description provided for @flamePurple.
  ///
  /// In en, this message translates to:
  /// **'purple flame'**
  String get flamePurple;

  /// No description provided for @flameRainbow.
  ///
  /// In en, this message translates to:
  /// **'rainbow flame'**
  String get flameRainbow;

  /// No description provided for @streakRule.
  ///
  /// In en, this message translates to:
  /// **'A day counts once you play a song for 30 seconds or more. Your history stays on this device.'**
  String get streakRule;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'id'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'id':
      return AppLocalizationsId();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
