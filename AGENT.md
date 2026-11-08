# AGENT.md

Guide for coding agents (and people) working on Riflay. Read it before
changing code.

## Who it's for

Riflay's users are **not technical**. Every feature must work with zero
setup and one obvious control:

- YouTube Music sign-in is a single **Sign in with Google** button. Never add
  "paste your cookies", OAuth client IDs, or browser pickers.
- Power-user audio settings live under **Settings › Sound › Output & quality**.
  Everyday effects (Equalizer, Volume leveling, Crossfade, Virtual speakers,
  Crossfeed, Mono audio) live in **Settings › Sound › Sound effects (DSP)**.
  Autoplay and gapless live in **Settings › Sound › Playback**.
  Power options live in **Settings › Power & background**.
- UI looks like a streaming app. Colours come from the theme picked in
  **Settings › Look & feel › Appearance** (`ThemeChoice`: Default; Dynamic,
  which follows the playing song's cover; Monochrome; Catppuccin, Everforest,
  Everblush, Nord, Gruvbox, Tokyo Night, Dracula, Rosé Pine; Custom; dark,
  light or matching the system) and from real
  cover art (`AccentBuilder`). No decorative gradients, no emoji, no "AI"
  styling.
- Error messages the user sees (SnackBars, error lines) are one calm, plain
  sentence: "Couldn't play Song", "No internet connection. Try again." Never
  append an exception, mpv / yt-dlp output, an HTTP code or a URL; those go
  to `debugPrint`.

## Layout

```
lib/
  platform/                    The seams between native and web builds (see Web build)
  models/track.dart            Track (local file, cue slice or YouTube song), Collection
  services/
    player_controller.dart     Queue, shuffle (done in Dart, see below), autoplay, library
    library_store.dart         The library's own file (library.json), read and written in an isolate
    legacy_data.dart           First start on a computer: brings over what OpenMusic (the old name) kept
    private_files.dart         The app's 0700 folder; atomic writes, 0600 secrets (the Google session)
    audio_engine.dart          Every mpv audio setting + SignalPath read-back
    crossfade.dart             Crossfade: the rules (pure functions) and `Crossfader`, which runs it on a second mpv player
    sleep_timer.dart           Sleep timer: wall-clock deadline, fade-down, pause (no player needed; tested with a fake clock)
    lyrics.dart                Your lyrics, .lrc / embedded tag, disk cache, then online (word-timed first): YouTube Music, LRCLIB, Better Lyrics, Kugou, NetEase, Musixmatch, QQ, Megalobiz, Genius, lyrics.ovh
    metadata.dart              Tag reading, cover art, tag editor (all in-process; Matroska via ffmpeg)
    tag_writer.dart            Tag edits for MP3, Ogg, WAV, AIFF, WavPack, APE: only the edited fields change
    dlna.dart                  DLNA / UPnP: SSDP search, AVTransport control, the LAN server the TV fetches from
    cast.dart                  A cast session (DLNA or AirPlay): follows position, pause, a song's end
    airplay.dart               AirPlay 1 (RAOP) sender: mDNS search, RTSP, ALAC over RTP, timing, RSA/AES
    dop.dart                   DSF / DSDIFF reading and DoP packing (Native DSD)
    sacd.dart                  SACD ISO: TOC, audio sectors, a DSDIFF built on the fly per song
    cue_sheet.dart             Splits whole-album rips into tracks
    ytmusic_web.dart           YouTube Music InnerTube client (WEB_REMIX), public + signed in
    youtube_music_account.dart Session, library, discover pages, playlist edits, likes, radio
    youtube_audio_source.dart  Streams YouTube audio in ranged chunks (yt-dlp resolves URLs)
    ytdlp.dart                 Finds / downloads yt-dlp, resolves and caches stream URLs
    download_prefs.dart        Settings › Library & downloads › Downloads (format, quality, folder), and pickForDownload: which stream a download takes
    video_download.dart        Music-video downloads: stream picking (MP4 = H.264 + AAC, WebM = VP9 + Opus, AV1 only where nothing else), sizes, muxVideo
    mp4_mux.dart / webm_mux.dart  Pure-Dart muxers (no re-encoding): YouTube's DASH fMP4 and WebM streams into one file; used where there is no ffmpeg
    download_edit.dart         Editing a downloaded song: title, album, cover (never the artist); lyrics live in lyrics.dart's UserLyrics
    ffmpeg.dart                Finds / downloads ffmpeg (tag editor, AirPlay, casting conversions)
    system_fonts.dart          Fonts from the device's font folders (Settings › Look & feel › Appearance › Font)
    desktop_login.dart         Runs linux/login_helper (WebKitGTK Google sign-in window)
    spotify_session.dart       Spotify sign-in: the web player's own token, caught in a WebView / linux/spotify_helper
    spotify_library.dart       Spotify library over the web player's GraphQL (hashes read from its bundle)
    spotify_account.dart       Spotify session, token refresh, what was imported; spotify_import.dart runs an import
    library_views.dart         LibraryViews: sorted lists, albums, artists and search keys, worked out once per library change
    smart_playlists.dart       The built-in, self-updating lists in Library
    folder_watch.dart          Picks up files added to or removed from the music folders
    play_history.dart          What was played; listening_stats.dart and wrap.dart read it (Stats, monthly Wrap)
    scrobbler.dart             Last.fm / ListenBrainz: when a play is a scrobble (ScrobbleTracker), a queue per service kept for offline listens
                               importHistory brings past listens into PlayHistory.importPlays; a song matching no file
                               or video gets an `imported:` key (SongInfo.imported): stats show it, smart playlists skip it
    backup.dart                Backup & restore: preferences (no secrets), the listening history and my-lyrics in one JSON file
    appearance.dart            Themes and palettes (AppPalette, ThemeChoice), accent, cover colours and their fades, window opacity
    language.dart              The language shown (English or Indonesian); `tr` gives its words anywhere
    layout_prefs.dart          Corners, density and motion (Settings › Look & feel › Layout)
    beta_features.dart         Optional feature preferences (legacy name); switches live in their respective settings pages
    listen_together/           Listen together: one queue shared over the LAN or the internet
    video_mode.dart            Video mode: a YouTube song's music video on Now Playing (and full screen, see Conventions)
    youtube_stream.dart        A YouTube song's audio stream in one player request (yt-dlp is the fallback)
    soundcloud.dart            SoundCloud over api-v2: search, links, related tracks, a track's HLS playlist (see SoundCloud)
    soundcloud_audio_source.dart  Plays a SoundCloud track: hands mpv its HLS playlist through just_audio's loopback server
    usb_dac.dart / linux_alsa.dart  Direct outputs: Android USB DACs, Linux ALSA cards
    direct_usb.dart            Android Direct USB: libusbdac streams to the DAC itself (DirectUsb.kt), any phone
    media_session.dart         System media controls (Android notification, Control Center, MPRIS)
    system_tray.dart           Computers: the tray icon and menu, and Close to tray (Settings › Power & background);
                               the plugin sits behind platform/tray.dart. Linux needs a StatusNotifier host
                               (no tray icon, e.g. plain GNOME: closing quits as before)
    discord_presence.dart      Discord Rich Presence over the local IPC socket
  ui/
    home_shell.dart            Layouts: phone tabs / desktop sidebar + one history
    navigation.dart            DesktopHistory (Back/Forward), Locations, sidebar highlight
    shell/                     Desktop sidebar, phone navigation (the Liquid glass bar: see below), FirstFrameGate
    player/                    Player bar, mini player, Now Playing, full screen, side panel
    theme.dart                 AppColors, ThemeData from the palette, restyleTree (see Colours)
    debug_switches.dart        Turns the rendering shortcuts off to debug them (see Debugging)
    pages/                     One file per screen; sound_settings.dart, equalizer_page.dart…; search/ and lyrics/ hold their parts
    widgets/                   Shared widgets: controls, track_row, menus, page_scaffold, smooth_scroll, signal_path
linux/login_helper/            C++ GTK3 + webkit2gtk-4.1 sign-in helper
linux/spotify_helper/          The same for Spotify; --refresh gets a new token without a window
linux/carla_bridge/            LADSPA plugin that runs a Carla project in mpv's filter chain (audio plugins)
third_party/                   Vendored packages (see below)
integration_test/              Real-engine tests, run in headless Weston
test/                          Unit and widget tests
```

## Phone tab bar

- Settings › Look & feel › Layout › Tab bar on phones. All styles live in `ui/shell/phone_navigation.dart`
  (`PhoneBottomBar`); the mini player is built there too.
- Liquid glass (`_GlassBar`, also set by the Liquid Kawaii preset): the mini player on its own row over the tabs,
  Search as a round button beside them. `GlassBarLink` (owned by the shell) shrinks it to one row when the page
  scrolls down: the shell's `NotificationListener<ScrollNotification>` around every tab feeds `onScroll`, so pages
  need nothing. On the Search tab the bar carries the search field (`GlassBarLink.search`, a `SearchInput`) and
  `SearchPage(boxInBar:)` leaves out its own box; while typing the field rides on the keyboard.
- The pills are drawn by liquid_glass_renderer (one `LiquidGlassLayer` and blend group). Full glass needs Impeller
  and Flutter GPU: on in iOS's `Info.plist` (`FLTEnableFlutterGPU`); Android stays on Impeller's OpenGL ES backend
  (the Adreno workaround in its manifest), so it and the other platforms get the package's FakeGlass. Lightweight
  draws the plain raised surface. `test/glass_tab_bar_test.dart` and `integration_test/glass_tab_bar_test.dart`
  (screenshots with `SHOTS`) cover it.
- Stacked and Kawaii use Capsule navigation. Liquid Stacked and Liquid Kawaii use Liquid Glass navigation and
  `playerGlassControls`: transparent player surfaces use `ui/player/player_glass.dart`, sharing a backdrop in the
  composed player. Opaque filled controls retain their fill; the seek bar, previous/play/next and the volume (row, or Kawaii's speaker pill) stay solid unless their own switches (`glassSeekBar`, `glassTransport`, `glassVolume`, shown under Liquid Glass controls) are on. Presets leave those three alone. Lightweight uses solid surfaces without a glass layer.
  The flag persists in Layout preferences and can be changed under Playback controls independently of the preset.
- The bar's large Close button clears Search and returns to the previous tab. There is no separate small Clear
  button in the bar; preserve the keyed input subtree during expansion so its keyboard connection stays alive.

## First start on a computer

- Low-end phones (`DeviceSetup.fitPhone`, Android): one with under 4 GB of memory (`/proc/meminfo`, which apps may
  read) is put in Lightweight once, at its first start with that code, if still in the default Balanced; a mode
  picked by hand stays. Lightweight on a phone also takes the music video at 720p, not 1440p
  (`VideoMode.maxHeight`). `MemoryTrim` runs on Android too: after a song change, once a minute and in the
  background it asks the allocator to hand free pages back (`mallopt(M_PURGE_ALL)`, then `M_PURGE`), and in the
  background drops decoded covers, since Android closes the apps holding the most memory first. Neither is measured
  on a phone yet. `RIFLAY_NO_PHONE_SETUP` and `RIFLAY_NO_ANDROID_TRIM` turn them off.
- `services/app_updates.dart` checks GitHub's latest stable release: on request (Settings › About,
  `AppUpdateTile`), and once a start (`AppUpdates.checkAtStart`, from `RiflayApp`): 10 s after the window is up, one
  quiet request; a newer release shows `showUpdatePopup` (the version, the tile that gets it, Not now), the latest
  version or no connection show nothing. Not in widget tests, `tool/cpu.sh` or `tool/memory_app.sh`;
  `RIFLAY_NO_UPDATE_CHECK` turns the check at start off.
- `services/device_setup.dart` reads the computer (processor name, threads, memory, battery: `/proc` and
  `/sys/class/power_supply` on Linux, `GlobalMemoryStatusEx` / `GetSystemPowerStatus` and the registry on Windows,
  `sysctl` / `pmset` on macOS) and recommends a `PerformanceMode` by kind of computer: Lightweight under 8 GB or 8
  threads, Heavy on a desktop with 16+ threads and 16+ GB, Balanced otherwise (laptops included: a 24-thread Core
  Ultra 9 laptop gets Balanced). The page is drawn over the shell, so it carries its own `AppTitleBar`.
- `ui/pages/device_setup_page.dart` shows it once (`deviceSetup.v1`), the recommendation picked; Continue applies
  the pick, "Keep my settings" changes nothing. Settings › Power & background › Check this computer opens it again.
  Computers only: phones keep their look. `main` loads the flag, so tests that build `RiflayApp` never see it.
- `playingCost` comes from `tool/cpu.sh`: measure again when what a mode draws changes.
  `RIFLAY_NO_DEVICE_SETUP` never shows the page.

## Downloaded executables

- Settings › About › Delete executables on desktop lists Riflay-owned FFmpeg and yt-dlp files and partial downloads
  from its application-support `bin` directory. It never follows symlinks, scans PATH, or deletes system tools.
- `services/executable_store.dart` serializes tool resolution, downloads and cleanup. `downloaded_tools.dart` scans
  and deletes only known filenames, reports partial failures, and invalidates cached executable paths. yt-dlp's
  deferred update checks its generation so an update queued behind cleanup cannot recreate a deleted binary.
- `test/downloaded_tools_test.dart` and `test/downloaded_tools_page_test.dart` cover ownership, queue ordering,
  confirmation, failures and empty state. Tests use temporary files; never delete the developer's own tools.

## Library model

- There is no "source" switch: Home and Library always show files on this device, Riflay playlists, YouTube
  Music and saved SoundCloud tracks together. Search picks where it looks online (see SoundCloud).
- `Track.isRemote` (has a `videoId`) means a YouTube Music song that streams; everything YouTube-only (radio
  through `upNext`, likes, downloads, the music video) keys off it. `Track.streams` is true for SoundCloud
  tracks too, and `Track.source` (`TrackSource`) says which service. Mark streamed songs with
  `SourceMark(online:, source:)` (YouTube Music's play ring, SoundCloud's cloud, a green pin once downloaded) /
  `MediaCard(online: true)`; `ArtistLinks` puts the mark before the artist in every player view. `PlayerController.downloadedCopy`
  finds a downloaded file for a YouTube song; `_sourceFor` plays that instead,
  so `isOffline(track)` is what the UI should show.
- Riflay playlists are `UserPlaylist` (in `models/track.dart`), stored in
  SharedPreferences (`playlists.v1`) and shown as `CollectionKind.playlist`.
- Song menus get "Remove from this playlist" from a `PlaylistEditScope` above
  them (Riflay playlists and the user's own YouTube Music playlists).
- The listening streak (`services/listening_streak.dart`, shown by `StreakBadge` beside Home's greeting): days
  in a row with a play kept in `PlayHistory` (30 seconds or more), alive through today until it ends. Its flame
  follows `StreakTier`: red under 10 days, gold from 10, blue from 50, purple from 100, every colour from 365.
  Counted once per history change and day (`RIFLAY_NO_STREAK_CACHE` turns that off).
- Picking several songs: every `CollectionPage` (albums, artists, playlists,
  YouTube Music ones too) has a `TrackSelectionHost` (`widgets/track_selection.dart`).
  Hold a row or use "Select" in its menu; while anything is picked a tap picks
  instead of playing, and `TrackSelectionBar` adds them to a playlist or the
  queue. Rows read the selection without depending on it and only the tint and
  the round mark listen, so picking doesn't rebuild every row. Not a shortcut,
  so no `RIFLAY_*` switch.
- Menus use `useRootNavigator: true`, and their actions use the navigator's
  context (`host` in `_TrackMenu`): the row may be rebuilt away while the
  menu is open.
- Autoplay: `PlayerController._maybeAutoplay` appends the radio of the current
  song when the queue is down to its last two songs.
- The library is saved in its own file by `LibraryStore` (it moved out of
  SharedPreferences' `library.v1`), never encoded on the UI isolate.
  Sorted lists, albums, artists and search keys come from `LibraryViews`
  (`services/library_views.dart`),
  worked out once per library change: add new derived views there, not as
  getters that sort `_library` on every call.
- `PlayerController` notifies for everything (song change, play / pause,
  buffering), several times a song. Widgets that need only part of it use
  `PlayerSelect` (rebuilds when the selected value changes),
  `VisiblePlayerBuilder` (skips pages that are covered) or
  `libraryRevision` (library and playlists only), not `PlayerScope.of`.
  `integration_test/big_library_test.dart` shows a regression (see
  Performance budget).

## How audio works

- **Android Direct USB** (Settings › Sound › Output & quality, experimental, off by default). A beta
  (`BetaFeature.directUsb`, off by default): its switch there warns first (`confirmDirectUsb`: may freeze or close
  the app, full volume to the DAC) and only then offers Direct USB; turned off, Direct USB stops and never runs. Android 14's
  bit-perfect mixer (`usb_dac.dart`) only works where the phone's maker offers it; many (Xiaomi, Samsung)
  list no bit-perfect format. Direct USB goes around Android instead: mpv writes the decoded song with
  `ao=pcm` into a FIFO in the cache folder (a WAV header per stream), and `DirectUsb.kt` reads it into
  libusbdac's `RoutingAudioSink` (JitPack `com.github.ostrichbat2k:libusbdac`), which claims the DAC's USB
  interface and streams to it, or plays through Android for a format the DAC doesn't take. One per
  process: mpv blocks on the FIFO without a reader. Pause/play/seek reach it from `PlayerController`.
  The position shown runs ahead by what the pipe holds (well under a second). Settings shows its route,
  formats, dropouts and log, so a screenshot tells what happened.
  mpv's `pcm` output has no clock: paced only by the pipe's reader, it held its audio lock through each ~1.4 s
  write (65536 frames) into the full pipe, the core waited on that lock, and every synchronous property read from
  Dart waited with it on the UI thread (ANR). So the chain ends in `asetnsamples` + `arealtime` while Direct USB
  runs (`AudioEngine.directUsbPaceFilter`; Android's libmpv is built with both): samples untouched, at the song's
  pace, the pipe near empty. arealtime sleeps in mpv's core thread until each frame is due, so the 256-sample
  frames keep property reads at ~2 ms (whole FLAC frames made them ~15 ms, and Signal path lagged).
  `DirectUsb.kt` reads the pipe on one thread into memory (up to 10 s) and feeds the sink on another, so a DAC that
  is activating never holds mpv's writes; audio more than 600 ms behind mpv's clock is dropped down to 200 ms once
  (screen, skips, Video mode and synced lyrics otherwise ran 1-3 s ahead of the sound). Signal path and Detail stats
  read mpv once per song while Direct USB runs (each read waits ~15-80 ms on the paced core). Never send mpv `audio-format=no` or `s24`: this mpv parses neither,
  and a song loaded with either fails.
  It must never close the app. SIGPIPE is ignored before the pipe opens (`ignoreBrokenPipes`: libmpv keeps the
  default, which kills the process silently when the reader stops); turning it off moves mpv off the pipe before
  the reader goes; every channel call answers; and an exception on the reader or on a libusbdac thread turns Direct
  USB off (Settings says why, songs go back to Android) instead of reaching Android's kill handler. A sink that
  stops taking audio (libusbdac's Android fallback goes silent once the DAC is claimed) is flushed once, then a
  watchdog thread closes the pipe, which frees mpv, and turns Direct USB off (`STALL_MS`, `WATCHDOG_MS` in
  `DirectUsb.kt`); each stream first waits briefly for the DAC to activate so it starts on USB. A crash nothing
  can catch (native code) leaves `directUsb.starting.v1` set, and the next start leaves Direct USB off once
  ("Riflay closed while starting it"). `RIFLAY_NO_DIRECT_USB_GUARD` turns the catching and the start marker off.
  Crash capture over ADB (libusbdac logs through Timber, which says nothing in Riflay): `adb logcat -c`, then
  `adb logcat -v time -b main,system,crash AndroidRuntime:E DEBUG:V libc:V DirectUsb:V flutter:V ActivityManager:I '*:S'`
  while turning it on.

- just_audio everywhere, with libmpv as its backend on **every platform**
  through `just_audio_media_kit`. Linux uses the system libmpv; the others use
  Riflay's own builds, which have the FFmpeg filters the sound settings
  need: `tool/build_libmpv_windows.sh` (committed DLL),
  `tool/build_libmpv_android.sh` (committed `.so` files in the vendored
  `media_kit_libs_android_audio`) and `tool/build_libmpv_apple.sh` (built on a
  Mac, by CI or by the podspec on first build; not committed). Change one and
  the others should follow: same mpv, same FFmpeg, same filter list. One
  exception: `alimiter` (clip protection) is only used where mpv feeds the DAC
  itself, which Android never does, so Android's build leaves it out.
- `third_party/just_audio_media_kit` is vendored (public domain) to expose the
  mpv player: `JustAudioMediaKit.onPlayerCreated` and `.activePlayer`.
  just_audio recreates the platform player after `stop()`, so settings are
  re-applied in `AudioEngine._applyAll` every time.
- `JustAudioMediaKit.pitch = false`: with pitch on, media_kit overwrites mpv's
  `af` property. The app owns `af` (EQ, crossfeed).
- All settings are mpv properties set in `AudioEngine._applyProps`. Options
  that only apply when the output opens (`audio-buffer`, `audio-exclusive`,
  `audio-samplerate`) need `reopen: true`, which sends `ao-reload`.
- Filters are labelled (`@eq:`, `@preamp:`, `@crossfeed:`, `@hrtf:`, `@mono:`)
  so `signalPath()` can name each stage. New DSP must use a label and add its
  name to the `switch` in `signalPath()`.
- A file in a filter graph (room correction's IR, Virtual speakers' HRIR)
  goes through `AudioEngine.graphPath` and `_lavfi` (mpv's `%n%` length
  quoting). Windows' `C:`, an apostrophe or a bracket in a folder name break
  the graph otherwise.
- Virtual speakers: FFmpeg's `headphone` with `assets/audio/hrir_kemar_48k.wav`
  (made by `tool/make_hrir.sh`, copied to a real file at first use). It runs
  at 48 kHz or the chosen output rate: left alone, `headphone` would move the
  song to the HRIR's rate with FFmpeg's default resampler.
- Mono audio uses mpv's own `format` filters, not FFmpeg's `pan`, so it needs
  nothing from the FFmpeg build. Mono turns Virtual speakers and crossfeed
  off; Virtual speakers turn crossfeed off.
- **Bit-perfect mode** must bypass every stage you add: check `bitPerfect` in
  your getter (see `eqActive`, `crossfeedActive`, `effectiveLeveling`).
- Clip protection (`@limiter`, FFmpeg's `alimiter`) is last in the chain
  wherever mpv itself feeds the DAC (Exclusive mode, ASIO, a direct ALSA card;
  `clipGuardActive`). The DAC's integer format cuts off anything past full
  scale, and Opus / AAC decodes, EQ boosts, leveling and plugins get there; it
  lowers those peaks instead and passes everything within full scale exactly.
  Through the system mixer the sound stays float and the mixer handles it.
- Resampling is Riflay's, not the system's: on Linux, when PipeWire runs at
  one fixed rate (its default, `clock.allowed-rates = [ 48000 ]`), mpv converts
  to it with SoX VHQ (`AudioEngine.soxrOptions`, passband widened to stay flat
  to 21 kHz) and PipeWire passes the stream through; with several allowed rates
  nothing resamples. mpv's converter always gets TPDF dither, which only acts
  where bits are lost (a 16-bit output after EQ or volume).
  `test/resampler_test.dart` measures it through the real mpv.
- The equalizer's headroom (`preamp`) comes from the curve's highest point
  (`peakGain`, the bands' combined RBJ response), not the loudest band:
  neighbouring boosts add up.
- **Crossfade** (`crossfade.dart`) is not done by mpv: a second `AudioPlayer` (the
  "tail", marked secondary through `JustAudioMediaKit.secondaryRequestedAt` so it never becomes
  `activePlayer`) replays the ending song's last seconds silently, in step with the main player
  (both mpv `time-pos` clocks are compared and corrected by seeks). At the fade the tail takes the
  ending song over and fades out, while the main player jumps to the next song and fades in. So the
  queue, now playing and media session are right at once, and nothing is handed back. The fades
  are mpv `volume` factors (`AudioEngine.setCrossGain` / `setSleepGain` / `setSecondaryGain`) on top
  of the user's level, which is never touched. Off in bit-perfect and exclusive/direct outputs, while
  casting, with DSD/DoP, in repeat one and for "End of this song"; albums that flow keep gapless.
  `integration_test/zz_crossfade_test.dart` runs it on two real libmpv players.
- media_kit has no `setShuffleOrder`, so shuffle is done in Dart
  (`PlayerController._ordered`, `_shuffledFrom`). Never call just_audio's
  `shuffle()` / `setShuffleModeEnabled`. A shuffled order goes through
  `spreadArtists` (`services/shuffle.dart`), which keeps an artist's songs apart.

### Adding an audio feature (checklist)

1. A field + setter in `AudioEngine`, saved in `load()` / `_save()`.
2. Apply it in `_applyProps` (with `reopen: true` if it's an AO option).
3. Bypass it in bit-perfect mode.
4. Show it in the signal path if it changes samples.
5. UI in `lib/ui/pages/sound_settings.dart` with `SettingTile` (it stacks the
   control under the text on narrow windows).
6. A unit test in `test/audio_features_test.dart` and a real-mpv check in
   `integration_test/zz_audio_test.dart` (read it back with `signalPath()`).

- An output device that isn't plugged in (a USB DAC) falls back to the
  system default with a note under Output device; the choice stays saved.
- **Casting** (`PlayerController.castTo`): the queue stays in `player`, paused,
  while a TV plays; `_castFollow` sends each new current song. UI must use
  the controller's `position`, `duration`, `seek`, `play`, `pause`, `volume`
  and `smoothPosition()` / `positionUpdates()`, never `player.*` directly,
  or it shows this device's paused player instead of the TV.
- `services/media_session.dart` (audio_service) mirrors the player to the
  Android notification / lock screen, Control Center and Linux MPRIS.
  On phones the synced line takes the artist's place; with the lyrics page's Pronunciation on, a line in
  another script reads "line — pronunciation" (`LyricsTranslation.of`, one cached request per song).

## YouTube Music

- InnerTube `WEB_REMIX`, **no API key** (it isn't needed, and a key-shaped
  string trips GitHub secret scanning). Signed-in requests add cookies +
  `SAPISIDHASH`; signed-out ones still get home, explore, charts, search,
  albums, playlists and radio.
- Request shapes follow [ytmusicapi](https://github.com/sigma67/ytmusicapi).
  Check its source before adding an endpoint.
- Radio / autoplay: `next` with `playlistId: RDAMVM<videoId>`.
- Playlist edits: `playlist/create`, `browse/edit_playlist` (actions
  `ACTION_ADD_VIDEO`, `ACTION_REMOVE_VIDEO` with the row's `setVideoId`,
  `ACTION_SET_PLAYLIST_NAME`, `ACTION_SET_PLAYLIST_PRIVACY`,
  `ACTION_MOVE_VIDEO_BEFORE`), `playlist/delete`, `like/like`, `like/removelike`.
- Only playlists with `musicEditablePlaylistDetailHeaderRenderer` are the
  user's own; offer edits only for those.
- A downloaded song goes into a YouTube Music playlist by the video it came
  from (`Track.youtubeId` / `Track.onYoutube`, read from `sourceUrl` with
  `youtubeVideoIdOf`). A file that never came from YouTube can't: the account's
  `createPlaylist` / `addToPlaylist` leave those out (`YoutubeMusicAccount.youtubeSongs`)
  and "Add to playlist" says so ("This song isn't on YouTube Music", or how many
  were skipped). Not a shortcut, so no `RIFLAY_*` switch.
- Links opened with Riflay (`lib/services/incoming_links.dart`; SoundCloud's too, see SoundCloud): Android's
  "Open with" and Share sheet (intent filters in `AndroidManifest.xml`, no
  `autoVerify` since Riflay can't own the domains; `MainActivity.kt` keeps the
  link until Dart takes it over `riflay/incoming_link`, cold start and
  `onNewIntent`), a link on the computers' command line (`riflay <link>`; a
  copy already running gets it over a loopback port with a token,
  `lib/platform/link_relay_io.dart`, and the new process quits), and the web
  app's `share_target` / `?url=`. `YoutubeLinks.parse` finds the link in a
  whole shared message; `HomeShell._openIncoming` plays a song or opens the
  playlist / album (`browse/MPREb_…`). Not on iOS or macOS yet: those need a
  share extension and `application(_:open:)`. `RIFLAY_NO_OPEN_LINKS` takes
  none (Android still lists Riflay).
- Uploading a file to the user's library (music.youtube.com uploads) is not
  built: ytmusicapi's `upload_song` does it with these same cookies
  (`upload.youtube.com/upload/usermusic/http`, resumable start + finalize), but
  YouTube processes the file for minutes before it gets a video id, so adding it
  to a playlist would mean polling the uploads list; no web build (CORS).

## SoundCloud

- A second place to search and stream from (`Features.soundcloud`: native builds; `RIFLAY_NO_SOUNDCLOUD` leaves it
  out). `services/soundcloud.dart` talks to api-v2, the API soundcloud.com's own web player calls, with the web
  player's public `client_id`: read from soundcloud.com's last script bundles (`scriptUrls`, `clientIdIn`), kept
  in `soundcloud.clientId.v1` (left out of backups), read again once when a request answers 401/403. No API key and
  no sign-in; never add a "paste your client id" field.
- A SoundCloud track is `Track.soundcloud`: id `sc:<trackId>`, `sourceUrl` its permalink, no `videoId`, so the
  YouTube code never sees it. It is saved like any track (library, Riflay playlists, history, recently played);
  "Save to library" (`PlayerController.saveToLibrary`) puts it in the library without a file.
- Playback: only full, unencrypted HLS. `pickTranscoding` takes AAC (best bitrate), then MP3, Opus, then the
  adaptive master playlist; `snipped` (Go+ previews), `*-encrypted-hls` (DRM) and `progressive` are never used,
  and `parseTrack` drops tracks whose `policy` is `SNIP` or `BLOCK`, so search never lists a song that can't play.
  Don't work around any of these. The playlist's address is signed for a few minutes only, so
  `SoundcloudAudioSource` (a `StreamAudioSource`) looks it up when mpv asks and serves the playlist text as
  `application/vnd.apple.mpegurl` (FFmpeg only treats an address without `.m3u8` as HLS with that type); mpv then
  fetches the segments from SoundCloud itself and seeks in them. The segments' signatures last about two hours.
  `absolutePlaylist` makes relative addresses absolute: mpv reads the playlist from the loopback server.
  Before the segments' signatures run out (`playlistExpiry`, the first `expires=`), `PlayerController` loads the
  playing track again where it is with a fresh playlist: one `Timer` set when the playlist is served
  (`SoundcloudClient.served`), 10 minutes early (mpv reads ahead), plus a check on play and seek, since timers stop
  while a phone sleeps. Nothing ticks meanwhile. `integration_test/soundcloud_playback_test.dart` covers it.
- Search: `SearchSourceToggle` switches between YouTube Music and SoundCloud, one source at a time. It sits in
  the desktop top bar to the right of the search box, and beside the Search title on phones. Its two service
  marks share a pill, with the current source filled. `SearchSource.current` keeps the switch and results in sync;
  `search.source.v1` remembers the choice (an older saved "both" falls back to YouTube Music). SoundCloud shows
  its top songs, then its artists and playlists, and leaves out Songs/Videos and the filters.
  The empty search page names the selected source. `integration_test/search_source_layout_test.dart` covers
  the switch in the real shell at desktop and phone widths, legacy preference fallback, and this text (`SHOTS`
  saves screenshots). Phone widths on Linux verify layout; they do not replace tests on Android or iOS.
  Autoplay and Start radio follow SoundCloud's related tracks for a SoundCloud song.
- Pages (`ui/soundcloud_pages.dart`, `openSoundcloud`): a playlist (`CollectionKind.remote`) or a profile
  (`CollectionKind.remoteArtist`, labelled Artist) as a `RemoteCollectionPage`, with Save to library and, for a
  playlist, Save as playlist (a Riflay playlist). "Go to artist" on a SoundCloud track opens its uploader's
  profile (`Track.artistId` holds the SoundCloud user id there; YouTube-only code checks `isRemote` first). The side
  panel's About the artist (YouTube Music's) is left out for SoundCloud tracks.
- A SoundCloud link pasted in the import sheet (`ui/youtube_import.dart`, `SoundcloudLink.parse`: tracks, sets,
  profiles, private links, `on.soundcloud.com` short links) plays, saves or (a set) becomes a playlist; nothing is
  downloaded. Shared to or opened with Riflay (`IncomingLinks.readSoundcloud`, Android's intent filter for the
  SoundCloud hosts, a link on the command line, Ctrl+V) a track plays and a playlist or profile opens.
  Not casting (renderers rarely play HLS: the song stays on this device, with a note), not the web build.
- Shortcuts: the client id, recent searches and each track's playlist (two minutes, four at most: mpv asks twice,
  probe then open) are kept; `RIFLAY_NO_SOUNDCLOUD_CACHE` asks SoundCloud every time.
- Terms: api-v2 is SoundCloud's private API and its API terms don't cover third-party players using the web
  player's id; it may change or be refused without notice. Riflay plays only what that player gives a signed-out
  visitor and links back to the track (Share).

## Web build

`flutter build web` builds Riflay Web: a YouTube Music streamer that talks to `tool/web_proxy`
(browsers may not call InnerTube themselves). Native builds must behave exactly as before, so
web differences live behind the seams in `lib/platform/`, never as `kIsWeb` checks spread
through the code:

- `host.dart` (`Host.isLinux`, `Host.environment`…): use it instead of `dart:io`'s `Platform`,
  which throws in a browser. On the web everything is false, so OS-specific code just doesn't run.
- `features.dart` (`Features.downloads`, `Features.casting`…): what this build offers. Hide a
  control whose feature is off; a new native-only feature gets a flag here.
- `mpv.dart`: media_kit's `NativePlayer`; on the web an interface nothing implements, so the
  `player.platform case NativePlayer p` paths in `AudioEngine` skip. Import media_kit with
  `hide NativePlayer` next to it. `AudioEngine.supported` is false there.
- `native_calls.dart`: every `dart:ffi` call (`malloc_trim`, `mkfifo`, power requests, `Abi`).
  `dart:ffi` doesn't compile for the web, so it must not be imported anywhere else.
- `background.dart`: `inBackground` instead of `Isolate.run` (no isolates in a browser).
- `network.dart`: `runWithNetwork` wraps `main`; on the web every `http.Client()` goes through
  `ProxyClient`, which sends allowed hosts to `<proxy>/fetch/<host>/<path>` and renames the
  headers a browser blocks (`User-Agent`, `Cookie`…) to `x-riflay-*`. `webAudioUri` makes a
  YouTube song play from `<proxy>/audio/<videoId>`: an `<audio>` element needs a URL up front,
  so the proxy looks the stream up itself (`lib/services/youtube_player_api.dart`, shared with
  `youtube_stream.dart`) and serves it with Range in 1 MiB googlevideo requests.
- `proxy_route.dart`: the allowed hosts, paths and headers. Plain Dart with no imports: the
  proxy imports it (and `youtube_player_api.dart`) by file path. A new service the app calls
  on the web needs its host here.

- `web_audio.dart`: every `<audio>` element just_audio plays is routed (by wrapping
  `HTMLMediaElement.prototype.play`, since just_audio keeps its element private) through one Web Audio
  graph: preamp, the equalizer's peaking filters, crossfeed or mono, then an analyser the visualizer reads
  (`AudioEngine._readWebVisualizer`, the same 24 bands as mpv's filter bank). `AudioEngine.webEffects` is
  its switch; Settings › Sound › Sound effects shows the equalizer, crossfeed and mono there. Only
  same-origin, `blob:` and CORS (`crossOrigin` set, which the player does on the web) elements are routed:
  a routed cross-origin element without CORS would play silence. `RIFLAY_NO_WEB_AUDIO` turns it off.
- `web_storage.dart`: the browser's local storage. `PlayHistory` keeps its file's text there (40,000 plays
  at most, the quota is a few megabytes), so Stats, Wrap and the streak work on the web.
- `browser_files.dart`: browser downloads (the Wrap card; a song's audio via the proxy's `?save=`, which
  answers with `Content-Disposition`, for "Save to device").
- `mqtt.dart`: Listen together over the internet connects to the same brokers as a secure WebSocket
  (`wss://<broker>:<wssPort>/mqtt`), so web and app share sessions. Same-Wi-Fi sessions stay native
  (`Features.listenOnLan`).
- The desktop layout's top bar (Back / Forward, Home, search) is drawn on the web too
  (`hasCustomTitleBar`); what belongs to a window (dragging, window buttons, `window_manager`) is behind
  `hasNativeWindow`.

Playback on the web is just_audio's own HTML backend (`JustAudioMediaKit.ensureInitialized`
registers nothing there). Run it against a local proxy:

```sh
cd tool/web_proxy && dart run bin/server.dart &            # http://127.0.0.1:8787
flutter run -d chrome --dart-define=RIFLAY_PROXY=http://127.0.0.1:8787/
(cd tool/web_proxy && dart test)                            # proxy tests
```

`test/web_seams_test.dart` checks that the seams answer as before on native.

## Vendored packages (`third_party/`)

| Package | Why |
|---|---|
| `just_audio_media_kit` | Exposes the libmpv player (hook + `activePlayer`) |
| `just_audio_web` | The web player: it reused the previous queue's songs for a new one (just_audio 0.10 keeps one playlist id), so a tapped song played another; `load()` builds its sources afresh |
| `media_kit_libs_macos_audio`, `media_kit_libs_ios_audio` | Their podspecs use `Mpv.xcframework` from `tool/build_libmpv_apple.sh` instead of media_kit's download |
| `media_kit_libs_android_audio` | Android's `libmpv.so` from `tool/build_libmpv_android.sh` (the FFmpeg filters crossfeed, room correction and Virtual speakers need) instead of media_kit's downloaded one; media_kit's helper library is kept as it was |
| `audio_metadata_reader` | Its FLAC and MP4 writers dropped ReplayGain, lyrics, disc numbers and unknown tags (MP4 freeform `----` atoms) on every save; ours keep them. WAV and AIFF read the disc number from an ID3 chunk |
| `flutter_inappwebview_linux` | Stub: the real one links WPE WebKit; Linux sign-in uses `linux/login_helper` instead |
| `mpv_asio` | Riflay's ASIO audio output for mpv, patched into the Windows libmpv by `tool/build_libmpv_windows.sh` |
| `asiosdk` | Steinberg's ASIO SDK, which `mpv_asio` builds against |
| `ladspa` | The LADSPA header (and its Windows build bits) for `linux/carla_bridge` |

Mark every change in vendored code with a `Riflay:` comment.

## Running and testing

CI pins the Flutter version in `.github/workflows/release.yml` (`FLUTTER_VERSION`); use the same one locally.

```sh
flutter analyze                 # must be clean
flutter test                    # unit + widget tests
```

Integration tests drive the real app with real libmpv. **Run them only in a
headless Weston, with their own data directory**:

```sh
weston --backend=headless --socket=om-test --width=3840 --height=2160 &   # once
env -u DISPLAY WAYLAND_DISPLAY=om-test GDK_BACKEND=wayland \
  XDG_DATA_HOME=/tmp/om-test-data \
  flutter test integration_test/zz_audio_test.dart -d linux
```

- Never run them on the user's desktop session (they open windows).
- **Always** set `XDG_DATA_HOME` to a throwaway directory. The YouTube Music
  session lives under it; without it a test runs signed in as the developer
  and could change their real account.
- `zz_audio_test` routes mpv to `ao=null` (silent) and checks the signal path.
- `dsp_test` renders a test song through each sound setting (`ao=pcm` into
  files) and measures every channel. It needs nothing on the host, so it is
  the check that a platform's own libmpv works: run it on Linux, Windows, an
  Android emulator or phone, macOS and the iOS Simulator.
- `zz_buttons_test` talks to the live YouTube Music service, signed out.
- `zz_responsive_test` sweeps every screen across 90 window sizes; it needs a
  folder of tagged MP3s (see `s` at the top of the file).
- Add `--dart-define=SHOTS=<dir>` to save screenshots, then look at them.
- `flutter test -d linux` rebuilds `build/linux/x64/debug/bundle`. If someone
  has `flutter run` open on the project, that breaks their running app; run
  integration tests from a copy of the project instead.

### Performance budget

`tool/perf.sh` runs `integration_test/performance_test.dart` in **profile
mode** (debug-mode speed means nothing) in its own headless Weston. It plays
a generated 120-song library and wheel-scrolls Home and All Songs, then
prints `PERF …` lines and saves `build/perf/<date>.json` to compare runs.
It fails when:

- the whole app is told to rebuild more than twice a second while a song just
  plays (`PlayerController.notifyListeners`; just_audio re-emits its sequence
  state on every position tick, so only real changes may pass through), or
- a frame's build takes over 8 ms at the 90th percentile, or 40 ms at worst.

Raster (GPU) time can't be measured headless; check that on real hardware
with `flutter run --profile` and DevTools.

The same script takes another target: `tool/perf.sh
--target=integration_test/big_library_test.dart` (8240 songs: load, a folder
scan, song changes and scrolling, as `BIG …` lines) and
`--target=integration_test/cpu_test.dart` (`CPU …`: one core's share while a
song plays and while paused). Compare the old code and the new in two
copies of the project, a couple of runs each.

The live test binding asks for a frame after every frame, so `cpu_test` can't see a view that keeps an idle window
redrawing. `tool/cpu.sh [runs]` can: it builds `tool/cpu_app.dart` (the real app on Flutter's own binding) in
profile mode, seeds a library of silent songs with long titles, and prints `CPU …` lines (share of one core,
frames/s, build and raster time a frame, the busiest threads) idle, playing and paused on Home and Now Playing.
`RIFLAY_CPU_LAYOUT='{"performance": "lightweight"}'` starts it with other Layout settings. Idle and paused must
draw no frames and stay under 0.8% of one core. In a debug build (swap `--profile` for `--debug` in a copy of the
script) `RIFLAY_CPU_STACKS=true` prints who asks for frames while playing and paused, and every running ticker.
`RIFLAY_CPU_ENV='RIFLAY_MPV_OPTIONS=name=value;name=value'` sets mpv options over Riflay's own, for an A/B of an
output setting. On Linux PipeWire's `data-loop.0` thread (inside the app) takes ~1.4% of one core whenever sound
plays, at its 1024-frame quantum: plain `mpv` costs the same, and `pipewire-buffer`, `PIPEWIRE_LATENCY`, a float
output and leaving the resampling to PipeWire don't change it. The rest of a playing song is Riflay's.

Budget on Linux, as a share of the whole processor (24 threads here, so 2.4% of one core is 0.1%): playing behind
another window, paused or idle, every mode stays under 0.1%; so does Lightweight in front. Balanced on a computer
(`LayoutPrefs.frugal`: decorations on one 5 fps beat, the visualizer at 10) is ~0.33% in front with the visualizer
moving, ~0.17% without it, and Heavy with the visualizer must stay under 0.8% (~0.57%). Seed the visualizer with
`{"visualizer": true, "visualizerStable": true}`: without the second key the old Beta migration turns it off. The
seeded songs are silent, so the visualizer's bars stand still: `RIFLAY_CPU_SOURCE='anoisesrc=r=44100:c=pink:a=0.3'`
gives them sound, and `RIFLAY_CPU_ENV='RIFLAY_MPV_OPTIONS=ao=null'` keeps it off the speakers (add PipeWire's ~1.3%).

Memory over a session: `tool/memory_app.sh` builds `tool/memory_app.dart` (the real app, on Flutter's own binding)
and takes it through idle, a hi-res song, Now Playing, scrolling 120 songs with 1000 px covers, a 1080p music video
(Now Playing, then the side panel) and a long pause, reading its own memory every 250 ms: each phase prints private
/ PSS / RSS as low / median / high, so a jump between fixed points shows. `RIFLAY_MEM_BUILD=release` measures what
people run (a profile build carries ~40 MiB more: the VM service, timeline, source maps).
`RIFLAY_MEM_ENV='RIFLAY_MEM_PARTS=true'` adds what private memory is made of (C heap, anonymous, Dart heap, each
library), `RIFLAY_MEM_DART=true` (profile) the Dart heap's biggest classes; `RIFLAY_MEM_LAYOUT` / `RIFLAY_MEM_AUDIO`
seed Layout and Sound settings. `RIFLAY_VIDEO_MPV_OPTIONS='name=value;…'` sets mpv options on the music video's
player, for an A/B. Runs differ by ~20 MiB; compare medians of a couple of runs.

Memory: `tool/memory.sh [runs]` runs `integration_test/memory_test.dart` the
same way (profile, headless, fresh process per run) and prints PSS / private /
RSS at idle, playing a local FLAC, streaming YouTube and after scrolling.
Compare medians of several complete runs; debug builds are meaningless here.

## Translations

Riflay speaks English, Indonesian and Japanese (Settings › Look & feel › Appearance › Language; by default the
device's language when Riflay has it). The words live in `lib/l10n/app_en.arb` (the template) and
`lib/l10n/app_id.arb` / `app_ja.arb`; `flutter gen-l10n` (also run by `flutter pub get` / any build) writes
`lib/l10n/generated/`.

- Read a word through `tr` (`lib/services/language.dart`): `Text(tr.navSettings)`, also in services and
  enums, no BuildContext needed. A language change rebuilds every screen (`_relanguage` in `main.dart`).
- A new string: add it to every .arb file (same key, same `{placeholders}`; counts as `{count}` with an
  `int` placeholder), run `flutter gen-l10n`. `test/language_test.dart` fails when a language is
  missing it or its placeholders differ. A new language: its .arb plus an `AppLanguage` entry named in its
  own script.
- Keep the English exactly as the code had it: widget tests find screens by their English words.
- Indonesian is plain and friendly ("kamu"), like a music app; keep product names (YouTube Music,
  Equalizer, playlist) as people say them.
- Japanese is casual plain form (だ/る) like app copy; です/ます only for confirmations and errors. Keep
  loanwords people expect (プレイリスト, イコライザー) and names as the English has them (Riflay, Wrap,
  Bit-perfect). Counters stick to the number (`{count}曲`); plurals keep only `other`.
- Every screen is translated. `test/hardcoded_strings_test.dart` fails on English typed into what a screen
  shows (`Text('…')`, `tooltip:`, `title:`, `labelText:` …); names that stay the same everywhere are listed
  there. Detail stats (`stats_for_nerds.dart`) stays English on purpose: its rows go into bug reports.
- Plurals: an ICU `plural` with `=1` and `other` in English, never `n == 1 ? 'song' : 'songs'`. Several
  placeholders: declare them in the order the call passes them (the metadata order is the argument order).
- A label of an enum value: a `String get label => switch (this) { … => tr.… }` getter, not a string in the
  constructor. A list of labels (`appShortcuts`, `ListeningStats.months`): a getter, not a `const` or
  `final` top-level list, which would keep the first language it was read in.
- Saved values stay English and are translated where they are shown: EQ presets (`eqPresetLabel`), lyrics
  sources (`lyricsSourceLabel`), player preset notes (`presetNote`).

## Colours and restyling

- A palette change (a theme picked, the Dynamic theme following a new cover,
  the "Whole app" wash) must not rebuild the whole app. New widgets read
  colours with `AppColors.of(context)` (or `Theme.of`), which rebuild only
  what depends on them. The static getters (`AppColors.accent`, …) still
  work: `restyleTree` (called from `_restyle` in `main.dart`) marks every
  widget that might read them.
- `restyleTree` skips what can't show a colour: framework widgets
  (`_frameworkWidgets` in `theme.dart`), anything under a widget that
  implements `ColorFreeSubtree` (`ColorFree`, `Artwork`), and the own build
  of a widget that implements `ColorFreeSelf` (`MediaCard`, `PlayButton`).
  Mark a widget only when that is true: a static colour read in a skipped
  build stays stale. Move the coloured part into a small widget that reads
  `AppColors.of(context)` instead (see `_HoverFill` in `controls.dart`).
- During a fade, `Appearance` notifies about a dozen times; the Material
  theme (`appThemeNow`) moves only every third step, and the last step always
  catches it up.
- `MediaCard` keeps what it built until its track, text, layout or text theme
  changes; add a field it shows to the check in `didUpdateWidget`.
- `test/theme_restyle_test.dart` and `test/dynamic_theme_perf_test.dart`
  guard both sides: colours follow, and a fade stays cheap.

## Debugging

- Debug builds write every error to `<app support dir>/errors.log`;
  user-facing text stays calm and the details go to `debugPrint`.
- The rendering shortcuts above can be turned off at launch to tell whether a
  bug is theirs (`lib/ui/debug_switches.dart`):

  ```sh
  flutter run --dart-define=RIFLAY_NO_SHORTCUTS=true      # all of them
  flutter run --dart-define=RIFLAY_RESTYLE_ALL=true       # ignore the colour-free marks
  flutter run --dart-define=RIFLAY_THEME_EVERY_STEP=true  # theme follows every fade step
  flutter run --dart-define=RIFLAY_NO_CARD_CACHE=true     # MediaCard builds every time
  flutter run --dart-define=RIFLAY_NO_FIRST_FRAME_GATE=true
  flutter run --dart-define=RIFLAY_LOG_RESTYLES=true      # print what each change rebuilds
  ```

  ```sh
  flutter run --dart-define=RIFLAY_SCROBBLE_DRY_RUN=true  # print scrobbles instead of sending them
  flutter run --dart-define=RIFLAY_LASTFM_KEY=… --dart-define=RIFLAY_LASTFM_SECRET=…
  flutter run --dart-define=RIFLAY_NO_TRAY=true           # no tray icon; closing the window quits
  flutter run --dart-define=RIFLAY_NO_TAB_BAR_COLLAPSE=true  # the phone's Liquid glass tab bar never shrinks on scroll
  flutter run --dart-define=RIFLAY_NO_GLASS_RENDERER=true    # its pills in Riflay's own blur, not liquid_glass_renderer
  flutter run --dart-define=RIFLAY_NO_DIRECT_USB_GUARD=true  # Android Direct USB crashes for real (logcat)
  flutter run --dart-define=RIFLAY_NO_OPEN_LINKS=true     # ignore links opened or shared with Riflay
  flutter run --dart-define=RIFLAY_NO_SOUNDCLOUD=true     # no SoundCloud anywhere (search, links, the source switch)
  flutter run --dart-define=RIFLAY_NO_SOUNDCLOUD_CACHE=true  # SoundCloud's client id, searches and stream playlists looked up every time
  flutter run --dart-define=RIFLAY_NO_SHARED_SIGNAL_PATH=true  # every signalPath() caller reads mpv itself
  flutter run --dart-define=RIFLAY_NO_STREAK_CACHE=true  # the listening streak counted afresh every build
  flutter run --dart-define=RIFLAY_NO_VIDEO_ROTATE=true  # turning a phone sideways on Now Playing doesn't open the music video full screen
  flutter run --dart-define=RIFLAY_NO_MV_SEARCH=true     # a song YouTube Music pairs with no video gets none (no search for its official video)
  flutter run --dart-define=RIFLAY_NO_MV_ALIGN=true      # a music video with no map of its parts plays on the song's timeline, not lined up by their sound
  flutter run --dart-define=RIFLAY_NO_SCANNED_GAIN=true  # a song without ReplayGain tags plays unleveled, measured or not
  flutter run --dart-define=RIFLAY_NO_ADAPTIVE_VIDEO=true # a music video stays at its full height however often it stalls
  flutter run --dart-define=RIFLAY_NO_PAGE_ARTWORK=true  # Cover: Background uses the list's 544 px cover, not a 1600 px one
  flutter run --dart-define=RIFLAY_ENDLESS_MARQUEE=true  # long titles scroll forever, card titles without a hover too
  flutter run --dart-define=RIFLAY_SIGNAL_PATH_WHILE_PAUSED=true  # the quality badge reads mpv every second while paused too
  flutter run --dart-define=RIFLAY_UNALIGNED_BEATS=true  # views on UiBeat count their own beats (same rate, separate frames)
  flutter run --dart-define=RIFLAY_NO_DEVICE_SETUP=true  # no setup page on a computer's first start
  flutter run --dart-define=RIFLAY_QUICK_LIGHTWEIGHT_SEEK_BAR=true  # Lightweight's seek bar moves 2-4 times a second, not once
  flutter run --dart-define=RIFLAY_BEAT_WHILE_PAUSED=true  # the seek bar's position stays on UiBeat while paused
  flutter run --dart-define=RIFLAY_MOVE_UNFOCUSED=true  # decorations, visualizer and marquees keep moving while another window has the focus
  flutter run --dart-define=RIFLAY_FULL_BALANCED=true  # Balanced on a computer moves at 20 fps, not 5 (visualizer 10)
  flutter run --dart-define=RIFLAY_NO_PHONE_SETUP=true  # a phone under 4 GB keeps Balanced at its first start
  flutter run --dart-define=RIFLAY_NO_ANDROID_TRIM=true  # Android keeps its allocator's free pages and covers in the background
  flutter run --dart-define=RIFLAY_NO_UPDATE_CHECK=true  # no update check at start (Settings › About still checks)
  flutter run --dart-define=RIFLAY_LYRICS_SCROLLBAR=true  # synced lyrics show a scrollbar on computers again
  flutter run --dart-define=RIFLAY_NO_PAGE_OUT=true  # Linux keeps the app resident behind other windows (no MADV_PAGEOUT)
  flutter run --dart-define=RIFLAY_ASTATS_VISUALIZER=true  # the visualizer measures its bands with astats (~3x the CPU), not aspectralstats
  flutter run -d chrome --dart-define=RIFLAY_NO_WEB_AUDIO=true  # web: songs play straight from <audio>, no effects or visualizer
  ```

  Last.fm is only offered when the build has an API account's key and secret
  (register one at last.fm/api/account/create); ListenBrainz needs nothing.
  Neither is ever committed.

  A bug that goes away with one of them on is in that shortcut. Tests can set
  `DebugSwitches.*` directly and reset them in `tearDown`.
- `themeCacheStats` (`theme.dart`) counts themes built and served from cache.

## Releases

1. Bump `version:` in `pubspec.yaml` (the `+` build number by one) and
   `appVersion` in `lib/app_version.dart` (shown in Settings › About;
   `test/about_test.dart` fails when they differ), and commit them as
   `chore: <version>`.
2. Tag and push: `git tag v<version> && git push origin main v<version>`.
   `.github/workflows/release.yml` prepares a draft with a changelog and download
   guide while Android, Windows, Linux, macOS and iOS build independently.
   Each `<platform>-asset` job calls `release-platform.yml` after its own build:
   it uploads that platform's files and `SHA256SUMS-<platform>`, then makes the
   release public. The first successful upload publishes it; slower or failed
   platforms do not block the others. Reruns replace only that platform's assets
   and keep an already public release public. The `checksums` job combines the
   successful platforms' checksums once the uploads finish, even if another failed.
   On tags iOS skips its Simulator test (macOS tests the same libmpv). Manual
   builds (`platforms: macos, ios`) still save artifacts without publishing.
3. Package managers: Linux gets a `.deb` and `.rpm` (nfpm,
   `linux/packaging/nfpm.yaml`) and an Arch `.pkg.tar.zst` (makepkg in a
   container, `linux/packaging/arch/PKGBUILD`) next to the AppImage. The
   release also carries `SHA256SUMS`, and the run's `package-manifests`
   artifact holds the Scoop manifest, the Homebrew cask (the macOS `.dmg`
   and the Linux AppImage) and the AUR `PKGBUILD` / `.SRCINFO` filled in for the
   version (`packaging/update_manifests.sh`). This job waits for Windows, Linux
   and macOS uploads; it does not delay the platform downloads. With the `TAP_TOKEN` secret the
   release pushes the manifest and cask to `Araryarch67/scoop-riflay` and
   `Araryarch67/homebrew-riflay`; the AUR files are copied by hand. Runtime dependencies live in those files: change them all
   when the Linux build links something new.

Release candidates: set `pubspec.yaml` to `1.3.0-rc1+<n>` and `lib/app_version.dart` to `1.3.0-rc1`, then tag
`v1.3.0-rc1` (`tool/ci_version.sh` takes `vX.Y.Z-rcN`). The release is a GitHub pre-release, so it is never
"latest": the app's update check (stable releases only) and the Scoop bucket / Homebrew tap (`package-manifests`
is skipped) stay on the last stable version, while someone on 1.3.0-rc1 is offered 1.3.0. Packages order it before
the release: `.deb` / `.rpm` 1.3.0~rc1 (nfpm), Arch `pkgver` 1.3.0rc1, and the Windows installer's numeric
VersionInfo 1.3.0 (`NumericVersion`).
The Linux build doesn't download mimalloc: `media_kit_libs_linux` fetches its source archive in CMake with no
retry and an MD5 check, and GitHub's archive route returned 504 to CI (v1.2.18). `linux/CMakeLists.txt` copies
`third_party/mimalloc/mimalloc-2.1.2.tar.gz` (the same archive, byte for byte) to where the plugin looks first.
Release recovery: if GitHub's `/releases/download` route returns HTTP 504, `tool/download_release_asset.py`
uses the asset API through `gh` first, then a retried direct download. Pinned checksums still apply; an
incomplete or mismatched download never replaces an existing file. CI uses this for Gradle, Carla,
Windows video libraries and Linux packaging tools (`GH_TOKEN` is the job's read-only token).
After fixing CI on main, recover an existing release without moving its tag:
`gh workflow run release.yml --ref main -f platforms=all -f publish_tag=v1.2.17`.
The target must exist and match `pubspec.yaml`; version codes still advance with the run number.
Leaving `publish_tag` blank keeps manual runs as artifacts only. Recovery preserves release notes,
publishes successful platform assets and consolidates checksums from the whole existing release.
`platforms=android,windows` can repair only those builds; desktop manifests use the release's current
Windows zip, Linux AppImage and macOS dmg, so successful platforms need not be rebuilt.

## Conventions

- Match the surrounding code: comment *why*, not what; doc comments on public
  members; 120-column `dart format`.
- A failing network call shows a message (SnackBar via `PlayerController.errors`)
  and never leaves a dead button. A control that can't act is disabled, never
  silently ignored.
- Desktop navigation is one browser-style history (`DesktopHistory`): open
  screens with `ShellScope.of(context).open(page, location: …)` so the sidebar can
  highlight them. Phones keep one stack per bottom tab.
- Nothing on screen may move forever by itself while the app is idle: one running ticker redraws the whole
  window at the display's rate (60-240 times a second), a busy CPU and GPU on laptops whose integrated GPU
  shares RAM. `MarqueeText` scrolls `loops` times (3), only while a song plays (`whilePaused` for a hovered card),
  and rests; card titles move only while hovered (once on phones). A debug build with
  `debugPrintScheduleFrameStacks = true` shows who asks for frames.
- What moves by itself rides `UiBeat`, never a ticker of its own (a ticker draws at the display's rate, up to 240
  times a second). Slower views fire on the same beats (`UiBeat.beatsFor`: from three beats on, multiples of three),
  so Balanced's cover, wave, visualizer and marquee all draw in the same 20 frames a second. On Linux each frame
  costs the main thread several milliseconds beyond Dart's build, so the number of frames is the cost.
  Lightweight's seek bar and the quality badge tick once a second on the same beat (about 1 frame a second while
  playing). Paused, nothing stays on the beat (`tool/cpu.sh` prints how many are): a listener that only returns
  still keeps its 60 Hz timer waking the app.
- The music video full screen (`ui/player/video_full_view.dart`, `VideoFullView`): the round button in the corner
  of the video on the cover (`VideoExpandButton`; over Cover: Background, `VideoBackgroundExpand`), a double tap on
  the video, or on a computer the button beside the Song / Video switch of the expanded player and beside Like in
  the side panel (the native video's window lies over anything drawn on the cover there). It opens on the root
  navigator, never in the desktop page history. It shows the same player's picture uncropped
  (`VideoPicture`, `BoxFit.contain`): no second decoder. `VideoMode.addView(full: true)` keeps the video wanted
  while the page under it lets go of its views, and doesn't reload a background video at the cover's size. On a
  phone it locks landscape and hides the system bars (`immersiveSticky`); closing puts back the app's declared
  orientations (`[]`) and both bars. A tablet keeps its orientation (turning it wide swaps the phone layout and its
  Now Playing for the desktop one). Turning a phone sideways while Now Playing shows the video opens it without the
  lock, and upright again closes it (`VideoRotateWatcher`, off with `RIFLAY_NO_VIDEO_ROTATE`). The controls (title,
  like, a lyrics line, Queue, close, the seek bar and transport) fade in on a tap and leave the tree 4 s after the
  last touch, so nothing ticks over the video. The lyrics line listens to `positionUpdates()` only while shown and
  rebuilds when the line changes. On a computer the view fills the window and keeps the controls above and below
  the picture (Linux's GTK surface and Windows' own video window lie over anything Flutter draws); they leave the
  tree, the pointer hides and the picture takes the whole window after 4 s without a mouse move (not while the
  pointer is on them or Queue is open). F11, a double click or the button fills the screen (`windowFullScreen`,
  `windowManager`); Esc leaves full screen, then the view, and closing puts the window back. Queue opens beside the
  picture in a navigator of its own (no back button, no page history), not in the history under the view.
- Video mode is the most a playing song can cost on a computer (a second mpv; every video frame re-rasters the
  whole window, blur included): ~1.7% of a 24-thread CPU and ~100 MB in Balanced. While another window has the
  focus the video holds its picture, and after `VideoMode.unfocusedRelease` (20 s) its player is let go; back in
  front it starts again where the song is. Its height follows the mode on computers (Heavy 1080p, Balanced 720p,
  Lightweight 480p), and so does its frame rate (`VideoMode.maxFps`: Balanced 15, Lightweight 10, an mpv `fps`
  filter that keeps hardware decoding; `RIFLAY_VIDEO_FPS` overrides Balanced's for measuring). Windows renders with
  Impeller on ANGLE, which has no raster cache: each video frame redraws every layer of the window (~15 render
  passes, ~17 ms of CPU a frame), so the video in front costs ~1.5-3% of a 24-thread CPU in Balanced.
  `services/window_focus.dart` tells the app `inactive` when the window opens without the focus
  (Windows only reports changes), and `resumed` / `inactive` on focus and blur.
- Windows plays the music video in a window of its own (`windows/runner/video_window.cpp`, channel
  `riflay/video_window`): Riflay's libmpv is sound only (no GPU output, no d3d11va), so the video was decoded,
  drawn and copied into Flutter on the processor. `windows/CMakeLists.txt` fetches media_kit's video libmpv
  (pinned by SHA-256) as `libmpv-video-2.dll`; `platform/native_video_io.dart` drives it over FFI with `wid`,
  `vo=gpu`, `gpu-context=d3d11`, d3d11va. `NativeVideoSurface` keeps the window over its box after each frame,
  cut to its scroll view and hidden while a route (menu, dialog) is on top: nothing Flutter draws can lie over it.
  So on Windows the side panel's video covers the picture (`panscan`) with the title under it, its shade and fade
  come from an mpv user shader (`VideoMode._fadeShader`), and there is no video behind Now Playing's words. The
  windows are disabled: the main window hands their mouse input to the Flutter view. Playing in front: ~0.1% of
  a 24-thread CPU (it was ~3%). It plays on behind other windows (only minimized or hidden lets it go), keeps its
  player a minute without a view (`_holdWithoutView`), and the side panel has none in Lightweight.
  `RIFLAY_IMPELLER=on|off` (runner/main.cpp) picks the renderer for measuring; Skia saved no memory here.
- Linux uses the same FFI video player with system `libmpv.so.2`, `vo=libmpv`, and a GTK3 `GtkGLArea`
  (`linux/runner/native_video.cc`). A `GtkOverlay` places the surface above the Flutter view, passing input through.
  mpv's update callback schedules GTK rendering; video frames do not invalidate a Flutter texture. Both Wayland
  and X11 use the render API with their native display supplied for hardware decoding. Clipping copies the
  visible portion of a full-size GPU framebuffer, keeping the aspect ratio while scrolling. The renderer is
  detached on the GTK thread before Dart destroys mpv. Initialization failure falls back to media_kit for the
  rest of the session. Full-page backgrounds retain the texture backend so Flutter can paint text above them.
  `integration_test/native_video_linux_test.dart` checks playback, clipping, dialogs, and reattachment with a
  generated local clip (needs ffmpeg). `tool/native_video_probe.dart` compares CPU and Flutter frame rates in a
  profile build, independently of the live integration-test frame loop; run it in headless Weston as above.
  `--dart-define=RIFLAY_NO_NATIVE_VIDEO=true` selects texture video in the full app for comparison.
  Linux keeps its performance-mode FPS caps, pause while unfocused, and two-second release without a view.
  On 2026-11-08, the isolated 640x360/30 fps profile probe in headless Weston on NVIDIA/NVDEC used 23.8% of
  one CPU core for GTK versus 29.8% for texture (six-second samples); both paused near zero. This is not a
  whole-app benchmark. With software decoding the same probe was about 30% for either renderer.
  Full-app measurements and raw data are in `docs/performance/linux-video-2026-11-08/`: three fresh processes
  per configuration, normal binding/profile build, 1280x800, 120 covers and local media, a silent PipeWire sink.
  Native video medians were 0.437% / 522 MiB private (Lightweight), 1.577% / 554 MiB (Balanced), and 2.624% /
  577 MiB (Heavy), CPU as a share of the whole 24-core machine. These exceed the numerical Windows references;
  Linux private/PSS/RSS and Windows private working set use different accounting. Balanced texture was 1.708%
  / 558 MiB: per-run CPU ranges overlap, so the isolated probe is not evidence of a consistent 20% app saving.
  All idle/paused samples were below 0.30% of one core with zero reported UI frames. `tool/benchmark_linux_video.py`
  reproduces the run using `tool/linux_video_benchmark_app.dart` in a copied checkout and headless Weston.
  The full-app driver exposed overlapping renderer initialization on song changes: `_opening` coalesces duplicate
  requests, a generation cancels obsolete work, and `_withSurface` serializes only creation/disposal, leaving
  network loads cancellable. The integration regression also exercises duplicate notifications and rapid skips.
- `StreakFlame` breathes three times when it comes on screen, then rests (it repeated forever at the display's rate).
- `UiBeat`'s timer fires only as often as its busiest view needs (`_stride`): a seek bar ticking once a second wakes
  the app once a second, not 60 times. Heavy's decorations and visualizer run at 30 fps (`PlayingMotion.heavyEvery`):
  at 60 a focused window cost ~0.9% of a 24-thread CPU. On Linux the visualizer moves only while the window has the
  focus (`PlayingMotion.visible`): its mpv filter bank (`VisualizerSpectrum`: 24 band filters, then a level per
  channel) kept mpv's core thread at ~5% of a core behind other windows, where the view drew 20 fps. Unfocused, the
  lease is let go and mpv drops the bank. Windows and macOS keep it moving behind other windows (people watch it
  beside their work), Heavy at 20 fps there; minimized or hidden lets it go everywhere.
- The bank measures each band with `aspectralstats` (mean and variance of one 1024-point FFT a window; their
  `variance + mean²` is the power, 34.6 dB under `astats`' RMS for any sound, `VisualizerLevels.spectralDb`).
  `astats` worked out ~25 statistics on every sample of 26 channels for the one RMS used, ~90% of the bank's cost:
  FFmpeg 9 spends 2.7 s per 120 s of audio on the bank now, 8.9 s before; mpv's core thread fell from ~5% to ~2.4%
  of a core. An mpv whose FFmpeg predates 5.1 refuses the graph (logged, playback goes on, `af` comes back
  without it): `_syncVisualizer` sees that and adds the `astats` bank instead. `RIFLAY_ASTATS_VISUALIZER` forces it.
- Balanced on a computer is frugal (`LayoutPrefs.frugal`, `RIFLAY_FULL_BALANCED` turns it off): the flower, wave,
  karaoke and seek bar move every 200 ms (`LayoutPrefs.frugalEvery`) and the visualizer every 100 ms, in the same
  frames. A focused window with the visualizer went from ~0.5% to ~0.33% of the CPU. Marquees
  keep 20 fps: they stop after a few loops, and at 5 fps a title jumps 7 px. Phones keep the full Balanced; tests
  run as a phone (`test/flutter_test_config.dart`) and turn the switch back for frugal's own tests.
- Karaoke fills at the player's rate (Balanced 20, Heavy 30 fps; it was the display's) and only with the window in
  front (`MarqueeText.playing`); the Heavy marquee moves at 30, not 60.
- Hidden views take no beats: the pages under Now Playing and a player bar slid away (`AutoHideBar`) sit in
  `TickerMode(enabled: false)`, and `SeekBar`, `EqualizerIcon` and the signal path badge stop on it.
- Measured on a 24-thread laptop (Windows, playing a YouTube song with its video and the visualizer on, % of the
  whole CPU / private working set): Lightweight 0.01-0.16% / 30-85 MB after the first idle trim (~15 s, see
  `MemoryTrim`), Balanced 0.2-0.7% / up to ~260 MB, Heavy 0.4-0.7% / up to ~275 MB in front and ~0.1% behind.
- Linux pages the app out like Windows empties its working set (`MemoryTrim`, `trimProcessMemory`):
  `madvise(MADV_PAGEOUT)` over its private mappings, while hidden or left alone (8 s without input) behind another
  window: once per time away (`_pagedOut`, reset when it is focused or shown again), not each minute. Pages go to
  zram/swap or back to the page cache and fault in when touched. Compressing them into zram costs ~0.6 s of CPU on
  the trim's own isolate, so it rests as it goes (~8 ms a MB, big mappings in eighths): spread over ~2.5 s, longer
  than btop's sampling. Repeated each minute it was a spike btop showed every minute (`DartWorker` 5.7% of a core
  in a 10 s window behind another window). `RIFLAY_CPU_ENV='RIFLAY_CPU_SPIKE=unfocus' tool/cpu.sh` shows it. btop showed ~400 MiB RSS for a window playing behind others (that is when people look at it);
  paged out, ~190-240 MiB RSS and 65-110 MiB private. Not while the window has the focus, so lyrics read without the
  mouse don't fault back in each minute. Off with `RIFLAY_NO_PAGE_OUT`. The base app is most of what stays:
  Lightweight measured the same as Balanced in front (~150 MiB private idle, ~200 playing, ~220 scrolling); Heavy
  peaks ~336 MiB private / ~460 MiB RSS with a 1080p music video.
- Opening the lyrics page (`RIFLAY_CPU_ENV='RIFLAY_CPU_SPIKE=lyrics' tool/cpu.sh`: CPU and frames every 100 ms,
  each thread, `RIFLAY_CPU_PROFILE=true` the Dart profile, `RIFLAY_CPU_STACKS=true` in a debug build who asks for
  frames). On Linux a frame costs the main thread ~10 ms natively (GTK composites the whole window; Dart is a small
  part), so what counts is how many frames run: synced lyrics have no scrollbar (`RIFLAY_LYRICS_SCROLLBAR`; each
  follow scroll showed it and faded it out again, ~25 frames a line and a second burst after the page opened);
  lyrics already found show in the page's first frame (`LyricsService.loaded`: no loading bars, no fade) and the
  first placement on the current line is a jump. In frugal Balanced the follow scroll glides on `UiBeat` at 20 fps
  (`_glideTo`, ~7 frames a line) and a line's colour changes at once (`_lineChange`). Opening the page went from
  ~800 ms of the main thread to ~320 ms; the page left open from ~1.6 s to ~0.74 s per 12 s.
- The native video's `GtkOverlay` keeps its `GtkFixed` hidden until a video has a place on screen: shown over the
  Flutter view at all times it made GTK composite the slow way, ~2.8% of a core more while a song played (main thread
  7.5% -> 4.7% on Home). Measurements across the 2026-11 kernel update differ: the same commit measured ~5% more on
  Home after it, so compare builds on the same day.
- Measuring a song (`AudioAnalysis._measure`: loudness for leveling, the waveform) keeps at most 8 of mpv's 64 KiB
  reads in flight to the worker isolate: mpv decodes far faster than the worker measures, and the whole song piled up
  in its queue (180 MiB for four minutes of 24/96, twice that at 192 kHz).
- mpv doesn't report `time-pos` (`stopPositionEvents` in `third_party/just_audio_media_kit`): it did for every
  audio chunk, 16+ times a second, each waking the app. The position is read on the spot when an event goes out
  that used to carry mpv's latest report, and checked once a second while playing; a playback event goes out only
  when just_audio's own extrapolation would be 250 ms off (or every 2 s), and for the read-ahead per second.
  `--dart-define=RIFLAY_TIME_POS_EVENTS=true` brings mpv's reports back.
- Everything that only needs to know how far a song has got (scrobbling, play history, YouTube Music's play
  reports, Listen together) listens to `PlayerController.secondTicks()`: one `UiBeat` listener a second while the
  player plays. just_audio's `positionStream` / `createPositionStream` are 5 Hz timers that never stop once made:
  don't use them. Paused, no position stream has a timer: seeks come in as position discontinuities.
- `EqualizerIcon` (a playing row's bars) rides `UiBeat` at 10 fps and `MarqueeText.playing`; its own repeating
  `AnimationController` redrew the window at the display's rate.
- Decorations (the flower, the wave, the visualizer) and marquees move only while the window has the focus
  (`PlayingMotion.decorates`: `resumed`; computers report `inactive` while another window has it), and the seek bar
  ticks once a second then. Most listening happens with another window in front: a playing song in Balanced then
  costs what Lightweight does. `tool/cpu.sh` measures it as "unfocused".
- Wheel scrolling: give new vertical scroll views a `SmoothScrollController`
  (or wrap them in `SmoothScroll`).
- Overlays above content (sticky headers) must not swallow clicks: wrap
  backgrounds in `IgnorePointer`.
- Commits follow [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat(audio): …`, `fix(ytmusic): …`). Don't commit unless asked.
- Never commit secrets, cookies or session files.
- A new preference that is a secret, or only makes sense on this one device,
  goes in `Backup._kept` so backups leave it out and restores keep it.
