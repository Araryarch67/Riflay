# Spotify playback

Sign in on the **Spotify** page, then tap a playlist or album: it opens as a page of songs that play from
Spotify itself. The tick beside each row still picks what to copy to YouTube Music / Riflay. Needs the
person's own **Spotify Premium**. Windows only for now; elsewhere the page only imports, as before.

## How it works

- `tool/spotify_bridge` (Rust: librespot-core / -metadata / -audio 0.8, no librespot-playback) is built by
  `tool/build_spotify_bridge.ps1` from `windows/CMakeLists.txt` into `spotify_bridge.exe` beside the app.
  Without cargo the build skips it and the app goes without playback (`SpotifyBridge.supported`).
  `RIFLAY_REQUIRE_SPOTIFY_BRIDGE` makes a missing cargo fail the build; `RIFLAY_NO_SPOTIFY_PLAYBACK` turns
  playback off at run time.
- `Cargo.lock` is committed and pins vergen 9.0.6: librespot-core 0.8.0's build script doesn't compile
  against 9.1. Build with `--locked`.
- `lib/services/spotify_bridge.dart` starts the bridge on the first Spotify song and talks JSON lines on its
  stdin / stdout (`hello`, `login {token}`, `logout`). The bridge ends when Riflay closes its stdin.
- The bridge serves `GET /<secret>/<track id>` on a loopback port: the track's Ogg Vorbis file (320 kbps,
  then lower), decrypted, with Range. `SpotifyAudioSource` passes it to mpv through just_audio's loopback
  server, so seeking, the equalizer, crossfade, gapless and the signal path work as for any stream.
- A Spotify track is `Track.spotify`: id `sp:<trackId>`, `sourceUrl` its open.spotify.com page, no
  `videoId`. `SpotifyLibraryClient.songs` gives each song its `ForeignSong.native`.

## Sign-in

The first sign-in hands librespot the web player's token (`SpotifyAccount.auth`). librespot then keeps
reusable credentials of its own in the app's private folder (`spotify_bridge/credentials.json`), used by
later launches and deleted on sign-out.

**Not confirmed against a live account yet:** whether Spotify's access points accept the web player's token.
If they refuse it, the bridge needs librespot-oauth's browser sign-in instead.

## Limits

- Streaming only: no downloads and no disk cache of Spotify's audio.
- Not cast: the audio only leaves the bridge on this device's loopback.
- Ogg Vorbis up to 320 kbps; Spotify's lossless isn't available through librespot.
- Autoplay after a Spotify song follows YouTube Music's radio for its match by name.
- librespot is unofficial and outside Spotify's terms for third-party clients; it can stop working without
  notice, and the account used carries that risk.

## Debugging

`RIFLAY_SPOTIFY_LOG=1` makes the bridge log to stderr. Riflay doesn't read it, so run the bridge by hand:
`spotify_bridge.exe <state folder>`, then type `{"id":1,"method":"hello"}`.

Tests: `test/spotify_playback_test.dart`; `cargo test --locked` in `tool/spotify_bridge`.
