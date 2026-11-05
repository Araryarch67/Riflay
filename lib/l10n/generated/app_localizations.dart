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
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('id'),
  ];

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

  /// No description provided for @hideDetailStats.
  ///
  /// In en, this message translates to:
  /// **'Hide detail stats'**
  String get hideDetailStats;

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
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'id'].contains(locale.languageCode);

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
