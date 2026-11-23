# Riflay TUI

`riflay-tui` is Riflay in a terminal. It works two ways:

- **With the Riflay desktop app open**, it is the app's remote: the app plays, the terminal shows and controls it
  (the same queue, library, playlists and settings). It talks to the app's [CLI service](cli.md).
- **Without the app**, it plays on its own: your Riflay library and playlists when Riflay is installed (read only),
  else the songs in your Music folder; YouTube Music search; radio and autoplay; lyrics with their pronunciation
  and translation; covers; Discord Rich Presence.

It is built to be light: it draws only when something changes, sleeps while nothing plays, and asks for the
visualizer's levels only while the visualizer is on. Idle it uses no CPU and a few MB of memory.

## Install

`riflay-tui` comes with Riflay, next to `riflay-cli`: Scoop, Homebrew, the Arch package and the .deb/.rpm put it on
the PATH; with the Windows installer or the zip it is in Riflay's folder.

## Icons: install a Nerd Font

riflay-tui draws its icons from a [Nerd Font](https://www.nerdfonts.com). Install one (JetBrainsMono Nerd Font,
CaskaydiaCove Nerd Font…) and pick it as your terminal's font:

```sh
scoop bucket add nerd-fonts; scoop install JetBrainsMono-NF     # Windows
brew install --cask font-jetbrains-mono-nerd-font               # macOS
```

On Linux, your package manager's `nerd-fonts` package, or a font from the site. Without one the icons show as boxes:
start it with `--plain-icons` (or set `RIFLAY_TUI_ICONS=plain`) for plain symbols.

## Build

```sh
cd tui
cargo build --release
./target/release/riflay-tui        # riflay-tui.exe on Windows
```

## What it needs on its own

| For | Needs |
|---|---|
| Playing anything | libmpv (mpv's library): installed with Riflay, or `mpv` / `libmpv` from your package manager. `RIFLAY_LIBMPV` points at it anywhere else. |
| YouTube Music songs | `yt-dlp` on the PATH (or the one Riflay downloaded) |
| YouTube Music search and radio, lyrics and their translation, online covers | `curl` (built into Windows 10+, macOS and most Linux) |
| Discord Rich Presence | the Discord app, open |

`RIFLAY_MUSIC_DIR` picks the folder it plays when Riflay isn't installed (default: Music in your home folder).
`RIFLAY_LANG` the language lyrics are translated to (default: Riflay's setting, else your computer's language).
Autoplay and Discord start as Riflay's settings say when Riflay is installed (autoplay on, Discord off otherwise).
SoundCloud and the app's other services need the app.

## Options

```sh
riflay-tui                 # the app if it is open, else on its own
riflay-tui --standalone    # on its own even when the app is open
riflay-tui --remote        # only the app's remote (waits for it)
riflay-tui --endpoint PATH # the app's CLI endpoint file
riflay-tui --plain-icons   # plain symbols instead of a Nerd Font's icons
```

## Keys

| Key | |
|---|---|
| `space` | play / pause |
| `n` `p` | next / previous |
| `←` `→` | seek 5 s (`[` `]` 30 s) |
| `+` `-` | volume |
| `s` `r` | shuffle / repeat |
| `1`–`5`, `Tab` | Queue, Lyrics, Search, Library, Playlists |
| `↑` `↓`, `j` `k` | move (`PgUp` `PgDn`, `g` `G`) |
| `Enter` | play the selected song or playlist |
| `a` `i` | add to the queue / play next |
| `d` | remove from the queue |
| `/` | search (`Tab` while typing: library, YouTube Music, SoundCloud) |
| `v` `c` | visualizer / cover |
| `o` `t` | lyrics: pronunciation (for lines in another script) / translation |
| `R` | radio: the selected song's (or the current one's) similar songs |
| `A` | autoplay: similar songs when the queue runs out |
| `D` | show what plays on Discord |
| `?` | all keys |
| `q` | quit (with the app, it keeps playing) |

## How the app side works

These CLI commands exist for live clients (and `radio`, `autoplay` and `discord` for anyone):

- `subscribe` keeps the connection open and sends a JSON line for each change: a `status` event (with `at`, the app's
  clock, to count the position on from: no position ticks are sent), and with `levels on` the visualizer's levels
  about 20 times a second while a song plays.
- `lyrics` returns the current song's timed lines (or plain text); `lyrics.extras` each line's pronunciation and
  translation (Google Translate, as the app shows them).
- `cover --size N` returns the current song's cover, cropped square, as base64 RGB pixels: the terminal needs no
  image decoder.

The standalone player answers the same commands with the same JSON, so the screens don't know which one they talk to.
