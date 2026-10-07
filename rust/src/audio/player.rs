use std::collections::VecDeque;
use std::sync::{
    atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering},
    Arc, Mutex,
};
use std::thread;
use std::time::{Duration, Instant};

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{
    BufferSize, SampleFormat, SampleRate, StreamConfig, SupportedBufferSize, SupportedStreamConfig,
    SupportedStreamConfigRange,
};

use crate::audio::dsp::{self, StreamDecoder};
use crate::audio::profiler;
use crate::audio::rubberband::RubberBandPitchShifter;
use crate::audio::sample::{finite_sample, OutputSample, TpdfDither};

// Thread-safe ring buffer / FIFO used to bridge the decode thread and the cpal
// hardware callback thread.
pub struct AudioBuffer {
    data: Mutex<VecDeque<f64>>,
    capacity: usize,
    len_samples: AtomicUsize,
}

#[derive(Clone, Debug)]
struct AudioQualitySettings {
    peak_protection_enabled: bool,
    dither_enabled: bool,
    rubberband_window: String,
    rubberband_formant_preserved: bool,
    rubberband_vocal_only_pitch: bool,
    resampler_quality: String,
}

impl Default for AudioQualitySettings {
    fn default() -> Self {
        Self {
            peak_protection_enabled: true,
            dither_enabled: true,
            rubberband_window: "latency".to_string(),
            rubberband_formant_preserved: false,
            rubberband_vocal_only_pitch: false,
            resampler_quality: "high".to_string(),
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
    pub output_latency_mode: String,
    pub output_buffer_ms: u32,
    pub queued_ms: u32,
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
    output_latency_mode: String,
}

#[derive(Clone)]
struct ProcessingParams {
    pitch: Arc<Mutex<f64>>,
    algo: Arc<Mutex<String>>,
    loudness_normalization_gain: Arc<Mutex<f32>>,
    quality_settings: Arc<Mutex<AudioQualitySettings>>,
    clipped_sample_count: Arc<AtomicU64>,
    peak_bits: Arc<AtomicU64>,
}

struct DecodePipeline {
    decoder: StreamDecoder,
    block_frames: usize,
    sample_rate: u32,
    channels: u32,
    params: ProcessingParams,
    pending_output: Vec<f64>,
}

/// Pitch-shifts the stereo center component while keeping the side component intact.
///
/// In a typical music mix, lead vocals are placed near the stereo center. Keeping the
/// side component untouched preserves stereo background material without requiring an
/// offline stem-separation model. Center-panned instruments are intentionally part of
/// the trade-off and may be shifted as well.
struct VocalOnlyPitchProcessor {
    shifter: RubberBandPitchShifter,
    pending_mid: VecDeque<f32>,
    pending_left_side: VecDeque<f32>,
    pending_right_side: VecDeque<f32>,
}

impl VocalOnlyPitchProcessor {
    fn new(
        sample_rate: u32,
        pitch_scale: f64,
        window: &str,
        preserve_formant: bool,
    ) -> Result<Self, String> {
        Ok(Self {
            shifter: RubberBandPitchShifter::new(
                sample_rate,
                1,
                pitch_scale,
                window,
                preserve_formant,
            )?,
            pending_mid: VecDeque::new(),
            pending_left_side: VecDeque::new(),
            pending_right_side: VecDeque::new(),
        })
    }

    fn reset(&mut self) {
        self.shifter.reset();
        self.pending_mid.clear();
        self.pending_left_side.clear();
        self.pending_right_side.clear();
    }

    fn set_formant_preserved(&mut self, preserve_formant: bool) {
        self.shifter.set_formant_preserved(preserve_formant);
    }

    fn process(&mut self, input: &[f32], pitch_scale: f64) -> Vec<f32> {
        if input.is_empty() {
            return Vec::new();
        }
        if input.len() % 2 != 0 {
            return input.to_vec();
        }

        let frames = input.len() / 2;
        let mut mid = Vec::with_capacity(frames);
        for frame in input.chunks_exact(2) {
            let center = (frame[0] + frame[1]) * 0.5;
            self.pending_mid.push_back(center);
            self.pending_left_side.push_back(frame[0] - center);
            self.pending_right_side.push_back(frame[1] - center);
            mid.push(center);
        }

        let shifted_mid = self.shifter.process(&mid, pitch_scale);
        self.combine_shifted(&shifted_mid)
    }

    fn finish(&mut self) -> Vec<f32> {
        let shifted_mid = self.shifter.finish();
        let mut output = self.combine_shifted(&shifted_mid);

        // If the live shifter cannot emit its final latency window, drain the
        // unmatched frames unchanged rather than truncating the song tail.
        while let (Some(mid), Some(left_side), Some(right_side)) = (
            self.pending_mid.pop_front(),
            self.pending_left_side.pop_front(),
            self.pending_right_side.pop_front(),
        ) {
            output.push(mid + left_side);
            output.push(mid + right_side);
        }
        output
    }

    fn combine_shifted(&mut self, shifted_mid: &[f32]) -> Vec<f32> {
        let frames = shifted_mid
            .len()
            .min(self.pending_mid.len())
            .min(self.pending_left_side.len())
            .min(self.pending_right_side.len());
        let mut output = Vec::with_capacity(frames * 2);
        for &mid in shifted_mid.iter().take(frames) {
            let _ = self.pending_mid.pop_front();
            let left_side = self.pending_left_side.pop_front().unwrap_or(0.0);
            let right_side = self.pending_right_side.pop_front().unwrap_or(0.0);
            output.push(mid + left_side);
            output.push(mid + right_side);
        }
        output
    }
}

impl Default for OutputDeviceInfo {
    fn default() -> Self {
        Self {
            device_name: "未连接".to_string(),
            sample_rate: 0,
            channels: 0,
            sample_format: "unknown".to_string(),
            buffer_size: "unknown".to_string(),
            output_latency_mode: "shared-default".to_string(),
        }
    }
}

impl DecodePipeline {
    fn new(
        path: &str,
        sample_rate: u32,
        channels: u32,
        params: ProcessingParams,
    ) -> Result<Self, String> {
        let _scope = profiler::scope("audio::player::DecodePipeline::new");
        let initial_quality = params
            .quality_settings
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone();
        let decoder = StreamDecoder::new(
            path,
            channels,
            sample_rate,
            &initial_quality.resampler_quality,
        )?;

        Ok(Self {
            decoder,
            block_frames: 2048,
            sample_rate,
            channels,
            params,
            pending_output: Vec::new(),
        })
    }

    fn seek(&mut self, secs: f64) -> Result<(), String> {
        let _scope = profiler::scope("audio::player::DecodePipeline::seek");
        self.decoder.seek(secs)?;
        self.pending_output.clear();
        Ok(())
    }

    fn next_block(
        &mut self,
        rubberband_shifter: &mut Option<RubberBandPitchShifter>,
        vocal_only_shifter: &mut Option<VocalOnlyPitchProcessor>,
    ) -> Result<Option<Vec<f64>>, String> {
        let _scope = profiler::scope("audio::player::DecodePipeline::next_block");
        if !self.pending_output.is_empty() {
            return Ok(Some(std::mem::take(&mut self.pending_output)));
        }
        let current_quality = self
            .params
            .quality_settings
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone();

        let current_pitch = *self.params.pitch.lock().unwrap_or_else(|e| e.into_inner());
        let current_algo = self
            .params
            .algo
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone();
        let vocal_only_active = current_pitch.abs() > 0.01
            && self.channels == 2
            && current_algo == "rubberband"
            && current_quality.rubberband_vocal_only_pitch;

        let mut block = self.decoder.read_block(self.block_frames)?;
        if block.is_empty() {
            if vocal_only_active {
                if let Some(shifter) = vocal_only_shifter {
                    let tail = shifter.finish();
                    if !tail.is_empty() {
                        let mut tail: Vec<f64> = tail.into_iter().map(f64::from).collect();
                        apply_post_dsp_protection(
                            &mut tail,
                            current_quality.peak_protection_enabled,
                            &self.params.clipped_sample_count,
                            &self.params.peak_bits,
                        );
                        return Ok(Some(tail));
                    }
                }
            } else if let Some(shifter) = rubberband_shifter {
                let tail = shifter.finish();
                if !tail.is_empty() {
                    let mut tail: Vec<f64> = tail.into_iter().map(f64::from).collect();
                    apply_post_dsp_protection(
                        &mut tail,
                        current_quality.peak_protection_enabled,
                        &self.params.clipped_sample_count,
                        &self.params.peak_bits,
                    );
                    return Ok(Some(tail));
                }
            }
            return Ok(None);
        }

        let total_gain = *self
            .params
            .loudness_normalization_gain
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        if total_gain != 1.0 {
            for sample in block.iter_mut() {
                *sample *= total_gain as f64;
            }
        }

        let mut processed = if current_pitch.abs() > 0.01 && self.channels == 2 {
            let _pitch_scope = profiler::scope("audio::player::DecodePipeline::pitch_shift");
            let pitch_factor = 2.0f64.powf(current_pitch / 12.0);
            let block: Vec<f32> = block.iter().map(|&s| s as f32).collect();
            let shifted = match current_algo.as_str() {
                "resample" => {
                    *rubberband_shifter = None;
                    *vocal_only_shifter = None;
                    dsp::pitch_shift_resample(&block, pitch_factor)
                }
                "ola" => {
                    *rubberband_shifter = None;
                    *vocal_only_shifter = None;
                    dsp::pitch_shift_ola(&block, pitch_factor)
                }
                "wsola" => {
                    *rubberband_shifter = None;
                    *vocal_only_shifter = None;
                    dsp::pitch_shift_wsola(&block, pitch_factor)
                }
                _ => {
                    if vocal_only_active {
                        *rubberband_shifter = None;
                        if vocal_only_shifter.is_none() {
                            match VocalOnlyPitchProcessor::new(
                                self.sample_rate,
                                pitch_factor,
                                &current_quality.rubberband_window,
                                current_quality.rubberband_formant_preserved,
                            ) {
                                Ok(shifter) => {
                                    *vocal_only_shifter = Some(shifter);
                                }
                                Err(e) => {
                                    eprintln!(
                                        "Rubber Band vocal-only initialization failed: {}",
                                        e
                                    );
                                }
                            }
                        }
                        if let Some(shifter) = vocal_only_shifter {
                            shifter.set_formant_preserved(
                                current_quality.rubberband_formant_preserved,
                            );
                            shifter.process(&block, pitch_factor)
                        } else {
                            block
                        }
                    } else {
                        *vocal_only_shifter = None;
                        if rubberband_shifter.is_none() {
                            match RubberBandPitchShifter::new(
                                self.sample_rate,
                                self.channels,
                                pitch_factor,
                                &current_quality.rubberband_window,
                                current_quality.rubberband_formant_preserved,
                            ) {
                                Ok(shifter) => {
                                    *rubberband_shifter = Some(shifter);
                                }
                                Err(e) => {
                                    eprintln!("Rubber Band initialization failed: {}", e);
                                }
                            }
                        }
                        if let Some(shifter) = rubberband_shifter {
                            shifter.set_formant_preserved(
                                current_quality.rubberband_formant_preserved,
                            );
                            shifter.process(&block, pitch_factor)
                        } else {
                            block
                        }
                    }
                }
            };
            shifted.into_iter().map(f64::from).collect()
        } else {
            *rubberband_shifter = None;
            *vocal_only_shifter = None;
            block
        };

        if processed.is_empty() {
            return Ok(Some(processed));
        }

        {
            let _protection_scope =
                profiler::scope("audio::player::DecodePipeline::post_dsp_protection");
            apply_post_dsp_protection(
                &mut processed,
                current_quality.peak_protection_enabled,
                &self.params.clipped_sample_count,
                &self.params.peak_bits,
            );
        }
        Ok(Some(processed))
    }
}

impl AudioBuffer {
    pub fn new(capacity: usize) -> Self {
        let _scope = profiler::scope("audio::player::AudioBuffer::new");
        Self {
            data: Mutex::new(VecDeque::with_capacity(capacity)),
            capacity,
            len_samples: AtomicUsize::new(0),
        }
    }

    /// Push samples, blocking (backpressure) until there is room. Aborts early (discarding
    /// the block) if `stop_flag` becomes set, so the decode thread can always be joined even
    /// when the output stream is paused and therefore not draining the buffer.
    pub fn push(&self, samples: &[f64], stop_flag: &AtomicBool) {
        let _scope = profiler::scope("audio::player::AudioBuffer::push");
        for chunk in samples.chunks(self.capacity.max(1)) {
            loop {
                if stop_flag.load(Ordering::SeqCst) {
                    return;
                }
                if self.try_push(chunk) {
                    break;
                }
                thread::sleep(Duration::from_millis(2));
            }
        }
    }

    pub fn try_push(&self, samples: &[f64]) -> bool {
        let _scope = profiler::scope("audio::player::AudioBuffer::try_push");
        let mut queue = self.data.lock().unwrap_or_else(|e| e.into_inner());
        if queue.len() + samples.len() > self.capacity {
            return false;
        }
        queue.extend(samples.iter().cloned());
        self.len_samples.fetch_add(samples.len(), Ordering::Relaxed);
        true
    }

    pub fn capacity(&self) -> usize {
        self.capacity
    }

    fn pop<T: OutputSample>(
        &self,
        out: &mut [T],
        channels: usize,
        volume: f64,
        dither: &mut TpdfDither,
        enabled: bool,
    ) -> usize {
        let _scope = profiler::scope("audio::player::AudioBuffer::pop");
        let mut queue = self.data.lock().unwrap_or_else(|e| e.into_inner());
        let len = out.len().min(queue.len()) / channels * channels;
        for i in 0..len {
            out[i] = T::encode(queue.pop_front().unwrap_or(0.0) * volume, dither, enabled);
        }
        if len > 0 {
            self.len_samples.fetch_sub(len, Ordering::Relaxed);
        }
        out[len..].fill(T::SILENCE);
        len
    }

    pub fn clear(&self) {
        let _scope = profiler::scope("audio::player::AudioBuffer::clear");
        let mut queue = self.data.lock().unwrap_or_else(|e| e.into_inner());
        queue.clear();
        self.len_samples.store(0, Ordering::Relaxed);
    }

    pub fn len(&self) -> usize {
        let _scope = profiler::scope("audio::player::AudioBuffer::len");
        self.len_samples.load(Ordering::Relaxed)
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
    stream_finished: Arc<AtomicBool>,
    sample_rate: u32,
    channels: u32,
    volume: Arc<Mutex<f32>>,
    pitch: Arc<Mutex<f64>>,
    algo: Arc<Mutex<String>>,
    loudness_normalization_gain: Arc<Mutex<f32>>,
    output_buffer_ms: u32,
    output_latency_mode: String,
    quality_settings: Arc<Mutex<AudioQualitySettings>>,
    output_info: Arc<Mutex<OutputDeviceInfo>>,
    underrun_count: Arc<AtomicU64>,
    clipped_sample_count: Arc<AtomicU64>,
    peak_bits: Arc<AtomicU64>,
    queue_headroom_history: VecDeque<(Instant, u32)>,
}

lazy_static::lazy_static! {
    static ref GLOBAL_PLAYER: Mutex<PlayerState> = Mutex::new(PlayerState {
        thread_handle: None,
        stream: None,
        buffer: None,
        stop_flag: Arc::new(AtomicBool::new(false)),
        seek_request: Arc::new(Mutex::new(None)),
        frames_played: Arc::new(AtomicU64::new(0)),
        stream_finished: Arc::new(AtomicBool::new(false)),
        sample_rate: 44100,
        channels: 2,
        volume: Arc::new(Mutex::new(0.8)),
        pitch: Arc::new(Mutex::new(0.0)),
        algo: Arc::new(Mutex::new("rubberband".to_string())),
        loudness_normalization_gain: Arc::new(Mutex::new(1.0)),
        output_buffer_ms: 240,
        output_latency_mode: "shared-default".to_string(),
        quality_settings: Arc::new(Mutex::new(AudioQualitySettings::default())),
        output_info: Arc::new(Mutex::new(OutputDeviceInfo::default())),
        underrun_count: Arc::new(AtomicU64::new(0)),
        clipped_sample_count: Arc::new(AtomicU64::new(0)),
        peak_bits: Arc::new(AtomicU64::new(0.0f64.to_bits())),
        queue_headroom_history: VecDeque::new(),
    });
}

fn err_fn(err: cpal::StreamError) {
    eprintln!("Audio output stream error: {}", err);
}

fn apply_post_dsp_protection(
    samples: &mut [f64],
    enabled: bool,
    clipped_sample_count: &AtomicU64,
    peak_bits: &AtomicU64,
) {
    let _scope = profiler::scope("audio::player::apply_post_dsp_protection");
    if samples.is_empty() {
        return;
    }

    for sample in samples.iter_mut() {
        *sample = finite_sample(*sample);
    }
    let peak = samples
        .iter()
        .fold(0.0f64, |acc, sample| acc.max(sample.abs()));
    update_atomic_peak(peak_bits, peak);

    if !enabled || peak <= 1.0 {
        return;
    }

    const TARGET_PEAK: f64 = 0.891_250_9;
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

fn soft_limit(sample: f64) -> f64 {
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

fn normalize_output_latency_mode(value: &str) -> String {
    match value {
        "shared-low-latency" | "shared-stable" => value.to_string(),
        _ => "shared-default".to_string(),
    }
}

fn select_output_buffer_size(
    latency_mode: &str,
    supported: &SupportedBufferSize,
) -> (BufferSize, String) {
    let target_frames = match normalize_output_latency_mode(latency_mode).as_str() {
        "shared-low-latency" => Some(256),
        "shared-stable" => Some(1024),
        _ => None,
    };

    let Some(target_frames) = target_frames else {
        return (BufferSize::Default, "Default".to_string());
    };

    match supported {
        SupportedBufferSize::Range { min, max } => {
            let frames = target_frames.clamp(*min, *max);
            (
                BufferSize::Fixed(frames),
                format!("Fixed({frames} frames, supported {min}-{max})"),
            )
        }
        SupportedBufferSize::Unknown => (
            BufferSize::Default,
            "Default (fixed unsupported)".to_string(),
        ),
    }
}

fn prefill_audio_buffer(
    pipeline: &mut DecodePipeline,
    rubberband_shifter: &mut Option<RubberBandPitchShifter>,
    vocal_only_shifter: &mut Option<VocalOnlyPitchProcessor>,
    buffer: &AudioBuffer,
    stop_flag: &AtomicBool,
    target_ms: u32,
) -> Result<(), String> {
    let _scope = profiler::scope("audio::player::prefill_audio_buffer");
    let requested_samples = ((pipeline.sample_rate as usize
        * pipeline.channels as usize
        * target_ms.clamp(20, 500) as usize)
        / 1000)
        .max((pipeline.channels as usize).max(1) * pipeline.block_frames);
    let target_samples = requested_samples.min(buffer.capacity().saturating_mul(2) / 3);

    while buffer.len() < target_samples && !stop_flag.load(Ordering::SeqCst) {
        let Some(block) = pipeline.next_block(rubberband_shifter, vocal_only_shifter)? else {
            break;
        };
        if block.is_empty() {
            continue;
        }
        if !buffer.try_push(&block) {
            pipeline.pending_output = block;
            break;
        }
    }
    Ok(())
}

fn current_output_volume(volume: &Arc<Mutex<f32>>) -> f64 {
    let value = *volume.lock().unwrap_or_else(|e| e.into_inner());
    finite_sample(value as f64).clamp(0.0, 1.0)
}

fn format_precision(format: SampleFormat) -> u32 {
    match format {
        SampleFormat::F64 => 53,
        SampleFormat::I32 | SampleFormat::U32 => 32,
        SampleFormat::F32 => 24,
        SampleFormat::I16 | SampleFormat::U16 => 16,
        SampleFormat::I8 | SampleFormat::U8 => 8,
        _ => 0,
    }
}

/// Rank only formats the backend advertises. Actual stream creation can still fail;
/// the caller tries the next candidate and ultimately the system default.
fn output_candidates(
    source: dsp::SourceFormat,
    default: SupportedStreamConfig,
    supported: impl IntoIterator<Item = SupportedStreamConfigRange>,
) -> Vec<SupportedStreamConfig> {
    let mut candidates = Vec::new();
    for range in supported {
        for rate in [
            source.sample_rate,
            default.sample_rate().0,
            range.max_sample_rate().0,
        ] {
            if !(8000..=768000).contains(&rate) {
                continue;
            }
            if let Some(config) = range.try_with_sample_rate(SampleRate(rate)) {
                if config.channels() > 0
                    && config.channels() <= 32
                    && format_precision(config.sample_format()) > 0
                {
                    candidates.push(config);
                }
            }
        }
    }
    candidates.push(default.clone());
    candidates.sort_by_key(|cfg| {
        let precision = format_precision(cfg.sample_format());
        // CPAL does not describe speaker ordering. Use front stereo for multi-channel
        // sources, with the decoder's explicit downmix. Mono-to-stereo is exact and
        // also keeps the stereo pitch processors available for mono tracks.
        let channel_rank = if cfg.channels() == 2 {
            0
        } else if cfg.channels() == 1 && source.channels == 1 {
            1
        } else {
            2
        };
        (
            channel_rank,
            source.precision_bits.min(53).saturating_sub(precision),
            u8::from(cfg.sample_rate().0 != source.sample_rate),
            u8::from(cfg.sample_rate() != default.sample_rate()),
            u8::from(cfg.sample_format() != SampleFormat::F32),
            53u32.saturating_sub(precision),
        )
    });
    candidates.dedup_by(|a, b| {
        a.channels() == b.channels()
            && a.sample_rate() == b.sample_rate()
            && a.sample_format() == b.sample_format()
    });
    candidates
}

/// Request source-rate output with adequate precision where supported. These are
/// application stream attributes, not proof of the physical DAC/mixer configuration.
fn build_output(
    source: dsp::SourceFormat,
    frames_played: Arc<AtomicU64>,
    underrun_count: Arc<AtomicU64>,
    live_volume: Arc<Mutex<f32>>,
    quality_settings: Arc<Mutex<AudioQualitySettings>>,
    output_buffer_ms: u32,
    output_latency_mode: String,
) -> Result<(SendStream, OutputDeviceInfo, Arc<AudioBuffer>), String> {
    let _scope = profiler::scope("audio::player::build_output");
    let host = cpal::default_host();
    let device = host
        .default_output_device()
        .ok_or_else(|| "No default audio output device found".to_string())?;

    let default_cfg = device.default_output_config().map_err(|e| e.to_string())?;
    let device_name = device
        .name()
        .unwrap_or_else(|_| "Unknown output".to_string());
    let supported = device
        .supported_output_configs()
        .map(|configs| configs.collect::<Vec<_>>())
        .unwrap_or_default();
    let candidates = output_candidates(source, default_cfg, supported);
    let mut errors = Vec::new();
    for candidate in candidates {
        let want_rate = candidate.sample_rate();
        let want_ch = candidate.channels();
        let sample_format = candidate.sample_format();
        let supported_buffer_size = *candidate.buffer_size();
        let output_latency_mode = normalize_output_latency_mode(&output_latency_mode);
        let (device_buffer_size, mut buffer_size_label) =
            select_output_buffer_size(&output_latency_mode, &supported_buffer_size);

        let config = StreamConfig {
            channels: want_ch,
            sample_rate: want_rate,
            buffer_size: device_buffer_size,
        };

        let sample_rate = config.sample_rate.0;
        let channels = config.channels as u32;
        let ch = channels as usize;

        let buffer_ms = output_buffer_ms.clamp(60, 1500) as usize;
        let capacity = ((sample_rate as usize * buffer_ms / 1000).max(8192usize.div_ceil(ch))) * ch;
        let buffer = Arc::new(AudioBuffer::new(capacity));

        macro_rules! build_typed_stream {
            ($config:expr, $ty:ty) => {{
                let buf = buffer.clone();
                let fp = frames_played.clone();
                let uc = underrun_count.clone();
                let vol = live_volume.clone();
                let qs = quality_settings.clone();
                let mut dither = TpdfDither::new(0xA17E_51A3_59C3_0D42);
                device
                    .build_output_stream(
                        $config,
                        move |data: &mut [$ty], _| {
                            let _scope = profiler::scope("audio::player::output_callback");
                            let volume = current_output_volume(&vol);
                            let enabled =
                                qs.lock().unwrap_or_else(|e| e.into_inner()).dither_enabled;
                            let n = buf.pop(data, ch, volume, &mut dither, enabled);
                            if n < data.len() {
                                uc.fetch_add(1, Ordering::Relaxed);
                            }
                            fp.fetch_add((n / ch) as u64, Ordering::Relaxed);
                        },
                        err_fn,
                        None,
                    )
                    .map_err(|e| e.to_string())
            }};
        }
        macro_rules! build_stream_for_config {
            ($config:expr) => {{
                match sample_format {
                    SampleFormat::F32 => build_typed_stream!($config, f32),
                    SampleFormat::F64 => build_typed_stream!($config, f64),
                    SampleFormat::I8 => build_typed_stream!($config, i8),
                    SampleFormat::I16 => build_typed_stream!($config, i16),
                    SampleFormat::I32 => build_typed_stream!($config, i32),
                    SampleFormat::U8 => build_typed_stream!($config, u8),
                    SampleFormat::U16 => build_typed_stream!($config, u16),
                    SampleFormat::U32 => build_typed_stream!($config, u32),
                    other => Err(format!("Unsupported output sample format: {other:?}")),
                }
            }};
        }

        let stream = match build_stream_for_config!(&config) {
            Ok(stream) => stream,
            Err(err) if config.buffer_size != BufferSize::Default => {
                eprintln!(
                    "Requested output buffer {:?} failed ({}); falling back to default buffer",
                    config.buffer_size, err
                );
                let fallback_config = StreamConfig {
                    buffer_size: BufferSize::Default,
                    ..config.clone()
                };
                buffer_size_label = format!("{buffer_size_label} -> Default fallback");
                match build_stream_for_config!(&fallback_config) {
                    Ok(stream) => stream,
                    Err(fallback_err) => {
                        errors.push(format!("{sample_rate} Hz/{channels}ch/{sample_format:?}: {err}; default buffer: {fallback_err}"));
                        continue;
                    }
                }
            }
            Err(err) => {
                errors.push(format!(
                    "{sample_rate} Hz/{channels}ch/{sample_format:?}: {err}"
                ));
                continue;
            }
        };
        let output_info = OutputDeviceInfo {
            device_name,
            sample_rate,
            channels,
            sample_format: format!("{:?}", sample_format),
            buffer_size: buffer_size_label,
            output_latency_mode,
        };

        return Ok((SendStream(stream), output_info, buffer));
    }
    Err(format!(
        "No supported output stream could be opened: {}",
        errors.join("; ")
    ))
}

pub fn default_output_device_name() -> Result<String, String> {
    let _scope = profiler::scope("audio::player::default_output_device_name");
    let host = cpal::default_host();
    let device = host
        .default_output_device()
        .ok_or_else(|| "No default audio output device found".to_string())?;
    device.name().map_err(|e| e.to_string())
}

/// Start streaming playback of `path` with the given DSP parameters.
pub fn start_playback(
    path: String,
    vol: f32,
    pitch_val: f64,
    pitch_algo: String,
    normalization_gain: f32,
) -> Result<(), String> {
    let _scope = profiler::scope("audio::player::start_playback");
    let source = dsp::probe_source_format(&path)?;
    let mut state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());

    // Stop any existing playback.
    state.stop_flag.store(true, Ordering::SeqCst);
    if let Some(handle) = state.thread_handle.take() {
        let _ = handle.join();
    }
    // Drop the old stream first so the hardware callback stops touching the old buffer.
    state.stream = None;
    state.buffer = None;
    state.stream_finished.store(false, Ordering::SeqCst);
    state.queue_headroom_history.clear();

    let stop_flag = Arc::new(AtomicBool::new(false));
    let seek_request = Arc::new(Mutex::new(None));
    let frames_played = Arc::new(AtomicU64::new(0));
    let stream_finished = Arc::new(AtomicBool::new(false));
    let volume = Arc::new(Mutex::new(vol));
    let pitch = Arc::new(Mutex::new(pitch_val));
    let algo = Arc::new(Mutex::new(pitch_algo));
    let norm_gain = Arc::new(Mutex::new(normalization_gain));
    let output_buffer_ms = state.output_buffer_ms;
    let output_latency_mode = state.output_latency_mode.clone();
    let quality_settings = state.quality_settings.clone();
    let underrun_count = Arc::new(AtomicU64::new(0));
    let clipped_sample_count = Arc::new(AtomicU64::new(0));
    let peak_bits = Arc::new(AtomicU64::new(0.0f64.to_bits()));
    let processing_params = ProcessingParams {
        pitch: pitch.clone(),
        algo: algo.clone(),
        loudness_normalization_gain: norm_gain.clone(),
        quality_settings: quality_settings.clone(),
        clipped_sample_count: clipped_sample_count.clone(),
        peak_bits: peak_bits.clone(),
    };

    let (stream, output_info, buffer) = build_output(
        source,
        frames_played.clone(),
        underrun_count.clone(),
        volume.clone(),
        quality_settings.clone(),
        output_buffer_ms,
        output_latency_mode,
    )?;
    let sample_rate = output_info.sample_rate;
    let channels = output_info.channels;
    let mut pipeline = DecodePipeline::new(&path, sample_rate, channels, processing_params)?;
    // Keep the same processor state from prefill through playback, including its
    // delayed samples. Starting a pitch stream with an empty queue causes avoidable underruns.
    let mut rubberband_shifter: Option<RubberBandPitchShifter> = None;
    let mut vocal_only_shifter: Option<VocalOnlyPitchProcessor> = None;
    prefill_audio_buffer(
        &mut pipeline,
        &mut rubberband_shifter,
        &mut vocal_only_shifter,
        &buffer,
        &stop_flag,
        output_buffer_ms.min(160),
    )?;
    stream.0.play().map_err(|e| e.to_string())?;

    state.stream = Some(stream);
    state.buffer = Some(buffer.clone());
    state.sample_rate = sample_rate;
    state.channels = channels;
    state.stop_flag = stop_flag.clone();
    state.seek_request = seek_request.clone();
    state.frames_played = frames_played.clone();
    state.stream_finished = stream_finished.clone();
    state.volume = volume.clone();
    state.pitch = pitch.clone();
    state.algo = algo.clone();
    state.loudness_normalization_gain = norm_gain.clone();
    state.output_info = Arc::new(Mutex::new(output_info));
    state.underrun_count = underrun_count.clone();
    state.clipped_sample_count = clipped_sample_count.clone();
    state.peak_bits = peak_bits.clone();

    let handle = thread::Builder::new()
        .name("aetheria-audio-decode".to_string())
        .spawn(move || {
            loop {
                if stop_flag.load(Ordering::SeqCst) {
                    break;
                }
                let _loop_scope = profiler::scope("audio::player::decode_thread_loop");

                // Handle seek requests.
                {
                    let mut req = seek_request.lock().unwrap_or_else(|e| e.into_inner());
                    if let Some(sec) = req.take() {
                        if let Err(e) = pipeline.seek(sec) {
                            eprintln!("Seek error: {}", e);
                        }
                        if let Some(shifter) = &mut rubberband_shifter {
                            shifter.reset();
                        }
                        if let Some(shifter) = &mut vocal_only_shifter {
                            shifter.reset();
                        }
                        buffer.clear();
                        // A seek starts a fresh five-second headroom window.
                        stream_finished.store(false, Ordering::SeqCst);
                        if let Err(e) = prefill_audio_buffer(
                            &mut pipeline,
                            &mut rubberband_shifter,
                            &mut vocal_only_shifter,
                            &buffer,
                            &stop_flag,
                            80,
                        ) {
                            eprintln!("Prefill error after seek: {}", e);
                        }
                        frames_played
                            .store((sec * sample_rate as f64).round() as u64, Ordering::SeqCst);
                    }
                }

                let block =
                    match pipeline.next_block(&mut rubberband_shifter, &mut vocal_only_shifter) {
                        Ok(Some(block)) => block,
                        Ok(None) => {
                            // End of stream: let the hardware drain whatever is still buffered.
                            while buffer.len() > 0 && !stop_flag.load(Ordering::SeqCst) {
                                thread::sleep(Duration::from_millis(20));
                            }
                            stream_finished.store(true, Ordering::SeqCst);
                            break;
                        }
                        Err(e) => {
                            eprintln!("Decode error: {}", e);
                            stream_finished.store(true, Ordering::SeqCst);
                            break;
                        }
                    };

                if block.is_empty() {
                    continue;
                }
                {
                    let _push_scope = profiler::scope("audio::player::AudioBuffer::push_wait");
                    buffer.push(&block, &stop_flag);
                }
            }
        })
        .map_err(|e| e.to_string())?;

    state.thread_handle = Some(handle);
    Ok(())
}

pub fn pause_playback() -> Result<(), String> {
    let _scope = profiler::scope("audio::player::pause_playback");
    let state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(s) = &state.stream {
        s.0.pause().map_err(|e| e.to_string())?;
    }
    Ok(())
}

pub fn resume_playback() -> Result<(), String> {
    let _scope = profiler::scope("audio::player::resume_playback");
    let state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(s) = &state.stream {
        s.0.play().map_err(|e| e.to_string())?;
    }
    Ok(())
}

pub fn seek_playback(secs: f64) -> Result<(), String> {
    let _scope = profiler::scope("audio::player::seek_playback");
    let mut state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
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
    state.stream_finished.store(false, Ordering::SeqCst);
    state.queue_headroom_history.clear();
    Ok(())
}

pub fn stop_playback() -> Result<(), String> {
    let _scope = profiler::scope("audio::player::stop_playback");
    let mut state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    state.stop_flag.store(true, Ordering::SeqCst);
    if let Some(handle) = state.thread_handle.take() {
        let _ = handle.join();
    }
    state.stream = None;
    state.buffer = None;
    state.stream_finished.store(false, Ordering::SeqCst);
    state.queue_headroom_history.clear();
    Ok(())
}

pub fn set_volume(vol: f32) -> Result<(), String> {
    let _scope = profiler::scope("audio::player::set_volume");
    let state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    *state.volume.lock().unwrap_or_else(|e| e.into_inner()) = vol;
    Ok(())
}

pub fn set_pitch(pitch_val: f64, pitch_algo: String) -> Result<(), String> {
    let _scope = profiler::scope("audio::player::set_pitch");
    let state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    *state.pitch.lock().unwrap_or_else(|e| e.into_inner()) = pitch_val;
    *state.algo.lock().unwrap_or_else(|e| e.into_inner()) = pitch_algo;
    Ok(())
}

pub fn set_output_buffer_ms(ms: i32) -> Result<(), String> {
    let _scope = profiler::scope("audio::player::set_output_buffer_ms");
    let mut state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    state.output_buffer_ms = ms.clamp(60, 1500) as u32;
    Ok(())
}

pub fn set_output_latency_mode(mode: String) -> Result<(), String> {
    let _scope = profiler::scope("audio::player::set_output_latency_mode");
    let mut state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    let normalized = normalize_output_latency_mode(&mode);
    state.output_latency_mode = normalized.clone();
    state
        .output_info
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .output_latency_mode = normalized;
    Ok(())
}

pub fn set_quality_settings(
    peak_protection_enabled: bool,
    dither_enabled: bool,
    rubberband_window: String,
    rubberband_formant_preserved: bool,
    rubberband_vocal_only_pitch: bool,
    resampler_quality: String,
) -> Result<(), String> {
    let _scope = profiler::scope("audio::player::set_quality_settings");
    let state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    *state
        .quality_settings
        .lock()
        .unwrap_or_else(|e| e.into_inner()) = AudioQualitySettings {
        peak_protection_enabled,
        dither_enabled,
        rubberband_window: normalize_rubberband_window(&rubberband_window),
        rubberband_formant_preserved,
        rubberband_vocal_only_pitch,
        resampler_quality: normalize_resampler_quality(&resampler_quality),
    };
    Ok(())
}

pub fn get_output_info() -> AudioOutputInfo {
    let _scope = profiler::scope("audio::player::get_output_info");
    let mut state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
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
    let current_queued_ms = if state.sample_rate > 0 && state.channels > 0 {
        state
            .buffer
            .as_ref()
            .map(|buffer| {
                ((buffer.len() as u64 * 1000) / (state.sample_rate as u64 * state.channels as u64))
                    as u32
            })
            .unwrap_or(0)
    } else {
        0
    };
    let now = Instant::now();
    state
        .queue_headroom_history
        .push_back((now, current_queued_ms));
    while state
        .queue_headroom_history
        .front()
        .is_some_and(|(captured_at, _)| now.duration_since(*captured_at) > Duration::from_secs(5))
    {
        state.queue_headroom_history.pop_front();
    }
    let queued_ms = state
        .queue_headroom_history
        .iter()
        .map(|(_, value)| *value)
        .min()
        .unwrap_or(current_queued_ms);

    AudioOutputInfo {
        device_name: info.device_name,
        sample_rate: info.sample_rate,
        channels: info.channels,
        sample_format: info.sample_format,
        buffer_size: info.buffer_size,
        output_latency_mode: info.output_latency_mode,
        output_buffer_ms: state.output_buffer_ms,
        queued_ms,
        underruns: state.underrun_count.load(Ordering::Relaxed),
        clipped_samples: state.clipped_sample_count.load(Ordering::Relaxed),
        peak_db,
    }
}

/// Current playback position in seconds, derived from samples actually consumed by the
/// hardware (not samples queued in the buffer), so it stays accurate regardless of
/// buffering or pitch shifting.
pub fn get_position() -> f64 {
    let _scope = profiler::scope("audio::player::get_position");
    let state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    let frames = state.frames_played.load(Ordering::Relaxed);
    if state.sample_rate == 0 {
        0.0
    } else {
        frames as f64 / state.sample_rate as f64
    }
}

pub fn is_finished() -> bool {
    let _scope = profiler::scope("audio::player::is_finished");
    let state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    state.stream_finished.load(Ordering::Relaxed)
}

fn normalize_rubberband_window(value: &str) -> String {
    if value == "quality" {
        "quality".to_string()
    } else {
        "latency".to_string()
    }
}

fn normalize_resampler_quality(value: &str) -> String {
    if value == "standard" {
        "standard".to_string()
    } else {
        "high".to_string()
    }
}

#[cfg(test)]
mod fidelity_tests {
    use super::*;
    use crate::audio::test_support::TestWav;

    fn params() -> ProcessingParams {
        ProcessingParams {
            pitch: Arc::new(Mutex::new(0.0)),
            algo: Arc::new(Mutex::new("rubberband".into())),
            loudness_normalization_gain: Arc::new(Mutex::new(1.0)),
            quality_settings: Arc::new(Mutex::new(AudioQualitySettings::default())),
            clipped_sample_count: Arc::new(AtomicU64::new(0)),
            peak_bits: Arc::new(AtomicU64::new(0)),
        }
    }

    #[test]
    fn prefill_and_neutral_pipeline_preserve_every_32bit_sample() {
        let samples: Vec<i32> = (0i32..20000).map(|n| n.wrapping_mul(104729)).collect();
        let file = TestWav::pcm(48000, 2, 32, &samples);
        let mut pipeline = DecodePipeline::new(file.path(), 48000, 2, params()).unwrap();
        let buffer = AudioBuffer::new(7000);
        let mut rubberband = None;
        let mut vocal = None;
        prefill_audio_buffer(
            &mut pipeline,
            &mut rubberband,
            &mut vocal,
            &buffer,
            &AtomicBool::new(false),
            160,
        )
        .unwrap();
        assert!(
            !pipeline.pending_output.is_empty(),
            "test must fill beyond queue capacity"
        );
        let mut output = vec![0i32; buffer.len()];
        let mut dither = TpdfDither::new(123);
        let len = output.len();
        assert_eq!(buffer.pop(&mut output, 2, 1.0, &mut dither, true), len);
        while let Some(block) = pipeline.next_block(&mut rubberband, &mut vocal).unwrap() {
            output.extend(block.into_iter().map(|s| i32::encode(s, &mut dither, true)));
        }
        assert_eq!(output, samples);
    }

    #[test]
    fn unsigned_underflow_is_silent_and_partial_frames_are_not_consumed() {
        let buffer = AudioBuffer::new(16);
        buffer.try_push(&[-1.0, 0.0, 0.5]);
        let mut output = [0u16; 6];
        let count = buffer.pop(&mut output, 2, 1.0, &mut TpdfDither::new(1), true);
        assert_eq!(count, 2);
        assert_eq!(output, [0, 32768, 32768, 32768, 32768, 32768]);
        assert_eq!(buffer.len(), 1);
    }

    #[test]
    fn larger_than_capacity_blocks_keep_order_and_can_be_stopped() {
        let buffer = Arc::new(AudioBuffer::new(64));
        let producer = buffer.clone();
        let stop = Arc::new(AtomicBool::new(false));
        let producer_stop = stop.clone();
        let input: Vec<f64> = (0..1000).map(|n| n as f64 / 1000.0).collect();
        let expected = input.clone();
        let handle = thread::spawn(move || producer.push(&input, &producer_stop));
        let mut actual = Vec::new();
        let start = Instant::now();
        while actual.len() < expected.len() && start.elapsed() < Duration::from_secs(3) {
            let mut block = [0.0f64; 32];
            let count = buffer.pop(&mut block, 2, 1.0, &mut TpdfDither::new(1), true);
            actual.extend_from_slice(&block[..count]);
            thread::yield_now();
        }
        stop.store(true, Ordering::SeqCst);
        handle.join().unwrap();
        assert_eq!(actual, expected);
    }

    fn range(rate: u32, format: SampleFormat) -> SupportedStreamConfigRange {
        SupportedStreamConfigRange::new(
            2,
            SampleRate(rate),
            SampleRate(rate),
            SupportedBufferSize::Unknown,
            format,
        )
    }

    #[test]
    fn output_selection_keeps_native_rate_and_pcm32_precision_when_available() {
        let default = range(48000, SampleFormat::F32).with_sample_rate(SampleRate(48000));
        let source = dsp::SourceFormat {
            sample_rate: 44100,
            channels: 2,
            precision_bits: 32,
        };
        let candidates = output_candidates(
            source,
            default,
            [
                range(44100, SampleFormat::F32),
                range(44100, SampleFormat::I32),
                range(48000, SampleFormat::I32),
                range(44100, SampleFormat::I16),
            ],
        );
        assert_eq!(candidates[0].sample_rate().0, 44100);
        assert_eq!(candidates[0].sample_format(), SampleFormat::I32);
        assert!(candidates
            .iter()
            .any(|c| c.sample_rate().0 == 48000 && c.sample_format() == SampleFormat::F32));
    }

    #[test]
    fn float64_source_prefers_float64_and_empty_capabilities_keep_default() {
        let default = range(48000, SampleFormat::F32).with_sample_rate(SampleRate(48000));
        let source = dsp::SourceFormat {
            sample_rate: 48000,
            channels: 2,
            precision_bits: 64,
        };
        let candidates = output_candidates(
            source,
            default.clone(),
            [
                range(48000, SampleFormat::I32),
                range(48000, SampleFormat::F64),
            ],
        );
        assert_eq!(candidates[0].sample_format(), SampleFormat::F64);
        let fallback = output_candidates(source, default, []);
        assert_eq!(fallback.len(), 1);
        assert_eq!(fallback[0].sample_format(), SampleFormat::F32);
    }

    #[test]
    fn protection_preserves_in_range_signal_and_contains_nonfinite_or_overload() {
        let counter = AtomicU64::new(0);
        let peak = AtomicU64::new(0);
        let mut input = [-1.0, -1e-14, 0.0, 1e-14, 0.999999999999];
        let expected = input;
        apply_post_dsp_protection(&mut input, true, &counter, &peak);
        assert_eq!(input, expected);
        let mut overload = [f64::NAN, f64::INFINITY, -2.0, 2.0];
        apply_post_dsp_protection(&mut overload, true, &counter, &peak);
        assert!(overload.iter().all(|s| s.is_finite() && s.abs() < 1.0));
        assert_eq!(counter.load(Ordering::Relaxed), 2);
    }
    #[test]
    #[ignore = "requires a physical/system output device; opens a silent stream"]
    fn system_output_negotiation_smoke_test() {
        let (stream, info, _) = build_output(
            dsp::SourceFormat {
                sample_rate: 44100,
                channels: 2,
                precision_bits: 24,
            },
            Arc::new(AtomicU64::new(0)),
            Arc::new(AtomicU64::new(0)),
            Arc::new(Mutex::new(0.0)),
            Arc::new(Mutex::new(AudioQualitySettings::default())),
            240,
            "shared-default".into(),
        )
        .unwrap();
        eprintln!("System stream opened: {info:?}");
        drop(stream);
    }
    #[test]
    fn vocal_only_pitch_keeps_side_channels_aligned_through_tail() {
        let mut processor = VocalOnlyPitchProcessor::new(48000, 1.12246, "latency", false).unwrap();
        let input: Vec<f32> = (0..12001)
            .flat_map(|n| {
                let s = (n as f32 * 0.13).sin() * 0.2;
                [s, -s]
            })
            .collect();
        let mut output = Vec::new();
        for block in input.chunks(258) {
            output.extend(processor.process(block, 1.12246));
        }
        output.extend(processor.finish());
        assert_eq!(output, input);
        assert!(processor.finish().is_empty());
    }
}
