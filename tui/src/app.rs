//! What the terminal shows and what each key does. The app is the truth: commands go to it, and its status events
//! come back; nothing here plays sound.

use std::collections::HashMap;
use std::time::{Duration, Instant};

use ratatui::crossterm::event::{KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
use ratatui::style::Color;
use serde_json::{Value, json};

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Tab {
    Queue,
    Lyrics,
    Search,
    Library,
    Playlists,
}

impl Tab {
    pub const ALL: [Tab; 5] = [
        Tab::Queue,
        Tab::Lyrics,
        Tab::Search,
        Tab::Library,
        Tab::Playlists,
    ];
    pub fn title(self) -> &'static str {
        match self {
            Tab::Queue => "Queue",
            Tab::Lyrics => "Lyrics",
            Tab::Search => "Search",
            Tab::Library => "Library",
            Tab::Playlists => "Playlists",
        }
    }
}

#[derive(Clone, Default)]
pub struct Track {
    pub id: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration_ms: Option<u64>,
}

impl Track {
    fn from(v: &Value) -> Option<Track> {
        Some(Track {
            id: v["id"].as_str()?.to_string(),
            title: v["title"].as_str().unwrap_or("").to_string(),
            artist: v["artist"].as_str().unwrap_or("").to_string(),
            album: v["album"].as_str().unwrap_or("").to_string(),
            duration_ms: v["durationMs"].as_u64(),
        })
    }
}

/// A lyric line's pronunciation and translation.
pub type LineExtras = (Option<String>, Option<String>);

pub struct Lyrics {
    pub track_id: String,
    pub lines: Vec<(u64, String)>,
    pub plain: Vec<String>,
    pub source: String,
}

/// A list the cursor moves in.
#[derive(Default)]
pub struct Cursor {
    pub at: usize,
}

impl Cursor {
    fn move_by(&mut self, by: isize, len: usize) {
        if len == 0 {
            self.at = 0;
            return;
        }
        self.at = (self.at as isize + by).clamp(0, len as isize - 1) as usize;
    }
}

pub const SOURCES: [&str; 3] = ["library", "youtube", "soundcloud"];

pub struct App {
    pub quit: bool,
    /// Playing on its own (no Riflay app): shown in the header; the visualizer has no levels then.
    pub standalone: bool,
    /// Nerd Font icons (else plain symbols).
    pub nerd: bool,
    pub disconnected: Option<String>,

    // The app's status, and when it came: the position counts on from there while playing.
    pub playing: bool,
    pub buffering: bool,
    pub track: Option<Track>,
    pub position_ms: u64,
    pub duration_ms: Option<u64>,
    pub volume: i64,
    pub can_set_volume: bool,
    pub shuffle: bool,
    pub repeat: String,
    pub autoplay: bool,
    pub discord: bool,
    pub last_error: Option<String>,
    received: Instant,
    queue_revision: Option<i64>,

    pub tab: Tab,
    pub queue: Vec<(usize, bool, Track)>,
    pub queue_cursor: Cursor,
    pub lyrics: Option<Lyrics>,
    /// Each lyric line's pronunciation and translation (by line, as the lyrics list them), for one song.
    pub extras: Option<(String, Vec<LineExtras>)>,
    extras_for: Option<String>,
    pub show_romanized: bool,
    pub show_translation: bool,
    lyrics_for: Option<String>,

    pub search_query: String,
    pub search_editing: bool,
    pub search_source: usize,
    pub search_results: Vec<Track>,
    pub search_cursor: Cursor,
    pub search_busy: bool,

    pub library: Vec<Track>,
    pub library_total: usize,
    pub library_cursor: Cursor,
    library_loading: bool,

    pub playlists: Vec<(String, String, u64)>,
    pub playlists_cursor: Cursor,
    pub playlist_open: Option<(String, String, Vec<Track>)>,
    pub playlist_cursor: Cursor,

    pub cover: Option<(String, usize, Vec<u8>)>,
    cover_for: Option<String>,
    pub accent: Color,
    pub levels: Vec<u8>,
    pub show_visualizer: bool,
    pub show_cover: bool,
    pub help: bool,
    pub toast: Option<(String, Instant)>,

    // Requests in flight, by tag; what each is for.
    next_tag: u64,
    pending: HashMap<u64, Purpose>,
    pub outbox: Vec<(u64, String, Value)>,
}

#[derive(Clone)]
enum Purpose {
    Queue,
    Lyrics(String),
    Extras(String),
    Cover(String),
    Search,
    Library,
    Playlists,
    Playlist(String, String),
    Action,
}

/// The cover's size in pixels a side: 32 columns, 16 rows of half blocks.
pub const COVER: usize = 32;

impl App {
    pub fn new() -> App {
        App {
            quit: false,
            standalone: false,
            nerd: true,
            disconnected: Some("Connecting to Riflay…".into()),
            playing: false,
            buffering: false,
            track: None,
            position_ms: 0,
            duration_ms: None,
            volume: 0,
            can_set_volume: true,
            shuffle: false,
            repeat: "off".into(),
            autoplay: true,
            discord: false,
            last_error: None,
            received: Instant::now(),
            queue_revision: None,
            tab: Tab::Queue,
            queue: vec![],
            queue_cursor: Cursor::default(),
            lyrics: None,
            lyrics_for: None,
            extras: None,
            extras_for: None,
            show_romanized: true,
            show_translation: false,
            search_query: String::new(),
            search_editing: false,
            search_source: 1,
            search_results: vec![],
            search_cursor: Cursor::default(),
            search_busy: false,
            library: vec![],
            library_total: 0,
            library_cursor: Cursor::default(),
            library_loading: false,
            playlists: vec![],
            playlists_cursor: Cursor::default(),
            playlist_open: None,
            playlist_cursor: Cursor::default(),
            cover: None,
            cover_for: None,
            accent: Color::Rgb(255, 128, 72),
            levels: vec![],
            show_visualizer: false,
            show_cover: true,
            help: false,
            toast: None,
            next_tag: 0,
            pending: HashMap::new(),
            outbox: vec![],
        }
    }

    fn send(&mut self, command: &str, params: Value, purpose: Purpose) {
        self.next_tag += 1;
        self.pending.insert(self.next_tag, purpose);
        self.outbox
            .push((self.next_tag, command.to_string(), params));
    }

    fn act(&mut self, command: &str, params: Value) {
        self.send(command, params, Purpose::Action);
    }

    fn say(&mut self, text: impl Into<String>) {
        self.toast = Some((text.into(), Instant::now()));
    }

    /// The position now: as the app said, counted on while playing.
    pub fn position(&self) -> u64 {
        let mut at = self.position_ms;
        if self.playing && !self.buffering {
            at += self.received.elapsed().as_millis() as u64;
        }
        match self.duration_ms {
            Some(d) => at.min(d),
            None => at,
        }
    }

    /// How long until something on screen changes on its own: the clock while playing, the toast's end; none
    /// (wait for an event) otherwise.
    pub fn next_tick(&self) -> Option<Duration> {
        let mut tick = None;
        if self.playing && !self.buffering && self.track.is_some() {
            tick = Some(Duration::from_millis(250));
        }
        if let Some((_, at)) = &self.toast {
            let left = Duration::from_secs(3).saturating_sub(at.elapsed());
            tick = Some(
                tick.map_or(left, |t: Duration| t.min(left))
                    .max(Duration::from_millis(50)),
            );
        }
        tick
    }

    pub fn tick(&mut self) {
        if let Some((_, at)) = &self.toast
            && at.elapsed() >= Duration::from_secs(3)
        {
            self.toast = None;
        }
    }

    pub fn connected(&mut self) {
        if self.disconnected.take().is_some() {
            self.send("playlists", json!({"limit": 100}), Purpose::Playlists);
            self.load_library();
        }
    }

    pub fn disconnected(&mut self, why: String) {
        self.disconnected = Some(why);
        self.playing = false;
    }

    /// A status or levels event from the subscription.
    pub fn event(&mut self, v: Value) {
        match v["type"].as_str() {
            Some("levels") => {
                self.levels = v["v"].as_array().map_or(vec![], |a| {
                    a.iter()
                        .map(|x| x.as_u64().unwrap_or(0).min(100) as u8)
                        .collect()
                });
            }
            Some("status") => {
                self.connected();
                self.playing = v["playing"].as_bool().unwrap_or(false);
                self.buffering = v["buffering"].as_bool().unwrap_or(false);
                self.track = Track::from(&v["track"]);
                self.position_ms = v["positionMs"].as_u64().unwrap_or(0);
                self.duration_ms = v["durationMs"]
                    .as_u64()
                    .or(self.track.as_ref().and_then(|t| t.duration_ms));
                self.volume = v["volume"].as_i64().unwrap_or(0);
                self.can_set_volume = v["canSetVolume"].as_bool().unwrap_or(true);
                self.shuffle = v["shuffle"].as_bool().unwrap_or(false);
                self.repeat = v["repeat"].as_str().unwrap_or("off").to_string();
                self.autoplay = v["autoplay"].as_bool().unwrap_or(false);
                self.discord = v["discord"].as_bool().unwrap_or(false);
                self.last_error = v["lastError"].as_str().map(str::to_string);
                self.received = Instant::now();
                if !self.playing {
                    self.levels.clear();
                }
                let revision = v["queueRevision"].as_i64();
                if revision != self.queue_revision {
                    self.queue_revision = revision;
                    self.send("queue", json!({"limit": 100}), Purpose::Queue);
                }
                self.follow_track();
            }
            _ => {}
        }
    }

    /// A new song: its cover and (on the Lyrics tab) its lyrics.
    fn follow_track(&mut self) {
        let id = self.track.as_ref().map(|t| t.id.clone());
        if self.show_cover && id != self.cover_for {
            self.cover_for = id.clone();
            match &id {
                Some(id) => self.send("cover", json!({"size": COVER}), Purpose::Cover(id.clone())),
                None => self.cover = None,
            }
        }
        if self.tab == Tab::Lyrics && id != self.lyrics_for {
            self.lyrics_for = id.clone();
            self.lyrics = None;
            if let Some(id) = id {
                self.send("lyrics", json!({}), Purpose::Lyrics(id));
            }
        }
    }

    fn load_library(&mut self) {
        if self.library_loading
            || (self.library_total > 0 && self.library.len() >= self.library_total)
        {
            return;
        }
        self.library_loading = true;
        let offset = self.library.len();
        self.send(
            "library",
            json!({"limit": 100, "offset": offset}),
            Purpose::Library,
        );
    }

    pub fn reply(&mut self, tag: u64, result: Result<Value, String>) {
        let Some(purpose) = self.pending.remove(&tag) else {
            return;
        };
        let v = match result {
            Ok(v) => v,
            Err(e) => {
                match purpose {
                    Purpose::Search => self.search_busy = false,
                    Purpose::Library => self.library_loading = false,
                    Purpose::Lyrics(_) | Purpose::Cover(_) => return,
                    Purpose::Extras(id) => {
                        if self.extras_for.as_ref() == Some(&id) {
                            self.extras_for = None;
                        }
                        self.say(if self.standalone {
                            "Translation unavailable: Google Translate is not answering."
                        } else {
                            "Translation unavailable."
                        });
                        return;
                    }
                    _ => {}
                }
                self.say(e);
                return;
            }
        };
        let tracks = |v: &Value| -> Vec<Track> {
            v["items"]
                .as_array()
                .map_or(vec![], |a| a.iter().filter_map(Track::from).collect())
        };
        match purpose {
            Purpose::Queue => {
                self.queue = v["items"].as_array().map_or(vec![], |a| {
                    a.iter()
                        .filter_map(|i| {
                            Some((
                                i["index"].as_u64()? as usize,
                                i["current"].as_bool().unwrap_or(false),
                                Track::from(&i["track"])?,
                            ))
                        })
                        .collect()
                });
                let len = self.queue.len();
                self.queue_cursor.move_by(0, len);
            }
            Purpose::Lyrics(id) => {
                if self.track.as_ref().map(|t| &t.id) != Some(&id) {
                    return;
                }
                let lines = v["lines"].as_array().map_or(vec![], |a| {
                    a.iter()
                        .map(|l| {
                            (
                                l["ms"].as_u64().unwrap_or(0),
                                l["text"].as_str().unwrap_or("").to_string(),
                            )
                        })
                        .collect()
                });
                let plain = v["plain"]
                    .as_str()
                    .map_or(vec![], |p| p.lines().map(str::to_string).collect());
                let source = v["source"].as_str().unwrap_or("").to_string();
                self.lyrics = Some(Lyrics {
                    track_id: id,
                    lines,
                    plain,
                    source,
                });
                self.want_extras();
            }
            Purpose::Extras(id) => {
                let lines = v["lines"].as_array().map_or(vec![], |a| {
                    a.iter()
                        .map(|l| {
                            (
                                l["romanized"].as_str().map(str::to_string),
                                l["translation"].as_str().map(str::to_string),
                            )
                        })
                        .collect()
                });
                self.extras = Some((id, lines));
            }
            Purpose::Cover(id) => {
                if self.track.as_ref().map(|t| &t.id) != Some(&id) {
                    return;
                }
                let size = v["size"].as_u64().unwrap_or(0) as usize;
                let rgb = crate::client::base64(v["rgb"].as_str().unwrap_or(""));
                if size == 0 || rgb.len() < size * size * 3 {
                    self.cover = None;
                    return;
                }
                self.accent = accent_of(&rgb);
                self.cover = Some((id, size, rgb));
            }
            Purpose::Search => {
                self.search_busy = false;
                self.search_results = tracks(&v);
                self.search_cursor = Cursor::default();
                if self.search_results.is_empty() {
                    self.say("Nothing found");
                }
            }
            Purpose::Library => {
                self.library_loading = false;
                self.library_total = v["total"].as_u64().unwrap_or(0) as usize;
                self.library.extend(tracks(&v));
            }
            Purpose::Playlists => {
                self.playlists = v["items"].as_array().map_or(vec![], |a| {
                    a.iter()
                        .filter_map(|p| {
                            Some((
                                p["id"].as_str()?.to_string(),
                                p["name"].as_str().unwrap_or("").to_string(),
                                p["trackCount"].as_u64().unwrap_or(0),
                            ))
                        })
                        .collect()
                });
            }
            Purpose::Playlist(id, name) => {
                self.playlist_open = Some((id, name, tracks(&v)));
                self.playlist_cursor = Cursor::default();
            }
            Purpose::Action => {}
        }
    }

    /// The pronunciation and translation of the lyrics shown, asked once per song while either is on.
    fn want_extras(&mut self) {
        if !(self.show_romanized || self.show_translation) {
            return;
        }
        let Some(l) = &self.lyrics else { return };
        if l.lines.is_empty() && l.plain.is_empty() {
            return;
        }
        let id = l.track_id.clone();
        if self.extras_for.as_ref() == Some(&id) {
            return;
        }
        self.extras_for = Some(id.clone());
        self.send("lyrics.extras", json!({}), Purpose::Extras(id));
    }

    fn set_tab(&mut self, tab: Tab) {
        self.tab = tab;
        self.search_editing = false;
        if tab == Tab::Lyrics {
            self.follow_track();
        }
        if tab == Tab::Playlists && self.playlists.is_empty() {
            self.send("playlists", json!({"limit": 100}), Purpose::Playlists);
        }
    }

    /// The list the cursor keys move in now, and how long it is.
    fn list(&mut self) -> Option<(&mut Cursor, usize)> {
        match self.tab {
            Tab::Queue => Some((&mut self.queue_cursor, self.queue.len())),
            Tab::Search => Some((&mut self.search_cursor, self.search_results.len())),
            Tab::Library => Some((&mut self.library_cursor, self.library.len())),
            Tab::Playlists => match &self.playlist_open {
                Some((_, _, t)) => Some((&mut self.playlist_cursor, t.len())),
                None => Some((&mut self.playlists_cursor, self.playlists.len())),
            },
            Tab::Lyrics => None,
        }
    }

    fn selected_track(&self) -> Option<Track> {
        match self.tab {
            Tab::Queue => self.queue.get(self.queue_cursor.at).map(|q| q.2.clone()),
            Tab::Search => self.search_results.get(self.search_cursor.at).cloned(),
            Tab::Library => self.library.get(self.library_cursor.at).cloned(),
            Tab::Playlists => self
                .playlist_open
                .as_ref()
                .and_then(|p| p.2.get(self.playlist_cursor.at).cloned()),
            Tab::Lyrics => None,
        }
    }

    fn seek_by(&mut self, seconds: i64) {
        if self.track.is_none() {
            return;
        }
        let to = (self.position() as i64 + seconds * 1000).max(0) as u64;
        let to = self
            .duration_ms
            .map_or(to, |d| to.min(d.saturating_sub(500)));
        // Shown at once; the app's status follows.
        self.position_ms = to;
        self.received = Instant::now();
        self.act("seek", json!({"seconds": to as f64 / 1000.0}));
    }

    pub fn key(&mut self, key: KeyEvent) {
        if key.kind != KeyEventKind::Press {
            return;
        }
        if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
            self.quit = true;
            return;
        }
        if self.help {
            self.help = false;
            return;
        }
        if self.search_editing {
            match key.code {
                KeyCode::Esc => self.search_editing = false,
                KeyCode::Enter => {
                    self.search_editing = false;
                    let query = self.search_query.trim().to_string();
                    if !query.is_empty() {
                        self.search_busy = true;
                        let source = SOURCES[self.search_source];
                        self.send(
                            "search",
                            json!({"query": query, "source": source, "limit": 50}),
                            Purpose::Search,
                        );
                    }
                }
                KeyCode::Backspace => {
                    self.search_query.pop();
                }
                KeyCode::Tab => self.search_source = (self.search_source + 1) % SOURCES.len(),
                KeyCode::Char(c) => self.search_query.push(c),
                _ => {}
            }
            return;
        }
        match key.code {
            KeyCode::Char('q') => self.quit = true,
            KeyCode::Char('?') => self.help = true,
            KeyCode::Char(' ') => self.act("toggle", json!({})),
            KeyCode::Char('n') => self.act("next", json!({})),
            KeyCode::Char('p') => self.act("previous", json!({})),
            KeyCode::Left => self.seek_by(-5),
            KeyCode::Right => self.seek_by(5),
            KeyCode::Char('[') => self.seek_by(-30),
            KeyCode::Char(']') => self.seek_by(30),
            KeyCode::Char('+') | KeyCode::Char('=') => {
                self.volume = (self.volume + 5).min(100);
                self.act("volume", json!({"value": self.volume}));
            }
            KeyCode::Char('-') => {
                self.volume = (self.volume - 5).max(0);
                self.act("volume", json!({"value": self.volume}));
            }
            KeyCode::Char('s') => self.act(
                "shuffle",
                json!({"mode": if self.shuffle { "off" } else { "on" }}),
            ),
            KeyCode::Char('r') => {
                let next = match self.repeat.as_str() {
                    "off" => "all",
                    "all" => "one",
                    _ => "off",
                };
                self.act("repeat", json!({"mode": next}));
            }
            KeyCode::Char('v') => {
                self.show_visualizer = !self.show_visualizer;
                self.levels.clear();
                // On its own, the player decodes the levels only while they show (with the app, the subscription asks).
                if self.standalone {
                    self.act("_levels", json!({"on": self.show_visualizer}));
                }
            }
            KeyCode::Char('o') => {
                self.show_romanized = !self.show_romanized;
                self.say(if self.show_romanized {
                    "Pronunciation on"
                } else {
                    "Pronunciation off"
                });
                self.want_extras();
            }
            KeyCode::Char('t') => {
                self.show_translation = !self.show_translation;
                self.say(if self.show_translation {
                    "Translation on"
                } else {
                    "Translation off"
                });
                self.want_extras();
            }
            KeyCode::Char('A') => {
                let on = !self.autoplay;
                self.act("autoplay", json!({"mode": if on { "on" } else { "off" }}));
                self.say(if on { "Autoplay on" } else { "Autoplay off" });
            }
            KeyCode::Char('D') => {
                let on = !self.discord;
                self.act("discord", json!({"mode": if on { "on" } else { "off" }}));
                self.say(if on {
                    "Discord shows what plays"
                } else {
                    "Discord shows nothing"
                });
            }
            KeyCode::Char('R') => {
                // The selected song's radio on a list, else the current song's.
                let seed = self
                    .selected_track()
                    .filter(|_| self.tab != Tab::Lyrics)
                    .or(self.track.clone());
                match seed {
                    Some(t) => {
                        self.say(format!("Starting a radio from {}…", t.title));
                        self.act("radio", json!({"id": t.id}));
                    }
                    None => self.say("Play or select a song to start its radio."),
                }
            }
            KeyCode::Char('c') => {
                self.show_cover = !self.show_cover;
                self.cover_for = None;
                self.follow_track();
            }
            KeyCode::Char('1') => self.set_tab(Tab::Queue),
            KeyCode::Char('2') => self.set_tab(Tab::Lyrics),
            KeyCode::Char('3') => self.set_tab(Tab::Search),
            KeyCode::Char('4') => self.set_tab(Tab::Library),
            KeyCode::Char('5') => self.set_tab(Tab::Playlists),
            KeyCode::Tab => {
                let i = Tab::ALL.iter().position(|t| *t == self.tab).unwrap_or(0);
                self.set_tab(Tab::ALL[(i + 1) % Tab::ALL.len()]);
            }
            KeyCode::BackTab => {
                let i = Tab::ALL.iter().position(|t| *t == self.tab).unwrap_or(0);
                self.set_tab(Tab::ALL[(i + Tab::ALL.len() - 1) % Tab::ALL.len()]);
            }
            KeyCode::Char('/') => {
                self.set_tab(Tab::Search);
                self.search_editing = true;
            }
            KeyCode::Up | KeyCode::Char('k') => self.move_cursor(-1),
            KeyCode::Down | KeyCode::Char('j') => self.move_cursor(1),
            KeyCode::PageUp => self.move_cursor(-10),
            KeyCode::PageDown => self.move_cursor(10),
            KeyCode::Home | KeyCode::Char('g') => self.move_cursor(-100_000),
            KeyCode::End | KeyCode::Char('G') => self.move_cursor(100_000),
            KeyCode::Esc | KeyCode::Backspace if self.tab == Tab::Playlists => {
                self.playlist_open = None
            }
            KeyCode::Enter => self.enter(),
            KeyCode::Char('a') => {
                if let Some(t) = self.selected_track().filter(|_| self.tab != Tab::Queue) {
                    self.act("queue.add", json!({"id": t.id}));
                    self.say(format!("Added: {}", t.title));
                }
            }
            KeyCode::Char('i') => {
                if let Some(t) = self.selected_track().filter(|_| self.tab != Tab::Queue) {
                    self.act("queue.next", json!({"id": t.id}));
                    self.say(format!("Plays next: {}", t.title));
                }
            }
            KeyCode::Char('d') | KeyCode::Delete if self.tab == Tab::Queue => {
                if let Some((index, _, _)) = self.queue.get(self.queue_cursor.at) {
                    let index = *index;
                    self.act("queue.remove", json!({"index": index}));
                }
            }
            _ => {}
        }
    }

    fn move_cursor(&mut self, by: isize) {
        if let Some((cursor, len)) = self.list() {
            cursor.move_by(by, len);
        }
        // The library is read a hundred at a time, as the cursor gets near the end.
        if self.tab == Tab::Library && self.library_cursor.at + 20 >= self.library.len() {
            self.load_library();
        }
    }

    fn enter(&mut self) {
        match self.tab {
            Tab::Queue => {
                if let Some((index, _, _)) = self.queue.get(self.queue_cursor.at) {
                    let index = *index;
                    self.act("queue.play", json!({"index": index}));
                }
            }
            Tab::Search | Tab::Library => {
                if let Some(t) = self.selected_track() {
                    self.act("play", json!({"id": t.id}));
                }
            }
            Tab::Playlists => match &self.playlist_open {
                Some((id, _, tracks)) => {
                    if !tracks.is_empty() {
                        let id = id.clone();
                        self.act("playlist.play", json!({"id": id}));
                    }
                }
                None => {
                    if let Some((id, name, _)) =
                        self.playlists.get(self.playlists_cursor.at).cloned()
                    {
                        self.send(
                            "playlist.show",
                            json!({"id": id, "limit": 100}),
                            Purpose::Playlist(id.clone(), name),
                        );
                    }
                }
            },
            Tab::Lyrics => {}
        }
    }
}

/// The cover's lively colour: the average of its more saturated pixels, lifted so it reads on a dark terminal.
fn accent_of(rgb: &[u8]) -> Color {
    let (mut r, mut g, mut b, mut n) = (0u64, 0u64, 0u64, 0u64);
    for px in rgb.as_chunks::<3>().0 {
        let (hi, lo) = (
            *px.iter().max().unwrap() as i32,
            *px.iter().min().unwrap() as i32,
        );
        if hi - lo > 48 && hi > 80 {
            r += px[0] as u64;
            g += px[1] as u64;
            b += px[2] as u64;
            n += 1;
        }
    }
    if n == 0 {
        return Color::Rgb(255, 128, 72);
    }
    let (r, g, b) = ((r / n) as f32, (g / n) as f32, (b / n) as f32);
    let max = r.max(g).max(b).max(1.0);
    let lift = (230.0 / max).max(1.0);
    Color::Rgb(
        (r * lift).min(255.0) as u8,
        (g * lift).min(255.0) as u8,
        (b * lift).min(255.0) as u8,
    )
}
