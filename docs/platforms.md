# Audio and platform notes

## YouTube Music

All public YouTube Music features work without an account. **Sign in with Google** opens Google's own sign-in page, in a separate window on Linux and inside the app on other platforms. Once the sign-in completes, the session is stored in the app's private storage on your device. Riflay never sees your password, and nothing is sent anywhere except to YouTube Music itself.

Changes you make (likes, playlists) go through YouTube Music's own API, so they also appear in the official apps.

## Audio

Every platform plays through [libmpv](https://mpv.io), using Riflay's own build where the stock one lacks filters (Windows, Android, macOS, iOS; see `tool/build_libmpv_*.sh`). The audio settings are therefore the same on every platform:

| Area | Details |
|---|---|
| **Playback** (Settings › Sound) | Equalizer with presets and automatic headroom, volume leveling (ReplayGain per song or album), gapless playback, **Virtual speakers** (MIT's KEMAR HRTF: two speakers at ±30°), headphone crossfeed, **Mono audio** (both ears, left only or right only) |
| **Output & quality** | Output sample rate; SoX resampler; buffer size. On desktop also: output device, including direct ALSA hardware on Linux; **bit-perfect mode**; **exclusive mode** (WASAPI on Windows, Core Audio hog mode on macOS); **native DSD (DoP)** for DSF, DSDIFF and SACD songs; **ASIO** on Windows; **audio plugins** through [Carla](https://kx.studio/Applications:Carla). On Android 14 and later with a USB DAC: **bit-perfect mode** and **native DSD (DoP)**. On iOS: the output picker, and a USB DAC follows each song's sample rate |
| **Play on** | DLNA / UPnP renderers and classic AirPlay speakers, found on the network. Files the device cannot play (DSD, cue-sheet songs, WavPack, ...) are converted to FLAC on the fly; YouTube songs are sent as AAC; AirPlay receives ALAC |
| **Signal path** | Source codec and stored bit depth → decoder → every DSP stage → volume → resampler → output device, with a verdict: *Bit-perfect*, *Lossless to the system mixer* or *Processed* |

Not yet verified on real hardware: ASIO, exclusive mode, and casting to physical TVs and speakers (tested under Wine, against a simulated renderer and shairport-sync). On macOS and iOS: everything beyond the automated checks GitHub's runners perform. Reports from real devices are welcome.

## Platform notes

| | Linux | Windows | macOS | Android | iOS |
|---|---|---|---|---|---|
| Sound settings, signal path | ✓ | ✓ | ✓ | ✓ | ✓ |
| Output device, bit-perfect, DSD, exclusive | ✓ | ✓ | ✓ | partial¹, untested | partial², untested |
| ASIO | not needed³ | ✓ | not needed³ | N/A | N/A |
| Add a folder | ✓ | ✓ | ✓ | ✓ | ✓, untested |
| Tag editor, cover art | ✓ | ✓ | ✓ | partial⁴ | ✓, untested |
| AirPlay | ✓ | ✓ | untested | untested | partial⁵, untested |
| Play on TVs (DLNA), with conversions | ✓ | ✓ | untested | untested | partial⁵, untested |
| Discord | ✓ | ✓ | ✓ | N/A⁶ | N/A⁶ |
| Audio plugins (Carla) | ✓ | ✓⁷ | ✓⁷ | N/A⁷ | N/A⁷ |
| See-through window | ✓ | untested⁸ | untested⁸ | ✓⁸ | N/A⁸ |
| Video mode | ✓ | untested | untested⁹ | untested⁹ | untested⁹ |

✓ means the feature works and has been verified (tests, CI on that OS, an emulator or Wine). **untested** means it is built for that OS but has not yet been tried on a real device; reports from real devices are welcome.

1. Android 14 and later with a USB DAC: bit-perfect mode sends the song to the DAC untouched through Android's bit-perfect USB output, and native DSD goes as DoP when the DAC accepts 176.4 kHz. Android chooses the output itself (a plugged-in USB DAC), so there is no picker or exclusive mode.
2. Pick the output (speaker, Bluetooth, AirPlay, a USB DAC) with the system picker. A USB DAC follows each song's sample rate (FLAC, WAV, AIFF, WavPack). iOS always mixes, so it is never bit-perfect, and DSD plays as PCM.
3. ASIO is a Windows driver standard. Linux and macOS have the same direct path to the DAC built in: bit-perfect mode (ALSA's hardware device) and exclusive mode (Core Audio's hog mode), in the row above.
4. Songs added with **Add songs** can be edited. Songs read in place from a folder are read-only to apps since Android 11. Matroska (.mka) tags can be edited on computers only.
5. Playing and converting work. Finding speakers and TVs on the network normally requires a multicast permission from Apple that a sideloaded app cannot have. AirPlay sends 44.1 kHz / 16-bit everywhere (AirPlay 1).
6. Phones give other apps no connection to Discord.
7. Carla is a separate free download: unzip it into Downloads or Program Files on Windows, put Carla.app in Applications on macOS. Android has no plugin standard, and iOS's AUv3 plugins are not supported yet.
8. A blur behind the window on Windows 11 and macOS (plain transparency on Windows 10); the home-screen wallpaper on Android. iOS does not let apps show the wallpaper.
9. Riflay's own player builds for these systems carry H.264 and VP9 video decoders (hardware decoding where the device has it), but Video mode has not been tried on a real device yet. Phones get a lighter stream. Video mode shows songs that are videos on YouTube Music, and with a signed-in account also the music video YouTube Music pairs with a song.

YouTube streams through YouTube's player API everywhere, with yt-dlp (desktop) or a built-in extractor (phones) as the fallback. yt-dlp needs a JavaScript runtime (Deno or Node) for some YouTube challenges.

No additional installation is required. Conversions for AirPlay and TVs, and the tag editor, run inside Riflay (libmpv and its own tag writers). FFmpeg is used only for AirPlay and TV conversions on Windows and for Matroska tags on computers: a system one where one exists; otherwise the official static build (gyan.dev on Windows, johnvansickle.com on Linux, Martin Riedl's on macOS, about 40 MB) is downloaded on first use, checked against its published checksum and stored in the app's folder.

The macOS app is not signed by Apple. On first launch, open it from System Settings › Privacy & Security › **Open Anyway**. The iOS `.ipa` is unsigned as well; sideload it with AltStore or Sideloadly.

Debug builds append every Flutter error with its full stack trace to `<app support dir>/errors.log` (on Linux, `~/.local/share/dev.riflay.riflay/errors.log`).
