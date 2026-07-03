use std::sync::{
    atomic::{AtomicBool, AtomicU64, Ordering},
    Arc, Mutex,
};
use std::thread;
use std::time::Duration;
use std::collections::VecDeque;

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{BufferSize, SampleFormat, StreamConfig};

use crate::audio::dsp::{self, StreamDecoder};

// Thread-safe ring buffer / FIFO used to bridge the decode thread and the cpal
// hardware callback thread.
pub struct AudioBuffer {
    data: Mutex<VecDeque<f32>>,
    capacity: usize,
}

impl AudioBuffer {
    pub fn new(capacity: usize) -> Self {
        Self {
            data: Mutex::new(VecDeque::with_capacity(capacity)),
            capacity,
        }
    }

    /// Push samples, blocking (backpressure) until there is room. Aborts early (discarding
    /// the block) if `stop_flag` becomes set, so the decode thread can always be joined even
    /// when the output stream is paused and therefore not draining the buffer.
    pub fn push(&self, samples: &[f32], stop_flag: &AtomicBool) {
        let mut queue = self.data.lock().unwrap_or_else(|e| e.into_inner());
        while queue.len() + samples.len() > self.capacity {
            drop(queue);
            if stop_flag.load(Ordering::SeqCst) {
                return;
            }
            thread::sleep(Duration::from_millis(5));
            queue = self.data.lock().unwrap_or_else(|e| e.into_inner());
        }
        queue.extend(samples.iter().cloned());
    }

    pub fn pop(&self, out: &mut [f32]) -> usize {
        let mut queue = self.data.lock().unwrap_or_else(|e| e.into_inner());
        let len = out.len().min(queue.len());
        for i in 0..len {
            out[i] = queue.pop_front().unwrap_or(0.0);
        }
        len
    }

    pub fn clear(&self) {
        self.data.lock().unwrap_or_else(|e| e.into_inner()).clear();
    }

    pub fn len(&self) -> usize {
        self.data.lock().unwrap_or_else(|e| e.into_inner()).len()
    }
}

// cpal streams are not `Send` on Android (oboe), but we need to control them from
// the FFI thread. This wrapper asserts `Send` + `Sync`; cpal/oboe streams are safe
// to pause/resume/drop from a different thread.
pub struct SendStream(pub cpal::Stream);
unsafe impl Send for SendStream {}
unsafe impl Sync for SendStream {}

struct PlayerState {
    thread_handle: Option<thread::JoinHandle<()>>,
    stream: Option<SendStream>,
    buffer: Option<Arc<AudioBuffer>>,
    stop_flag: Arc<AtomicBool>,
    seek_request: Arc<Mutex<Option<f64>>>,
    frames_played: Arc<AtomicU64>,
    sample_rate: u32,
    channels: u32,
    volume: Arc<Mutex<f32>>,
    pitch: Arc<Mutex<f64>>,
    algo: Arc<Mutex<String>>,
    loudness_normalization_gain: Arc<Mutex<f32>>,
}

lazy_static::lazy_static! {
    static ref GLOBAL_PLAYER: Mutex<PlayerState> = Mutex::new(PlayerState {
        thread_handle: None,
        stream: None,
        buffer: None,
        stop_flag: Arc::new(AtomicBool::new(false)),
        seek_request: Arc::new(Mutex::new(None)),
        frames_played: Arc::new(AtomicU64::new(0)),
        sample_rate: 44100,
        channels: 2,
        volume: Arc::new(Mutex::new(0.8)),
        pitch: Arc::new(Mutex::new(0.0)),
        algo: Arc::new(Mutex::new("wsola".to_string())),
        loudness_normalization_gain: Arc::new(Mutex::new(1.0)),
    });
}

fn err_fn(err: cpal::StreamError) {
    eprintln!("Audio output stream error: {}", err);
}

/// Negotiate an output config, preferring f32 at the device's default rate/channels so we
/// can feed the callback without per-callback allocation. Returns the live stream plus the
/// negotiated sample rate, channel count and the shared ring buffer.
fn build_output(
    frames_played: Arc<AtomicU64>,
) -> Result<(SendStream, u32, u32, Arc<AudioBuffer>), String> {
    let host = cpal::default_host();
    let device = host
        .default_output_device()
        .ok_or_else(|| "No default audio output device found".to_string())?;

    let default_cfg = device.default_output_config().map_err(|e| e.to_string())?;
    let want_rate = default_cfg.sample_rate();
    let want_ch = default_cfg.channels();
    let default_fmt = default_cfg.sample_format();

    // Prefer an f32 config (zero-allocation callback). Fall back to the device default format.
    let sample_format = if default_fmt == SampleFormat::F32 {
        SampleFormat::F32
    } else {
        let mut found_f32 = false;
        if let Ok(supported) = device.supported_output_configs() {
            for cfg in supported {
                if cfg.channels() == want_ch
                    && cfg.sample_format() == SampleFormat::F32
                    && cfg.min_sample_rate() <= want_rate
                    && cfg.max_sample_rate() >= want_rate
                {
                    found_f32 = true;
                    break;
                }
            }
        }
        if found_f32 {
            SampleFormat::F32
        } else {
            default_fmt
        }
    };

    let config = StreamConfig {
        channels: want_ch,
        sample_rate: want_rate,
        buffer_size: BufferSize::Default,
    };

    let sample_rate = config.sample_rate.0;
    let channels = config.channels as u32;
    let ch = channels as usize;

    // ~2 seconds of buffering: enough to absorb decode hiccups, low enough for responsive seek.
    let capacity = (sample_rate as usize * ch * 2).max(8192);
    let buffer = Arc::new(AudioBuffer::new(capacity));

    let stream = match sample_format {
        SampleFormat::F32 => {
            let buf = buffer.clone();
            let fp = frames_played.clone();
            device
                .build_output_stream(
                    &config,
                    move |data: &mut [f32], _| {
                        let n = buf.pop(data);
                        for i in n..data.len() {
                            data[i] = 0.0;
                        }
                        if ch > 0 {
                            fp.fetch_add((n / ch) as u64, Ordering::Relaxed);
                        }
                    },
                    err_fn,
                    None,
                )
                .map_err(|e| e.to_string())?
        }
        SampleFormat::I16 => {
            let buf = buffer.clone();
            let fp = frames_played.clone();
            device
                .build_output_stream(
                    &config,
                    move |data: &mut [i16], _| {
                        let mut tmp = vec![0.0f32; data.len()];
                        let n = buf.pop(&mut tmp);
                        for i in 0..n {
                            data[i] = (tmp[i].clamp(-1.0, 1.0) * 32767.0) as i16;
                        }
                        for i in n..data.len() {
                            data[i] = 0;
                        }
                        if ch > 0 {
                            fp.fetch_add((n / ch) as u64, Ordering::Relaxed);
                        }
                    },
                    err_fn,
                    None,
                )
                .map_err(|e| e.to_string())?
        }
        SampleFormat::U16 => {
            let buf = buffer.clone();
            let fp = frames_played.clone();
            device
                .build_output_stream(
                    &config,
                    move |data: &mut [u16], _| {
                        let mut tmp = vec![0.0f32; data.len()];
                        let n = buf.pop(&mut tmp);
                        for i in 0..n {
                            data[i] = ((tmp[i].clamp(-1.0, 1.0) * 0.5 + 0.5) * 65535.0) as u16;
                        }
                        for i in n..data.len() {
                            data[i] = 0;
                        }
                        if ch > 0 {
                            fp.fetch_add((n / ch) as u64, Ordering::Relaxed);
                        }
                    },
                    err_fn,
                    None,
                )
                .map_err(|e| e.to_string())?
        }
        SampleFormat::I32 => {
            let buf = buffer.clone();
            let fp = frames_played.clone();
            device
                .build_output_stream(
                    &config,
                    move |data: &mut [i32], _| {
                        let mut tmp = vec![0.0f32; data.len()];
                        let n = buf.pop(&mut tmp);
                        for i in 0..n {
                            data[i] = (tmp[i].clamp(-1.0, 1.0) * 2147483647.0) as i32;
                        }
                        for i in n..data.len() {
                            data[i] = 0;
                        }
                        if ch > 0 {
                            fp.fetch_add((n / ch) as u64, Ordering::Relaxed);
                        }
                    },
                    err_fn,
                    None,
                )
                .map_err(|e| e.to_string())?
        }
        SampleFormat::U8 => {
            let buf = buffer.clone();
            let fp = frames_played.clone();
            device
                .build_output_stream(
                    &config,
                    move |data: &mut [u8], _| {
                        let mut tmp = vec![0.0f32; data.len()];
                        let n = buf.pop(&mut tmp);
                        for i in 0..n {
                            data[i] = ((tmp[i].clamp(-1.0, 1.0) * 0.5 + 0.5) * 255.0) as u8;
                        }
                        for i in n..data.len() {
                            data[i] = 0;
                        }
                        if ch > 0 {
                            fp.fetch_add((n / ch) as u64, Ordering::Relaxed);
                        }
                    },
                    err_fn,
                    None,
                )
                .map_err(|e| e.to_string())?
        }
        SampleFormat::F64 => {
            let buf = buffer.clone();
            let fp = frames_played.clone();
            device
                .build_output_stream(
                    &config,
                    move |data: &mut [f64], _| {
                        let mut tmp = vec![0.0f32; data.len()];
                        let n = buf.pop(&mut tmp);
                        for i in 0..n {
                            data[i] = tmp[i] as f64;
                        }
                        for i in n..data.len() {
                            data[i] = 0.0;
                        }
                        if ch > 0 {
                            fp.fetch_add((n / ch) as u64, Ordering::Relaxed);
                        }
                    },
                    err_fn,
                    None,
                )
                .map_err(|e| e.to_string())?
        }
        other => {
            return Err(format!("Unsupported output sample format: {:?}", other));
        }
    };

    stream.play().map_err(|e| e.to_string())?;
    Ok((SendStream(stream), sample_rate, channels, buffer))
}

/// Start streaming playback of `path` with the given DSP parameters.
pub fn start_playback(
    path: String,
    vol: f32,
    pitch_val: f64,
    pitch_algo: String,
    normalization_gain: f32,
) -> Result<(), String> {
    let mut state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());

    // Stop any existing playback.
    state.stop_flag.store(true, Ordering::SeqCst);
    if let Some(handle) = state.thread_handle.take() {
        let _ = handle.join();
    }
    // Drop the old stream first so the hardware callback stops touching the old buffer.
    state.stream = None;
    state.buffer = None;

    let stop_flag = Arc::new(AtomicBool::new(false));
    let seek_request = Arc::new(Mutex::new(None));
    let frames_played = Arc::new(AtomicU64::new(0));
    let volume = Arc::new(Mutex::new(vol));
    let pitch = Arc::new(Mutex::new(pitch_val));
    let algo = Arc::new(Mutex::new(pitch_algo));
    let norm_gain = Arc::new(Mutex::new(normalization_gain));

    let (stream, sample_rate, channels, buffer) = build_output(frames_played.clone())?;

    state.stream = Some(stream);
    state.buffer = Some(buffer.clone());
    state.sample_rate = sample_rate;
    state.channels = channels;
    state.stop_flag = stop_flag.clone();
    state.seek_request = seek_request.clone();
    state.frames_played = frames_played.clone();
    state.volume = volume.clone();
    state.pitch = pitch.clone();
    state.algo = algo.clone();
    state.loudness_normalization_gain = norm_gain.clone();

    let handle = thread::spawn(move || {
        let mut decoder = match StreamDecoder::new(&path, channels, sample_rate) {
            Ok(d) => d,
            Err(e) => {
                eprintln!("Failed to open decoder for {}: {}", path, e);
                return;
            }
        };

        let block_frames = 2048usize;

        loop {
            if stop_flag.load(Ordering::SeqCst) {
                break;
            }

            // Handle seek requests.
            {
                let mut req = seek_request.lock().unwrap_or_else(|e| e.into_inner());
                if let Some(sec) = req.take() {
                    if let Err(e) = decoder.seek(sec) {
                        eprintln!("Seek error: {}", e);
                    }
                    buffer.clear();
                    frames_played.store((sec * sample_rate as f64).round() as u64, Ordering::SeqCst);
                }
            }

            let mut block = match decoder.read_block(block_frames) {
                Ok(b) => b,
                Err(e) => {
                    eprintln!("Decode error: {}", e);
                    break;
                }
            };

            if block.is_empty() {
                // End of stream: let the hardware drain whatever is still buffered.
                while buffer.len() > 0 && !stop_flag.load(Ordering::SeqCst) {
                    thread::sleep(Duration::from_millis(20));
                }
                break;
            }

            // 1. Master volume * loudness normalization gain.
            let total_gain = *volume.lock().unwrap_or_else(|e| e.into_inner()) * *norm_gain.lock().unwrap_or_else(|e| e.into_inner());
            if (total_gain - 1.0).abs() > 0.001 {
                for sample in block.iter_mut() {
                    *sample *= total_gain;
                }
            }

            // 2. Pitch shift (block-based; only meaningful for stereo output).
            let current_pitch = *pitch.lock().unwrap_or_else(|e| e.into_inner());
            if current_pitch.abs() > 0.01 && channels == 2 {
                let current_algo = algo.lock().unwrap_or_else(|e| e.into_inner()).clone();
                let pitch_factor = 2.0f64.powf(current_pitch / 12.0);
                let processed = match current_algo.as_str() {
                    "resample" => dsp::pitch_shift_resample(&block, pitch_factor),
                    "ola" => dsp::pitch_shift_ola(&block, pitch_factor),
                    _ => dsp::pitch_shift_wsola(&block, pitch_factor),
                };
                buffer.push(&processed, &stop_flag);
            } else {
                buffer.push(&block, &stop_flag);
            }
        }
    });

    state.thread_handle = Some(handle);
    Ok(())
}

pub fn pause_playback() -> Result<(), String> {
    let state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(s) = &state.stream {
        s.0.pause().map_err(|e| e.to_string())?;
    }
    Ok(())
}

pub fn resume_playback() -> Result<(), String> {
    let state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(s) = &state.stream {
        s.0.play().map_err(|e| e.to_string())?;
    }
    Ok(())
}

pub fn seek_playback(secs: f64) -> Result<(), String> {
    let state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    // Clear buffered audio immediately so resume/seek is responsive and stale samples
    // are never played. The decode thread will refill from the requested position.
    if let Some(b) = &state.buffer {
        b.clear();
    }
    *state.seek_request.lock().unwrap_or_else(|e| e.into_inner()) = Some(secs);
    state
        .frames_played
        .store((secs * state.sample_rate as f64).round() as u64, Ordering::SeqCst);
    Ok(())
}

pub fn stop_playback() -> Result<(), String> {
    let mut state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    state.stop_flag.store(true, Ordering::SeqCst);
    if let Some(handle) = state.thread_handle.take() {
        let _ = handle.join();
    }
    state.stream = None;
    state.buffer = None;
    Ok(())
}

pub fn set_volume(vol: f32) -> Result<(), String> {
    let state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    *state.volume.lock().unwrap_or_else(|e| e.into_inner()) = vol;
    Ok(())
}

pub fn set_pitch(pitch_val: f64, pitch_algo: String) -> Result<(), String> {
    let state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    *state.pitch.lock().unwrap_or_else(|e| e.into_inner()) = pitch_val;
    *state.algo.lock().unwrap_or_else(|e| e.into_inner()) = pitch_algo;
    Ok(())
}

/// Current playback position in seconds, derived from samples actually consumed by the
/// hardware (not samples queued in the buffer), so it stays accurate regardless of
/// buffering or pitch shifting.
pub fn get_position() -> f64 {
    let state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    let frames = state.frames_played.load(Ordering::Relaxed);
    if state.sample_rate == 0 {
        0.0
    } else {
        frames as f64 / state.sample_rate as f64
    }
}
