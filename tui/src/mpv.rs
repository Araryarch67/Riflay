//! libmpv, loaded when the standalone player starts: plays local files and stream addresses, no video, no window.
//! Only the few calls the player needs, through libmpv's C client API.

use std::ffi::{CStr, CString, c_char, c_int, c_void};
use std::path::PathBuf;
use std::sync::Arc;

use libloading::Library;

type Handle = *mut c_void;

#[repr(C)]
struct RawEvent {
    event_id: c_int,
    error: c_int,
    reply_userdata: u64,
    data: *mut c_void,
}

#[repr(C)]
struct RawProperty {
    name: *const c_char,
    format: c_int,
    data: *mut c_void,
}

#[repr(C)]
struct RawEndFile {
    reason: c_int,
    error: c_int,
}

const FORMAT_FLAG: c_int = 3;
const FORMAT_DOUBLE: c_int = 5;

const EVENT_SHUTDOWN: c_int = 1;
const EVENT_END_FILE: c_int = 7;
const EVENT_FILE_LOADED: c_int = 8;
const EVENT_PLAYBACK_RESTART: c_int = 21;
const EVENT_PROPERTY_CHANGE: c_int = 22;

const END_EOF: c_int = 0;
const END_ERROR: c_int = 4;

pub enum Event {
    /// A file finished: on its own (eof true), or it could not be played.
    Ended {
        eof: bool,
        error: bool,
    },
    Loaded,
    /// After a seek or a stall, playing again.
    Restarted,
    Paused(bool),
    Duration(f64),
    Buffering(bool),
    Shutdown,
}

struct Api {
    create: unsafe extern "C" fn() -> Handle,
    initialize: unsafe extern "C" fn(Handle) -> c_int,
    set_option_string: unsafe extern "C" fn(Handle, *const c_char, *const c_char) -> c_int,
    set_property_string: unsafe extern "C" fn(Handle, *const c_char, *const c_char) -> c_int,
    get_property_string: unsafe extern "C" fn(Handle, *const c_char) -> *mut c_char,
    free: unsafe extern "C" fn(*mut c_void),
    command: unsafe extern "C" fn(Handle, *mut *const c_char) -> c_int,
    observe_property: unsafe extern "C" fn(Handle, u64, *const c_char, c_int) -> c_int,
    wait_event: unsafe extern "C" fn(Handle, f64) -> *mut RawEvent,
    terminate_destroy: unsafe extern "C" fn(Handle),
    _lib: Library,
}

/// One mpv player. Commands from any thread (libmpv's client API is thread-safe); events from [Mpv::next_event] on one.
pub struct Mpv {
    api: Arc<Api>,
    handle: Handle,
}

unsafe impl Send for Mpv {}
unsafe impl Sync for Mpv {}

/// Where libmpv may be: `RIFLAY_LIBMPV`, next to this program, a Riflay install, then the system's own.
fn candidates() -> Vec<PathBuf> {
    let mut out = vec![];
    if let Ok(p) = std::env::var("RIFLAY_LIBMPV") {
        out.push(PathBuf::from(p));
    }
    let names: &[&str] = if cfg!(windows) {
        &["libmpv-2.dll", "mpv-2.dll", "mpv-1.dll"]
    } else if cfg!(target_os = "macos") {
        &["libmpv.2.dylib", "libmpv.dylib"]
    } else {
        &["libmpv.so.2", "libmpv.so.1", "libmpv.so"]
    };
    let mut dirs = vec![];
    if let Some(dir) = std::env::current_exe()
        .ok()
        .and_then(|e| e.parent().map(|p| p.to_path_buf()))
    {
        // Inside Riflay's own bundle: lib/ on Linux, Frameworks/ beside MacOS/ in the .app.
        dirs.push(dir.join("lib"));
        dirs.push(dir.join("..").join("Frameworks"));
        dirs.push(dir);
    }
    if cfg!(windows) {
        for var in ["LOCALAPPDATA", "ProgramFiles"] {
            if let Ok(base) = std::env::var(var) {
                dirs.push(PathBuf::from(&base).join("Riflay"));
                dirs.push(PathBuf::from(&base).join("Programs").join("Riflay"));
            }
        }
        if let Ok(home) = std::env::var("USERPROFILE") {
            dirs.push(
                PathBuf::from(home)
                    .join("scoop")
                    .join("apps")
                    .join("riflay")
                    .join("current"),
            );
        }
    } else if cfg!(target_os = "macos") {
        dirs.push(PathBuf::from(
            "/Applications/Riflay.app/Contents/Frameworks",
        ));
        dirs.push(PathBuf::from("/opt/homebrew/lib"));
        dirs.push(PathBuf::from("/usr/local/lib"));
    } else {
        dirs.push(PathBuf::from("/usr/share/riflay/lib"));
        dirs.push(PathBuf::from("/opt/riflay/lib"));
    }
    for dir in &dirs {
        for name in names {
            out.push(dir.join(name));
        }
    }
    // Last, by name: the system's loader finds it on its own path.
    for name in names {
        out.push(PathBuf::from(name));
    }
    out
}

fn load() -> Result<Api, String> {
    let mut last = String::new();
    for path in candidates() {
        let lib = match unsafe { Library::new(&path) } {
            Ok(lib) => lib,
            Err(e) => {
                last = e.to_string();
                continue;
            }
        };
        macro_rules! sym {
            ($name:literal) => {
                *unsafe { lib.get($name) }.map_err(|e| e.to_string())?
            };
        }
        let api = Api {
            create: sym!(b"mpv_create\0"),
            initialize: sym!(b"mpv_initialize\0"),
            set_option_string: sym!(b"mpv_set_option_string\0"),
            set_property_string: sym!(b"mpv_set_property_string\0"),
            get_property_string: sym!(b"mpv_get_property_string\0"),
            free: sym!(b"mpv_free\0"),
            command: sym!(b"mpv_command\0"),
            observe_property: sym!(b"mpv_observe_property\0"),
            wait_event: sym!(b"mpv_wait_event\0"),
            terminate_destroy: sym!(b"mpv_terminate_destroy\0"),
            _lib: lib,
        };
        return Ok(api);
    }
    Err(format!(
        "libmpv was not found ({last}). Install mpv's library (libmpv) or Riflay, or set RIFLAY_LIBMPV to its path."
    ))
}

fn c(s: &str) -> CString {
    CString::new(s.replace('\0', "")).unwrap_or_default()
}

impl Mpv {
    pub fn new() -> Result<Mpv, String> {
        let api = Arc::new(load()?);
        let handle = unsafe { (api.create)() };
        if handle.is_null() {
            return Err("libmpv could not start.".into());
        }
        let mpv = Mpv { api, handle };
        // Sound only: no window, no video decoding, no terminal output, no config files of the user's mpv.
        for (k, v) in [
            ("vid", "no"),
            ("video", "no"),
            ("force-window", "no"),
            ("terminal", "no"),
            ("config", "no"),
            ("idle", "yes"),
            ("audio-display", "no"),
            ("ytdl", "no"),
            ("cache", "yes"),
            ("demuxer-max-bytes", "8MiB"),
            ("demuxer-max-back-bytes", "1MiB"),
            ("gapless-audio", "weak"),
        ] {
            unsafe { (mpv.api.set_option_string)(mpv.handle, c(k).as_ptr(), c(v).as_ptr()) };
        }
        if unsafe { (mpv.api.initialize)(mpv.handle) } < 0 {
            return Err("libmpv could not start.".into());
        }
        for (id, name, format) in [
            (1, "pause", FORMAT_FLAG),
            (2, "duration", FORMAT_DOUBLE),
            (3, "paused-for-cache", FORMAT_FLAG),
        ] {
            unsafe { (mpv.api.observe_property)(mpv.handle, id, c(name).as_ptr(), format) };
        }
        Ok(mpv)
    }

    pub fn command(&self, args: &[&str]) {
        let owned: Vec<CString> = args.iter().map(|a| c(a)).collect();
        let mut ptrs: Vec<*const c_char> = owned.iter().map(|a| a.as_ptr()).collect();
        ptrs.push(std::ptr::null());
        unsafe { (self.api.command)(self.handle, ptrs.as_mut_ptr()) };
    }

    pub fn set(&self, name: &str, value: &str) {
        unsafe { (self.api.set_property_string)(self.handle, c(name).as_ptr(), c(value).as_ptr()) };
    }

    pub fn get(&self, name: &str) -> Option<String> {
        let raw = unsafe { (self.api.get_property_string)(self.handle, c(name).as_ptr()) };
        if raw.is_null() {
            return None;
        }
        let value = unsafe { CStr::from_ptr(raw) }
            .to_string_lossy()
            .into_owned();
        unsafe { (self.api.free)(raw as *mut c_void) };
        Some(value)
    }

    /// The next event, waiting up to [timeout] seconds; None when nothing came.
    pub fn next_event(&self, timeout: f64) -> Option<Event> {
        let raw = unsafe { (self.api.wait_event)(self.handle, timeout) };
        if raw.is_null() {
            return None;
        }
        let e = unsafe { &*raw };
        match e.event_id {
            EVENT_SHUTDOWN => Some(Event::Shutdown),
            EVENT_FILE_LOADED => Some(Event::Loaded),
            EVENT_PLAYBACK_RESTART => Some(Event::Restarted),
            EVENT_END_FILE if !e.data.is_null() => {
                let end = unsafe { &*(e.data as *const RawEndFile) };
                Some(Event::Ended {
                    eof: end.reason == END_EOF,
                    error: end.reason == END_ERROR,
                })
            }
            EVENT_PROPERTY_CHANGE if !e.data.is_null() => {
                let p = unsafe { &*(e.data as *const RawProperty) };
                if p.data.is_null() {
                    return None;
                }
                let name = unsafe { CStr::from_ptr(p.name) }.to_string_lossy();
                match (name.as_ref(), p.format) {
                    ("pause", FORMAT_FLAG) => {
                        Some(Event::Paused(unsafe { *(p.data as *const c_int) } != 0))
                    }
                    ("paused-for-cache", FORMAT_FLAG) => {
                        Some(Event::Buffering(unsafe { *(p.data as *const c_int) } != 0))
                    }
                    ("duration", FORMAT_DOUBLE) => {
                        Some(Event::Duration(unsafe { *(p.data as *const f64) }))
                    }
                    _ => None,
                }
            }
            _ => None,
        }
    }
}

impl Drop for Mpv {
    fn drop(&mut self) {
        unsafe { (self.api.terminate_destroy)(self.handle) };
    }
}
