# Monochrome

Turn on **Settings > Accounts & services > Music sources > Monochrome in search**,
then select the **Monochrome** filter below the search field on the Search page. SoundCloud has its own switch
in the same settings page. Disabled services disappear from the source filters; with no
optional service enabled the source filters are hidden and YouTube Music is used.
The choice is remembered. Monochrome songs appear as song rows with download controls. They stream
from Monochrome's Tracks service; no account is required. Song menus can save them
to the library or add them to a Riflay playlist.

Paste a `https://monochrome.st/track/...`, `/album/...`, `/playlist/...` or
`/userplaylist/...` URL in the music-link dialog. On desktop, Ctrl+V outside a text
field also opens these links. Android supports Open with and shared links.
Track links play; album and playlist links open a collection with **Save as playlist**.
Library's **Import a playlist** also accepts Monochrome collections and keeps their
original streams, without replacing them with YouTube matches. Imported Monochrome
playlists are stored in Riflay even when signed in to YouTube Music.

## Smart merge

Enable **Settings > Accounts & services > Music sources > Smart merge** to keep
a YouTube Music song's cover, lyrics, music video and library identity while
playing the same recording from a lossless file in your library first, then
Monochrome when that source is enabled. With neither available, playback uses
YouTube Music. Web playback continues through the existing YouTube proxy.

Automatic matches require the same title and artist, matching version labels,
and known lengths within three seconds. Ambiguous matches are skipped. Source
lookups have a time limit; a failed merged stream retries using the original
YouTube audio. Changing source settings clears cached matches and failures.
SpotiFLAC remains a download source; its downloaded lossless files can be matched
from the library.

Shuffle reorders existing audio sources without reopening the playing stream or
seeking it. Initial loads and reconnect attempts show buffering; pausing cancels
pending automatic resume. Legacy manifests resolve with bounded transient-error
retries, and byte-range requests reuse the same manifest until a player retry
creates a fresh source.

## Downloads

On native platforms, use a song's **Download** button or menu, or a collection's
**Download all offline**. The music-link dialog also offers **Download**.
Monochrome downloads keep the source FLAC without resampling or converting it to
the YouTube download format. Available title, artist, album, source link and JPEG
or PNG cover are embedded in the file. Files use the download folder in Settings.

Downloads share Riflay's Downloads queue, progress, cancel and retry controls.
Waiting and failed jobs survive a restart; interrupted Monochrome downloads restart
from the beginning. Completed files enter the library and are used automatically
when playing their original streamed tracks, including those in imported playlists.
Legacy DASH manifests require FFmpeg to copy their FLAC audio packets without
re-encoding; access still depends on the selected HiFi endpoint.

## Service availability

Search and native `tracks:track:` / `tracks:album:` shares use
`https://tracks.monochrome.st`. Public user playlists use Monochrome's public
playlist endpoint. Private playlists and account synchronization are not supported.
Native track shares can lack a title and artist: Monochrome's Tracks API has no
metadata-by-id endpoint, so the id is shown until catalog metadata is available.

Older numeric TIDAL tracks and collections use Monochrome's HiFi API shape
(`/info/`, `/album/`, `/playlist/`, `/track/`). The historical default instance is
`https://arran.monochrome.tf`; availability and third-party access vary. A build can
select an accessible HiFi instance using
`--dart-define=RIFLAY_MONOCHROME_API=https://your-instance.example`.
Riflay does not forge browser origins or bypass a server's access restrictions.
Legacy stream manifests are resolved when played so expiring URLs are not saved
in the library. Native FLAC streams use a stable URL and support byte-range seeking.

Playlist pagination failures are reported instead of silently saving a partial
playlist. Saving a playlist alone does not download its audio; use Download for
offline playback.

Protocol references: [Monochrome Tracks client](https://github.com/monochrome-music/monochrome/blob/main/js/tracks-api.js),
[HiFi client](https://github.com/monochrome-music/monochrome/blob/main/js/api.js),
[public playlists](https://github.com/monochrome-music/monochrome/blob/main/js/accounts/pocketbase.js).
