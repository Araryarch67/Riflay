# Riflay in a browser

Riflay also runs in a browser as a YouTube Music player. Browsers may not call YouTube Music directly (CORS), so the web version talks to a small proxy you run yourself, [`tool/web_proxy`](tool/web_proxy). It forwards only the requests Riflay makes (YouTube Music, song streams, covers and lyrics), keeps nothing about who listens to what, and logs no requests.

**What works:** Home, Search, albums, artists and playlists, the queue, autoplay, synced lyrics, Riflay playlists (kept in the browser), themes and appearance, the player bar and Now Playing. YouTube Music is used signed out.

**What doesn't:** your music folders and anything on files (tag editor, duplicates, converting), downloads, signing in to Google or Spotify and playlist imports, casting, Listen together, Discord, the equalizer and every sound setting (bit-perfect, exclusive mode, crossfade, Virtual speakers and the rest), Video mode, the mini player and the listening history. These are hidden in the web version.

Run the proxy and serve the app from it, so both share one address:

```sh
flutter build web --release
cd tool/web_proxy
dart pub get
dart run bin/server.dart --web ../../build/web     # http://127.0.0.1:8787
```

Or run the proxy on its own (also as a container) and point the app at it:

```sh
docker build -f tool/web_proxy/Dockerfile -t riflay-web-proxy .
docker run --rm -p 8787:8787 riflay-web-proxy
flutter run -d chrome --dart-define=RIFLAY_PROXY=http://127.0.0.1:8787/
```

`dart run bin/server.dart --help` lists the options: `--host 0.0.0.0` to listen beyond this computer, `--allow-origin https://your.site` to accept only your own page, and `--trust-forwarded` behind your own reverse proxy so the rate limit sees real addresses. Each address gets about two YouTube Music requests a second (song bytes are not counted); a song's stream URL is remembered until shortly before it expires.
