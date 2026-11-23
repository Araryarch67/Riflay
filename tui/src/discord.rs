//! Discord Rich Presence for the standalone player, over Discord's local IPC (no SDK, no network): frames of
//! `[u32 LE opcode][u32 LE length][JSON]` on `discord-ipc-N`, a named pipe on Windows, a Unix socket elsewhere.
//! One thread; it sleeps until the song changes, and sends at most one update every four seconds (Discord allows
//! five in twenty).

use std::io::{Read, Write};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::thread;
use std::time::{Duration, Instant};

use serde_json::{Value, json};

/// Riflay's application on Discord (the app's own).
const CLIENT_ID: &str = "1561368591297941655";

trait Pipe: Read + Write + Send {}
impl<T: Read + Write + Send> Pipe for T {}

/// Starts the presence thread. Send an activity (Discord's JSON) to show it, or None to clear it.
pub fn spawn() -> Sender<Option<Value>> {
    let (tx, rx) = mpsc::channel();
    thread::spawn(move || run(rx));
    tx
}

fn run(rx: Receiver<Option<Value>>) {
    let mut pipe: Option<Box<dyn Pipe>> = None;
    let mut sent: Option<Option<Value>> = None;
    let mut last = Instant::now() - Duration::from_secs(60);
    let mut wanted: Option<Option<Value>> = None;
    let mut closing = false;
    while !closing {
        // Wait for a change; while one waits for its turn, only until then.
        let wait = if wanted.is_some() {
            Duration::from_secs(4).saturating_sub(last.elapsed())
        } else {
            Duration::from_secs(3600)
        };
        match rx.recv_timeout(wait) {
            Ok(a) => {
                wanted = Some(a);
                while let Ok(a) = rx.try_recv() {
                    wanted = Some(a);
                }
                if last.elapsed() < Duration::from_secs(4) {
                    continue;
                }
            }
            Err(RecvTimeoutError::Timeout) => {}
            // The player is gone: what it asked for last (clearing, usually) is sent, then the thread ends.
            Err(RecvTimeoutError::Disconnected) => closing = true,
        }
        let Some(activity) = wanted.take() else {
            continue;
        };
        if sent.as_ref() == Some(&activity) {
            continue;
        }
        if pipe.is_none() {
            pipe = connect();
        }
        let Some(p) = pipe.as_mut() else {
            // Discord isn't open: tried again with the next change.
            continue;
        };
        let frame = json!({
            "cmd": "SET_ACTIVITY",
            "args": {"pid": std::process::id(), "activity": activity},
            "nonce": format!("{}", last.elapsed().as_nanos()),
        });
        if send(p, 1, &frame).and_then(|_| receive(p)).is_ok() {
            sent = Some(activity);
        } else {
            pipe = None;
            sent = None;
        }
        last = Instant::now();
    }
}

fn send(p: &mut Box<dyn Pipe>, op: u32, body: &Value) -> std::io::Result<()> {
    let body = body.to_string();
    let mut frame = Vec::with_capacity(8 + body.len());
    frame.extend_from_slice(&op.to_le_bytes());
    frame.extend_from_slice(&(body.len() as u32).to_le_bytes());
    frame.extend_from_slice(body.as_bytes());
    p.write_all(&frame)?;
    p.flush()
}

/// One frame from Discord, read and dropped (its answer to the handshake or a command).
fn receive(p: &mut Box<dyn Pipe>) -> std::io::Result<()> {
    let mut head = [0u8; 8];
    p.read_exact(&mut head)?;
    let len = u32::from_le_bytes([head[4], head[5], head[6], head[7]]) as usize;
    if len > 1 << 20 {
        return Err(std::io::Error::other("frame too long"));
    }
    let mut body = vec![0u8; len];
    p.read_exact(&mut body)?;
    // Opcode 2: Discord closed the connection.
    if u32::from_le_bytes([head[0], head[1], head[2], head[3]]) == 2 {
        return Err(std::io::Error::other("closed"));
    }
    Ok(())
}

fn connect() -> Option<Box<dyn Pipe>> {
    for path in paths() {
        let Some(mut p) = open(&path) else { continue };
        if send(&mut p, 0, &json!({"v": 1, "client_id": CLIENT_ID})).is_ok()
            && receive(&mut p).is_ok()
        {
            return Some(p);
        }
    }
    None
}

#[cfg(windows)]
fn open(path: &str) -> Option<Box<dyn Pipe>> {
    std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(path)
        .ok()
        .map(|f| Box::new(f) as Box<dyn Pipe>)
}

#[cfg(unix)]
fn open(path: &str) -> Option<Box<dyn Pipe>> {
    std::os::unix::net::UnixStream::connect(path).ok().map(|s| {
        let _ = s.set_read_timeout(Some(Duration::from_secs(5)));
        Box::new(s) as Box<dyn Pipe>
    })
}

/// Where Discord listens: discord-ipc-0 to 9, in its runtime folders (and the sandboxed clients' ones).
fn paths() -> Vec<String> {
    let mut out = vec![];
    if cfg!(windows) {
        for i in 0..10 {
            out.push(format!(r"\\?\pipe\discord-ipc-{i}"));
        }
        return out;
    }
    let mut bases: Vec<String> = vec![];
    for key in ["XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"] {
        if let Ok(dir) = std::env::var(key)
            && !dir.is_empty()
            && !bases.contains(&dir)
        {
            bases.push(dir.trim_end_matches('/').to_string());
        }
    }
    if !bases.iter().any(|b| b == "/tmp") {
        bases.push("/tmp".into());
    }
    for base in &bases {
        for sub in [
            "",
            "app/com.discordapp.Discord/",
            "app/dev.vencord.Vesktop/",
            "snap.discord/",
            ".flatpak/com.discordapp.Discord/xdg-run/",
        ] {
            for i in 0..10 {
                out.push(format!("{base}/{sub}discord-ipc-{i}"));
            }
        }
    }
    out
}

/// "Listening to" a song: its title, artist and album, the cover when it is online, and the time left while it plays.
#[allow(clippy::too_many_arguments)]
pub fn activity(
    title: &str,
    artist: &str,
    album: &str,
    art: Option<&str>,
    video: Option<&str>,
    playing: bool,
    start_ms: i64,
    duration_ms: Option<u64>,
) -> Value {
    let clip = |s: &str| -> String {
        let s = s.trim();
        let s: String = s.chars().take(127).collect();
        if s.chars().count() < 2 {
            format!("{s}  ")
        } else {
            s
        }
    };
    let listen = video.map(|v| format!("https://music.youtube.com/watch?v={v}"));
    let mut a = json!({
        "type": 2,
        "status_display_type": 2,
        "details": clip(title),
        "state": clip(if artist.is_empty() { "Riflay" } else { artist }),
        "assets": {
            "large_image": art.unwrap_or("openmusic"),
            "large_text": clip(if album.is_empty() { title } else { album }),
            "small_image": "openmusic",
            "small_text": if playing { "Riflay (terminal)" } else { "Paused · Riflay (terminal)" },
        },
    });
    if playing {
        a["timestamps"] = match duration_ms {
            Some(d) => json!({"start": start_ms, "end": start_ms + d as i64}),
            None => json!({"start": start_ms}),
        };
    }
    let mut buttons = vec![];
    if let Some(url) = &listen {
        buttons.push(json!({"label": "Listen on YouTube Music", "url": url}));
    }
    buttons
        .push(json!({"label": "Download Riflay", "url": "https://github.com/Araryarch67/Riflay"}));
    a["buttons"] = json!(buttons);
    a
}
