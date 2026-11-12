> [!WARNING]
> **Free and Open-Source Android is under threat.**
>
> Google will turn Android into a locked-down platform, restricting your essential freedom to install apps of your choice. Make your voice heard.
>
> **[Keep Android Open](https://keepandroidopen.org).**

> [!NOTE]
> **Riflay is in maintenance mode.** Work is limited to fixing issues: bug reports are welcome, new features
> are on hold for now.

<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/icon/riflay-transparent.svg">
  <img src="assets/icon/riflay-transparent-light.svg" width="112" height="112" alt="Riflay logo">
</picture>

# Riflay

**Your local music and YouTube Music, together in one hi-fi player.**

Free and open source, for Linux, Windows, macOS, Android and iOS.

[![License: AGPL v3](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)
![Platforms](https://img.shields.io/badge/platforms-Linux%20%7C%20Windows%20%7C%20macOS%20%7C%20Android%20%7C%20iOS-555)
[![Latest release](https://img.shields.io/github/v/release/Araryarch67/Riflay)](https://github.com/Araryarch67/Riflay/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/Araryarch67/Riflay/total)](https://github.com/Araryarch67/Riflay/releases)

![Riflay home](docs/screenshots/home.webp)

| ![Full-screen player](docs/screenshots/fullscreen.webp) | ![Lyrics](docs/screenshots/lyrics.webp) |
|---|---|
| ![Signal path](docs/screenshots/signal-path.webp) | <img src="docs/screenshots/phone.webp" alt="Riflay on a phone" width="260"> |

</div>

## What makes it different

- **Local files and YouTube Music in one library.** Mix both in the same playlist; no account needed, sign in only to sync. Import playlists from Spotify, Apple Music, Deezer, TIDAL or NetEase Cloud Music.
- **Real hi-fi.** Bit-perfect output, native DSD (DoP), exclusive mode and ASIO, with a **signal path** that shows every stage from file to speaker. FLAC, ALAC, WavPack, APE, DSD, SACD ISO and cue sheets.
- **Sound tools usually found in pro apps.** Virtual speakers (HRTF) for headphones, crossfeed, room correction from REW, and VST / LV2 / CLAP plugins through Carla.
- **Lyrics that follow every word**, from many free sources, with pronunciation and translation.
- **Music videos.** Watch a song's video in step with it, or use it as the Now Playing background.
- **Listen together, anywhere.** Friends play along in sync over the same Wi-Fi or the internet, end-to-end encrypted.
- **Build your own player.** Pick the cover, top, buttons, progress bar, controls and bottom row one by one, or start from a preset (Classic, Stacked, Kawaii). On phone and desktop.
- **Free FLAC sources.** Search shows FLAC recordings from the Internet Archive's curated collections (Live Music Archive concerts, netlabel releases), and the search page carries Radio Paradise's FLAC channels.
- **Riflay Wrap** and listening stats, kept on your device.
- **Light on your computer.** Lightweight, Balanced and Heavy performance modes; under 2% CPU and 200 MB while playing on Windows, even with a music video.

## Install

Every file is on the [latest release](https://github.com/Araryarch67/Riflay/releases/latest), with `SHA256SUMS`.

| System | Install |
|---|---|
| Windows | `scoop bucket add riflay https://github.com/Araryarch67/scoop-riflay` then `scoop install riflay/riflay`, or the `setup.exe` / `.zip` |
| Debian, Ubuntu, Mint | `sudo apt install ./Riflay-linux-amd64.deb` |
| Fedora / openSUSE | `sudo dnf install ./Riflay-linux-x86_64.rpm` / `sudo zypper install ./Riflay-linux-x86_64.rpm` |
| Arch | `sudo pacman -U Riflay-linux-x86_64.pkg.tar.zst` |
| Linux or macOS, with Homebrew | `brew install --cask araryarch67/riflay/riflay` |
| Any Linux | the `.AppImage` (`chmod +x`, then run it) |
| Android | `Riflay-android.apk` (Android 7.0 and later) |
| macOS | `Riflay-macos.dmg` (macOS 12 and later) |
| iOS | `Riflay-ios-unsigned.ipa`, sideloaded with AltStore or Sideloadly |

The macOS app is unsigned: on first launch use System Settings › Privacy & Security › **Open Anyway**. The iOS file is attached to a release a little after the others.

## System requirements

| System | Version | Processor |
|---|---|---|
| Windows | 10 or 11, 64-bit | x64 |
| Linux | a 64-bit distribution with GTK 3, on Wayland or X11, and a working OpenGL driver; PipeWire, PulseAudio or ALSA | x86_64 |
| macOS | 12 Monterey or later | Apple silicon or Intel |
| Android | 7.0 or later | arm64, arm32 or x86_64 |
| iOS | 15 or later (sideloaded) | arm64 |

On a computer Riflay picks a performance mode at first start (Settings › Power & background changes it):

| | Lightweight | Balanced | Heavy |
|---|---|---|---|
| Suits | under 8 GB of memory, or fewer than 8 processor threads | laptops and most desktops | desktops with 16+ threads and 16+ GB |
| Moves | the seek bar, about once a second | cover and wave at 5 fps, visualizer at 10 | everything at 30 fps |
| CPU while a song plays, in front | ~3% of one thread | ~8% | ~14% |

Phones keep Balanced, except one with under 4 GB of memory, which starts in Lightweight (the music video at 720p
instead of 1440p). At least 4 GB of memory is recommended on a computer for the system, Riflay and a browser beside it. Riflay itself measured on
Linux (release build, private memory): ~150 MB idle, ~200-230 MB playing or scrolling a library of covers, ~300 MB
with a 1080p music video, and 65-110 MB while it plays behind other windows (it hands unused memory back to the
system then; Windows does the same). Behind other windows every mode draws about one frame a second. The app takes
about 40 MB on disk on Linux (plus the system's libmpv) and a few hundred MB elsewhere, where libmpv comes with it;
downloads and the cover cache need room of their own.

## Build from source

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable) and the desktop toolchain; on Linux also `clang`, `cmake`, `ninja`, `pkg-config`, GTK 3, the `libmpv` headers and `libayatana-appindicator3` (the tray icon; `libayatana-appindicator3-dev` on Debian and Ubuntu).

```sh
git clone https://github.com/Araryarch67/Riflay.git
cd Riflay
flutter pub get
flutter run -d linux          # or: windows, macos, android, ios
```

## More

- [Riflay CLI](docs/cli.md): control the desktop player from a terminal or AI agent, with JSON output.
- [Audio and platform notes](docs/platforms.md): YouTube Music sign-in, every audio setting, and what works on which system.
- [Riflay in a browser](docs/web.md): the web version and its proxy.
- [Contributing](CONTRIBUTING.md) and [AGENT.md](AGENT.md) (how the code is organized and tested).

## Acknowledgements

Riflay builds on the work of:

| Project | Used for | License |
|---|---|---|
| [mpv](https://mpv.io) / [media_kit](https://github.com/media-kit/media-kit) | Playback | LGPL-2.1-or-later |
| [just_audio](https://github.com/ryanheise/just_audio) | Playback | MIT |
| [FFmpeg](https://ffmpeg.org) | Decoding and filters | LGPL-2.1-or-later; some builds enable GPL components |
| [SoX's resampler](https://sourceforge.net/projects/soxr/) | Resampling | LGPL-2.1-or-later |
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | YouTube audio | Unlicense |
| [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) | YouTube audio | MIT |
| [ytmusicapi](https://github.com/sigma67/ytmusicapi) | Documentation of YouTube Music's API, which this app follows | MIT |
| [LRCLIB](https://lrclib.net), [Better Lyrics](https://betterlyrics.org), Kugou, NetEase Cloud Music, QQ Music, Musixmatch, [Megalobiz](https://www.megalobiz.com), [Genius](https://genius.com), [lyrics.ovh](https://lyrics.ovh) | Free lyrics | Various; see each project |
| [audio_metadata_reader](https://github.com/ClementBeal/audio_metadata_reader) | Tags | MIT |
| Bill Gardner and Keith Martin's [KEMAR HRTF measurements](https://sound.media.mit.edu/resources/KEMAR.html) (MIT Media Lab) | Virtual speakers and its 7.1 room | MIT |
| [Internet Archive](https://archive.org) | Free FLAC recordings in search, streamed from archive.org | Each recording's own license |
| [Radio Paradise](https://radioparadise.com) | Listener-supported FLAC radio channels | Free to listen; please support them |
| [AutoEq](https://github.com/jaakkopasanen/AutoEq) by Jaakko Pasanen, with measurements by crinacle, oratory1990 and others | Headphone / IEM equalizer profiles, downloaded when picked | MIT |
| [akagi](https://github.com/z0orb/akagi) | Ideas behind playlist reordering and Downloads storage overview (re-implemented, no code copied) | MIT |
| [liquid_glass_renderer](https://github.com/whynotmake-it/flutter_liquid_glass/tree/main/packages/liquid_glass_renderer) | The phone's Liquid glass tab bar | Apache-2.0 |
| Apple Music on iOS 26 | Idea behind the Liquid glass tab bar that shrinks to one row on scroll and carries the search field (re-implemented, no code copied) | — |

### Special thanks

**[Houshou Marine](https://www.youtube.com/@HoushouMarine)** (hololive). Her song "きゃぴ - Kyapi" and its music video are
the reference test for Riflay's performance work. Every CPU and memory target is measured while it plays: the music video,
the synced lyrics with their pronunciation, and full screen. The song and video are streamed from YouTube when the test
runs; nothing of them ships with Riflay.

Riflay is not affiliated with YouTube, Google, Discord, Apple, hololive or COVER Corporation.

## License

Riflay is free software: you can redistribute it and/or modify it under the terms of the **GNU Affero General Public License v3.0** as published by the Free Software Foundation. See [LICENSE](LICENSE).

If you run a modified version for others over a network, the AGPL asks you to offer them its source too.

Vendored packages in [`third_party/`](third_party) keep their own licenses: Unlicense for `just_audio_media_kit`, MIT for `audio_metadata_reader` and the `media_kit_libs_*` packages, and GPL-3.0-or-later or the Steinberg ASIO license for `asiosdk` (see its [license file](third_party/asiosdk/LICENSE.txt)). Flutter and Dart packages generally use MIT or BSD-3-Clause licenses; each package ships its own license in the dependency cache. Native dependencies and downloaded tools retain their upstream licenses; in particular, FFmpeg may be built with optional GPL components.
