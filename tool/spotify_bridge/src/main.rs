//! Riflay's Spotify bridge: signs in with librespot and serves a track's audio to mpv over loopback.
//!
//! `spotify_bridge <state dir>` talks JSON lines on stdin / stdout (`{"id", "method", "params"}` in,
//! `{"id", "result"}` or `{"id", "error"}` out) and answers `GET /<secret>/<track id>` on 127.0.0.1 with the
//! track's Ogg Vorbis file, decrypted, with Range. Nothing is written to disk but librespot's reusable
//! credentials (`<state dir>/credentials.json`), and nothing is logged unless `RIFLAY_SPOTIFY_LOG` is set.
#![cfg_attr(windows, windows_subsystem = "windows")]

use std::{
    collections::HashMap,
    hash::{BuildHasher, Hasher},
    io::{self, BufRead, Read, Seek, SeekFrom, Write},
    path::PathBuf,
    sync::{Arc, Mutex},
    thread,
};

use librespot_audio::{AudioDecrypt, AudioFile};
use librespot_core::{
    audio_key::AudioKey, authentication::Credentials, cache::Cache, error::ErrorKind, Error, FileId, Session,
    SessionConfig, SpotifyId, SpotifyUri,
};
use librespot_metadata::{audio::AudioFileFormat, Metadata, Track};
use serde_json::{json, Value};
use tiny_http::{Header, Method, Request, Response, Server, StatusCode};

/// Spotify's Ogg files start with a page of its own that players skip.
const OGG_HEADER: u64 = 0xa7;

/// What a track id resolved to; kept so mpv's probe, open and seeks ask Spotify once.
#[derive(Clone)]
struct Resolved {
    file: FileId,
    key: Option<AudioKey>,
    bytes_per_second: usize,
}

struct Bridge {
    runtime: tokio::runtime::Runtime,
    state: PathBuf,
    session: tokio::sync::Mutex<Option<Session>>,
    resolved: Mutex<HashMap<String, Resolved>>,
}

impl Bridge {
    fn cache(&self) -> Option<Cache> {
        Cache::new(Some(self.state.clone()), None, None, None).ok()
    }

    /// Signs in: with the credentials kept from last time, else with `token`.
    async fn login(&self, token: Option<&str>) -> Result<String, Error> {
        let mut slot = self.session.lock().await;
        if let Some(session) = slot.as_ref().filter(|s| !s.is_invalid()) {
            return Ok(session.username());
        }
        let cache = self.cache();
        let mut tries: Vec<Credentials> = cache.as_ref().and_then(|c| c.credentials()).into_iter().collect();
        if let Some(token) = token.filter(|t| !t.is_empty()) {
            tries.push(Credentials::with_access_token(token));
        }
        let mut last = Error::unauthenticated("no credentials");
        for credentials in tries {
            let session = Session::new(SessionConfig::default(), cache.clone());
            match session.connect(credentials, true).await {
                Ok(()) => {
                    let name = session.username();
                    *slot = Some(session);
                    self.resolved.lock().unwrap().clear();
                    return Ok(name);
                }
                Err(e) => {
                    log::warn!("sign-in failed: {e}");
                    last = e;
                }
            }
        }
        Err(last)
    }

    async fn logout(&self) {
        if let Some(session) = self.session.lock().await.take() {
            session.shutdown();
        }
        self.resolved.lock().unwrap().clear();
        let _ = std::fs::remove_file(self.state.join("credentials.json"));
    }

    /// The live session; one the server dropped is opened again from the kept credentials.
    async fn session(&self) -> Result<Session, Error> {
        self.login(None).await?;
        self.session.lock().await.clone().ok_or_else(|| Error::unauthenticated("signed out"))
    }

    async fn resolve(&self, session: &Session, id: &str, quality: u32) -> Result<Resolved, Error> {
        let cached = format!("{id}:{quality}");
        if let Some(found) = self.resolved.lock().unwrap().get(&cached) {
            return Ok(found.clone());
        }
        let uri = SpotifyUri::Track { id: SpotifyId::from_base62(id)? };
        let mut track = Track::get(session, &uri).await?;
        // A song Spotify holds under another id in this country lists that one as an alternative.
        if track.files.is_empty() {
            for other in track.alternatives.0.clone() {
                if let Ok(found) = Track::get(session, &other).await {
                    if !found.files.is_empty() {
                        track = found;
                        break;
                    }
                }
            }
        }
        let wanted: &[(AudioFileFormat, usize)] = &[
            (AudioFileFormat::OGG_VORBIS_320, 40 * 1024),
            (AudioFileFormat::OGG_VORBIS_160, 20 * 1024),
            (AudioFileFormat::OGG_VORBIS_96, 12 * 1024),
        ];
        let from = match quality {
            q if q >= 320 => 0,
            q if q >= 160 => 1,
            _ => 2,
        };
        // The asked quality, then lower ones, then higher ones.
        let order = wanted[from..].iter().chain(wanted[..from].iter().rev());
        let (file, bytes_per_second) = order
            .filter_map(|(format, rate)| track.files.get(format).map(|file| (*file, *rate)))
            .next()
            .ok_or_else(|| Error::unavailable("no Ogg Vorbis file"))?;
        let SpotifyUri::Track { id: track_id } = track.id else {
            return Err(Error::unavailable("not a track"));
        };
        let key = session.audio_key().request(track_id, file).await?;
        let found = Resolved { file, key: Some(key), bytes_per_second };
        let mut all = self.resolved.lock().unwrap();
        if all.len() > 64 {
            all.clear();
        }
        all.insert(cached, found.clone());
        Ok(found)
    }

    /// The decrypted file of track `id`, positioned at its first Ogg page, and that file's length.
    async fn open(&self, id: &str, quality: u32) -> Result<(AudioDecrypt<AudioFile>, u64), Error> {
        let session = self.session().await?;
        let found = self.resolve(&session, id, quality).await?;
        let file = AudioFile::open(&session, found.file, found.bytes_per_second).await?;
        let size = file.get_stream_loader_controller()?.len() as u64;
        Ok((AudioDecrypt::new(found.key, file), size.saturating_sub(OGG_HEADER)))
    }
}

fn kind_of(e: &Error) -> &'static str {
    match e.kind {
        ErrorKind::Unauthenticated | ErrorKind::PermissionDenied => "auth",
        ErrorKind::NotFound | ErrorKind::Unavailable | ErrorKind::InvalidArgument => "unavailable",
        _ => "failed",
    }
}

/// `bytes=a-b`, `bytes=a-` or `bytes=-n` against a body of `size` bytes: first byte and length.
fn parse_range(value: &str, size: u64) -> Option<(u64, u64)> {
    let (from, to) = value.trim().strip_prefix("bytes=")?.split(',').next()?.trim().split_once('-')?;
    if from.is_empty() {
        let last: u64 = to.parse().ok()?;
        let length = last.min(size);
        return (length > 0).then_some((size - length, length));
    }
    let start: u64 = from.parse().ok()?;
    if start >= size {
        return None;
    }
    let end = if to.is_empty() { size - 1 } else { to.parse::<u64>().ok()?.min(size - 1) };
    (end >= start).then_some((start, end - start + 1))
}

fn header(name: &str, value: &str) -> Header {
    Header::from_bytes(name.as_bytes(), value.as_bytes()).expect("ASCII header")
}

fn serve(bridge: &Bridge, secret: &str, request: Request) {
    let empty = |code: u16| Response::new_empty(StatusCode(code));
    if !matches!(request.method(), Method::Get | Method::Head) {
        let _ = request.respond(empty(405));
        return;
    }
    let url = request.url().to_owned();
    let (path, query) = url.split_once('?').unwrap_or((&url, ""));
    let mut parts = path.trim_start_matches('/').split('/');
    let (given, id, rest) = (parts.next(), parts.next(), parts.next());
    let (Some(given), Some(id), None) = (given, id, rest) else {
        let _ = request.respond(empty(404));
        return;
    };
    if given != secret {
        let _ = request.respond(empty(403));
        return;
    }
    let quality = query
        .split('&')
        .find_map(|pair| pair.strip_prefix("q="))
        .and_then(|q| q.parse().ok())
        .unwrap_or(320);
    let (mut body, size) = match bridge.runtime.block_on(bridge.open(id, quality)) {
        Ok(opened) => opened,
        Err(e) => {
            log::warn!("track {id}: {e}");
            let code = match kind_of(&e) {
                "auth" => 401,
                "unavailable" => 404,
                _ => 502,
            };
            let _ = request.respond(empty(code));
            return;
        }
    };
    let asked = request.headers().iter().find(|h| h.field.equiv("Range")).map(|h| h.value.as_str().to_owned());
    let (start, length, partial) = match asked {
        Some(value) => match parse_range(&value, size) {
            Some((start, length)) => (start, length, true),
            None => {
                let _ = request.respond(empty(416).with_header(header("Content-Range", &format!("bytes */{size}"))));
                return;
            }
        },
        None => (0, size, false),
    };
    if body.seek(SeekFrom::Start(OGG_HEADER + start)).is_err() {
        let _ = request.respond(empty(502));
        return;
    }
    let mut headers = vec![header("Content-Type", "audio/ogg"), header("Accept-Ranges", "bytes")];
    if partial {
        headers.push(header("Content-Range", &format!("bytes {start}-{}/{size}", start + length - 1)));
    }
    let response = Response::new(
        StatusCode(if partial { 206 } else { 200 }),
        headers,
        body.take(length),
        Some(length as usize),
        None,
    );
    // mpv closes the connection when it seeks or skips: not an error.
    let _ = request.respond(response);
}

fn random_secret() -> String {
    let word = || std::collections::hash_map::RandomState::new().build_hasher().finish();
    format!("{:016x}{:016x}", word(), word())
}

struct StderrLog;

impl log::Log for StderrLog {
    fn enabled(&self, metadata: &log::Metadata) -> bool {
        metadata.level() <= log::Level::Debug
    }

    fn log(&self, record: &log::Record) {
        if self.enabled(record.metadata()) {
            eprintln!("[{}] {}: {}", record.level(), record.target(), record.args());
        }
    }

    fn flush(&self) {}
}

fn main() {
    let Some(state) = std::env::args_os().nth(1).map(PathBuf::from) else {
        std::process::exit(2);
    };
    if std::env::var_os("RIFLAY_SPOTIFY_LOG").is_some() {
        static LOG: StderrLog = StderrLog;
        let _ = log::set_logger(&LOG);
        log::set_max_level(log::LevelFilter::Debug);
    }
    let runtime = tokio::runtime::Builder::new_multi_thread().enable_all().build().expect("tokio runtime");
    let bridge = Arc::new(Bridge {
        runtime,
        state,
        session: tokio::sync::Mutex::new(None),
        resolved: Mutex::new(HashMap::new()),
    });
    let server = Arc::new(Server::http("127.0.0.1:0").expect("loopback port"));
    let port = server.server_addr().to_ip().map(|a| a.port()).unwrap_or(0);
    let secret = random_secret();
    {
        let (bridge, server, secret) = (bridge.clone(), server.clone(), secret.clone());
        thread::spawn(move || {
            for request in server.incoming_requests() {
                let (bridge, secret) = (bridge.clone(), secret.clone());
                thread::spawn(move || serve(&bridge, &secret, request));
            }
        });
    }

    let stdout = io::stdout();
    // Riflay closing its end of the pipe (or exiting) ends the bridge.
    for line in io::stdin().lock().lines() {
        let Ok(line) = line else { break };
        let Ok(message) = serde_json::from_str::<Value>(&line) else { continue };
        let id = message["id"].clone();
        let params = &message["params"];
        let answer = match message["method"].as_str().unwrap_or("") {
            "hello" => Ok(json!({ "port": port, "secret": secret })),
            "login" => bridge
                .runtime
                .block_on(bridge.login(params["token"].as_str()))
                .map(|name| json!({ "username": name }))
                .map_err(|e| kind_of(&e)),
            "logout" => {
                bridge.runtime.block_on(bridge.logout());
                Ok(Value::Null)
            }
            _ => Err("unknown"),
        };
        let reply = match answer {
            Ok(result) => json!({ "id": id, "result": result }),
            Err(error) => json!({ "id": id, "error": error }),
        };
        let mut out = stdout.lock();
        if writeln!(out, "{reply}").and_then(|_| out.flush()).is_err() {
            break;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::parse_range;

    #[test]
    fn ranges() {
        assert_eq!(parse_range("bytes=0-99", 1000), Some((0, 100)));
        assert_eq!(parse_range("bytes=100-", 1000), Some((100, 900)));
        assert_eq!(parse_range("bytes=-100", 1000), Some((900, 100)));
        // Past the end: clamped; starting past the end: not satisfiable.
        assert_eq!(parse_range("bytes=900-5000", 1000), Some((900, 100)));
        assert_eq!(parse_range("bytes=1000-", 1000), None);
        assert_eq!(parse_range("bytes=5-2", 1000), None);
        assert_eq!(parse_range("items=0-1", 1000), None);
        assert_eq!(parse_range("bytes=-0", 1000), None);
    }
}
