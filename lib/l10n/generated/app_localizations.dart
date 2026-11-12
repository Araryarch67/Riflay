import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_id.dart';
import 'app_localizations_ja.dart';

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
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('id'), Locale('ja')];

  /// No description provided for @betaFeatures.
  ///
  /// In en, this message translates to:
  /// **'Beta features'**
  String get betaFeatures;

  /// No description provided for @betaFeaturesSummary.
  ///
  /// In en, this message translates to:
  /// **'Experimental features, off by default'**
  String get betaFeaturesSummary;

  /// No description provided for @betaAudioVisualizerBody.
  ///
  /// In en, this message translates to:
  /// **'Experimental: audio bars and effects may not appear on every device. Off by default.'**
  String get betaAudioVisualizerBody;

  /// No description provided for @musicFolderAlreadyAdded.
  ///
  /// In en, this message translates to:
  /// **'This folder is already in your library.'**
  String get musicFolderAlreadyAdded;

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
  /// **'Theme, language and text, Now Playing, lyrics, pages'**
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
  /// **'YouTube Music, Spotify, Last.fm, Discord, extensions'**
  String get groupAccountsSummary;

  /// No description provided for @topicPlayback.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get topicPlayback;

  /// No description provided for @topicPlaybackSummary.
  ///
  /// In en, this message translates to:
  /// **'Autoplay, gapless playback and crossfade'**
  String get topicPlaybackSummary;

  /// No description provided for @topicDsp.
  ///
  /// In en, this message translates to:
  /// **'Sound effects (DSP)'**
  String get topicDsp;

  /// No description provided for @topicDspSummary.
  ///
  /// In en, this message translates to:
  /// **'Equalizer, volume leveling, spatial audio and room correction'**
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
  /// **'Theme & colours'**
  String get topicAppearance;

  /// No description provided for @topicAppearanceSummary.
  ///
  /// In en, this message translates to:
  /// **'Theme, mode, accent colour, cover colours, frosted glass'**
  String get topicAppearanceSummary;

  /// No description provided for @topicLayout.
  ///
  /// In en, this message translates to:
  /// **'Pages & navigation'**
  String get topicLayout;

  /// No description provided for @topicLayoutSummary.
  ///
  /// In en, this message translates to:
  /// **'Home, the bars, corners, spacing, cover size, motion'**
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
  /// **'Discord'**
  String get topicIntegrations;

  /// No description provided for @topicIntegrationsSummary.
  ///
  /// In en, this message translates to:
  /// **'Show what you play on Discord'**
  String get topicIntegrationsSummary;

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
  /// **'Performance & power'**
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

  /// No description provided for @downloadWithMv.
  ///
  /// In en, this message translates to:
  /// **'Download with MV'**
  String get downloadWithMv;

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
  /// **'Performance mode, screen timeout, sleep, background playback and the tray'**
  String get settingsPowerSummaryTray;

  /// No description provided for @settingsPowerSummary.
  ///
  /// In en, this message translates to:
  /// **'Performance mode, screen timeout, sleep and background playback'**
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

  /// No description provided for @removeFromRecentlyPlayed.
  ///
  /// In en, this message translates to:
  /// **'Remove from Recently played'**
  String get removeFromRecentlyPlayed;

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

  /// No description provided for @local.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get local;

  /// No description provided for @folder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get folder;

  /// No description provided for @localEmpty.
  ///
  /// In en, this message translates to:
  /// **'Music folders you add and songs you download show up here.'**
  String get localEmpty;

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
  /// **'Searches your own music and {source} together. Songs with a service icon stream online; the rest play offline.'**
  String searchIntro(String source);

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

  /// No description provided for @watchVideo.
  ///
  /// In en, this message translates to:
  /// **'Watch full screen'**
  String get watchVideo;

  /// No description provided for @showLyrics.
  ///
  /// In en, this message translates to:
  /// **'Show lyrics'**
  String get showLyrics;

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

  /// No description provided for @songsLeft.
  ///
  /// In en, this message translates to:
  /// **'{count} songs left'**
  String songsLeft(int count);

  /// No description provided for @songEndShort.
  ///
  /// In en, this message translates to:
  /// **'Song end'**
  String get songEndShort;

  /// No description provided for @endOfSong.
  ///
  /// In en, this message translates to:
  /// **'End of song'**
  String get endOfSong;

  /// No description provided for @hours.
  ///
  /// In en, this message translates to:
  /// **'Hours'**
  String get hours;

  /// No description provided for @minutes.
  ///
  /// In en, this message translates to:
  /// **'Minutes'**
  String get minutes;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @thisPhone.
  ///
  /// In en, this message translates to:
  /// **'This phone'**
  String get thisPhone;

  /// No description provided for @thisComputer.
  ///
  /// In en, this message translates to:
  /// **'This computer'**
  String get thisComputer;

  /// No description provided for @playOn.
  ///
  /// In en, this message translates to:
  /// **'Play on'**
  String get playOn;

  /// No description provided for @lookingForDevices.
  ///
  /// In en, this message translates to:
  /// **'Looking for TVs and speakers…'**
  String get lookingForDevices;

  /// No description provided for @noDevicesFound.
  ///
  /// In en, this message translates to:
  /// **'No TVs or speakers found. They need to be on and on the same Wi-Fi.'**
  String get noDevicesFound;

  /// No description provided for @castWorksWith.
  ///
  /// In en, this message translates to:
  /// **'Works with TVs, speakers and receivers that support DLNA or AirPlay.'**
  String get castWorksWith;

  /// No description provided for @searchAgain.
  ///
  /// In en, this message translates to:
  /// **'Search again'**
  String get searchAgain;

  /// No description provided for @discordSongCover.
  ///
  /// In en, this message translates to:
  /// **'Song cover'**
  String get discordSongCover;

  /// No description provided for @discordTime.
  ///
  /// In en, this message translates to:
  /// **'Time played and left'**
  String get discordTime;

  /// No description provided for @discordSongInList.
  ///
  /// In en, this message translates to:
  /// **'Song title in the member list'**
  String get discordSongInList;

  /// No description provided for @discordListenButton.
  ///
  /// In en, this message translates to:
  /// **'\"Listen on YouTube Music\" button'**
  String get discordListenButton;

  /// No description provided for @discordWhilePaused.
  ///
  /// In en, this message translates to:
  /// **'Keep showing while paused'**
  String get discordWhilePaused;

  /// No description provided for @discordShowQuality.
  ///
  /// In en, this message translates to:
  /// **'Show the sound quality (FLAC 24/96, Opus 160 kbps)'**
  String get discordShowQuality;

  /// No description provided for @shareLyrics.
  ///
  /// In en, this message translates to:
  /// **'Share lyrics'**
  String get shareLyrics;

  /// No description provided for @lyricCardPick.
  ///
  /// In en, this message translates to:
  /// **'Pick up to {count} lines for the card'**
  String lyricCardPick(int count);

  /// No description provided for @lyricCardCaption.
  ///
  /// In en, this message translates to:
  /// **'“{lines}” — {title} by {artist}, on Riflay'**
  String lyricCardCaption(String lines, String title, String artist);

  /// No description provided for @videoQualityLower.
  ///
  /// In en, this message translates to:
  /// **'Resolution adjusted to your network ({height})'**
  String videoQualityLower(String height);

  /// No description provided for @videoQualityHigher.
  ///
  /// In en, this message translates to:
  /// **'Back up to {height}: your network keeps up'**
  String videoQualityHigher(String height);

  /// No description provided for @showBluetoothCodec.
  ///
  /// In en, this message translates to:
  /// **'Show the Bluetooth codec'**
  String get showBluetoothCodec;

  /// No description provided for @previewYourSong.
  ///
  /// In en, this message translates to:
  /// **'Your song'**
  String get previewYourSong;

  /// No description provided for @previewItsArtist.
  ///
  /// In en, this message translates to:
  /// **'Its artist'**
  String get previewItsArtist;

  /// No description provided for @discordListeningTo.
  ///
  /// In en, this message translates to:
  /// **'Listening to'**
  String get discordListeningTo;

  /// No description provided for @paused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get paused;

  /// No description provided for @playerPresets.
  ///
  /// In en, this message translates to:
  /// **'Player presets'**
  String get playerPresets;

  /// No description provided for @presetsCustomMix.
  ///
  /// In en, this message translates to:
  /// **'Your settings are a custom mix'**
  String get presetsCustomMix;

  /// No description provided for @presetsMatch.
  ///
  /// In en, this message translates to:
  /// **'Your settings match {preset}'**
  String presetsMatch(String preset);

  /// No description provided for @applyPresetQuestion.
  ///
  /// In en, this message translates to:
  /// **'Apply {preset}?'**
  String applyPresetQuestion(String preset);

  /// No description provided for @applyPresetBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This changes 1 player setting. You can still change each one after.} other{This changes {count} player settings. You can still change each one after.}}'**
  String applyPresetBody(int count);

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @inUse.
  ///
  /// In en, this message translates to:
  /// **'In use'**
  String get inUse;

  /// No description provided for @tapToApply.
  ///
  /// In en, this message translates to:
  /// **'Tap to apply'**
  String get tapToApply;

  /// No description provided for @presetCustomNote.
  ///
  /// In en, this message translates to:
  /// **'Your own preset'**
  String get presetCustomNote;

  /// No description provided for @yourPresets.
  ///
  /// In en, this message translates to:
  /// **'Your presets'**
  String get yourPresets;

  /// No description provided for @riflayPresets.
  ///
  /// In en, this message translates to:
  /// **'Riflay presets'**
  String get riflayPresets;

  /// No description provided for @saveAsPreset.
  ///
  /// In en, this message translates to:
  /// **'Save this look as a preset'**
  String get saveAsPreset;

  /// No description provided for @saveAsPresetBody.
  ///
  /// In en, this message translates to:
  /// **'Keeps the player as it is set up now, to put back in one tap.'**
  String get saveAsPresetBody;

  /// No description provided for @presetName.
  ///
  /// In en, this message translates to:
  /// **'Preset name'**
  String get presetName;

  /// No description provided for @presetNameBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'Riflay already has a preset with this name'**
  String get presetNameBuiltIn;

  /// No description provided for @presetNameReplaces.
  ///
  /// In en, this message translates to:
  /// **'Replaces your preset with this name'**
  String get presetNameReplaces;

  /// No description provided for @presetNameTaken.
  ///
  /// In en, this message translates to:
  /// **'You already have a preset with this name'**
  String get presetNameTaken;

  /// No description provided for @renamePreset.
  ///
  /// In en, this message translates to:
  /// **'Rename preset'**
  String get renamePreset;

  /// No description provided for @updatePresetToCurrent.
  ///
  /// In en, this message translates to:
  /// **'Save this look into it'**
  String get updatePresetToCurrent;

  /// No description provided for @deletePresetQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete {preset}?'**
  String deletePresetQuestion(String preset);

  /// No description provided for @deletePresetBody.
  ///
  /// In en, this message translates to:
  /// **'Your player stays as it is; only the preset goes.'**
  String get deletePresetBody;

  /// No description provided for @presetSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved {preset}'**
  String presetSaved(String preset);

  /// No description provided for @autoplayKeepGoing.
  ///
  /// In en, this message translates to:
  /// **'When the queue ends, keep going with similar songs'**
  String get autoplayKeepGoing;

  /// No description provided for @gaplessPlayback.
  ///
  /// In en, this message translates to:
  /// **'Gapless playback'**
  String get gaplessPlayback;

  /// No description provided for @gaplessPlaybackSubtitle.
  ///
  /// In en, this message translates to:
  /// **'No added silence between tracks. Crossfade is under Sound effects (DSP).'**
  String get gaplessPlaybackSubtitle;

  /// No description provided for @skipSilence.
  ///
  /// In en, this message translates to:
  /// **'Skip silence'**
  String get skipSilence;

  /// No description provided for @offWhileBitPerfect.
  ///
  /// In en, this message translates to:
  /// **'Off while bit-perfect mode is on'**
  String get offWhileBitPerfect;

  /// No description provided for @skipSilenceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Silent intros, outros and gaps are cut short. Soft passages play whole'**
  String get skipSilenceSubtitle;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @volumeLeveling.
  ///
  /// In en, this message translates to:
  /// **'Volume leveling'**
  String get volumeLeveling;

  /// No description provided for @volumeLevelingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Plays songs at a similar loudness, using their ReplayGain tags'**
  String get volumeLevelingSubtitle;

  /// No description provided for @measureLoudness.
  ///
  /// In en, this message translates to:
  /// **'Measure songs without ReplayGain tags'**
  String get measureLoudness;

  /// No description provided for @measureLoudnessSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{measured} of {total} songs on this device measured. A song without tags is leveled by what is measured'**
  String measureLoudnessSubtitle(int measured, int total);

  /// No description provided for @measuringLoudness.
  ///
  /// In en, this message translates to:
  /// **'Measuring {done} of {total}…'**
  String measuringLoudness(int done, int total);

  /// No description provided for @measure.
  ///
  /// In en, this message translates to:
  /// **'Measure'**
  String get measure;

  /// No description provided for @crossfade.
  ///
  /// In en, this message translates to:
  /// **'Crossfade'**
  String get crossfade;

  /// No description provided for @crossfadeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The end of a song fades into the start of the next. Off in bit-perfect and exclusive modes'**
  String get crossfadeSubtitle;

  /// No description provided for @fadeLength.
  ///
  /// In en, this message translates to:
  /// **'Fade length'**
  String get fadeLength;

  /// No description provided for @skipForAlbums.
  ///
  /// In en, this message translates to:
  /// **'Skip for albums'**
  String get skipForAlbums;

  /// No description provided for @skipForAlbumsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Songs that follow each other on an album play without a fade, as the artist made them'**
  String get skipForAlbumsSubtitle;

  /// No description provided for @virtualSpeakers.
  ///
  /// In en, this message translates to:
  /// **'Virtual speakers'**
  String get virtualSpeakers;

  /// No description provided for @offWhileMono.
  ///
  /// In en, this message translates to:
  /// **'Off while Mono audio is on'**
  String get offWhileMono;

  /// No description provided for @virtualSpeakersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'For headphones: the music plays in front of you, like from two speakers, instead of inside your head'**
  String get virtualSpeakersSubtitle;

  /// No description provided for @virtualSpeakerLevel.
  ///
  /// In en, this message translates to:
  /// **'Virtual speaker level'**
  String get virtualSpeakerLevel;

  /// No description provided for @virtualSpeakerLevelBody.
  ///
  /// In en, this message translates to:
  /// **'Adjust the simulation output level to match your other listening modes.'**
  String get virtualSpeakerLevelBody;

  /// No description provided for @headphoneCrossfeed.
  ///
  /// In en, this message translates to:
  /// **'Headphone crossfeed'**
  String get headphoneCrossfeed;

  /// No description provided for @crossfeedNotNeeded.
  ///
  /// In en, this message translates to:
  /// **'Not needed with Virtual speakers: they already do this'**
  String get crossfeedNotNeeded;

  /// No description provided for @crossfeedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Makes headphones sound more like speakers in a room'**
  String get crossfeedSubtitle;

  /// No description provided for @crossfeedSoundstage.
  ///
  /// In en, this message translates to:
  /// **'Crossfeed soundstage'**
  String get crossfeedSoundstage;

  /// No description provided for @crossfeedSoundstageBody.
  ///
  /// In en, this message translates to:
  /// **'Adjust the frequency range blended between the left and right channels. Default: 50%.'**
  String get crossfeedSoundstageBody;

  /// No description provided for @monoAudio.
  ///
  /// In en, this message translates to:
  /// **'Mono audio'**
  String get monoAudio;

  /// No description provided for @monoAudioSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Both sides as one sound. Handy when one side of your headphones doesn\'t work'**
  String get monoAudioSubtitle;

  /// No description provided for @audioPlugins.
  ///
  /// In en, this message translates to:
  /// **'Audio plugins'**
  String get audioPlugins;

  /// No description provided for @audioPluginsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'VST, LV2 and CLAP plugins, set up in Carla: add them there and save, and they play here'**
  String get audioPluginsSubtitle;

  /// No description provided for @editInCarla.
  ///
  /// In en, this message translates to:
  /// **'Edit in Carla'**
  String get editInCarla;

  /// No description provided for @needsCarlaDownload.
  ///
  /// In en, this message translates to:
  /// **'Needs Carla, a free program that holds your VST, LV2 and CLAP plugins. Download it, unzip it in your Downloads or Program Files folder, then reopen this page.'**
  String get needsCarlaDownload;

  /// No description provided for @needsCarlaInstall.
  ///
  /// In en, this message translates to:
  /// **'Needs Carla, a free program that holds your VST, LV2 and CLAP plugins. Install it, then reopen this page.'**
  String get needsCarlaInstall;

  /// No description provided for @installCarla.
  ///
  /// In en, this message translates to:
  /// **'Install Carla'**
  String get installCarla;

  /// No description provided for @roomCorrection.
  ///
  /// In en, this message translates to:
  /// **'Room correction'**
  String get roomCorrection;

  /// No description provided for @roomCorrectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Load an impulse response (WAV or FLAC, e.g. made with REW) to correct your room or headphones'**
  String get roomCorrectionSubtitle;

  /// No description provided for @chooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get chooseFile;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @roomCorrectionHeadroom.
  ///
  /// In en, this message translates to:
  /// **'Room correction headroom'**
  String get roomCorrectionHeadroom;

  /// No description provided for @roomCorrectionHeadroomBody.
  ///
  /// In en, this message translates to:
  /// **'Lower the corrected signal if the impulse response makes peaks too loud.'**
  String get roomCorrectionHeadroomBody;

  /// No description provided for @signalPathSubtitle.
  ///
  /// In en, this message translates to:
  /// **'See which effects are actually active for the current song'**
  String get signalPathSubtitle;

  /// No description provided for @resetNamed.
  ///
  /// In en, this message translates to:
  /// **'Reset {name}'**
  String resetNamed(String name);

  /// No description provided for @chooseImpulse.
  ///
  /// In en, this message translates to:
  /// **'Choose an impulse response'**
  String get chooseImpulse;

  /// No description provided for @couldntUseFile.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t use that file'**
  String get couldntUseFile;

  /// No description provided for @output.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get output;

  /// No description provided for @iosOutputNote.
  ///
  /// In en, this message translates to:
  /// **'A USB DAC follows each song\'s sample rate; the speaker and Bluetooth keep one rate. iOS always mixes the sound, so it can\'t be bit-perfect here.'**
  String get iosOutputNote;

  /// No description provided for @outputDevice.
  ///
  /// In en, this message translates to:
  /// **'Output device'**
  String get outputDevice;

  /// No description provided for @directDevicesNote.
  ///
  /// In en, this message translates to:
  /// **'Devices marked \"direct\" skip the system mixer: bit-perfect, but other apps go quiet'**
  String get directDevicesNote;

  /// No description provided for @phonesOwnOutput.
  ///
  /// In en, this message translates to:
  /// **'Your phone\'s own output'**
  String get phonesOwnOutput;

  /// No description provided for @usbDacNamed.
  ///
  /// In en, this message translates to:
  /// **'{name} (USB DAC)'**
  String usbDacNamed(String name);

  /// No description provided for @bitPerfectMode.
  ///
  /// In en, this message translates to:
  /// **'Bit-perfect mode'**
  String get bitPerfectMode;

  /// No description provided for @needsAndroid14.
  ///
  /// In en, this message translates to:
  /// **'Needs Android 14 or later'**
  String get needsAndroid14;

  /// No description provided for @androidFormatsUnplayable.
  ///
  /// In en, this message translates to:
  /// **'Android offers {dac} only in formats Riflay can\'t play bit-perfect ({bitPerfect} of {total} formats). Riflay still plays through your DAC, with Android mixing the sound first.'**
  String androidFormatsUnplayable(String dac, int bitPerfect, int total);

  /// No description provided for @phoneNoBitPerfect.
  ///
  /// In en, this message translates to:
  /// **'This phone doesn\'t offer bit-perfect output for {dac}: its maker leaves it out (Android lists {count} formats for it, none bit-perfect). Riflay still plays through your DAC, with Android mixing the sound first.'**
  String phoneNoBitPerfect(String dac, int count);

  /// No description provided for @plugInDacForBitPerfect.
  ///
  /// In en, this message translates to:
  /// **'Plug in a USB DAC to play bit-perfect'**
  String get plugInDacForBitPerfect;

  /// No description provided for @bitPerfectAndroid.
  ///
  /// In en, this message translates to:
  /// **'Sends the file to your USB DAC untouched: no equalizer, leveling or resampling. Other apps and system sounds are muted on the DAC, and the phone\'s volume keys stop working: use your DAC\'s volume, since lowering Riflay\'s own volume changes the sound.'**
  String get bitPerfectAndroid;

  /// No description provided for @bitPerfectMac.
  ///
  /// In en, this message translates to:
  /// **'No equalizer, leveling or resampling in Riflay, and your DAC follows each song\'s sample rate. Volume still works; at 100% nothing is changed. Other apps keep playing, so macOS still mixes the sound: turn on Exclusive mode too to send the file to your DAC untouched.'**
  String get bitPerfectMac;

  /// No description provided for @bitPerfectWindows.
  ///
  /// In en, this message translates to:
  /// **'No equalizer, leveling or resampling in Riflay. Volume still works; at 100% nothing is changed. Other apps keep playing, so Windows still mixes the sound: turn on Exclusive mode too to send the file to your DAC untouched.'**
  String get bitPerfectWindows;

  /// No description provided for @bitPerfectLinux.
  ///
  /// In en, this message translates to:
  /// **'Sends the file to your DAC untouched: no equalizer, leveling or resampling. Volume still works; at 100% nothing is changed. Takes over your DAC so the system mixer can\'t resample. Meanwhile other apps play through another output.'**
  String get bitPerfectLinux;

  /// No description provided for @nativeDsd.
  ///
  /// In en, this message translates to:
  /// **'Native DSD (DoP)'**
  String get nativeDsd;

  /// No description provided for @nativeDsdSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sends DSD files to your DAC as DSD instead of converting them. Only for DACs that support DoP: others play a faint hiss, so turn it off then. The volume stays at 100% for DSD songs; use your DAC\'s.'**
  String get nativeDsdSubtitle;

  /// No description provided for @needsBitPerfectAndDac.
  ///
  /// In en, this message translates to:
  /// **'Needs Bit-perfect mode and a USB DAC that takes 176.4 kHz or higher'**
  String get needsBitPerfectAndDac;

  /// No description provided for @needsBitPerfectAndExclusive.
  ///
  /// In en, this message translates to:
  /// **'Needs Bit-perfect mode and Exclusive mode'**
  String get needsBitPerfectAndExclusive;

  /// No description provided for @needsBitPerfect.
  ///
  /// In en, this message translates to:
  /// **'Needs Bit-perfect mode'**
  String get needsBitPerfect;

  /// No description provided for @exclusiveMode.
  ///
  /// In en, this message translates to:
  /// **'Exclusive mode'**
  String get exclusiveMode;

  /// No description provided for @exclusiveMac.
  ///
  /// In en, this message translates to:
  /// **'Takes over the device so macOS can\'t mix or resample: the DAC switches to each song\'s sample rate. Other apps go silent while Riflay plays.'**
  String get exclusiveMac;

  /// No description provided for @exclusiveWindows.
  ///
  /// In en, this message translates to:
  /// **'Takes over the device so Windows\' mixer can\'t resample: the DAC switches to each song\'s sample rate. Other apps go silent while Riflay plays, and Windows\' volume mixer can\'t control it.'**
  String get exclusiveWindows;

  /// No description provided for @outputSampleRate.
  ///
  /// In en, this message translates to:
  /// **'Output sample rate'**
  String get outputSampleRate;

  /// No description provided for @followsEachSong.
  ///
  /// In en, this message translates to:
  /// **'Follows each song while bit-perfect mode is on'**
  String get followsEachSong;

  /// No description provided for @followOrConvert.
  ///
  /// In en, this message translates to:
  /// **'Follow the song, or convert everything to one rate'**
  String get followOrConvert;

  /// No description provided for @followTheSong.
  ///
  /// In en, this message translates to:
  /// **'Follow the song'**
  String get followTheSong;

  /// No description provided for @hqResampler.
  ///
  /// In en, this message translates to:
  /// **'High-quality resampler'**
  String get hqResampler;

  /// No description provided for @hqResamplerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'SoX-grade conversion whenever the rate has to change (slightly more CPU)'**
  String get hqResamplerSubtitle;

  /// No description provided for @buffer.
  ///
  /// In en, this message translates to:
  /// **'Buffer'**
  String get buffer;

  /// No description provided for @bufferSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Raise it if you hear crackles or dropouts'**
  String get bufferSubtitle;

  /// No description provided for @signalPathSubtitleExact.
  ///
  /// In en, this message translates to:
  /// **'See exactly what happens to the song you\'re playing'**
  String get signalPathSubtitleExact;

  /// No description provided for @directUsbIntro.
  ///
  /// In en, this message translates to:
  /// **'Riflay talks to your USB DAC itself, past Android, so songs reach it untouched even on phones where Bit-perfect mode can\'t. Experimental.'**
  String get directUsbIntro;

  /// No description provided for @directUsbPlugIn.
  ///
  /// In en, this message translates to:
  /// **'On. Plug in a USB DAC.'**
  String get directUsbPlugIn;

  /// No description provided for @directUsbAllow.
  ///
  /// In en, this message translates to:
  /// **'On. Allow Riflay to use {dac}.'**
  String directUsbAllow(String dac);

  /// No description provided for @directUsbBitPerfectTo.
  ///
  /// In en, this message translates to:
  /// **'Bit-perfect to {dac}'**
  String directUsbBitPerfectTo(String dac);

  /// No description provided for @directUsbFallback.
  ///
  /// In en, this message translates to:
  /// **'This song{format} is in a format {dac} doesn\'t take, so it plays through Android.'**
  String directUsbFallback(String format, String dac);

  /// No description provided for @directUsbOnWith.
  ///
  /// In en, this message translates to:
  /// **'On, with {dac}. Play a song.'**
  String directUsbOnWith(String dac);

  /// No description provided for @allowUsbAccess.
  ///
  /// In en, this message translates to:
  /// **'Allow USB access'**
  String get allowUsbAccess;

  /// No description provided for @problemWith.
  ///
  /// In en, this message translates to:
  /// **'Problem: {error}'**
  String problemWith(String error);

  /// No description provided for @directUsbPipe.
  ///
  /// In en, this message translates to:
  /// **'Pipe: {state} · Output: {output}'**
  String directUsbPipe(String state, String output);

  /// No description provided for @pipeOpen.
  ///
  /// In en, this message translates to:
  /// **'open'**
  String get pipeOpen;

  /// No description provided for @pipeClosed.
  ///
  /// In en, this message translates to:
  /// **'closed'**
  String get pipeClosed;

  /// No description provided for @fromThePlayer.
  ///
  /// In en, this message translates to:
  /// **'From the player: {format}'**
  String fromThePlayer(String format);

  /// No description provided for @directUsbRoute.
  ///
  /// In en, this message translates to:
  /// **'Route: {route}'**
  String directUsbRoute(String route);

  /// No description provided for @dropouts.
  ///
  /// In en, this message translates to:
  /// **'Dropouts: {count}'**
  String dropouts(String count);

  /// No description provided for @directUsb.
  ///
  /// In en, this message translates to:
  /// **'Direct USB'**
  String get directUsb;

  /// No description provided for @styleClassic.
  ///
  /// In en, this message translates to:
  /// **'Classic'**
  String get styleClassic;

  /// No description provided for @styleCompact.
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get styleCompact;

  /// No description provided for @styleMinimal.
  ///
  /// In en, this message translates to:
  /// **'Minimal'**
  String get styleMinimal;

  /// No description provided for @vizWave.
  ///
  /// In en, this message translates to:
  /// **'Wave'**
  String get vizWave;

  /// No description provided for @vizBars.
  ///
  /// In en, this message translates to:
  /// **'Bars'**
  String get vizBars;

  /// No description provided for @vizLine.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get vizLine;

  /// No description provided for @vizDots.
  ///
  /// In en, this message translates to:
  /// **'Dots'**
  String get vizDots;

  /// No description provided for @vizMirror.
  ///
  /// In en, this message translates to:
  /// **'Mirror'**
  String get vizMirror;

  /// No description provided for @vizTwinWaves.
  ///
  /// In en, this message translates to:
  /// **'Twin waves'**
  String get vizTwinWaves;

  /// No description provided for @vizPulse.
  ///
  /// In en, this message translates to:
  /// **'Pulse'**
  String get vizPulse;

  /// No description provided for @vizOrbit.
  ///
  /// In en, this message translates to:
  /// **'Orbit'**
  String get vizOrbit;

  /// No description provided for @vizPetals.
  ///
  /// In en, this message translates to:
  /// **'Petals'**
  String get vizPetals;

  /// No description provided for @vizPeaks.
  ///
  /// In en, this message translates to:
  /// **'Peaks'**
  String get vizPeaks;

  /// No description provided for @shapeFlower.
  ///
  /// In en, this message translates to:
  /// **'Flower'**
  String get shapeFlower;

  /// No description provided for @shapeSquare.
  ///
  /// In en, this message translates to:
  /// **'Square'**
  String get shapeSquare;

  /// No description provided for @shapeRounded.
  ///
  /// In en, this message translates to:
  /// **'Rounded'**
  String get shapeRounded;

  /// No description provided for @shapeExtraRound.
  ///
  /// In en, this message translates to:
  /// **'Extra round'**
  String get shapeExtraRound;

  /// No description provided for @densityComfortable.
  ///
  /// In en, this message translates to:
  /// **'Comfortable'**
  String get densityComfortable;

  /// No description provided for @sizeSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get sizeSmall;

  /// No description provided for @sizeMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get sizeMedium;

  /// No description provided for @sizeLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get sizeLarge;

  /// No description provided for @motionFull.
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get motionFull;

  /// No description provided for @motionReduced.
  ///
  /// In en, this message translates to:
  /// **'Reduced'**
  String get motionReduced;

  /// No description provided for @decoderAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get decoderAuto;

  /// No description provided for @decoderGpu.
  ///
  /// In en, this message translates to:
  /// **'Graphics card'**
  String get decoderGpu;

  /// No description provided for @decoderCpu.
  ///
  /// In en, this message translates to:
  /// **'Processor'**
  String get decoderCpu;

  /// No description provided for @decoderAutoNote.
  ///
  /// In en, this message translates to:
  /// **'The graphics card when it is known to work, else the processor'**
  String get decoderAutoNote;

  /// No description provided for @decoderGpuNote.
  ///
  /// In en, this message translates to:
  /// **'Always try the graphics card first. Lightest, if your drivers cope'**
  String get decoderGpuNote;

  /// No description provided for @decoderCpuNote.
  ///
  /// In en, this message translates to:
  /// **'Never the graphics card. Uses more power; try it if videos look wrong'**
  String get decoderCpuNote;

  /// No description provided for @perfLight.
  ///
  /// In en, this message translates to:
  /// **'Lightweight'**
  String get perfLight;

  /// No description provided for @perfBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get perfBalanced;

  /// No description provided for @perfHeavy.
  ///
  /// In en, this message translates to:
  /// **'Heavy'**
  String get perfHeavy;

  /// No description provided for @perfLightNote.
  ///
  /// In en, this message translates to:
  /// **'Fewest effects. Best for older computers and battery.'**
  String get perfLightNote;

  /// No description provided for @perfBalancedNote.
  ///
  /// In en, this message translates to:
  /// **'Smooth animations with sensible limits.'**
  String get perfBalancedNote;

  /// No description provided for @perfHeavyNote.
  ///
  /// In en, this message translates to:
  /// **'Every effect at full speed. Uses more power.'**
  String get perfHeavyNote;

  /// No description provided for @styleThin.
  ///
  /// In en, this message translates to:
  /// **'Thin'**
  String get styleThin;

  /// No description provided for @styleThick.
  ///
  /// In en, this message translates to:
  /// **'Thick'**
  String get styleThick;

  /// No description provided for @shapeStraight.
  ///
  /// In en, this message translates to:
  /// **'Straight'**
  String get shapeStraight;

  /// No description provided for @shapeWavy.
  ///
  /// In en, this message translates to:
  /// **'Wavy'**
  String get shapeWavy;

  /// No description provided for @shapePill.
  ///
  /// In en, this message translates to:
  /// **'Pill'**
  String get shapePill;

  /// No description provided for @shapeThinLine.
  ///
  /// In en, this message translates to:
  /// **'Thin line'**
  String get shapeThinLine;

  /// No description provided for @shapeWaveform.
  ///
  /// In en, this message translates to:
  /// **'Waveform'**
  String get shapeWaveform;

  /// No description provided for @shapeCircle.
  ///
  /// In en, this message translates to:
  /// **'Circle'**
  String get shapeCircle;

  /// No description provided for @shapeRoundedSquare.
  ///
  /// In en, this message translates to:
  /// **'Rounded square'**
  String get shapeRoundedSquare;

  /// No description provided for @sizeNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get sizeNormal;

  /// No description provided for @coverBackground.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get coverBackground;

  /// No description provided for @headerCentred.
  ///
  /// In en, this message translates to:
  /// **'Centred'**
  String get headerCentred;

  /// No description provided for @headerPlayingFrom.
  ///
  /// In en, this message translates to:
  /// **'Playing from'**
  String get headerPlayingFrom;

  /// No description provided for @styleBoxed.
  ///
  /// In en, this message translates to:
  /// **'Boxed'**
  String get styleBoxed;

  /// No description provided for @stylePlain.
  ///
  /// In en, this message translates to:
  /// **'Plain'**
  String get stylePlain;

  /// No description provided for @styleChips.
  ///
  /// In en, this message translates to:
  /// **'Chips'**
  String get styleChips;

  /// No description provided for @styleIcons.
  ///
  /// In en, this message translates to:
  /// **'Icons'**
  String get styleIcons;

  /// No description provided for @styleBottomCard.
  ///
  /// In en, this message translates to:
  /// **'Bottom card'**
  String get styleBottomCard;

  /// No description provided for @styleTopHeader.
  ///
  /// In en, this message translates to:
  /// **'Top header'**
  String get styleTopHeader;

  /// No description provided for @styleFloatingPill.
  ///
  /// In en, this message translates to:
  /// **'Floating pill'**
  String get styleFloatingPill;

  /// No description provided for @styleHero.
  ///
  /// In en, this message translates to:
  /// **'Hero'**
  String get styleHero;

  /// No description provided for @badgeUnderArtist.
  ///
  /// In en, this message translates to:
  /// **'Under the artist'**
  String get badgeUnderArtist;

  /// No description provided for @badgeTimeRow.
  ///
  /// In en, this message translates to:
  /// **'In the time row'**
  String get badgeTimeRow;

  /// No description provided for @styleHighlightedCard.
  ///
  /// In en, this message translates to:
  /// **'Highlighted card'**
  String get styleHighlightedCard;

  /// No description provided for @sizeLargest.
  ///
  /// In en, this message translates to:
  /// **'Largest'**
  String get sizeLargest;

  /// No description provided for @lyricsFocused.
  ///
  /// In en, this message translates to:
  /// **'Focused'**
  String get lyricsFocused;

  /// No description provided for @lyricsWordByWord.
  ///
  /// In en, this message translates to:
  /// **'Word by word'**
  String get lyricsWordByWord;

  /// No description provided for @lyricsLineByLine.
  ///
  /// In en, this message translates to:
  /// **'Line by line'**
  String get lyricsLineByLine;

  /// No description provided for @alignLeft.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get alignLeft;

  /// No description provided for @alignCentre.
  ///
  /// In en, this message translates to:
  /// **'Centre'**
  String get alignCentre;

  /// No description provided for @styleMaterial.
  ///
  /// In en, this message translates to:
  /// **'Material'**
  String get styleMaterial;

  /// No description provided for @styleUnderline.
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get styleUnderline;

  /// No description provided for @styleTextOnly.
  ///
  /// In en, this message translates to:
  /// **'Text only'**
  String get styleTextOnly;

  /// No description provided for @styleFloating.
  ///
  /// In en, this message translates to:
  /// **'Floating'**
  String get styleFloating;

  /// No description provided for @styleCapsule.
  ///
  /// In en, this message translates to:
  /// **'Capsule'**
  String get styleCapsule;

  /// No description provided for @styleDock.
  ///
  /// In en, this message translates to:
  /// **'Dock'**
  String get styleDock;

  /// No description provided for @styleCentreButton.
  ///
  /// In en, this message translates to:
  /// **'Centre button'**
  String get styleCentreButton;

  /// No description provided for @styleLiquidGlass.
  ///
  /// In en, this message translates to:
  /// **'Liquid glass'**
  String get styleLiquidGlass;

  /// No description provided for @quickPicks.
  ///
  /// In en, this message translates to:
  /// **'Quick picks'**
  String get quickPicks;

  /// No description provided for @fromYoutubeMusic.
  ///
  /// In en, this message translates to:
  /// **'From YouTube Music'**
  String get fromYoutubeMusic;

  /// No description provided for @presets.
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get presets;

  /// No description provided for @custom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get custom;

  /// No description provided for @matchesPreset.
  ///
  /// In en, this message translates to:
  /// **'Matches {preset}'**
  String matchesPreset(String preset);

  /// No description provided for @fullScreenPlayerHint.
  ///
  /// In en, this message translates to:
  /// **'The full-screen player'**
  String get fullScreenPlayerHint;

  /// No description provided for @cover.
  ///
  /// In en, this message translates to:
  /// **'Cover'**
  String get cover;

  /// No description provided for @coverSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Square or flower frame the cover. Background has no frame: it fills the top and fades into the page'**
  String get coverSubtitle;

  /// No description provided for @coverSizeOnPhones.
  ///
  /// In en, this message translates to:
  /// **'Cover size on phones'**
  String get coverSizeOnPhones;

  /// No description provided for @coverSizeOnPhonesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Large reaches nearly the edges of the screen'**
  String get coverSizeOnPhonesSubtitle;

  /// No description provided for @topOfPlayer.
  ///
  /// In en, this message translates to:
  /// **'Top of the player'**
  String get topOfPlayer;

  /// No description provided for @topOfPlayerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'What the top shows beside the close arrow, or above the song on desktop'**
  String get topOfPlayerSubtitle;

  /// No description provided for @buttonsByTitle.
  ///
  /// In en, this message translates to:
  /// **'Buttons by the title'**
  String get buttonsByTitle;

  /// No description provided for @buttonsByTitleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Like and More as they are, a joined Share and heart pair, or plain icons. The song menu stays on desktop'**
  String get buttonsByTitleSubtitle;

  /// No description provided for @showSoundQuality.
  ///
  /// In en, this message translates to:
  /// **'Show sound quality'**
  String get showSoundQuality;

  /// No description provided for @showSoundQualitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'The small label under the song title, such as FLAC or Hi-Res'**
  String get showSoundQualitySubtitle;

  /// No description provided for @songVideoSwitch.
  ///
  /// In en, this message translates to:
  /// **'Song / Video switch'**
  String get songVideoSwitch;

  /// No description provided for @songVideoSwitchSubtitle.
  ///
  /// In en, this message translates to:
  /// **'At the top of Now Playing. Adaptive shows it only when the song has a music video'**
  String get songVideoSwitchSubtitle;

  /// No description provided for @adaptive.
  ///
  /// In en, this message translates to:
  /// **'Adaptive'**
  String get adaptive;

  /// No description provided for @qualityBadge.
  ///
  /// In en, this message translates to:
  /// **'Quality badge'**
  String get qualityBadge;

  /// No description provided for @qualityBadgeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Where FLAC or Opus 130 kbps sits on the phone player: under the artist, or between the two times'**
  String get qualityBadgeSubtitle;

  /// No description provided for @background.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get background;

  /// No description provided for @backgroundSubtitle.
  ///
  /// In en, this message translates to:
  /// **'What fills the page behind the player. Cover: Background replaces it'**
  String get backgroundSubtitle;

  /// No description provided for @videoMode.
  ///
  /// In en, this message translates to:
  /// **'Video mode'**
  String get videoMode;

  /// No description provided for @videoModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Watch music videos in sync with the song'**
  String get videoModeSubtitle;

  /// No description provided for @videoDecoding.
  ///
  /// In en, this message translates to:
  /// **'Video decoding'**
  String get videoDecoding;

  /// No description provided for @decoderNow.
  ///
  /// In en, this message translates to:
  /// **'Now: {decoder}'**
  String decoderNow(String decoder);

  /// No description provided for @decoderNowCpu.
  ///
  /// In en, this message translates to:
  /// **'the processor'**
  String get decoderNowCpu;

  /// No description provided for @decoderNowGpu.
  ///
  /// In en, this message translates to:
  /// **'graphics card ({hwdec})'**
  String decoderNowGpu(String hwdec);

  /// No description provided for @playbackControls.
  ///
  /// In en, this message translates to:
  /// **'Playback controls'**
  String get playbackControls;

  /// No description provided for @playbackControlsHint.
  ///
  /// In en, this message translates to:
  /// **'The progress bar, the buttons and the row under them'**
  String get playbackControlsHint;

  /// No description provided for @progressBarShape.
  ///
  /// In en, this message translates to:
  /// **'Progress bar shape'**
  String get progressBarShape;

  /// No description provided for @progressBar.
  ///
  /// In en, this message translates to:
  /// **'Progress bar'**
  String get progressBar;

  /// No description provided for @progressBarSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How thick the bar you drag to skip around is'**
  String get progressBarSubtitle;

  /// No description provided for @showTimeLeft.
  ///
  /// In en, this message translates to:
  /// **'Show time left'**
  String get showTimeLeft;

  /// No description provided for @showTimeLeftSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The right time counts down instead of showing the total, also on the desktop bar'**
  String get showTimeLeftSubtitle;

  /// No description provided for @controls.
  ///
  /// In en, this message translates to:
  /// **'Controls'**
  String get controls;

  /// No description provided for @controlsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Previous, play and next as circles, a wide Play pill, or plain big icons, also on the desktop bar'**
  String get controlsSubtitle;

  /// No description provided for @playButton.
  ///
  /// In en, this message translates to:
  /// **'Play button'**
  String get playButton;

  /// No description provided for @playButtonSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The shape of the big play and pause button'**
  String get playButtonSubtitle;

  /// No description provided for @volumeSlider.
  ///
  /// In en, this message translates to:
  /// **'Volume slider'**
  String get volumeSlider;

  /// No description provided for @volumeSliderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'At the very bottom of the phone player. Off, it opens from the speaker button (Icons) or the desktop bar button'**
  String get volumeSliderSubtitle;

  /// No description provided for @sliderLook.
  ///
  /// In en, this message translates to:
  /// **'Slider look'**
  String get sliderLook;

  /// No description provided for @sliderLookSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Every slider: volume, the equalizer and settings. Classic, a thin line, or a thick pill with a bar handle'**
  String get sliderLookSubtitle;

  /// No description provided for @bottomButtons.
  ///
  /// In en, this message translates to:
  /// **'Bottom buttons'**
  String get bottomButtons;

  /// No description provided for @bottomButtonsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Lyrics and Queue; a joined row of icon buttons; or Lyrics, a speaker and person capsule and Queue. Icons only, Lyrics is always there'**
  String get bottomButtonsSubtitle;

  /// No description provided for @lyricsHint.
  ///
  /// In en, this message translates to:
  /// **'The lyrics page, and the lyrics beside the cover on desktop'**
  String get lyricsHint;

  /// No description provided for @lyricsPage.
  ///
  /// In en, this message translates to:
  /// **'Lyrics page'**
  String get lyricsPage;

  /// No description provided for @lyricsPageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Where the player sits on the lyrics page. Desktop gets a song card on top or at the bottom'**
  String get lyricsPageSubtitle;

  /// No description provided for @linesShown.
  ///
  /// In en, this message translates to:
  /// **'Lines shown'**
  String get linesShown;

  /// No description provided for @linesShownSubtitle.
  ///
  /// In en, this message translates to:
  /// **'All keeps the whole song in view. Focused shows only the previous, the current and the next line'**
  String get linesShownSubtitle;

  /// No description provided for @sync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get sync;

  /// No description provided for @syncSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Word by word fills each word as it is sung, where the lyrics have word timings. Line by line lights the whole line'**
  String get syncSubtitle;

  /// No description provided for @textSize.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get textSize;

  /// No description provided for @lyricsTextSizeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How big the lyrics are'**
  String get lyricsTextSizeSubtitle;

  /// No description provided for @alignment.
  ///
  /// In en, this message translates to:
  /// **'Alignment'**
  String get alignment;

  /// No description provided for @alignmentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Lines start at the left edge, or sit in the middle'**
  String get alignmentSubtitle;

  /// No description provided for @dimUnsung.
  ///
  /// In en, this message translates to:
  /// **'Dim lines not yet sung'**
  String get dimUnsung;

  /// No description provided for @dimUnsungSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Only the line being sung and the ones before it stay bright'**
  String get dimUnsungSubtitle;

  /// No description provided for @highlightLyricLine.
  ///
  /// In en, this message translates to:
  /// **'Highlight the line being sung'**
  String get highlightLyricLine;

  /// No description provided for @highlightLyricLineSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A faint pane of dark frosted glass behind the whole line'**
  String get highlightLyricLineSubtitle;

  /// No description provided for @lockScreenLyrics.
  ///
  /// In en, this message translates to:
  /// **'Lyrics on the lock screen'**
  String get lockScreenLyrics;

  /// No description provided for @lockScreenLyricsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The line being sung takes the artist\'s place in the notification, on the lock screen and on a car\'s display. With Pronunciation on in the lyrics, a line in another script shows how it\'s read too'**
  String get lockScreenLyricsSubtitle;

  /// No description provided for @visualizer.
  ///
  /// In en, this message translates to:
  /// **'Visualizer'**
  String get visualizer;

  /// No description provided for @visualizerHint.
  ///
  /// In en, this message translates to:
  /// **'Shapes that move with the music'**
  String get visualizerHint;

  /// No description provided for @pages.
  ///
  /// In en, this message translates to:
  /// **'Pages'**
  String get pages;

  /// No description provided for @pagesHint.
  ///
  /// In en, this message translates to:
  /// **'Album, playlist and artist pages, song lists and Home'**
  String get pagesHint;

  /// No description provided for @albumPlaylistTop.
  ///
  /// In en, this message translates to:
  /// **'Album and playlist top'**
  String get albumPlaylistTop;

  /// No description provided for @albumPlaylistTopSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hero: a big cover fading behind the title, round buttons around a Play pill. Also on artist pages'**
  String get albumPlaylistTopSubtitle;

  /// No description provided for @songThatIsPlaying.
  ///
  /// In en, this message translates to:
  /// **'Song that is playing'**
  String get songThatIsPlaying;

  /// No description provided for @songThatIsPlayingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'In a list of songs: coloured text, or a filled rounded card with the bars'**
  String get songThatIsPlayingSubtitle;

  /// No description provided for @bars.
  ///
  /// In en, this message translates to:
  /// **'Bars'**
  String get bars;

  /// No description provided for @barsHint.
  ///
  /// In en, this message translates to:
  /// **'The mini player and the bars that hold the controls'**
  String get barsHint;

  /// No description provided for @miniPlayerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The bar above the tabs when a song plays, on phones. Floating pill has a flower cover and round buttons'**
  String get miniPlayerSubtitle;

  /// No description provided for @tabBarOnPhones.
  ///
  /// In en, this message translates to:
  /// **'Tab bar on phones'**
  String get tabBarOnPhones;

  /// No description provided for @tabBarOnPhonesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Classic sits at the bottom edge; Floating and Liquid glass hover above it'**
  String get tabBarOnPhonesSubtitle;

  /// No description provided for @desktopPlayerBar.
  ///
  /// In en, this message translates to:
  /// **'Desktop player bar'**
  String get desktopPlayerBar;

  /// No description provided for @desktopPlayerBarSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Along the window\'s foot: full-width controls, a compact row beside the song, or a minimal strip'**
  String get desktopPlayerBarSubtitle;

  /// No description provided for @shapesAndMotion.
  ///
  /// In en, this message translates to:
  /// **'Shapes and motion'**
  String get shapesAndMotion;

  /// No description provided for @motionOffLightweight.
  ///
  /// In en, this message translates to:
  /// **'Performance is set to Lightweight, so the motion settings stay off.'**
  String get motionOffLightweight;

  /// No description provided for @corners.
  ///
  /// In en, this message translates to:
  /// **'Corners'**
  String get corners;

  /// No description provided for @cornersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Covers, cards, menus, dialogs and the mini player'**
  String get cornersSubtitle;

  /// No description provided for @spacing.
  ///
  /// In en, this message translates to:
  /// **'Spacing'**
  String get spacing;

  /// No description provided for @spacingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Compact fits more songs and cards on screen'**
  String get spacingSubtitle;

  /// No description provided for @coverSizeInGrids.
  ///
  /// In en, this message translates to:
  /// **'Cover size in grids'**
  String get coverSizeInGrids;

  /// No description provided for @coverSizeInGridsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The albums and playlists on Home and in \"Show all\"'**
  String get coverSizeInGridsSubtitle;

  /// No description provided for @transitionStyle.
  ///
  /// In en, this message translates to:
  /// **'Transition style'**
  String get transitionStyle;

  /// No description provided for @transitionStyleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Coordinated page, tab and player transitions'**
  String get transitionStyleSubtitle;

  /// No description provided for @transitionSpeed.
  ///
  /// In en, this message translates to:
  /// **'Transition speed'**
  String get transitionSpeed;

  /// No description provided for @transitionSpeedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a brisk or more relaxed pace'**
  String get transitionSpeedSubtitle;

  /// No description provided for @animations.
  ///
  /// In en, this message translates to:
  /// **'Animations'**
  String get animations;

  /// No description provided for @animationsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reduced keeps quick fades only. Full follows your system when it asks for less motion'**
  String get animationsSubtitle;

  /// No description provided for @window.
  ///
  /// In en, this message translates to:
  /// **'Window'**
  String get window;

  /// No description provided for @desktopOnly.
  ///
  /// In en, this message translates to:
  /// **'Desktop only'**
  String get desktopOnly;

  /// No description provided for @windowButtons.
  ///
  /// In en, this message translates to:
  /// **'Window buttons'**
  String get windowButtons;

  /// No description provided for @windowButtonsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Minimize, maximize and close in the title bar. Turn off with a tiling window manager'**
  String get windowButtonsSubtitle;

  /// No description provided for @resetLayout.
  ///
  /// In en, this message translates to:
  /// **'Reset layout to default'**
  String get resetLayout;

  /// No description provided for @dragToReorderSections.
  ///
  /// In en, this message translates to:
  /// **'Drag the handle to put sections in a different order'**
  String get dragToReorderSections;

  /// No description provided for @audioVisualizer.
  ///
  /// In en, this message translates to:
  /// **'Audio visualizer'**
  String get audioVisualizer;

  /// No description provided for @audioVisualizerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Shapes that move with the music around the cover and under it'**
  String get audioVisualizerSubtitle;

  /// No description provided for @visualizerStyle.
  ///
  /// In en, this message translates to:
  /// **'Visualizer style'**
  String get visualizerStyle;

  /// No description provided for @visualizerStyleBackground.
  ///
  /// In en, this message translates to:
  /// **'A strip under the song. Pulse, Orbit and Petals ring the cover: pick Square or Flower for them'**
  String get visualizerStyleBackground;

  /// No description provided for @visualizerStyleRings.
  ///
  /// In en, this message translates to:
  /// **'Rings the cover'**
  String get visualizerStyleRings;

  /// No description provided for @visualizerStyleEdge.
  ///
  /// In en, this message translates to:
  /// **'Moves along the cover\'s edge, with a strip under the song'**
  String get visualizerStyleEdge;

  /// No description provided for @radiusMovement.
  ///
  /// In en, this message translates to:
  /// **'Radius movement'**
  String get radiusMovement;

  /// No description provided for @radiusMovementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{percent}% · How far the shape expands with the music'**
  String radiusMovementSubtitle(String percent);

  /// No description provided for @lineThickness.
  ///
  /// In en, this message translates to:
  /// **'Line thickness'**
  String get lineThickness;

  /// No description provided for @signedInAs.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {name}'**
  String signedInAs(String name);

  /// No description provided for @ytSignedInBody.
  ///
  /// In en, this message translates to:
  /// **'Signed in. Your likes, playlists and followed artists are here.'**
  String get ytSignedInBody;

  /// No description provided for @ytSignedOutBody.
  ///
  /// In en, this message translates to:
  /// **'Not signed in. Search and the public home work without an account.'**
  String get ytSignedOutBody;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @addToYtHistory.
  ///
  /// In en, this message translates to:
  /// **'Add songs you play to your YouTube Music history'**
  String get addToYtHistory;

  /// No description provided for @addToYtHistorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Like the official app, so YouTube Music keeps learning what you like.'**
  String get addToYtHistorySubtitle;

  /// No description provided for @musixmatchLyrics.
  ///
  /// In en, this message translates to:
  /// **'Musixmatch lyrics'**
  String get musixmatchLyrics;

  /// No description provided for @musixmatchLyricsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Find word-by-word lyrics when other sources have none'**
  String get musixmatchLyricsSubtitle;

  /// No description provided for @discordRichPresence.
  ///
  /// In en, this message translates to:
  /// **'Discord Rich Presence'**
  String get discordRichPresence;

  /// No description provided for @discordRichPresenceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show what you\'re listening to on your Discord profile'**
  String get discordRichPresenceSubtitle;

  /// No description provided for @betterLyricsKey.
  ///
  /// In en, this message translates to:
  /// **'Better Lyrics API key'**
  String get betterLyricsKey;

  /// No description provided for @betterLyricsKeyOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional. Lets Better Lyrics find lyrics it hasn\'t saved yet, if you have a key.'**
  String get betterLyricsKeyOptional;

  /// No description provided for @betterLyricsKeyAdded.
  ///
  /// In en, this message translates to:
  /// **'Added. Better Lyrics can find lyrics it hasn\'t saved yet.'**
  String get betterLyricsKeyAdded;

  /// No description provided for @crumbsThen.
  ///
  /// In en, this message translates to:
  /// **'{crumbs}, then {current}'**
  String crumbsThen(String crumbs, String current);

  /// No description provided for @crumbsJoin.
  ///
  /// In en, this message translates to:
  /// **', then '**
  String get crumbsJoin;

  /// No description provided for @betterLyricsKeyInvalid.
  ///
  /// In en, this message translates to:
  /// **'Better Lyrics says this key isn\'t valid.'**
  String get betterLyricsKeyInvalid;

  /// No description provided for @betterLyricsUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach Better Lyrics to check the key. Try again.'**
  String get betterLyricsUnreachable;

  /// No description provided for @betterLyricsKeyBody.
  ///
  /// In en, this message translates to:
  /// **'Without a key, lyrics from Better Lyrics still work for every song it has saved. Better Lyrics isn\'t giving out new keys right now.'**
  String get betterLyricsKeyBody;

  /// No description provided for @apiKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get apiKey;

  /// No description provided for @checking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get checking;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @statsNothingPlaying.
  ///
  /// In en, this message translates to:
  /// **'Nothing is playing.'**
  String get statsNothingPlaying;

  /// No description provided for @statsOtherDevice.
  ///
  /// In en, this message translates to:
  /// **'Playing on another device: the stats come from the device playing.'**
  String get statsOtherDevice;

  /// No description provided for @waitingForAudio.
  ///
  /// In en, this message translates to:
  /// **'Waiting for audio…'**
  String get waitingForAudio;

  /// No description provided for @statsCopied.
  ///
  /// In en, this message translates to:
  /// **'Stats copied'**
  String get statsCopied;

  /// No description provided for @copyStats.
  ///
  /// In en, this message translates to:
  /// **'Copy stats'**
  String get copyStats;

  /// No description provided for @statsHint.
  ///
  /// In en, this message translates to:
  /// **'Updates every second. Copy them to paste into a bug report.'**
  String get statsHint;

  /// No description provided for @themeLegacy.
  ///
  /// In en, this message translates to:
  /// **'Legacy'**
  String get themeLegacy;

  /// No description provided for @themeDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get themeDefault;

  /// No description provided for @themeMonochrome.
  ///
  /// In en, this message translates to:
  /// **'Monochrome'**
  String get themeMonochrome;

  /// No description provided for @modeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get modeDark;

  /// No description provided for @modeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get modeLight;

  /// No description provided for @modeBlack.
  ///
  /// In en, this message translates to:
  /// **'Black'**
  String get modeBlack;

  /// No description provided for @modeSystem.
  ///
  /// In en, this message translates to:
  /// **'Match system'**
  String get modeSystem;

  /// No description provided for @accentTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get accentTheme;

  /// No description provided for @accentTeal.
  ///
  /// In en, this message translates to:
  /// **'Teal'**
  String get accentTeal;

  /// No description provided for @accentGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get accentGreen;

  /// No description provided for @accentBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get accentBlue;

  /// No description provided for @accentViolet.
  ///
  /// In en, this message translates to:
  /// **'Violet'**
  String get accentViolet;

  /// No description provided for @accentPink.
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get accentPink;

  /// No description provided for @accentOrange.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get accentOrange;

  /// No description provided for @accentWhite.
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get accentWhite;

  /// No description provided for @customEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Custom…'**
  String get customEllipsis;

  /// No description provided for @coverColorPlayer.
  ///
  /// In en, this message translates to:
  /// **'Player only'**
  String get coverColorPlayer;

  /// No description provided for @coverColorApp.
  ///
  /// In en, this message translates to:
  /// **'Whole app'**
  String get coverColorApp;

  /// No description provided for @npBgSimple.
  ///
  /// In en, this message translates to:
  /// **'Simple'**
  String get npBgSimple;

  /// No description provided for @npBgBlurredCover.
  ///
  /// In en, this message translates to:
  /// **'Blurred cover'**
  String get npBgBlurredCover;

  /// No description provided for @npBgMusicVideo.
  ///
  /// In en, this message translates to:
  /// **'Music video'**
  String get npBgMusicVideo;

  /// No description provided for @npBgMusicVideoHint.
  ///
  /// In en, this message translates to:
  /// **'The song\'s music video, when it has one'**
  String get npBgMusicVideoHint;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @matugenColors.
  ///
  /// In en, this message translates to:
  /// **'Matugen colors'**
  String get matugenColors;

  /// No description provided for @matugenChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose a generated JSON file. Colors update automatically.'**
  String get matugenChoose;

  /// No description provided for @matugenFollowing.
  ///
  /// In en, this message translates to:
  /// **'Following generated colors automatically'**
  String get matugenFollowing;

  /// No description provided for @matugenFind.
  ///
  /// In en, this message translates to:
  /// **'Find generated colors automatically'**
  String get matugenFind;

  /// No description provided for @coloursFromCover.
  ///
  /// In en, this message translates to:
  /// **'Colours come from the cover of what\'s playing'**
  String get coloursFromCover;

  /// No description provided for @backgroundColour.
  ///
  /// In en, this message translates to:
  /// **'Background colour'**
  String get backgroundColour;

  /// No description provided for @backgroundColourSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Panels, cards and menus are worked out from it'**
  String get backgroundColourSubtitle;

  /// No description provided for @textColour.
  ///
  /// In en, this message translates to:
  /// **'Text colour'**
  String get textColour;

  /// No description provided for @textColourAuto.
  ///
  /// In en, this message translates to:
  /// **'Chosen to suit the background'**
  String get textColourAuto;

  /// No description provided for @textColourAdjusted.
  ///
  /// In en, this message translates to:
  /// **'Lightened or darkened where it would be hard to read'**
  String get textColourAdjusted;

  /// No description provided for @automatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get automatic;

  /// No description provided for @mode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get mode;

  /// No description provided for @modeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Light or dark, for every theme'**
  String get modeSubtitle;

  /// No description provided for @accentColour.
  ///
  /// In en, this message translates to:
  /// **'Accent colour'**
  String get accentColour;

  /// No description provided for @coloursFromCoverArt.
  ///
  /// In en, this message translates to:
  /// **'Colours from cover art'**
  String get coloursFromCoverArt;

  /// No description provided for @coverColorOffNote.
  ///
  /// In en, this message translates to:
  /// **'Colours stay as the theme has them'**
  String get coverColorOffNote;

  /// No description provided for @coverColorPlayerNote.
  ///
  /// In en, this message translates to:
  /// **'Tint the player and pages with the colour of what\'s playing'**
  String get coverColorPlayerNote;

  /// No description provided for @coverColorAppNote.
  ///
  /// In en, this message translates to:
  /// **'The whole app takes the colour of what\'s playing'**
  String get coverColorAppNote;

  /// No description provided for @colourStrength.
  ///
  /// In en, this message translates to:
  /// **'Colour strength'**
  String get colourStrength;

  /// No description provided for @colourStrengthSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How much of the cover\'s colour shows in backgrounds and panels'**
  String get colourStrengthSubtitle;

  /// No description provided for @strengthSubtle.
  ///
  /// In en, this message translates to:
  /// **'Subtle'**
  String get strengthSubtle;

  /// No description provided for @strengthStrong.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get strengthStrong;

  /// No description provided for @highContrast.
  ///
  /// In en, this message translates to:
  /// **'High contrast'**
  String get highContrast;

  /// No description provided for @highContrastSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Brighter text and clearer edges, easier to read'**
  String get highContrastSubtitle;

  /// No description provided for @textSizeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Body text, in pixels; titles and labels grow with it. {size} px is the default'**
  String textSizeSubtitle(int size);

  /// No description provided for @font.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get font;

  /// No description provided for @openFontsFolder.
  ///
  /// In en, this message translates to:
  /// **'Open the fonts folder (put .ttf or .otf files here)'**
  String get openFontsFolder;

  /// No description provided for @nowPlayingBackground.
  ///
  /// In en, this message translates to:
  /// **'Now playing background'**
  String get nowPlayingBackground;

  /// No description provided for @nowPlayingBackgroundSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Only the Now Playing and expanded player pages'**
  String get nowPlayingBackgroundSubtitle;

  /// No description provided for @frostedGlass.
  ///
  /// In en, this message translates to:
  /// **'Frosted glass'**
  String get frostedGlass;

  /// No description provided for @frostedGlassSubtitle.
  ///
  /// In en, this message translates to:
  /// **'See-through, blurred mini player and tab bar. Uses a little more GPU'**
  String get frostedGlassSubtitle;

  /// No description provided for @blurStrength.
  ///
  /// In en, this message translates to:
  /// **'Blur strength'**
  String get blurStrength;

  /// No description provided for @componentOpacity.
  ///
  /// In en, this message translates to:
  /// **'Component opacity'**
  String get componentOpacity;

  /// No description provided for @componentOpacitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'See-through backgrounds with the desktop blurred behind them. Text, covers and controls stay solid'**
  String get componentOpacitySubtitle;

  /// No description provided for @backgroundOpacity.
  ///
  /// In en, this message translates to:
  /// **'Background opacity'**
  String get backgroundOpacity;

  /// No description provided for @backgroundOpacityAndroid.
  ///
  /// In en, this message translates to:
  /// **'Below 100% your wallpaper shows through'**
  String get backgroundOpacityAndroid;

  /// No description provided for @backgroundOpacityDesktop.
  ///
  /// In en, this message translates to:
  /// **'Below 100% the desktop shows through, blurred where the system can (Windows 11, macOS, Hyprland, KDE)'**
  String get backgroundOpacityDesktop;

  /// No description provided for @resetToDefault.
  ///
  /// In en, this message translates to:
  /// **'Reset to default'**
  String get resetToDefault;

  /// No description provided for @couldntLoadFont.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load {font}.'**
  String couldntLoadFont(String font);

  /// No description provided for @searchFonts.
  ///
  /// In en, this message translates to:
  /// **'Search fonts on this device'**
  String get searchFonts;

  /// No description provided for @riflaysOwnFont.
  ///
  /// In en, this message translates to:
  /// **'Riflay\'s own font'**
  String get riflaysOwnFont;

  /// No description provided for @fontFiles.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file} other{{count} files (weights and styles)}}'**
  String fontFiles(int count);

  /// No description provided for @defaultThemeFollows.
  ///
  /// In en, this message translates to:
  /// **'Default theme, follows the song that is playing'**
  String get defaultThemeFollows;

  /// No description provided for @themeNamed.
  ///
  /// In en, this message translates to:
  /// **'{name} theme'**
  String themeNamed(String name);

  /// No description provided for @smaller.
  ///
  /// In en, this message translates to:
  /// **'Smaller'**
  String get smaller;

  /// No description provided for @larger.
  ///
  /// In en, this message translates to:
  /// **'Larger'**
  String get larger;

  /// No description provided for @levelingPerSong.
  ///
  /// In en, this message translates to:
  /// **'Per song'**
  String get levelingPerSong;

  /// No description provided for @levelingPerAlbum.
  ///
  /// In en, this message translates to:
  /// **'Per album'**
  String get levelingPerAlbum;

  /// No description provided for @bufferLow.
  ///
  /// In en, this message translates to:
  /// **'Low latency'**
  String get bufferLow;

  /// No description provided for @bufferStable.
  ///
  /// In en, this message translates to:
  /// **'Extra stable'**
  String get bufferStable;

  /// No description provided for @monoOff.
  ///
  /// In en, this message translates to:
  /// **'Off (stereo)'**
  String get monoOff;

  /// No description provided for @monoBoth.
  ///
  /// In en, this message translates to:
  /// **'Both ears'**
  String get monoBoth;

  /// No description provided for @monoLeft.
  ///
  /// In en, this message translates to:
  /// **'Left ear only'**
  String get monoLeft;

  /// No description provided for @monoRight.
  ///
  /// In en, this message translates to:
  /// **'Right ear only'**
  String get monoRight;

  /// No description provided for @eqFlat.
  ///
  /// In en, this message translates to:
  /// **'Flat'**
  String get eqFlat;

  /// No description provided for @eqBassBoost.
  ///
  /// In en, this message translates to:
  /// **'Bass boost'**
  String get eqBassBoost;

  /// No description provided for @eqBassCut.
  ///
  /// In en, this message translates to:
  /// **'Bass cut'**
  String get eqBassCut;

  /// No description provided for @eqTrebleBoost.
  ///
  /// In en, this message translates to:
  /// **'Treble boost'**
  String get eqTrebleBoost;

  /// No description provided for @eqVocal.
  ///
  /// In en, this message translates to:
  /// **'Vocal'**
  String get eqVocal;

  /// No description provided for @eqRock.
  ///
  /// In en, this message translates to:
  /// **'Rock'**
  String get eqRock;

  /// No description provided for @eqPop.
  ///
  /// In en, this message translates to:
  /// **'Pop'**
  String get eqPop;

  /// No description provided for @eqJazz.
  ///
  /// In en, this message translates to:
  /// **'Jazz'**
  String get eqJazz;

  /// No description provided for @eqClassical.
  ///
  /// In en, this message translates to:
  /// **'Classical'**
  String get eqClassical;

  /// No description provided for @eqElectronic.
  ///
  /// In en, this message translates to:
  /// **'Electronic'**
  String get eqElectronic;

  /// No description provided for @eqLoudness.
  ///
  /// In en, this message translates to:
  /// **'Loudness'**
  String get eqLoudness;

  /// No description provided for @dopNote.
  ///
  /// In en, this message translates to:
  /// **'Your DAC takes up to {rate}, and DoP needs 176.4 kHz, so DSD files play as PCM on it'**
  String dopNote(String rate);

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemDefault;

  /// No description provided for @outputNotConnected.
  ///
  /// In en, this message translates to:
  /// **'The chosen output isn\'t connected, so it plays through the system default for now.'**
  String get outputNotConnected;

  /// No description provided for @cardBusy.
  ///
  /// In en, this message translates to:
  /// **'{card} is busy, so it plays through the system mixer for now.'**
  String cardBusy(String card);

  /// No description provided for @fxRoomCorrection.
  ///
  /// In en, this message translates to:
  /// **'Room correction ({name})'**
  String fxRoomCorrection(String name);

  /// No description provided for @fxEqHeadroom.
  ///
  /// In en, this message translates to:
  /// **'Equalizer headroom'**
  String get fxEqHeadroom;

  /// No description provided for @fxHrtf.
  ///
  /// In en, this message translates to:
  /// **'Virtual speakers (HRTF)'**
  String get fxHrtf;

  /// No description provided for @fxMonoBoth.
  ///
  /// In en, this message translates to:
  /// **'Mono (both ears)'**
  String get fxMonoBoth;

  /// No description provided for @fxMonoLeft.
  ///
  /// In en, this message translates to:
  /// **'Mono (left ear only)'**
  String get fxMonoLeft;

  /// No description provided for @fxMonoRight.
  ///
  /// In en, this message translates to:
  /// **'Mono (right ear only)'**
  String get fxMonoRight;

  /// No description provided for @fxPlugins.
  ///
  /// In en, this message translates to:
  /// **'Audio plugins (Carla)'**
  String get fxPlugins;

  /// No description provided for @removedFromLiked.
  ///
  /// In en, this message translates to:
  /// **'Removed from Liked music'**
  String get removedFromLiked;

  /// No description provided for @addedToLiked.
  ///
  /// In en, this message translates to:
  /// **'Added to Liked music'**
  String get addedToLiked;

  /// No description provided for @renamePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Rename playlist'**
  String get renamePlaylist;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @playlistOnDeviceNote.
  ///
  /// In en, this message translates to:
  /// **'Kept on this device. Can mix your own files and YouTube Music songs.'**
  String get playlistOnDeviceNote;

  /// No description provided for @playlistOnYtNote.
  ///
  /// In en, this message translates to:
  /// **'Saved to your YouTube Music account, on all your devices.'**
  String get playlistOnYtNote;

  /// No description provided for @privacyPrivate.
  ///
  /// In en, this message translates to:
  /// **'Only you can see it.'**
  String get privacyPrivate;

  /// No description provided for @privacyUnlisted.
  ///
  /// In en, this message translates to:
  /// **'Anyone with the link can see it.'**
  String get privacyUnlisted;

  /// No description provided for @privacyPublic.
  ///
  /// In en, this message translates to:
  /// **'Anyone can find and see it.'**
  String get privacyPublic;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @createdInYt.
  ///
  /// In en, this message translates to:
  /// **'Created \"{title}\" in YouTube Music'**
  String createdInYt(String title);

  /// No description provided for @createdPlaylistWith.
  ///
  /// In en, this message translates to:
  /// **'Created \"{title}\" with {count} songs'**
  String createdPlaylistWith(String title, int count);

  /// No description provided for @createdPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Created \"{title}\"'**
  String createdPlaylist(String title);

  /// No description provided for @removedFromThisPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Removed from this playlist'**
  String get removedFromThisPlaylist;

  /// No description provided for @makeUnlistedQuestion.
  ///
  /// In en, this message translates to:
  /// **'Make it unlisted?'**
  String get makeUnlistedQuestion;

  /// No description provided for @makeUnlistedBody.
  ///
  /// In en, this message translates to:
  /// **'Friends can only join a playlist that isn\'t private. It will become unlisted: hidden from search, but anyone with the link can see it.'**
  String get makeUnlistedBody;

  /// No description provided for @makeUnlisted.
  ///
  /// In en, this message translates to:
  /// **'Make unlisted'**
  String get makeUnlisted;

  /// No description provided for @inviteFriends.
  ///
  /// In en, this message translates to:
  /// **'Invite friends'**
  String get inviteFriends;

  /// No description provided for @inviteLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'The link is copied. Send it to your friends: anyone who opens it can add songs.'**
  String get inviteLinkCopied;

  /// No description provided for @copyAgain.
  ///
  /// In en, this message translates to:
  /// **'Copy again'**
  String get copyAgain;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @stopSharingQuestion.
  ///
  /// In en, this message translates to:
  /// **'Stop sharing?'**
  String get stopSharingQuestion;

  /// No description provided for @stopSharingBody.
  ///
  /// In en, this message translates to:
  /// **'Friends won\'t be able to add songs any more, and old invite links stop working.'**
  String get stopSharingBody;

  /// No description provided for @stopSharing.
  ///
  /// In en, this message translates to:
  /// **'Stop sharing'**
  String get stopSharing;

  /// No description provided for @onlyYouCanAdd.
  ///
  /// In en, this message translates to:
  /// **'Only you can add songs now'**
  String get onlyYouCanAdd;

  /// No description provided for @joinSharedPlaylistBody.
  ///
  /// In en, this message translates to:
  /// **'Paste the invite link a friend sent you. You\'ll both be able to add songs.'**
  String get joinSharedPlaylistBody;

  /// No description provided for @inviteLink.
  ///
  /// In en, this message translates to:
  /// **'Invite link'**
  String get inviteLink;

  /// No description provided for @notAnInviteLink.
  ///
  /// In en, this message translates to:
  /// **'That isn\'t an invite link'**
  String get notAnInviteLink;

  /// No description provided for @join.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get join;

  /// No description provided for @unfollowedName.
  ///
  /// In en, this message translates to:
  /// **'Unfollowed {name}'**
  String unfollowedName(String name);

  /// No description provided for @followingName.
  ///
  /// In en, this message translates to:
  /// **'Following {name}'**
  String followingName(String name);

  /// No description provided for @downloadFailedTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Download failed, try again'**
  String get downloadFailedTryAgain;

  /// No description provided for @downloadHoldTooltip.
  ///
  /// In en, this message translates to:
  /// **'Download\nHold to download now as {format}'**
  String downloadHoldTooltip(String format);

  /// No description provided for @downloadingIn.
  ///
  /// In en, this message translates to:
  /// **'Downloading in {format}…'**
  String downloadingIn(String format);

  /// No description provided for @downloadingTitle.
  ///
  /// In en, this message translates to:
  /// **'Downloading {title}…'**
  String downloadingTitle(String title);

  /// No description provided for @thisMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get thisMonth;

  /// No description provided for @thisYear.
  ///
  /// In en, this message translates to:
  /// **'This year'**
  String get thisYear;

  /// No description provided for @allTime.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get allTime;

  /// No description provided for @monthJanuary.
  ///
  /// In en, this message translates to:
  /// **'January'**
  String get monthJanuary;

  /// No description provided for @monthFebruary.
  ///
  /// In en, this message translates to:
  /// **'February'**
  String get monthFebruary;

  /// No description provided for @monthMarch.
  ///
  /// In en, this message translates to:
  /// **'March'**
  String get monthMarch;

  /// No description provided for @monthApril.
  ///
  /// In en, this message translates to:
  /// **'April'**
  String get monthApril;

  /// No description provided for @monthMay.
  ///
  /// In en, this message translates to:
  /// **'May'**
  String get monthMay;

  /// No description provided for @monthJune.
  ///
  /// In en, this message translates to:
  /// **'June'**
  String get monthJune;

  /// No description provided for @monthJuly.
  ///
  /// In en, this message translates to:
  /// **'July'**
  String get monthJuly;

  /// No description provided for @monthAugust.
  ///
  /// In en, this message translates to:
  /// **'August'**
  String get monthAugust;

  /// No description provided for @monthSeptember.
  ///
  /// In en, this message translates to:
  /// **'September'**
  String get monthSeptember;

  /// No description provided for @monthOctober.
  ///
  /// In en, this message translates to:
  /// **'October'**
  String get monthOctober;

  /// No description provided for @monthNovember.
  ///
  /// In en, this message translates to:
  /// **'November'**
  String get monthNovember;

  /// No description provided for @monthDecember.
  ///
  /// In en, this message translates to:
  /// **'December'**
  String get monthDecember;

  /// No description provided for @monthInitials.
  ///
  /// In en, this message translates to:
  /// **'J F M A M J J A S O N D'**
  String get monthInitials;

  /// No description provided for @monthYear.
  ///
  /// In en, this message translates to:
  /// **'{month} {year}'**
  String monthYear(String month, String year);

  /// No description provided for @monthDay.
  ///
  /// In en, this message translates to:
  /// **'{month} {day}'**
  String monthDay(String month, String day);

  /// No description provided for @durZero.
  ///
  /// In en, this message translates to:
  /// **'0 min'**
  String get durZero;

  /// No description provided for @durOneMin.
  ///
  /// In en, this message translates to:
  /// **'1 min'**
  String get durOneMin;

  /// No description provided for @durMin.
  ///
  /// In en, this message translates to:
  /// **'{m} min'**
  String durMin(String m);

  /// No description provided for @durHours.
  ///
  /// In en, this message translates to:
  /// **'{h} h'**
  String durHours(String h);

  /// No description provided for @durHoursMin.
  ///
  /// In en, this message translates to:
  /// **'{h} h {m} min'**
  String durHoursMin(String h, String m);

  /// No description provided for @wrapSoFar.
  ///
  /// In en, this message translates to:
  /// **'{month} so far'**
  String wrapSoFar(String month);

  /// No description provided for @playFewSongsWrap.
  ///
  /// In en, this message translates to:
  /// **'Play a few songs to see your Wrap.'**
  String get playFewSongsWrap;

  /// No description provided for @notEnoughForWrap.
  ///
  /// In en, this message translates to:
  /// **'There is not enough listening in {month} for a Wrap.'**
  String notEnoughForWrap(String month);

  /// No description provided for @wrapCaption.
  ///
  /// In en, this message translates to:
  /// **'My {month} on Riflay: {listened} of music. Top song: {song}. Top artist: {artist}.'**
  String wrapCaption(String month, String listened, String song, String artist);

  /// No description provided for @wrapCaptionStreak.
  ///
  /// In en, this message translates to:
  /// **'🔥 {count} days in a row.'**
  String wrapCaptionStreak(int count);

  /// No description provided for @savedFile.
  ///
  /// In en, this message translates to:
  /// **'Saved {file}'**
  String savedFile(String file);

  /// No description provided for @couldntSaveImage.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the image'**
  String get couldntSaveImage;

  /// No description provided for @savedCaptionCopied.
  ///
  /// In en, this message translates to:
  /// **'Saved {file}; the caption is copied'**
  String savedCaptionCopied(String file);

  /// No description provided for @saveImage.
  ///
  /// In en, this message translates to:
  /// **'Save image'**
  String get saveImage;

  /// No description provided for @weekdayMonday.
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get weekdayMonday;

  /// No description provided for @weekdayTuesday.
  ///
  /// In en, this message translates to:
  /// **'Tuesday'**
  String get weekdayTuesday;

  /// No description provided for @weekdayWednesday.
  ///
  /// In en, this message translates to:
  /// **'Wednesday'**
  String get weekdayWednesday;

  /// No description provided for @weekdayThursday.
  ///
  /// In en, this message translates to:
  /// **'Thursday'**
  String get weekdayThursday;

  /// No description provided for @weekdayFriday.
  ///
  /// In en, this message translates to:
  /// **'Friday'**
  String get weekdayFriday;

  /// No description provided for @weekdaySaturday.
  ///
  /// In en, this message translates to:
  /// **'Saturday'**
  String get weekdaySaturday;

  /// No description provided for @weekdaySunday.
  ///
  /// In en, this message translates to:
  /// **'Sunday'**
  String get weekdaySunday;

  /// No description provided for @weekdayMonthDay.
  ///
  /// In en, this message translates to:
  /// **'{weekday}, {month} {day}'**
  String weekdayMonthDay(String weekday, String month, String day);

  /// No description provided for @wrapSoFarKicker.
  ///
  /// In en, this message translates to:
  /// **'Your Wrap so far'**
  String get wrapSoFarKicker;

  /// No description provided for @wrapMonthlyKicker.
  ///
  /// In en, this message translates to:
  /// **'Your monthly Wrap'**
  String get wrapMonthlyKicker;

  /// No description provided for @wrapMonthInMusic.
  ///
  /// In en, this message translates to:
  /// **'Your {month} in music'**
  String wrapMonthInMusic(String month);

  /// No description provided for @wrapUpTo.
  ///
  /// In en, this message translates to:
  /// **'Up to {day}'**
  String wrapUpTo(String day);

  /// No description provided for @wrapListenedFor.
  ///
  /// In en, this message translates to:
  /// **'You listened for'**
  String get wrapListenedFor;

  /// No description provided for @wrapAcross.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{across 1 play in {month}.} other{across {count} plays in {month}.}}'**
  String wrapAcross(int count, String month);

  /// No description provided for @wrapAcrossSoFar.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{across 1 play so far in {month}.} other{across {count} plays so far in {month}.}}'**
  String wrapAcrossSoFar(int count, String month);

  /// No description provided for @wrapSummary.
  ///
  /// In en, this message translates to:
  /// **'Top song: {song}\nTop artist: {artist}\n{songs, plural, =1{1 song} other{{songs} songs}}, {artists, plural, =1{1 artist} other{{artists} artists}}'**
  String wrapSummary(int songs, int artists, String song, String artist);

  /// No description provided for @wrapYouPlayed.
  ///
  /// In en, this message translates to:
  /// **'You played'**
  String get wrapYouPlayed;

  /// No description provided for @songsPlural.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 song} other{{count} songs}}'**
  String songsPlural(int count);

  /// No description provided for @wrapByArtists.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{by 1 artist.} other{by {count} artists.}}'**
  String wrapByArtists(int count);

  /// No description provided for @wrapTopSong.
  ///
  /// In en, this message translates to:
  /// **'Your top song'**
  String get wrapTopSong;

  /// No description provided for @playsPlural.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 play} other{{count} plays}}'**
  String playsPlural(int count);

  /// No description provided for @wrapTopSongs.
  ///
  /// In en, this message translates to:
  /// **'Your top songs'**
  String get wrapTopSongs;

  /// No description provided for @wrapTopArtist.
  ///
  /// In en, this message translates to:
  /// **'Your top artist'**
  String get wrapTopArtist;

  /// No description provided for @wrapTopArtists.
  ///
  /// In en, this message translates to:
  /// **'Your top artists'**
  String get wrapTopArtists;

  /// No description provided for @wrapTopAlbum.
  ///
  /// In en, this message translates to:
  /// **'Your top album'**
  String get wrapTopAlbum;

  /// No description provided for @wrapBiggestDay.
  ///
  /// In en, this message translates to:
  /// **'Your biggest day'**
  String get wrapBiggestDay;

  /// No description provided for @wrapOfMusic.
  ///
  /// In en, this message translates to:
  /// **'{listened} of music.'**
  String wrapOfMusic(String listened);

  /// No description provided for @wrapStreakGoing.
  ///
  /// In en, this message translates to:
  /// **'Your streak, still going'**
  String get wrapStreakGoing;

  /// No description provided for @wrapLongestStreak.
  ///
  /// In en, this message translates to:
  /// **'Your longest streak'**
  String get wrapLongestStreak;

  /// No description provided for @daysInARow.
  ///
  /// In en, this message translates to:
  /// **'{count} days in a row'**
  String daysInARow(int count);

  /// No description provided for @wrapListenedOnDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{You listened on {listened} of 1 day.} other{You listened on {listened} of {count} days.}}'**
  String wrapListenedOnDays(int listened, int count);

  /// No description provided for @wrapListenedOnDaysSoFar.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{You listened on {listened} of 1 day so far.} other{You listened on {listened} of {count} days so far.}}'**
  String wrapListenedOnDaysSoFar(int listened, int count);

  /// No description provided for @wrapMostReplayed.
  ///
  /// In en, this message translates to:
  /// **'Most replayed'**
  String get wrapMostReplayed;

  /// No description provided for @wrapPlayedTimesOn.
  ///
  /// In en, this message translates to:
  /// **'{artist}\nPlayed {count} times on {day}.'**
  String wrapPlayedTimesOn(String artist, int count, String day);

  /// No description provided for @wrapNewThisMonth.
  ///
  /// In en, this message translates to:
  /// **'New this month'**
  String get wrapNewThisMonth;

  /// No description provided for @wrapYearlyKicker.
  ///
  /// In en, this message translates to:
  /// **'Your yearly Wrap'**
  String get wrapYearlyKicker;

  /// No description provided for @wrapNewThisYear.
  ///
  /// In en, this message translates to:
  /// **'New this year'**
  String get wrapNewThisYear;

  /// No description provided for @wrapLongestStreakOf.
  ///
  /// In en, this message translates to:
  /// **'Your longest streak of {year}'**
  String wrapLongestStreakOf(String year);

  /// No description provided for @yourYearlyWraps.
  ///
  /// In en, this message translates to:
  /// **'Your yearly Wraps'**
  String get yourYearlyWraps;

  /// No description provided for @thisYearUpToNow.
  ///
  /// In en, this message translates to:
  /// **'This year, up to now'**
  String get thisYearUpToNow;

  /// No description provided for @newSongsPlural.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 new song} other{{count} new songs}}'**
  String newSongsPlural(int count);

  /// No description provided for @wrapStayedWithKnown.
  ///
  /// In en, this message translates to:
  /// **'You stayed with the songs you know.'**
  String get wrapStayedWithKnown;

  /// No description provided for @wrapNeverPlayed.
  ///
  /// In en, this message translates to:
  /// **'Songs you had never played before.'**
  String get wrapNeverPlayed;

  /// No description provided for @wrapNewCount.
  ///
  /// In en, this message translates to:
  /// **', {count} new'**
  String wrapNewCount(int count);

  /// No description provided for @madeWithRiflay.
  ///
  /// In en, this message translates to:
  /// **'Made with Riflay'**
  String get madeWithRiflay;

  /// No description provided for @yourListening.
  ///
  /// In en, this message translates to:
  /// **'Your listening'**
  String get yourListening;

  /// No description provided for @yourListeningBody.
  ///
  /// In en, this message translates to:
  /// **'Worked out from songs you played for 30 seconds or more. It stays on this device.'**
  String get yourListeningBody;

  /// No description provided for @listeningTime.
  ///
  /// In en, this message translates to:
  /// **'Listening time'**
  String get listeningTime;

  /// No description provided for @topSongs.
  ///
  /// In en, this message translates to:
  /// **'Top songs'**
  String get topSongs;

  /// No description provided for @topArtists.
  ///
  /// In en, this message translates to:
  /// **'Top artists'**
  String get topArtists;

  /// No description provided for @topAlbums.
  ///
  /// In en, this message translates to:
  /// **'Top albums'**
  String get topAlbums;

  /// No description provided for @yourMonthlyWraps.
  ///
  /// In en, this message translates to:
  /// **'Your monthly Wraps'**
  String get yourMonthlyWraps;

  /// No description provided for @thisMonthUpToNow.
  ///
  /// In en, this message translates to:
  /// **'This month up to now'**
  String get thisMonthUpToNow;

  /// No description provided for @playFewSongsWrapShort.
  ///
  /// In en, this message translates to:
  /// **'Play a few songs to see your Wrap'**
  String get playFewSongsWrapShort;

  /// No description provided for @couldntFindSong.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t find {title}'**
  String couldntFindSong(String title);

  /// No description provided for @statsNothingYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet. Songs you listen to for 30 seconds or more will show up.'**
  String get statsNothingYet;

  /// No description provided for @historyOff.
  ///
  /// In en, this message translates to:
  /// **'Your listening history is off. Turn it on in Settings › Library & downloads › Listening history & Wrap.'**
  String get historyOff;

  /// No description provided for @listeningTimeChart.
  ///
  /// In en, this message translates to:
  /// **'Listening time chart. {bars}'**
  String listeningTimeChart(String bars);

  /// No description provided for @listeningWith.
  ///
  /// In en, this message translates to:
  /// **'Listening with {host}'**
  String listeningWith(String host);

  /// No description provided for @aFriend.
  ///
  /// In en, this message translates to:
  /// **'a friend'**
  String get aFriend;

  /// No description provided for @hosting.
  ///
  /// In en, this message translates to:
  /// **'Hosting'**
  String get hosting;

  /// No description provided for @listeningCount.
  ///
  /// In en, this message translates to:
  /// **'{count} listening'**
  String listeningCount(int count);

  /// No description provided for @couldntConnect.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t connect. Try again.'**
  String get couldntConnect;

  /// No description provided for @listenTogetherIntro.
  ///
  /// In en, this message translates to:
  /// **'Play YouTube songs together with friends.'**
  String get listenTogetherIntro;

  /// No description provided for @yourName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get yourName;

  /// No description provided for @yourNameHelper.
  ///
  /// In en, this message translates to:
  /// **'Friends see it when you join or start a session'**
  String get yourNameHelper;

  /// No description provided for @enterNameFirst.
  ///
  /// In en, this message translates to:
  /// **'Enter your name first'**
  String get enterNameFirst;

  /// No description provided for @sameWifi.
  ///
  /// In en, this message translates to:
  /// **'Same Wi-Fi'**
  String get sameWifi;

  /// No description provided for @anywhere.
  ///
  /// In en, this message translates to:
  /// **'Anywhere'**
  String get anywhere;

  /// No description provided for @anywhereNote.
  ///
  /// In en, this message translates to:
  /// **'Connects through free public servers. Everything is encrypted, but it\'s new and can sometimes fail to connect.'**
  String get anywhereNote;

  /// No description provided for @sameWifiNote.
  ///
  /// In en, this message translates to:
  /// **'Everyone needs to be on the same Wi-Fi.'**
  String get sameWifiNote;

  /// No description provided for @startSession.
  ///
  /// In en, this message translates to:
  /// **'Start a session'**
  String get startSession;

  /// No description provided for @scanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get scanQr;

  /// No description provided for @onThisWifi.
  ///
  /// In en, this message translates to:
  /// **'On this Wi-Fi'**
  String get onThisWifi;

  /// No description provided for @lookingForSessions.
  ///
  /// In en, this message translates to:
  /// **'Looking for sessions on this network…'**
  String get lookingForSessions;

  /// No description provided for @tapToJoin.
  ///
  /// In en, this message translates to:
  /// **'Tap to join'**
  String get tapToJoin;

  /// No description provided for @haveACode.
  ///
  /// In en, this message translates to:
  /// **'Have a code?'**
  String get haveACode;

  /// No description provided for @joinCodeAnywhere.
  ///
  /// In en, this message translates to:
  /// **'Friends anywhere can join with this code.'**
  String get joinCodeAnywhere;

  /// No description provided for @joinCodeWifi.
  ///
  /// In en, this message translates to:
  /// **'Friends on the same Wi-Fi can join with this code.'**
  String get joinCodeWifi;

  /// No description provided for @showQr.
  ///
  /// In en, this message translates to:
  /// **'Show QR code'**
  String get showQr;

  /// No description provided for @listening.
  ///
  /// In en, this message translates to:
  /// **'Listening'**
  String get listening;

  /// No description provided for @nobodyJoined.
  ///
  /// In en, this message translates to:
  /// **'Nobody has joined yet.'**
  String get nobodyJoined;

  /// No description provided for @letFriendsAdd.
  ///
  /// In en, this message translates to:
  /// **'Let friends add songs'**
  String get letFriendsAdd;

  /// No description provided for @letFriendsAddSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A song a friend plays goes into your queue, in the order they come'**
  String get letFriendsAddSubtitle;

  /// No description provided for @letFriendsSeek.
  ///
  /// In en, this message translates to:
  /// **'Let friends seek within songs'**
  String get letFriendsSeek;

  /// No description provided for @letFriendsSeekSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Changes playback position for everyone'**
  String get letFriendsSeekSubtitle;

  /// No description provided for @youPickSongs.
  ///
  /// In en, this message translates to:
  /// **'You pick the songs. Play any YouTube song and everyone follows.'**
  String get youPickSongs;

  /// No description provided for @endSession.
  ///
  /// In en, this message translates to:
  /// **'End session'**
  String get endSession;

  /// No description provided for @waitingForHost.
  ///
  /// In en, this message translates to:
  /// **'Waiting for {host} to play something.'**
  String waitingForHost(String host);

  /// No description provided for @hostPlayingOwnFiles.
  ///
  /// In en, this message translates to:
  /// **'{host} is playing a song from their own files. It\'ll continue when they play a YouTube song.'**
  String hostPlayingOwnFiles(String host);

  /// No description provided for @playGoesToHostQueue.
  ///
  /// In en, this message translates to:
  /// **'Play any YouTube song and it goes into {host}\'s queue.'**
  String playGoesToHostQueue(String host);

  /// No description provided for @hostNotTakingSongs.
  ///
  /// In en, this message translates to:
  /// **'{host} isn\'t taking songs right now.'**
  String hostNotTakingSongs(String host);

  /// No description provided for @host.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get host;

  /// No description provided for @upNext.
  ///
  /// In en, this message translates to:
  /// **'Up next'**
  String get upNext;

  /// No description provided for @seekForEveryone.
  ///
  /// In en, this message translates to:
  /// **'Use the player timeline to seek for everyone.'**
  String get seekForEveryone;

  /// No description provided for @onlyHostSeeks.
  ///
  /// In en, this message translates to:
  /// **'Only the host can seek within songs.'**
  String get onlyHostSeeks;

  /// No description provided for @leave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get leave;

  /// No description provided for @spMixerResamples.
  ///
  /// In en, this message translates to:
  /// **'Riflay leaves the sound alone, but the system mixer runs your DAC at {dacRate} instead of {songRate}.'**
  String spMixerResamples(String dacRate, String songRate);

  /// No description provided for @spFixedRateOutputs.
  ///
  /// In en, this message translates to:
  /// **'iPhone, iPad and Bluetooth outputs run at one fixed rate; a USB DAC usually follows each song.'**
  String get spFixedRateOutputs;

  /// No description provided for @spTurnOnBitPerfect.
  ///
  /// In en, this message translates to:
  /// **'Turn on Bit-perfect mode in Settings › Sound › Output & quality to send it as it is.'**
  String get spTurnOnBitPerfect;

  /// No description provided for @spMixerMayResample.
  ///
  /// In en, this message translates to:
  /// **'Nothing in Riflay changes the sound, but the system mixer may resample it.'**
  String get spMixerMayResample;

  /// No description provided for @spIosAlwaysMixes.
  ///
  /// In en, this message translates to:
  /// **'iOS always mixes the sound, so it is never bit-perfect here.'**
  String get spIosAlwaysMixes;

  /// No description provided for @spForBitPerfectExclusive.
  ///
  /// In en, this message translates to:
  /// **'For bit-perfect, turn on Bit-perfect mode and Exclusive mode in Settings › Sound › Output & quality (other apps go silent meanwhile).'**
  String get spForBitPerfectExclusive;

  /// No description provided for @spForBitPerfect.
  ///
  /// In en, this message translates to:
  /// **'For bit-perfect, turn on Bit-perfect mode in Settings › Sound › Output & quality.'**
  String get spForBitPerfect;

  /// No description provided for @spDsdToPcmExclusive.
  ///
  /// In en, this message translates to:
  /// **'DSD is decoded to high-rate PCM. To send it to your DAC as DSD, turn on Bit-perfect mode, Exclusive mode and Native DSD (DoP) in Settings › Sound › Output & quality.'**
  String get spDsdToPcmExclusive;

  /// No description provided for @spDsdToPcmHowTo.
  ///
  /// In en, this message translates to:
  /// **'DSD is decoded to high-rate PCM. To send it to your DAC as DSD, turn on Bit-perfect mode and Native DSD (DoP) in Settings › Sound › Output & quality.'**
  String get spDsdToPcmHowTo;

  /// No description provided for @spUsbDacRateUnsupported.
  ///
  /// In en, this message translates to:
  /// **'{dac} doesn\'t take {songRate}, so Android plays it at {outRate} instead.'**
  String spUsbDacRateUnsupported(String dac, String songRate, String outRate);

  /// No description provided for @qualityLossy.
  ///
  /// In en, this message translates to:
  /// **'Lossy'**
  String get qualityLossy;

  /// No description provided for @qualityLossless.
  ///
  /// In en, this message translates to:
  /// **'Lossless'**
  String get qualityLossless;

  /// No description provided for @nativeDsd2.
  ///
  /// In en, this message translates to:
  /// **'Native DSD'**
  String get nativeDsd2;

  /// No description provided for @spNativeDsdBody.
  ///
  /// In en, this message translates to:
  /// **'The DSD stream reaches your DAC as it is, packed as DoP. A DAC that supports DoP shows DSD; one that doesn\'t plays a faint hiss (then turn off Native DSD).'**
  String get spNativeDsdBody;

  /// No description provided for @spDopChanged.
  ///
  /// In en, this message translates to:
  /// **'DoP is being changed'**
  String get spDopChanged;

  /// No description provided for @spDopChangedBody.
  ///
  /// In en, this message translates to:
  /// **'Something between Riflay and your DAC changes the samples, so the DAC can\'t see the DSD. Choose a direct output in Settings › Sound › Output & quality.'**
  String get spDopChangedBody;

  /// No description provided for @spUsbBitPerfect.
  ///
  /// In en, this message translates to:
  /// **'USB DAC, bit-perfect (Android 14): every sample reaches {dac} exactly as it is stored in the file.'**
  String spUsbBitPerfect(String dac);

  /// No description provided for @spNotBitPerfect.
  ///
  /// In en, this message translates to:
  /// **'Not bit-perfect'**
  String get spNotBitPerfect;

  /// No description provided for @spBitPerfectBody.
  ///
  /// In en, this message translates to:
  /// **'Every sample reaches your DAC exactly as it is stored in the file.'**
  String get spBitPerfectBody;

  /// No description provided for @spResampledByMixer.
  ///
  /// In en, this message translates to:
  /// **'Resampled by the system mixer'**
  String get spResampledByMixer;

  /// No description provided for @spLosslessToMixer.
  ///
  /// In en, this message translates to:
  /// **'Lossless to the system mixer'**
  String get spLosslessToMixer;

  /// No description provided for @spDsdConverted.
  ///
  /// In en, this message translates to:
  /// **'DSD converted to PCM'**
  String get spDsdConverted;

  /// No description provided for @spDsdIos.
  ///
  /// In en, this message translates to:
  /// **'DSD is decoded to high-rate PCM. iOS can\'t send DSD to a DAC as DSD.'**
  String get spDsdIos;

  /// No description provided for @spProcessed.
  ///
  /// In en, this message translates to:
  /// **'Processed'**
  String get spProcessed;

  /// No description provided for @spProcessedBody.
  ///
  /// In en, this message translates to:
  /// **'Something below changes the samples. That is fine if it is what you want.'**
  String get spProcessedBody;

  /// No description provided for @spSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get spSource;

  /// No description provided for @spLosslessParen.
  ///
  /// In en, this message translates to:
  /// **'(lossless)'**
  String get spLosslessParen;

  /// No description provided for @spDecoded.
  ///
  /// In en, this message translates to:
  /// **'Decoded'**
  String get spDecoded;

  /// No description provided for @spPadded.
  ///
  /// In en, this message translates to:
  /// **'({bits}-bit, padded losslessly)'**
  String spPadded(int bits);

  /// No description provided for @spUntouched.
  ///
  /// In en, this message translates to:
  /// **'100% (untouched)'**
  String get spUntouched;

  /// No description provided for @spMuted.
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get spMuted;

  /// No description provided for @spClipProtection.
  ///
  /// In en, this message translates to:
  /// **'Clip protection'**
  String get spClipProtection;

  /// No description provided for @spClipProtectionBody.
  ///
  /// In en, this message translates to:
  /// **'Softens any peak past full scale instead of cutting it off'**
  String get spClipProtectionBody;

  /// No description provided for @spResampled.
  ///
  /// In en, this message translates to:
  /// **'Resampled'**
  String get spResampled;

  /// No description provided for @spDacReceives.
  ///
  /// In en, this message translates to:
  /// **'DAC receives'**
  String get spDacReceives;

  /// No description provided for @spMono.
  ///
  /// In en, this message translates to:
  /// **'mono'**
  String get spMono;

  /// No description provided for @spStereo.
  ///
  /// In en, this message translates to:
  /// **'stereo'**
  String get spStereo;

  /// No description provided for @spChannels.
  ///
  /// In en, this message translates to:
  /// **'{count} channels'**
  String spChannels(String count);

  /// No description provided for @spPipewire.
  ///
  /// In en, this message translates to:
  /// **'PipeWire (system mixer)'**
  String get spPipewire;

  /// No description provided for @spPulse.
  ///
  /// In en, this message translates to:
  /// **'PulseAudio (system mixer)'**
  String get spPulse;

  /// No description provided for @spAlsaDirect.
  ///
  /// In en, this message translates to:
  /// **'ALSA, direct to hardware'**
  String get spAlsaDirect;

  /// No description provided for @spWasapiExclusive.
  ///
  /// In en, this message translates to:
  /// **'WASAPI exclusive'**
  String get spWasapiExclusive;

  /// No description provided for @spWasapiShared.
  ///
  /// In en, this message translates to:
  /// **'WASAPI shared'**
  String get spWasapiShared;

  /// No description provided for @spAndroidMixer.
  ///
  /// In en, this message translates to:
  /// **'Android mixer'**
  String get spAndroidMixer;

  /// No description provided for @spAndroidMixerParen.
  ///
  /// In en, this message translates to:
  /// **'(Android mixer)'**
  String get spAndroidMixerParen;

  /// No description provided for @spIosSession.
  ///
  /// In en, this message translates to:
  /// **'iOS audio session (system mixer)'**
  String get spIosSession;

  /// No description provided for @spMeasureOutput.
  ///
  /// In en, this message translates to:
  /// **'Measure output'**
  String get spMeasureOutput;

  /// No description provided for @spMeasureOutputBody.
  ///
  /// In en, this message translates to:
  /// **'Records 10 s of what Riflay sends to PipeWire and compares it, sample by sample, with the song itself. The recording is digital: it shows whether Riflay and the system mixer changed the samples, not what your DAC makes of them.'**
  String get spMeasureOutputBody;

  /// No description provided for @spMeasure.
  ///
  /// In en, this message translates to:
  /// **'Measure'**
  String get spMeasure;

  /// No description provided for @spMeasureAgain.
  ///
  /// In en, this message translates to:
  /// **'Measure again'**
  String get spMeasureAgain;

  /// No description provided for @spMeasureRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording… {seconds} / {total} s'**
  String spMeasureRecording(String seconds, String total);

  /// No description provided for @spMeasureDecoding.
  ///
  /// In en, this message translates to:
  /// **'Decoding the song…'**
  String get spMeasureDecoding;

  /// No description provided for @spMeasureComparing.
  ///
  /// In en, this message translates to:
  /// **'Comparing…'**
  String get spMeasureComparing;

  /// No description provided for @spNotBitPerfectShare.
  ///
  /// In en, this message translates to:
  /// **'NOT Bit Perfect {share}'**
  String spNotBitPerfectShare(String share);

  /// No description provided for @spGain.
  ///
  /// In en, this message translates to:
  /// **'Gain'**
  String get spGain;

  /// No description provided for @spPhaseOffset.
  ///
  /// In en, this message translates to:
  /// **'Phase Offset'**
  String get spPhaseOffset;

  /// No description provided for @spDifferenceRms.
  ///
  /// In en, this message translates to:
  /// **'Difference (rms)'**
  String get spDifferenceRms;

  /// No description provided for @spCorrelatedNull.
  ///
  /// In en, this message translates to:
  /// **'Correlated Null'**
  String get spCorrelatedNull;

  /// No description provided for @spClockDrift.
  ///
  /// In en, this message translates to:
  /// **'Clock Drift'**
  String get spClockDrift;

  /// No description provided for @spFitQuality.
  ///
  /// In en, this message translates to:
  /// **'Fit Quality'**
  String get spFitQuality;

  /// No description provided for @spFitExcellent.
  ///
  /// In en, this message translates to:
  /// **'Excellent'**
  String get spFitExcellent;

  /// No description provided for @spFitGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get spFitGood;

  /// No description provided for @spFitPoor.
  ///
  /// In en, this message translates to:
  /// **'Poor'**
  String get spFitPoor;

  /// No description provided for @spMeasuredAt.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s compared at {rate}, 32-bit float from PipeWire'**
  String spMeasuredAt(String seconds, String rate);

  /// No description provided for @spMeasureNoRecorder.
  ///
  /// In en, this message translates to:
  /// **'PipeWire\'s pw-record isn\'t installed.'**
  String get spMeasureNoRecorder;

  /// No description provided for @spMeasureNoStream.
  ///
  /// In en, this message translates to:
  /// **'None of Riflay\'s sound is playing through PipeWire. Play the song and try again.'**
  String get spMeasureNoStream;

  /// No description provided for @spMeasureTwoStreams.
  ///
  /// In en, this message translates to:
  /// **'Two songs are fading into each other. Try again in a moment.'**
  String get spMeasureTwoStreams;

  /// No description provided for @spMeasureSongMoved.
  ///
  /// In en, this message translates to:
  /// **'The song paused, moved or changed while recording. Let it play and try again.'**
  String get spMeasureSongMoved;

  /// No description provided for @spMeasureNoSource.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t decode the song again to compare.'**
  String get spMeasureNoSource;

  /// No description provided for @spMeasureNoMatch.
  ///
  /// In en, this message translates to:
  /// **'What came out didn\'t line up with the song (silence, or something else playing).'**
  String get spMeasureNoMatch;

  /// No description provided for @couldntOpenBrowser.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the browser.'**
  String get couldntOpenBrowser;

  /// No description provided for @versionNamed.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String versionNamed(String version);

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @whatsNew.
  ///
  /// In en, this message translates to:
  /// **'What\'s new'**
  String get whatsNew;

  /// No description provided for @whatsNewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Release notes and downloads for every platform'**
  String get whatsNewSubtitle;

  /// No description provided for @reportProblem.
  ///
  /// In en, this message translates to:
  /// **'Report a problem'**
  String get reportProblem;

  /// No description provided for @reportProblemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Opens a new issue; paste the version details in it'**
  String get reportProblemSubtitle;

  /// No description provided for @supportArtists.
  ///
  /// In en, this message translates to:
  /// **'Support the artists'**
  String get supportArtists;

  /// No description provided for @supportArtistsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enjoying the music? YouTube Music Premium pays the people who make it'**
  String get supportArtistsSubtitle;

  /// No description provided for @supportRiflay.
  ///
  /// In en, this message translates to:
  /// **'Support Riflay'**
  String get supportRiflay;

  /// No description provided for @supportRiflaySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Send a gift on Tako to keep it going'**
  String get supportRiflaySubtitle;

  /// No description provided for @sourceCode.
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get sourceCode;

  /// No description provided for @sourceCodeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Riflay is open source, on GitHub'**
  String get sourceCodeSubtitle;

  /// No description provided for @licence.
  ///
  /// In en, this message translates to:
  /// **'Licence'**
  String get licence;

  /// No description provided for @openSourceLicences.
  ///
  /// In en, this message translates to:
  /// **'Open-source licences'**
  String get openSourceLicences;

  /// No description provided for @openSourceLicencesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The libraries Riflay is built with'**
  String get openSourceLicencesSubtitle;

  /// No description provided for @scrobbleBody.
  ///
  /// In en, this message translates to:
  /// **'Songs you listen to past the halfway mark (or 4 minutes) are added to your profile there. Listens made offline are sent once you\'re back online.'**
  String get scrobbleBody;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @notConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get notConnected;

  /// No description provided for @connectedAs.
  ///
  /// In en, this message translates to:
  /// **'Connected as {user}'**
  String connectedAs(String user);

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @noNewListens.
  ///
  /// In en, this message translates to:
  /// **'No new listens to bring in'**
  String get noNewListens;

  /// No description provided for @listensAdded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 listen added to your history} other{{count} listens added to your history}}'**
  String listensAdded(int count);

  /// No description provided for @serviceSignedOut.
  ///
  /// In en, this message translates to:
  /// **'{service} signed you out. Connect it again.'**
  String serviceSignedOut(String service);

  /// No description provided for @couldntReachService.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach {service}. Try again.'**
  String couldntReachService(String service);

  /// No description provided for @readingListens.
  ///
  /// In en, this message translates to:
  /// **'Reading your listens: {count} so far'**
  String readingListens(String count);

  /// No description provided for @turnOnHistoryFirst.
  ///
  /// In en, this message translates to:
  /// **'Turn on the listening history in Library & downloads first.'**
  String get turnOnHistoryFirst;

  /// No description provided for @bringInBody.
  ///
  /// In en, this message translates to:
  /// **'Adds the songs you played elsewhere to your stats, Wraps and Most played. Ones already here are skipped.'**
  String get bringInBody;

  /// No description provided for @bringInHistory.
  ///
  /// In en, this message translates to:
  /// **'Bring in your {service} history'**
  String bringInHistory(String service);

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @bringIn.
  ///
  /// In en, this message translates to:
  /// **'Bring in'**
  String get bringIn;

  /// No description provided for @connectService.
  ///
  /// In en, this message translates to:
  /// **'Connect {service}'**
  String connectService(String service);

  /// No description provided for @listenBrainzTokenBody.
  ///
  /// In en, this message translates to:
  /// **'Copy your user token from your ListenBrainz settings and paste it here.'**
  String get listenBrainzTokenBody;

  /// No description provided for @openListenBrainzSettings.
  ///
  /// In en, this message translates to:
  /// **'Open ListenBrainz settings'**
  String get openListenBrainzSettings;

  /// No description provided for @userToken.
  ///
  /// In en, this message translates to:
  /// **'User token'**
  String get userToken;

  /// No description provided for @signInTooLong.
  ///
  /// In en, this message translates to:
  /// **'The sign-in took too long. Try again.'**
  String get signInTooLong;

  /// No description provided for @lastfmDidntFinish.
  ///
  /// In en, this message translates to:
  /// **'Last.fm didn\'t finish the sign-in. Try again.'**
  String get lastfmDidntFinish;

  /// No description provided for @lastfmAllowBody.
  ///
  /// In en, this message translates to:
  /// **'Allow Riflay on the Last.fm page that opened in your browser. This closes by itself once you have.'**
  String get lastfmAllowBody;

  /// No description provided for @openLastfmAgain.
  ///
  /// In en, this message translates to:
  /// **'Open Last.fm again'**
  String get openLastfmAgain;

  /// No description provided for @spotifyReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read your Spotify library right now. Try again later.'**
  String get spotifyReadFailed;

  /// No description provided for @needsWebkit.
  ///
  /// In en, this message translates to:
  /// **'Signing in needs WebKitGTK (webkit2gtk-4.1). Install it and restart Riflay.'**
  String get needsWebkit;

  /// No description provided for @spotifySignInUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Signing in to Spotify isn\'t available here.'**
  String get spotifySignInUnavailable;

  /// No description provided for @spotifyIntro.
  ///
  /// In en, this message translates to:
  /// **'Copy your Spotify playlists, Liked Songs and albums into Riflay.'**
  String get spotifyIntro;

  /// No description provided for @spotifyReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Riflay only reads your library. It never changes your Spotify account.'**
  String get spotifyReadOnly;

  /// No description provided for @signInWithSpotify.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Spotify'**
  String get signInWithSpotify;

  /// No description provided for @playlistsGoToYt.
  ///
  /// In en, this message translates to:
  /// **'Playlists go to your YouTube Music library.'**
  String get playlistsGoToYt;

  /// No description provided for @playlistsBecomeRiflay.
  ///
  /// In en, this message translates to:
  /// **'Playlists become Riflay playlists.'**
  String get playlistsBecomeRiflay;

  /// No description provided for @signedInToSpotify.
  ///
  /// In en, this message translates to:
  /// **'Signed in to Spotify'**
  String get signedInToSpotify;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @nothingHereYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.'**
  String get nothingHereYet;

  /// No description provided for @imported.
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get imported;

  /// No description provided for @importAll.
  ///
  /// In en, this message translates to:
  /// **'Import all'**
  String get importAll;

  /// No description provided for @importCount.
  ///
  /// In en, this message translates to:
  /// **'Import {count}'**
  String importCount(String count);

  /// No description provided for @import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import;

  /// No description provided for @importing.
  ///
  /// In en, this message translates to:
  /// **'Importing'**
  String get importing;

  /// No description provided for @stopping.
  ///
  /// In en, this message translates to:
  /// **'Stopping…'**
  String get stopping;

  /// No description provided for @findingSongsInYt.
  ///
  /// In en, this message translates to:
  /// **'Finding songs in YouTube Music: {matched} of {total}'**
  String findingSongsInYt(String matched, String total);

  /// No description provided for @findingArtistInYt.
  ///
  /// In en, this message translates to:
  /// **'Finding the artist in YouTube Music…'**
  String get findingArtistInYt;

  /// No description provided for @readingTheSongs.
  ///
  /// In en, this message translates to:
  /// **'Reading the songs…'**
  String get readingTheSongs;

  /// No description provided for @importedOf.
  ///
  /// In en, this message translates to:
  /// **'Imported {done} of {total}'**
  String importedOf(String done, String total);

  /// No description provided for @youStoppedImport.
  ///
  /// In en, this message translates to:
  /// **'You stopped the import.'**
  String get youStoppedImport;

  /// No description provided for @pronunciation.
  ///
  /// In en, this message translates to:
  /// **'Pronunciation'**
  String get pronunciation;

  /// No description provided for @translation.
  ///
  /// In en, this message translates to:
  /// **'Translation'**
  String get translation;

  /// No description provided for @copyLyrics.
  ///
  /// In en, this message translates to:
  /// **'Copy lyrics'**
  String get copyLyrics;

  /// No description provided for @adjustTiming.
  ///
  /// In en, this message translates to:
  /// **'Adjust timing'**
  String get adjustTiming;

  /// No description provided for @removeMyLyrics.
  ///
  /// In en, this message translates to:
  /// **'Remove my lyrics'**
  String get removeMyLyrics;

  /// No description provided for @playerOptions.
  ///
  /// In en, this message translates to:
  /// **'Player options'**
  String get playerOptions;

  /// No description provided for @chooseLyricsFile.
  ///
  /// In en, this message translates to:
  /// **'Choose a lyrics file'**
  String get chooseLyricsFile;

  /// No description provided for @lyricsFileTooBig.
  ///
  /// In en, this message translates to:
  /// **'That file is too big to be lyrics.'**
  String get lyricsFileTooBig;

  /// No description provided for @yourLyricsInUse.
  ///
  /// In en, this message translates to:
  /// **'Your lyrics are in use'**
  String get yourLyricsInUse;

  /// No description provided for @couldntReadFile.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read that file.'**
  String get couldntReadFile;

  /// No description provided for @couldntRemoveLyrics.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t remove your lyrics.'**
  String get couldntRemoveLyrics;

  /// No description provided for @onTime.
  ///
  /// In en, this message translates to:
  /// **'On time'**
  String get onTime;

  /// No description provided for @secondsEarlier.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s earlier'**
  String secondsEarlier(String seconds);

  /// No description provided for @secondsLater.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s later'**
  String secondsLater(String seconds);

  /// No description provided for @adjustTimingBody.
  ///
  /// In en, this message translates to:
  /// **'If the lyrics come too early or too late, move them until they match the song.'**
  String get adjustTimingBody;

  /// No description provided for @earlier.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get earlier;

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @lyricsCopied.
  ///
  /// In en, this message translates to:
  /// **'Lyrics copied'**
  String get lyricsCopied;

  /// No description provided for @couldntTranslateLyrics.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t translate these lyrics. Check your internet connection.'**
  String get couldntTranslateLyrics;

  /// No description provided for @privacyPublicLabel.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get privacyPublicLabel;

  /// No description provided for @privacyUnlistedLabel.
  ///
  /// In en, this message translates to:
  /// **'Unlisted'**
  String get privacyUnlistedLabel;

  /// No description provided for @privacyPrivateLabel.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get privacyPrivateLabel;

  /// No description provided for @joinedPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Joined \"{title}\"'**
  String joinedPlaylist(String title);

  /// No description provided for @thePlaylist.
  ///
  /// In en, this message translates to:
  /// **'the playlist'**
  String get thePlaylist;

  /// No description provided for @sharedPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Shared playlist'**
  String get sharedPlaylist;

  /// No description provided for @ytSignInPrompt.
  ///
  /// In en, this message translates to:
  /// **'Sign in to YouTube Music to add your liked songs, playlists and history.'**
  String get ytSignInPrompt;

  /// No description provided for @signingIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in…'**
  String get signingIn;

  /// No description provided for @ytLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load YouTube Music. Check your internet connection.'**
  String get ytLoadFailed;

  /// No description provided for @playlistLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this playlist. Check your internet connection.'**
  String get playlistLoadFailed;

  /// No description provided for @playlistIsNow.
  ///
  /// In en, this message translates to:
  /// **'Playlist is now {privacy}'**
  String playlistIsNow(String privacy);

  /// No description provided for @deleteYtPlaylistBody.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" will be deleted from your YouTube Music library. This can\'t be undone.'**
  String deleteYtPlaylistBody(String title);

  /// No description provided for @shared.
  ///
  /// In en, this message translates to:
  /// **'Shared'**
  String get shared;

  /// No description provided for @makePrivacy.
  ///
  /// In en, this message translates to:
  /// **'Make {privacy}'**
  String makePrivacy(String privacy);

  /// No description provided for @chooseDownloadsFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose where downloads are saved'**
  String get chooseDownloadsFolder;

  /// No description provided for @bestSoundNote.
  ///
  /// In en, this message translates to:
  /// **'The best sound YouTube has for each song.'**
  String get bestSoundNote;

  /// No description provided for @smallerFilesNote.
  ///
  /// In en, this message translates to:
  /// **'Smaller files, with a little less full sound.'**
  String get smallerFilesNote;

  /// No description provided for @closestVersionNote.
  ///
  /// In en, this message translates to:
  /// **'{base} Uses the closest version YouTube offers.'**
  String closestVersionNote(String base);

  /// No description provided for @whatToSave.
  ///
  /// In en, this message translates to:
  /// **'What to save'**
  String get whatToSave;

  /// No description provided for @saveAs.
  ///
  /// In en, this message translates to:
  /// **'Save as'**
  String get saveAs;

  /// No description provided for @saveAsVideoNote.
  ///
  /// In en, this message translates to:
  /// **'The music video, with its sound. Songs without a music video are saved as audio.'**
  String get saveAsVideoNote;

  /// No description provided for @saveAsAudioNote.
  ///
  /// In en, this message translates to:
  /// **'Just the sound. Choose Video to keep the music video too.'**
  String get saveAsAudioNote;

  /// No description provided for @videoFormat.
  ///
  /// In en, this message translates to:
  /// **'Video format'**
  String get videoFormat;

  /// No description provided for @size.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get size;

  /// No description provided for @videoSizeNote.
  ///
  /// In en, this message translates to:
  /// **'The tallest picture the video has, up to the one you choose. 1080p is a sharp picture without a huge file.'**
  String get videoSizeNote;

  /// No description provided for @bestAvailable.
  ///
  /// In en, this message translates to:
  /// **'Best available'**
  String get bestAvailable;

  /// No description provided for @heightRecommended.
  ///
  /// In en, this message translates to:
  /// **'{height}p (Recommended)'**
  String heightRecommended(String height);

  /// No description provided for @format.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get format;

  /// No description provided for @flacUnavailable.
  ///
  /// In en, this message translates to:
  /// **'{about}\nFLAC isn\'t available on this device.'**
  String flacUnavailable(String about);

  /// No description provided for @bitDepthSampleRate.
  ///
  /// In en, this message translates to:
  /// **'Bit depth and sample rate'**
  String get bitDepthSampleRate;

  /// No description provided for @bitrate.
  ///
  /// In en, this message translates to:
  /// **'Bitrate'**
  String get bitrate;

  /// No description provided for @askEveryTime.
  ///
  /// In en, this message translates to:
  /// **'Ask every time'**
  String get askEveryTime;

  /// No description provided for @askEveryTimeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the format and quality each time you download a song.'**
  String get askEveryTimeSubtitle;

  /// No description provided for @where.
  ///
  /// In en, this message translates to:
  /// **'Where'**
  String get where;

  /// No description provided for @downloadOverMobile.
  ///
  /// In en, this message translates to:
  /// **'Download over mobile data'**
  String get downloadOverMobile;

  /// No description provided for @downloadOverMobileOn.
  ///
  /// In en, this message translates to:
  /// **'Songs download on mobile data as well as Wi-Fi.'**
  String get downloadOverMobileOn;

  /// No description provided for @downloadOverMobileOff.
  ///
  /// In en, this message translates to:
  /// **'Songs wait for Wi-Fi, so they don\'t use your data plan.'**
  String get downloadOverMobileOff;

  /// No description provided for @downloadsFolder.
  ///
  /// In en, this message translates to:
  /// **'Downloads folder'**
  String get downloadsFolder;

  /// No description provided for @phoneDownloadsFixed.
  ///
  /// In en, this message translates to:
  /// **'{path}\nPhones keep downloads in Riflay\'s own storage, so this can\'t be changed.'**
  String phoneDownloadsFixed(String path);

  /// No description provided for @downloadsFolderUnusable.
  ///
  /// In en, this message translates to:
  /// **'Riflay can\'t save downloads in that folder. On Android, choose one inside Download or Documents.'**
  String get downloadsFolderUnusable;

  /// No description provided for @openFolder.
  ///
  /// In en, this message translates to:
  /// **'Open folder'**
  String get openFolder;

  /// No description provided for @ytDlp.
  ///
  /// In en, this message translates to:
  /// **'YouTube downloader (yt-dlp)'**
  String get ytDlp;

  /// No description provided for @ytDlpMissing.
  ///
  /// In en, this message translates to:
  /// **'Not available. Install it (e.g. pacman -S yt-dlp) for YouTube downloads.'**
  String get ytDlpMissing;

  /// No description provided for @installed.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get installed;

  /// No description provided for @noExtensionsYet.
  ///
  /// In en, this message translates to:
  /// **'No extensions yet'**
  String get noExtensionsYet;

  /// No description provided for @available.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get available;

  /// No description provided for @reading.
  ///
  /// In en, this message translates to:
  /// **'Reading…'**
  String get reading;

  /// No description provided for @install.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get install;

  /// No description provided for @scPlayPause.
  ///
  /// In en, this message translates to:
  /// **'Play or pause'**
  String get scPlayPause;

  /// No description provided for @scNext.
  ///
  /// In en, this message translates to:
  /// **'Next song'**
  String get scNext;

  /// No description provided for @scPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous song'**
  String get scPrevious;

  /// No description provided for @scVolumeUp.
  ///
  /// In en, this message translates to:
  /// **'Volume up'**
  String get scVolumeUp;

  /// No description provided for @scVolumeDown.
  ///
  /// In en, this message translates to:
  /// **'Volume down'**
  String get scVolumeDown;

  /// No description provided for @scBack.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get scBack;

  /// No description provided for @scForward.
  ///
  /// In en, this message translates to:
  /// **'Go forward'**
  String get scForward;

  /// No description provided for @scPasteLink.
  ///
  /// In en, this message translates to:
  /// **'Import a copied YouTube link'**
  String get scPasteLink;

  /// No description provided for @scFullScreen.
  ///
  /// In en, this message translates to:
  /// **'Full screen player'**
  String get scFullScreen;

  /// No description provided for @scHelp.
  ///
  /// In en, this message translates to:
  /// **'Show this list'**
  String get scHelp;

  /// No description provided for @scSlashOr.
  ///
  /// In en, this message translates to:
  /// **'? or Ctrl+/'**
  String get scSlashOr;

  /// No description provided for @saveABackup.
  ///
  /// In en, this message translates to:
  /// **'Save a backup'**
  String get saveABackup;

  /// No description provided for @backupSaved.
  ///
  /// In en, this message translates to:
  /// **'Backup saved'**
  String get backupSaved;

  /// No description provided for @couldntSaveBackup.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the backup.'**
  String get couldntSaveBackup;

  /// No description provided for @chooseBackup.
  ///
  /// In en, this message translates to:
  /// **'Choose a Riflay backup'**
  String get chooseBackup;

  /// No description provided for @backupNeedsNewer.
  ///
  /// In en, this message translates to:
  /// **'This backup needs a newer Riflay.'**
  String get backupNeedsNewer;

  /// No description provided for @notABackup.
  ///
  /// In en, this message translates to:
  /// **'That file isn\'t a Riflay backup.'**
  String get notABackup;

  /// No description provided for @restoreBackupQuestion.
  ///
  /// In en, this message translates to:
  /// **'Restore this backup?'**
  String get restoreBackupQuestion;

  /// No description provided for @restoreBackupBody.
  ///
  /// In en, this message translates to:
  /// **'{made}It has {playlists, plural, =1{1 playlist} other{{playlists} playlists}}, {plays, plural, =1{1 play} other{{plays} plays}} of listening history and {lyrics, plural, =1{1 lyrics file} other{{lyrics} lyrics files}}. They replace the settings, playlists and history on this device. Your sign-ins stay.'**
  String restoreBackupBody(int playlists, int plays, int lyrics, String made);

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @couldntRestoreBackup.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t restore the backup.'**
  String get couldntRestoreBackup;

  /// No description provided for @backupRestored.
  ///
  /// In en, this message translates to:
  /// **'Backup restored'**
  String get backupRestored;

  /// No description provided for @backupRestoredIos.
  ///
  /// In en, this message translates to:
  /// **'Close Riflay from the app switcher and open it again to finish.'**
  String get backupRestoredIos;

  /// No description provided for @backupRestoredDesktop.
  ///
  /// In en, this message translates to:
  /// **'Riflay closes now. Open it again to finish.'**
  String get backupRestoredDesktop;

  /// No description provided for @closeRiflay.
  ///
  /// In en, this message translates to:
  /// **'Close Riflay'**
  String get closeRiflay;

  /// No description provided for @madeOn.
  ///
  /// In en, this message translates to:
  /// **'Made on {date}.'**
  String madeOn(String date);

  /// No description provided for @saveABackupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your settings, playlists, listening history and your own lyrics, in one file. Sign-ins are left out.'**
  String get saveABackupSubtitle;

  /// No description provided for @restoreABackup.
  ///
  /// In en, this message translates to:
  /// **'Restore a backup'**
  String get restoreABackup;

  /// No description provided for @restoreABackupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Bring them back on this device or a new one.'**
  String get restoreABackupSubtitle;

  /// No description provided for @dupRemovedSomeFailed.
  ///
  /// In en, this message translates to:
  /// **'Removed {removed} copies. {failed} files couldn\'t be deleted.'**
  String dupRemovedSomeFailed(int removed, int failed);

  /// No description provided for @dupRemovedAndDeleted.
  ///
  /// In en, this message translates to:
  /// **'Removed {removed} copies and deleted {deleted} files, freeing {size}.'**
  String dupRemovedAndDeleted(int removed, int deleted, String size);

  /// No description provided for @dupRemovedFromLibrary.
  ///
  /// In en, this message translates to:
  /// **'Removed {removed} copies from your library.'**
  String dupRemovedFromLibrary(int removed);

  /// No description provided for @songsYouHaveTwice.
  ///
  /// In en, this message translates to:
  /// **'Songs you have twice'**
  String get songsYouHaveTwice;

  /// No description provided for @lookingThroughLibrary.
  ///
  /// In en, this message translates to:
  /// **'Looking through your library...'**
  String get lookingThroughLibrary;

  /// No description provided for @noDuplicates.
  ///
  /// In en, this message translates to:
  /// **'No song is in your library twice.'**
  String get noDuplicates;

  /// No description provided for @duplicatesBody.
  ///
  /// In en, this message translates to:
  /// **'These are the same song in more than one file. The best copy is chosen for each; pick another if you like, then remove the rest.'**
  String get duplicatesBody;

  /// No description provided for @nothingToRemove.
  ///
  /// In en, this message translates to:
  /// **'Nothing to remove'**
  String get nothingToRemove;

  /// No description provided for @removeExtraCopies.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Remove 1 extra copy} other{Remove {count} extra copies}}'**
  String removeExtraCopies(int count);

  /// No description provided for @upToCanBeFreed.
  ///
  /// In en, this message translates to:
  /// **'Up to {size} can be freed.'**
  String upToCanBeFreed(String size);

  /// No description provided for @chooseOne.
  ///
  /// In en, this message translates to:
  /// **'Choose one'**
  String get chooseOne;

  /// No description provided for @keepAll.
  ///
  /// In en, this message translates to:
  /// **'Keep all'**
  String get keepAll;

  /// No description provided for @bestQuality.
  ///
  /// In en, this message translates to:
  /// **'best quality'**
  String get bestQuality;

  /// No description provided for @downloadedByRiflay.
  ///
  /// In en, this message translates to:
  /// **'Downloaded by Riflay'**
  String get downloadedByRiflay;

  /// No description provided for @yourFile.
  ///
  /// In en, this message translates to:
  /// **'Your file'**
  String get yourFile;

  /// No description provided for @keep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get keep;

  /// No description provided for @removeCopiesQuestion.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Remove 1 copy?} other{Remove {count} copies?}}'**
  String removeCopiesQuestion(int count);

  /// No description provided for @removeCopiesBody.
  ///
  /// In en, this message translates to:
  /// **'They are taken out of your library, and the copy you keep stays. Playlists that had a removed copy use the one you keep.'**
  String get removeCopiesBody;

  /// No description provided for @alsoDeleteFiles.
  ///
  /// In en, this message translates to:
  /// **'Also delete the files from this device'**
  String get alsoDeleteFiles;

  /// No description provided for @freesSize.
  ///
  /// In en, this message translates to:
  /// **'Frees {size}. Deleted files can\'t be brought back.'**
  String freesSize(String size);

  /// No description provided for @ownFilesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} of your own files'**
  String ownFilesCount(int count);

  /// No description provided for @downloadsRiflaySaved.
  ///
  /// In en, this message translates to:
  /// **'{count} downloads Riflay saved'**
  String downloadsRiflaySaved(int count);

  /// No description provided for @listAnd.
  ///
  /// In en, this message translates to:
  /// **'and'**
  String get listAnd;

  /// No description provided for @filesUsedElsewhere.
  ///
  /// In en, this message translates to:
  /// **'{count} files are used by other songs and stay.'**
  String filesUsedElsewhere(int count);

  /// No description provided for @deleteFiles.
  ///
  /// In en, this message translates to:
  /// **'Delete files'**
  String get deleteFiles;

  /// No description provided for @couldntPlay.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t play {title}'**
  String couldntPlay(String title);

  /// No description provided for @ytSearchFailed.
  ///
  /// In en, this message translates to:
  /// **'YouTube search failed. Check your connection.'**
  String get ytSearchFailed;

  /// No description provided for @noYtResults.
  ///
  /// In en, this message translates to:
  /// **'No YouTube results.'**
  String get noYtResults;

  /// No description provided for @ytSearchSource.
  ///
  /// In en, this message translates to:
  /// **'YouTube search'**
  String get ytSearchSource;

  /// No description provided for @topResult.
  ///
  /// In en, this message translates to:
  /// **'Top result'**
  String get topResult;

  /// No description provided for @nothingFound.
  ///
  /// In en, this message translates to:
  /// **'Nothing found.'**
  String get nothingFound;

  /// No description provided for @noYtVideos.
  ///
  /// In en, this message translates to:
  /// **'No YouTube videos found.'**
  String get noYtVideos;

  /// No description provided for @ytVideosSource.
  ///
  /// In en, this message translates to:
  /// **'YouTube videos'**
  String get ytVideosSource;

  /// No description provided for @couldntReadSongInfo.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read this song\'s info'**
  String get couldntReadSongInfo;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @couldntSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the changes'**
  String get couldntSaveChanges;

  /// No description provided for @chooseCoverArt.
  ///
  /// In en, this message translates to:
  /// **'Choose cover art'**
  String get chooseCoverArt;

  /// No description provided for @noCoverFound.
  ///
  /// In en, this message translates to:
  /// **'No cover found for this album'**
  String get noCoverFound;

  /// No description provided for @couldntReachCoverArchive.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the Cover Art Archive'**
  String get couldntReachCoverArchive;

  /// No description provided for @changeCover.
  ///
  /// In en, this message translates to:
  /// **'Change cover'**
  String get changeCover;

  /// No description provided for @searching.
  ///
  /// In en, this message translates to:
  /// **'Searching…'**
  String get searching;

  /// No description provided for @findOnline.
  ///
  /// In en, this message translates to:
  /// **'Find online'**
  String get findOnline;

  /// No description provided for @largeImageHint.
  ///
  /// In en, this message translates to:
  /// **'Use a large image (1000 px or more) for sharp artwork.'**
  String get largeImageHint;

  /// No description provided for @trackNumber.
  ///
  /// In en, this message translates to:
  /// **'Track'**
  String get trackNumber;

  /// No description provided for @discNumber.
  ///
  /// In en, this message translates to:
  /// **'Disc'**
  String get discNumber;

  /// No description provided for @year.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get year;

  /// No description provided for @genre.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get genre;

  /// No description provided for @ytSignInAgain.
  ///
  /// In en, this message translates to:
  /// **'Please sign in to YouTube Music again.'**
  String get ytSignInAgain;

  /// No description provided for @ytBusy.
  ///
  /// In en, this message translates to:
  /// **'YouTube Music is busy. Try again in a minute.'**
  String get ytBusy;

  /// No description provided for @ytNotAnswering.
  ///
  /// In en, this message translates to:
  /// **'YouTube Music isn\'t answering right now. Try again later.'**
  String get ytNotAnswering;

  /// No description provided for @couldntFinishSignIn.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t finish signing in. Try again.'**
  String get couldntFinishSignIn;

  /// No description provided for @signInDidntFinish.
  ///
  /// In en, this message translates to:
  /// **'Signing in didn\'t finish. Try again.'**
  String get signInDidntFinish;

  /// No description provided for @moodsAndGenres.
  ///
  /// In en, this message translates to:
  /// **'Moods & genres'**
  String get moodsAndGenres;

  /// No description provided for @performance.
  ///
  /// In en, this message translates to:
  /// **'Performance'**
  String get performance;

  /// No description provided for @keepScreenOn.
  ///
  /// In en, this message translates to:
  /// **'Keep screen on'**
  String get keepScreenOn;

  /// No description provided for @keepScreenOnPhone.
  ///
  /// In en, this message translates to:
  /// **'Stops the screen from turning off by itself. Costs battery'**
  String get keepScreenOnPhone;

  /// No description provided for @keepScreenOnDesktop.
  ///
  /// In en, this message translates to:
  /// **'Stops the screen from turning off and locking by itself'**
  String get keepScreenOnDesktop;

  /// No description provided for @dontSleepWhilePlaying.
  ///
  /// In en, this message translates to:
  /// **'Don\'t sleep while playing'**
  String get dontSleepWhilePlaying;

  /// No description provided for @dontSleepSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The computer stays awake while music plays. The screen can still turn off'**
  String get dontSleepSubtitle;

  /// No description provided for @closeToTray.
  ///
  /// In en, this message translates to:
  /// **'Close to tray'**
  String get closeToTray;

  /// No description provided for @noTrayIcons.
  ///
  /// In en, this message translates to:
  /// **'Your desktop doesn\'t show tray icons, so closing the window quits Riflay'**
  String get noTrayIcons;

  /// No description provided for @closeToTraySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Closing the window keeps Riflay playing in the tray. Quit it from the tray icon'**
  String get closeToTraySubtitle;

  /// No description provided for @keepPlayingScreenOff.
  ///
  /// In en, this message translates to:
  /// **'Keep playing with the screen off'**
  String get keepPlayingScreenOff;

  /// No description provided for @batteryExemptOn.
  ///
  /// In en, this message translates to:
  /// **'On. Your phone won\'t put Riflay to sleep'**
  String get batteryExemptOn;

  /// No description provided for @batteryExemptOff.
  ///
  /// In en, this message translates to:
  /// **'Off. Your phone may stop the music after a while'**
  String get batteryExemptOff;

  /// No description provided for @allow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get allow;

  /// No description provided for @openBatterySettings.
  ///
  /// In en, this message translates to:
  /// **'Open battery settings'**
  String get openBatterySettings;

  /// No description provided for @keepMusicPlaying.
  ///
  /// In en, this message translates to:
  /// **'Keep the music playing'**
  String get keepMusicPlaying;

  /// No description provided for @keepMusicPlayingBody.
  ///
  /// In en, this message translates to:
  /// **'Some phones stop music when the screen has been off for a while. Allowing Riflay to run in the background keeps it playing. You can change this later in Settings.'**
  String get keepMusicPlayingBody;

  /// No description provided for @notNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notNow;

  /// No description provided for @couldntSaveChangesRetry.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the changes. Try again.'**
  String get couldntSaveChangesRetry;

  /// No description provided for @editSong.
  ///
  /// In en, this message translates to:
  /// **'Edit song'**
  String get editSong;

  /// No description provided for @artistNamesStay.
  ///
  /// In en, this message translates to:
  /// **'Artist names stay as the artist released them.'**
  String get artistNamesStay;

  /// No description provided for @yourLyrics.
  ///
  /// In en, this message translates to:
  /// **'Your lyrics'**
  String get yourLyrics;

  /// No description provided for @yourLyricsBody.
  ///
  /// In en, this message translates to:
  /// **'Shown instead of lyrics found online. Start lines with a time like [01:23.45] to have them follow the song.'**
  String get yourLyricsBody;

  /// No description provided for @pasteLyricsHere.
  ///
  /// In en, this message translates to:
  /// **'Paste lyrics here'**
  String get pasteLyricsHere;

  /// No description provided for @addFromFile.
  ///
  /// In en, this message translates to:
  /// **'Add from a file'**
  String get addFromFile;

  /// No description provided for @importedNamed.
  ///
  /// In en, this message translates to:
  /// **'Imported \"{title}\"'**
  String importedNamed(String title);

  /// No description provided for @pastePlaylistLink.
  ///
  /// In en, this message translates to:
  /// **'Paste a playlist link from Spotify, Apple Music, Deezer, TIDAL or NetEase Cloud Music.'**
  String get pastePlaylistLink;

  /// No description provided for @becomesYtPlaylist.
  ///
  /// In en, this message translates to:
  /// **'It becomes a playlist in your YouTube Music library.'**
  String get becomesYtPlaylist;

  /// No description provided for @becomesRiflayPlaylist.
  ///
  /// In en, this message translates to:
  /// **'It becomes a Riflay playlist of YouTube Music songs.'**
  String get becomesRiflayPlaylist;

  /// No description provided for @playlistLink.
  ///
  /// In en, this message translates to:
  /// **'Playlist link'**
  String get playlistLink;

  /// No description provided for @notAPlaylistLink.
  ///
  /// In en, this message translates to:
  /// **'That isn\'t a Spotify, Apple Music, Deezer, TIDAL or NetEase Cloud Music playlist link'**
  String get notAPlaylistLink;

  /// No description provided for @readingPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Reading the playlist…'**
  String get readingPlaylist;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saving;

  /// No description provided for @songsAddedOf.
  ///
  /// In en, this message translates to:
  /// **'{saved} of {total} songs added.'**
  String songsAddedOf(String saved, String total);

  /// No description provided for @songsAddedOfYt.
  ///
  /// In en, this message translates to:
  /// **'{saved} of {total} songs added to your YouTube Music library.'**
  String songsAddedOfYt(String saved, String total);

  /// No description provided for @firstSongsOnly.
  ///
  /// In en, this message translates to:
  /// **'{service} only shows the first {count} songs without signing in, so the rest were left out.'**
  String firstSongsOnly(int count, String service);

  /// No description provided for @songsNotOnYt.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 song isn\'t on YouTube Music:} other{{count} songs aren\'t on YouTube Music:}}'**
  String songsNotOnYt(int count);

  /// No description provided for @openPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Open playlist'**
  String get openPlaylist;

  /// No description provided for @fmtOpusAbout.
  ///
  /// In en, this message translates to:
  /// **'Smallest files for the same sound. Plays in Riflay and most players.'**
  String get fmtOpusAbout;

  /// No description provided for @fmtM4aAbout.
  ///
  /// In en, this message translates to:
  /// **'The most widely supported. Plays on nearly every phone, TV and speaker.'**
  String get fmtM4aAbout;

  /// No description provided for @fmtFlacAbout.
  ///
  /// In en, this message translates to:
  /// **'Lossless file for players and libraries that want FLAC. YouTube\'s sound is kept exactly; it gets no better.'**
  String get fmtFlacAbout;

  /// No description provided for @fmtMp3About.
  ///
  /// In en, this message translates to:
  /// **'For older players and car stereos. Made from YouTube\'s audio, so it never sounds better than Opus or M4A.'**
  String get fmtMp3About;

  /// No description provided for @kindAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get kindAudio;

  /// No description provided for @kindVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get kindVideo;

  /// No description provided for @vidMp4About.
  ///
  /// In en, this message translates to:
  /// **'H.264 picture and AAC sound. Plays on nearly every phone, TV and computer.'**
  String get vidMp4About;

  /// No description provided for @vidWebmAbout.
  ///
  /// In en, this message translates to:
  /// **'VP9 picture and Opus sound. Smaller files, and the tallest sizes; plays in Riflay and most computers.'**
  String get vidWebmAbout;

  /// No description provided for @flacStandardAbout.
  ///
  /// In en, this message translates to:
  /// **'Same sample rate as YouTube\'s audio. Plays everywhere.'**
  String get flacStandardAbout;

  /// No description provided for @flacCdAbout.
  ///
  /// In en, this message translates to:
  /// **'CD quality, for players and burners that want exactly that.'**
  String get flacCdAbout;

  /// No description provided for @flacHiResAbout.
  ///
  /// In en, this message translates to:
  /// **'Larger files, for libraries kept at 24-bit.'**
  String get flacHiResAbout;

  /// No description provided for @kbpsBest.
  ///
  /// In en, this message translates to:
  /// **'{kbps} kbps (best)'**
  String kbpsBest(String kbps);

  /// No description provided for @videoChoice.
  ///
  /// In en, this message translates to:
  /// **'Video · {container} · {height}'**
  String videoChoice(String container, String height);

  /// No description provided for @bestAvailableLower.
  ///
  /// In en, this message translates to:
  /// **'best available'**
  String get bestAvailableLower;

  /// No description provided for @waitingToStart.
  ///
  /// In en, this message translates to:
  /// **'Waiting to start'**
  String get waitingToStart;

  /// No description provided for @noteDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get noteDownloading;

  /// No description provided for @downloadedTitle.
  ///
  /// In en, this message translates to:
  /// **'Downloaded {title}'**
  String downloadedTitle(String title);

  /// No description provided for @savedToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Saved to your library'**
  String get savedToLibrary;

  /// No description provided for @couldntDownloadTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t download {title}'**
  String couldntDownloadTitle(String title);

  /// No description provided for @tapRetry.
  ///
  /// In en, this message translates to:
  /// **'Tap Retry to try again.'**
  String get tapRetry;

  /// No description provided for @downloadingSongsNote.
  ///
  /// In en, this message translates to:
  /// **'Downloading {count} songs'**
  String downloadingSongsNote(int count);

  /// No description provided for @openRiflay.
  ///
  /// In en, this message translates to:
  /// **'Open Riflay'**
  String get openRiflay;

  /// No description provided for @downloadsChannelDescription.
  ///
  /// In en, this message translates to:
  /// **'Progress of songs being downloaded'**
  String get downloadsChannelDescription;

  /// No description provided for @servicePlaylist.
  ///
  /// In en, this message translates to:
  /// **'{service} playlist'**
  String servicePlaylist(String service);

  /// No description provided for @clearHistoryQuestion.
  ///
  /// In en, this message translates to:
  /// **'Clear listening history?'**
  String get clearHistoryQuestion;

  /// No description provided for @clearHistoryBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This deletes 1 play from this device. Your library and playlists stay as they are, but your stats, Wraps and lists like Most played start over.} other{This deletes {count} plays from this device. Your library and playlists stay as they are, but your stats, Wraps and lists like Most played start over.}}'**
  String clearHistoryBody(int count);

  /// No description provided for @historyCleared.
  ///
  /// In en, this message translates to:
  /// **'Listening history cleared'**
  String get historyCleared;

  /// No description provided for @keepHistory.
  ///
  /// In en, this message translates to:
  /// **'Keep a listening history on this device'**
  String get keepHistory;

  /// No description provided for @keepHistorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Powers Your listening stats, monthly Wraps and lists like Most played. It is never sent anywhere. Turning it off stops recording; what is saved stays until you clear it.'**
  String get keepHistorySubtitle;

  /// No description provided for @wrapNotification.
  ///
  /// In en, this message translates to:
  /// **'Monthly Wrap notification'**
  String get wrapNotification;

  /// No description provided for @wrapNotificationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'On the 1st, tell me when last month\'s Wrap is ready.'**
  String get wrapNotificationSubtitle;

  /// No description provided for @clearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear listening history'**
  String get clearHistory;

  /// No description provided for @nothingSavedYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing saved yet'**
  String get nothingSavedYet;

  /// No description provided for @playsSaved.
  ///
  /// In en, this message translates to:
  /// **'{count} plays saved on this device'**
  String playsSaved(int count);

  /// No description provided for @lyricsFile.
  ///
  /// In en, this message translates to:
  /// **'Lyrics file'**
  String get lyricsFile;

  /// No description provided for @embeddedInFile.
  ///
  /// In en, this message translates to:
  /// **'Embedded in the file'**
  String get embeddedInFile;

  /// No description provided for @addLyricsFirst.
  ///
  /// In en, this message translates to:
  /// **'Add some lyrics first.'**
  String get addLyricsFirst;

  /// No description provided for @lrcTimesWrong.
  ///
  /// In en, this message translates to:
  /// **'Some of the times in these lyrics aren\'t written correctly. Start each line with a time like [01:23.45].'**
  String get lrcTimesWrong;

  /// No description provided for @lrcTimesPastEnd.
  ///
  /// In en, this message translates to:
  /// **'These times run past the end of the song. Check that the lyrics belong to it.'**
  String get lrcTimesPastEnd;

  /// No description provided for @couldntStartSession.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start a session. Check that you\'re connected to Wi-Fi.'**
  String get couldntStartSession;

  /// No description provided for @sessionStopped.
  ///
  /// In en, this message translates to:
  /// **'The session stopped. Start it again to keep listening together.'**
  String get sessionStopped;

  /// No description provided for @nameLeft.
  ///
  /// In en, this message translates to:
  /// **'{name} left'**
  String nameLeft(String name);

  /// No description provided for @someone.
  ///
  /// In en, this message translates to:
  /// **'Someone'**
  String get someone;

  /// No description provided for @nameAddedToQueue.
  ///
  /// In en, this message translates to:
  /// **'{name} added {title} to the queue'**
  String nameAddedToQueue(String name, String title);

  /// No description provided for @sessionNotFound.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t find that session. Check the code and that you\'re on the same Wi-Fi.'**
  String get sessionNotFound;

  /// No description provided for @sessionNotAnswering.
  ///
  /// In en, this message translates to:
  /// **'That session isn\'t answering. Try again in a moment.'**
  String get sessionNotAnswering;

  /// No description provided for @theHostCap.
  ///
  /// In en, this message translates to:
  /// **'The host'**
  String get theHostCap;

  /// No description provided for @hostEndedSession.
  ///
  /// In en, this message translates to:
  /// **'{host} ended the listening session'**
  String hostEndedSession(String host);

  /// No description provided for @sessionEndedOrDropped.
  ///
  /// In en, this message translates to:
  /// **'The session ended or the connection dropped.'**
  String get sessionEndedOrDropped;

  /// No description provided for @lostHostConnection.
  ///
  /// In en, this message translates to:
  /// **'Lost the connection to the host. Join again to keep listening.'**
  String get lostHostConnection;

  /// No description provided for @listeningTogetherSource.
  ///
  /// In en, this message translates to:
  /// **'Listening together'**
  String get listeningTogetherSource;

  /// No description provided for @youLeftSession.
  ///
  /// In en, this message translates to:
  /// **'You left the listening session'**
  String get youLeftSession;

  /// No description provided for @onlyYtToHostQueue.
  ///
  /// In en, this message translates to:
  /// **'Only songs from YouTube Music can be added to {host}\'s queue.'**
  String onlyYtToHostQueue(String host);

  /// No description provided for @checkGithubUpdate.
  ///
  /// In en, this message translates to:
  /// **'Check GitHub for a newer version of Riflay'**
  String get checkGithubUpdate;

  /// No description provided for @checkingUpdates.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get checkingUpdates;

  /// No description provided for @latestVersion.
  ///
  /// In en, this message translates to:
  /// **'You\'re using the latest version'**
  String get latestVersion;

  /// No description provided for @versionAvailable.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is available'**
  String versionAvailable(String version);

  /// No description provided for @downloadingVersion.
  ///
  /// In en, this message translates to:
  /// **'Downloading version {version}…'**
  String downloadingVersion(String version);

  /// No description provided for @versionReady.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is ready to install'**
  String versionReady(String version);

  /// No description provided for @openingInstaller.
  ///
  /// In en, this message translates to:
  /// **'Opening the Android installer…'**
  String get openingInstaller;

  /// No description provided for @completeInInstaller.
  ///
  /// In en, this message translates to:
  /// **'Complete the update in the Android installer'**
  String get completeInInstaller;

  /// No description provided for @allowInstallUpdates.
  ///
  /// In en, this message translates to:
  /// **'Allow Riflay to install updates, then try again'**
  String get allowInstallUpdates;

  /// No description provided for @differentSigningKey.
  ///
  /// In en, this message translates to:
  /// **'This copy uses a different signing key. Back up your data before installing the release'**
  String get differentSigningKey;

  /// No description provided for @couldntVerifyUpdate.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t verify the update. Try downloading it again'**
  String get couldntVerifyUpdate;

  /// No description provided for @couldntCheckUpdates.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check for updates. Try again'**
  String get couldntCheckUpdates;

  /// No description provided for @couldntUpdateRiflay.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update Riflay. Try again'**
  String get couldntUpdateRiflay;

  /// No description provided for @installUpdate.
  ///
  /// In en, this message translates to:
  /// **'Install update'**
  String get installUpdate;

  /// No description provided for @checkForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get checkForUpdates;

  /// No description provided for @downloadUpdate.
  ///
  /// In en, this message translates to:
  /// **'Download update'**
  String get downloadUpdate;

  /// No description provided for @getUpdate.
  ///
  /// In en, this message translates to:
  /// **'Get update'**
  String get getUpdate;

  /// No description provided for @spotifySignInExpired.
  ///
  /// In en, this message translates to:
  /// **'Your Spotify sign-in has expired. Sign in again.'**
  String get spotifySignInExpired;

  /// No description provided for @recommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get recommended;

  /// No description provided for @bestAvailableWith.
  ///
  /// In en, this message translates to:
  /// **'Best available ({label})'**
  String bestAvailableWith(String label);

  /// No description provided for @downloadAsTitle.
  ///
  /// In en, this message translates to:
  /// **'Download as'**
  String get downloadAsTitle;

  /// No description provided for @downloadTrackTitle.
  ///
  /// In en, this message translates to:
  /// **'Download track'**
  String get downloadTrackTitle;

  /// No description provided for @audioFormat.
  ///
  /// In en, this message translates to:
  /// **'Audio format'**
  String get audioFormat;

  /// No description provided for @bitrateQuality.
  ///
  /// In en, this message translates to:
  /// **'Bitrate quality'**
  String get bitrateQuality;

  /// No description provided for @fmtTagUniversal.
  ///
  /// In en, this message translates to:
  /// **'Universal'**
  String get fmtTagUniversal;

  /// No description provided for @fmtTagModern.
  ///
  /// In en, this message translates to:
  /// **'Modern'**
  String get fmtTagModern;

  /// No description provided for @downloadFormatAction.
  ///
  /// In en, this message translates to:
  /// **'Download {format}'**
  String downloadFormatAction(String format);

  /// No description provided for @savedToFolder.
  ///
  /// In en, this message translates to:
  /// **'Saved to {folder}'**
  String savedToFolder(String folder);

  /// No description provided for @couldntLookUpSizes.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t look up video sizes.'**
  String get couldntLookUpSizes;

  /// No description provided for @smallerFilesClosest.
  ///
  /// In en, this message translates to:
  /// **'Smaller files, with a little less full sound. Uses the closest version YouTube offers.'**
  String get smallerFilesClosest;

  /// No description provided for @musicFolders.
  ///
  /// In en, this message translates to:
  /// **'Music folders'**
  String get musicFolders;

  /// No description provided for @keepLibraryUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Keep the library up to date'**
  String get keepLibraryUpToDate;

  /// No description provided for @keepLibraryOpen.
  ///
  /// In en, this message translates to:
  /// **'New songs in your music folders are added, and songs you delete or move are taken out, each time you open Riflay.'**
  String get keepLibraryOpen;

  /// No description provided for @keepLibraryWatch.
  ///
  /// In en, this message translates to:
  /// **'New songs in your music folders are added, and songs you delete or move are taken out, without adding the folder again.'**
  String get keepLibraryWatch;

  /// No description provided for @checkNow.
  ///
  /// In en, this message translates to:
  /// **'Check now'**
  String get checkNow;

  /// No description provided for @addFolderFirst.
  ///
  /// In en, this message translates to:
  /// **'Add a music folder from the library first.'**
  String get addFolderFirst;

  /// No description provided for @checkingDots.
  ///
  /// In en, this message translates to:
  /// **'Checking...'**
  String get checkingDots;

  /// No description provided for @lookAtFoldersAgain.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Look at your music folder again.} other{Look at your {count} music folders again.}}'**
  String lookAtFoldersAgain(int count);

  /// No description provided for @stopWatching.
  ///
  /// In en, this message translates to:
  /// **'Stop watching'**
  String get stopWatching;

  /// No description provided for @tidyUp.
  ///
  /// In en, this message translates to:
  /// **'Tidy up'**
  String get tidyUp;

  /// No description provided for @findDuplicates.
  ///
  /// In en, this message translates to:
  /// **'Find songs you have twice'**
  String get findDuplicates;

  /// No description provided for @findDuplicatesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The same song in different files, so you can keep the best one.'**
  String get findDuplicatesSubtitle;

  /// No description provided for @sessionQr.
  ///
  /// In en, this message translates to:
  /// **'Session QR code'**
  String get sessionQr;

  /// No description provided for @sessionQrSemantics.
  ///
  /// In en, this message translates to:
  /// **'Listening session QR code'**
  String get sessionQrSemantics;

  /// No description provided for @sessionQrHowTo.
  ///
  /// In en, this message translates to:
  /// **'In Riflay on another device, open Listen together and choose Scan QR code.'**
  String get sessionQrHowTo;

  /// No description provided for @notASessionQr.
  ///
  /// In en, this message translates to:
  /// **'That QR code is not a Riflay session code.'**
  String get notASessionQr;

  /// No description provided for @noSessionInImage.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t find a Riflay session code in that image.'**
  String get noSessionInImage;

  /// No description provided for @couldntReadImage.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read that image. Try another one.'**
  String get couldntReadImage;

  /// No description provided for @cameraUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Camera unavailable. Allow camera access in your device settings, or open a QR image.'**
  String get cameraUnavailable;

  /// No description provided for @openQrImageToJoin.
  ///
  /// In en, this message translates to:
  /// **'Open an image of the session QR code to join.'**
  String get openQrImageToJoin;

  /// No description provided for @pointCamera.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the session QR code shown in Riflay.'**
  String get pointCamera;

  /// No description provided for @readingImage.
  ///
  /// In en, this message translates to:
  /// **'Reading image…'**
  String get readingImage;

  /// No description provided for @openQrImage.
  ///
  /// In en, this message translates to:
  /// **'Open QR image'**
  String get openQrImage;

  /// No description provided for @motionGlide.
  ///
  /// In en, this message translates to:
  /// **'Glide'**
  String get motionGlide;

  /// No description provided for @motionFadeThrough.
  ///
  /// In en, this message translates to:
  /// **'Fade through'**
  String get motionFadeThrough;

  /// No description provided for @motionSoftZoom.
  ///
  /// In en, this message translates to:
  /// **'Soft zoom'**
  String get motionSoftZoom;

  /// No description provided for @motionSlide.
  ///
  /// In en, this message translates to:
  /// **'Slide'**
  String get motionSlide;

  /// No description provided for @motionCurtain.
  ///
  /// In en, this message translates to:
  /// **'Curtain reveal'**
  String get motionCurtain;

  /// No description provided for @motionCircular.
  ///
  /// In en, this message translates to:
  /// **'Circular reveal'**
  String get motionCircular;

  /// No description provided for @motionSide.
  ///
  /// In en, this message translates to:
  /// **'Side reveal'**
  String get motionSide;

  /// No description provided for @motionDiamond.
  ///
  /// In en, this message translates to:
  /// **'Diamond reveal'**
  String get motionDiamond;

  /// No description provided for @speedFast.
  ///
  /// In en, this message translates to:
  /// **'Fast'**
  String get speedFast;

  /// No description provided for @speedRelaxed.
  ///
  /// In en, this message translates to:
  /// **'Relaxed'**
  String get speedRelaxed;

  /// No description provided for @serviceSignedOutSettings.
  ///
  /// In en, this message translates to:
  /// **'{service} signed you out. Connect it again in Settings.'**
  String serviceSignedOutSettings(String service);

  /// No description provided for @lostConnectionTo.
  ///
  /// In en, this message translates to:
  /// **'Lost connection to {device}'**
  String lostConnectionTo(String device);

  /// No description provided for @couldntPlayOn.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t play on {device}'**
  String couldntPlayOn(String device);

  /// No description provided for @pasteYtLink.
  ///
  /// In en, this message translates to:
  /// **'Paste a YouTube link to a video or playlist.'**
  String get pasteYtLink;

  /// No description provided for @linkLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load that link. It may be private, removed or region-locked.'**
  String get linkLoadFailed;

  /// No description provided for @importFromYtBody.
  ///
  /// In en, this message translates to:
  /// **'Downloads the audio track and adds it to your library.'**
  String get importFromYtBody;

  /// No description provided for @paste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// No description provided for @bestQualityNote.
  ///
  /// In en, this message translates to:
  /// **'Saved in the best quality YouTube offers (up to ~160 kbps Opus/AAC), without re-encoding.'**
  String get bestQualityNote;

  /// No description provided for @downloadCount.
  ///
  /// In en, this message translates to:
  /// **'Download {count}'**
  String downloadCount(String count);

  /// No description provided for @aboutSize.
  ///
  /// In en, this message translates to:
  /// **'About {size}'**
  String aboutSize(String size);

  /// No description provided for @aboutSizeTotal.
  ///
  /// In en, this message translates to:
  /// **'About {size} total'**
  String aboutSizeTotal(String size);

  /// No description provided for @ytPlaylistLine.
  ///
  /// In en, this message translates to:
  /// **'Playlist • {author} • {count} videos'**
  String ytPlaylistLine(int count, String author);

  /// No description provided for @checkingSize.
  ///
  /// In en, this message translates to:
  /// **'Checking size…'**
  String get checkingSize;

  /// No description provided for @eqBitPerfectNote.
  ///
  /// In en, this message translates to:
  /// **'Bit-perfect mode is on, so the equalizer is bypassed. Turn it off in Settings › Sound › Output & quality.'**
  String get eqBitPerfectNote;

  /// No description provided for @eqHint.
  ///
  /// In en, this message translates to:
  /// **'Pick a preset or drag the sliders. Tap a frequency to fine-tune it.'**
  String get eqHint;

  /// No description provided for @eqHeadroom.
  ///
  /// In en, this message translates to:
  /// **'Headroom {db} dB, so boosted bands never distort.'**
  String eqHeadroom(String db);

  /// No description provided for @changeFrequency.
  ///
  /// In en, this message translates to:
  /// **'Change frequency and width'**
  String get changeFrequency;

  /// No description provided for @bandNumber.
  ///
  /// In en, this message translates to:
  /// **'Band {number}'**
  String bandNumber(String number);

  /// No description provided for @defaultLabel.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultLabel;

  /// No description provided for @newReleases.
  ///
  /// In en, this message translates to:
  /// **'New releases'**
  String get newReleases;

  /// No description provided for @couldntLoadPage.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this page. Check your internet connection.'**
  String get couldntLoadPage;

  /// No description provided for @removedFromLibrary.
  ///
  /// In en, this message translates to:
  /// **'Removed from your library'**
  String get removedFromLibrary;

  /// No description provided for @saveToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Save to library'**
  String get saveToLibrary;

  /// No description provided for @phaseDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get phaseDownloading;

  /// No description provided for @converting.
  ///
  /// In en, this message translates to:
  /// **'Converting…'**
  String get converting;

  /// No description provided for @finishing.
  ///
  /// In en, this message translates to:
  /// **'Finishing…'**
  String get finishing;

  /// No description provided for @needsFfmpegMp3.
  ///
  /// In en, this message translates to:
  /// **'MP3 downloads need ffmpeg, which isn\'t available here. Pick another format in Settings › Library & downloads › Downloads.'**
  String get needsFfmpegMp3;

  /// No description provided for @noFlacHere.
  ///
  /// In en, this message translates to:
  /// **'FLAC downloads aren\'t available on this device. Pick another format in Settings › Library & downloads › Downloads.'**
  String get noFlacHere;

  /// No description provided for @mobileDataOff.
  ///
  /// In en, this message translates to:
  /// **'Mobile data downloads are off. Connect to Wi-Fi, or allow them in Settings › Library & downloads › Downloads.'**
  String get mobileDataOff;

  /// No description provided for @couldntDownloadSong.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t download this song. Try again later.'**
  String get couldntDownloadSong;

  /// No description provided for @spotifyLinePlaylist.
  ///
  /// In en, this message translates to:
  /// **'{name}: {found} of {total} songs'**
  String spotifyLinePlaylist(String name, String found, String total);

  /// No description provided for @spotifyLineAlbumSaved.
  ///
  /// In en, this message translates to:
  /// **'{name}: saved to your library'**
  String spotifyLineAlbumSaved(String name);

  /// No description provided for @spotifyLineFollowed.
  ///
  /// In en, this message translates to:
  /// **'{name}: followed'**
  String spotifyLineFollowed(String name);

  /// No description provided for @spotifyLineArtistMissing.
  ///
  /// In en, this message translates to:
  /// **'{name}: not found on YouTube Music'**
  String spotifyLineArtistMissing(String name);

  /// No description provided for @spotifyLineNoSongs.
  ///
  /// In en, this message translates to:
  /// **'{name}: no songs found on YouTube Music'**
  String spotifyLineNoSongs(String name);

  /// No description provided for @spotifyLineFailed.
  ///
  /// In en, this message translates to:
  /// **'{name}: {problem}'**
  String spotifyLineFailed(String name, String problem);

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'something went wrong'**
  String get somethingWentWrong;

  /// No description provided for @positionOf.
  ///
  /// In en, this message translates to:
  /// **'{kind} {position} of {count}'**
  String positionOf(String kind, String position, String count);

  /// No description provided for @signInYtFirst.
  ///
  /// In en, this message translates to:
  /// **'sign in to YouTube Music first'**
  String get signInYtFirst;

  /// No description provided for @hideRiflay.
  ///
  /// In en, this message translates to:
  /// **'Hide Riflay'**
  String get hideRiflay;

  /// No description provided for @showRiflay.
  ///
  /// In en, this message translates to:
  /// **'Show Riflay'**
  String get showRiflay;

  /// No description provided for @quitRiflay.
  ///
  /// In en, this message translates to:
  /// **'Quit Riflay'**
  String get quitRiflay;

  /// No description provided for @convertingToFlac.
  ///
  /// In en, this message translates to:
  /// **'Converting {title} to FLAC…'**
  String convertingToFlac(String title);

  /// No description provided for @convertingSongsToFlac.
  ///
  /// In en, this message translates to:
  /// **'Converting {count} songs to FLAC…'**
  String convertingSongsToFlac(int count);

  /// No description provided for @convertedToFlac.
  ///
  /// In en, this message translates to:
  /// **'Converted {title} to FLAC'**
  String convertedToFlac(String title);

  /// No description provided for @alreadyLossless.
  ///
  /// In en, this message translates to:
  /// **'{title} is already lossless'**
  String alreadyLossless(String title);

  /// No description provided for @couldntConvert.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t convert {title}'**
  String couldntConvert(String title);

  /// No description provided for @convertedSongsToFlac.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Converted 1 song to FLAC} other{Converted {count} songs to FLAC}}'**
  String convertedSongsToFlac(int count);

  /// No description provided for @convertedSomeFailed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Converted 1 song to FLAC, {failed} couldn\'t be converted} other{Converted {count} songs to FLAC, {failed} couldn\'t be converted}}'**
  String convertedSomeFailed(int count, int failed);

  /// No description provided for @couldntConvertThese.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t convert these songs'**
  String get couldntConvertThese;

  /// No description provided for @addedSongsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Added 1 song} other{Added {count} songs}}'**
  String addedSongsCount(int count);

  /// No description provided for @allowReadMusic.
  ///
  /// In en, this message translates to:
  /// **'Allow Riflay to read your music to add a folder'**
  String get allowReadMusic;

  /// No description provided for @couldntAddMusic.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add that music'**
  String get couldntAddMusic;

  /// No description provided for @pressBackToExit.
  ///
  /// In en, this message translates to:
  /// **'Press back again to exit'**
  String get pressBackToExit;

  /// No description provided for @downloadingAudio.
  ///
  /// In en, this message translates to:
  /// **'Downloading audio…'**
  String get downloadingAudio;

  /// No description provided for @view.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get view;

  /// No description provided for @resizeSidebar.
  ///
  /// In en, this message translates to:
  /// **'Resize sidebar'**
  String get resizeSidebar;

  /// No description provided for @resizeSidePanel.
  ///
  /// In en, this message translates to:
  /// **'Resize side panel'**
  String get resizeSidePanel;

  /// No description provided for @signInToSpotify.
  ///
  /// In en, this message translates to:
  /// **'Sign in to Spotify'**
  String get signInToSpotify;

  /// No description provided for @checkingSession.
  ///
  /// In en, this message translates to:
  /// **'Checking the session…'**
  String get checkingSession;

  /// No description provided for @spotifyHandlesSignIn.
  ///
  /// In en, this message translates to:
  /// **'Spotify handles the sign-in. Riflay only reads your library.'**
  String get spotifyHandlesSignIn;

  /// No description provided for @couldntLoadSignIn.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the sign-in page. Check your internet connection.'**
  String get couldntLoadSignIn;

  /// No description provided for @noSessionYet.
  ///
  /// In en, this message translates to:
  /// **'No signed-in session on this page yet. Finish signing in above, then tap Try again.'**
  String get noSessionYet;

  /// No description provided for @couldntReadSpotifySession.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read the Spotify session. Try again.'**
  String get couldntReadSpotifySession;

  /// No description provided for @signInToYt.
  ///
  /// In en, this message translates to:
  /// **'Sign in to YouTube Music'**
  String get signInToYt;

  /// No description provided for @googleHandlesSignIn.
  ///
  /// In en, this message translates to:
  /// **'Google handles the sign-in. Riflay only keeps the session.'**
  String get googleHandlesSignIn;

  /// No description provided for @couldNotUseSignIn.
  ///
  /// In en, this message translates to:
  /// **'Could not use that sign-in.'**
  String get couldNotUseSignIn;

  /// No description provided for @nothingIsPlaying.
  ///
  /// In en, this message translates to:
  /// **'Nothing is playing'**
  String get nothingIsPlaying;

  /// No description provided for @pressEscToExit.
  ///
  /// In en, this message translates to:
  /// **'Press Esc to exit full screen'**
  String get pressEscToExit;

  /// No description provided for @hideEqualizer.
  ///
  /// In en, this message translates to:
  /// **'Hide equalizer'**
  String get hideEqualizer;

  /// No description provided for @videoUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This video is unavailable.'**
  String get videoUnavailable;

  /// No description provided for @videoUnplayable.
  ///
  /// In en, this message translates to:
  /// **'This video can\'t be played (private, age-restricted or region-locked).'**
  String get videoUnplayable;

  /// No description provided for @muxFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t combine the picture and the sound. Try again, or pick another size in Settings › Library & downloads › Downloads.'**
  String get muxFailed;

  /// No description provided for @noInternetTryAgain.
  ///
  /// In en, this message translates to:
  /// **'No internet connection. Try again.'**
  String get noInternetTryAgain;

  /// No description provided for @flacBiggerOne.
  ///
  /// In en, this message translates to:
  /// **'The FLAC file will be bigger than the original. The sound stays the same: FLAC can\'t bring back what the original already lost.'**
  String get flacBiggerOne;

  /// No description provided for @flacBiggerEach.
  ///
  /// In en, this message translates to:
  /// **'Each FLAC file will be bigger than the original. The sound stays the same: FLAC can\'t bring back what the original already lost.'**
  String get flacBiggerEach;

  /// No description provided for @ownSongsStay.
  ///
  /// In en, this message translates to:
  /// **'Songs you added yourself stay as they are, next to their FLAC.'**
  String get ownSongsStay;

  /// No description provided for @quality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get quality;

  /// No description provided for @convert.
  ///
  /// In en, this message translates to:
  /// **'Convert'**
  String get convert;

  /// No description provided for @betaMusixmatchBody.
  ///
  /// In en, this message translates to:
  /// **'Look for word-by-word lyrics on Musixmatch when other sources have none.'**
  String get betaMusixmatchBody;

  /// No description provided for @betaVideoModeBody.
  ///
  /// In en, this message translates to:
  /// **'Watch a song\'s music video in the player, in step with the song.'**
  String get betaVideoModeBody;

  /// No description provided for @betaDirectUsbBody.
  ///
  /// In en, this message translates to:
  /// **'Play straight to a USB DAC, past Android. Experimental.'**
  String get betaDirectUsbBody;

  /// No description provided for @mostPlayed.
  ///
  /// In en, this message translates to:
  /// **'Most played'**
  String get mostPlayed;

  /// No description provided for @notPlayedForAWhile.
  ///
  /// In en, this message translates to:
  /// **'Not played for a while'**
  String get notPlayedForAWhile;

  /// No description provided for @thisSong.
  ///
  /// In en, this message translates to:
  /// **'this song'**
  String get thisSong;

  /// No description provided for @addMusicFolder.
  ///
  /// In en, this message translates to:
  /// **'Add music folder'**
  String get addMusicFolder;

  /// No description provided for @couldntReachDevice.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach {device}'**
  String couldntReachDevice(String device);

  /// No description provided for @presetClassicNote.
  ///
  /// In en, this message translates to:
  /// **'The player as it has always been, the cover pulsing with the music'**
  String get presetClassicNote;

  /// No description provided for @presetStackedNote.
  ///
  /// In en, this message translates to:
  /// **'The cover as the page, joined buttons, a thick bar and a wide Play button'**
  String get presetStackedNote;

  /// No description provided for @presetKawaiiNote.
  ///
  /// In en, this message translates to:
  /// **'The cover fades into the page, with plain icons, a wavy line and the volume behind a button'**
  String get presetKawaiiNote;

  /// No description provided for @useThisColour.
  ///
  /// In en, this message translates to:
  /// **'Use this colour'**
  String get useThisColour;

  /// No description provided for @saturationBrightness.
  ///
  /// In en, this message translates to:
  /// **'Saturation and brightness'**
  String get saturationBrightness;

  /// No description provided for @hue.
  ///
  /// In en, this message translates to:
  /// **'Hue'**
  String get hue;

  /// No description provided for @wrapReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your {month} in music is ready'**
  String wrapReadyTitle(String month);

  /// No description provided for @monthlyWrap.
  ///
  /// In en, this message translates to:
  /// **'Monthly Wrap'**
  String get monthlyWrap;

  /// No description provided for @monthlyWrapChannel.
  ///
  /// In en, this message translates to:
  /// **'Your month in music, once it is over'**
  String get monthlyWrapChannel;

  /// No description provided for @tapToSeeListened.
  ///
  /// In en, this message translates to:
  /// **'Tap to see what you listened to.'**
  String get tapToSeeListened;

  /// No description provided for @vizOffBitPerfect.
  ///
  /// In en, this message translates to:
  /// **'Off while Bit-perfect is on: nothing may change the sound on its way to your DAC'**
  String get vizOffBitPerfect;

  /// No description provided for @vizOffLightweight.
  ///
  /// In en, this message translates to:
  /// **'Off in the Lightweight performance mode'**
  String get vizOffLightweight;

  /// No description provided for @vizOffReducedMotion.
  ///
  /// In en, this message translates to:
  /// **'Off while Motion is reduced'**
  String get vizOffReducedMotion;

  /// No description provided for @vizHiddenDop.
  ///
  /// In en, this message translates to:
  /// **'Hidden while this song plays as DSD over DoP'**
  String get vizHiddenDop;

  /// No description provided for @vizHiddenCasting.
  ///
  /// In en, this message translates to:
  /// **'Hidden while playing on another device'**
  String get vizHiddenCasting;

  /// No description provided for @minimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get minimize;

  /// No description provided for @maximize.
  ///
  /// In en, this message translates to:
  /// **'Maximize'**
  String get maximize;

  /// No description provided for @windowRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get windowRestore;

  /// No description provided for @whilePlaying.
  ///
  /// In en, this message translates to:
  /// **'While playing'**
  String get whilePlaying;

  /// No description provided for @whileRiflayOpen.
  ///
  /// In en, this message translates to:
  /// **'While Riflay is open'**
  String get whileRiflayOpen;

  /// No description provided for @moreOptionsFor.
  ///
  /// In en, this message translates to:
  /// **'More options for {title}'**
  String moreOptionsFor(String title);

  /// No description provided for @removedFileNotDeleted.
  ///
  /// In en, this message translates to:
  /// **'Removed from your library; the file couldn\'t be deleted.'**
  String get removedFileNotDeleted;

  /// No description provided for @couldntPlayOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t play {title} on {device}'**
  String couldntPlayOnDevice(String title, String device);

  /// No description provided for @tallerAsWebm.
  ///
  /// In en, this message translates to:
  /// **'{size} is available as WebM.'**
  String tallerAsWebm(String size);

  /// No description provided for @dsdUseDacVolume.
  ///
  /// In en, this message translates to:
  /// **'DSD goes to your DAC as it is: use the DAC\'s volume'**
  String get dsdUseDacVolume;

  /// No description provided for @streamsOnline.
  ///
  /// In en, this message translates to:
  /// **'YouTube Music: needs internet'**
  String get streamsOnline;

  /// No description provided for @playsOfflineHere.
  ///
  /// In en, this message translates to:
  /// **'On this device: plays offline'**
  String get playsOfflineHere;

  /// No description provided for @showAll.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get showAll;

  /// No description provided for @offWhileDirect.
  ///
  /// In en, this message translates to:
  /// **'Off while the sound goes straight to your DAC'**
  String get offWhileDirect;

  /// No description provided for @ffmpegOneTime.
  ///
  /// In en, this message translates to:
  /// **'Getting this ready: a one-time download (about 40 MB)…'**
  String get ffmpegOneTime;

  /// No description provided for @matugenInvalid.
  ///
  /// In en, this message translates to:
  /// **'Choose a valid Matugen JSON color file. Keeping the last working colors.'**
  String get matugenInvalid;

  /// No description provided for @couldntSignInSpotify.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sign in to Spotify. Try again.'**
  String get couldntSignInSpotify;

  /// No description provided for @somethingWentWrongRetry.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get somethingWentWrongRetry;

  /// No description provided for @videoCouldntLoad.
  ///
  /// In en, this message translates to:
  /// **'The video couldn\'t load, so the song plays on its own.'**
  String get videoCouldntLoad;

  /// No description provided for @keySpace.
  ///
  /// In en, this message translates to:
  /// **'Space'**
  String get keySpace;

  /// No description provided for @forward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get forward;

  /// No description provided for @deletePlaylistBody.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" will be deleted. The songs stay in your library.'**
  String deletePlaylistBody(String name);

  /// No description provided for @lyricsOtherVersion.
  ///
  /// In en, this message translates to:
  /// **'These lyrics are from a different recording of the same song (for example, the studio version instead of a live performance). The words may be correct, but their timing may not match. Open the lyrics menu > Adjust timing to shift them.'**
  String get lyricsOtherVersion;

  /// No description provided for @backToCurrentLine.
  ///
  /// In en, this message translates to:
  /// **'Back to current line'**
  String get backToCurrentLine;

  /// No description provided for @signInWindowClosed.
  ///
  /// In en, this message translates to:
  /// **'The sign-in window closed unexpectedly. Try again.'**
  String get signInWindowClosed;

  /// No description provided for @spotifySignInWindowClosed.
  ///
  /// In en, this message translates to:
  /// **'The Spotify sign-in window closed unexpectedly. Try again.'**
  String get spotifySignInWindowClosed;

  /// No description provided for @deviceDidntRespond.
  ///
  /// In en, this message translates to:
  /// **'{device} didn\'t respond'**
  String deviceDidntRespond(String device);

  /// No description provided for @theDevice.
  ///
  /// In en, this message translates to:
  /// **'The device'**
  String get theDevice;

  /// No description provided for @ytReturnedNothing.
  ///
  /// In en, this message translates to:
  /// **'YouTube Music returned nothing. Check your connection.'**
  String get ytReturnedNothing;

  /// No description provided for @signInToChangeYt.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google to change your YouTube Music library.'**
  String get signInToChangeYt;

  /// No description provided for @notYtInvite.
  ///
  /// In en, this message translates to:
  /// **'That isn\'t a YouTube Music invite link.'**
  String get notYtInvite;

  /// No description provided for @noInternetCheck.
  ///
  /// In en, this message translates to:
  /// **'No internet connection. Check it and try again.'**
  String get noInternetCheck;

  /// No description provided for @ytDidntCreatePlaylist.
  ///
  /// In en, this message translates to:
  /// **'YouTube Music did not create the playlist.'**
  String get ytDidntCreatePlaylist;

  /// No description provided for @ytDidntTakeChange.
  ///
  /// In en, this message translates to:
  /// **'YouTube Music didn\'t take that change. Try again.'**
  String get ytDidntTakeChange;

  /// No description provided for @ytDidntMakeInvite.
  ///
  /// In en, this message translates to:
  /// **'YouTube Music did not make an invite link.'**
  String get ytDidntMakeInvite;

  /// No description provided for @notPlaylistLinkFrom.
  ///
  /// In en, this message translates to:
  /// **'That isn\'t a playlist link from {services}.'**
  String notPlaylistLinkFrom(String services);

  /// No description provided for @playlistEmptyOrPrivate.
  ///
  /// In en, this message translates to:
  /// **'That playlist is empty, or it\'s private.'**
  String get playlistEmptyOrPrivate;

  /// No description provided for @playlistMissingOrPrivate.
  ///
  /// In en, this message translates to:
  /// **'That playlist doesn\'t exist, or it\'s private.'**
  String get playlistMissingOrPrivate;

  /// No description provided for @spotifyPageChanged.
  ///
  /// In en, this message translates to:
  /// **'Spotify changed its page; this link can\'t be read right now.'**
  String get spotifyPageChanged;

  /// No description provided for @unexpectedDeezerReply.
  ///
  /// In en, this message translates to:
  /// **'Unexpected reply from Deezer.'**
  String get unexpectedDeezerReply;

  /// No description provided for @lbTokenInvalid.
  ///
  /// In en, this message translates to:
  /// **'ListenBrainz says this token isn\'t valid.'**
  String get lbTokenInvalid;

  /// No description provided for @noneOfItsSongsOnYt.
  ///
  /// In en, this message translates to:
  /// **'None of its songs are on YouTube Music.'**
  String get noneOfItsSongsOnYt;

  /// No description provided for @accentNamed.
  ///
  /// In en, this message translates to:
  /// **'{name} accent'**
  String accentNamed(String name);

  /// No description provided for @frequencyHz.
  ///
  /// In en, this message translates to:
  /// **'Frequency: {hz}Hz'**
  String frequencyHz(String hz);

  /// No description provided for @deletedNamed.
  ///
  /// In en, this message translates to:
  /// **'Deleted \"{title}\"'**
  String deletedNamed(String title);

  /// No description provided for @spotifySongsNotFound.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{name}: 1 song not found} other{{name}: {count} songs not found}}'**
  String spotifySongsNotFound(int count, String name);

  /// No description provided for @statsListened.
  ///
  /// In en, this message translates to:
  /// **'listened'**
  String get statsListened;

  /// No description provided for @statsSongsUnit.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{song} other{songs}}'**
  String statsSongsUnit(int count);

  /// No description provided for @statsPlaysUnit.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{play} other{plays}}'**
  String statsPlaysUnit(int count);

  /// No description provided for @albumsPlural.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 album} other{{count} albums}}'**
  String albumsPlural(int count);

  /// No description provided for @listensWaiting.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{who}. 1 listen waiting to be sent.} other{{who}. {count} listens waiting to be sent.}}'**
  String listensWaiting(int count, String who);

  /// No description provided for @sessionCodeHint.
  ///
  /// In en, this message translates to:
  /// **'ABC123 or ABCDE-FGHJK'**
  String get sessionCodeHint;

  /// No description provided for @downloadedTools.
  ///
  /// In en, this message translates to:
  /// **'Downloaded tools'**
  String get downloadedTools;

  /// No description provided for @deleteExecutables.
  ///
  /// In en, this message translates to:
  /// **'Delete executables'**
  String get deleteExecutables;

  /// No description provided for @downloadedToolsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Find and delete FFmpeg and yt-dlp downloaded by Riflay.'**
  String get downloadedToolsSubtitle;

  /// No description provided for @downloadedToolsIntro.
  ///
  /// In en, this message translates to:
  /// **'Only tools downloaded by Riflay are listed here. System-installed tools are managed separately.'**
  String get downloadedToolsIntro;

  /// No description provided for @noDownloadedTools.
  ///
  /// In en, this message translates to:
  /// **'No downloaded executables found.'**
  String get noDownloadedTools;

  /// No description provided for @deleteAllExecutables.
  ///
  /// In en, this message translates to:
  /// **'Delete all executables'**
  String get deleteAllExecutables;

  /// No description provided for @deleteExecutablesQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete downloaded executables?'**
  String get deleteExecutablesQuestion;

  /// No description provided for @deleteExecutablesBody.
  ///
  /// In en, this message translates to:
  /// **'Riflay will download these tools again when needed. Your music and settings will stay.'**
  String get deleteExecutablesBody;

  /// No description provided for @executablesDeleted.
  ///
  /// In en, this message translates to:
  /// **'Downloaded executables deleted.'**
  String get executablesDeleted;

  /// No description provided for @couldntFindExecutables.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t find downloaded executables. Try again.'**
  String get couldntFindExecutables;

  /// No description provided for @couldntDeleteExecutables.
  ///
  /// In en, this message translates to:
  /// **'Some executables couldn\'t be deleted. Try again.'**
  String get couldntDeleteExecutables;

  /// No description provided for @presetLiquidStackedNote.
  ///
  /// In en, this message translates to:
  /// **'Stacked, with Liquid Glass controls and glass tabs on phones'**
  String get presetLiquidStackedNote;

  /// No description provided for @presetLiquidKawaiiNote.
  ///
  /// In en, this message translates to:
  /// **'Kawaii, with Liquid Glass controls and glass tabs on phones'**
  String get presetLiquidKawaiiNote;

  /// No description provided for @liquidGlassControls.
  ///
  /// In en, this message translates to:
  /// **'Liquid Glass controls'**
  String get liquidGlassControls;

  /// No description provided for @liquidGlassControlsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Frost the player’s buttons. Choose below which other parts are glass too.'**
  String get liquidGlassControlsSubtitle;

  /// No description provided for @glassSeekBar.
  ///
  /// In en, this message translates to:
  /// **'Glass progress bar'**
  String get glassSeekBar;

  /// No description provided for @glassTransport.
  ///
  /// In en, this message translates to:
  /// **'Glass playback buttons'**
  String get glassTransport;

  /// No description provided for @glassTransportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Previous, play/pause and next'**
  String get glassTransportSubtitle;

  /// No description provided for @glassVolume.
  ///
  /// In en, this message translates to:
  /// **'Glass volume'**
  String get glassVolume;

  /// No description provided for @deviceSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up Riflay for this computer'**
  String get deviceSetupTitle;

  /// No description provided for @deviceSetupIntro.
  ///
  /// In en, this message translates to:
  /// **'Riflay looked at this computer and picked the look that suits it: fewer effects for older computers and little memory, more for powerful ones. You can change it any time in Settings › Power & background.'**
  String get deviceSetupIntro;

  /// No description provided for @deviceSetupThreads.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 processor thread} other{{count} processor threads}}'**
  String deviceSetupThreads(int count);

  /// No description provided for @deviceSetupMemory.
  ///
  /// In en, this message translates to:
  /// **'{size} GB of memory'**
  String deviceSetupMemory(String size);

  /// No description provided for @deviceSetupLaptop.
  ///
  /// In en, this message translates to:
  /// **'Laptop, runs on battery'**
  String get deviceSetupLaptop;

  /// No description provided for @deviceSetupDesktop.
  ///
  /// In en, this message translates to:
  /// **'Desktop, no battery'**
  String get deviceSetupDesktop;

  /// No description provided for @deviceSetupCost.
  ///
  /// In en, this message translates to:
  /// **'About {percent}% of the processor while a song plays'**
  String deviceSetupCost(String percent);

  /// No description provided for @deviceSetupRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get deviceSetupRecommended;

  /// No description provided for @deviceSetupContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get deviceSetupContinue;

  /// No description provided for @deviceSetupKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep my settings'**
  String get deviceSetupKeep;

  /// No description provided for @deviceSetupAgain.
  ///
  /// In en, this message translates to:
  /// **'Check this computer'**
  String get deviceSetupAgain;

  /// No description provided for @deviceSetupAgainNote.
  ///
  /// In en, this message translates to:
  /// **'Looks at this computer again and suggests the look that suits it'**
  String get deviceSetupAgainNote;

  /// No description provided for @sourceYoutubeMusic.
  ///
  /// In en, this message translates to:
  /// **'YouTube Music'**
  String get sourceYoutubeMusic;

  /// No description provided for @sourceSoundcloud.
  ///
  /// In en, this message translates to:
  /// **'SoundCloud'**
  String get sourceSoundcloud;

  /// No description provided for @streamsFromSoundcloud.
  ///
  /// In en, this message translates to:
  /// **'SoundCloud: needs internet'**
  String get streamsFromSoundcloud;

  /// No description provided for @soundcloudSearchSource.
  ///
  /// In en, this message translates to:
  /// **'SoundCloud search'**
  String get soundcloudSearchSource;

  /// No description provided for @onSoundcloud.
  ///
  /// In en, this message translates to:
  /// **'On SoundCloud'**
  String get onSoundcloud;

  /// No description provided for @soundcloudSearchFailed.
  ///
  /// In en, this message translates to:
  /// **'SoundCloud search failed. Check your connection.'**
  String get soundcloudSearchFailed;

  /// No description provided for @noSoundcloudResults.
  ///
  /// In en, this message translates to:
  /// **'No SoundCloud results.'**
  String get noSoundcloudResults;

  /// No description provided for @soundcloudCantCast.
  ///
  /// In en, this message translates to:
  /// **'SoundCloud songs play on this device only.'**
  String get soundcloudCantCast;

  /// No description provided for @pasteYtOrScLink.
  ///
  /// In en, this message translates to:
  /// **'Paste a YouTube or SoundCloud link.'**
  String get pasteYtOrScLink;

  /// No description provided for @soundcloudUnplayable.
  ///
  /// In en, this message translates to:
  /// **'SoundCloud doesn\'t let this track play here.'**
  String get soundcloudUnplayable;

  /// No description provided for @soundcloudImportNote.
  ///
  /// In en, this message translates to:
  /// **'SoundCloud tracks stream: play them now or save them to your library.'**
  String get soundcloudImportNote;

  /// No description provided for @soundcloudLine.
  ///
  /// In en, this message translates to:
  /// **'SoundCloud • {author} • {count, plural, =1{1 track} other{{count} tracks}}'**
  String soundcloudLine(int count, String author);

  /// No description provided for @saveCountToLibrary.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Save to library} other{Save {count} to library}}'**
  String saveCountToLibrary(int count);

  /// No description provided for @soundcloudArtists.
  ///
  /// In en, this message translates to:
  /// **'Artists on SoundCloud'**
  String get soundcloudArtists;

  /// No description provided for @soundcloudPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Playlists on SoundCloud'**
  String get soundcloudPlaylists;

  /// No description provided for @linkNotSupported.
  ///
  /// In en, this message translates to:
  /// **'There\'s no YouTube or SoundCloud link in what was shared.'**
  String get linkNotSupported;

  /// No description provided for @searchOnSource.
  ///
  /// In en, this message translates to:
  /// **'Search on {source}'**
  String searchOnSource(String source);

  /// No description provided for @searchSettings.
  ///
  /// In en, this message translates to:
  /// **'Search settings'**
  String get searchSettings;

  /// No description provided for @searchSettingsNone.
  ///
  /// In en, this message translates to:
  /// **'No settings match {query}'**
  String searchSettingsNone(String query);

  /// No description provided for @settingsPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get settingsPreview;

  /// No description provided for @settingsPreviewHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a setting that changes the look to see it here'**
  String get settingsPreviewHint;

  /// No description provided for @closePreview.
  ///
  /// In en, this message translates to:
  /// **'Close preview'**
  String get closePreview;

  /// No description provided for @homeSectionsOption.
  ///
  /// In en, this message translates to:
  /// **'Home sections'**
  String get homeSectionsOption;

  /// No description provided for @previewLyrics.
  ///
  /// In en, this message translates to:
  /// **'The line before this one\nThe line sung right now\nThe next line comes after\nAnd one more after that'**
  String get previewLyrics;

  /// No description provided for @kwAutoplay.
  ///
  /// In en, this message translates to:
  /// **'radio, continue, keep playing, similar songs, endless'**
  String get kwAutoplay;

  /// No description provided for @kwGapless.
  ///
  /// In en, this message translates to:
  /// **'seamless, no gap, live album, continuous'**
  String get kwGapless;

  /// No description provided for @kwSkipSilence.
  ///
  /// In en, this message translates to:
  /// **'silence, quiet parts, trim'**
  String get kwSkipSilence;

  /// No description provided for @kwEqualizer.
  ///
  /// In en, this message translates to:
  /// **'eq, bass, treble, tone, preset, autoeq, iem, headphone profile'**
  String get kwEqualizer;

  /// No description provided for @kwVolumeLeveling.
  ///
  /// In en, this message translates to:
  /// **'replaygain, normalize, loudness, same volume'**
  String get kwVolumeLeveling;

  /// No description provided for @kwCrossfade.
  ///
  /// In en, this message translates to:
  /// **'fade, blend, transition, mix songs'**
  String get kwCrossfade;

  /// No description provided for @kwFadeLength.
  ///
  /// In en, this message translates to:
  /// **'fade time, seconds, duration'**
  String get kwFadeLength;

  /// No description provided for @kwVirtualSpeakers.
  ///
  /// In en, this message translates to:
  /// **'spatial, surround, 3d, hrtf, headphones, dolby atmos'**
  String get kwVirtualSpeakers;

  /// No description provided for @kwCrossfeed.
  ///
  /// In en, this message translates to:
  /// **'headphones, stereo width, bs2b'**
  String get kwCrossfeed;

  /// No description provided for @kwMono.
  ///
  /// In en, this message translates to:
  /// **'one channel, single ear, accessibility'**
  String get kwMono;

  /// No description provided for @kwAudioPlugins.
  ///
  /// In en, this message translates to:
  /// **'vst, lv2, carla, effects'**
  String get kwAudioPlugins;

  /// No description provided for @kwRoomCorrection.
  ///
  /// In en, this message translates to:
  /// **'convolution, impulse response, ir, speakers'**
  String get kwRoomCorrection;

  /// No description provided for @kwSignalPath.
  ///
  /// In en, this message translates to:
  /// **'quality, bit depth, what plays, chain'**
  String get kwSignalPath;

  /// No description provided for @kwOutputDevice.
  ///
  /// In en, this message translates to:
  /// **'speaker, headphones, dac, sound card, bluetooth'**
  String get kwOutputDevice;

  /// No description provided for @kwBitPerfect.
  ///
  /// In en, this message translates to:
  /// **'hi-res, lossless, untouched, audiophile'**
  String get kwBitPerfect;

  /// No description provided for @kwDirectUsb.
  ///
  /// In en, this message translates to:
  /// **'usb dac, android, bit-perfect'**
  String get kwDirectUsb;

  /// No description provided for @kwNativeDsd.
  ///
  /// In en, this message translates to:
  /// **'dsd, dop, sacd'**
  String get kwNativeDsd;

  /// No description provided for @kwExclusiveMode.
  ///
  /// In en, this message translates to:
  /// **'wasapi, exclusive, hog mode'**
  String get kwExclusiveMode;

  /// No description provided for @kwSampleRate.
  ///
  /// In en, this message translates to:
  /// **'hz, 44.1, 48, 96, resample'**
  String get kwSampleRate;

  /// No description provided for @kwBuffer.
  ///
  /// In en, this message translates to:
  /// **'latency, stutter, crackle, dropouts'**
  String get kwBuffer;

  /// No description provided for @kwLanguage.
  ///
  /// In en, this message translates to:
  /// **'english, indonesian, japanese, translation'**
  String get kwLanguage;

  /// No description provided for @kwTheme.
  ///
  /// In en, this message translates to:
  /// **'colors, dark mode, light mode, catppuccin, nord, dracula'**
  String get kwTheme;

  /// No description provided for @kwColours.
  ///
  /// In en, this message translates to:
  /// **'color, colour, custom, palette'**
  String get kwColours;

  /// No description provided for @kwMode.
  ///
  /// In en, this message translates to:
  /// **'dark, light, system, night'**
  String get kwMode;

  /// No description provided for @kwCoverColours.
  ///
  /// In en, this message translates to:
  /// **'dynamic, artwork colours, tint'**
  String get kwCoverColours;

  /// No description provided for @kwHighContrast.
  ///
  /// In en, this message translates to:
  /// **'contrast, readability, accessibility'**
  String get kwHighContrast;

  /// No description provided for @kwTextSize.
  ///
  /// In en, this message translates to:
  /// **'font size, bigger text, zoom, scale'**
  String get kwTextSize;

  /// No description provided for @kwFont.
  ///
  /// In en, this message translates to:
  /// **'typeface, font family'**
  String get kwFont;

  /// No description provided for @kwPlayerBackground.
  ///
  /// In en, this message translates to:
  /// **'now playing, blurred cover, black, colour'**
  String get kwPlayerBackground;

  /// No description provided for @kwFrostedGlass.
  ///
  /// In en, this message translates to:
  /// **'blur, transparent, acrylic, mica'**
  String get kwFrostedGlass;

  /// No description provided for @kwOpacity.
  ///
  /// In en, this message translates to:
  /// **'transparency, see through'**
  String get kwOpacity;

  /// No description provided for @kwPresets.
  ///
  /// In en, this message translates to:
  /// **'whole look, style, liquid, kawaii'**
  String get kwPresets;

  /// No description provided for @kwCover.
  ///
  /// In en, this message translates to:
  /// **'artwork, album art, flower, square'**
  String get kwCover;

  /// No description provided for @kwPlayerHeader.
  ///
  /// In en, this message translates to:
  /// **'top bar, playing from, header'**
  String get kwPlayerHeader;

  /// No description provided for @kwTitleButtons.
  ///
  /// In en, this message translates to:
  /// **'like, share, heart, more'**
  String get kwTitleButtons;

  /// No description provided for @kwQualityBadge.
  ///
  /// In en, this message translates to:
  /// **'hi-res, flac, lossless, badge, bitrate'**
  String get kwQualityBadge;

  /// No description provided for @kwMusicVideo.
  ///
  /// In en, this message translates to:
  /// **'video, mv, clip'**
  String get kwMusicVideo;

  /// No description provided for @kwVideoDecoding.
  ///
  /// In en, this message translates to:
  /// **'hardware, gpu, cpu, decoder'**
  String get kwVideoDecoding;

  /// No description provided for @kwLiquidGlass.
  ///
  /// In en, this message translates to:
  /// **'glass, ios, frosted controls'**
  String get kwLiquidGlass;

  /// No description provided for @kwSeekBar.
  ///
  /// In en, this message translates to:
  /// **'progress, timeline, wavy, scrubber'**
  String get kwSeekBar;

  /// No description provided for @kwTimeLeft.
  ///
  /// In en, this message translates to:
  /// **'remaining, countdown, duration'**
  String get kwTimeLeft;

  /// No description provided for @kwTransport.
  ///
  /// In en, this message translates to:
  /// **'play, pause, next, previous, buttons'**
  String get kwTransport;

  /// No description provided for @kwVolumeSlider.
  ///
  /// In en, this message translates to:
  /// **'volume, loudness slider'**
  String get kwVolumeSlider;

  /// No description provided for @kwBottomButtons.
  ///
  /// In en, this message translates to:
  /// **'queue, lyrics, chips, row'**
  String get kwBottomButtons;

  /// No description provided for @kwLyrics.
  ///
  /// In en, this message translates to:
  /// **'words, lyric, karaoke'**
  String get kwLyrics;

  /// No description provided for @kwKaraoke.
  ///
  /// In en, this message translates to:
  /// **'word by word, sing along, timing'**
  String get kwKaraoke;

  /// No description provided for @kwLyricsSize.
  ///
  /// In en, this message translates to:
  /// **'lyrics font, bigger lyrics'**
  String get kwLyricsSize;

  /// No description provided for @kwLyricsAlign.
  ///
  /// In en, this message translates to:
  /// **'left, centre, center, align'**
  String get kwLyricsAlign;

  /// No description provided for @kwVisualizer.
  ///
  /// In en, this message translates to:
  /// **'spectrum, bars, wave, rings, audio reactive'**
  String get kwVisualizer;

  /// No description provided for @kwAlbumHeader.
  ///
  /// In en, this message translates to:
  /// **'album page, playlist page, header'**
  String get kwAlbumHeader;

  /// No description provided for @kwPlayingRow.
  ///
  /// In en, this message translates to:
  /// **'current song, highlight, equalizer icon'**
  String get kwPlayingRow;

  /// No description provided for @kwHomeSections.
  ///
  /// In en, this message translates to:
  /// **'home, shelves, reorder, hide'**
  String get kwHomeSections;

  /// No description provided for @kwMiniPlayer.
  ///
  /// In en, this message translates to:
  /// **'mini, small player, bottom player'**
  String get kwMiniPlayer;

  /// No description provided for @kwTabBar.
  ///
  /// In en, this message translates to:
  /// **'navigation, bottom bar, tabs, dock, glass'**
  String get kwTabBar;

  /// No description provided for @kwDesktopBar.
  ///
  /// In en, this message translates to:
  /// **'player bar, bottom bar, computer'**
  String get kwDesktopBar;

  /// No description provided for @kwCorners.
  ///
  /// In en, this message translates to:
  /// **'rounded, radius, roundness, square edges'**
  String get kwCorners;

  /// No description provided for @kwDensity.
  ///
  /// In en, this message translates to:
  /// **'spacing, compact, comfortable, padding'**
  String get kwDensity;

  /// No description provided for @kwCoverSize.
  ///
  /// In en, this message translates to:
  /// **'grid, cards, tiles, thumbnails'**
  String get kwCoverSize;

  /// No description provided for @kwMotion.
  ///
  /// In en, this message translates to:
  /// **'animation, transitions, reduce motion, speed'**
  String get kwMotion;

  /// No description provided for @kwWindowButtons.
  ///
  /// In en, this message translates to:
  /// **'title bar, close, minimize, maximize'**
  String get kwWindowButtons;

  /// No description provided for @kwPerformance.
  ///
  /// In en, this message translates to:
  /// **'battery, cpu, lightweight, balanced, heavy, speed'**
  String get kwPerformance;

  /// No description provided for @kwScreen.
  ///
  /// In en, this message translates to:
  /// **'display, awake, screen timeout'**
  String get kwScreen;

  /// No description provided for @kwSleep.
  ///
  /// In en, this message translates to:
  /// **'standby, suspend, awake'**
  String get kwSleep;

  /// No description provided for @kwTray.
  ///
  /// In en, this message translates to:
  /// **'system tray, background, close button'**
  String get kwTray;

  /// No description provided for @kwBattery.
  ///
  /// In en, this message translates to:
  /// **'background, screen off, battery optimization'**
  String get kwBattery;

  /// No description provided for @kwMusicFolders.
  ///
  /// In en, this message translates to:
  /// **'scan, watch, folders, library, rescan'**
  String get kwMusicFolders;

  /// No description provided for @kwDuplicates.
  ///
  /// In en, this message translates to:
  /// **'duplicates, same song twice, cleanup'**
  String get kwDuplicates;

  /// No description provided for @kwDownloadFormat.
  ///
  /// In en, this message translates to:
  /// **'mp3, flac, opus, m4a, video, audio'**
  String get kwDownloadFormat;

  /// No description provided for @kwDownloadQuality.
  ///
  /// In en, this message translates to:
  /// **'bitrate, kbps, bit depth, quality'**
  String get kwDownloadQuality;

  /// No description provided for @kwMobileData.
  ///
  /// In en, this message translates to:
  /// **'cellular, data, wifi only'**
  String get kwMobileData;

  /// No description provided for @kwDownloadsFolder.
  ///
  /// In en, this message translates to:
  /// **'save location, where, path'**
  String get kwDownloadsFolder;

  /// No description provided for @kwYtDlp.
  ///
  /// In en, this message translates to:
  /// **'ffmpeg, tools, executables, downloader'**
  String get kwYtDlp;

  /// No description provided for @kwHistory.
  ///
  /// In en, this message translates to:
  /// **'listening history, privacy, recently played'**
  String get kwHistory;

  /// No description provided for @kwWrap.
  ///
  /// In en, this message translates to:
  /// **'stats, wrapped, year in review, top songs'**
  String get kwWrap;

  /// No description provided for @kwBackup.
  ///
  /// In en, this message translates to:
  /// **'export, import, restore, transfer, save'**
  String get kwBackup;

  /// No description provided for @kwYoutubeAccount.
  ///
  /// In en, this message translates to:
  /// **'google, sign in, login, account'**
  String get kwYoutubeAccount;

  /// No description provided for @kwScrobbling.
  ///
  /// In en, this message translates to:
  /// **'scrobble, last.fm, listenbrainz, profile'**
  String get kwScrobbling;

  /// No description provided for @kwLyricsServices.
  ///
  /// In en, this message translates to:
  /// **'musixmatch, better lyrics, api key'**
  String get kwLyricsServices;

  /// No description provided for @kwDiscord.
  ///
  /// In en, this message translates to:
  /// **'rich presence, status, activity'**
  String get kwDiscord;

  /// No description provided for @kwUpdates.
  ///
  /// In en, this message translates to:
  /// **'new version, upgrade, update'**
  String get kwUpdates;

  /// No description provided for @kwVersion.
  ///
  /// In en, this message translates to:
  /// **'about, licence, license, open source'**
  String get kwVersion;

  /// No description provided for @discordAppButton.
  ///
  /// In en, this message translates to:
  /// **'\"Download Riflay\" button'**
  String get discordAppButton;

  /// No description provided for @topicText.
  ///
  /// In en, this message translates to:
  /// **'Language & text'**
  String get topicText;

  /// No description provided for @topicTextSummary.
  ///
  /// In en, this message translates to:
  /// **'Language, text size, font'**
  String get topicTextSummary;

  /// No description provided for @topicNowPlaying.
  ///
  /// In en, this message translates to:
  /// **'Now Playing'**
  String get topicNowPlaying;

  /// No description provided for @topicNowPlayingSummary.
  ///
  /// In en, this message translates to:
  /// **'Cover, controls, progress bar, Liquid Glass'**
  String get topicNowPlayingSummary;

  /// No description provided for @topicLyrics.
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get topicLyrics;

  /// No description provided for @topicLyricsSummary.
  ///
  /// In en, this message translates to:
  /// **'How lyrics look, and where they come from'**
  String get topicLyricsSummary;

  /// No description provided for @losslessCheck.
  ///
  /// In en, this message translates to:
  /// **'Check lossless files'**
  String get losslessCheck;

  /// No description provided for @losslessCheckSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Find FLACs made from an MP3, fake hi-res and 24-bit files padded from 16-bit'**
  String get losslessCheckSubtitle;

  /// No description provided for @losslessCheckAbout.
  ///
  /// In en, this message translates to:
  /// **'Reads each FLAC, WAV, AIFF, WavPack and APE once: its spectrum and the bits it really uses'**
  String get losslessCheckAbout;

  /// No description provided for @losslessCheckFiles.
  ///
  /// In en, this message translates to:
  /// **'{checked} of {total} lossless files checked'**
  String losslessCheckFiles(int checked, int total);

  /// No description provided for @losslessCheckRun.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get losslessCheckRun;

  /// No description provided for @losslessCheckAllGood.
  ///
  /// In en, this message translates to:
  /// **'Every checked file looks genuine'**
  String get losslessCheckAllGood;

  /// No description provided for @losslessCheckFound.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file is probably not what it claims} other{{count} files are probably not what they claim}}'**
  String losslessCheckFound(int count);

  /// No description provided for @losslessCheckLossyCut.
  ///
  /// In en, this message translates to:
  /// **'cut at {khz} kHz: made from an MP3 or AAC'**
  String losslessCheckLossyCut(String khz);

  /// No description provided for @losslessCheckUpsampled.
  ///
  /// In en, this message translates to:
  /// **'nothing above 22 kHz: upsampled from 44.1 / 48 kHz'**
  String get losslessCheckUpsampled;

  /// No description provided for @losslessCheckPadded.
  ///
  /// In en, this message translates to:
  /// **'{bits}-bit holding only 16 bits'**
  String losslessCheckPadded(int bits);

  /// No description provided for @downloadNeedsSignIn.
  ///
  /// In en, this message translates to:
  /// **'This song needs a signed-in viewer (age-restricted). Sign in to YouTube Music in Settings › Accounts & services and try again.'**
  String get downloadNeedsSignIn;

  /// No description provided for @kwLosslessCheck.
  ///
  /// In en, this message translates to:
  /// **'fake flac, upscaled, transcoded, spectrum, genuine lossless, bit depth'**
  String get kwLosslessCheck;

  /// No description provided for @dsSong.
  ///
  /// In en, this message translates to:
  /// **'Song'**
  String get dsSong;

  /// No description provided for @dsSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get dsSource;

  /// No description provided for @dsSignal.
  ///
  /// In en, this message translates to:
  /// **'Signal'**
  String get dsSignal;

  /// No description provided for @dsAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Analysis'**
  String get dsAnalysis;

  /// No description provided for @dsSound.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get dsSound;

  /// No description provided for @dsOutput.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get dsOutput;

  /// No description provided for @dsNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get dsNetwork;

  /// No description provided for @dsReading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get dsReading;

  /// No description provided for @dsTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get dsTitle;

  /// No description provided for @dsArtist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get dsArtist;

  /// No description provided for @dsAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get dsAlbum;

  /// No description provided for @dsPosition.
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get dsPosition;

  /// No description provided for @dsPlaysFrom.
  ///
  /// In en, this message translates to:
  /// **'Plays from'**
  String get dsPlaysFrom;

  /// No description provided for @dsPlaysStream.
  ///
  /// In en, this message translates to:
  /// **'YouTube Music stream'**
  String get dsPlaysStream;

  /// No description provided for @dsPlaysDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded copy'**
  String get dsPlaysDownloaded;

  /// No description provided for @dsPlaysFile.
  ///
  /// In en, this message translates to:
  /// **'File on this device'**
  String get dsPlaysFile;

  /// No description provided for @dsVideoIdItag.
  ///
  /// In en, this message translates to:
  /// **'Video ID / itag'**
  String get dsVideoIdItag;

  /// No description provided for @dsVideoId.
  ///
  /// In en, this message translates to:
  /// **'Video ID'**
  String get dsVideoId;

  /// No description provided for @dsFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get dsFile;

  /// No description provided for @dsQuality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get dsQuality;

  /// No description provided for @dsFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get dsFormat;

  /// No description provided for @dsSampleRate.
  ///
  /// In en, this message translates to:
  /// **'Sample rate'**
  String get dsSampleRate;

  /// No description provided for @dsBitDepth.
  ///
  /// In en, this message translates to:
  /// **'Bit depth'**
  String get dsBitDepth;

  /// No description provided for @dsBits.
  ///
  /// In en, this message translates to:
  /// **'{bits}-bit'**
  String dsBits(int bits);

  /// No description provided for @dsBitrate.
  ///
  /// In en, this message translates to:
  /// **'Bitrate'**
  String get dsBitrate;

  /// No description provided for @dsKbpsAvg.
  ///
  /// In en, this message translates to:
  /// **'{avg} kbps (avg)'**
  String dsKbpsAvg(int avg);

  /// No description provided for @dsKbpsNowAvg.
  ///
  /// In en, this message translates to:
  /// **'{now} kbps (avg {avg})'**
  String dsKbpsNowAvg(int now, int avg);

  /// No description provided for @dsChannels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get dsChannels;

  /// No description provided for @dsMono.
  ///
  /// In en, this message translates to:
  /// **'Mono'**
  String get dsMono;

  /// No description provided for @dsStereo.
  ///
  /// In en, this message translates to:
  /// **'Stereo'**
  String get dsStereo;

  /// No description provided for @dsChannelCount.
  ///
  /// In en, this message translates to:
  /// **'{count} channels'**
  String dsChannelCount(int count);

  /// No description provided for @dsContainer.
  ///
  /// In en, this message translates to:
  /// **'Container'**
  String get dsContainer;

  /// No description provided for @dsFileSize.
  ///
  /// In en, this message translates to:
  /// **'File size'**
  String get dsFileSize;

  /// No description provided for @dsFrequencyRange.
  ///
  /// In en, this message translates to:
  /// **'Frequency range'**
  String get dsFrequencyRange;

  /// No description provided for @dsUpToNyquist.
  ///
  /// In en, this message translates to:
  /// **'Up to {khz} (Nyquist)'**
  String dsUpToNyquist(String khz);

  /// No description provided for @dsTheoreticalRange.
  ///
  /// In en, this message translates to:
  /// **'Theoretical dynamic range'**
  String get dsTheoreticalRange;

  /// No description provided for @dsMeasuring.
  ///
  /// In en, this message translates to:
  /// **'Measuring'**
  String get dsMeasuring;

  /// No description provided for @dsReadingFile.
  ///
  /// In en, this message translates to:
  /// **'Reading the whole file…'**
  String get dsReadingFile;

  /// No description provided for @dsSpectrum.
  ///
  /// In en, this message translates to:
  /// **'Spectrum'**
  String get dsSpectrum;

  /// No description provided for @dsCutLossless.
  ///
  /// In en, this message translates to:
  /// **'Cut at {khz}: probably made from an MP3 or AAC'**
  String dsCutLossless(String khz);

  /// No description provided for @dsCutLossy.
  ///
  /// In en, this message translates to:
  /// **'Cut at {khz}, as lossy files are'**
  String dsCutLossy(String khz);

  /// No description provided for @dsUpsampled.
  ///
  /// In en, this message translates to:
  /// **'Nothing above about 22 kHz: upsampled from 44.1 / 48 kHz'**
  String get dsUpsampled;

  /// No description provided for @dsFullBand.
  ///
  /// In en, this message translates to:
  /// **'Full band, up to {khz}'**
  String dsFullBand(String khz);

  /// No description provided for @dsBitsUsed.
  ///
  /// In en, this message translates to:
  /// **'Bits used'**
  String get dsBitsUsed;

  /// No description provided for @dsBitsPadded.
  ///
  /// In en, this message translates to:
  /// **'{used} of {stored}: padded from a 16-bit file'**
  String dsBitsPadded(int used, int stored);

  /// No description provided for @dsBitsAll.
  ///
  /// In en, this message translates to:
  /// **'All {stored}'**
  String dsBitsAll(int stored);

  /// No description provided for @dsBitsOf.
  ///
  /// In en, this message translates to:
  /// **'{used} of {stored}'**
  String dsBitsOf(int used, int stored);

  /// No description provided for @dsDynamicRange.
  ///
  /// In en, this message translates to:
  /// **'Dynamic range'**
  String get dsDynamicRange;

  /// No description provided for @dsDrDynamic.
  ///
  /// In en, this message translates to:
  /// **'dynamic'**
  String get dsDrDynamic;

  /// No description provided for @dsDrModerate.
  ///
  /// In en, this message translates to:
  /// **'moderately compressed'**
  String get dsDrModerate;

  /// No description provided for @dsDrHeavy.
  ///
  /// In en, this message translates to:
  /// **'heavily compressed'**
  String get dsDrHeavy;

  /// No description provided for @dsLoudness.
  ///
  /// In en, this message translates to:
  /// **'Loudness'**
  String get dsLoudness;

  /// No description provided for @dsPeak.
  ///
  /// In en, this message translates to:
  /// **'peak {db} dBFS'**
  String dsPeak(String db);

  /// No description provided for @dsMeasuredGain.
  ///
  /// In en, this message translates to:
  /// **'Measured gain'**
  String get dsMeasuredGain;

  /// No description provided for @dsMeasuredGainValue.
  ///
  /// In en, this message translates to:
  /// **'{gain} dB (leveling uses it without ReplayGain tags)'**
  String dsMeasuredGainValue(String gain);

  /// No description provided for @dsDecoded.
  ///
  /// In en, this message translates to:
  /// **'Decoded'**
  String get dsDecoded;

  /// No description provided for @dsEffects.
  ///
  /// In en, this message translates to:
  /// **'Effects'**
  String get dsEffects;

  /// No description provided for @dsNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get dsNone;

  /// No description provided for @dsVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get dsVolume;

  /// No description provided for @dsMuted.
  ///
  /// In en, this message translates to:
  /// **'muted'**
  String get dsMuted;

  /// No description provided for @dsLeveling.
  ///
  /// In en, this message translates to:
  /// **'Leveling'**
  String get dsLeveling;

  /// No description provided for @dsOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get dsOff;

  /// No description provided for @dsOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get dsOn;

  /// No description provided for @dsNoReplayGain.
  ///
  /// In en, this message translates to:
  /// **'no ReplayGain tag'**
  String get dsNoReplayGain;

  /// No description provided for @dsLoudnessTarget.
  ///
  /// In en, this message translates to:
  /// **'{lufs} LUFS (target {target} LUFS)'**
  String dsLoudnessTarget(String lufs, String target);

  /// No description provided for @dsTempoPitch.
  ///
  /// In en, this message translates to:
  /// **'Tempo / pitch'**
  String get dsTempoPitch;

  /// No description provided for @dsTempoPitchValue.
  ///
  /// In en, this message translates to:
  /// **'{tempo}× / {pitch} semitones'**
  String dsTempoPitchValue(String tempo, String pitch);

  /// No description provided for @dsCrossfade.
  ///
  /// In en, this message translates to:
  /// **'Crossfade'**
  String get dsCrossfade;

  /// No description provided for @dsClipProtection.
  ///
  /// In en, this message translates to:
  /// **'Clip protection'**
  String get dsClipProtection;

  /// No description provided for @dsResampled.
  ///
  /// In en, this message translates to:
  /// **'Resampled'**
  String get dsResampled;

  /// No description provided for @dsDevice.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get dsDevice;

  /// No description provided for @dsBluetooth.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get dsBluetooth;

  /// No description provided for @dsBtAllow.
  ///
  /// In en, this message translates to:
  /// **'codec: allow Nearby devices'**
  String get dsBtAllow;

  /// No description provided for @dsBtUnknown.
  ///
  /// In en, this message translates to:
  /// **'codec unknown'**
  String get dsBtUnknown;

  /// No description provided for @dsDacReceives.
  ///
  /// In en, this message translates to:
  /// **'DAC receives'**
  String get dsDacReceives;

  /// No description provided for @dsDirectUsb.
  ///
  /// In en, this message translates to:
  /// **'Direct USB'**
  String get dsDirectUsb;

  /// No description provided for @dsBitPerfect.
  ///
  /// In en, this message translates to:
  /// **'Bit-perfect'**
  String get dsBitPerfect;

  /// No description provided for @dsYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get dsYes;

  /// No description provided for @dsNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get dsNo;

  /// No description provided for @dsConnectionSpeed.
  ///
  /// In en, this message translates to:
  /// **'Connection speed'**
  String get dsConnectionSpeed;

  /// No description provided for @dsReadingNow.
  ///
  /// In en, this message translates to:
  /// **'Reading now'**
  String get dsReadingNow;

  /// No description provided for @dsReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get dsReceived;

  /// No description provided for @dsReceivedOf.
  ///
  /// In en, this message translates to:
  /// **'{received} of {total}'**
  String dsReceivedOf(String received, String total);

  /// No description provided for @dsBufferHealth.
  ///
  /// In en, this message translates to:
  /// **'Buffer health'**
  String get dsBufferHealth;

  /// No description provided for @dsStreamUrlFrom.
  ///
  /// In en, this message translates to:
  /// **'Stream URL from'**
  String get dsStreamUrlFrom;

  /// No description provided for @dsSpectrogram.
  ///
  /// In en, this message translates to:
  /// **'Spectrogram'**
  String get dsSpectrogram;

  /// No description provided for @surroundUpmix.
  ///
  /// In en, this message translates to:
  /// **'Surround upmix'**
  String get surroundUpmix;

  /// No description provided for @surroundUpmixSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Stereo songs fill a 7.1 room around you: the voice stays in front, the space moves to the sides and back. 5.1 / 7.1 songs, Dolby Atmos too, always get each channel in its place.'**
  String get surroundUpmixSubtitle;

  /// No description provided for @passthrough.
  ///
  /// In en, this message translates to:
  /// **'Dolby / DTS passthrough'**
  String get passthrough;

  /// No description provided for @passthroughSubtitle.
  ///
  /// In en, this message translates to:
  /// **'For an AV receiver or soundbar over HDMI or optical: Dolby Digital, Dolby Atmos (E-AC-3, TrueHD) and DTS go out undecoded and the receiver plays them, Atmos heights included. Effects and the volume don\'t apply to those songs.'**
  String get passthroughSubtitle;

  /// No description provided for @kwSurroundUpmix.
  ///
  /// In en, this message translates to:
  /// **'dolby atmos, spatial audio, surround, 7.1, 3d, upmix'**
  String get kwSurroundUpmix;

  /// No description provided for @kwPassthrough.
  ///
  /// In en, this message translates to:
  /// **'dolby atmos, hdmi, spdif, optical, receiver, soundbar, bitstream, dts, truehd'**
  String get kwPassthrough;

  /// No description provided for @fxUpmix.
  ///
  /// In en, this message translates to:
  /// **'Surround upmix'**
  String get fxUpmix;

  /// No description provided for @dsAtmosBed.
  ///
  /// In en, this message translates to:
  /// **'{channels}-channel bed decoded; the height objects need a receiver (passthrough)'**
  String dsAtmosBed(int channels);

  /// No description provided for @dsPassthrough.
  ///
  /// In en, this message translates to:
  /// **'Passthrough'**
  String get dsPassthrough;

  /// No description provided for @dsPassthroughValue.
  ///
  /// In en, this message translates to:
  /// **'{codec} to the receiver, undecoded'**
  String dsPassthroughValue(String codec);

  /// No description provided for @dsVirtualRoom.
  ///
  /// In en, this message translates to:
  /// **'Virtual speakers'**
  String get dsVirtualRoom;

  /// No description provided for @dsRoomStereo.
  ///
  /// In en, this message translates to:
  /// **'2 speakers (stereo)'**
  String get dsRoomStereo;

  /// No description provided for @dsRoomSurround.
  ///
  /// In en, this message translates to:
  /// **'7.1 room, each channel in its place'**
  String get dsRoomSurround;

  /// No description provided for @dsRoomUpmix.
  ///
  /// In en, this message translates to:
  /// **'7.1 room, upmixed from stereo'**
  String get dsRoomUpmix;

  /// No description provided for @autoEq.
  ///
  /// In en, this message translates to:
  /// **'Headphone / IEM profile (AutoEQ)'**
  String get autoEq;

  /// No description provided for @autoEqSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sets the equalizer for your model from its measurement, so it sounds neutral (the Harman target).'**
  String get autoEqSubtitle;

  /// No description provided for @autoEqPick.
  ///
  /// In en, this message translates to:
  /// **'Pick your headphones or IEM'**
  String get autoEqPick;

  /// No description provided for @autoEqSearch.
  ///
  /// In en, this message translates to:
  /// **'Search a model, e.g. KZ ZSN Pro'**
  String get autoEqSearch;

  /// No description provided for @autoEqLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading the list of models…'**
  String get autoEqLoading;

  /// No description provided for @autoEqModels.
  ///
  /// In en, this message translates to:
  /// **'{count} models, measured by crinacle, oratory1990 and others. Type a name to search.'**
  String autoEqModels(int count);

  /// No description provided for @autoEqNoResults.
  ///
  /// In en, this message translates to:
  /// **'No model by that name.'**
  String get autoEqNoResults;

  /// No description provided for @autoEqFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load AutoEQ: {error}'**
  String autoEqFailed(String error);

  /// No description provided for @autoEqApplied.
  ///
  /// In en, this message translates to:
  /// **'Equalizer set for {name}'**
  String autoEqApplied(String name);

  /// No description provided for @autoEqAppliedFitted.
  ///
  /// In en, this message translates to:
  /// **'Equalizer set for {name} (within ±{db} dB of its profile)'**
  String autoEqAppliedFitted(String name, String db);

  /// No description provided for @clearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear cache'**
  String get clearCache;

  /// No description provided for @clearCacheSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{size} of covers, lyrics found online and other things Riflay fetches again. Your music stays.'**
  String clearCacheSubtitle(String size);

  /// No description provided for @clearCacheCounting.
  ///
  /// In en, this message translates to:
  /// **'Counting…'**
  String get clearCacheCounting;

  /// No description provided for @clearCacheConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear {size} of cache?'**
  String clearCacheConfirm(String size);

  /// No description provided for @clearCacheConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Covers and lyrics are downloaded again when they are needed. Your library, downloads, playlists, settings, your own lyrics and the loudness measurements stay.'**
  String get clearCacheConfirmBody;

  /// No description provided for @clearCacheAction.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearCacheAction;

  /// No description provided for @clearCacheDone.
  ///
  /// In en, this message translates to:
  /// **'Freed {size}'**
  String clearCacheDone(String size);

  /// No description provided for @kwClearCache.
  ///
  /// In en, this message translates to:
  /// **'cache, storage, space, free up, clean, temporary files'**
  String get kwClearCache;

  /// No description provided for @dsDeviceRate.
  ///
  /// In en, this message translates to:
  /// **'Device sample rate'**
  String get dsDeviceRate;

  /// No description provided for @dsDeviceFormat.
  ///
  /// In en, this message translates to:
  /// **'Device format'**
  String get dsDeviceFormat;

  /// No description provided for @dsMixerBuffer.
  ///
  /// In en, this message translates to:
  /// **'Mixer buffer'**
  String get dsMixerBuffer;

  /// No description provided for @dsMixerBufferValue.
  ///
  /// In en, this message translates to:
  /// **'{ms} ms · {frames} frames'**
  String dsMixerBufferValue(String ms, int frames);

  /// No description provided for @dsLowLatency.
  ///
  /// In en, this message translates to:
  /// **'Low-latency audio'**
  String get dsLowLatency;

  /// No description provided for @dsProAudio.
  ///
  /// In en, this message translates to:
  /// **'Pro audio'**
  String get dsProAudio;

  /// No description provided for @dsSpatialAudio.
  ///
  /// In en, this message translates to:
  /// **'Spatial audio'**
  String get dsSpatialAudio;

  /// No description provided for @dsSystemVolume.
  ///
  /// In en, this message translates to:
  /// **'System volume'**
  String get dsSystemVolume;

  /// No description provided for @dsSupported.
  ///
  /// In en, this message translates to:
  /// **'Supported'**
  String get dsSupported;

  /// No description provided for @dsNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Not supported'**
  String get dsNotSupported;

  /// No description provided for @fromInternetArchive.
  ///
  /// In en, this message translates to:
  /// **'FLAC from the Internet Archive'**
  String get fromInternetArchive;

  /// No description provided for @radioParadiseFlac.
  ///
  /// In en, this message translates to:
  /// **'Radio Paradise in FLAC'**
  String get radioParadiseFlac;

  /// No description provided for @onAir.
  ///
  /// In en, this message translates to:
  /// **'On air: {song}'**
  String onAir(String song);

  /// No description provided for @archiveCouldntLoad.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load from the Internet Archive: {error}'**
  String archiveCouldntLoad(String error);

  /// No description provided for @archiveNoFlac.
  ///
  /// In en, this message translates to:
  /// **'This recording has no FLAC files that can be played here.'**
  String get archiveNoFlac;

  /// No description provided for @topicSources.
  ///
  /// In en, this message translates to:
  /// **'Music sources'**
  String get topicSources;

  /// No description provided for @topicSourcesSummary.
  ///
  /// In en, this message translates to:
  /// **'Internet Archive and Radio Paradise: free music in FLAC'**
  String get topicSourcesSummary;

  /// No description provided for @sourcesAbout.
  ///
  /// In en, this message translates to:
  /// **'Free places with lossless sound, shared with the artists\' or rights holders\' leave. Riflay plays from their own servers.'**
  String get sourcesAbout;

  /// No description provided for @sourceArchive.
  ///
  /// In en, this message translates to:
  /// **'Internet Archive in search'**
  String get sourceArchive;

  /// No description provided for @sourceArchiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Live Music Archive concerts and netlabel releases in FLAC, on search\'s All'**
  String get sourceArchiveSubtitle;

  /// No description provided for @sourceRadioParadise.
  ///
  /// In en, this message translates to:
  /// **'Radio Paradise on the search page'**
  String get sourceRadioParadise;

  /// No description provided for @sourceRadioParadiseSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Listener-supported, commercial-free radio, every channel in FLAC (CD quality)'**
  String get sourceRadioParadiseSubtitle;

  /// No description provided for @kwSources.
  ///
  /// In en, this message translates to:
  /// **'flac, lossless, internet archive, live music archive, radio paradise, free music, sources'**
  String get kwSources;

  /// No description provided for @spotifyCanvas.
  ///
  /// In en, this message translates to:
  /// **'Canvas'**
  String get spotifyCanvas;

  /// No description provided for @spotifyCanvasSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The looping video Spotify shows with a song, in Video mode instead of its music video (turn Video mode on in Beta features)'**
  String get spotifyCanvasSubtitle;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'id', 'ja'].contains(locale.languageCode);

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
    case 'ja':
      return AppLocalizationsJa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
