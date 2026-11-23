//! The standalone player: no Riflay app, sound through libmpv in this process. It answers the same commands with the
//! same JSON as the app's CLI service, so the screens don't know which one they talk to.
//!
//! Songs come from Riflay's own library file when Riflay is installed (read only), else from a music folder; YouTube
//! Music's search is asked directly (through curl), and a song's sound address comes from yt-dlp. Lyrics: a .lrc
//! beside the file, else LRCLIB. Everything slow runs on a thread of its own; the player's thread only keeps state.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use serde_json::{Value, json};

use crate::Message;
use crate::discord;
use crate::mpv::{Event, Mpv};

#[derive(Clone)]
enum Source {
    File(PathBuf),
    YouTube(String),
}

#[derive(Clone)]
struct Song {
    id: String,
    title: String,
    artist: String,
    album: String,
    duration_ms: Option<u64>,
    source: Source,
    art: Option<String>,
}

impl Song {
    fn json(&self) -> Value {
        json!({"id": self.id, "title": self.title, "artist": self.artist, "album": self.album, "durationMs": self.duration_ms})
    }
}

enum Inbox {
    Request(u64, String, Value),
    Mpv(Event),
    Resolved(String, Result<String, String>),
    Library(Vec<Song>),
    /// Similar songs for a radio (station) or for autoplay; tag 0 when nobody waits for a reply.
    Radio {
        tag: u64,
        seed: Song,
        station: bool,
        songs: Result<Vec<Song>, String>,
    },
    Tick,
}

/// Starts the standalone player. Returns where its requests go (as the app's worker takes them), or why it can't
/// play (no libmpv).
pub fn spawn(
    out: Sender<Message>,
    data_dir: PathBuf,
) -> Result<Sender<(u64, String, Value)>, String> {
    let mpv = Arc::new(Mpv::new()?);
    let (inbox, rx) = mpsc::channel::<Inbox>();

    // mpv's events into the player's inbox.
    let (events, tx) = (mpv.clone(), inbox.clone());
    thread::spawn(move || {
        loop {
            if let Some(e) = events.next_event(60.0) {
                let stop = matches!(e, Event::Shutdown);
                if tx.send(Inbox::Mpv(e)).is_err() || stop {
                    break;
                }
            }
        }
    });
    // Every five seconds: the status again, so the screen's clock stays in step.
    let tick = inbox.clone();
    thread::spawn(move || {
        while tick.send(Inbox::Tick).is_ok() {
            thread::sleep(Duration::from_secs(5));
        }
    });
    // The library, read off the player's thread.
    let (lib, dir) = (inbox.clone(), data_dir.clone());
    thread::spawn(move || {
        let _ = lib.send(Inbox::Library(read_library(&dir)));
    });

    let (requests, from_ui) = mpsc::channel::<(u64, String, Value)>();
    let forward = inbox.clone();
    thread::spawn(move || {
        for (tag, command, params) in from_ui {
            if forward.send(Inbox::Request(tag, command, params)).is_err() {
                break;
            }
        }
    });

    let playlists = read_playlists(&data_dir);
    thread::spawn(move || Player::new(mpv, out, inbox, playlists, data_dir).run(rx));
    Ok(requests)
}

struct Player {
    mpv: Arc<Mpv>,
    out: Sender<Message>,
    inbox: Sender<Inbox>,
    library: Vec<Song>,
    library_ready: bool,
    playlists: Vec<(String, String, Vec<Song>)>,
    found: HashMap<String, Song>,
    queue: Vec<Song>,
    unshuffled: Option<Vec<Song>>,
    at: Option<usize>,
    loaded: bool,
    paused: bool,
    buffering: bool,
    duration: Option<f64>,
    volume: i64,
    repeat: &'static str,
    last_error: Option<String>,
    /// Sound addresses from yt-dlp, by song id, and when they were looked up (they expire after some hours).
    streams: HashMap<String, (String, Instant)>,
    /// The song whose sound is being looked up, to start when it comes.
    waiting: Option<String>,
    /// The queue ran out (the last song ended): autoplay's songs start at once when they come.
    ran_out: bool,
    /// When the queue runs out, keep going with similar songs (as the app does; its setting when Riflay is here).
    autoplay: bool,
    /// The song autoplay last looked up similar songs for, so it asks once per song.
    autoplay_seed: Option<String>,
    /// A radio being looked up.
    radio_busy: bool,
    /// Discord Rich Presence (the app's setting when Riflay is here, else off), and what it shows now.
    discord: Option<Sender<Option<Value>>>,
    presence: Option<(String, bool, i64)>,
    /// The lyrics' target language.
    language: String,
}

impl Player {
    fn new(
        mpv: Arc<Mpv>,
        out: Sender<Message>,
        inbox: Sender<Inbox>,
        playlists: Vec<(String, String, Vec<Song>)>,
        data_dir: PathBuf,
    ) -> Player {
        mpv.set("volume", "70");
        let prefs = read_prefs(&data_dir);
        let autoplay = prefs["flutter.autoplay.v1"].as_bool().unwrap_or(true);
        let discord = prefs["flutter.discord.enabled"].as_bool() == Some(true);
        Player {
            mpv,
            out,
            inbox,
            library: vec![],
            library_ready: false,
            playlists,
            found: HashMap::new(),
            queue: vec![],
            unshuffled: None,
            at: None,
            loaded: false,
            paused: true,
            buffering: false,
            duration: None,
            volume: 70,
            repeat: "off",
            last_error: None,
            streams: HashMap::new(),
            waiting: None,
            ran_out: false,
            autoplay,
            autoplay_seed: None,
            radio_busy: false,
            discord: discord.then(discord::spawn),
            presence: None,
            language: language(&prefs),
        }
    }

    fn run(mut self, rx: Receiver<Inbox>) {
        self.status();
        for message in rx {
            match message {
                Inbox::Request(tag, command, params) => {
                    let result = self.handle(tag, &command, &params);
                    if let Some(result) = result {
                        let _ = self.out.send(Message::Reply(tag, command, result));
                    }
                }
                Inbox::Mpv(e) => self.mpv_event(e),
                Inbox::Resolved(id, result) => self.resolved(id, result),
                Inbox::Library(songs) => {
                    self.library = songs;
                    self.library_ready = true;
                }
                Inbox::Radio {
                    tag,
                    seed,
                    station,
                    songs,
                } => self.radio_done(tag, seed, station, songs),
                Inbox::Tick => {
                    if self.loaded && !self.paused {
                        self.status();
                    }
                    continue;
                }
            }
            self.maybe_autoplay();
            self.status();
            self.show_presence();
        }
    }

    fn current(&self) -> Option<&Song> {
        self.at.and_then(|i| self.queue.get(i))
    }

    fn position_ms(&self) -> u64 {
        if !self.loaded {
            return 0;
        }
        self.mpv
            .get("time-pos")
            .and_then(|p| p.parse::<f64>().ok())
            .map_or(0, |s| (s.max(0.0) * 1000.0) as u64)
    }

    fn queue_revision(&self) -> i64 {
        let mut h: i64 = self.at.map_or(-1, |a| a as i64);
        for s in &self.queue {
            for b in s.id.bytes() {
                h = h.wrapping_mul(31).wrapping_add(b as i64);
            }
        }
        h
    }

    fn status_json(&self) -> Value {
        let track = self.current();
        json!({
            "type": "status",
            "playing": self.loaded && !self.paused,
            "buffering": self.buffering || self.waiting.is_some(),
            "track": track.map(Song::json),
            "positionMs": self.position_ms(),
            "durationMs": self.duration.map(|d| (d * 1000.0) as u64).or(track.and_then(|t| t.duration_ms)),
            "volume": self.volume,
            "canSetVolume": true,
            "shuffle": self.unshuffled.is_some(),
            "repeat": self.repeat,
            "autoplay": self.autoplay,
            "discord": self.discord.is_some(),
            "queueLength": self.queue.len(),
            "hasNext": self.at.is_some_and(|a| a + 1 < self.queue.len()),
            "hasPrevious": self.at.is_some(),
            "casting": false,
            "lastError": self.last_error,
            "queueRevision": self.queue_revision(),
        })
    }

    fn status(&self) {
        let _ = self.out.send(Message::Event(self.status_json()));
    }

    fn find(&self, id: &str) -> Option<Song> {
        self.library
            .iter()
            .chain(self.queue.iter())
            .chain(self.playlists.iter().flat_map(|p| p.2.iter()))
            .find(|s| s.id == id)
            .cloned()
            .or_else(|| self.found.get(id).cloned())
    }

    /// Plays the queue's song [index]: a file at once; a YouTube song once yt-dlp has its sound's address.
    fn start(&mut self, index: usize) {
        let Some(song) = self.queue.get(index).cloned() else {
            return;
        };
        self.at = Some(index);
        self.ran_out = false;
        self.duration = song.duration_ms.map(|d| d as f64 / 1000.0);
        self.last_error = None;
        match &song.source {
            Source::File(path) => {
                self.waiting = None;
                self.load(&path.to_string_lossy());
            }
            Source::YouTube(video) => match self.streams.get(&song.id) {
                Some((url, at)) if at.elapsed() < Duration::from_secs(3 * 3600) => {
                    let url = url.clone();
                    self.waiting = None;
                    self.load(&url);
                }
                _ => {
                    self.mpv.command(&["stop"]);
                    self.loaded = false;
                    self.waiting = Some(song.id.clone());
                    resolve(song.id.clone(), video.clone(), self.inbox.clone());
                }
            },
        }
    }

    fn load(&mut self, what: &str) {
        self.mpv.command(&["loadfile", what, "replace"]);
        self.mpv.set("pause", "no");
        self.paused = false;
        self.loaded = true;
    }

    fn resolved(&mut self, id: String, result: Result<String, String>) {
        match result {
            Ok(url) => {
                self.streams
                    .insert(id.clone(), (url.clone(), Instant::now()));
                if self.waiting.as_deref() == Some(&id) {
                    self.waiting = None;
                    self.load(&url);
                }
            }
            Err(e) => {
                if self.waiting.as_deref() == Some(&id) {
                    self.waiting = None;
                    self.last_error = Some(e);
                    self.loaded = false;
                }
            }
        }
    }

    /// The next song's sound looked up ahead, so it starts at once.
    fn prefetch(&mut self) {
        let Some(next) = self.at.map(|a| a + 1).and_then(|n| self.queue.get(n)) else {
            return;
        };
        if let Source::YouTube(video) = &next.source
            && !self.streams.contains_key(&next.id)
        {
            self.streams.insert(
                next.id.clone(),
                (
                    String::new(),
                    Instant::now() - Duration::from_secs(4 * 3600),
                ),
            );
            resolve(next.id.clone(), video.clone(), self.inbox.clone());
        }
    }

    fn mpv_event(&mut self, e: Event) {
        match e {
            Event::Paused(p) => self.paused = p,
            Event::Buffering(b) => self.buffering = b,
            Event::Duration(d) => self.duration = Some(d),
            Event::Loaded => {
                self.buffering = false;
                self.prefetch();
            }
            Event::Restarted => self.buffering = false,
            Event::Ended { eof, error } => {
                if error {
                    self.last_error = Some("This song could not be played.".into());
                }
                if eof || error {
                    self.advance(error);
                }
            }
            Event::Shutdown => {}
        }
    }

    /// The song ended: the next one, as repeat says.
    fn advance(&mut self, after_error: bool) {
        let Some(at) = self.at else { return };
        if self.repeat == "one" && !after_error {
            return self.start(at);
        }
        if at + 1 < self.queue.len() {
            self.start(at + 1);
        } else if self.repeat == "all" && !self.queue.is_empty() {
            self.start(0);
        } else {
            self.loaded = false;
            self.paused = true;
            self.ran_out = true;
        }
    }

    /// Near the end of the queue (its last two songs), similar songs are looked up and added after it, once per song.
    fn maybe_autoplay(&mut self) {
        if !self.autoplay || self.repeat != "off" || self.radio_busy {
            return;
        }
        let Some(at) = self.at else { return };
        if at + 2 < self.queue.len() {
            return;
        }
        let Some(seed) = self.queue.get(at).cloned() else {
            return;
        };
        if self.autoplay_seed.as_deref() == Some(&seed.id) {
            return;
        }
        self.autoplay_seed = Some(seed.id.clone());
        self.spawn_radio(0, seed, false);
    }

    /// Looks up [seed]'s similar songs off this thread: YouTube Music's radio for it, and for a song on this computer
    /// also the library's songs like it (the same artist first), which alone keep it going offline.
    fn spawn_radio(&mut self, tag: u64, seed: Song, station: bool) {
        self.radio_busy = true;
        let mut local: Vec<Song> = vec![];
        if let Source::File(_) = seed.source {
            let artist = seed.artist.to_lowercase();
            let mut same: Vec<Song> = self
                .library
                .iter()
                .filter(|s| {
                    s.id != seed.id && !artist.is_empty() && s.artist.to_lowercase() == artist
                })
                .cloned()
                .collect();
            let mut others: Vec<Song> = self
                .library
                .iter()
                .filter(|s| {
                    s.id != seed.id && (artist.is_empty() || s.artist.to_lowercase() != artist)
                })
                .cloned()
                .collect();
            shuffle(&mut same);
            shuffle(&mut others);
            local = same
                .into_iter()
                .take(10)
                .chain(others.into_iter().take(15))
                .collect();
        }
        let inbox = self.inbox.clone();
        thread::spawn(move || {
            let songs = match radio_youtube(&seed) {
                Ok(mut songs) => {
                    songs.extend(local);
                    Ok(songs)
                }
                Err(_) if !local.is_empty() => Ok(local),
                Err(e) => Err(e),
            };
            let _ = inbox.send(Inbox::Radio {
                tag,
                seed,
                station,
                songs,
            });
        });
    }

    fn radio_done(
        &mut self,
        tag: u64,
        seed: Song,
        station: bool,
        songs: Result<Vec<Song>, String>,
    ) {
        self.radio_busy = false;
        let reply = |out: &Sender<Message>, r: Result<Value, String>| {
            if tag != 0 {
                let _ = out.send(Message::Reply(tag, "radio".into(), r));
            }
        };
        let songs = match songs {
            Ok(s) => s,
            Err(e) => {
                if station {
                    reply(&self.out, Err(e));
                }
                return;
            }
        };
        for s in &songs {
            self.found.insert(s.id.clone(), s.clone());
        }
        let mut seen: HashSet<String> = HashSet::from([seed.id.clone()]);
        if station {
            let fresh: Vec<Song> = songs
                .into_iter()
                .filter(|s| seen.insert(s.id.clone()))
                .collect();
            if fresh.is_empty() {
                return reply(&self.out, Err("No similar songs were found.".into()));
            }
            self.unshuffled = None;
            self.autoplay_seed = Some(seed.id.clone());
            match self
                .at
                .filter(|&a| self.queue.get(a).is_some_and(|s| s.id == seed.id))
            {
                Some(at) => {
                    self.queue.truncate(at + 1);
                    self.queue.extend(fresh);
                    self.prefetch();
                }
                None => {
                    self.queue = std::iter::once(seed).chain(fresh).collect();
                    self.start(0);
                }
            }
            return reply(&self.out, Ok(json!({"accepted": true})));
        }
        if !self.autoplay || self.repeat != "off" {
            return;
        }
        // Not the songs already queued.
        seen.extend(self.queue.iter().map(|s| s.id.clone()));
        let fresh: Vec<Song> = songs
            .into_iter()
            .filter(|s| seen.insert(s.id.clone()))
            .take(25)
            .collect();
        if fresh.is_empty() {
            return;
        }
        let first = self.queue.len();
        self.queue.extend(fresh);
        if self.ran_out && self.waiting.is_none() {
            self.start(first);
        } else {
            self.prefetch();
        }
    }

    /// What Discord shows: the song and the time left, sent when the song, pausing or the position (a seek) changed.
    fn show_presence(&mut self) {
        let Some(tx) = &self.discord else { return };
        let song = self
            .current()
            .filter(|_| self.loaded || self.waiting.is_some())
            .cloned();
        let Some(song) = song else {
            if self.presence.take().is_some() {
                let _ = tx.send(None);
            }
            return;
        };
        let playing = self.loaded && !self.paused;
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_millis() as i64);
        let start = now - self.position_ms() as i64;
        if let Some((id, was_playing, was_start)) = &self.presence
            && *id == song.id
            && *was_playing == playing
            && (!playing || (start - was_start).abs() < 3000)
        {
            return;
        }
        self.presence = Some((song.id.clone(), playing, start));
        let video = match &song.source {
            Source::YouTube(v) => Some(v.as_str()),
            Source::File(_) => None,
        };
        let duration = self
            .duration
            .map(|d| (d * 1000.0) as u64)
            .or(song.duration_ms);
        let art = song.art.as_deref().filter(|a| a.starts_with("https://"));
        let _ = tx.send(Some(discord::activity(
            &song.title,
            &song.artist,
            &song.album,
            art,
            video,
            playing,
            start,
            duration,
        )));
    }

    fn page(items: Vec<Value>, params: &Value) -> Value {
        let offset = params["offset"].as_u64().unwrap_or(0) as usize;
        let limit = params["limit"].as_u64().unwrap_or(20) as usize;
        let total = items.len();
        json!({"items": items.into_iter().skip(offset).take(limit).collect::<Vec<_>>(), "total": total, "offset": offset, "limit": limit})
    }

    /// One command, as the app answers it. None: answered later, from another thread.
    fn handle(&mut self, tag: u64, command: &str, p: &Value) -> Option<Result<Value, String>> {
        let ok = |v: Value| Some(Ok(v));
        match command {
            "status" => ok(self.status_json()),
            "library" => {
                if !self.library_ready {
                    return ok(json!({"items": [], "total": 0, "offset": 0, "limit": 0}));
                }
                ok(Self::page(self.library.iter().map(Song::json).collect(), p))
            }
            "queue" => {
                let at = self.at;
                let items = self
                    .queue
                    .iter()
                    .enumerate()
                    .map(|(i, s)| json!({"index": i, "current": Some(i) == at, "track": s.json()}))
                    .collect();
                ok(Self::page(items, p))
            }
            "playlists" => ok(Self::page(
                self.playlists
                    .iter()
                    .map(|(id, name, t)| json!({"id": id, "name": name, "trackCount": t.len()}))
                    .collect(),
                p,
            )),
            "playlist.show" => {
                let id = p["id"].as_str().unwrap_or("");
                match self.playlists.iter().find(|x| x.0 == id) {
                    Some((id, name, t)) => {
                        let mut page = Self::page(t.iter().map(Song::json).collect(), p);
                        page["id"] = json!(id);
                        page["name"] = json!(name);
                        ok(page)
                    }
                    None => Some(Err("Unknown playlist.".into())),
                }
            }
            "playlist.play" => {
                let id = p["id"].as_str().unwrap_or("");
                match self
                    .playlists
                    .iter()
                    .find(|x| x.0 == id)
                    .map(|x| x.2.clone())
                {
                    Some(t) if !t.is_empty() => {
                        self.unshuffled = None;
                        self.queue = t;
                        self.start(0);
                        ok(json!({"accepted": true}))
                    }
                    _ => Some(Err("The playlist is empty.".into())),
                }
            }
            "search" => {
                let query = p["query"].as_str().unwrap_or("").to_string();
                let limit = p["limit"].as_u64().unwrap_or(20) as usize;
                match p["source"].as_str().unwrap_or("library") {
                    "youtube" => {
                        let (out, inbox) = (self.out.clone(), self.inbox.clone());
                        thread::spawn(move || {
                            let result = search_youtube_music(&query).map(|songs| {
                                let items: Vec<Value> = songs.iter().take(limit).map(Song::json).collect();
                                let _ = inbox.send(Inbox::Request(0, "_found".into(), json!({"songs": songs.iter().map(song_record).collect::<Vec<_>>()})));
                                json!({"items": items, "total": items.len(), "offset": 0, "limit": limit, "source": "youtube", "query": query})
                            });
                            let _ = out.send(Message::Reply(tag, "search".into(), result));
                        });
                        None
                    }
                    "library" => {
                        let words: Vec<String> = query
                            .to_lowercase()
                            .split_whitespace()
                            .map(str::to_string)
                            .collect();
                        let items = self
                            .library
                            .iter()
                            .filter(|s| {
                                let hay =
                                    format!("{} {} {}", s.title, s.artist, s.album).to_lowercase();
                                words.iter().all(|w| hay.contains(w))
                            })
                            .take(limit)
                            .map(Song::json)
                            .collect::<Vec<_>>();
                        ok(
                            json!({"items": items, "total": items.len(), "offset": 0, "limit": limit, "source": "library", "query": query}),
                        )
                    }
                    _ => Some(Err("SoundCloud needs the Riflay app.".into())),
                }
            }
            // Results of a YouTube Music search, kept so they can be played and queued by id.
            "_found" => {
                for s in p["songs"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .filter_map(song_from_record)
                {
                    self.found.insert(s.id.clone(), s);
                }
                if self.found.len() > 2000 {
                    self.found.clear();
                }
                None
            }
            "play" => {
                if let Some(id) = p["id"].as_str() {
                    let Some(song) = self.find(id) else {
                        return Some(Err("Unknown song. Search again.".into()));
                    };
                    self.unshuffled = None;
                    // From the library: the library from there on, as an album or a playlist plays.
                    if let Some(i) = self.library.iter().position(|s| s.id == song.id) {
                        self.queue = self.library.clone();
                        self.start(i);
                    } else {
                        self.queue = vec![song];
                        self.start(0);
                    }
                } else if let Some(at) = self.at {
                    if !self.loaded {
                        self.start(at);
                    } else {
                        self.mpv.set("pause", "no");
                    }
                }
                ok(json!({"accepted": true}))
            }
            "toggle" => {
                match self.at {
                    Some(at) if !self.loaded && self.waiting.is_none() => self.start(at),
                    Some(_) => self.mpv.command(&["cycle", "pause"]),
                    None if !self.queue.is_empty() => self.start(0),
                    None if !self.library.is_empty() => {
                        self.queue = self.library.clone();
                        self.start(0);
                    }
                    None => return Some(Err("Nothing to play yet. Search with /.".into())),
                }
                ok(json!({"accepted": true}))
            }
            "pause" => {
                self.mpv.set("pause", "yes");
                ok(json!({}))
            }
            "next" => match self.at {
                Some(at) if at + 1 < self.queue.len() => {
                    self.start(at + 1);
                    ok(json!({}))
                }
                _ => Some(Err("There is no next song.".into())),
            },
            "previous" => {
                match self.at {
                    Some(at) if self.position_ms() < 3000 && at > 0 => self.start(at - 1),
                    Some(_) => self.mpv.command(&["seek", "0", "absolute"]),
                    None => {}
                }
                ok(json!({}))
            }
            "seek" => {
                let to = p["seconds"].as_f64().unwrap_or(0.0);
                self.mpv.command(&["seek", &format!("{to:.3}"), "absolute"]);
                ok(json!({}))
            }
            "volume" => {
                if let Some(v) = p["value"].as_f64() {
                    self.volume = v.clamp(0.0, 100.0).round() as i64;
                    self.mpv.set("volume", &self.volume.to_string());
                }
                ok(json!({"volume": self.volume}))
            }
            "shuffle" => {
                let on = p["mode"].as_str() == Some("on");
                if on && self.unshuffled.is_none() {
                    self.unshuffled = Some(self.queue.clone());
                    // The songs after this one, in a new order; this one plays on.
                    let from = self.at.map_or(0, |a| a + 1).min(self.queue.len());
                    shuffle(&mut self.queue[from..]);
                } else if !on && let Some(original) = self.unshuffled.take() {
                    let current = self.current().map(|s| s.id.clone());
                    self.queue = original;
                    self.at = current.and_then(|id| self.queue.iter().position(|s| s.id == id));
                }
                ok(json!({}))
            }
            "repeat" => {
                self.repeat = match p["mode"].as_str() {
                    Some("all") => "all",
                    Some("one") => "one",
                    _ => "off",
                };
                ok(json!({}))
            }
            "queue.add" | "queue.next" => {
                let Some(song) = p["id"].as_str().and_then(|id| self.find(id)) else {
                    return Some(Err("Unknown song. Search again.".into()));
                };
                let empty = self.queue.is_empty();
                if command == "queue.next" {
                    let at = self.at.map_or(0, |a| a + 1).min(self.queue.len());
                    self.queue.insert(at, song);
                } else {
                    self.queue.push(song);
                }
                if empty {
                    self.start(0);
                } else {
                    self.prefetch();
                }
                ok(json!({}))
            }
            "queue.remove" => {
                let i = p["index"].as_u64().unwrap_or(u64::MAX) as usize;
                if i >= self.queue.len() {
                    return Some(Err("No song there.".into()));
                }
                self.queue.remove(i);
                match self.at {
                    Some(at) if i < at => self.at = Some(at - 1),
                    Some(at) if i == at => {
                        if at < self.queue.len() {
                            self.start(at);
                        } else {
                            self.mpv.command(&["stop"]);
                            self.at = None;
                            self.loaded = false;
                        }
                    }
                    _ => {}
                }
                ok(json!({}))
            }
            "queue.play" => {
                let i = p["index"].as_u64().unwrap_or(u64::MAX) as usize;
                if i >= self.queue.len() {
                    return Some(Err("No song there.".into()));
                }
                self.start(i);
                ok(json!({"accepted": true}))
            }
            "stop" | "queue.clear" => {
                self.mpv.command(&["stop"]);
                self.queue.clear();
                self.unshuffled = None;
                self.at = None;
                self.loaded = false;
                ok(json!({}))
            }
            "autoplay" => {
                self.autoplay = p["mode"].as_str() == Some("on");
                self.autoplay_seed = None;
                ok(json!({}))
            }
            "discord" => {
                let on = p["mode"].as_str() == Some("on");
                if on && self.discord.is_none() {
                    self.discord = Some(discord::spawn());
                    self.presence = None;
                } else if !on && let Some(tx) = self.discord.take() {
                    // Cleared, then the thread ends with the sender gone.
                    let _ = tx.send(None);
                    self.presence = None;
                }
                ok(json!({}))
            }
            "radio" => {
                let seed = match p["id"].as_str() {
                    Some(id) => self.find(id),
                    None => self.current().cloned(),
                };
                let Some(seed) = seed else {
                    return Some(Err("Nothing to start a radio from.".into()));
                };
                if self.radio_busy {
                    return Some(Err("A radio is being looked up already.".into()));
                }
                self.spawn_radio(tag, seed, true);
                None
            }
            "lyrics.extras" => {
                let Some(song) = self.current().cloned() else {
                    return Some(Err("Nothing playing.".into()));
                };
                let to = p["to"]
                    .as_str()
                    .map_or(self.language.clone(), str::to_string);
                let out = self.out.clone();
                thread::spawn(move || {
                    let l = lyrics(&song);
                    let texts: Vec<String> = match l["lines"].as_array() {
                        Some(a) if !a.is_empty() => a
                            .iter()
                            .map(|x| x["text"].as_str().unwrap_or("").to_string())
                            .collect(),
                        _ => l["plain"]
                            .as_str()
                            .map_or(vec![], |p| p.lines().map(str::to_string).collect()),
                    };
                    let result = extras(&texts, &to).map(|lines| {
                        json!({
                            "trackId": song.id,
                            "to": to,
                            "lines": lines.into_iter().map(|(r, t)| json!({"romanized": r, "translation": t})).collect::<Vec<_>>(),
                        })
                    });
                    let _ = out.send(Message::Reply(tag, "lyrics.extras".into(), result));
                });
                None
            }
            "lyrics" => {
                let Some(song) = self.current().cloned() else {
                    return Some(Err("Nothing playing.".into()));
                };
                let out = self.out.clone();
                thread::spawn(move || {
                    let _ = out.send(Message::Reply(tag, "lyrics".into(), Ok(lyrics(&song))));
                });
                None
            }
            "cover" => {
                let Some(song) = self.current().cloned() else {
                    return Some(Err("Nothing playing.".into()));
                };
                let size = p["size"].as_u64().unwrap_or(32).clamp(1, 128) as u32;
                let out = self.out.clone();
                thread::spawn(move || {
                    let result = match cover(&song, size) {
                        Some(rgb) => {
                            json!({"trackId": song.id, "size": size, "rgb": base64_encode(&rgb)})
                        }
                        None => json!({"trackId": song.id, "size": 0, "rgb": ""}),
                    };
                    let _ = out.send(Message::Reply(tag, "cover".into(), Ok(result)));
                });
                None
            }
            _ => Some(Err(format!(
                "{command} is not available without the Riflay app."
            ))),
        }
    }
}

/// A song as plain JSON, its source included, to hand it between threads.
fn song_record(s: &Song) -> Value {
    let (kind, value) = match &s.source {
        Source::File(p) => ("file", p.to_string_lossy().into_owned()),
        Source::YouTube(v) => ("youtube", v.clone()),
    };
    json!({"id": s.id, "title": s.title, "artist": s.artist, "album": s.album, "durationMs": s.duration_ms, "kind": kind, "value": value, "art": s.art})
}

fn song_from_record(v: &Value) -> Option<Song> {
    let value = v["value"].as_str()?.to_string();
    Some(Song {
        id: v["id"].as_str()?.to_string(),
        title: v["title"].as_str().unwrap_or("").to_string(),
        artist: v["artist"].as_str().unwrap_or("").to_string(),
        album: v["album"].as_str().unwrap_or("").to_string(),
        duration_ms: v["durationMs"].as_u64(),
        source: if v["kind"] == "file" {
            Source::File(value.into())
        } else {
            Source::YouTube(value)
        },
        art: v["art"].as_str().map(str::to_string),
    })
}

fn shuffle<T>(items: &mut [T]) {
    // A small xorshift seeded by the clock: enough to mix a queue.
    let mut x = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(1, |d| d.as_nanos() as u64)
        | 1;
    for i in (1..items.len()).rev() {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        items.swap(i, (x % (i as u64 + 1)) as usize);
    }
}

// ---- Tools on this computer ----

/// yt-dlp on the PATH, or the one Riflay downloaded.
fn yt_dlp() -> Option<PathBuf> {
    let exe = if cfg!(windows) {
        "yt-dlp.exe"
    } else {
        "yt-dlp"
    };
    if Command::new(exe)
        .arg("--version")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok_and(|s| s.success())
    {
        return Some(PathBuf::from(exe));
    }
    let riflay = crate::client::default_endpoint()
        .parent()?
        .parent()?
        .join("bin")
        .join(exe);
    riflay.exists().then_some(riflay)
}

fn quiet(cmd: &mut Command) -> &mut Command {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        // No console window flashing up for each tool run.
        cmd.creation_flags(0x0800_0000);
    }
    cmd.stdin(Stdio::null()).stderr(Stdio::null())
}

/// The sound's address of a YouTube video (best audio), from yt-dlp; sent to the player's inbox.
fn resolve(id: String, video: String, inbox: Sender<Inbox>) {
    thread::spawn(move || {
        let result = match yt_dlp() {
            None => Err("yt-dlp is needed to play YouTube Music songs: install it (it must be on the PATH).".into()),
            Some(exe) => quiet(Command::new(exe).args([
                "-f",
                "bestaudio",
                "--no-playlist",
                "--no-warnings",
                "-g",
                &format!("https://music.youtube.com/watch?v={video}"),
            ]))
            .output()
            .map_err(|e| e.to_string())
            .and_then(|o| {
                String::from_utf8_lossy(&o.stdout)
                    .lines()
                    .find(|l| l.starts_with("http"))
                    .map(str::to_string)
                    .ok_or_else(|| "YouTube didn't give this song's sound.".to_string())
            }),
        };
        let _ = inbox.send(Inbox::Resolved(id, result));
    });
}

fn curl(args: &[&str], body: Option<&str>) -> Result<Vec<u8>, String> {
    let mut cmd = Command::new("curl");
    quiet(&mut cmd)
        .args(["-s", "-L", "-m", "15"])
        .args(args)
        .stdout(Stdio::piped());
    if body.is_some() {
        cmd.stdin(Stdio::piped());
    }
    let mut child = cmd
        .spawn()
        .map_err(|_| "curl is needed for search and lyrics.".to_string())?;
    if let (Some(body), Some(mut stdin)) = (body, child.stdin.take()) {
        use std::io::Write;
        let _ = stdin.write_all(body.as_bytes());
    }
    let out = child.wait_with_output().map_err(|e| e.to_string())?;
    if !out.status.success() {
        return Err("No connection.".into());
    }
    Ok(out.stdout)
}

// ---- YouTube Music search ----

fn runs(v: &Value) -> Vec<&Value> {
    v["musicResponsiveListItemFlexColumnRenderer"]["text"]["runs"]
        .as_array()
        .map(|a| a.iter().collect())
        .unwrap_or_default()
}

fn all<'a>(v: &'a Value, key: &str, out: &mut Vec<&'a Value>) {
    match v {
        Value::Object(m) => {
            for (k, x) in m {
                if k == key {
                    out.push(x);
                }
                all(x, key, out);
            }
        }
        Value::Array(a) => a.iter().for_each(|x| all(x, key, out)),
        _ => {}
    }
}

fn duration_of(text: &str) -> Option<u64> {
    let mut total = 0u64;
    for part in text.split(':') {
        total = total * 60 + part.trim().parse::<u64>().ok()?;
    }
    Some(total * 1000)
}

/// Songs matching [query] on YouTube Music, as its web client asks for them (the songs filter).
fn search_youtube_music(query: &str) -> Result<Vec<Song>, String> {
    let v = innertube(
        "search",
        json!({"query": query, "params": "EgWKAQIIAWoKEAoQCRADEAQQBQ%3D%3D"}),
    )?;
    let mut rows = vec![];
    all(&v, "musicResponsiveListItemRenderer", &mut rows);
    let mut songs = vec![];
    for row in rows {
        let cols = row["flexColumns"].as_array().cloned().unwrap_or_default();
        let Some(first) = cols.first() else { continue };
        let title_runs = runs(first);
        let Some(title) = title_runs.first().and_then(|r| r["text"].as_str()) else {
            continue;
        };
        let mut ids = vec![];
        all(row, "videoId", &mut ids);
        let Some(video) = ids.first().and_then(|v| v.as_str()) else {
            continue;
        };
        let second = cols.get(1).map(runs).unwrap_or_default();
        let texts: Vec<&str> = second.iter().filter_map(|r| r["text"].as_str()).collect();
        // "Artist • Album • 3:21": the parts between the dots.
        let parts: Vec<String> = texts
            .join("")
            .split(" • ")
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_string)
            .collect();
        let duration = parts.last().and_then(|p| duration_of(p));
        let artist = parts.first().cloned().unwrap_or_default();
        let album = if parts.len() >= 3 {
            parts[1].clone()
        } else {
            String::new()
        };
        let mut thumbs = vec![];
        all(&row["thumbnail"], "url", &mut thumbs);
        let art = thumbs
            .last()
            .and_then(|u| u.as_str())
            .map(|u| u.replace("w60-h60", "w226-h226"));
        songs.push(Song {
            id: format!("yt:{video}"),
            title: title.to_string(),
            artist,
            album,
            duration_ms: duration,
            source: Source::YouTube(video.to_string()),
            art,
        });
    }
    Ok(songs)
}

/// One request to YouTube Music's web API ([endpoint] "search", "next"…), as its web client sends it, signed out.
fn innertube(endpoint: &str, mut body: Value) -> Result<Value, String> {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs());
    let (y, m, d) = civil(now / 86400);
    body["context"] = json!({"client": {"clientName": "WEB_REMIX", "clientVersion": format!("1.{y:04}{m:02}{d:02}.01.00"), "hl": "en"}, "user": {}});
    let body = body.to_string();
    let url = format!("https://music.youtube.com/youtubei/v1/{endpoint}?prettyPrint=false");
    let bytes = curl(
        &[
            "-X",
            "POST",
            &url,
            "-H",
            "Content-Type: application/json",
            "-H",
            "Origin: https://music.youtube.com",
            "-H",
            "User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:88.0) Gecko/20100101 Firefox/88.0",
            "--data-binary",
            "@-",
        ],
        Some(&body),
    )?;
    serde_json::from_slice(&bytes)
        .map_err(|_| "YouTube Music answered something unreadable.".to_string())
}

/// A day number since 1970 as (year, month, day).
fn civil(days: u64) -> (i64, u32, u32) {
    let z = days as i64 + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (yoe + era * 400 + i64::from(m <= 2), m, d)
}

// ---- The library ----

fn file_from_uri(uri: &str) -> Option<PathBuf> {
    let rest = uri.strip_prefix("file://")?;
    let mut bytes = vec![];
    let raw = rest.as_bytes();
    let mut i = 0;
    while i < raw.len() {
        if raw[i] == b'%'
            && i + 2 < raw.len()
            && let Ok(b) = u8::from_str_radix(&rest[i + 1..i + 3], 16)
        {
            bytes.push(b);
            i += 3;
            continue;
        }
        bytes.push(raw[i]);
        i += 1;
    }
    let path = String::from_utf8_lossy(&bytes).into_owned();
    // file:///C:/… on Windows: no leading slash before the drive.
    let path = if cfg!(windows) {
        path.trim_start_matches('/').to_string()
    } else {
        path
    };
    Some(PathBuf::from(path))
}

/// A song of Riflay's library file (or a playlist), if this player can play it: a file here, or a YouTube video.
fn song_from_riflay(v: &Value) -> Option<Song> {
    let id = v["id"].as_str()?.to_string();
    let uri = v["uri"].as_str().unwrap_or("");
    let source = if let Some(path) = file_from_uri(uri).filter(|p| p.exists()) {
        Source::File(path)
    } else if let Some(video) = v["videoId"].as_str() {
        Source::YouTube(video.to_string())
    } else {
        let video = id.strip_prefix("yt:")?;
        Source::YouTube(video.to_string())
    };
    Some(Song {
        id,
        title: v["title"].as_str().unwrap_or("").to_string(),
        artist: v["artist"].as_str().unwrap_or("").to_string(),
        album: v["album"].as_str().unwrap_or("").to_string(),
        duration_ms: v["durationMs"].as_u64(),
        source,
        art: v["artworkUrl"].as_str().map(str::to_string),
    })
}

/// Riflay's library when Riflay is installed here; else the music folder (`RIFLAY_MUSIC_DIR`, or Music in home).
fn read_library(data_dir: &Path) -> Vec<Song> {
    if let Ok(text) = std::fs::read_to_string(data_dir.join("library.json"))
        && let Ok(Value::Array(items)) = serde_json::from_str::<Value>(&text)
    {
        let songs: Vec<Song> = items.iter().filter_map(song_from_riflay).collect();
        if !songs.is_empty() {
            return songs;
        }
    }
    let dir = std::env::var("RIFLAY_MUSIC_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            let home = std::env::var(if cfg!(windows) { "USERPROFILE" } else { "HOME" })
                .unwrap_or_default();
            PathBuf::from(home).join("Music")
        });
    let mut songs = vec![];
    scan(&dir, &mut songs, 0);
    songs.sort_by(|a, b| {
        (a.artist.to_lowercase(), &a.album, &a.title).cmp(&(
            b.artist.to_lowercase(),
            &b.album,
            &b.title,
        ))
    });
    songs
}

const AUDIO: [&str; 12] = [
    "mp3", "flac", "m4a", "aac", "ogg", "opus", "wav", "aiff", "aif", "wv", "ape", "alac",
];

fn scan(dir: &Path, out: &mut Vec<Song>, depth: u32) {
    if depth > 8 || out.len() > 50_000 {
        return;
    }
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            scan(&path, out, depth + 1);
            continue;
        }
        let ext = path
            .extension()
            .and_then(|e| e.to_str())
            .unwrap_or("")
            .to_lowercase();
        if !AUDIO.contains(&ext.as_str()) {
            continue;
        }
        out.push(song_of_file(&path));
    }
}

fn song_of_file(path: &Path) -> Song {
    use lofty::file::{AudioFile, TaggedFileExt};
    use lofty::tag::Accessor;
    let stem = path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_string();
    // "Artist - Title" names (Riflay's downloads) when the file has no tags.
    let (mut artist, mut title) = match stem.split_once(" - ") {
        Some((a, t)) => (a.to_string(), t.to_string()),
        None => (String::new(), stem.clone()),
    };
    let (mut album, mut duration) = (String::new(), None);
    if let Ok(file) = lofty::read_from_path(path) {
        duration = Some(file.properties().duration().as_millis() as u64).filter(|d| *d > 0);
        if let Some(tag) = file.primary_tag().or(file.first_tag()) {
            if let Some(t) = tag.title() {
                title = t.to_string();
            }
            if let Some(a) = tag.artist() {
                artist = a.to_string();
            }
            if let Some(a) = tag.album() {
                album = a.to_string();
            }
        }
    }
    let uri = format!(
        "file:///{}",
        path.to_string_lossy()
            .replace('\\', "/")
            .trim_start_matches('/')
    );
    Song {
        id: uri,
        title,
        artist,
        album,
        duration_ms: duration,
        source: Source::File(path.to_path_buf()),
        art: None,
    }
}

/// Riflay's playlists (its settings file) when Riflay is installed here; none on macOS, where they are not a file.
fn read_playlists(data_dir: &Path) -> Vec<(String, String, Vec<Song>)> {
    let prefs = read_prefs(data_dir);
    let Some(raw) = prefs["flutter.playlists.v1"].as_str() else {
        return vec![];
    };
    let Ok(Value::Array(lists)) = serde_json::from_str::<Value>(raw) else {
        return vec![];
    };
    lists
        .iter()
        .filter_map(|p| {
            Some((
                p["id"].as_str()?.to_string(),
                p["name"].as_str().unwrap_or("").to_string(),
                p["tracks"]
                    .as_array()
                    .map_or(vec![], |t| t.iter().filter_map(song_from_riflay).collect()),
            ))
        })
        .collect()
}

/// Riflay's settings file (shared_preferences.json) when Riflay is installed here, else null.
fn read_prefs(data_dir: &Path) -> Value {
    std::fs::read_to_string(data_dir.join("shared_preferences.json"))
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or(Value::Null)
}

// ---- Radio ----

/// YouTube Music's radio for [seed]: its own when it is a YouTube Music song, else the radio of its match (the first
/// song found by its title and artist).
fn radio_youtube(seed: &Song) -> Result<Vec<Song>, String> {
    let video = match &seed.source {
        Source::YouTube(v) => v.clone(),
        Source::File(_) => {
            let found = search_youtube_music(&format!("{} {}", seed.title, seed.artist))?;
            match found.into_iter().next().map(|s| s.source) {
                Some(Source::YouTube(v)) => v,
                _ => return Err("No match on YouTube Music.".into()),
            }
        }
    };
    let v = innertube(
        "next",
        json!({
            "videoId": video,
            "playlistId": format!("RDAMVM{video}"),
            "isAudioOnly": true,
            "enablePersistentPlaylistPanel": true,
            "tunerSettingValue": "AUTOMIX_SETTING_NORMAL",
            "watchEndpointMusicSupportedConfigs": {"watchEndpointMusicConfig": {"hasPersistentPlaylistPanel": true, "musicVideoType": "MUSIC_VIDEO_TYPE_ATV"}},
        }),
    )?;
    let mut rows = vec![];
    all(&v, "playlistPanelVideoRenderer", &mut rows);
    let songs: Vec<Song> = rows
        .into_iter()
        .filter_map(panel_song)
        .filter(|s| !matches!(&s.source, Source::YouTube(v) if *v == video))
        .collect();
    if songs.is_empty() {
        return Err("YouTube Music has no radio for this song.".into());
    }
    Ok(songs)
}

/// A row of YouTube Music's queue panel: title, "Artist • Album • Year", length, picture.
fn panel_song(row: &Value) -> Option<Song> {
    let video = row["videoId"].as_str()?;
    let title = row["title"]["runs"][0]["text"].as_str()?.to_string();
    let byline: Vec<&str> = row["longBylineText"]["runs"]
        .as_array()
        .map_or(vec![], |r| {
            r.iter().filter_map(|x| x["text"].as_str()).collect()
        });
    let parts: Vec<String> = byline
        .join("")
        .split(" • ")
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
        .collect();
    let mut thumbs = vec![];
    all(&row["thumbnail"], "url", &mut thumbs);
    Some(Song {
        id: format!("yt:{video}"),
        title,
        artist: parts.first().cloned().unwrap_or_default(),
        album: if parts.len() >= 3 {
            parts[1].clone()
        } else {
            String::new()
        },
        duration_ms: row["lengthText"]["runs"][0]["text"]
            .as_str()
            .and_then(duration_of),
        source: Source::YouTube(video.to_string()),
        art: thumbs
            .last()
            .and_then(|u| u.as_str())
            .map(|u| u.replace("w60-h60", "w226-h226")),
    })
}

// ---- Pronunciation and translation of lyrics ----

/// The language lyrics are translated to: RIFLAY_LANG, Riflay's own setting, else the computer's language.
fn language(prefs: &Value) -> String {
    if let Ok(l) = std::env::var("RIFLAY_LANG")
        && !l.is_empty()
    {
        return l;
    }
    if let Some(l) = prefs["flutter.lyrics.targetLanguage"]
        .as_str()
        .filter(|l| !l.is_empty())
    {
        return l.to_string();
    }
    system_language().unwrap_or_else(|| "en".into())
}

#[cfg(windows)]
fn system_language() -> Option<String> {
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn GetUserDefaultLocaleName(name: *mut u16, len: i32) -> i32;
    }
    let mut buf = [0u16; 85];
    let n = unsafe { GetUserDefaultLocaleName(buf.as_mut_ptr(), buf.len() as i32) };
    if n <= 1 {
        return None;
    }
    let name = String::from_utf16_lossy(&buf[..n as usize - 1]);
    name.split('-')
        .next()
        .filter(|l| !l.is_empty())
        .map(str::to_lowercase)
}

#[cfg(not(windows))]
fn system_language() -> Option<String> {
    for key in ["LC_ALL", "LC_MESSAGES", "LANG"] {
        if let Ok(v) = std::env::var(key) {
            let l = v.split(['_', '.', '@']).next().unwrap_or("").to_lowercase();
            if !l.is_empty() && l != "c" && l != "posix" {
                return Some(l);
            }
        }
    }
    None
}

/// Letters outside the Latin script: kana, kanji, hangul, Cyrillic, Arabic…
fn has_non_latin(s: &str) -> bool {
    s.chars().any(|c| {
        c.is_alphabetic()
            && !matches!(c as u32, 0x41..=0x5A | 0x61..=0x7A | 0xAA | 0xBA | 0xC0..=0x24F | 0x1E00..=0x1EFF | 0x2C60..=0x2C7F | 0xA720..=0xA7FF)
    })
}

/// Google's romanization made readable (as the app does): the scholarly marks it puts on Thai, Hindi or Arabic
/// dropped. Chinese keeps its pinyin tones.
fn plain_marks(romanized: &str, line: &str) -> String {
    if line
        .chars()
        .any(|c| matches!(c as u32, 0x4E00..=0x9FFF | 0x3400..=0x4DBF))
    {
        return romanized.to_string();
    }
    let mut out = String::with_capacity(romanized.len());
    for c in romanized.chars() {
        let r = c as u32;
        if (0x0300..=0x036F).contains(&r)
            || (0x1AB0..=0x1AFF).contains(&r)
            || (0x1DC0..=0x1DFF).contains(&r)
        {
            continue;
        }
        let plain = match c {
            'ā' | 'á' | 'à' | 'ǎ' | 'ạ' | 'ă' | 'â' | 'ä' => "a",
            'ē' | 'é' | 'è' | 'ě' | 'ẹ' | 'ê' | 'ë' => "e",
            'ī' | 'í' | 'ì' | 'ǐ' | 'ị' | 'î' | 'ï' => "i",
            'ō' | 'ó' | 'ò' | 'ǒ' | 'ọ' | 'ô' | 'ö' => "o",
            'ū' | 'ú' | 'ù' | 'ǔ' | 'ụ' | 'û' | 'ü' | 'ů' => "u",
            'ṭ' => "t",
            'ḍ' => "d",
            'ṇ' | 'ṅ' | 'ñ' => "n",
            'ṁ' | 'ṃ' => "m",
            'ḥ' => "h",
            'ṣ' | 'ś' => "s",
            'ẓ' => "z",
            'ḷ' => "l",
            'ṛ' => "r",
            'ġ' => "g",
            'ḳ' => "k",
            'ç' => "c",
            'š' => "sh",
            'ž' => "zh",
            'č' => "ch",
            'Ā' | 'Á' => "A",
            'Ē' | 'É' => "E",
            'Ī' | 'Í' => "I",
            'Ō' | 'Ó' => "O",
            'Ū' | 'Ú' => "U",
            'Ś' | 'Ṣ' => "S",
            'Š' => "Sh",
            'Ž' => "Zh",
            'Č' => "Ch",
            _ => {
                out.push(c);
                continue;
            }
        };
        out.push_str(plain);
    }
    out
}

/// A value only when it adds something to [line].
fn useful(value: Option<&str>, line: &str) -> Option<String> {
    let v = value?.trim();
    (!v.is_empty() && v.to_lowercase() != line.to_lowercase()).then(|| v.to_string())
}

type Extras = (Option<String>, Option<String>);

/// Each line's pronunciation (for lines in another script) and translation to [to], from Google Translate's free
/// endpoint, which returns both in one request (as the app and the Better Lyrics extension ask it).
fn extras(lines: &[String], to: &str) -> Result<Vec<Extras>, String> {
    let mut unique: Vec<String> = vec![];
    for l in lines.iter().map(|l| l.trim()) {
        if !l.is_empty() && !unique.iter().any(|u| u == l) {
            unique.push(l.to_string());
        }
    }
    let mut sep = "0000".to_string();
    while unique.iter().any(|l| l.contains(&sep)) {
        sep.push('0');
    }
    // Lines go out joined by a separator that survives translation and romanization, chunked for the URL's length.
    let mut chunks: Vec<Vec<String>> = vec![vec![]];
    let mut size = 0;
    for l in &unique {
        let cost = url_part(&format!("{l}\n{sep}\n")).len();
        if size + cost > 8000 && chunks.last().is_some_and(|c| !c.is_empty()) {
            chunks.push(vec![]);
            size = 0;
        }
        if let Some(c) = chunks.last_mut() {
            c.push(l.clone());
        }
        size += cost;
    }
    let mut found: HashMap<String, Extras> = HashMap::new();
    for chunk in chunks.iter().filter(|c| !c.is_empty()) {
        let url = format!(
            "https://translate.googleapis.com/translate_a/single?client=dict-chrome-ex&sl=auto&tl={}&dt=t&dt=rm&q={}",
            url_part(to),
            url_part(&chunk.join(&format!("\n{sep}\n")))
        );
        let bytes = curl(&[&url, "-H", "User-Agent: Mozilla/5.0"], None)?;
        // A blocked client gets an HTML "Sorry" page.
        if bytes.first() != Some(&b'[') {
            return Err("Google Translate is not answering.".into());
        }
        let data: Value = serde_json::from_slice(&bytes)
            .map_err(|_| "Google Translate answered something unreadable.".to_string())?;
        let parts: Vec<&Value> = data[0]
            .as_array()
            .map_or(vec![], |a| a.iter().filter(|p| p.is_array()).collect());
        let translated: String = parts.iter().filter_map(|p| p[0].as_str()).collect();
        let romanized: String = parts
            .iter()
            .filter(|p| p[0].is_null() && p.as_array().is_some_and(|a| a.len() > 2))
            .map(|p| p[3].as_str().or(p[2].as_str()).unwrap_or(""))
            .collect();
        let same_language = data[2].as_str() == Some(to);
        let split = |s: &str| -> Option<Vec<String>> {
            let pieces: Vec<String> = s
                .split(sep.as_str())
                .map(|p| p.trim().to_string())
                .collect();
            (pieces.len() == chunk.len()).then_some(pieces)
        };
        // A reply that doesn't split back into the same lines can't be lined up.
        let t = if same_language {
            None
        } else {
            split(&translated)
        };
        let r = split(&romanized);
        for (i, line) in chunk.iter().enumerate() {
            let rom = if has_non_latin(line) {
                useful(
                    r.as_ref().map(|r| plain_marks(&r[i], line)).as_deref(),
                    line,
                )
            } else {
                None
            };
            let tr = useful(t.as_ref().map(|t| t[i].as_str()), line);
            found.insert(line.clone(), (rom, tr));
        }
    }
    Ok(lines
        .iter()
        .map(|l| found.get(l.trim()).cloned().unwrap_or((None, None)))
        .collect())
}

// ---- Lyrics and covers ----

fn parse_lrc(text: &str) -> Vec<(u64, String)> {
    let mut lines = vec![];
    for line in text.lines() {
        let mut rest = line;
        let mut times = vec![];
        while let Some(stripped) = rest.strip_prefix('[') {
            let Some(end) = stripped.find(']') else { break };
            let stamp = &stripped[..end];
            rest = &stripped[end + 1..];
            let Some((m, s)) = stamp.split_once(':') else {
                continue;
            };
            if let (Ok(m), Ok(s)) = (m.parse::<u64>(), s.parse::<f64>()) {
                times.push(m * 60_000 + (s * 1000.0) as u64);
            }
        }
        for t in times {
            lines.push((t, rest.trim().to_string()));
        }
    }
    lines.sort_by_key(|l| l.0);
    lines
}

fn url_part(s: &str) -> String {
    s.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                (b as char).to_string()
            }
            _ => format!("%{b:02X}"),
        })
        .collect()
}

/// The last song's lyrics, so its pronunciation and translation don't ask LRCLIB again.
static LYRICS: Mutex<Option<(String, Value)>> = Mutex::new(None);

fn lyrics(song: &Song) -> Value {
    if let Ok(cache) = LYRICS.lock()
        && let Some((id, v)) = cache.as_ref()
        && *id == song.id
    {
        return v.clone();
    }
    let v = find_lyrics(song);
    if let Ok(mut cache) = LYRICS.lock() {
        *cache = Some((song.id.clone(), v.clone()));
    }
    v
}

/// A .lrc beside the file, else LRCLIB's.
fn find_lyrics(song: &Song) -> Value {
    let reply = |lines: Vec<(u64, String)>, plain: Option<String>, source: &str| {
        json!({
            "trackId": song.id,
            "synced": !lines.is_empty(),
            "instrumental": false,
            "source": source,
            "lines": lines.iter().map(|(ms, t)| json!({"ms": ms, "text": t})).collect::<Vec<_>>(),
            "plain": plain,
        })
    };
    if let Source::File(path) = &song.source
        && let Ok(text) = std::fs::read_to_string(path.with_extension("lrc"))
    {
        return reply(parse_lrc(&text), None, "Beside the file");
    }
    let mut url = format!(
        "https://lrclib.net/api/get?artist_name={}&track_name={}",
        url_part(&song.artist),
        url_part(&song.title)
    );
    if let Some(d) = song.duration_ms {
        url.push_str(&format!("&duration={}", d / 1000));
    }
    if let Ok(bytes) = curl(
        &[
            &url,
            "-H",
            "User-Agent: riflay-tui (https://github.com/Araryarch67/Riflay)",
        ],
        None,
    ) && let Ok(v) = serde_json::from_slice::<Value>(&bytes)
    {
        if let Some(lrc) = v["syncedLyrics"].as_str() {
            return reply(parse_lrc(lrc), None, "LRCLIB");
        }
        if let Some(plain) = v["plainLyrics"].as_str() {
            return reply(vec![], Some(plain.to_string()), "LRCLIB");
        }
    }
    reply(vec![], None, "")
}

/// The cover, square from the middle, [size] pixels a side, as RGB: the file's own picture, a cover image beside it,
/// or the song's picture online.
fn cover(song: &Song, size: u32) -> Option<Vec<u8>> {
    let mut bytes: Option<Vec<u8>> = None;
    if let Source::File(path) = &song.source {
        use lofty::file::TaggedFileExt;
        if let Ok(file) = lofty::read_from_path(path) {
            bytes = file
                .tags()
                .iter()
                .flat_map(|t| t.pictures())
                .next()
                .map(|p| p.data().to_vec());
        }
        if bytes.is_none() {
            let dir = path.parent()?;
            bytes = ["cover.jpg", "folder.jpg", "cover.png", "front.jpg"]
                .iter()
                .find_map(|n| std::fs::read(dir.join(n)).ok());
        }
    }
    if bytes.is_none() {
        let url = match (&song.art, &song.source) {
            (Some(u), _) if u.starts_with("http") => u.clone(),
            (_, Source::YouTube(v)) => format!("https://i.ytimg.com/vi/{v}/hqdefault.jpg"),
            _ => return None,
        };
        bytes = curl(&[&url], None).ok();
    }
    let img = image::load_from_memory(&bytes?).ok()?.to_rgb8();
    let side = img.width().min(img.height());
    let square = image::imageops::crop_imm(
        &img,
        (img.width() - side) / 2,
        (img.height() - side) / 2,
        side,
        side,
    )
    .to_image();
    Some(image::imageops::thumbnail(&square, size, size).into_raw())
}

fn base64_encode(bytes: &[u8]) -> String {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let n = (chunk[0] as u32) << 16
            | (*chunk.get(1).unwrap_or(&0) as u32) << 8
            | *chunk.get(2).unwrap_or(&0) as u32;
        out.push(T[(n >> 18) as usize & 63] as char);
        out.push(T[(n >> 12) as usize & 63] as char);
        out.push(if chunk.len() > 1 {
            T[(n >> 6) as usize & 63] as char
        } else {
            '='
        });
        out.push(if chunk.len() > 2 {
            T[n as usize & 63] as char
        } else {
            '='
        });
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_lrc_lines_in_time_order() {
        let lines =
            parse_lrc("[00:12.50]second\n[00:01.00][00:30.00]first and again\n[ar:Someone]\n");
        assert_eq!(
            lines,
            vec![
                (1000, "first and again".into()),
                (12500, "second".into()),
                (30000, "first and again".into())
            ]
        );
    }

    #[test]
    fn turns_file_uris_into_paths() {
        let p = file_from_uri("file:///C:/Music/%E3%81%A8%E3%81%8D%20-%20KING.flac").unwrap();
        assert!(p.to_string_lossy().ends_with("とき - KING.flac"));
    }

    #[test]
    fn reads_durations_and_dates() {
        assert_eq!(duration_of("3:21"), Some(201_000));
        assert_eq!(duration_of("1:02:03"), Some(3_723_000));
        assert_eq!(duration_of("22M plays"), None);
        assert_eq!(civil(0), (1970, 1, 1));
        assert_eq!(civil(20_779), (2026, 11, 22));
    }

    #[test]
    fn base64_round_trips() {
        for data in [&b""[..], b"M", b"Ma", b"Man", b"\x00\xff\x10\x20"] {
            assert_eq!(crate::client::base64(&base64_encode(data)), data);
        }
    }

    /// On a computer with libmpv, yt-dlp, curl and a connection: RIFLAY_TUI_LIVE=1 cargo test -- --nocapture live
    #[test]
    fn live_search_resolve_and_play() {
        if std::env::var("RIFLAY_TUI_LIVE").is_err() {
            return;
        }
        let songs = search_youtube_music("houshou marine king").expect("search");
        assert!(!songs.is_empty());
        let first = &songs[0];
        println!(
            "found {} by {} ({:?} ms), {} results",
            first.title,
            first.artist,
            first.duration_ms,
            songs.len()
        );
        assert!(!first.artist.is_empty() && first.duration_ms.is_some());
        let Source::YouTube(video) = &first.source else {
            panic!("not a video")
        };
        let (tx, rx) = mpsc::channel();
        resolve(first.id.clone(), video.clone(), tx);
        let Inbox::Resolved(_, url) = rx.recv_timeout(Duration::from_secs(60)).expect("resolved")
        else {
            panic!()
        };
        let url = url.expect("stream address");
        println!("stream {}…", &url[..60.min(url.len())]);
        let mpv = Mpv::new().expect("libmpv");
        mpv.set("volume", "0");
        mpv.command(&["loadfile", &url, "replace"]);
        let start = Instant::now();
        let mut position = 0.0;
        while start.elapsed() < Duration::from_secs(20) && position < 2.0 {
            let _ = mpv.next_event(0.5);
            position = mpv
                .get("time-pos")
                .and_then(|p| p.parse().ok())
                .unwrap_or(0.0);
        }
        println!("played to {position:.1} s");
        assert!(position >= 2.0, "it played");
        let art = cover(first, 32).expect("cover");
        assert_eq!(art.len(), 32 * 32 * 3);
        let words = lyrics(first);
        println!(
            "lyrics: synced {} from {}",
            words["synced"], words["source"]
        );
    }

    /// Asks YouTube Music for a radio and Google for pronunciation and translation. Needs the network:
    /// RIFLAY_TUI_LIVE=1 cargo test live_radio -- --nocapture
    #[test]
    fn live_radio_and_extras() {
        if std::env::var("RIFLAY_TUI_LIVE").is_err() {
            return;
        }
        let seed = search_youtube_music("YOASOBI Idol").unwrap().remove(0);
        let radio = radio_youtube(&seed).unwrap();
        eprintln!("radio of {}: {} songs", seed.title, radio.len());
        for s in radio.iter().take(5) {
            eprintln!("  {} — {} ({:?} ms)", s.title, s.artist, s.duration_ms);
        }
        assert!(radio.len() > 5);
        assert!(radio.iter().all(|s| !s.title.is_empty()));
        let lines: Vec<String> = ["無敵の笑顔で荒らすメディア", "", "사랑해", "hello"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        let e = extras(&lines, "id").unwrap();
        eprintln!("{e:?}");
        assert_eq!(e.len(), 4);
        assert!(e[0].0.is_some() && e[0].1.is_some());
        assert!(e[2].0.is_some());
        assert!(e[3].0.is_none());
    }

    #[test]
    fn tells_latin_from_other_scripts() {
        assert!(!has_non_latin("Café déjà vu, ñandú"));
        assert!(has_non_latin("사랑해"));
        assert!(has_non_latin("Я тебя"));
        assert_eq!(plain_marks("C̄hạn rạk", "ฉันรัก"), "Chan rak");
        assert_eq!(plain_marks("wǒ ài nǐ", "我爱你"), "wǒ ài nǐ");
    }
}