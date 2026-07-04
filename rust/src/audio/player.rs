use std::collections::VecDeque;
use std::sync::{
    atomic::{AtomicBool, AtomicU64, Ordering},
    Arc, Mutex,
};
use std::thread;
use std::time::Duration;

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{BufferSize, SampleFormat, StreamConfig};

use crate::audio::dsp::{self, StreamDecoder};
use crate::audio::rubberband::RubberBandPitchShifter;

// Thread-safe ring buffer / FIFO used to bridge the decode thread and the cpal
// hardware callback thread.
pub struct AudioBuffer {
    data: Mutex<VecDeque<f32>>,
    capacity: usize,
}

#[derive(Clone, Debug)]
struct AudioQualitySettings {
    peak_protection_enabled: bool,
    dither_enabled: bool,
    rubberband_window: String,
    rubberband_formant_preserved: bool,
    resampler_quality: String,
}

impl Default for AudioQualitySettings {
    fn default() -> Self {
        Self {
            peak_protection_enabled: true,
            dither_enabled: true,
            rubberband_window: "latency".to_string(),
            rubberband_formant_preserved: false,
            resampler_quality: "standard".to_string(),
        }
    }
}

#[derive(Clone, Debug)]
pub struct AudioOutputInfo {
    pub device_name: String,
    pub sample_rate: u32,
    pub channels: u32,
    pub sample_format: String,
    pub buffer_size: String,
    pub output_buffer_ms: u32,
    pub underruns: u64,
    pub clipped_samples: u64,
    pub peak_db: f64,
}

#[derive(Clone, Debug)]
struct OutputDeviceInfo {
    device_name: String,
    sample_rate: u32,
    channels: u32,
    sample_format: String,
    buffer_size: String,
}

impl Default for OutputDeviceInfo {
    fn default() -> Self {
        Self {
            device_name: "未连接".to_string(),
            sample_rate: 0,
            channels: 0,
            sample_format: "unknown".to_string(),
            buffer_size: "unknown".to_string(),
        }
    }
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
    output_buffer_ms: u32,
    quality_settings: Arc<Mutex<AudioQualitySettings>>,
    output_info: Arc<Mutex<OutputDeviceInfo>>,
    underrun_count: Arc<AtomicU64>,
    clipped_sample_count: Arc<AtomicU64>,
    peak_bits: Arc<AtomicU64>,
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
        algo: Arc::new(Mutex::new("rubberband".to_string())),
        loudness_normalization_gain: Arc::new(Mutex::new(1.0)),
        output_buffer_ms: 240,
        quality_settings: Arc::new(Mutex::new(AudioQualitySettings::default())),
        output_info: Arc::new(Mutex::new(OutputDeviceInfo::default())),
        underrun_count: Arc::new(AtomicU64::new(0)),
        clipped_sample_count: Arc::new(AtomicU64::new(0)),
        peak_bits: Arc::new(AtomicU64::new(0.0f64.to_bits())),
    });
}

fn err_fn(err: cpal::StreamError) {
    eprintln!("Audio output stream error: {}", err);
}

struct TpdfDither {
    state: u64,
}

impl TpdfDither {
    fn new(seed: u64) -> Self {
        Self { state: seed }
    }

    fn apply(&mut self, sample: f32, lsb: f32) -> f32 {
        sample + ((self.next_unit() - self.next_unit()) * lsb as f64) as f32
    }

    fn next_unit(&mut self) -> f64 {
        self.state = self
            .state
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        ((self.state >> 11) as f64) * (1.0 / ((1u64 << 53) as f64))
    }
}

fn apply_post_dsp_protection(
    samples: &mut [f32],
    enabled: bool,
    clipped_sample_count: &AtomicU64,
    peak_bits: &AtomicU64,
) {
    if samples.is_empty() {
        return;
    }

    let peak = samples
        .iter()
        .fold(0.0f32, |acc, sample| acc.max(sample.abs()));
    update_atomic_peak(peak_bits, peak as f64);

    if !enabled || peak <= 1.0 {
        return;
    }

    const TARGET_PEAK: f32 = 0.891_250_9;
    let gain = TARGET_PEAK / peak;
    let mut clipped = 0u64;
    for sample in samples {
        if sample.abs() > 1.0 {
            clipped += 1;
        }
        *sample = soft_limit(*sample * gain);
    }
    clipped_sample_count.fetch_add(clipped, Ordering::Relaxed);
}

fn soft_limit(sample: f32) -> f32 {
    if sample.abs() <= 1.0 {
        sample
    } else {
        sample.tanh()
    }
}

fn update_atomic_peak(peak_bits: &AtomicU64, peak: f64) {
    let mut current = peak_bits.load(Ordering::Relaxed);
    loop {
        let current_peak = f64::from_bits(current);
        if peak <= current_peak {
            break;
        }
        match peak_bits.compare_exchange_weak(
            current,
            peak.to_bits(),
            Ordering::Relaxed,
            Ordering::Relaxed,
        ) {
            Ok(_) => break,
            Err(next) => current = next,
        }
    }
}

/// Negotiate an output config, preferring f32 at the device's default rate/channels so we
/// can feed the callback without per-callback allocation. Returns the live stream plus the
/// negotiated sample rate, channel count and the shared ring buffer.
fn build_output(
    frames_played: Arc<AtomicU64>,
    underrun_count: Arc<AtomicU64>,
    quality_settings: Arc<Mutex<AudioQualitySettings>>,
    output_buffer_ms: u32,
) -> Result<(SendStream, OutputDeviceInfo, Arc<AudioBuffer>), String> {
    let host = cpal::default_host();
    let device = host
        .default_output_device()
        .ok_or_else(|| "No default audio output device found".to_string())?;

    let default_cfg = device.default_output_config().map_err(|e| e.to_string())?;
    let device_name = device
        .name()
        .unwrap_or_else(|_| "Unknown output".to_string());
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

    let buffer_ms = output_buffer_ms.clamp(60, 1500) as usize;
    let capacity = ((sample_rate as usize * ch * buffer_ms) / 1000).max(8192);
    let buffer = Arc::new(AudioBuffer::new(capacity));
    let output_info = OutputDeviceInfo {
        device_name,
        sample_rate,
        channels,
        sample_format: format!("{:?}", sample_format),
        buffer_size: "Default".to_string(),
    };

    let stream = match sample_format {
        SampleFormat::F32 => {
            let buf = buffer.clone();
            let fp = frames_played.clone();
            let uc = underrun_count.clone();
            device
                .build_output_stream(
                    &config,
                    move |data: &mut [f32], _| {
                        let n = buf.pop(data);
                        if n < data.len() {
                            uc.fetch_add(1, Ordering::Relaxed);
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
        SampleFormat::I16 => {
            let buf = buffer.clone();
            let fp = frames_played.clone();
            let uc = underrun_count.clone();
            let qs = quality_settings.clone();
            let mut dither = TpdfDither::new(0xA17E_51A3_59C3_0D42);
            device
                .build_output_stream(
                    &config,
                    move |data: &mut [i16], _| {
                        let mut tmp = vec![0.0f32; data.len()];
                        let n = buf.pop(&mut tmp);
                        if n < data.len() {
                            uc.fetch_add(1, Ordering::Relaxed);
                        }
                        let dither_enabled =
                            qs.lock().unwrap_or_else(|e| e.into_inner()).dither_enabled;
                        for i in 0..n {
                            let v = if dither_enabled {
                                dither.apply(tmp[i], 1.0 / 32768.0)
                            } else {
                                tmp[i]
                            };
                            data[i] = (v.clamp(-1.0, 1.0) * 32767.0) as i16;
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
            let uc = underrun_count.clone();
            let qs = quality_settings.clone();
            let mut dither = TpdfDither::new(0x9E37_79B9_7F4A_7C15);
            device
                .build_output_stream(
                    &config,
                    move |data: &mut [u16], _| {
                        let mut tmp = vec![0.0f32; data.len()];
                        let n = buf.pop(&mut tmp);
                        if n < data.len() {
                            uc.fetch_add(1, Ordering::Relaxed);
                        }
                        let dither_enabled =
                            qs.lock().unwrap_or_else(|e| e.into_inner()).dither_enabled;
                        for i in 0..n {
                            let v = if dither_enabled {
                                dither.apply(tmp[i], 1.0 / 65536.0)
                            } else {
                                tmp[i]
                            };
                            data[i] = ((v.clamp(-1.0, 1.0) * 0.5 + 0.5) * 65535.0) as u16;
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
            let uc = underrun_count.clone();
            let qs = quality_settings.clone();
            let mut dither = TpdfDither::new(0xD1B5_4A32_D192_ED03);
            device
                .build_output_stream(
                    &config,
                    move |data: &mut [i32], _| {
                        let mut tmp = vec![0.0f32; data.len()];
                        let n = buf.pop(&mut tmp);
                        if n < data.len() {
                            uc.fetch_add(1, Ordering::Relaxed);
                        }
                        let dither_enabled =
                            qs.lock().unwrap_or_else(|e| e.into_inner()).dither_enabled;
                        for i in 0..n {
                            let v = if dither_enabled {
                                dither.apply(tmp[i], 1.0 / 2_147_483_648.0)
                            } else {
                                tmp[i]
                            };
                            data[i] = (v.clamp(-1.0, 1.0) * 2147483647.0) as i32;
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
            let uc = underrun_count.clone();
            let qs = quality_settings.clone();
            let mut dither = TpdfDither::new(0x94D0_49BB_1331_11EB);
            device
                .build_output_stream(
                    &config,
                    move |data: &mut [u8], _| {
                        let mut tmp = vec![0.0f32; data.len()];
                        let n = buf.pop(&mut tmp);
                        if n < data.len() {
                            uc.fetch_add(1, Ordering::Relaxed);
                        }
                        let dither_enabled =
                            qs.lock().unwrap_or_else(|e| e.into_inner()).dither_enabled;
                        for i in 0..n {
                            let v = if dither_enabled {
                                dither.apply(tmp[i], 1.0 / 256.0)
                            } else {
                                tmp[i]
                            };
                            data[i] = ((v.clamp(-1.0, 1.0) * 0.5 + 0.5) * 255.0) as u8;
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
            let uc = underrun_count.clone();
            device
                .build_output_stream(
                    &config,
                    move |data: &mut [f64], _| {
                        let mut tmp = vec![0.0f32; data.len()];
                        let n = buf.pop(&mut tmp);
                        if n < data.len() {
                            uc.fetch_add(1, Ordering::Relaxed);
                        }
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
    Ok((SendStream(stream), output_info, buffer))
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
    let output_buffer_ms = state.output_buffer_ms;
    let quality_settings = state.quality_settings.clone();
    let underrun_count = Arc::new(AtomicU64::new(0));
    let clipped_sample_count = Arc::new(AtomicU64::new(0));
    let peak_bits = Arc::new(AtomicU64::new(0.0f64.to_bits()));

    let (stream, output_info, buffer) = build_output(
        frames_played.clone(),
        underrun_count.clone(),
        quality_settings.clone(),
        output_buffer_ms,
    )?;
    let sample_rate = output_info.sample_rate;
    let channels = output_info.channels;

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
    state.output_info = Arc::new(Mutex::new(output_info));
    state.underrun_count = underrun_count.clone();
    state.clipped_sample_count = clipped_sample_count.clone();
    state.peak_bits = peak_bits.clone();

    let handle = thread::spawn(move || {
        let initial_quality = quality_settings
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone();
        let mut decoder = match StreamDecoder::new(
            &path,
            channels,
            sample_rate,
            &initial_quality.resampler_quality,
        ) {
            Ok(d) => d,
            Err(e) => {
                eprintln!("Failed to open decoder for {}: {}", path, e);
                return;
            }
        };

        let block_frames = 2048usize;
        let mut rubberband_shifter: Option<RubberBandPitchShifter> = None;

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
                    if let Some(shifter) = &mut rubberband_shifter {
                        shifter.reset();
                    }
                    buffer.clear();
                    frames_played
                        .store((sec * sample_rate as f64).round() as u64, Ordering::SeqCst);
                }
            }

            let current_quality = quality_settings
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .clone();

            let mut block = match decoder.read_block(block_frames) {
                Ok(b) => b,
                Err(e) => {
                    eprintln!("Decode error: {}", e);
                    break;
                }
            };

            if block.is_empty() {
                if let Some(shifter) = &mut rubberband_shifter {
                    let tail = shifter.finish();
                    if !tail.is_empty() {
                        buffer.push(&tail, &stop_flag);
                    }
                }
                // End of stream: let the hardware drain whatever is still buffered.
                while buffer.len() > 0 && !stop_flag.load(Ordering::SeqCst) {
                    thread::sleep(Duration::from_millis(20));
                }
                break;
            }

            // 1. Master volume * loudness normalization gain.
            let total_gain = *volume.lock().unwrap_or_else(|e| e.into_inner())
                * *norm_gain.lock().unwrap_or_else(|e| e.into_inner());
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
                    "wsola" => dsp::pitch_shift_wsola(&block, pitch_factor),
                    _ => {
                        if rubberband_shifter.is_none() {
                            match RubberBandPitchShifter::new(
                                sample_rate,
                                channels,
                                pitch_factor,
                                &current_quality.rubberband_window,
                                current_quality.rubberband_formant_preserved,
                            ) {
                                Ok(shifter) => {
                                    rubberband_shifter = Some(shifter);
                                }
                                Err(e) => {
                                    eprintln!("Rubber Band initialization failed: {}", e);
                                }
                            }
                        }
                        if let Some(shifter) = &mut rubberband_shifter {
                            shifter.set_formant_preserved(
                                current_quality.rubberband_formant_preserved,
                            );
                            shifter.process(&block, pitch_factor)
                        } else {
                            block.clone()
                        }
                    }
                };
                if !processed.is_empty() {
                    let mut protected = processed;
                    apply_post_dsp_protection(
                        &mut protected,
                        current_quality.peak_protection_enabled,
                        &clipped_sample_count,
                        &peak_bits,
                    );
                    buffer.push(&protected, &stop_flag);
                }
            } else {
                apply_post_dsp_protection(
                    &mut block,
                    current_quality.peak_protection_enabled,
                    &clipped_sample_count,
                    &peak_bits,
                );
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
    state.frames_played.store(
        (secs * state.sample_rate as f64).round() as u64,
        Ordering::SeqCst,
    );
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

pub fn set_output_buffer_ms(ms: i32) -> Result<(), String> {
    let mut state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    state.output_buffer_ms = ms.clamp(60, 1500) as u32;
    Ok(())
}

pub fn set_quality_settings(
    peak_protection_enabled: bool,
    dither_enabled: bool,
    rubberband_window: String,
    rubberband_formant_preserved: bool,
    resampler_quality: String,
) -> Result<(), String> {
    let state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    *state
        .quality_settings
        .lock()
        .unwrap_or_else(|e| e.into_inner()) = AudioQualitySettings {
        peak_protection_enabled,
        dither_enabled,
        rubberband_window: normalize_rubberband_window(&rubberband_window),
        rubberband_formant_preserved,
        resampler_quality: normalize_resampler_quality(&resampler_quality),
    };
    Ok(())
}

pub fn get_output_info() -> AudioOutputInfo {
    let state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    let info = state
        .output_info
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .clone();
    let peak = f64::from_bits(state.peak_bits.load(Ordering::Relaxed));
    let peak_db = if peak > 0.0 {
        20.0 * peak.log10()
    } else {
        f64::NEG_INFINITY
    };

    AudioOutputInfo {
        device_name: info.device_name,
        sample_rate: info.sample_rate,
        channels: info.channels,
        sample_format: info.sample_format,
        buffer_size: info.buffer_size,
        output_buffer_ms: state.output_buffer_ms,
        underruns: state.underrun_count.load(Ordering::Relaxed),
        clipped_samples: state.clipped_sample_count.load(Ordering::Relaxed),
        peak_db,
    }
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

fn normalize_rubberband_window(value: &str) -> String {
    if value == "quality" {
        "quality".to_string()
    } else {
        "latency".to_string()
    }
}

fn normalize_resampler_quality(value: &str) -> String {
    if value == "high" {
        "high".to_string()
    } else {
        "standard".to_string()
    }
}
