// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get language => '言語';

  @override
  String get languageSubtitle => 'Riflay の画面の言語';

  @override
  String get languageSystem => '端末の言語';

  @override
  String get navHome => 'ホーム';

  @override
  String get navLibrary => 'ライブラリ';

  @override
  String get navSearch => '検索';

  @override
  String get navDownloads => 'ダウンロード';

  @override
  String get navSettings => '設定';

  @override
  String get yourLibrary => 'ライブラリ';

  @override
  String get more => 'その他';

  @override
  String get groupSound => 'サウンド';

  @override
  String get groupSoundSummary => '再生、音響効果（DSP）、出力と音質';

  @override
  String get groupLook => '見た目と操作感';

  @override
  String get groupLookSummary => 'テーマ、色、文字の大きさ、画面に出すもの';

  @override
  String get groupLibrary => 'ライブラリとダウンロード';

  @override
  String get groupLibrarySummary => '音楽フォルダ、ダウンロード、再生履歴、バックアップ';

  @override
  String get groupAccounts => 'アカウントとサービス';

  @override
  String get groupAccountsSummary => 'YouTube Music、Spotify、Last.fm、Discord、歌詞、拡張機能';

  @override
  String get topicPlayback => '再生';

  @override
  String get topicPlaybackSummary => '自動再生とギャップレス再生';

  @override
  String get topicDsp => '音響効果（DSP）';

  @override
  String get topicDspSummary => 'イコライザー、音量の均一化、クロスフェード、空間オーディオ、ルーム補正';

  @override
  String get topicOutput => '出力と音質';

  @override
  String get topicOutputSummary => '出力デバイス、Bit-perfect モード、サンプルレート';

  @override
  String get topicAppearance => '外観';

  @override
  String get topicAppearanceSummary => 'テーマ、アクセントカラー、背景、文字の大きさ、フォント';

  @override
  String get topicLayout => 'レイアウト';

  @override
  String get topicLayoutSummary => '形、サイズ、プレイヤーに出すもの';

  @override
  String get topicLibrary => 'ライブラリ';

  @override
  String get topicLibrarySummary => '音楽フォルダを最新に保つ、重複した曲を探す';

  @override
  String get topicDownloads => 'ダウンロード';

  @override
  String get topicDownloadsSummary => '形式、音質、曲の保存先';

  @override
  String get topicHistory => '再生履歴と Wrap';

  @override
  String get topicHistorySummary => '統計のもとになる履歴。この端末だけに保存';

  @override
  String get topicBackup => 'バックアップと復元';

  @override
  String get topicBackupSummary => '設定、プレイリスト、履歴をまとめてひとつのファイルに';

  @override
  String get topicAccount => 'YouTube Music アカウント';

  @override
  String get topicAccountSummary => 'Google でログイン';

  @override
  String get topicSpotify => 'Spotify';

  @override
  String get topicSpotifySummary => 'プレイリスト、お気に入りの曲、アルバムを持ってくる';

  @override
  String get topicScrobbling => 'Last.fm と ListenBrainz';

  @override
  String get topicScrobblingSummary => '聴いた曲をそっちのプロフィールに記録する';

  @override
  String get topicIntegrations => 'Discord と歌詞サービス';

  @override
  String get topicIntegrationsSummary => '聴いてる曲を Discord に表示、歌詞サービス';

  @override
  String get topicExtensions => '拡張機能';

  @override
  String get topicExtensionsSummary => 'SpotiFLAC の拡張リポジトリ：検索先を増やせる';

  @override
  String get topicLyricsServices => '歌詞サービス';

  @override
  String get topicPlaybackSummaryWeb => '自動再生';

  @override
  String get topicIntegrationsSummaryWeb => '単語ごとの歌詞に使う Better Lyrics のキー';

  @override
  String get settingsPower => '電源とバックグラウンド';

  @override
  String get listenTogether => '一緒に聴く';

  @override
  String get keyboardShortcuts => 'キーボードショートカット';

  @override
  String get about => 'Riflay について';

  @override
  String get sectionPlayer => 'プレイヤー';

  @override
  String get queue => 'キュー';

  @override
  String get lyrics => '歌詞';

  @override
  String get closePlayer => 'プレイヤーを閉じる';

  @override
  String get sectionSong => '曲';

  @override
  String get share => '共有';

  @override
  String get addToPlaylist => 'プレイリストに追加';

  @override
  String get downloaded => 'ダウンロード済み';

  @override
  String get stopDownload => 'ダウンロードを止める';

  @override
  String get download => 'ダウンロード';

  @override
  String get playsOffline => 'オフラインで聴ける';

  @override
  String get downloading => 'ダウンロード中…';

  @override
  String get sectionListen => '聴く';

  @override
  String get sleepTimer => 'スリープタイマー';

  @override
  String get playOnDevice => 'ほかのデバイスで再生';

  @override
  String playingOn(Object device) {
    return '$device で再生中';
  }

  @override
  String get sectionSound => 'サウンド';

  @override
  String get equalizer => 'イコライザー';

  @override
  String get signalPath => '信号経路';

  @override
  String get detailStats => '詳細な統計';

  @override
  String get playNext => '次に再生';

  @override
  String get addToQueue => 'キューに追加';

  @override
  String get goToArtist => 'アーティストへ';

  @override
  String get goToAlbum => 'アルバムへ';

  @override
  String get removeFromThisPlaylist => 'このプレイリストから外す';

  @override
  String get addToLiked => 'お気に入りに追加';

  @override
  String get removeFromLiked => 'お気に入りから外す';

  @override
  String get startRadio => 'ラジオを開始';

  @override
  String get downloadForOffline => 'オフライン用にダウンロード';

  @override
  String get downloadAs => '形式を選んでダウンロード…';

  @override
  String get saveToDevice => '端末に保存';

  @override
  String savingToDevice(Object title) {
    return '$title をブラウザでダウンロード中';
  }

  @override
  String get edit => '編集';

  @override
  String get editInfo => '情報を編集';

  @override
  String get removeFromLibrary => 'ライブラリから外す';

  @override
  String get deleteDownload => 'ダウンロードを削除';

  @override
  String get deleteDownloadQuestion => 'このダウンロードを削除しますか？';

  @override
  String deleteDownloadBody(String title) {
    return '$title がライブラリから外れて、ファイルもこの端末から削除されます。';
  }

  @override
  String get delete => '削除';

  @override
  String get downloadDeleted => 'ダウンロードを削除しました';

  @override
  String get convertToFlac => 'FLAC に変換';

  @override
  String get toastPlaysNext => '次に再生する';

  @override
  String get toastAddedToQueue => 'キューに追加した';

  @override
  String get toastRequestedNext => '次の曲をリクエストした';

  @override
  String get play => '再生';

  @override
  String get pause => '一時停止';

  @override
  String get previous => '前へ';

  @override
  String get next => '次へ';

  @override
  String get enableShuffle => 'シャッフルをオン';

  @override
  String get disableShuffle => 'シャッフルをオフ';

  @override
  String get enableRepeat => 'リピートをオン';

  @override
  String get enableRepeatOne => '1曲リピートをオン';

  @override
  String get disableRepeat => 'リピートをオフ';

  @override
  String get mute => 'ミュート';

  @override
  String get unmute => 'ミュート解除';

  @override
  String get sleepTimerFades => '音がだんだん小さくなって止まる';

  @override
  String get afterAWhile => '時間で止める';

  @override
  String get afterSongs => '曲数で止める';

  @override
  String minutesCount(int count) {
    return '$count分';
  }

  @override
  String songsCount(int count) {
    return '$count曲';
  }

  @override
  String get endOfThisSong => 'この曲が終わったら';

  @override
  String get customTime => '時間を指定';

  @override
  String get add10Minutes => '10分延長';

  @override
  String get cancelTimer => 'タイマーを取り消す';

  @override
  String stopsIn(Object time) {
    return 'あと $time で止まる';
  }

  @override
  String get stopsWhenSongEnds => 'この曲が終わったら止まる';

  @override
  String get stopsAfterOneMore => 'この曲とあと1曲で止まる';

  @override
  String stopsAfterMore(int count) {
    return 'この曲とあと$count曲で止まる';
  }

  @override
  String get settingsPowerSummaryTray => '画面のタイムアウト、スリープ、バックグラウンド再生、トレイに閉じる';

  @override
  String get settingsPowerSummary => '画面のタイムアウト、スリープ、バックグラウンド再生';

  @override
  String get listenTogetherSummary => 'セッションを開くか友だちに参加して、共有の権限を管理';

  @override
  String get keyboardShortcutsSummary => '再生、スキップ、検索などをマウスなしで';

  @override
  String get aboutSummary => 'バージョン、新機能、問題の報告、ライセンス';

  @override
  String addToHostQueue(Object host) {
    return '$host のキューに追加';
  }

  @override
  String get theHost => 'ホスト';

  @override
  String goToNamedArtist(Object artist) {
    return '$artist へ';
  }

  @override
  String get aboutTheArtist => 'アーティストについて';

  @override
  String get follow => 'フォロー';

  @override
  String get following => 'フォロー中';

  @override
  String get showMore => 'もっと見る';

  @override
  String get showLess => '閉じる';

  @override
  String get tempoPitch => 'テンポとピッチ';

  @override
  String get tempo => 'テンポ';

  @override
  String get pitch => 'ピッチ';

  @override
  String semitones(int count) {
    return '$count 半音';
  }

  @override
  String get reset => 'リセット';

  @override
  String get asRecorded => '原曲のまま';

  @override
  String get tempoPitchOff => 'Bit-perfect モード中と一緒に聴いてる間は使えない';

  @override
  String get greetingNight => 'おやすみ';

  @override
  String get greetingMorning => 'おはよう';

  @override
  String get greetingAfternoon => 'こんにちは';

  @override
  String get greetingEvening => 'こんばんは';

  @override
  String get allSongs => 'すべての曲';

  @override
  String get likedMusic => 'お気に入り';

  @override
  String get recentlyPlayed => '最近聴いた曲';

  @override
  String get yourPlaylists => 'プレイリスト';

  @override
  String get yourAlbums => 'アルバム';

  @override
  String get yourArtists => 'アーティスト';

  @override
  String get artists => 'アーティスト';

  @override
  String get artist => 'アーティスト';

  @override
  String get albums => 'アルバム';

  @override
  String get album => 'アルバム';

  @override
  String get playlists => 'プレイリスト';

  @override
  String get playlist => 'プレイリスト';

  @override
  String get smartPlaylist => 'スマートプレイリスト';

  @override
  String get recentlyAdded => '最近追加した曲';

  @override
  String get refresh => '更新';

  @override
  String get addMusicOffline => 'この端末の音楽を追加すれば、オフラインで聴ける。';

  @override
  String get addSongs => '曲を追加';

  @override
  String get addFolder => 'フォルダを追加';

  @override
  String get addMusic => '音楽を追加';

  @override
  String get addFiles => 'ファイルを追加';

  @override
  String get add => '追加';

  @override
  String get importFromYouTube => 'YouTube から取り込む';

  @override
  String get fromYouTube => 'YouTube から';

  @override
  String get noMusicYet => 'まだ音楽がない';

  @override
  String get noMusicYetBody => 'この端末から音声ファイルを追加しよう。アルバム、アーティスト、ジャケットはファイルのタグから読み込む。';

  @override
  String get newPlaylist => '新しいプレイリスト';

  @override
  String get newPlaylistSubtitle => '手持ちの曲と YouTube Music を混ぜて作れる';

  @override
  String get yourListeningStats => 'リスニング統計';

  @override
  String get yourListeningStatsSubtitle => 'よく聴く曲、アーティスト、アルバム';

  @override
  String get yourYouTubeMusic => 'YouTube Music';

  @override
  String get yourYouTubeMusicBody => 'ログインすると、お気に入りの曲やプレイリストがここに出る。';

  @override
  String get signInWithGoogle => 'Google でログイン';

  @override
  String get musicOnDevice => 'この端末の音楽';

  @override
  String get musicOnDeviceBody => '音声ファイルを追加してオフラインで聴こう。';

  @override
  String get joinSharedPlaylist => '共有プレイリストに参加';

  @override
  String get importPlaylist => 'プレイリストを取り込む';

  @override
  String get spotifyLibrary => 'Spotify のライブラリ';

  @override
  String get libraryEmpty => '曲かプレイリストを追加して、ライブラリを始めよう。';

  @override
  String get all => 'すべて';

  @override
  String get songs => '曲';

  @override
  String get videos => '動画';

  @override
  String get searchIntro => '自分の音楽と YouTube Music 全体をまとめて検索。クラウドマークの曲はオンラインでストリーミング、それ以外はオフラインで再生。';

  @override
  String get browseArtists => 'アーティストを見る';

  @override
  String get inYourLibrary => 'ライブラリ内';

  @override
  String get searchHint => '何を聴く？';

  @override
  String get clear => 'クリア';

  @override
  String get recentSearches => '最近の検索';

  @override
  String get remove => '削除';

  @override
  String get clearFinished => '完了したものを消す';

  @override
  String get nothingDownloading => 'ダウンロード中のものはない。YouTube の動画かプレイリストのリンクを貼れば、その音声がライブラリに入る。';

  @override
  String downloadsUse(Object size) {
    return 'ダウンロード：$size 使用中';
  }

  @override
  String get missingFiles => '見つからないファイル';

  @override
  String get downloadAllAgain => 'すべて再ダウンロード';

  @override
  String get removeAllFromLibrary => 'すべてライブラリから外す';

  @override
  String get missingFilesBody => 'ライブラリにはあるけど、ファイルがもうこの端末にない曲。';

  @override
  String get downloadAgain => '再ダウンロード';

  @override
  String get waiting => '待機中…';

  @override
  String get preparing => '準備中…';

  @override
  String bytesOf(Object received, Object total) {
    return '$received / $total';
  }

  @override
  String get addedToLibrary => 'ライブラリに追加済み';

  @override
  String get failed => '失敗';

  @override
  String get cancelled => 'キャンセル済み';

  @override
  String get cancel => 'キャンセル';

  @override
  String get retry => '再試行';

  @override
  String downloadingCount(int count) {
    return '$count件ダウンロード中';
  }

  @override
  String get saveAsPlaylist => 'プレイリストとして保存';

  @override
  String get queueEmpty => 'まだ何も再生してない。アルバム、アーティスト、曲を選んでキューを埋めよう。';

  @override
  String get nowPlaying => '再生中';

  @override
  String get nowPlayingTitle => '再生中';

  @override
  String get nextUp => '次の曲';

  @override
  String nextFrom(Object source) {
    return '次は $source から';
  }

  @override
  String get autoplay => '自動再生';

  @override
  String get autoplaySubtitle => 'キューが終わったら、YouTube Music から似た曲を流し続ける';

  @override
  String get autoplaySimilar => '自動再生：今聴いてる曲に似た曲';

  @override
  String get removeFromQueue => 'キューから外す';

  @override
  String get dragToMove => 'ドラッグで移動';

  @override
  String get shufflePlay => 'シャッフル再生';

  @override
  String get addAllToPlaylist => 'すべてプレイリストに追加';

  @override
  String get select => '選択';

  @override
  String get unselect => '選択を解除';

  @override
  String get selectAll => 'すべて選択';

  @override
  String get cancelSelection => '選択をやめる';

  @override
  String selectedCount(int count) {
    return '$count件選択中';
  }

  @override
  String playlistOnRiflay(int count) {
    return 'Riflay • $count曲';
  }

  @override
  String playlistOnYoutubeMusic(int count) {
    return 'YouTube Music • $count曲';
  }

  @override
  String addedTo(String name) {
    return '$name に追加した';
  }

  @override
  String addedSongsTo(int count, String name) {
    return '$name に$count曲追加した';
  }

  @override
  String alreadyIn(String name) {
    return 'もう $name に入ってる';
  }

  @override
  String get notOnYoutubeMusic => 'この曲は YouTube Music にない';

  @override
  String get noneOnYoutubeMusic => 'どの曲も YouTube Music にない';

  @override
  String skippedNotOnYoutubeMusic(int count) {
    return '$count曲は YouTube Music になかったのでスキップ';
  }

  @override
  String get addAllToQueue => 'すべてキューに追加';

  @override
  String get downloadAllOffline => 'すべてオフライン用にダウンロード';

  @override
  String get alreadyDownloaded => 'ダウンロード済み';

  @override
  String downloadingSongs(int count) {
    return '$count曲をダウンロード中…';
  }

  @override
  String disc(Object number) {
    return 'ディスク $number';
  }

  @override
  String removedFrom(Object playlist) {
    return '$playlist から外した';
  }

  @override
  String get undo => '元に戻す';

  @override
  String get title => 'タイトル';

  @override
  String get editPlaylist => 'プレイリストを編集';

  @override
  String get rename => '名前を変更';

  @override
  String get convertAllToFlac => 'すべて FLAC に変換';

  @override
  String get deletePlaylistQuestion => 'プレイリストを削除しますか？';

  @override
  String get deletePlaylist => 'プレイリストを削除';

  @override
  String get close => '閉じる';

  @override
  String get playingFromCaps => '再生元';

  @override
  String get yourLibrarySource => 'ライブラリ';

  @override
  String get yourLibraryInline => 'ライブラリ';

  @override
  String playingFrom(Object source) {
    return '$source から再生中';
  }

  @override
  String get nothingPlaying => '再生してない';

  @override
  String get quieter => '小さく';

  @override
  String get louder => '大きく';

  @override
  String get linkCopied => 'リンクをコピーした';

  @override
  String get songNameCopied => '曲名をコピーした';

  @override
  String sleepTimerWith(Object time) {
    return 'スリープタイマー：$time';
  }

  @override
  String get volume => '音量';

  @override
  String get speaker => 'スピーカー';

  @override
  String get expandedPlayer => '大きいプレイヤー';

  @override
  String get closeExpandedPlayer => '大きいプレイヤーを閉じる';

  @override
  String get hideLyrics => '歌詞を隠す';

  @override
  String get nowPlayingView => '再生中の画面';

  @override
  String get hideNowPlayingView => '再生中の画面を隠す';

  @override
  String get moreOptions => 'その他のオプション';

  @override
  String get miniPlayer => 'ミニプレイヤー';

  @override
  String get fullScreen => '全画面';

  @override
  String get exitFullScreen => '全画面を終了';

  @override
  String get sidePanelEmpty => '何か再生すると、ここに出てくる。';

  @override
  String get nextInQueue => 'キューの次の曲';

  @override
  String get openQueue => 'キューを開く';

  @override
  String get nothingAfterThisSong => 'この曲のあとは何もない';

  @override
  String get lyricsLoadFailed => '歌詞を読み込めませんでした。ネット接続を確認してください。';

  @override
  String get tryAgain => 'もう一度';

  @override
  String get lyricsInstrumental => 'インストゥルメンタルの曲だよ。音楽を楽しんで。';

  @override
  String get noLyricsFound => 'この曲の歌詞は見つからなかった。';

  @override
  String get useMyLyricsFile => '自分の歌詞ファイルを使う';

  @override
  String get loadingLyrics => '歌詞を読み込み中';

  @override
  String lyricsFrom(Object source) {
    return '歌詞：$source';
  }

  @override
  String get lyricsUntimed => 'この歌詞は曲に合わせて動かない。';

  @override
  String get back => '戻る';

  @override
  String get playToSeeLyrics => '曲を再生すると、ここに歌詞が出る。';

  @override
  String get directUsbFailed => 'Direct USB が動かなかったので、Android 経由で再生してます。もう一度試すならオンにしてください。';

  @override
  String get directUsbClosedWhileStarting => '起動中に Riflay が閉じたので、Direct USB をオフにしました。もう一度試すならオンにしてください。';

  @override
  String get directUsbBeta => 'Direct USB（ベータ）';

  @override
  String get directUsbBetaSubtitle => '下に Direct USB が出る。Android を通さず、Riflay が USB DAC に直接出力する。試験的な機能。';

  @override
  String get directUsbWarningTitle => 'Direct USB をオンにしますか？';

  @override
  String get directUsbWarningBody =>
      'Direct USB は試験的な機能です。Riflay が固まったり閉じたりすることがあり、すべてのスマホや DAC で動くとは限りません。DAC に最大音量で音が届くことがあるので、再生する前に DAC の音量を下げて、イヤホンを外してください。オフにすれば通常の出力に戻ります。';

  @override
  String get directUsbWarningConfirm => 'オンにする';

  @override
  String get linkNotYoutube => '共有されたものに YouTube のリンクがない。';

  @override
  String get linkOpening => 'リンクを開いてる…';

  @override
  String get linkFailed => 'そのリンクを開けませんでした。非公開か、削除されたか、地域制限があるのかもしれません。';

  @override
  String get streakTitle => 'リスニングストリーク';

  @override
  String streakDays(int count) {
    return '$count日連続';
  }

  @override
  String streakTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'リスニングストリーク：$count日');
    return '$_temp0';
  }

  @override
  String get streakSafe => '今日はもう聴いた。また明日！';

  @override
  String get streakKeepGoing => '今日1曲聴いてストリークをつなごう';

  @override
  String get streakStart => '1曲聴いてストリークを始めよう';

  @override
  String streakLongest(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '最長：$count日');
    return '$_temp0';
  }

  @override
  String streakToNext(int count, Object flame) {
    return '$flameまであと$count日';
  }

  @override
  String get streakTop => 'これが最高の炎';

  @override
  String get flameRed => '赤い炎';

  @override
  String get flameGold => '金の炎';

  @override
  String get flameBlue => '青い炎';

  @override
  String get flamePurple => '紫の炎';

  @override
  String get flameRainbow => '虹の炎';

  @override
  String get streakRule => '曲を30秒以上聴いたら、その日はカウントされる。履歴はこの端末だけに残る。';
}
