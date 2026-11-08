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

  @override
  String songsLeft(int count) {
    return 'あと$count曲';
  }

  @override
  String get songEndShort => '曲の終わり';

  @override
  String get endOfSong => '曲の終わりまで';

  @override
  String get hours => '時間';

  @override
  String get minutes => '分';

  @override
  String get start => '開始';

  @override
  String get thisPhone => 'このスマホ';

  @override
  String get thisComputer => 'このパソコン';

  @override
  String get playOn => '再生先';

  @override
  String get lookingForDevices => 'テレビやスピーカーを探してる…';

  @override
  String get noDevicesFound => 'テレビもスピーカーも見つからない。電源が入っていて、同じ Wi-Fi につながってるか確認してね。';

  @override
  String get castWorksWith => 'DLNA か AirPlay に対応したテレビ、スピーカー、レシーバーで使える。';

  @override
  String get searchAgain => 'もう一度探す';

  @override
  String get discordSongCover => 'ジャケット';

  @override
  String get discordTime => '経過時間と残り時間';

  @override
  String get discordSongInList => 'メンバーリストに曲名を出す';

  @override
  String get discordListenButton => '「Listen on YouTube Music」ボタン';

  @override
  String get discordWhilePaused => '一時停止中も表示する';

  @override
  String get discordShowQuality => '音質も表示する（FLAC 24/96、Opus 160 kbps）';

  @override
  String get shareLyrics => '歌詞をシェア';

  @override
  String lyricCardPick(int count) {
    return 'カードに載せる行を $count 行まで選んでね';
  }

  @override
  String lyricCardCaption(String lines, String title, String artist) {
    return '「$lines」— $artist「$title」、Riflay で';
  }

  @override
  String videoQualityLower(String height) {
    return '回線に合わせて画質を下げたよ（$height）';
  }

  @override
  String videoQualityHigher(String height) {
    return '回線が安定したので $height に戻したよ';
  }

  @override
  String get showBluetoothCodec => 'Bluetooth のコーデックを表示';

  @override
  String get previewYourSong => '曲名';

  @override
  String get previewItsArtist => 'アーティスト名';

  @override
  String get discordListeningTo => '再生中：';

  @override
  String get paused => '一時停止中';

  @override
  String get playerPresets => 'プレイヤーのプリセット';

  @override
  String get presetsCustomMix => '今の設定はカスタム';

  @override
  String presetsMatch(String preset) {
    return '今の設定は「$preset」と同じ';
  }

  @override
  String applyPresetQuestion(String preset) {
    return '「$preset」を適用しますか？';
  }

  @override
  String applyPresetBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'プレイヤーの設定が$count個変わります。あとから個別に変えられます。');
    return '$_temp0';
  }

  @override
  String get apply => '適用';

  @override
  String get inUse => '使用中';

  @override
  String get tapToApply => 'タップで適用';

  @override
  String get autoplayKeepGoing => 'キューが終わったら、似た曲で続ける';

  @override
  String get gaplessPlayback => 'ギャップレス再生';

  @override
  String get gaplessPlaybackSubtitle => '曲間に無音を入れない。クロスフェードは「音響効果（DSP）」にある。';

  @override
  String get skipSilence => '無音をスキップ';

  @override
  String get offWhileBitPerfect => 'Bit-perfect モード中はオフ';

  @override
  String get skipSilenceSubtitle => '無音のイントロ、アウトロ、曲間を短くする。静かなパートはそのまま';

  @override
  String get off => 'オフ';

  @override
  String get volumeLeveling => '音量の均一化';

  @override
  String get volumeLevelingSubtitle => 'ReplayGain タグを使って、曲ごとの音量をそろえる';

  @override
  String get measureLoudness => 'ReplayGain タグのない曲を測る';

  @override
  String measureLoudnessSubtitle(int measured, int total) {
    return 'この端末の $total 曲中 $measured 曲を測定済み。タグのない曲は測った音量でそろえるよ';
  }

  @override
  String measuringLoudness(int done, int total) {
    return '$total 曲中 $done 曲目を測定中…';
  }

  @override
  String get measure => '測る';

  @override
  String get crossfade => 'クロスフェード';

  @override
  String get crossfadeSubtitle => '曲の終わりを次の曲の始まりに重ねる。Bit-perfect と排他モードではオフ';

  @override
  String get fadeLength => 'フェードの長さ';

  @override
  String get skipForAlbums => 'アルバムでは使わない';

  @override
  String get skipForAlbumsSubtitle => 'アルバムで続く曲はフェードなしで、アーティストが作ったとおりに流す';

  @override
  String get virtualSpeakers => 'バーチャルスピーカー';

  @override
  String get offWhileMono => 'モノラル中はオフ';

  @override
  String get virtualSpeakersSubtitle => 'ヘッドホン向け：頭の中じゃなく、2台のスピーカーみたいに前から聞こえる';

  @override
  String get virtualSpeakerLevel => 'バーチャルスピーカーのレベル';

  @override
  String get virtualSpeakerLevelBody => 'ほかの聴き方と音量がそろうように、シミュレーションの出力レベルを調整する。';

  @override
  String get headphoneCrossfeed => 'ヘッドホンのクロスフィード';

  @override
  String get crossfeedNotNeeded => 'バーチャルスピーカーと一緒なら不要：もう同じことをしてる';

  @override
  String get crossfeedSubtitle => 'ヘッドホンを部屋のスピーカーっぽく聞こえさせる';

  @override
  String get crossfeedSoundstage => 'クロスフィードの音場';

  @override
  String get crossfeedSoundstageBody => '左右のチャンネルで混ぜる周波数の範囲を調整する。デフォルト：50%。';

  @override
  String get monoAudio => 'モノラル';

  @override
  String get monoAudioSubtitle => '左右をひとつの音に。ヘッドホンの片方が聞こえないときに便利';

  @override
  String get audioPlugins => 'オーディオプラグイン';

  @override
  String get audioPluginsSubtitle => 'Carla で設定した VST、LV2、CLAP プラグイン。そこで追加して保存すれば、ここで鳴る';

  @override
  String get editInCarla => 'Carla で編集';

  @override
  String get needsCarlaDownload =>
      'VST、LV2、CLAP プラグインをまとめる無料ソフト Carla が必要。ダウンロードして「ダウンロード」か「Program Files」フォルダに展開してから、このページを開き直してね。';

  @override
  String get needsCarlaInstall => 'VST、LV2、CLAP プラグインをまとめる無料ソフト Carla が必要。インストールしてから、このページを開き直してね。';

  @override
  String get installCarla => 'Carla をインストール';

  @override
  String get roomCorrection => 'ルーム補正';

  @override
  String get roomCorrectionSubtitle => 'インパルス応答（WAV か FLAC、REW などで作ったもの）を読み込んで、部屋やヘッドホンを補正する';

  @override
  String get chooseFile => 'ファイルを選ぶ';

  @override
  String get change => '変更';

  @override
  String get roomCorrectionHeadroom => 'ルーム補正のヘッドルーム';

  @override
  String get roomCorrectionHeadroomBody => 'インパルス応答でピークが大きくなりすぎるなら、補正後の信号を下げる。';

  @override
  String get signalPathSubtitle => '今の曲で実際に効いてるエフェクトを見る';

  @override
  String resetNamed(String name) {
    return '$nameをリセット';
  }

  @override
  String get chooseImpulse => 'インパルス応答を選ぶ';

  @override
  String get couldntUseFile => 'そのファイルは使えませんでした';

  @override
  String get output => '出力';

  @override
  String get iosOutputNote =>
      'USB DAC は曲ごとのサンプルレートに合わせる。スピーカーと Bluetooth はひとつのレートのまま。iOS は常に音をミックスするので、ここでは Bit-perfect にできない。';

  @override
  String get outputDevice => '出力デバイス';

  @override
  String get directDevicesNote => '「direct」のデバイスはシステムのミキサーを通さない。Bit-perfect になるけど、ほかのアプリの音は出なくなる';

  @override
  String get phonesOwnOutput => 'スマホ本体の出力';

  @override
  String usbDacNamed(String name) {
    return '$name（USB DAC）';
  }

  @override
  String get bitPerfectMode => 'Bit-perfect モード';

  @override
  String get needsAndroid14 => 'Android 14 以降が必要';

  @override
  String androidFormatsUnplayable(String dac, int bitPerfect, int total) {
    return 'Android が $dac に出す形式は、Riflay が Bit-perfect で再生できないものだけ（$total個中$bitPerfect個）。DAC からは鳴るけど、先に Android が音をミックスする。';
  }

  @override
  String phoneNoBitPerfect(String dac, int count) {
    return 'このスマホは $dac への Bit-perfect 出力に対応してない。メーカーが外してる（Android が出す形式は$count個で、Bit-perfect なものはなし）。DAC からは鳴るけど、先に Android が音をミックスする。';
  }

  @override
  String get plugInDacForBitPerfect => 'USB DAC をつなぐと Bit-perfect で再生できる';

  @override
  String get bitPerfectAndroid =>
      'ファイルをそのまま USB DAC に送る。イコライザーも音量の均一化もリサンプリングもなし。ほかのアプリやシステム音は DAC で消音され、スマホの音量ボタンも効かなくなる。Riflay の音量を下げると音が変わるので、DAC の音量を使ってね。';

  @override
  String get bitPerfectMac =>
      'Riflay ではイコライザーも音量の均一化もリサンプリングもなし。DAC は曲ごとのサンプルレートに合わせる。音量は使えて、100% なら何も変わらない。ほかのアプリも鳴るので macOS がまだ音をミックスする。ファイルをそのまま DAC に送るなら排他モードもオンにしてね。';

  @override
  String get bitPerfectWindows =>
      'Riflay ではイコライザーも音量の均一化もリサンプリングもなし。音量は使えて、100% なら何も変わらない。ほかのアプリも鳴るので Windows がまだ音をミックスする。ファイルをそのまま DAC に送るなら排他モードもオンにしてね。';

  @override
  String get bitPerfectLinux =>
      'ファイルをそのまま DAC に送る。イコライザーも音量の均一化もリサンプリングもなし。音量は使えて、100% なら何も変わらない。システムのミキサーがリサンプリングできないよう DAC を占有する。その間、ほかのアプリは別の出力から鳴る。';

  @override
  String get nativeDsd => 'ネイティブ DSD（DoP）';

  @override
  String get nativeDsdSubtitle =>
      'DSD ファイルを変換せず DSD のまま DAC に送る。DoP 対応の DAC 専用で、非対応だとかすかなノイズが出るのでオフにしてね。DSD の曲は音量 100% 固定なので、DAC の音量を使って。';

  @override
  String get needsBitPerfectAndDac => 'Bit-perfect モードと、176.4 kHz 以上に対応した USB DAC が必要';

  @override
  String get needsBitPerfectAndExclusive => 'Bit-perfect モードと排他モードが必要';

  @override
  String get needsBitPerfect => 'Bit-perfect モードが必要';

  @override
  String get exclusiveMode => '排他モード';

  @override
  String get exclusiveMac => 'デバイスを占有して、macOS がミックスもリサンプリングもできないようにする。DAC は曲ごとのサンプルレートに切り替わる。Riflay の再生中、ほかのアプリは鳴らない。';

  @override
  String get exclusiveWindows =>
      'デバイスを占有して、Windows のミキサーがリサンプリングできないようにする。DAC は曲ごとのサンプルレートに切り替わる。Riflay の再生中、ほかのアプリは鳴らず、Windows の音量ミキサーでも操作できない。';

  @override
  String get outputSampleRate => '出力サンプルレート';

  @override
  String get followsEachSong => 'Bit-perfect モード中は曲ごとに合わせる';

  @override
  String get followOrConvert => '曲に合わせるか、全部ひとつのレートに変換するか';

  @override
  String get followTheSong => '曲に合わせる';

  @override
  String get hqResampler => '高品質リサンプラー';

  @override
  String get hqResamplerSubtitle => 'レートを変えるときは SoX 並みの変換をする（CPU を少し多めに使う）';

  @override
  String get buffer => 'バッファ';

  @override
  String get bufferSubtitle => 'プチプチ音や途切れがあるなら上げてね';

  @override
  String get signalPathSubtitleExact => '再生中の曲に何が起きてるか、そのまま見られる';

  @override
  String get directUsbIntro => 'Riflay が Android を通さず USB DAC と直接やりとりするので、Bit-perfect モードが使えないスマホでも曲がそのまま届く。試験的な機能。';

  @override
  String get directUsbPlugIn => 'オン。USB DAC をつないでね。';

  @override
  String directUsbAllow(String dac) {
    return 'オン。Riflay に $dac の使用を許可してね。';
  }

  @override
  String directUsbBitPerfectTo(String dac) {
    return '$dac へ Bit-perfect';
  }

  @override
  String directUsbFallback(String format, String dac) {
    return 'この曲$formatは $dac が受け付けない形式なので、Android 経由で再生する。';
  }

  @override
  String directUsbOnWith(String dac) {
    return 'オン、$dac を使用中。曲を再生してね。';
  }

  @override
  String get allowUsbAccess => 'USB へのアクセスを許可';

  @override
  String problemWith(String error) {
    return '問題：$error';
  }

  @override
  String directUsbPipe(String state, String output) {
    return 'パイプ：$state · 出力：$output';
  }

  @override
  String get pipeOpen => '開いてる';

  @override
  String get pipeClosed => '閉じてる';

  @override
  String fromThePlayer(String format) {
    return 'プレイヤーから：$format';
  }

  @override
  String directUsbRoute(String route) {
    return '経路：$route';
  }

  @override
  String dropouts(String count) {
    return '途切れ：$count';
  }

  @override
  String get directUsb => 'Direct USB';

  @override
  String get styleClassic => 'クラシック';

  @override
  String get styleCompact => 'コンパクト';

  @override
  String get styleMinimal => 'ミニマル';

  @override
  String get vizWave => 'ウェーブ';

  @override
  String get vizBars => 'バー';

  @override
  String get vizLine => 'ライン';

  @override
  String get vizDots => 'ドット';

  @override
  String get vizMirror => 'ミラー';

  @override
  String get vizTwinWaves => 'ツインウェーブ';

  @override
  String get vizPulse => 'パルス';

  @override
  String get vizOrbit => 'オービット';

  @override
  String get vizPetals => '花びら';

  @override
  String get vizPeaks => 'ピーク';

  @override
  String get shapeFlower => '花';

  @override
  String get shapeSquare => '四角';

  @override
  String get shapeRounded => '角丸';

  @override
  String get shapeExtraRound => 'もっと丸く';

  @override
  String get densityComfortable => 'ゆったり';

  @override
  String get sizeSmall => '小';

  @override
  String get sizeMedium => '中';

  @override
  String get sizeLarge => '大';

  @override
  String get motionFull => 'フル';

  @override
  String get motionReduced => '控えめ';

  @override
  String get decoderAuto => '自動';

  @override
  String get decoderGpu => 'グラフィックカード';

  @override
  String get decoderCpu => 'プロセッサー';

  @override
  String get decoderAutoNote => '動くとわかってればグラフィックカード、だめならプロセッサー';

  @override
  String get decoderGpuNote => '常にまずグラフィックカードを試す。ドライバーが対応してれば一番軽い';

  @override
  String get decoderCpuNote => 'グラフィックカードは使わない。電力は多めに使うので、動画の表示がおかしいときに試してね';

  @override
  String get perfLight => '軽量';

  @override
  String get perfBalanced => 'バランス';

  @override
  String get perfHeavy => '全開';

  @override
  String get perfLightNote => 'エフェクトは最小限。古いパソコンやバッテリー持ちを優先するならこれ。';

  @override
  String get perfBalancedNote => 'ほどよく抑えた、なめらかなアニメーション。';

  @override
  String get perfHeavyNote => 'すべてのエフェクトをフルスピードで。電力は多めに使う。';

  @override
  String get styleThin => '細い';

  @override
  String get styleThick => '太い';

  @override
  String get shapeStraight => 'まっすぐ';

  @override
  String get shapeWavy => '波線';

  @override
  String get shapePill => 'ピル';

  @override
  String get shapeThinLine => '細い線';

  @override
  String get shapeWaveform => '波形';

  @override
  String get shapeCircle => '丸';

  @override
  String get shapeRoundedSquare => '角丸の四角';

  @override
  String get sizeNormal => '普通';

  @override
  String get coverBackground => '背景';

  @override
  String get headerCentred => '中央';

  @override
  String get headerPlayingFrom => '再生元';

  @override
  String get styleBoxed => '枠つき';

  @override
  String get stylePlain => 'シンプル';

  @override
  String get styleChips => 'チップ';

  @override
  String get styleIcons => 'アイコン';

  @override
  String get styleBottomCard => '下のカード';

  @override
  String get styleTopHeader => '上のヘッダー';

  @override
  String get styleFloatingPill => '浮かぶピル';

  @override
  String get styleHero => 'ヒーロー';

  @override
  String get badgeUnderArtist => 'アーティスト名の下';

  @override
  String get badgeTimeRow => '時間の行';

  @override
  String get styleHighlightedCard => '強調カード';

  @override
  String get sizeLargest => '特大';

  @override
  String get lyricsFocused => 'フォーカス';

  @override
  String get lyricsWordByWord => '単語ごと';

  @override
  String get lyricsLineByLine => '行ごと';

  @override
  String get alignLeft => '左寄せ';

  @override
  String get alignCentre => '中央';

  @override
  String get styleMaterial => 'Material';

  @override
  String get styleUnderline => '下線';

  @override
  String get styleTextOnly => '文字だけ';

  @override
  String get styleFloating => 'フローティング';

  @override
  String get styleCapsule => 'カプセル';

  @override
  String get styleDock => 'ドック';

  @override
  String get styleCentreButton => '中央ボタン';

  @override
  String get styleLiquidGlass => 'リキッドグラス';

  @override
  String get quickPicks => 'おすすめ';

  @override
  String get fromYoutubeMusic => 'YouTube Music から';

  @override
  String get presets => 'プリセット';

  @override
  String get custom => 'カスタム';

  @override
  String matchesPreset(String preset) {
    return '「$preset」と同じ';
  }

  @override
  String get fullScreenPlayerHint => '全画面のプレイヤー';

  @override
  String get cover => 'ジャケット';

  @override
  String get coverSubtitle => '四角か花の形でジャケットを囲む。「背景」は枠なしで、上側いっぱいに広がってページに溶け込む';

  @override
  String get coverSizeOnPhones => 'スマホでのジャケットの大きさ';

  @override
  String get coverSizeOnPhonesSubtitle => '「大」だと画面の端近くまで広がる';

  @override
  String get topOfPlayer => 'プレイヤーの上部';

  @override
  String get topOfPlayerSubtitle => '閉じる矢印の横（デスクトップでは曲の上）に出すもの';

  @override
  String get buttonsByTitle => 'タイトル横のボタン';

  @override
  String get buttonsByTitleSubtitle => 'いいねとその他をそのまま、共有とハートをひとまとめ、またはシンプルなアイコン。デスクトップでは曲のメニューが残る';

  @override
  String get showSoundQuality => '音質を表示';

  @override
  String get showSoundQualitySubtitle => '曲名の下の小さなラベル（FLAC や Hi-Res など）';

  @override
  String get songVideoSwitch => '曲／動画の切り替え';

  @override
  String get songVideoSwitchSubtitle => '再生中の画面の上部。「自動」だとMVがある曲のときだけ出る';

  @override
  String get adaptive => '自動';

  @override
  String get qualityBadge => '音質バッジ';

  @override
  String get qualityBadgeSubtitle => 'スマホのプレイヤーで FLAC や Opus 130 kbps を出す場所：アーティスト名の下か、2つの時間の間';

  @override
  String get background => '背景';

  @override
  String get backgroundSubtitle => 'プレイヤーの後ろに敷くもの。ジャケットを「背景」にするとこれの代わりになる';

  @override
  String get videoMode => '動画モード';

  @override
  String get videoModeSubtitle => '曲に合わせてMVを観る';

  @override
  String get videoDecoding => '動画のデコード';

  @override
  String decoderNow(String decoder) {
    return '現在：$decoder';
  }

  @override
  String get decoderNowCpu => 'プロセッサー';

  @override
  String decoderNowGpu(String hwdec) {
    return 'グラフィックカード（$hwdec）';
  }

  @override
  String get playbackControls => '再生コントロール';

  @override
  String get playbackControlsHint => 'シークバー、ボタン、その下の行';

  @override
  String get progressBarShape => 'シークバーの形';

  @override
  String get progressBar => 'シークバー';

  @override
  String get progressBarSubtitle => 'ドラッグして移動するバーの太さ';

  @override
  String get showTimeLeft => '残り時間を表示';

  @override
  String get showTimeLeftSubtitle => '右側の時間を合計じゃなくカウントダウンにする（デスクトップのバーでも）';

  @override
  String get controls => 'コントロール';

  @override
  String get controlsSubtitle => '前へ・再生・次へを丸ボタン、横長の再生ピル、大きいシンプルなアイコンから選べる（デスクトップのバーでも）';

  @override
  String get playButton => '再生ボタン';

  @override
  String get playButtonSubtitle => '大きい再生／一時停止ボタンの形';

  @override
  String get volumeSlider => '音量スライダー';

  @override
  String get volumeSliderSubtitle => 'スマホのプレイヤーのいちばん下。オフにすると、スピーカーボタン（アイコン）かデスクトップのバーのボタンから開く';

  @override
  String get sliderLook => 'スライダーの見た目';

  @override
  String get sliderLookSubtitle => '音量、イコライザー、設定のすべてのスライダー。クラシック、細い線、バーのつまみがついた太いピル';

  @override
  String get bottomButtons => '下のボタン';

  @override
  String get bottomButtonsSubtitle => '歌詞とキュー、アイコンボタンを一列に、または歌詞・スピーカーと人のカプセル・キュー。アイコンだけでも歌詞は常にある';

  @override
  String get lyricsHint => '歌詞のページと、デスクトップでジャケットの横に出る歌詞';

  @override
  String get lyricsPage => '歌詞のページ';

  @override
  String get lyricsPageSubtitle => '歌詞のページでのプレイヤーの位置。デスクトップでは曲のカードが上か下に出る';

  @override
  String get linesShown => '表示する行';

  @override
  String get linesShownSubtitle => '「すべて」は曲全体を表示。「フォーカス」は前・今・次の行だけ';

  @override
  String get sync => '同期';

  @override
  String get syncSubtitle => '「単語ごと」は歌詞に単語のタイミングがあれば、歌われた単語から色がつく。「行ごと」は行全体が光る';

  @override
  String get textSize => '文字の大きさ';

  @override
  String get lyricsTextSizeSubtitle => '歌詞の大きさ';

  @override
  String get alignment => '配置';

  @override
  String get alignmentSubtitle => '行を左端からそろえるか、中央に置くか';

  @override
  String get dimUnsung => 'まだ歌われてない行を暗くする';

  @override
  String get dimUnsungSubtitle => '歌われてる行とそれより前の行だけ明るいまま';

  @override
  String get highlightLyricLine => '歌ってる行をハイライト';

  @override
  String get highlightLyricLineSubtitle => '行全体の後ろに、うっすら暗いすりガラスを敷くよ';

  @override
  String get lockScreenLyrics => 'ロック画面に歌詞';

  @override
  String get lockScreenLyricsSubtitle => '通知やロック画面、車のディスプレイで、アーティスト名の代わりに今歌ってる行を出すよ。歌詞の「読み方」がオンなら、ほかの文字の行には読み方も付くよ';

  @override
  String get visualizer => 'ビジュアライザー';

  @override
  String get visualizerHint => '音楽に合わせて動く図形';

  @override
  String get pages => 'ページ';

  @override
  String get pagesHint => 'アルバム、プレイリスト、アーティストのページ、曲リスト、ホーム';

  @override
  String get albumPlaylistTop => 'アルバムとプレイリストの上部';

  @override
  String get albumPlaylistTopSubtitle => 'ヒーロー：タイトルの後ろに大きなジャケットがフェードし、再生ピルの周りに丸ボタン。アーティストのページにも';

  @override
  String get songThatIsPlaying => '再生中の曲';

  @override
  String get songThatIsPlayingSubtitle => '曲リストで：文字に色をつけるか、バーのついた角丸カードにする';

  @override
  String get bars => 'バー';

  @override
  String get barsHint => 'ミニプレイヤーと、コントロールの入ったバー';

  @override
  String get miniPlayerSubtitle => 'スマホで曲の再生中にタブの上に出るバー。「浮かぶピル」は花の形のジャケットと丸ボタン';

  @override
  String get tabBarOnPhones => 'スマホのタブバー';

  @override
  String get tabBarOnPhonesSubtitle => 'クラシックは下端に、フローティングとリキッドグラスはその上に浮かぶ';

  @override
  String get desktopPlayerBar => 'デスクトップのプレイヤーバー';

  @override
  String get desktopPlayerBarSubtitle => 'ウィンドウの下端に：横幅いっぱいのコントロール、曲の横のコンパクトな行、またはミニマルな帯';

  @override
  String get shapesAndMotion => '形と動き';

  @override
  String get motionOffLightweight => 'パフォーマンスが「軽量」なので、動きの設定はオフのまま。';

  @override
  String get corners => '角';

  @override
  String get cornersSubtitle => 'ジャケット、カード、メニュー、ダイアログ、ミニプレイヤー';

  @override
  String get spacing => '余白';

  @override
  String get spacingSubtitle => '「コンパクト」だと画面に曲やカードがたくさん入る';

  @override
  String get coverSizeInGrids => 'グリッドのジャケットの大きさ';

  @override
  String get coverSizeInGridsSubtitle => 'ホームと「すべて表示」のアルバムとプレイリスト';

  @override
  String get transitionStyle => 'トランジションのスタイル';

  @override
  String get transitionStyleSubtitle => 'ページ、タブ、プレイヤーの切り替えをそろえる';

  @override
  String get transitionSpeed => 'トランジションの速さ';

  @override
  String get transitionSpeedSubtitle => 'きびきびか、ゆったりかを選ぶ';

  @override
  String get animations => 'アニメーション';

  @override
  String get animationsSubtitle => '「控えめ」は短いフェードだけ。「フル」はシステムが動きを減らす設定ならそれに従う';

  @override
  String get window => 'ウィンドウ';

  @override
  String get desktopOnly => 'デスクトップのみ';

  @override
  String get windowButtons => 'ウィンドウのボタン';

  @override
  String get windowButtonsSubtitle => 'タイトルバーの最小化・最大化・閉じる。タイル型ウィンドウマネージャーならオフにしてね';

  @override
  String get resetLayout => 'レイアウトをデフォルトに戻す';

  @override
  String get dragToReorderSections => 'つまみをドラッグしてセクションの順番を変える';

  @override
  String get audioVisualizer => 'オーディオビジュアライザー';

  @override
  String get audioVisualizerSubtitle => 'ジャケットの周りと下で音楽に合わせて動く図形';

  @override
  String get visualizerStyle => 'ビジュアライザーのスタイル';

  @override
  String get visualizerStyleBackground => '曲の下に帯で表示。パルス、オービット、花びらはジャケットを囲むので、四角か花を選んでね';

  @override
  String get visualizerStyleRings => 'ジャケットを囲む';

  @override
  String get visualizerStyleEdge => 'ジャケットのふちに沿って動き、曲の下にも帯が出る';

  @override
  String get radiusMovement => '半径の動き';

  @override
  String radiusMovementSubtitle(String percent) {
    return '$percent% · 音楽に合わせて図形が広がる大きさ';
  }

  @override
  String get lineThickness => '線の太さ';

  @override
  String signedInAs(String name) {
    return '$name でログイン中';
  }

  @override
  String get ytSignedInBody => 'ログイン中。お気に入り、プレイリスト、フォロー中のアーティストがここに出る。';

  @override
  String get ytSignedOutBody => 'ログインしてない。検索と公開ホームはアカウントなしでも使える。';

  @override
  String get disconnect => '接続を解除';

  @override
  String get addToYtHistory => '再生した曲を YouTube Music の履歴に追加';

  @override
  String get addToYtHistorySubtitle => '公式アプリと同じように、YouTube Music が好みを覚えていく。';

  @override
  String get musixmatchLyrics => 'Musixmatch の歌詞';

  @override
  String get musixmatchLyricsSubtitle => 'ほかで見つからないとき、単語ごとの歌詞を探す';

  @override
  String get discordRichPresence => 'Discord Rich Presence';

  @override
  String get discordRichPresenceSubtitle => '聴いてる曲を Discord のプロフィールに表示';

  @override
  String get betterLyricsKey => 'Better Lyrics の API キー';

  @override
  String get betterLyricsKeyOptional => '任意。キーがあれば、Better Lyrics がまだ保存してない歌詞も探せる。';

  @override
  String get betterLyricsKeyAdded => '追加済み。Better Lyrics がまだ保存してない歌詞も探せる。';

  @override
  String crumbsThen(String crumbs, String current) {
    return '$crumbs、$current';
  }

  @override
  String get crumbsJoin => '、';

  @override
  String get betterLyricsKeyInvalid => 'Better Lyrics によると、このキーは無効です。';

  @override
  String get betterLyricsUnreachable => 'キーを確認するために Better Lyrics に接続できませんでした。もう一度試してください。';

  @override
  String get betterLyricsKeyBody => 'キーがなくても、Better Lyrics に保存済みの曲なら歌詞は出る。今は新しいキーの配布はしてないみたい。';

  @override
  String get apiKey => 'API キー';

  @override
  String get checking => '確認中…';

  @override
  String get save => '保存';

  @override
  String get statsNothingPlaying => '何も再生してない。';

  @override
  String get statsOtherDevice => 'ほかのデバイスで再生中。統計は再生してるデバイスのもの。';

  @override
  String get waitingForAudio => '音声を待ってる…';

  @override
  String get statsCopied => '統計をコピーした';

  @override
  String get copyStats => '統計をコピー';

  @override
  String get statsHint => '毎秒更新。コピーしてバグ報告に貼り付けられる。';

  @override
  String get themeLegacy => '旧デザイン';

  @override
  String get themeDefault => 'デフォルト';

  @override
  String get themeMonochrome => 'モノクロ';

  @override
  String get modeDark => 'ダーク';

  @override
  String get modeLight => 'ライト';

  @override
  String get modeBlack => 'ブラック';

  @override
  String get modeSystem => 'システムに合わせる';

  @override
  String get accentTheme => 'テーマ';

  @override
  String get accentTeal => 'ティール';

  @override
  String get accentGreen => '緑';

  @override
  String get accentBlue => '青';

  @override
  String get accentViolet => '紫';

  @override
  String get accentPink => 'ピンク';

  @override
  String get accentOrange => 'オレンジ';

  @override
  String get accentWhite => '白';

  @override
  String get customEllipsis => 'カスタム…';

  @override
  String get coverColorPlayer => 'プレイヤーだけ';

  @override
  String get coverColorApp => 'アプリ全体';

  @override
  String get npBgSimple => 'シンプル';

  @override
  String get npBgBlurredCover => 'ぼかしたジャケット';

  @override
  String get npBgMusicVideo => 'MV';

  @override
  String get npBgMusicVideoHint => '曲のMV（あれば）';

  @override
  String get theme => 'テーマ';

  @override
  String get matugenColors => 'Matugen の色';

  @override
  String get matugenChoose => '生成した JSON ファイルを選んでね。色は自動で更新される。';

  @override
  String get matugenFollowing => '生成された色に自動で合わせてる';

  @override
  String get matugenFind => '生成された色を自動で探す';

  @override
  String get coloursFromCover => '再生中の曲のジャケットから色を取る';

  @override
  String get backgroundColour => '背景色';

  @override
  String get backgroundColourSubtitle => 'パネル、カード、メニューの色はここから決まる';

  @override
  String get textColour => '文字の色';

  @override
  String get textColourAuto => '背景に合わせて選ばれる';

  @override
  String get textColourAdjusted => '読みにくいところは明るく、または暗くする';

  @override
  String get automatic => '自動';

  @override
  String get mode => 'モード';

  @override
  String get modeSubtitle => 'すべてのテーマで、ライトかダークか';

  @override
  String get accentColour => 'アクセントカラー';

  @override
  String get coloursFromCoverArt => 'ジャケットの色を使う';

  @override
  String get coverColorOffNote => 'テーマの色のまま';

  @override
  String get coverColorPlayerNote => '再生中の曲の色でプレイヤーとページを染める';

  @override
  String get coverColorAppNote => 'アプリ全体が再生中の曲の色になる';

  @override
  String get colourStrength => '色の強さ';

  @override
  String get colourStrengthSubtitle => '背景やパネルにジャケットの色をどれだけ出すか';

  @override
  String get strengthSubtle => '控えめ';

  @override
  String get strengthStrong => '強め';

  @override
  String get highContrast => 'ハイコントラスト';

  @override
  String get highContrastSubtitle => '文字を明るく、ふちをくっきりさせて読みやすくする';

  @override
  String textSizeSubtitle(int size) {
    return '本文の大きさ（ピクセル）。タイトルやラベルも一緒に大きくなる。デフォルトは $size px';
  }

  @override
  String get font => 'フォント';

  @override
  String get openFontsFolder => 'フォントフォルダを開く（.ttf か .otf ファイルをここに入れてね）';

  @override
  String get nowPlayingBackground => '再生中の画面の背景';

  @override
  String get nowPlayingBackgroundSubtitle => '再生中の画面と大きいプレイヤーだけ';

  @override
  String get frostedGlass => 'すりガラス';

  @override
  String get frostedGlassSubtitle => 'ミニプレイヤーとタブバーを透けたぼかしに。GPU を少し多めに使う';

  @override
  String get blurStrength => 'ぼかしの強さ';

  @override
  String get componentOpacity => 'パーツの不透明度';

  @override
  String get componentOpacitySubtitle => '背景を透かして、後ろのデスクトップをぼかす。文字、ジャケット、コントロールは透けない';

  @override
  String get backgroundOpacity => '背景の不透明度';

  @override
  String get backgroundOpacityAndroid => '100% 未満だと壁紙が透けて見える';

  @override
  String get backgroundOpacityDesktop => '100% 未満だとデスクトップが透けて見える。対応してるシステムではぼかしがかかる（Windows 11、macOS、Hyprland、KDE）';

  @override
  String get resetToDefault => 'デフォルトに戻す';

  @override
  String couldntLoadFont(String font) {
    return '$font を読み込めませんでした。';
  }

  @override
  String get searchFonts => 'この端末のフォントを検索';

  @override
  String get riflaysOwnFont => 'Riflay のフォント';

  @override
  String fontFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$countファイル（太さとスタイル）', one: '1ファイル');
    return '$_temp0';
  }

  @override
  String get defaultThemeFollows => 'デフォルトのテーマ。再生中の曲に合わせる';

  @override
  String themeNamed(String name) {
    return '$name テーマ';
  }

  @override
  String get smaller => '小さく';

  @override
  String get larger => '大きく';

  @override
  String get levelingPerSong => '曲ごと';

  @override
  String get levelingPerAlbum => 'アルバムごと';

  @override
  String get bufferLow => '低遅延';

  @override
  String get bufferStable => '安定重視';

  @override
  String get monoOff => 'オフ（ステレオ）';

  @override
  String get monoBoth => '両耳';

  @override
  String get monoLeft => '左耳だけ';

  @override
  String get monoRight => '右耳だけ';

  @override
  String get eqFlat => 'フラット';

  @override
  String get eqBassBoost => '低音強調';

  @override
  String get eqBassCut => '低音カット';

  @override
  String get eqTrebleBoost => '高音強調';

  @override
  String get eqVocal => 'ボーカル';

  @override
  String get eqRock => 'ロック';

  @override
  String get eqPop => 'ポップ';

  @override
  String get eqJazz => 'ジャズ';

  @override
  String get eqClassical => 'クラシック';

  @override
  String get eqElectronic => 'エレクトロニック';

  @override
  String get eqLoudness => 'ラウドネス';

  @override
  String dopNote(String rate) {
    return 'この DAC は $rate までで、DoP には 176.4 kHz が必要なので、DSD ファイルは PCM で再生される';
  }

  @override
  String get systemDefault => 'システムのデフォルト';

  @override
  String get outputNotConnected => '選んだ出力がつながってないので、今はシステムのデフォルトから再生してます。';

  @override
  String cardBusy(String card) {
    return '$card が使用中なので、今はシステムのミキサー経由で再生してます。';
  }

  @override
  String fxRoomCorrection(String name) {
    return 'ルーム補正（$name）';
  }

  @override
  String get fxEqHeadroom => 'イコライザーのヘッドルーム';

  @override
  String get fxHrtf => 'バーチャルスピーカー（HRTF）';

  @override
  String get fxMonoBoth => 'モノラル（両耳）';

  @override
  String get fxMonoLeft => 'モノラル（左耳だけ）';

  @override
  String get fxMonoRight => 'モノラル（右耳だけ）';

  @override
  String get fxPlugins => 'オーディオプラグイン（Carla）';

  @override
  String get removedFromLiked => 'お気に入りから外した';

  @override
  String get addedToLiked => 'お気に入りに追加した';

  @override
  String get renamePlaylist => 'プレイリストの名前を変更';

  @override
  String get name => '名前';

  @override
  String get playlistOnDeviceNote => 'この端末に保存。手持ちのファイルと YouTube Music の曲を混ぜられる。';

  @override
  String get playlistOnYtNote => 'YouTube Music アカウントに保存。どの端末でも使える。';

  @override
  String get privacyPrivate => '自分だけが見られる。';

  @override
  String get privacyUnlisted => 'リンクを知ってる人なら誰でも見られる。';

  @override
  String get privacyPublic => '誰でも見つけて見られる。';

  @override
  String get create => '作成';

  @override
  String createdInYt(String title) {
    return 'YouTube Music に「$title」を作成した';
  }

  @override
  String createdPlaylistWith(String title, int count) {
    return '「$title」を$count曲で作成した';
  }

  @override
  String createdPlaylist(String title) {
    return '「$title」を作成した';
  }

  @override
  String get removedFromThisPlaylist => 'このプレイリストから外した';

  @override
  String get makeUnlistedQuestion => '限定公開にしますか？';

  @override
  String get makeUnlistedBody => '友だちが参加できるのは非公開じゃないプレイリストだけです。限定公開になり、検索には出ませんが、リンクを知ってる人は誰でも見られます。';

  @override
  String get makeUnlisted => '限定公開にする';

  @override
  String get inviteFriends => '友だちを招待';

  @override
  String get inviteLinkCopied => 'リンクをコピーした。友だちに送ってね。開いた人は誰でも曲を追加できる。';

  @override
  String get copyAgain => 'もう一度コピー';

  @override
  String get done => '完了';

  @override
  String get stopSharingQuestion => '共有をやめますか？';

  @override
  String get stopSharingBody => '友だちは曲を追加できなくなり、以前の招待リンクも使えなくなります。';

  @override
  String get stopSharing => '共有をやめる';

  @override
  String get onlyYouCanAdd => '曲を追加できるのは自分だけになった';

  @override
  String get joinSharedPlaylistBody => '友だちからもらった招待リンクを貼り付けてね。2人とも曲を追加できるようになる。';

  @override
  String get inviteLink => '招待リンク';

  @override
  String get notAnInviteLink => 'それは招待リンクじゃない';

  @override
  String get join => '参加';

  @override
  String unfollowedName(String name) {
    return '$name のフォローを外した';
  }

  @override
  String followingName(String name) {
    return '$name をフォローした';
  }

  @override
  String get downloadFailedTryAgain => 'ダウンロードに失敗しました。もう一度試してください';

  @override
  String downloadHoldTooltip(String format) {
    return 'ダウンロード\n長押しで今すぐ $format でダウンロード';
  }

  @override
  String downloadingIn(String format) {
    return '$format でダウンロード中…';
  }

  @override
  String downloadingTitle(String title) {
    return '$title をダウンロード中…';
  }

  @override
  String get thisMonth => '今月';

  @override
  String get thisYear => '今年';

  @override
  String get allTime => 'これまで全部';

  @override
  String get monthJanuary => '1月';

  @override
  String get monthFebruary => '2月';

  @override
  String get monthMarch => '3月';

  @override
  String get monthApril => '4月';

  @override
  String get monthMay => '5月';

  @override
  String get monthJune => '6月';

  @override
  String get monthJuly => '7月';

  @override
  String get monthAugust => '8月';

  @override
  String get monthSeptember => '9月';

  @override
  String get monthOctober => '10月';

  @override
  String get monthNovember => '11月';

  @override
  String get monthDecember => '12月';

  @override
  String get monthInitials => '1 2 3 4 5 6 7 8 9 10 11 12';

  @override
  String monthYear(String month, String year) {
    return '$year年$month';
  }

  @override
  String monthDay(String month, String day) {
    return '$month$day日';
  }

  @override
  String get durZero => '0分';

  @override
  String get durOneMin => '1分';

  @override
  String durMin(String m) {
    return '$m分';
  }

  @override
  String durHours(String h) {
    return '$h時間';
  }

  @override
  String durHoursMin(String h, String m) {
    return '$h時間$m分';
  }

  @override
  String wrapSoFar(String month) {
    return '$month（ここまで）';
  }

  @override
  String get playFewSongsWrap => '何曲か聴くと Wrap が見られる。';

  @override
  String notEnoughForWrap(String month) {
    return '$monthは Wrap を作れるほど聴いてない。';
  }

  @override
  String wrapCaption(String month, String listened, String song, String artist) {
    return 'Riflay での$month：音楽を$listened。トップソング：$song。トップアーティスト：$artist。';
  }

  @override
  String wrapCaptionStreak(int count) {
    return '🔥 $count日連続。';
  }

  @override
  String savedFile(String file) {
    return '$file を保存した';
  }

  @override
  String get couldntSaveImage => '画像を保存できませんでした';

  @override
  String savedCaptionCopied(String file) {
    return '$file を保存して、キャプションをコピーした';
  }

  @override
  String get saveImage => '画像を保存';

  @override
  String get weekdayMonday => '月曜日';

  @override
  String get weekdayTuesday => '火曜日';

  @override
  String get weekdayWednesday => '水曜日';

  @override
  String get weekdayThursday => '木曜日';

  @override
  String get weekdayFriday => '金曜日';

  @override
  String get weekdaySaturday => '土曜日';

  @override
  String get weekdaySunday => '日曜日';

  @override
  String weekdayMonthDay(String weekday, String month, String day) {
    return '$month$day日（$weekday）';
  }

  @override
  String get wrapSoFarKicker => 'ここまでの Wrap';

  @override
  String get wrapMonthlyKicker => '今月の Wrap';

  @override
  String wrapMonthInMusic(String month) {
    return '音楽で振り返る$month';
  }

  @override
  String wrapUpTo(String day) {
    return '$dayまで';
  }

  @override
  String get wrapListenedFor => '聴いた時間';

  @override
  String wrapAcross(int count, String month) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$monthに$count回再生。');
    return '$_temp0';
  }

  @override
  String wrapAcrossSoFar(int count, String month) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$monthはここまで$count回再生。');
    return '$_temp0';
  }

  @override
  String wrapSummary(int songs, int artists, String song, String artist) {
    return 'トップソング：$song\nトップアーティスト：$artist\n$songs曲、アーティスト$artists組';
  }

  @override
  String get wrapYouPlayed => '聴いた曲';

  @override
  String songsPlural(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count曲');
    return '$_temp0';
  }

  @override
  String wrapByArtists(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'アーティストは$count組。');
    return '$_temp0';
  }

  @override
  String get wrapTopSong => 'トップソング';

  @override
  String playsPlural(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count回再生');
    return '$_temp0';
  }

  @override
  String get wrapTopSongs => 'トップソング一覧';

  @override
  String get wrapTopArtist => 'トップアーティスト';

  @override
  String get wrapTopArtists => 'トップアーティスト一覧';

  @override
  String get wrapTopAlbum => 'トップアルバム';

  @override
  String get wrapBiggestDay => 'いちばん聴いた日';

  @override
  String wrapOfMusic(String listened) {
    return '音楽を$listened。';
  }

  @override
  String get wrapStreakGoing => 'ストリーク継続中';

  @override
  String get wrapLongestStreak => '最長ストリーク';

  @override
  String daysInARow(int count) {
    return '$count日連続';
  }

  @override
  String wrapListenedOnDays(int listened, int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count日のうち$listened日聴いた。');
    return '$_temp0';
  }

  @override
  String wrapListenedOnDaysSoFar(int listened, int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'ここまで$count日のうち$listened日聴いた。');
    return '$_temp0';
  }

  @override
  String get wrapMostReplayed => 'いちばんリピートした曲';

  @override
  String wrapPlayedTimesOn(String artist, int count, String day) {
    return '$artist\n$dayに$count回再生。';
  }

  @override
  String get wrapNewThisMonth => '今月の新顔';

  @override
  String get wrapYearlyKicker => '今年の Wrap';

  @override
  String get wrapNewThisYear => '今年はじめて聴いた曲';

  @override
  String wrapLongestStreakOf(String year) {
    return '$year 年の最長ストリーク';
  }

  @override
  String get yourYearlyWraps => '年間 Wrap';

  @override
  String get thisYearUpToNow => '今年、ここまで';

  @override
  String newSongsPlural(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '新しい曲$count曲');
    return '$_temp0';
  }

  @override
  String get wrapStayedWithKnown => '知ってる曲をずっと聴いてた。';

  @override
  String get wrapNeverPlayed => '今まで聴いたことのなかった曲。';

  @override
  String wrapNewCount(int count) {
    return '、新しい曲$count曲';
  }

  @override
  String get madeWithRiflay => 'Riflay で作成';

  @override
  String get yourListening => 'リスニング';

  @override
  String get yourListeningBody => '30秒以上聴いた曲から計算してる。データはこの端末だけに残る。';

  @override
  String get listeningTime => '聴いた時間';

  @override
  String get topSongs => 'トップソング';

  @override
  String get topArtists => 'トップアーティスト';

  @override
  String get topAlbums => 'トップアルバム';

  @override
  String get yourMonthlyWraps => '毎月の Wrap';

  @override
  String get thisMonthUpToNow => '今月の今まで';

  @override
  String get playFewSongsWrapShort => '何曲か聴くと Wrap が見られる';

  @override
  String couldntFindSong(String title) {
    return '$title が見つかりませんでした';
  }

  @override
  String get statsNothingYet => 'まだ何もない。30秒以上聴いた曲がここに出てくる。';

  @override
  String get historyOff => '再生履歴がオフになってる。「設定 › ライブラリとダウンロード › 再生履歴と Wrap」でオンにしてね。';

  @override
  String listeningTimeChart(String bars) {
    return '聴いた時間のグラフ。$bars';
  }

  @override
  String listeningWith(String host) {
    return '$host と一緒に聴いてる';
  }

  @override
  String get aFriend => '友だち';

  @override
  String get hosting => 'ホスト中';

  @override
  String listeningCount(int count) {
    return '$count人が聴いてる';
  }

  @override
  String get couldntConnect => '接続できませんでした。もう一度試してください。';

  @override
  String get listenTogetherIntro => '友だちと一緒に YouTube の曲を聴こう。';

  @override
  String get yourName => '名前';

  @override
  String get yourNameHelper => '参加したりセッションを始めたりすると、友だちに表示される';

  @override
  String get enterNameFirst => '先に名前を入れてね';

  @override
  String get sameWifi => '同じ Wi-Fi';

  @override
  String get anywhere => 'どこからでも';

  @override
  String get anywhereNote => '無料の公開サーバー経由でつなぐ。すべて暗号化されてるけど、新しい機能なのでつながらないこともある。';

  @override
  String get sameWifiNote => '全員が同じ Wi-Fi につながってる必要がある。';

  @override
  String get startSession => 'セッションを始める';

  @override
  String get scanQr => 'QR コードを読み取る';

  @override
  String get onThisWifi => 'この Wi-Fi で';

  @override
  String get lookingForSessions => 'このネットワークのセッションを探してる…';

  @override
  String get tapToJoin => 'タップで参加';

  @override
  String get haveACode => 'コードを持ってる？';

  @override
  String get joinCodeAnywhere => 'どこにいる友だちでも、このコードで参加できる。';

  @override
  String get joinCodeWifi => '同じ Wi-Fi の友だちは、このコードで参加できる。';

  @override
  String get showQr => 'QR コードを表示';

  @override
  String get listening => '聴いてる人';

  @override
  String get nobodyJoined => 'まだ誰も参加してない。';

  @override
  String get letFriendsAdd => '友だちに曲の追加を許可';

  @override
  String get letFriendsAddSubtitle => '友だちが再生した曲が、来た順にキューに入る';

  @override
  String get letFriendsSeek => '友だちにシークを許可';

  @override
  String get letFriendsSeekSubtitle => '全員の再生位置が変わる';

  @override
  String get youPickSongs => '曲を選ぶのは自分。YouTube の曲を再生すれば、みんなもついてくる。';

  @override
  String get endSession => 'セッションを終了';

  @override
  String waitingForHost(String host) {
    return '$host が何か再生するのを待ってる。';
  }

  @override
  String hostPlayingOwnFiles(String host) {
    return '$host は自分のファイルの曲を再生中。YouTube の曲を再生したら続きが流れる。';
  }

  @override
  String playGoesToHostQueue(String host) {
    return 'YouTube の曲を再生すると、$host のキューに入る。';
  }

  @override
  String hostNotTakingSongs(String host) {
    return '$host は今は曲を受け付けてない。';
  }

  @override
  String get host => 'ホスト';

  @override
  String get upNext => '次の曲';

  @override
  String get seekForEveryone => 'プレイヤーのシークバーで全員の再生位置を動かせる。';

  @override
  String get onlyHostSeeks => 'シークできるのはホストだけ。';

  @override
  String get leave => '退出';

  @override
  String spMixerResamples(String dacRate, String songRate) {
    return 'Riflay は音に手を加えてないけど、システムのミキサーが DAC を $songRate じゃなく $dacRate で動かしてる。';
  }

  @override
  String get spFixedRateOutputs => 'iPhone、iPad、Bluetooth の出力はレート固定。USB DAC ならたいてい曲ごとに合わせる。';

  @override
  String get spTurnOnBitPerfect => 'そのまま送るなら「設定 › サウンド › 出力と音質」で Bit-perfect モードをオンにしてね。';

  @override
  String get spMixerMayResample => 'Riflay では何も音を変えてないけど、システムのミキサーがリサンプリングするかもしれない。';

  @override
  String get spIosAlwaysMixes => 'iOS は常に音をミックスするので、ここでは Bit-perfect にならない。';

  @override
  String get spForBitPerfectExclusive =>
      'Bit-perfect にするなら「設定 › サウンド › 出力と音質」で Bit-perfect モードと排他モードをオンにしてね（その間ほかのアプリは鳴らない）。';

  @override
  String get spForBitPerfect => 'Bit-perfect にするなら「設定 › サウンド › 出力と音質」で Bit-perfect モードをオンにしてね。';

  @override
  String get spDsdToPcmExclusive =>
      'DSD は高レートの PCM にデコードされる。DSD のまま DAC に送るなら「設定 › サウンド › 出力と音質」で Bit-perfect モード、排他モード、ネイティブ DSD（DoP）をオンにしてね。';

  @override
  String get spDsdToPcmHowTo =>
      'DSD は高レートの PCM にデコードされる。DSD のまま DAC に送るなら「設定 › サウンド › 出力と音質」で Bit-perfect モードとネイティブ DSD（DoP）をオンにしてね。';

  @override
  String spUsbDacRateUnsupported(String dac, String songRate, String outRate) {
    return '$dac は $songRate に対応してないので、Android が $outRate で再生してる。';
  }

  @override
  String get qualityLossy => '非可逆';

  @override
  String get qualityLossless => 'ロスレス';

  @override
  String get nativeDsd2 => 'ネイティブ DSD';

  @override
  String get spNativeDsdBody =>
      'DSD のストリームが DoP に包まれてそのまま DAC に届く。DoP 対応の DAC なら DSD と表示され、非対応だとかすかなノイズが出る（そのときはネイティブ DSD をオフにしてね）。';

  @override
  String get spDopChanged => 'DoP が変えられてる';

  @override
  String get spDopChangedBody =>
      'Riflay と DAC の間で何かがサンプルを変えてるので、DAC が DSD だと認識できない。「設定 › サウンド › 出力と音質」で direct の出力を選んでね。';

  @override
  String spUsbBitPerfect(String dac) {
    return 'USB DAC、Bit-perfect（Android 14）：すべてのサンプルがファイルのまま $dac に届く。';
  }

  @override
  String get spNotBitPerfect => 'Bit-perfect じゃない';

  @override
  String get spBitPerfectBody => 'すべてのサンプルがファイルのまま DAC に届く。';

  @override
  String get spResampledByMixer => 'システムのミキサーがリサンプリング';

  @override
  String get spLosslessToMixer => 'システムのミキサーまではロスレス';

  @override
  String get spDsdConverted => 'DSD を PCM に変換';

  @override
  String get spDsdIos => 'DSD は高レートの PCM にデコードされる。iOS は DSD を DSD のまま DAC に送れない。';

  @override
  String get spProcessed => '加工あり';

  @override
  String get spProcessedBody => '下のどれかがサンプルを変えてる。それが狙いなら問題なし。';

  @override
  String get spSource => 'ソース';

  @override
  String get spLosslessParen => '（ロスレス）';

  @override
  String get spDecoded => 'デコード';

  @override
  String spPadded(int bits) {
    return '（${bits}bit、ロスレスで補完）';
  }

  @override
  String get spUntouched => '100%（そのまま）';

  @override
  String get spMuted => 'ミュート';

  @override
  String get spClipProtection => 'クリップ保護';

  @override
  String get spClipProtectionBody => 'フルスケールを超えたピークを切らずになめらかに抑える';

  @override
  String get spResampled => 'リサンプリング';

  @override
  String get spDacReceives => 'DAC が受け取るもの';

  @override
  String get spMono => 'モノラル';

  @override
  String get spStereo => 'ステレオ';

  @override
  String spChannels(String count) {
    return '$countチャンネル';
  }

  @override
  String get spPipewire => 'PipeWire（システムのミキサー）';

  @override
  String get spPulse => 'PulseAudio（システムのミキサー）';

  @override
  String get spAlsaDirect => 'ALSA、ハードウェアに直接';

  @override
  String get spWasapiExclusive => 'WASAPI 排他';

  @override
  String get spWasapiShared => 'WASAPI 共有';

  @override
  String get spAndroidMixer => 'Android のミキサー';

  @override
  String get spAndroidMixerParen => '（Android のミキサー）';

  @override
  String get spIosSession => 'iOS のオーディオセッション（システムのミキサー）';

  @override
  String get couldntOpenBrowser => 'ブラウザを開けませんでした。';

  @override
  String versionNamed(String version) {
    return 'バージョン $version';
  }

  @override
  String get version => 'バージョン';

  @override
  String get copy => 'コピー';

  @override
  String get copied => 'コピーした';

  @override
  String get whatsNew => '新機能';

  @override
  String get whatsNewSubtitle => 'リリースノートと各プラットフォームのダウンロード';

  @override
  String get reportProblem => '問題を報告';

  @override
  String get reportProblemSubtitle => '新しい issue を開く。バージョン情報を貼り付けてね';

  @override
  String get supportArtists => 'アーティストを応援';

  @override
  String get supportArtistsSubtitle => '音楽を楽しんでる？ YouTube Music Premium なら作り手に収益が届く';

  @override
  String get supportRiflay => 'Riflay を応援';

  @override
  String get supportRiflaySubtitle => 'Tako でギフトを送って開発を応援';

  @override
  String get sourceCode => 'ソースコード';

  @override
  String get sourceCodeSubtitle => 'Riflay はオープンソース。GitHub にある';

  @override
  String get licence => 'ライセンス';

  @override
  String get openSourceLicences => 'オープンソースライセンス';

  @override
  String get openSourceLicencesSubtitle => 'Riflay が使ってるライブラリ';

  @override
  String get scrobbleBody => '半分（または4分）を過ぎるまで聴いた曲が、そっちのプロフィールに記録される。オフラインで聴いた分は、オンラインに戻ったら送られる。';

  @override
  String get connect => '接続';

  @override
  String get notConnected => '未接続';

  @override
  String connectedAs(String user) {
    return '$user として接続中';
  }

  @override
  String get connected => '接続済み';

  @override
  String get noNewListens => '取り込む新しい再生記録はない';

  @override
  String listensAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '再生記録を$count件、履歴に追加した');
    return '$_temp0';
  }

  @override
  String serviceSignedOut(String service) {
    return '$service からログアウトされました。もう一度接続してください。';
  }

  @override
  String couldntReachService(String service) {
    return '$service に接続できませんでした。もう一度試してください。';
  }

  @override
  String readingListens(String count) {
    return '再生記録を読み込み中：今$count件';
  }

  @override
  String get turnOnHistoryFirst => '先に「ライブラリとダウンロード」で再生履歴をオンにしてね。';

  @override
  String get bringInBody => 'ほかで聴いた曲を統計、Wrap、よく聴く曲に追加する。もうあるものはスキップ。';

  @override
  String bringInHistory(String service) {
    return '$service の履歴を取り込む';
  }

  @override
  String get stop => '停止';

  @override
  String get bringIn => '取り込む';

  @override
  String connectService(String service) {
    return '$service に接続';
  }

  @override
  String get listenBrainzTokenBody => 'ListenBrainz の設定からユーザートークンをコピーして、ここに貼り付けてね。';

  @override
  String get openListenBrainzSettings => 'ListenBrainz の設定を開く';

  @override
  String get userToken => 'ユーザートークン';

  @override
  String get signInTooLong => 'ログインに時間がかかりすぎました。もう一度試してください。';

  @override
  String get lastfmDidntFinish => 'Last.fm のログインが完了しませんでした。もう一度試してください。';

  @override
  String get lastfmAllowBody => 'ブラウザで開いた Last.fm のページで Riflay を許可してね。許可したらこれは自動で閉じる。';

  @override
  String get openLastfmAgain => 'Last.fm をもう一度開く';

  @override
  String get spotifyReadFailed => '今は Spotify のライブラリを読み込めませんでした。あとでもう一度試してください。';

  @override
  String get needsWebkit => 'ログインには WebKitGTK（webkit2gtk-4.1）が必要です。インストールして Riflay を再起動してください。';

  @override
  String get spotifySignInUnavailable => 'ここでは Spotify にログインできません。';

  @override
  String get spotifyIntro => 'Spotify のプレイリスト、お気に入りの曲、アルバムを Riflay にコピーしよう。';

  @override
  String get spotifyReadOnly => 'Riflay はライブラリを読むだけ。Spotify のアカウントは一切変えない。';

  @override
  String get signInWithSpotify => 'Spotify でログイン';

  @override
  String get playlistsGoToYt => 'プレイリストは YouTube Music のライブラリに入る。';

  @override
  String get playlistsBecomeRiflay => 'プレイリストは Riflay のプレイリストになる。';

  @override
  String get signedInToSpotify => 'Spotify にログイン中';

  @override
  String get signOut => 'ログアウト';

  @override
  String get nothingHereYet => 'まだ何もない。';

  @override
  String get imported => '取り込み済み';

  @override
  String get importAll => 'すべて取り込む';

  @override
  String importCount(String count) {
    return '$count件を取り込む';
  }

  @override
  String get import => '取り込む';

  @override
  String get importing => '取り込み中';

  @override
  String get stopping => '停止中…';

  @override
  String findingSongsInYt(String matched, String total) {
    return 'YouTube Music で曲を検索中：$total曲中$matched曲';
  }

  @override
  String get findingArtistInYt => 'YouTube Music でアーティストを検索中…';

  @override
  String get readingTheSongs => '曲を読み込み中…';

  @override
  String importedOf(String done, String total) {
    return '$total件中$done件を取り込んだ';
  }

  @override
  String get youStoppedImport => '取り込みを止めた。';

  @override
  String get pronunciation => '読み方';

  @override
  String get translation => '翻訳';

  @override
  String get copyLyrics => '歌詞をコピー';

  @override
  String get adjustTiming => 'タイミングを調整';

  @override
  String get removeMyLyrics => '自分の歌詞を削除';

  @override
  String get playerOptions => 'プレイヤーのオプション';

  @override
  String get chooseLyricsFile => '歌詞ファイルを選ぶ';

  @override
  String get lyricsFileTooBig => '歌詞にしては大きすぎるファイルです。';

  @override
  String get yourLyricsInUse => '自分の歌詞を使ってる';

  @override
  String get couldntReadFile => 'そのファイルを読み込めませんでした。';

  @override
  String get couldntRemoveLyrics => '自分の歌詞を削除できませんでした。';

  @override
  String get onTime => 'ぴったり';

  @override
  String secondsEarlier(String seconds) {
    return '$seconds秒早く';
  }

  @override
  String secondsLater(String seconds) {
    return '$seconds秒遅く';
  }

  @override
  String get adjustTimingBody => '歌詞が早すぎたり遅すぎたりするなら、曲に合うまでずらしてね。';

  @override
  String get earlier => '早く';

  @override
  String get later => '遅く';

  @override
  String get lyricsCopied => '歌詞をコピーした';

  @override
  String get couldntTranslateLyrics => 'この歌詞を翻訳できませんでした。ネット接続を確認してください。';

  @override
  String get privacyPublicLabel => '公開';

  @override
  String get privacyUnlistedLabel => '限定公開';

  @override
  String get privacyPrivateLabel => '非公開';

  @override
  String joinedPlaylist(String title) {
    return '「$title」に参加した';
  }

  @override
  String get thePlaylist => 'プレイリスト';

  @override
  String get sharedPlaylist => '共有プレイリスト';

  @override
  String get ytSignInPrompt => 'YouTube Music にログインすると、お気に入りの曲、プレイリスト、履歴を追加できる。';

  @override
  String get signingIn => 'ログイン中…';

  @override
  String get ytLoadFailed => 'YouTube Music を読み込めませんでした。ネット接続を確認してください。';

  @override
  String get playlistLoadFailed => 'このプレイリストを読み込めませんでした。ネット接続を確認してください。';

  @override
  String playlistIsNow(String privacy) {
    return 'プレイリストを$privacyにした';
  }

  @override
  String deleteYtPlaylistBody(String title) {
    return '「$title」が YouTube Music のライブラリから削除されます。元に戻せません。';
  }

  @override
  String get shared => '共有中';

  @override
  String makePrivacy(String privacy) {
    return '$privacyにする';
  }

  @override
  String get chooseDownloadsFolder => 'ダウンロードの保存先を選ぶ';

  @override
  String get bestSoundNote => '曲ごとに YouTube にある一番いい音。';

  @override
  String get smallerFilesNote => 'ファイルは小さめ、音の厚みは少し落ちる。';

  @override
  String closestVersionNote(String base) {
    return '${base}YouTube にある一番近いものを使う。';
  }

  @override
  String get whatToSave => '保存するもの';

  @override
  String get saveAs => '保存形式';

  @override
  String get saveAsVideoNote => 'MVを音声つきで。MVがない曲は音声で保存。';

  @override
  String get saveAsAudioNote => '音声だけ。MVも残すなら「動画」を選んでね。';

  @override
  String get videoFormat => '動画の形式';

  @override
  String get size => 'サイズ';

  @override
  String get videoSizeNote => '選んだ高さまでで、動画にある一番高い解像度。1080p ならファイルが大きすぎず、くっきり見える。';

  @override
  String get bestAvailable => '最高画質';

  @override
  String heightRecommended(String height) {
    return '${height}p（おすすめ）';
  }

  @override
  String get format => '形式';

  @override
  String flacUnavailable(String about) {
    return '$about\nこの端末では FLAC を使えない。';
  }

  @override
  String get bitDepthSampleRate => 'ビット深度とサンプルレート';

  @override
  String get bitrate => 'ビットレート';

  @override
  String get askEveryTime => '毎回聞く';

  @override
  String get askEveryTimeSubtitle => '曲をダウンロードするたびに形式と音質を選ぶ。';

  @override
  String get where => '保存先';

  @override
  String get downloadOverMobile => 'モバイルデータでダウンロード';

  @override
  String get downloadOverMobileOn => 'Wi-Fi だけじゃなく、モバイルデータでもダウンロードする。';

  @override
  String get downloadOverMobileOff => 'Wi-Fi になるまで待つので、データ通信量を使わない。';

  @override
  String get downloadsFolder => 'ダウンロードフォルダ';

  @override
  String phoneDownloadsFixed(String path) {
    return '$path\nスマホでは Riflay 専用の領域に保存するので、変えられない。';
  }

  @override
  String get openFolder => 'フォルダを開く';

  @override
  String get ytDlp => 'YouTube ダウンローダー（yt-dlp）';

  @override
  String get ytDlpMissing => '見つからない。YouTube からダウンロードするならインストールしてね（例：pacman -S yt-dlp）。';

  @override
  String removeNamedQuestion(String name) {
    return '$name を削除しますか？';
  }

  @override
  String get removeExtensionBody => 'ファイルと、この端末に保存したデータが削除されます。';

  @override
  String couldntRemoveNamed(String name) {
    return '$name を削除できませんでした';
  }

  @override
  String get extensionsIntro =>
      'SpotiFLAC 向けの拡張機能で、Apple Music、SoundCloud、JioSaavn などの検索先を増やせる。曲は YouTube Music から再生する。信頼できるリポジトリだけ追加してね。拡張機能は独自のコードを動かし、マニフェストに書かれたサイトにアクセスできる。';

  @override
  String get repositories => 'リポジトリ';

  @override
  String get installed => 'インストール済み';

  @override
  String get noExtensionsYet => '拡張機能はまだない';

  @override
  String get installFromRepo => '下のリポジトリからインストールしてね';

  @override
  String get available => '利用可能';

  @override
  String get repositoryAddress => 'リポジトリのアドレス';

  @override
  String get reading => '読み込み中…';

  @override
  String couldntReadIt(String error) {
    return '読み込めませんでした：$error';
  }

  @override
  String get notReadYet => 'まだ読み込んでない';

  @override
  String extensionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '拡張機能$count個');
    return '$_temp0';
  }

  @override
  String get removeRepository => 'リポジトリを削除';

  @override
  String get addsToSearch => '検索結果に追加';

  @override
  String get downloadsUnsupported => 'ダウンロードはまだ未対応';

  @override
  String get lyricsUnsupported => '歌詞はまだ未対応';

  @override
  String get needsSpotiflacFeatures => 'Riflay にない SpotiFLAC の機能が必要なので、動かないかも';

  @override
  String updateTo(String version) {
    return '$version に更新';
  }

  @override
  String couldntUpdateNamed(String name) {
    return '$name を更新できませんでした';
  }

  @override
  String couldntInstallNamed(String name) {
    return '$name をインストールできませんでした';
  }

  @override
  String get install => 'インストール';

  @override
  String get scPlayPause => '再生／一時停止';

  @override
  String get scNext => '次の曲';

  @override
  String get scPrevious => '前の曲';

  @override
  String get scVolumeUp => '音量を上げる';

  @override
  String get scVolumeDown => '音量を下げる';

  @override
  String get scBack => '戻る';

  @override
  String get scForward => '進む';

  @override
  String get scPasteLink => 'コピーした YouTube のリンクを取り込む';

  @override
  String get scFullScreen => '全画面プレイヤー';

  @override
  String get scHelp => 'この一覧を表示';

  @override
  String get scSlashOr => '? または Ctrl+/';

  @override
  String get saveABackup => 'バックアップを保存';

  @override
  String get backupSaved => 'バックアップを保存した';

  @override
  String get couldntSaveBackup => 'バックアップを保存できませんでした。';

  @override
  String get chooseBackup => 'Riflay のバックアップを選ぶ';

  @override
  String get backupNeedsNewer => 'このバックアップには新しい Riflay が必要です。';

  @override
  String get notABackup => 'それは Riflay のバックアップファイルじゃありません。';

  @override
  String get restoreBackupQuestion => 'このバックアップを復元しますか？';

  @override
  String restoreBackupBody(int playlists, int plays, int lyrics, String made) {
    return '$madeプレイリスト$playlists個、再生履歴$plays回分、歌詞ファイル$lyrics個が入ってます。この端末の設定、プレイリスト、履歴は置き換わります。ログイン情報はそのまま残ります。';
  }

  @override
  String get restore => '復元';

  @override
  String get couldntRestoreBackup => 'バックアップを復元できませんでした。';

  @override
  String get backupRestored => 'バックアップを復元した';

  @override
  String get backupRestoredIos => '仕上げに、アプリスイッチャーで Riflay を閉じてから開き直してください。';

  @override
  String get backupRestoredDesktop => 'Riflay を閉じます。仕上げにもう一度開いてください。';

  @override
  String get closeRiflay => 'Riflay を閉じる';

  @override
  String madeOn(String date) {
    return '$dateに作成。';
  }

  @override
  String get saveABackupSubtitle => '設定、プレイリスト、再生履歴、自分の歌詞をひとつのファイルに。ログイン情報は含まない。';

  @override
  String get restoreABackup => 'バックアップを復元';

  @override
  String get restoreABackupSubtitle => 'この端末か新しい端末で元に戻せる。';

  @override
  String dupRemovedSomeFailed(int removed, int failed) {
    return '$removed個のコピーを外しました。$failed個のファイルは削除できませんでした。';
  }

  @override
  String dupRemovedAndDeleted(int removed, int deleted, String size) {
    return '$removed個のコピーを外して$deleted個のファイルを削除し、$size空いた。';
  }

  @override
  String dupRemovedFromLibrary(int removed) {
    return 'ライブラリから$removed個のコピーを外した。';
  }

  @override
  String get songsYouHaveTwice => '重複してる曲';

  @override
  String get lookingThroughLibrary => 'ライブラリを調べてる…';

  @override
  String get noDuplicates => 'ライブラリに重複してる曲はない。';

  @override
  String get duplicatesBody => '同じ曲が複数のファイルにある。それぞれ一番いいコピーを選んであるので、変えたければ選び直して、残りを外してね。';

  @override
  String get nothingToRemove => '外すものはない';

  @override
  String removeExtraCopies(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '余分なコピー$count個を外す');
    return '$_temp0';
  }

  @override
  String upToCanBeFreed(String size) {
    return '最大$size空けられる。';
  }

  @override
  String get chooseOne => 'ひとつ選ぶ';

  @override
  String get keepAll => '全部残す';

  @override
  String get bestQuality => '最高音質';

  @override
  String get downloadedByRiflay => 'Riflay でダウンロード';

  @override
  String get yourFile => '自分のファイル';

  @override
  String get keep => '残す';

  @override
  String removeCopiesQuestion(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count個のコピーを外しますか？');
    return '$_temp0';
  }

  @override
  String get removeCopiesBody => 'ライブラリから外れて、残すコピーはそのまま。外したコピーが入ってたプレイリストは、残すほうを使う。';

  @override
  String get alsoDeleteFiles => 'この端末からファイルも削除する';

  @override
  String freesSize(String size) {
    return '$size空きます。削除したファイルは元に戻せません。';
  }

  @override
  String ownFilesCount(int count) {
    return '自分のファイル$count個';
  }

  @override
  String downloadsRiflaySaved(int count) {
    return 'Riflay がダウンロードしたもの$count個';
  }

  @override
  String get listAnd => 'と';

  @override
  String filesUsedElsewhere(int count) {
    return '$count個のファイルはほかの曲が使ってるので残る。';
  }

  @override
  String get deleteFiles => 'ファイルを削除';

  @override
  String couldntPlay(String title) {
    return '$title を再生できませんでした';
  }

  @override
  String get ytSearchFailed => 'YouTube の検索に失敗しました。接続を確認してください。';

  @override
  String get noYtResults => 'YouTube の結果はない。';

  @override
  String get ytSearchSource => 'YouTube 検索';

  @override
  String get topResult => 'トップの結果';

  @override
  String get nothingFound => '何も見つからない。';

  @override
  String get noYtVideos => 'YouTube の動画は見つからない。';

  @override
  String get ytVideosSource => 'YouTube の動画';

  @override
  String get couldntReadSongInfo => 'この曲の情報を読み込めませんでした';

  @override
  String get saved => '保存した';

  @override
  String get couldntSaveChanges => '変更を保存できませんでした';

  @override
  String get chooseCoverArt => 'ジャケット画像を選ぶ';

  @override
  String get noCoverFound => 'このアルバムのジャケットは見つからなかった';

  @override
  String get couldntReachCoverArchive => 'Cover Art Archive に接続できませんでした';

  @override
  String get changeCover => 'ジャケットを変更';

  @override
  String get searching => '検索中…';

  @override
  String get findOnline => 'ネットで探す';

  @override
  String get largeImageHint => 'くっきりしたジャケットにするなら大きい画像（1000 px 以上）を使ってね。';

  @override
  String get trackNumber => 'トラック';

  @override
  String get discNumber => 'ディスク';

  @override
  String get year => '年';

  @override
  String get genre => 'ジャンル';

  @override
  String get ytSignInAgain => 'もう一度 YouTube Music にログインしてください。';

  @override
  String get ytBusy => 'YouTube Music が混み合ってます。少ししてからもう一度試してください。';

  @override
  String get ytNotAnswering => 'YouTube Music から応答がありません。あとでもう一度試してください。';

  @override
  String get couldntFinishSignIn => 'ログインを完了できませんでした。もう一度試してください。';

  @override
  String get signInDidntFinish => 'ログインが完了しませんでした。もう一度試してください。';

  @override
  String get moodsAndGenres => 'ムードとジャンル';

  @override
  String get performance => 'パフォーマンス';

  @override
  String get keepScreenOn => '画面をつけたままにする';

  @override
  String get keepScreenOnPhone => '画面が勝手に消えないようにする。バッテリーを使う';

  @override
  String get keepScreenOnDesktop => '画面が勝手に消えたりロックされたりしないようにする';

  @override
  String get dontSleepWhilePlaying => '再生中はスリープしない';

  @override
  String get dontSleepSubtitle => '音楽の再生中はパソコンをスリープさせない。画面は消えることがある';

  @override
  String get closeToTray => 'トレイに閉じる';

  @override
  String get noTrayIcons => 'このデスクトップはトレイアイコンを表示しないので、ウィンドウを閉じると Riflay が終了する';

  @override
  String get closeToTraySubtitle => 'ウィンドウを閉じても Riflay はトレイで再生を続ける。終了はトレイアイコンから';

  @override
  String get keepPlayingScreenOff => '画面オフでも再生を続ける';

  @override
  String get batteryExemptOn => 'オン。スマホが Riflay をスリープさせない';

  @override
  String get batteryExemptOff => 'オフ。しばらくするとスマホが音楽を止めるかも';

  @override
  String get allow => '許可';

  @override
  String get openBatterySettings => 'バッテリーの設定を開く';

  @override
  String get keepMusicPlaying => '音楽を流し続ける';

  @override
  String get keepMusicPlayingBody => 'スマホによっては、画面が消えてしばらくすると音楽が止まる。Riflay のバックグラウンド実行を許可すれば再生が続く。あとから設定で変えられる。';

  @override
  String get notNow => '今はしない';

  @override
  String get couldntSaveChangesRetry => '変更を保存できませんでした。もう一度試してください。';

  @override
  String get editSong => '曲を編集';

  @override
  String get artistNamesStay => 'アーティスト名はリリースされたままにしておく。';

  @override
  String get yourLyrics => '自分の歌詞';

  @override
  String get yourLyricsBody => 'ネットで見つけた歌詞の代わりに表示する。行の頭に [01:23.45] みたいな時間をつけると曲に合わせて動く。';

  @override
  String get pasteLyricsHere => 'ここに歌詞を貼り付け';

  @override
  String get addFromFile => 'ファイルから追加';

  @override
  String importedNamed(String title) {
    return '「$title」を取り込んだ';
  }

  @override
  String get pastePlaylistLink => 'Spotify、Apple Music、Deezer のプレイリストのリンクを貼り付けてね。';

  @override
  String get becomesYtPlaylist => 'YouTube Music のライブラリのプレイリストになる。';

  @override
  String get becomesRiflayPlaylist => 'YouTube Music の曲で Riflay のプレイリストになる。';

  @override
  String get playlistLink => 'プレイリストのリンク';

  @override
  String get notAPlaylistLink => 'それは Spotify、Apple Music、Deezer のプレイリストのリンクじゃない';

  @override
  String get readingPlaylist => 'プレイリストを読み込み中…';

  @override
  String get saving => '保存中…';

  @override
  String songsAddedOf(String saved, String total) {
    return '$total曲中$saved曲を追加した。';
  }

  @override
  String songsAddedOfYt(String saved, String total) {
    return '$total曲中$saved曲を YouTube Music のライブラリに追加した。';
  }

  @override
  String firstSongsOnly(int count, String service) {
    return '$service はログインしないと最初の$count曲しか出さないので、残りは入れられなかった。';
  }

  @override
  String songsNotOnYt(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'YouTube Music にない曲が$count曲：');
    return '$_temp0';
  }

  @override
  String get openPlaylist => 'プレイリストを開く';

  @override
  String get fmtOpusAbout => '同じ音でファイルが一番小さい。Riflay とほとんどのプレイヤーで再生できる。';

  @override
  String get fmtM4aAbout => '一番対応してる機器が多い。ほぼすべてのスマホ、テレビ、スピーカーで再生できる。';

  @override
  String get fmtFlacAbout => 'FLAC が必要なプレイヤーやライブラリ向けのロスレスファイル。YouTube の音をそのまま残すだけで、良くはならない。';

  @override
  String get fmtMp3About => '古いプレイヤーやカーステ向け。YouTube の音声から作るので、Opus や M4A より良くなることはない。';

  @override
  String get kindAudio => '音声';

  @override
  String get kindVideo => '動画';

  @override
  String get vidMp4About => '映像は H.264、音声は AAC。ほぼすべてのスマホ、テレビ、パソコンで再生できる。';

  @override
  String get vidWebmAbout => '映像は VP9、音声は Opus。ファイルが小さく、一番高い解像度もある。Riflay とほとんどのパソコンで再生できる。';

  @override
  String get flacStandardAbout => 'YouTube の音声と同じサンプルレート。どこでも再生できる。';

  @override
  String get flacCdAbout => 'CD 品質。それが必要なプレイヤーや書き込みソフト向け。';

  @override
  String get flacHiResAbout => 'ファイルは大きめ。24bit でそろえたライブラリ向け。';

  @override
  String kbpsBest(String kbps) {
    return '$kbps kbps（最高）';
  }

  @override
  String videoChoice(String container, String height) {
    return '動画 · $container · $height';
  }

  @override
  String get bestAvailableLower => '最高画質';

  @override
  String get waitingToStart => '開始待ち';

  @override
  String get noteDownloading => 'ダウンロード中';

  @override
  String downloadedTitle(String title) {
    return '$title をダウンロードした';
  }

  @override
  String get savedToLibrary => 'ライブラリに保存した';

  @override
  String couldntDownloadTitle(String title) {
    return '$title をダウンロードできませんでした';
  }

  @override
  String get tapRetry => '「再試行」をタップするともう一度試せます。';

  @override
  String downloadingSongsNote(int count) {
    return '$count曲をダウンロード中';
  }

  @override
  String get openRiflay => 'Riflay を開く';

  @override
  String get downloadsChannelDescription => 'ダウンロード中の曲の進み具合';

  @override
  String servicePlaylist(String service) {
    return '$service のプレイリスト';
  }

  @override
  String get clearHistoryQuestion => '再生履歴を消しますか？';

  @override
  String clearHistoryBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'この端末から再生記録を$count件削除します。ライブラリとプレイリストはそのままですが、統計、Wrap、よく聴く曲などはリセットされます。',
    );
    return '$_temp0';
  }

  @override
  String get historyCleared => '再生履歴を消した';

  @override
  String get keepHistory => 'この端末に再生履歴を残す';

  @override
  String get keepHistorySubtitle => 'リスニング統計、毎月の Wrap、よく聴く曲などに使う。どこにも送られない。オフにすると記録が止まり、保存済みの分は消すまで残る。';

  @override
  String get wrapNotification => '毎月の Wrap の通知';

  @override
  String get wrapNotificationSubtitle => '毎月1日に、先月の Wrap ができたら知らせる。';

  @override
  String get clearHistory => '再生履歴を消す';

  @override
  String get nothingSavedYet => 'まだ何も保存されてない';

  @override
  String playsSaved(int count) {
    return 'この端末に再生記録$count件';
  }

  @override
  String get lyricsFile => '歌詞ファイル';

  @override
  String get embeddedInFile => 'ファイルに埋め込み';

  @override
  String get addLyricsFirst => '先に歌詞を入れてね。';

  @override
  String get lrcTimesWrong => '歌詞の時間の書き方に間違いがある。各行の頭に [01:23.45] みたいな時間をつけてね。';

  @override
  String get lrcTimesPastEnd => '時間が曲の長さを超えてる。この曲の歌詞か確認してね。';

  @override
  String get couldntStartSession => 'セッションを始められませんでした。Wi-Fi につながってるか確認してください。';

  @override
  String get sessionStopped => 'セッションが止まりました。一緒に聴き続けるなら、もう一度始めてください。';

  @override
  String nameLeft(String name) {
    return '$name が抜けた';
  }

  @override
  String get someone => '誰か';

  @override
  String nameAddedToQueue(String name, String title) {
    return '$name が $title をキューに追加した';
  }

  @override
  String get sessionNotFound => 'そのセッションが見つかりませんでした。コードと、同じ Wi-Fi につながってるか確認してください。';

  @override
  String get sessionNotAnswering => 'そのセッションから応答がありません。少ししてからもう一度試してください。';

  @override
  String get theHostCap => 'ホスト';

  @override
  String hostEndedSession(String host) {
    return '$host がセッションを終了した';
  }

  @override
  String get sessionEndedOrDropped => 'セッションが終わったか、接続が切れました。';

  @override
  String get lostHostConnection => 'ホストとの接続が切れました。聴き続けるならもう一度参加してください。';

  @override
  String get listeningTogetherSource => '一緒に聴く';

  @override
  String get youLeftSession => 'セッションから抜けた';

  @override
  String onlyYtToHostQueue(String host) {
    return '$host のキューに追加できるのは YouTube Music の曲だけです。';
  }

  @override
  String get checkGithubUpdate => 'GitHub で Riflay の新しいバージョンを確認する';

  @override
  String get checkingUpdates => 'アップデートを確認中…';

  @override
  String get latestVersion => '最新バージョンです';

  @override
  String versionAvailable(String version) {
    return 'バージョン $version が出てます';
  }

  @override
  String downloadingVersion(String version) {
    return 'バージョン $version をダウンロード中…';
  }

  @override
  String versionReady(String version) {
    return 'バージョン $version をインストールできます';
  }

  @override
  String get openingInstaller => 'Android のインストーラーを開いてる…';

  @override
  String get completeInInstaller => 'Android のインストーラーでアップデートを完了してね';

  @override
  String get allowInstallUpdates => 'Riflay にアップデートのインストールを許可してから、もう一度試してね';

  @override
  String get differentSigningKey => 'このコピーは別の署名キーを使ってます。リリース版をインストールする前にデータをバックアップしてください';

  @override
  String get couldntVerifyUpdate => 'アップデートを検証できませんでした。もう一度ダウンロードしてください';

  @override
  String get couldntCheckUpdates => 'アップデートを確認できませんでした。もう一度試してください';

  @override
  String get couldntUpdateRiflay => 'Riflay を更新できませんでした。もう一度試してください';

  @override
  String get installUpdate => 'アップデートをインストール';

  @override
  String get checkForUpdates => 'アップデートを確認';

  @override
  String get downloadUpdate => 'アップデートをダウンロード';

  @override
  String get getUpdate => 'アップデートを入手';

  @override
  String get spotifySignInExpired => 'Spotify のログインが切れました。もう一度ログインしてください。';

  @override
  String get recommended => 'おすすめ';

  @override
  String bestAvailableWith(String label) {
    return '最高画質（$label）';
  }

  @override
  String get downloadAsTitle => '形式を選んでダウンロード';

  @override
  String get downloadTrackTitle => '曲をダウンロード';

  @override
  String get audioFormat => '音声の形式';

  @override
  String get bitrateQuality => 'ビットレート';

  @override
  String get fmtTagUniversal => 'どこでも再生';

  @override
  String get fmtTagModern => '新しめ';

  @override
  String downloadFormatAction(String format) {
    return '$formatでダウンロード';
  }

  @override
  String savedToFolder(String folder) {
    return '保存先: $folder';
  }

  @override
  String get couldntLookUpSizes => '動画のサイズを調べられませんでした。';

  @override
  String get smallerFilesClosest => 'ファイルは小さめ、音の厚みは少し落ちる。YouTube にある一番近いものを使う。';

  @override
  String get musicFolders => '音楽フォルダ';

  @override
  String get keepLibraryUpToDate => 'ライブラリを最新に保つ';

  @override
  String get keepLibraryOpen => 'Riflay を開くたびに、音楽フォルダの新しい曲を追加し、削除や移動した曲を外す。';

  @override
  String get keepLibraryWatch => 'フォルダを追加し直さなくても、音楽フォルダの新しい曲を追加し、削除や移動した曲を外す。';

  @override
  String get checkNow => '今すぐ確認';

  @override
  String get addFolderFirst => '先にライブラリから音楽フォルダを追加してね。';

  @override
  String get checkingDots => '確認中…';

  @override
  String lookAtFoldersAgain(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '音楽フォルダ（$count個）をもう一度見る。');
    return '$_temp0';
  }

  @override
  String get stopWatching => '監視をやめる';

  @override
  String get tidyUp => '整理';

  @override
  String get findDuplicates => '重複してる曲を探す';

  @override
  String get findDuplicatesSubtitle => '同じ曲が別のファイルにあるものを探して、一番いいのを残せる。';

  @override
  String get sessionQr => 'セッションの QR コード';

  @override
  String get sessionQrSemantics => 'リスニングセッションの QR コード';

  @override
  String get sessionQrHowTo => 'ほかの端末の Riflay で「一緒に聴く」を開いて「QR コードを読み取る」を選んでね。';

  @override
  String get notASessionQr => 'その QR コードは Riflay のセッションコードじゃありません。';

  @override
  String get noSessionInImage => 'その画像に Riflay のセッションコードが見つかりませんでした。';

  @override
  String get couldntReadImage => 'その画像を読み込めませんでした。別の画像を試してください。';

  @override
  String get cameraUnavailable => 'カメラが使えません。端末の設定でカメラへのアクセスを許可するか、QR の画像を開いてください。';

  @override
  String get openQrImageToJoin => '参加するには、セッションの QR コードの画像を開いてね。';

  @override
  String get pointCamera => 'Riflay に表示されたセッションの QR コードにカメラを向けてね。';

  @override
  String get readingImage => '画像を読み込み中…';

  @override
  String get openQrImage => 'QR の画像を開く';

  @override
  String get motionGlide => 'グライド';

  @override
  String get motionFadeThrough => 'フェードスルー';

  @override
  String get motionSoftZoom => 'ソフトズーム';

  @override
  String get motionSlide => 'スライド';

  @override
  String get motionCurtain => 'カーテン';

  @override
  String get motionCircular => 'サークル';

  @override
  String get motionSide => 'サイド';

  @override
  String get motionDiamond => 'ダイヤ';

  @override
  String get speedFast => '速い';

  @override
  String get speedRelaxed => 'ゆったり';

  @override
  String serviceSignedOutSettings(String service) {
    return '$service からログアウトされました。設定からもう一度接続してください。';
  }

  @override
  String lostConnectionTo(String device) {
    return '$device との接続が切れました';
  }

  @override
  String couldntPlayOn(String device) {
    return '$device で再生できませんでした';
  }

  @override
  String get pasteYtLink => 'YouTube の動画かプレイリストのリンクを貼り付けてね。';

  @override
  String get linkLoadFailed => 'そのリンクを読み込めませんでした。非公開か、削除されたか、地域制限があるのかもしれません。';

  @override
  String get importFromYtBody => '音声をダウンロードしてライブラリに追加する。';

  @override
  String get paste => '貼り付け';

  @override
  String get bestQualityNote => 'YouTube にある最高音質（最大約 160 kbps の Opus/AAC）で、再エンコードせずに保存する。';

  @override
  String downloadCount(String count) {
    return '$count件をダウンロード';
  }

  @override
  String aboutSize(String size) {
    return '約$size';
  }

  @override
  String aboutSizeTotal(String size) {
    return '合計 約$size';
  }

  @override
  String ytPlaylistLine(int count, String author) {
    return 'プレイリスト • $author • 動画$count本';
  }

  @override
  String get checkingSize => 'サイズを確認中…';

  @override
  String get eqBitPerfectNote => 'Bit-perfect モードがオンなので、イコライザーは使われない。「設定 › サウンド › 出力と音質」でオフにしてね。';

  @override
  String get eqHint => 'プリセットを選ぶか、スライダーをドラッグしてね。周波数をタップすると細かく調整できる。';

  @override
  String eqHeadroom(String db) {
    return 'ヘッドルーム $db dB。上げた帯域でも音割れしない。';
  }

  @override
  String get changeFrequency => '周波数と幅を変える';

  @override
  String bandNumber(String number) {
    return 'バンド $number';
  }

  @override
  String get defaultLabel => 'デフォルト';

  @override
  String get newReleases => '新作';

  @override
  String get couldntLoadPage => 'このページを読み込めませんでした。ネット接続を確認してください。';

  @override
  String get removedFromLibrary => 'ライブラリから外した';

  @override
  String get saveToLibrary => 'ライブラリに保存';

  @override
  String get phaseDownloading => 'ダウンロード中';

  @override
  String get converting => '変換中…';

  @override
  String get finishing => '仕上げ中…';

  @override
  String get needsFfmpegMp3 => 'MP3 のダウンロードには ffmpeg が必要ですが、ここでは使えません。「設定 › ライブラリとダウンロード › ダウンロード」で別の形式を選んでください。';

  @override
  String get noFlacHere => 'この端末では FLAC のダウンロードは使えません。「設定 › ライブラリとダウンロード › ダウンロード」で別の形式を選んでください。';

  @override
  String get mobileDataOff => 'モバイルデータでのダウンロードはオフです。Wi-Fi につなぐか、「設定 › ライブラリとダウンロード › ダウンロード」で許可してください。';

  @override
  String get couldntDownloadSong => 'この曲をダウンロードできませんでした。あとでもう一度試してください。';

  @override
  String spotifyLinePlaylist(String name, String found, String total) {
    return '$name：$total曲中$found曲';
  }

  @override
  String spotifyLineAlbumSaved(String name) {
    return '$name：ライブラリに保存した';
  }

  @override
  String spotifyLineFollowed(String name) {
    return '$name：フォローした';
  }

  @override
  String spotifyLineArtistMissing(String name) {
    return '$name：YouTube Music に見つからない';
  }

  @override
  String spotifyLineNoSongs(String name) {
    return '$name：YouTube Music に曲が見つからない';
  }

  @override
  String spotifyLineFailed(String name, String problem) {
    return '$name：$problem';
  }

  @override
  String get somethingWentWrong => '問題が発生しました';

  @override
  String positionOf(String kind, String position, String count) {
    return '$kind $count件中$position件目';
  }

  @override
  String get signInYtFirst => '先に YouTube Music にログインしてください';

  @override
  String get hideRiflay => 'Riflay を隠す';

  @override
  String get showRiflay => 'Riflay を表示';

  @override
  String get quitRiflay => 'Riflay を終了';

  @override
  String convertingToFlac(String title) {
    return '$title を FLAC に変換中…';
  }

  @override
  String convertingSongsToFlac(int count) {
    return '$count曲を FLAC に変換中…';
  }

  @override
  String convertedToFlac(String title) {
    return '$title を FLAC に変換した';
  }

  @override
  String alreadyLossless(String title) {
    return '$title はもうロスレス';
  }

  @override
  String couldntConvert(String title) {
    return '$title を変換できませんでした';
  }

  @override
  String convertedSongsToFlac(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count曲を FLAC に変換した');
    return '$_temp0';
  }

  @override
  String convertedSomeFailed(int count, int failed) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count曲を FLAC に変換、$failed曲は変換できなかった');
    return '$_temp0';
  }

  @override
  String get couldntConvertThese => 'これらの曲を変換できませんでした';

  @override
  String addedSongsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count曲を追加した');
    return '$_temp0';
  }

  @override
  String get allowReadMusic => 'フォルダを追加するには、Riflay に音楽の読み取りを許可してね';

  @override
  String get couldntAddMusic => 'その音楽を追加できませんでした';

  @override
  String get pressBackToExit => 'もう一度「戻る」で終了';

  @override
  String get downloadingAudio => '音声をダウンロード中…';

  @override
  String get view => '見る';

  @override
  String get resizeSidebar => 'サイドバーのサイズを変える';

  @override
  String get resizeSidePanel => 'サイドパネルのサイズを変える';

  @override
  String get signInToSpotify => 'Spotify にログイン';

  @override
  String get checkingSession => 'セッションを確認中…';

  @override
  String get spotifyHandlesSignIn => 'ログインは Spotify が行う。Riflay はライブラリを読むだけ。';

  @override
  String get couldntLoadSignIn => 'ログインページを読み込めませんでした。ネット接続を確認してください。';

  @override
  String get noSessionYet => 'このページにはまだログイン中のセッションがありません。上でログインを済ませてから「もう一度」をタップしてください。';

  @override
  String get couldntReadSpotifySession => 'Spotify のセッションを読み込めませんでした。もう一度試してください。';

  @override
  String get signInToYt => 'YouTube Music にログイン';

  @override
  String get googleHandlesSignIn => 'ログインは Google が行う。Riflay はセッションを保存するだけ。';

  @override
  String get couldNotUseSignIn => 'そのログインは使えませんでした。';

  @override
  String get nothingIsPlaying => '何も再生してない';

  @override
  String get pressEscToExit => 'Esc で全画面を終了';

  @override
  String get hideEqualizer => 'イコライザーを隠す';

  @override
  String get videoUnavailable => 'この動画は利用できません。';

  @override
  String get videoUnplayable => 'この動画は再生できません（非公開、年齢制限、または地域制限）。';

  @override
  String get muxFailed => '映像と音声を合わせられませんでした。もう一度試すか、「設定 › ライブラリとダウンロード › ダウンロード」で別のサイズを選んでください。';

  @override
  String get noInternetTryAgain => 'ネットにつながってません。もう一度試してください。';

  @override
  String extAnsweredUnreadable(String name) {
    return '$name から読めない応答が返ってきた';
  }

  @override
  String extStopped(String name) {
    return '$name が停止された';
  }

  @override
  String get flacBiggerOne => 'FLAC ファイルは元のファイルより大きくなる。音は同じまま。元のファイルで失われた分は FLAC でも戻らない。';

  @override
  String get flacBiggerEach => 'どの FLAC ファイルも元のファイルより大きくなる。音は同じまま。元のファイルで失われた分は FLAC でも戻らない。';

  @override
  String get ownSongsStay => '自分で追加した曲はそのまま残り、FLAC がその横にできる。';

  @override
  String get quality => '音質';

  @override
  String get convert => '変換';

  @override
  String get betaMusixmatchBody => 'ほかで見つからないとき、Musixmatch で単語ごとの歌詞を探す。';

  @override
  String get betaVideoModeBody => 'プレイヤーで曲に合わせてMVを観る。';

  @override
  String get betaDirectUsbBody => 'Android を通さず USB DAC に直接出力する。試験的な機能。';

  @override
  String get mostPlayed => 'よく聴く曲';

  @override
  String get notPlayedForAWhile => 'しばらく聴いてない曲';

  @override
  String get thisSong => 'この曲';

  @override
  String get addMusicFolder => '音楽フォルダを追加';

  @override
  String couldntReachDevice(String device) {
    return '$device に接続できませんでした';
  }

  @override
  String get presetClassicNote => 'いつものプレイヤー。ジャケットが音楽に合わせて脈打つ';

  @override
  String get presetStackedNote => 'ジャケットがページいっぱいに。まとまったボタン、太いバー、横長の再生ボタン';

  @override
  String get presetKawaiiNote => 'ジャケットがページに溶け込み、シンプルなアイコン、波線、ボタンの奥に音量';

  @override
  String get useThisColour => 'この色を使う';

  @override
  String get saturationBrightness => '彩度と明るさ';

  @override
  String get hue => '色相';

  @override
  String wrapReadyTitle(String month) {
    return '$monthの振り返りができた';
  }

  @override
  String get monthlyWrap => '毎月の Wrap';

  @override
  String get monthlyWrapChannel => '月が終わったら、その月の音楽を振り返る';

  @override
  String get tapToSeeListened => 'タップして聴いた曲を見よう。';

  @override
  String get vizOffBitPerfect => 'Bit-perfect 中はオフ：DAC に届くまでの音は何も変えられない';

  @override
  String get vizOffLightweight => 'パフォーマンスが「軽量」のときはオフ';

  @override
  String get vizOffReducedMotion => '動きを控えめにしてる間はオフ';

  @override
  String get vizHiddenDop => 'この曲を DoP で DSD 再生してる間は隠れる';

  @override
  String get vizHiddenCasting => 'ほかのデバイスで再生中は隠れる';

  @override
  String get minimize => '最小化';

  @override
  String get maximize => '最大化';

  @override
  String get windowRestore => '元のサイズに戻す';

  @override
  String get whilePlaying => '再生中';

  @override
  String get whileRiflayOpen => 'Riflay を開いてる間';

  @override
  String couldntFindOnYt(String title) {
    return 'YouTube Music に $title が見つかりませんでした';
  }

  @override
  String fromNamed(String name) {
    return '$name から';
  }

  @override
  String extCouldntSearch(String name, String error) {
    return '$name で検索できませんでした：$error';
  }

  @override
  String moreOptionsFor(String title) {
    return '$title のその他のオプション';
  }

  @override
  String get removedFileNotDeleted => 'ライブラリから外しましたが、ファイルは削除できませんでした。';

  @override
  String couldntPlayOnDevice(String title, String device) {
    return '$device で $title を再生できませんでした';
  }

  @override
  String tallerAsWebm(String size) {
    return '$size は WebM で使える。';
  }

  @override
  String get dsdUseDacVolume => 'DSD はそのまま DAC に届く：DAC の音量を使ってね';

  @override
  String get streamsOnline => 'YouTube Music：ネットが必要';

  @override
  String get playsOfflineHere => 'この端末：オフラインで再生できる';

  @override
  String get showAll => 'すべて表示';

  @override
  String get offWhileDirect => '音が DAC に直接届いてる間はオフ';

  @override
  String get ffmpegOneTime => '準備中：初回だけのダウンロード（約 40 MB）…';

  @override
  String get matugenInvalid => '正しい Matugen の JSON カラーファイルを選んでね。前に使えてた色のままにしておく。';

  @override
  String get couldntSignInSpotify => 'Spotify にログインできませんでした。もう一度試してください。';

  @override
  String get somethingWentWrongRetry => '問題が発生しました。もう一度試してください。';

  @override
  String get videoCouldntLoad => '動画を読み込めなかったので、曲だけ再生してます。';

  @override
  String get keySpace => 'スペース';

  @override
  String get forward => '進む';

  @override
  String deletePlaylistBody(String name) {
    return '「$name」を削除します。曲はライブラリに残ります。';
  }

  @override
  String get lyricsOtherVersion => 'この歌詞は同じ曲の別の録音のもの（ライブ版じゃなくスタジオ版など）。歌詞自体は合ってても、タイミングがずれてるかも。歌詞メニューの「タイミングを調整」でずらせる。';

  @override
  String get backToCurrentLine => '今の行に戻る';

  @override
  String get signInWindowClosed => 'ログインのウィンドウが突然閉じました。もう一度試してください。';

  @override
  String get spotifySignInWindowClosed => 'Spotify のログインのウィンドウが突然閉じました。もう一度試してください。';

  @override
  String deviceDidntRespond(String device) {
    return '$device から応答がありません';
  }

  @override
  String get theDevice => 'デバイス';

  @override
  String get ytReturnedNothing => 'YouTube Music から何も返ってきませんでした。接続を確認してください。';

  @override
  String get signInToChangeYt => 'YouTube Music のライブラリを変えるには Google でログインしてください。';

  @override
  String get notYtInvite => 'それは YouTube Music の招待リンクじゃありません。';

  @override
  String get noInternetCheck => 'ネットにつながってません。確認してもう一度試してください。';

  @override
  String get ytDidntCreatePlaylist => 'YouTube Music でプレイリストが作成されませんでした。';

  @override
  String get ytDidntTakeChange => 'YouTube Music に変更が反映されませんでした。もう一度試してください。';

  @override
  String get ytDidntMakeInvite => 'YouTube Music で招待リンクが作成されませんでした。';

  @override
  String notPlaylistLinkFrom(String services) {
    return 'それは $services のプレイリストのリンクじゃありません。';
  }

  @override
  String get playlistEmptyOrPrivate => 'そのプレイリストは空か、非公開です。';

  @override
  String get playlistMissingOrPrivate => 'そのプレイリストは存在しないか、非公開です。';

  @override
  String get spotifyPageChanged => 'Spotify のページが変わったため、今はこのリンクを読み込めません。';

  @override
  String get unexpectedDeezerReply => 'Deezer から予期しない応答がありました。';

  @override
  String get lbTokenInvalid => 'ListenBrainz によると、このトークンは無効です。';

  @override
  String get noneOfItsSongsOnYt => 'どの曲も YouTube Music にありません。';

  @override
  String accentNamed(String name) {
    return 'アクセント：$name';
  }

  @override
  String frequencyHz(String hz) {
    return '周波数：${hz}Hz';
  }

  @override
  String deletedNamed(String title) {
    return '「$title」を削除した';
  }

  @override
  String spotifySongsNotFound(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$name：見つからない曲$count曲');
    return '$_temp0';
  }

  @override
  String get statsListened => '聴いた時間';

  @override
  String statsSongsUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '曲');
    return '$_temp0';
  }

  @override
  String statsPlaysUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '回再生');
    return '$_temp0';
  }

  @override
  String albumsPlural(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'アルバム$count枚');
    return '$_temp0';
  }

  @override
  String listensWaiting(int count, String who) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$who。送信待ちの再生記録が$count件。');
    return '$_temp0';
  }

  @override
  String get sessionCodeHint => 'ABC123 または ABCDE-FGHJK';

  @override
  String get downloadedTools => 'ダウンロードしたツール';

  @override
  String get deleteExecutables => '実行ファイルを削除';

  @override
  String get downloadedToolsSubtitle => 'Riflay がダウンロードした FFmpeg と yt-dlp を探して削除。';

  @override
  String get downloadedToolsIntro => 'Riflay がダウンロードしたツールだけを表示。システムにインストールしたツールは別で管理。';

  @override
  String get noDownloadedTools => 'ダウンロードした実行ファイルは見つからなかった。';

  @override
  String get deleteAllExecutables => '実行ファイルをすべて削除';

  @override
  String get deleteExecutablesQuestion => 'ダウンロードした実行ファイルを削除する？';

  @override
  String get deleteExecutablesBody => '必要になったら Riflay がもう一度ダウンロードする。音楽と設定はそのまま。';

  @override
  String get executablesDeleted => 'ダウンロードした実行ファイルを削除した。';

  @override
  String get couldntFindExecutables => '実行ファイルを探せなかった。もう一度試してね。';

  @override
  String get couldntDeleteExecutables => '一部の実行ファイルを削除できなかった。もう一度試してね。';

  @override
  String get presetLiquidStackedNote => 'Stacked にリキッドグラスの操作パネルとスマホのガラスタブを追加';

  @override
  String get presetLiquidKawaiiNote => 'Kawaii にリキッドグラスの操作パネルとスマホのガラスタブを追加';

  @override
  String get liquidGlassControls => 'リキッドグラスの操作パネル';

  @override
  String get liquidGlassControlsSubtitle => 'プレーヤーのボタンをリキッドグラスにする。下でほかにガラスにする部分を選べます。';

  @override
  String get glassSeekBar => 'シークバーをガラスに';

  @override
  String get glassTransport => '再生ボタンをガラスに';

  @override
  String get glassTransportSubtitle => '前へ・再生/一時停止・次へ';

  @override
  String get glassVolume => '音量をガラスに';

  @override
  String get deviceSetupTitle => 'このパソコンに合わせて設定';

  @override
  String get deviceSetupIntro =>
      'Riflay がこのパソコンを調べて、合う見た目を選んだ。古いパソコンやメモリが少ないなら効果を控えめに、性能が高いなら多めに。設定 › 電源とバックグラウンド でいつでも変えられる。';

  @override
  String deviceSetupThreads(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'プロセッサ $countスレッド');
    return '$_temp0';
  }

  @override
  String deviceSetupMemory(String size) {
    return 'メモリ ${size}GB';
  }

  @override
  String get deviceSetupLaptop => 'ノートパソコン(バッテリーあり)';

  @override
  String get deviceSetupDesktop => 'デスクトップ(バッテリーなし)';

  @override
  String deviceSetupCost(String percent) {
    return '再生中はプロセッサの約$percent%';
  }

  @override
  String get deviceSetupRecommended => 'おすすめ';

  @override
  String get deviceSetupContinue => '続ける';

  @override
  String get deviceSetupKeep => '今の設定のままにする';

  @override
  String get deviceSetupAgain => 'このパソコンを調べる';

  @override
  String get deviceSetupAgainNote => 'このパソコンをもう一度調べて、合う見た目を提案する';

  @override
  String get sourceYoutubeMusic => 'YouTube Music';

  @override
  String get sourceSoundcloud => 'SoundCloud';

  @override
  String get sourceBoth => '両方';

  @override
  String get searchSourceTooltip => '検索する場所';

  @override
  String get streamsFromSoundcloud => 'SoundCloud：ネットが必要';

  @override
  String get soundcloudSearchSource => 'SoundCloudで検索';

  @override
  String get onSoundcloud => 'SoundCloudから';

  @override
  String get soundcloudSearchFailed => 'SoundCloudの検索に失敗しました。接続を確認してください。';

  @override
  String get noSoundcloudResults => 'SoundCloudに結果がない';

  @override
  String get soundcloudCantCast => 'SoundCloudの曲はこのデバイスでのみ再生できます。';

  @override
  String get pasteYtOrScLink => 'YouTubeかSoundCloudのリンクを貼り付けて';

  @override
  String get soundcloudUnplayable => 'SoundCloudではこの曲をここで再生できません。';

  @override
  String get soundcloudImportNote => 'SoundCloudの曲はストリーミング再生。今すぐ再生するか、ライブラリに保存できる';

  @override
  String soundcloudLine(int count, String author) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count曲');
    return 'SoundCloud • $author • $_temp0';
  }

  @override
  String saveCountToLibrary(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count曲をライブラリに保存');
    return '$_temp0';
  }

  @override
  String get soundcloudArtists => 'SoundCloudのアーティスト';

  @override
  String get soundcloudPlaylists => 'SoundCloudのプレイリスト';

  @override
  String get linkNotSupported => '共有されたものに YouTube や SoundCloud のリンクがない。';
}
