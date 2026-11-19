# Advanced player audit

The matrix reflects source inspection before extending the 89-item checklist. Implemented means a production path was identified. Physical-device verification is tracked separately.

## Audio

| Feature | Status | Existing implementation | Required work or identified behavior |
|---|---|---|---|
| Audio quality selection | Partial | youtube_player_api.dart | Selects original stream; expose supported levels. |
| Data saver | Missing | youtube_player_api.dart | Coordinate stream bitrate and prefetch with network conditions. |
| Crossfade switch | Implemented | crossfade.dart | audio_engine and crossfade |
| Crossfade duration | Implemented | crossfade.dart | crossfade, 1–12 seconds |
| Gapless album exception | Implemented | crossfade.dart | crossfade checks adjacent album tracks and discs. |
| Playback history duration | Partial | play_history.dart | play_history bounds count rather than age. |
| Silence skipping | Implemented | audio_engine.dart | audio_engine uses silenceremove on compatible builds. |
| Instant silence skipping | Partial | audio_engine.dart | Add tested fast thresholds to existing silence filter. |
| Audio normalization | Implemented | audio_engine.dart | audio_engine uses ReplayGain with measured fallback. |
| Normalization target including −7 | Partial | audio_engine.dart | Target and mpv preamp in current changes. Validate extended range and peak handling. |
| Audio offload | Unsupported | youtube_player_api.dart | android_output does not own a compressed-offload AudioTrack. |
| Varispeed | Partial | audio_engine.dart | audio_engine has tempo and pitch. Add coupled pitch behavior. |
| Hardware AudioTrack speed and pitch | Unsupported | youtube_player_api.dart | libmpv owns output. Hardware acceleration is not guaranteed by Android PlaybackParams. |
| Progressive seek | Missing | youtube_player_api.dart | Centralize seek increments and held-input acceleration. |

## Sleep and alarms

| Feature | Status | Existing implementation | Required work or identified behavior |
|---|---|---|---|
| Automatic sleep timer | Partial | sleep_timer.dart | Duration and clock deadlines exist. Add automatic arming. |
| Repeat sleep timer | Missing | sleep_timer.dart | Persist a recurring arming policy. |
| End of track | Implemented | sleep_timer.dart | startEndOfSong handles a song or a count. |
| Gradual fade | Implemented | sleep_timer.dart | Existing fade envelope and gain restoration. |
| Playback alarms | Missing | sleep_timer.dart | Native wake scheduling and permission flow needed. |
| Scheduled playlists | Missing | sleep_timer.dart | Resolve persisted playlist identity when alarm fires. |
| Exact alarm permission | Missing | sleep_timer.dart | Android manifest, Settings handoff and capability detection needed. |
| Battery optimization guidance | Partial | sleep_timer.dart | Power settings include exemption guidance; integrate with alarm reliability. |

## Queue and playback

| Feature | Status | Existing implementation | Required work or identified behavior |
|---|---|---|---|
| Persistent queue | Missing | player_controller.dart | Restore occurrence order, index and position without autoplaying on launch. |
| Load more tracks | Implemented | player_controller.dart | Near-end autoplay extends queue. |
| Generate radio queues | Implemented | player_controller.dart | Existing radio lookup and new regenerate action. |
| Autoplay | Implemented | player_controller.dart | Persisted switch. |
| Autoplay without repeats | Partial | player_controller.dart | Excludes current queue and recent 30 tracks. |
| Disable loading in repeat-all | Implemented | player_controller.dart | Loop mode must be off for autoplay. |
| Auto-download likes | Missing | player_controller.dart | Wire confirmed likes to provider-aware download queue. |
| Similar recommendations | Implemented | player_controller.dart | Existing similar-song autoplay. |
| Persistent shuffle | Partial | player_controller.dart | shuffle.dart spreads artists; retain realized order on restart. |
| Remember repeat and shuffle | Partial | player_controller.dart | Loop mode restored. Shuffle lacks persisted session state. |
| Shuffle playlist before radio | Implemented | player_controller.dart | Radio appends after existing shuffled order. |
| Move existing duplicate | Partial | player_controller.dart | Intentional duplicate occurrences are supported; add opt-in behavior. |
| Skip failed tracks | Implemented | player_controller.dart | Recovery can advance to next playable item. |
| Stop on close | Partial | player_controller.dart | system_tray distinguishes hiding from exiting; platform close policies differ. |
| Pause on media mute | Missing | player_controller.dart | Observe OS stream mute independently of app volume. |
| Resume on Bluetooth reconnect | Missing | player_controller.dart | Remember route-loss pause reason and respond only to matching reconnection. |
| Keep screen awake in player | Partial | player_controller.dart | power_policy supports foreground playback; add route-specific option. |
| Animated artwork | Partial | player_controller.dart | spotify_canvas provides provider-specific video artwork. |
| Video mode | Implemented | player_controller.dart | video_mode and video_engine |
| Select video result to play video | Partial | player_controller.dart | youtube_video_search returns video results; verify mode selection on every entry point. |

## Appearance

| Feature | Status | Existing implementation | Required work or identified behavior |
|---|---|---|---|
| Appearance styles and glass | Implemented | layout_prefs.dart | appearance.dart and player_presets |
| Rounded icon styles | Partial | layout_prefs.dart | Rounded glyphs and selectable corners exist. No app-wide icon family selector identified. |
| Glass blur | Implemented | layout_prefs.dart | Appearance blur and lightweight fallback. |
| Lens effects | Implemented | layout_prefs.dart | player_glass on supported renderer. |
| Collapse navigation on scroll | Partial | layout_prefs.dart | Inspect scroll behavior across phone_navigation variants. |
| iOS-style animations | Partial | layout_prefs.dart | page_motion provides transitions. Validate interactive transitions. |
| Home listening streak | Implemented | layout_prefs.dart | listening_streak and home_page |
| High refresh mode | Missing | layout_prefs.dart | Add native display-mode negotiation. |
| Landscape scaling | Missing | layout_prefs.dart | Keep independently scalable from text accessibility. |
| Theme color | Implemented | layout_prefs.dart | Custom accent and cover-generated palettes. |
| Dynamic launcher colors | Partial | layout_prefs.dart | The in-app mark follows theme. OS launcher tint needs native resources. |
| Launcher icon styles | Missing | layout_prefs.dart | Package platform icon variants. |
| Theme management | Implemented | layout_prefs.dart | appearance.dart and theme selection |
| Alternative mini-player | Implemented | layout_prefs.dart | Classic, capsule and glass variants. |
| Mini-player background | Partial | layout_prefs.dart | Cover-derived color and glass exist. No independent override identified. |
| Swipe change track | Implemented | layout_prefs.dart | mini_player horizontal drag. |
| Swipe sensitivity | Missing | layout_prefs.dart | Thresholds currently fixed. |
| Alternative full player | Implemented | layout_prefs.dart | player_presets |
| Player background | Implemented | layout_prefs.dart | appearance.nowPlaying |
| Hide artwork and show logo | Partial | layout_prefs.dart | app_logo and placeholder exist. Need explicit player cover selection. |
| Full-screen artwork | Implemented | layout_prefs.dart | PlayerCover.background |
| Square artwork | Implemented | layout_prefs.dart | PlayerCover.square |
| Playback button colors | Partial | layout_prefs.dart | Theme-derived colors exist. Add scoped override with readable contrast. |
| Progress slider styles | Implemented | layout_prefs.dart | ProgressBarShape and ProgressBarStyle |

## Lyrics and overlay

| Feature | Status | Existing implementation | Required work or identified behavior |
|---|---|---|---|
| Experimental lyrics mode | Partial | lyrics_view.dart | Existing beta features; define independent experimental behavior. |
| Lyrics text alignment | Implemented | lyrics_view.dart | LayoutPrefs.lyricsAlign |
| Dim inactive lyrics | Implemented | lyrics_view.dart | LayoutPrefs.dimUnsungLyrics |
| Vocal-role alignment | Missing | lyrics_view.dart | Requires per-line role data from parser and provider. |
| Tap lyrics to seek | Implemented | lyrics_view.dart | Synced lyric line gestures. |
| Auto-scroll lyrics | Implemented | lyrics_view.dart | Timeline-based scrolling. |
| Hide status bar in full-screen lyrics | Partial | lyrics_view.dart | video_full_view uses immersive mode. Apply and restore per lyrics route. |
| Dynamic Island overlay | Partial | lyrics_view.dart | mini_window supports desktop floating capsule. Android overlay needs separate permission and service. |

## Navigation and automatic playlists

| Feature | Status | Existing implementation | Required work or identified behavior |
|---|---|---|---|
| Startup tab | Missing | library_page.dart | home_shell initially selects Home. |
| Default library chip | Missing | library_page.dart | LibraryFilter starts unset. |
| Swipe left to queue | Missing | library_page.dart | Reuse queue and guest permission checks. |
| Swipe right for next | Missing | library_page.dart | Integrate with reorder gestures. |
| Swipe remove from playlist | Partial | library_page.dart | Owned playlist removal exists. Add scoped gesture with undo. |
| Force navigation bar visible | Partial | library_page.dart | Bar placement is configurable; add independent visibility policy. |
| Hide navigation labels | Partial | library_page.dart | Different bar layouts have different labels. Add explicit preference. |
| Grid cell size | Partial | library_page.dart | CoverSize and density exist. Verify all grid layouts. |
| UI scale including 100% | Partial | library_page.dart | Text scale and density exist. Native UI scaling remains separate. |
| Liked playlist visibility | Partial | library_page.dart | Real connected liked collection exists. Add visibility preference. |
| Downloaded playlist visibility | Partial | library_page.dart | Real offline collection exists. Add visibility preference. |
| Top Tracks visibility | Partial | library_page.dart | smart_playlists provides mostPlayed. Add visibility preference. |
| Saved playlist visibility | Partial | library_page.dart | Distinguish user library saves from all local tracks. |
| Uploaded playlist visibility | Unsupported | library_page.dart | No verified personal uploads collection exposed by current provider model. |

## Dependency order

1. Extend existing settings and renderer controls, with persistence and disabled-state tests.
2. Implement queue restoration before persistent shuffle or recurring playback actions.
3. Add platform scheduling, audio route and launcher integrations only with capability checks and native lifecycle tests.
4. Exercise real libmpv and Android devices before promoting audio and background features to verified status.


## Changes since the initial audit

| Feature | Production behavior | Files |
|---|---|---|
| Streaming quality and data saver | Automatic selection or a bitrate ceiling for YouTube audio. Data saver applies a 64 kbps ceiling and suppresses ahead-of-track prefetch. | sound_settings.dart, music_sources.dart, youtube_player_api.dart, youtube_stream.dart |
| Listening history duration | History settings persist the retention period and expire older entries. | play_history.dart, privacy_settings.dart |
| Varispeed and normalization target | The native engine can couple pitch to tempo. ReplayGain uses the selected loudness target. Physical playback verification is pending. | audio_engine.dart, sound_settings.dart |
| Startup tab, default library category and mini-player swipe sensitivity | Layout preferences feed shell startup, library filtering and the gesture threshold. | layout_prefs.dart, home_shell.dart, library_page.dart, mini_player.dart |
| Liked, Downloaded and Top Tracks visibility | Library settings control visibility of the corresponding real collections. | library_settings.dart, library_page.dart |
| Liquid Glass | Theme, light and black tints apply to the player and glass navigation, including its selected button. | player_glass.dart, phone_navigation.dart, appearance_settings.dart |
| Cache and search privacy | Library & downloads contains Storage & cache and Privacy. Cache budgets, cache clearing and search-history removal are indexed at their owning pages. | storage_settings.dart, settings_index.dart, settings_page.dart |
## Follow-up after v1.7.0

| Feature | Production behavior | Files |
|---|---|---|
| Queue and shuffle persistence | Restores the saved order and current occurrence in the paused player. Checkpoints use queue changes, seeks, pauses and lifecycle events. The original order remains available when shuffle is turned off. | player_controller.dart |
| Seek steps | Playback settings persist the step size or disable keyboard seek steps. Shift and the arrow keys seek in the chosen increments. | sound_settings.dart, player_controller.dart, shortcuts.dart |
| MV sync | Video opens at the current audio position after stream resolution, resynchronizes on seek, and uses the audio speed and video timeline rate. Lyric-derived alignment survives a video decoder reload. | video_mode.dart, video_timing.dart, lyrics_video_alignment.dart |
| Logo cover | Choose the Riflay mark as the artwork in Now Playing, fullscreen, and the sidebar. Lightweight mode offers the logo too. | layout_prefs.dart, now_playing_page.dart, full_screen_player.dart, side_panel.dart |
| Phone navigation | The glass bar can stay expanded while scrolling. Bottom navigation labels can be hidden with accessible tab names preserved. | layout_settings.dart, phone_navigation.dart |
| Playlist order and pins | The Library offers default, alphabetical and custom ordering for Riflay, folder and connected YouTube Music playlists. Pinned playlists appear above the rest. | library_page.dart, layout_prefs.dart |
| Cover editor | The editor previews the exported square crop and supports pan, zoom, rotation, flip and reset. | playlist_cover_edit.dart |
| Song / Video placement | The sidebar switch sits above the scroll area and follows the existing Now Playing visibility preference. | side_panel.dart |
| Discord reconnection | Connection retries use backoff. The latest activity is applied when the handshake completes, including after a Discord restart. | discord_presence.dart |
| Interactive mini-player expansion | Drag follows the pointer from the mini-player bounds. A short drag settles back and a committed drag hands off to the real Now Playing route. | home_shell.dart, mini_player.dart |
| Draggable glass tab selection | The selection pill follows a horizontal drag and settles into the chosen tab on release. The tint picker labels white explicitly. | phone_navigation.dart, appearance_settings.dart |

## Remaining requirements

These rows supersede the initial status where the same item appears in both tables.

| Area | Status | Feature or remaining work | Evidence |
|---|---|---|---|
| Audio | Partial | Instant silence skipping needs a separate mode and tested filter thresholds. The standard silence filter is available on supported native builds. | `audio_engine.dart` |
| Audio | Implemented, native checks pending | The target includes −7 dB. Check ReplayGain, peak behavior, and varispeed on actual outputs with DSP, exclusive output, and bit-perfect modes. | `audio_engine.dart`, `sound_settings.dart` |
| Audio | Unsupported by current backend | Compressed AudioTrack offload and hardware AudioTrack speed and pitch need a compatible Android output backend. | `just_audio_media_kit`, `audio_engine.dart` |
| Sleep | Partial | Manual duration, end of track, and fading work. Automatic arming and recurring schedules are missing. | `sleep_timer.dart`, `sleep_timer_button.dart` |
| Alarms | Missing | Playback alarms, scheduled playlists, exact-alarm permission, and alarm-specific battery guidance. The existing battery exemption setting can be reused. | `stay_awake.dart`, `power_settings.dart`, `AndroidManifest.xml` |
| Queue | Partial | Autoplay already filters the queue and the 30 most recent tracks. Preventing repeats throughout the entire listening session needs a longer memory. | `player_controller.dart` |
| Queue | Missing | Automatically download liked tracks and optionally move existing queue entries on duplicate insertion. | `player_controller.dart`, `youtube_music_account.dart` |
| Queue | Implemented | Clear upcoming tracks and retain position on the current track. The existing regenerate action can then create a new set of recommendations. | `queue_page.dart`, `player_controller.dart` |
| Playback | Partial | Desktop Close to tray controls playback on window close. The screen wake setting covers playback and foreground app use. Mobile task-dismiss behavior and a Now Playing-only wake setting need separate handling. | `system_tray.dart`, `stay_awake.dart`, `power_policy.dart` |
| Playback | Missing | Pause on system media mute and resume on reconnection of the matching Bluetooth device. | `player_controller.dart`, native audio route channels |
| Playback | Partial | Animated artwork is available when the provider supplies it. Search results in the Videos tab start playback through the audio queue. Explicitly selecting Video mode on tap still requires wiring. | `video_mode.dart`, `remote_results.dart` |
| Appearance | Partial | Rounded glyphs are already used, with no global icon family selector. Android provides monochrome launcher resources, with tint controlled by the launcher. User-selected launcher styles are missing. | `layout_prefs.dart`, `AndroidManifest.xml`, `ic_launcher.xml` |
| Appearance | Missing | High refresh-rate mode and landscape-specific UI scaling. | `layout_prefs.dart`, native display integration |
| Player | Partial | Mini-player tint can be chosen independently in Liquid Glass. A background selector for all mini-player styles and independent playback-button colors are missing. | `mini_player.dart`, `appearance_settings.dart`, `player_parts.dart` |
| Lyrics | Missing | A separate experimental mode, alignment per vocalist role, and a status-bar preference for fullscreen lyrics. | `lyrics.dart`, `lyrics_sources.dart`, `synced_view.dart` |
| Floating player | Partial | Desktop mini-window supports always-on-top. The mobile system overlay is missing. | `mini_window.dart` |
| Navigation | Partial | Scroll collapse and keep-expanded behavior are available on the glass bar. Cover grid size presets exist. General UI scaling with native 100% and track swipes for queue, play next, and playlist removal are missing. | `phone_navigation.dart`, `layout_settings.dart`, `track_row.dart` |
| Automatic playlists | Partial or unsupported | Liked, Downloaded, and Top Tracks have visibility controls. Saved needs a real track collection. The current provider model has no verified personal uploads collection. | `library_settings.dart`, `library_page.dart`, `youtube_music_account.dart` |
