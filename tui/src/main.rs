//! riflay-tui: Riflay in a terminal. With the Riflay app open it is the app's remote (the app plays, this draws);
//! without it, it plays on its own through libmpv. Light by design: it draws only when something changed, sleeps while
//! nothing plays, and asks for the visualizer's levels only while it shows them.

mod app;
mod client;
mod discord;
mod local;
mod mpv;
mod ui;
mod viz;

use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread;

use ratatui::crossterm::event::{self, Event};
use serde_json::{Value, json};

/// Everything that wakes the drawing loop.
pub enum Message {
    Input(Event),
    Event(Value),
    Reply(u64, String, Result<Value, String>),
    Disconnected(String),
}

#[derive(PartialEq)]
enum Mode {
    /// The app if it is open, else on its own.
    Auto,
    Remote,
    Standalone,
}

const HELP: &str = "riflay-tui: Riflay in a terminal.

With the Riflay desktop app open, riflay-tui controls it. Without it, riflay-tui plays on its own:
your Riflay library and playlists if Riflay is installed (else the Music folder), YouTube Music
search, lyrics and covers. Playing on its own needs libmpv (mpv's library), and for YouTube Music
yt-dlp, and curl for search and lyrics.

  --standalone      play on its own even when the app is open
  --remote          only control the app (wait for it to open)
  --endpoint PATH   the app's CLI endpoint file (default: the app's own)
  --plain-icons     plain symbols instead of a Nerd Font's icons
  -V, --version     print the version

Icons: riflay-tui draws a Nerd Font's icons. Install one (https://www.nerdfonts.com, e.g. JetBrainsMono
Nerd Font) and pick it as your terminal's font; without one, use --plain-icons.

Environment: RIFLAY_LIBMPV (libmpv's path), RIFLAY_MUSIC_DIR (the folder to play without Riflay),
RIFLAY_LANG (the language lyrics are translated to), RIFLAY_TUI_ICONS=plain (as --plain-icons).
In the player, ? lists the keys.";

fn main() {
    let mut endpoint = client::default_endpoint();
    let mut mode = Mode::Auto;
    // Nerd Font icons unless asked otherwise (RIFLAY_TUI_ICONS=plain, or --plain-icons).
    let mut nerd = std::env::var("RIFLAY_TUI_ICONS").map_or(true, |v| v != "plain");
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--endpoint" => {
                if let Some(path) = args.next() {
                    endpoint = path.into();
                }
            }
            "--standalone" => mode = Mode::Standalone,
            "--remote" => mode = Mode::Remote,
            "--plain-icons" => nerd = false,
            "--nerd-icons" => nerd = true,
            "-h" | "--help" => {
                println!("{HELP}");
                return;
            }
            "-V" | "--version" => {
                println!("riflay-tui {}", env!("CARGO_PKG_VERSION"));
                return;
            }
            other => {
                eprintln!("Unknown option: {other}\n\n{HELP}");
                std::process::exit(2);
            }
        }
    }

    let (tx, rx) = mpsc::channel::<Message>();
    // The app when it is open (and answers); else, or when asked, the player of its own.
    let app_open = mode != Mode::Standalone
        && client::Endpoint::read(&endpoint)
            .is_ok_and(|ep| ep.request("status", json!({})).is_ok());
    let standalone = mode == Mode::Standalone || (mode == Mode::Auto && !app_open);
    let mut subscription = None;
    let worker = if standalone {
        let data = endpoint
            .parent()
            .and_then(|p| p.parent())
            .map(|p| p.to_path_buf())
            .unwrap_or_default();
        match local::spawn(tx.clone(), data) {
            Ok(worker) => worker,
            Err(e) => {
                eprintln!(
                    "riflay-tui can't play on its own here: {e}\nOpen the Riflay app and run riflay-tui again to control it."
                );
                std::process::exit(1);
            }
        }
    } else {
        let shared = Arc::new(Mutex::new(None));
        subscription = Some(client::Subscription::spawn(
            endpoint,
            shared.clone(),
            tx.clone(),
        ));
        client::spawn_worker(shared, tx.clone())
    };

    // Keys and resizes on a thread of their own: the loop below sleeps on one channel for everything.
    let input = tx.clone();
    thread::spawn(move || {
        while let Ok(e) = event::read() {
            if input.send(Message::Input(e)).is_err() {
                break;
            }
        }
    });

    let mut terminal = ratatui::init();
    let mut app = app::App::new();
    app.standalone = standalone;
    app.nerd = nerd;
    let mut dirty = true;
    loop {
        if dirty {
            let _ = terminal.draw(|f| ui::draw(f, &app));
            dirty = false;
        }
        // Wait for something, or for the clock while a song plays (the bar and the lyrics move); nothing else wakes it.
        let message = match app.next_tick() {
            Some(t) => match rx.recv_timeout(t) {
                Ok(m) => Some(m),
                Err(mpsc::RecvTimeoutError::Timeout) => None,
                Err(_) => break,
            },
            None => match rx.recv() {
                Ok(m) => Some(m),
                Err(_) => break,
            },
        };
        match message {
            None => app.tick(),
            Some(Message::Input(Event::Key(key))) => app.key(key),
            Some(Message::Input(Event::Resize(..))) => {}
            Some(Message::Input(_)) => continue,
            Some(Message::Event(v)) => app.event(v),
            Some(Message::Reply(tag, _, result)) => app.reply(tag, result),
            Some(Message::Disconnected(why)) => app.disconnected(why),
        }
        dirty = true;
        if app.quit {
            break;
        }
        if let Some(s) = &subscription {
            s.set_levels(app.show_visualizer && app.disconnected.is_none());
        }
        for request in app.outbox.drain(..) {
            let _ = worker.send(request);
        }
    }
    ratatui::restore();
}
