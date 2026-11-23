//! The visualizer's levels for the standalone player. libmpv doesn't hand out the sound it plays, so ffmpeg decodes
//! the same song once more, to small mono samples, on a thread of its own, and each 50 ms of it becomes the levels of
//! [BANDS] bands (bass to treble, 0-100). The player shows the ones at its position. ffmpeg runs only while the
//! visualizer is on; a song's levels are a few tens of KB.

use std::io::Read;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;

pub const BANDS: usize = 32;
const RATE: usize = 22_050;
/// 50 ms of samples: one frame of levels.
const HOP: usize = RATE / 20;
const WINDOW: usize = 2048;

/// One song's levels, filled while ffmpeg decodes it (much faster than it plays).
pub struct Analysis {
    pub id: String,
    frames: Arc<Mutex<Vec<[u8; BANDS]>>>,
    stop: Arc<AtomicBool>,
}

impl Analysis {
    /// Starts decoding [source] (a file or a stream address) with [ffmpeg].
    pub fn start(id: String, source: String, ffmpeg: PathBuf) -> Analysis {
        let frames = Arc::new(Mutex::new(Vec::new()));
        let stop = Arc::new(AtomicBool::new(false));
        let (f, s) = (frames.clone(), stop.clone());
        thread::spawn(move || {
            let mut cmd = Command::new(ffmpeg);
            cmd.args([
                "-v", "quiet", "-nostdin", "-i", &source, "-vn", "-ac", "1", "-ar",
            ])
            .arg(RATE.to_string())
            .args(["-f", "s16le", "-"])
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
            #[cfg(windows)]
            {
                use std::os::windows::process::CommandExt;
                cmd.creation_flags(0x0800_0000); // no console window
            }
            let Ok(child) = cmd.spawn() else { return };
            analyse(child, &f, &s);
        });
        Analysis { id, frames, stop }
    }

    /// The levels at [ms] into the song, None until ffmpeg has got there.
    pub fn at(&self, ms: u64) -> Option<[u8; BANDS]> {
        let i = (ms / 50) as usize;
        self.frames.lock().ok()?.get(i).copied()
    }
}

impl Drop for Analysis {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
    }
}

fn analyse(mut child: Child, frames: &Mutex<Vec<[u8; BANDS]>>, stop: &AtomicBool) {
    let Some(mut out) = child.stdout.take() else {
        return;
    };
    let edges = band_edges();
    let hann: Vec<f32> = (0..WINDOW)
        .map(|i| 0.5 - 0.5 * (2.0 * std::f32::consts::PI * i as f32 / WINDOW as f32).cos())
        .collect();
    // The last WINDOW samples, the newest at the end.
    let mut ring = vec![0f32; WINDOW];
    let mut bytes = vec![0u8; HOP * 2];
    let mut re = vec![0f32; WINDOW];
    let mut im = vec![0f32; WINDOW];
    loop {
        if stop.load(Ordering::Relaxed) {
            break;
        }
        if out.read_exact(&mut bytes).is_err() {
            break;
        }
        ring.copy_within(HOP.., 0);
        for (i, pair) in bytes.as_chunks::<2>().0.iter().enumerate() {
            ring[WINDOW - HOP + i] = i16::from_le_bytes([pair[0], pair[1]]) as f32 / 32768.0;
        }
        for i in 0..WINDOW {
            re[i] = ring[i] * hann[i];
            im[i] = 0.0;
        }
        fft(&mut re, &mut im);
        let mut levels = [0u8; BANDS];
        for (b, level) in levels.iter_mut().enumerate() {
            let (lo, hi) = (edges[b], edges[b + 1]);
            let mut peak = 0f32;
            for k in lo..hi {
                peak = peak.max((re[k] * re[k] + im[k] * im[k]).sqrt());
            }
            // Full scale is about WINDOW / 4 for a Hann window; -60 dB to 0 dB is the bar's height.
            let db = 20.0 * (peak / (WINDOW as f32 / 4.0)).max(1e-6).log10();
            *level = (((db + 60.0) / 60.0).clamp(0.0, 1.0) * 100.0) as u8;
        }
        match frames.lock() {
            Ok(mut f) => f.push(levels),
            Err(_) => break,
        }
    }
    let _ = child.kill();
    let _ = child.wait();
}

/// FFT bins of each band, spaced as hearing is (log) from 40 Hz to 11 kHz; every band at least one bin.
fn band_edges() -> Vec<usize> {
    let bin = |hz: f32| (hz * WINDOW as f32 / RATE as f32) as usize;
    let (lo, hi) = (40f32, 11_000f32);
    let mut edges: Vec<usize> = (0..=BANDS)
        .map(|i| bin(lo * (hi / lo).powf(i as f32 / BANDS as f32)))
        .collect();
    for i in 1..edges.len() {
        if edges[i] <= edges[i - 1] {
            edges[i] = edges[i - 1] + 1;
        }
    }
    let last = WINDOW / 2;
    for e in edges.iter_mut() {
        *e = (*e).min(last);
    }
    edges
}

/// In-place radix-2 FFT; [re] and [im] are a power of two long.
fn fft(re: &mut [f32], im: &mut [f32]) {
    let n = re.len();
    let mut j = 0;
    for i in 1..n {
        let mut bit = n >> 1;
        while j & bit != 0 {
            j ^= bit;
            bit >>= 1;
        }
        j |= bit;
        if i < j {
            re.swap(i, j);
            im.swap(i, j);
        }
    }
    let mut len = 2;
    while len <= n {
        let angle = -2.0 * std::f32::consts::PI / len as f32;
        let (wr, wi) = (angle.cos(), angle.sin());
        for start in (0..n).step_by(len) {
            let (mut cr, mut ci) = (1f32, 0f32);
            for k in 0..len / 2 {
                let (a, b) = (start + k, start + k + len / 2);
                let tr = re[b] * cr - im[b] * ci;
                let ti = re[b] * ci + im[b] * cr;
                re[b] = re[a] - tr;
                im[b] = im[a] - ti;
                re[a] += tr;
                im[a] += ti;
                let next = cr * wr - ci * wi;
                ci = cr * wi + ci * wr;
                cr = next;
            }
        }
        len <<= 1;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_tone_lights_its_own_band() {
        let hz = 1000.0;
        let mut re: Vec<f32> = (0..WINDOW)
            .map(|i| (2.0 * std::f32::consts::PI * hz * i as f32 / RATE as f32).sin())
            .collect();
        let mut im = vec![0f32; WINDOW];
        fft(&mut re, &mut im);
        let mags: Vec<f32> = (0..WINDOW / 2)
            .map(|k| (re[k] * re[k] + im[k] * im[k]).sqrt())
            .collect();
        let top = mags
            .iter()
            .enumerate()
            .max_by(|a, b| a.1.total_cmp(b.1))
            .unwrap()
            .0;
        assert_eq!(top, (hz * WINDOW as f32 / RATE as f32).round() as usize);
        let edges = band_edges();
        assert_eq!(edges.len(), BANDS + 1);
        assert!(edges.windows(2).all(|w| w[0] < w[1]));
    }

    /// Decodes a 1 kHz tone with ffmpeg: RIFLAY_TUI_LIVE=1 cargo test decodes_a_tone -- --nocapture
    #[test]
    fn decodes_a_tone() {
        if std::env::var("RIFLAY_TUI_LIVE").is_err() {
            return;
        }
        let wav = std::env::temp_dir().join("riflay-tui-tone.wav");
        let made = Command::new("ffmpeg")
            .args(["-v", "quiet", "-y", "-f", "lavfi", "-i", "sine=frequency=1000:duration=2"])
            .arg(&wav)
            .status()
            .unwrap();
        assert!(made.success());
        let a = Analysis::start("t".into(), wav.to_string_lossy().into_owned(), "ffmpeg".into());
        std::thread::sleep(std::time::Duration::from_millis(1500));
        let frames = a.frames.lock().unwrap().len();
        let at = a.at(1000).unwrap();
        eprintln!("{frames} frames; at 1 s: {at:?}");
        assert!(frames >= 38);
        let loudest = at.iter().enumerate().max_by_key(|x| x.1).unwrap().0;
        let edges = band_edges();
        let bin = (1000.0 * WINDOW as f32 / RATE as f32) as usize;
        assert!(edges[loudest] <= bin && bin <= edges[loudest + 1]);
        let _ = std::fs::remove_file(wav);
    }
}