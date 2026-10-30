# AGENT.md

Guide for coding agents (and people) working on Riflay. Read it before
changing code.

## Who it's for

Riflay's users are **not technical**. Every feature must work with zero
setup and one obvious control:

- YouTube Music sign-in is a single **Sign in with Google** button. Never add
  "paste your cookies", OAuth client IDs, or browser pickers.
- Power-user audio settings live under **Settings › Sound › Hi-fi audio**, folded
  away. Everyday ones (Equalizer, Volume leveling, Gapless, Virtual speakers,
  Crossfeed, Mono audio) sit above it in plain words.
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
    appearance.dart            Themes and palettes (AppPalette, ThemeChoice), accent, cover colours and their fades, window opacity
    layout_prefs.dart          Corners, density and motion (Settings › Look & feel › Layout)
    beta_features.dart         Features still in Beta, each switchable in Settings › Beta features
    listen_together/           Listen together: one queue shared over the LAN or the internet
    video_mode.dart            Video mode (Beta): a YouTube song's music video on Now Playing
    youtube_stream.dart        A YouTube song's audio stream in one player request (yt-dlp is the fallback)
    usb_dac.dart / linux_alsa.dart  Direct outputs: Android USB DACs, Linux ALSA cards
    media_session.dart         System media controls (Android notification, Control Center, MPRIS)
    discord_presence.dart      Discord Rich Presence over the local IPC socket
  ui/
    home_shell.dart            Layouts: phone tabs / desktop sidebar + one history
    navigation.dart            DesktopHistory (Back/Forward), Locations, sidebar highlight
    shell/                     Desktop sidebar, phone navigation, FirstFrameGate
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

## Library model

- There is no "source" switch: Home, Search and Library always show files on
  this device, Riflay playlists and YouTube Music together.
- `Track.isRemote` (has a `videoId`) means it streams. Mark those with
  `SourceMark` / `MediaCard(online: true)`. `PlayerController.downloadedCopy`
  finds a downloaded file for a YouTube song; `_sourceFor` plays that instead,
  so `isOffline(track)` is what the UI should show.
- Riflay playlists are `UserPlaylist` (in `models/track.dart`), stored in
  SharedPreferences (`playlists.v1`) and shown as `CollectionKind.playlist`.
- Song menus get "Remove from this playlist" from a `PlaylistEditScope` above
  them (Riflay playlists and the user's own YouTube Music playlists).
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
  `shuffle()` / `setShuffleModeEnabled`.

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

## Vendored packages (`third_party/`)

| Package | Why |
|---|---|
| `just_audio_media_kit` | Exposes the libmpv player (hook + `activePlayer`) |
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

Memory: `tool/memory.sh [runs]` runs `integration_test/memory_test.dart` the
same way (profile, headless, fresh process per run) and prints PSS / private /
RSS at idle, playing a local FLAC, streaming YouTube and after scrolling.
Compare medians of several complete runs; debug builds are meaningless here.

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

  A bug that goes away with one of them on is in that shortcut. Tests can set
  `DebugSwitches.*` directly and reset them in `tearDown`.
- `themeCacheStats` (`theme.dart`) counts themes built and served from cache.

## Releases

1. Bump `version:` in `pubspec.yaml` (the `+` build number by one) and
   `appVersion` in `lib/app_version.dart` (shown in Settings › About;
   `test/about_test.dart` fails when they differ), and commit them as
   `chore: <version>`.
2. Tag and push: `git tag v<version> && git push origin main v<version>`.
   `.github/workflows/release.yml` builds Android, Windows, Linux, macOS and
   iOS and publishes the GitHub release with generated notes.

## Conventions

- Match the surrounding code: comment *why*, not what; doc comments on public
  members; 120-column `dart format`.
- A failing network call shows a message (SnackBar via `PlayerController.errors`)
  and never leaves a dead button. A control that can't act is disabled, never
  silently ignored.
- Desktop navigation is one browser-style history (`DesktopHistory`): open
  screens with `ShellScope.of(context).open(page, location: …)` so the sidebar can
  highlight them. Phones keep one stack per bottom tab.
- Wheel scrolling: give new vertical scroll views a `SmoothScrollController`
  (or wrap them in `SmoothScroll`).
- Overlays above content (sticky headers) must not swallow clicks: wrap
  backgrounds in `IgnorePointer`.
- Commits follow [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat(audio): …`, `fix(ytmusic): …`). Don't commit unless asked.
- Never commit secrets, cookies or session files.
