//! The Riflay CLI protocol: one JSON line per request on a loopback socket, with the token from the app's
//! endpoint file. `subscribe` keeps its connection open and streams a line per event.

use std::io::{BufRead, BufReader, Write};
use std::net::{Shutdown, TcpStream};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::Sender;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use serde_json::{Value, json};

use crate::Message;

const API_VERSION: i64 = 1;

/// Where the app writes its port and token: `RIFLAY_CLI_ENDPOINT`, or the app's private folder.
pub fn default_endpoint() -> PathBuf {
    if let Ok(path) = std::env::var("RIFLAY_CLI_ENDPOINT")
        && !path.is_empty()
    {
        return PathBuf::from(path);
    }
    let home =
        std::env::var(if cfg!(windows) { "USERPROFILE" } else { "HOME" }).unwrap_or_default();
    let base = if cfg!(windows) {
        let appdata =
            std::env::var("APPDATA").unwrap_or_else(|_| format!("{home}\\AppData\\Roaming"));
        PathBuf::from(appdata).join("dev.riflay").join("riflay")
    } else if cfg!(target_os = "macos") {
        PathBuf::from(home).join("Library/Application Support/dev.riflay.riflay")
    } else {
        let data = std::env::var("XDG_DATA_HOME")
            .ok()
            .filter(|d| !d.is_empty())
            .unwrap_or_else(|| format!("{home}/.local/share"));
        PathBuf::from(data).join("dev.riflay.riflay")
    };
    base.join("cli").join("endpoint.json")
}

#[derive(Clone)]
pub struct Endpoint {
    port: u16,
    token: String,
}

impl Endpoint {
    pub fn read(path: &PathBuf) -> Result<Endpoint, String> {
        let text = std::fs::read_to_string(path)
            .map_err(|_| "Riflay is not running. Open the desktop app first.".to_string())?;
        let v: Value = serde_json::from_str(&text)
            .map_err(|_| "The app's endpoint file is unreadable.".to_string())?;
        if v["apiVersion"].as_i64() != Some(API_VERSION) {
            return Err("This riflay-tui does not match the app's version.".into());
        }
        let port = v["port"]
            .as_u64()
            .filter(|p| *p > 0 && *p < 65536)
            .ok_or("No port in the endpoint file.")?;
        let token = v["token"]
            .as_str()
            .ok_or("No token in the endpoint file.")?
            .to_string();
        Ok(Endpoint {
            port: port as u16,
            token,
        })
    }

    fn connect(&self, command: &str, params: Value) -> Result<TcpStream, String> {
        let stream =
            TcpStream::connect_timeout(&([127, 0, 0, 1], self.port).into(), Duration::from_secs(2))
                .map_err(|_| "Cannot reach Riflay. Is the app open?".to_string())?;
        stream.set_nodelay(true).ok();
        let line = json!({"apiVersion": API_VERSION, "token": self.token, "command": command, "params": params});
        let mut writer = stream.try_clone().map_err(|e| e.to_string())?;
        writeln!(writer, "{line}").map_err(|e| e.to_string())?;
        writer.flush().map_err(|e| e.to_string())?;
        Ok(stream)
    }

    /// One request, its result or the app's message.
    pub fn request(&self, command: &str, params: Value) -> Result<Value, String> {
        let stream = self.connect(command, params)?;
        stream.set_read_timeout(Some(Duration::from_secs(60))).ok();
        let mut line = String::new();
        BufReader::new(stream)
            .read_line(&mut line)
            .map_err(|_| "No reply from Riflay.".to_string())?;
        let mut v: Value =
            serde_json::from_str(&line).map_err(|_| "Invalid reply from Riflay.".to_string())?;
        if v["ok"].as_bool() == Some(true) {
            Ok(v["result"].take())
        } else {
            Err(v["error"]["message"]
                .as_str()
                .unwrap_or("The command failed.")
                .to_string())
        }
    }
}

/// Requests run here, off the drawing thread: a search on YouTube can take seconds.
pub fn spawn_worker(
    endpoint: Arc<Mutex<Option<Endpoint>>>,
    out: Sender<Message>,
) -> Sender<(u64, String, Value)> {
    let (tx, rx) = std::sync::mpsc::channel::<(u64, String, Value)>();
    thread::spawn(move || {
        for (tag, command, params) in rx {
            let ep = endpoint.lock().ok().and_then(|e| e.clone());
            let result = match ep {
                Some(ep) => ep.request(&command, params),
                None => Err("Not connected to Riflay.".into()),
            };
            if out.send(Message::Reply(tag, command, result)).is_err() {
                break;
            }
        }
    });
    tx
}

/// The live connection: reconnects every two seconds while the app is away, and again when [Subscription::restart]
/// is called (the visualizer's levels switched on or off).
pub struct Subscription {
    levels: Arc<AtomicBool>,
    current: Arc<Mutex<Option<TcpStream>>>,
}

impl Subscription {
    pub fn spawn(
        path: PathBuf,
        endpoint: Arc<Mutex<Option<Endpoint>>>,
        out: Sender<Message>,
    ) -> Subscription {
        let levels = Arc::new(AtomicBool::new(false));
        let current: Arc<Mutex<Option<TcpStream>>> = Arc::new(Mutex::new(None));
        let (want, slot) = (levels.clone(), current.clone());
        thread::spawn(move || {
            loop {
                let ep = match Endpoint::read(&path) {
                    Ok(ep) => ep,
                    Err(e) => {
                        if out.send(Message::Disconnected(e)).is_err() {
                            return;
                        }
                        thread::sleep(Duration::from_secs(2));
                        continue;
                    }
                };
                if let Ok(mut e) = endpoint.lock() {
                    *e = Some(ep.clone());
                }
                let on = if want.load(Ordering::Relaxed) {
                    "on"
                } else {
                    "off"
                };
                match ep.connect("subscribe", json!({"levels": on})) {
                    Ok(stream) => {
                        if let Ok(mut s) = slot.lock() {
                            *s = stream.try_clone().ok();
                        }
                        let reader = BufReader::new(stream);
                        for line in reader.lines() {
                            let Ok(line) = line else { break };
                            let Ok(mut v) = serde_json::from_str::<Value>(&line) else {
                                continue;
                            };
                            if v["ok"].as_bool() != Some(true) {
                                let message = v["error"]["message"]
                                    .as_str()
                                    .unwrap_or("Riflay refused")
                                    .to_string();
                                let _ = out.send(Message::Disconnected(message));
                                break;
                            }
                            if out.send(Message::Event(v["result"].take())).is_err() {
                                return;
                            }
                        }
                        if let Ok(mut s) = slot.lock() {
                            *s = None;
                        }
                    }
                    Err(e) => {
                        if out.send(Message::Disconnected(e)).is_err() {
                            return;
                        }
                    }
                }
                thread::sleep(Duration::from_millis(400));
            }
        });
        Subscription { levels, current }
    }

    /// Asks for the visualizer's levels or not: the connection is made again with the new choice.
    pub fn set_levels(&self, on: bool) {
        if self.levels.swap(on, Ordering::Relaxed) != on
            && let Ok(s) = self.current.lock()
            && let Some(stream) = s.as_ref()
        {
            let _ = stream.shutdown(Shutdown::Both);
        }
    }
}

/// Base64 (standard alphabet, padded), for the cover's pixels.
pub fn base64(text: &str) -> Vec<u8> {
    let mut out = Vec::with_capacity(text.len() * 3 / 4);
    let (mut acc, mut bits) = (0u32, 0u32);
    for c in text.bytes() {
        let v = match c {
            b'A'..=b'Z' => c - b'A',
            b'a'..=b'z' => c - b'a' + 26,
            b'0'..=b'9' => c - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            _ => continue,
        } as u32;
        acc = (acc << 6) | v;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((acc >> bits) as u8);
            acc &= (1 << bits) - 1;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::base64;

    #[test]
    fn decodes_base64() {
        assert_eq!(base64("TWFu"), b"Man");
        assert_eq!(base64("TWE="), b"Ma");
        assert_eq!(base64("TQ=="), b"M");
        assert_eq!(base64("AAECAwQF"), vec![0, 1, 2, 3, 4, 5]);
    }
}
