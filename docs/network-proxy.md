# Network proxy

Open Settings → Accounts & services → Music sources → Network proxy. Enter an
HTTP forward proxy you control, such as `http://127.0.0.1:7890`, and press Save.
HTTPS destinations use the HTTP proxy's CONNECT support. Proxy authentication,
SOCKS and HTTPS-to-the-proxy connections are not supported by this setting.

Domain bypass rules accept comma-separated or newline-separated hosts.
`example.com` and `*.example.com` both include that domain and its subdomains,
but not `badexample.com`. Localhost, loopback, private LAN and `.local` devices
always connect directly, including the app's local audio/video servers and cast
devices. A failing configured proxy does not silently fall back to a direct
connection for other hosts.

Changes apply to new Dart HTTP connections, including app API requests,
HTTP downloads and the app's stream caches. yt-dlp receives the same route for
its YouTube requests. Restart playback after changing the route. Embedded sign-in
browsers, native decoder connections and SpotiFLAC provider runtimes use separate
network stacks; this setting does not configure those stacks. Browser builds use
the browser's own proxy settings and Riflay's existing web relay.

A proxy does not guarantee freedom from rate limits. Catalogue and merged
download requests share a cooldown for each host. Requests already waiting in
the queue recheck a new cooldown before continuing. YouTube Music requests also
honor their shared cooldown. Retry-After accepts both seconds and HTTP dates;
explicit waits are bounded to one day, while missing headers use escalating
15/30/60/120-second waits.
