use std::collections::VecDeque;
use std::sync::{
    atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering},
    Arc, Mutex,
};
use std::thread;
use std::time::{Duration, Instant};

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{BufferSize, SampleFormat, StreamConfig, SupportedBufferSize};

use crate::audio::dsp::{self, StreamDecoder};
use crate::audio::profiler;
use crate::audio::rubberband::RubberBandPitchShifter;

// Thread-safe ring buffer / FIFO used to bridge the decode thread and the cpal
// hardware callback thread.
pub struct AudioBuffer {
    data: Mutex<VecDeque<f32>>,
    capacity: usize,
    len_samples: AtomicUsize,
}

const HAPTIC_FRAME_DURATION_MS: u32 = 10;
const MAX_HAPTIC_QUEUE_POINTS: usize = 80;

#[derive(Clone, Copy, Debug)]
struct HapticControlPoint {
    amplitude: f32,
    frequency_position: f32,
}

struct HapticAnalyzer {
    sample_rate: u32,
    channels: usize,
    target_frames: usize,
    accumulated_frames: usize,
    sum_squares: f64,
    zero_crossings: usize,
    previous_sample: f32,
    has_previous_sample: bool,
    smoothed_amplitude: f32,
    smoothed_frequency_position: f32,
}

impl HapticAnalyzer {
    fn new(sample_rate: u32, channels: usize) -> Self {
        Self {
            sample_rate,
            channels: channels.max(1),
            target_frames: ((sample_rate as usize * HAPTIC_FRAME_DURATION_MS as usize) / 1000)
                .max(1),
            accumulated_frames: 0,
            sum_squares: 0.0,
            zero_crossings: 0,
            previous_sample: 0.0,
            has_previous_sample: false,
            smoothed_amplitude: 0.0,
            smoothed_frequency_position: 0.5,
        }
    }

    fn reset(&mut self) {
        self.accumulated_frames = 0;
        self.sum_squares = 0.0;
        self.zero_crossings = 0;
        self.previous_sample = 0.0;
        self.has_previous_sample = false;
        self.smoothed_amplitude = 0.0;
        self.smoothed_frequency_position = 0.5;
    }

    fn push(
        &mut self,
        samples: &[f32],
        intensity: f32,
        queue: &Mutex<VecDeque<HapticControlPoint>>,
    ) {
        for frame in samples.chunks(self.channels) {
            if frame.is_empty() {
                continue;
            }
            let mono = frame.iter().copied().sum::<f32>() / frame.len() as f32;
            self.sum_squares += (mono as f64) * (mono as f64);
            if self.has_previous_sample
                && ((self.previous_sample < 0.0 && mono >= 0.0)
                    || (self.previous_sample >= 0.0 && mono < 0.0))
            {
                self.zero_crossings += 1;
            }
            self.previous_sample = mono;
            self.has_previous_sample = true;
            self.accumulated_frames += 1;

            if self.accumulated_frames >= self.target_frames {
                self.finish_frame(intensity, queue);
            }
        }
    }

    fn finish_frame(&mut self, intensity: f32, queue: &Mutex<VecDeque<HapticControlPoint>>) {
        let frame_count = self.accumulated_frames.max(1);
        let rms = (self.sum_squares / frame_count as f64).sqrt() as f32;
        let gated = if rms < 0.004 {
            0.0
        } else {
            ((rms - 0.004) * 5.5).clamp(0.0, 1.0).powf(0.58)
        };
        let target_amplitude = gated * intensity.clamp(0.0, 1.0);
        let amplitude_mix = if target_amplitude > self.smoothed_amplitude {
            0.48
        } else {
            0.22
        };
        self.smoothed_amplitude += (target_amplitude - self.smoothed_amplitude) * amplitude_mix;

        let estimated_frequency_hz =
            self.zero_crossings as f32 * self.sample_rate as f32 / (2.0 * frame_count as f32);
        let target_frequency_position =
            ((estimated_frequency_hz.clamp(70.0, 420.0) - 70.0) / 350.0).clamp(0.0, 1.0);
        self.smoothed_frequency_position +=
            (target_frequency_position - self.smoothed_frequency_position) * 0.28;

        if let Ok(mut points) = queue.try_lock() {
            while points.len() >= MAX_HAPTIC_QUEUE_POINTS {
                points.pop_front();
            }
            points.push_back(HapticControlPoint {
                amplitude: self.smoothed_amplitude.clamp(0.0, 1.0),
                frequency_position: self.smoothed_frequency_position.clamp(0.0, 1.0),
            });
        }

        self.accumulated_frames = 0;
        self.sum_squares = 0.0;
        self.zero_crossings = 0;
    }
}

#[derive(Clone)]
struct HapticCapture {
    enabled: Arc<AtomicBool>,
    queue: Arc<Mutex<VecDeque<HapticControlPoint>>>,
    analyzer: Arc<Mutex<HapticAnalyzer>>,
}

impl HapticCapture {
    fn new(
        enabled: Arc<AtomicBool>,
        queue: Arc<Mutex<VecDeque<HapticControlPoint>>>,
        sample_rate: u32,
        channels: usize,
    ) -> Self {
        Self {
            enabled,
            queue,
            analyzer: Arc::new(Mutex::new(HapticAnalyzer::new(sample_rate, channels))),
        }
    }

    /// Returns true when normal speaker output should be silenced.
    fn process(&self, samples: &[f32], intensity: f32) -> bool {
        if !self.enabled.load(Ordering::Relaxed) {
            if let Ok(mut analyzer) = self.analyzer.try_lock() {
                analyzer.reset();
            }
            return false;
        }
        if let Ok(mut analyzer) = self.analyzer.try_lock() {
            analyzer.push(samples, intensity, &self.queue);
        }
        true
    }
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
        })
    }

    fn seek(&mut self, secs: f64) -> Result<(), String> {
        let _scope = profiler::scope("audio::player::DecodePipeline::seek");
        self.decoder.seek(secs)?;
        Ok(())
    }

    fn next_block(
        &mut self,
        rubberband_shifter: &mut Option<RubberBandPitchShifter>,
        vocal_only_shifter: &mut Option<VocalOnlyPitchProcessor>,
    ) -> Result<Option<Vec<f32>>, String> {
        let _scope = profiler::scope("audio::player::DecodePipeline::next_block");
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
                        return Ok(Some(tail));
                    }
                }
            } else if let Some(shifter) = rubberband_shifter {
                let tail = shifter.finish();
                if !tail.is_empty() {
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
        if (total_gain - 1.0).abs() > 0.001 {
            for sample in block.iter_mut() {
                *sample *= total_gain;
            }
        }

        let mut processed = if current_pitch.abs() > 0.01 && self.channels == 2 {
            let _pitch_scope = profiler::scope("audio::player::DecodePipeline::pitch_shift");
            let pitch_factor = 2.0f64.powf(current_pitch / 12.0);
            match current_algo.as_str() {
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
            }
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
    pub fn push(&self, samples: &[f32], stop_flag: &AtomicBool) {
        let _scope = profiler::scope("audio::player::AudioBuffer::push");
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
        self.len_samples.fetch_add(samples.len(), Ordering::Relaxed);
    }

    pub fn try_push(&self, samples: &[f32]) -> bool {
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

    pub fn pop(&self, out: &mut [f32]) -> usize {
        let _scope = profiler::scope("audio::player::AudioBuffer::pop");
        let mut queue = self.data.lock().unwrap_or_else(|e| e.into_inner());
        let len = out.len().min(queue.len());
        for i in 0..len {
            out[i] = queue.pop_front().unwrap_or(0.0);
        }
        if len > 0 {
            self.len_samples.fetch_sub(len, Ordering::Relaxed);
        }
        len
    }

    pub fn clear(&self) {
        let _scope = profiler::scope("audio::player::AudioBuffer::clear");
        self.data.lock().unwrap_or_else(|e| e.into_inner()).clear();
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
    haptic_enabled: Arc<AtomicBool>,
    haptic_queue: Arc<Mutex<VecDeque<HapticControlPoint>>>,
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
        haptic_enabled: Arc::new(AtomicBool::new(false)),
        haptic_queue: Arc::new(Mutex::new(VecDeque::new())),
        queue_headroom_history: VecDeque::new(),
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
    let _scope = profiler::scope("audio::player::apply_post_dsp_protection");
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
            break;
        }
    }
    Ok(())
}

fn current_output_volume(volume: &Arc<Mutex<f32>>) -> f32 {
    let value = *volume.lock().unwrap_or_else(|e| e.into_inner());
    value.clamp(0.0, 1.0)
}

/// Negotiate an output config, preferring f32 at the device's default rate/channels so we
/// can feed the callback without per-callback allocation. Returns the live stream plus the
/// negotiated sample rate, channel count and the shared ring buffer.
fn build_output(
    frames_played: Arc<AtomicU64>,
    underrun_count: Arc<AtomicU64>,
    live_volume: Arc<Mutex<f32>>,
    quality_settings: Arc<Mutex<AudioQualitySettings>>,
    haptic_enabled: Arc<AtomicBool>,
    haptic_queue: Arc<Mutex<VecDeque<HapticControlPoint>>>,
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
    let want_rate = default_cfg.sample_rate();
    let want_ch = default_cfg.channels();
    let default_fmt = default_cfg.sample_format();
    let mut supported_buffer_size = *default_cfg.buffer_size();

    // Prefer an f32 config (zero-allocation callback). Fall back to the device default format.
    let sample_format = if default_fmt == SampleFormat::F32 {
        SampleFormat::F32
    } else {
        let mut f32_buffer_size = None;
        if let Ok(supported) = device.supported_output_configs() {
            for cfg in supported {
                if cfg.channels() == want_ch
                    && cfg.sample_format() == SampleFormat::F32
                    && cfg.min_sample_rate() <= want_rate
                    && cfg.max_sample_rate() >= want_rate
                {
                    f32_buffer_size = Some(*cfg.buffer_size());
                    break;
                }
            }
        }
        if let Some(buffer_size) = f32_buffer_size {
            supported_buffer_size = buffer_size;
            SampleFormat::F32
        } else {
            default_fmt
        }
    };
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
    let haptic_capture = HapticCapture::new(haptic_enabled, haptic_queue, sample_rate, ch);

    let buffer_ms = output_buffer_ms.clamp(60, 1500) as usize;
    let capacity = ((sample_rate as usize * ch * buffer_ms) / 1000).max(8192);
    let buffer = Arc::new(AudioBuffer::new(capacity));

    macro_rules! build_stream_for_config {
        ($stream_config:expr) => {{
            match sample_format {
                SampleFormat::F32 => {
                    let buf = buffer.clone();
                    let fp = frames_played.clone();
                    let uc = underrun_count.clone();
                    let vol = live_volume.clone();
                    let haptics = haptic_capture.clone();
                    device
                        .build_output_stream(
                            $stream_config,
                            move |data: &mut [f32], _| {
                                let _profile_scope =
                                    profiler::scope("audio::player::output_callback");
                                let n = buf.pop(data);
                                if n < data.len() {
                                    uc.fetch_add(1, Ordering::Relaxed);
                                }
                                let output_volume = current_output_volume(&vol);
                                let motor_audio_active = haptics.process(&data[..n], output_volume);
                                if motor_audio_active {
                                    data[..n].fill(0.0);
                                } else if (output_volume - 1.0).abs() > 0.001 {
                                    for sample in &mut data[..n] {
                                        *sample *= output_volume;
                                    }
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
                        .map_err(|e| e.to_string())
                }
                SampleFormat::I16 => {
                    let buf = buffer.clone();
                    let fp = frames_played.clone();
                    let uc = underrun_count.clone();
                    let qs = quality_settings.clone();
                    let vol = live_volume.clone();
                    let haptics = haptic_capture.clone();
                    let mut tmp = Vec::<f32>::new();
                    let mut dither = TpdfDither::new(0xA17E_51A3_59C3_0D42);
                    device
                        .build_output_stream(
                            $stream_config,
                            move |data: &mut [i16], _| {
                                let _profile_scope =
                                    profiler::scope("audio::player::output_callback");
                                tmp.resize(data.len(), 0.0);
                                let n = buf.pop(&mut tmp);
                                if n < data.len() {
                                    uc.fetch_add(1, Ordering::Relaxed);
                                }
                                let dither_enabled =
                                    qs.lock().unwrap_or_else(|e| e.into_inner()).dither_enabled;
                                let output_volume = current_output_volume(&vol);
                                let motor_audio_active = haptics.process(&tmp[..n], output_volume);
                                if motor_audio_active {
                                    data[..n].fill(0);
                                } else {
                                    for i in 0..n {
                                        let sample = tmp[i] * output_volume;
                                        let v = if dither_enabled {
                                            dither.apply(sample, 1.0 / 32768.0)
                                        } else {
                                            sample
                                        };
                                        data[i] = (v.clamp(-1.0, 1.0) * 32767.0) as i16;
                                    }
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
                        .map_err(|e| e.to_string())
                }
                SampleFormat::U16 => {
                    let buf = buffer.clone();
                    let fp = frames_played.clone();
                    let uc = underrun_count.clone();
                    let qs = quality_settings.clone();
                    let vol = live_volume.clone();
                    let haptics = haptic_capture.clone();
                    let mut tmp = Vec::<f32>::new();
                    let mut dither = TpdfDither::new(0x9E37_79B9_7F4A_7C15);
                    device
                        .build_output_stream(
                            $stream_config,
                            move |data: &mut [u16], _| {
                                let _profile_scope =
                                    profiler::scope("audio::player::output_callback");
                                tmp.resize(data.len(), 0.0);
                                let n = buf.pop(&mut tmp);
                                if n < data.len() {
                                    uc.fetch_add(1, Ordering::Relaxed);
                                }
                                let dither_enabled =
                                    qs.lock().unwrap_or_else(|e| e.into_inner()).dither_enabled;
                                let output_volume = current_output_volume(&vol);
                                let motor_audio_active = haptics.process(&tmp[..n], output_volume);
                                if motor_audio_active {
                                    data[..n].fill(32768);
                                } else {
                                    for i in 0..n {
                                        let sample = tmp[i] * output_volume;
                                        let v = if dither_enabled {
                                            dither.apply(sample, 1.0 / 65536.0)
                                        } else {
                                            sample
                                        };
                                        data[i] =
                                            ((v.clamp(-1.0, 1.0) * 0.5 + 0.5) * 65535.0) as u16;
                                    }
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
                        .map_err(|e| e.to_string())
                }
                SampleFormat::I32 => {
                    let buf = buffer.clone();
                    let fp = frames_played.clone();
                    let uc = underrun_count.clone();
                    let qs = quality_settings.clone();
                    let vol = live_volume.clone();
                    let haptics = haptic_capture.clone();
                    let mut tmp = Vec::<f32>::new();
                    let mut dither = TpdfDither::new(0xD1B5_4A32_D192_ED03);
                    device
                        .build_output_stream(
                            $stream_config,
                            move |data: &mut [i32], _| {
                                let _profile_scope =
                                    profiler::scope("audio::player::output_callback");
                                tmp.resize(data.len(), 0.0);
                                let n = buf.pop(&mut tmp);
                                if n < data.len() {
                                    uc.fetch_add(1, Ordering::Relaxed);
                                }
                                let dither_enabled =
                                    qs.lock().unwrap_or_else(|e| e.into_inner()).dither_enabled;
                                let output_volume = current_output_volume(&vol);
                                let motor_audio_active = haptics.process(&tmp[..n], output_volume);
                                if motor_audio_active {
                                    data[..n].fill(0);
                                } else {
                                    for i in 0..n {
                                        let sample = tmp[i] * output_volume;
                                        let v = if dither_enabled {
                                            dither.apply(sample, 1.0 / 2_147_483_648.0)
                                        } else {
                                            sample
                                        };
                                        data[i] = (v.clamp(-1.0, 1.0) * 2147483647.0) as i32;
                                    }
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
                        .map_err(|e| e.to_string())
                }
                SampleFormat::U8 => {
                    let buf = buffer.clone();
                    let fp = frames_played.clone();
                    let uc = underrun_count.clone();
                    let qs = quality_settings.clone();
                    let vol = live_volume.clone();
                    let haptics = haptic_capture.clone();
                    let mut tmp = Vec::<f32>::new();
                    let mut dither = TpdfDither::new(0x94D0_49BB_1331_11EB);
                    device
                        .build_output_stream(
                            $stream_config,
                            move |data: &mut [u8], _| {
                                let _profile_scope =
                                    profiler::scope("audio::player::output_callback");
                                tmp.resize(data.len(), 0.0);
                                let n = buf.pop(&mut tmp);
                                if n < data.len() {
                                    uc.fetch_add(1, Ordering::Relaxed);
                                }
                                let dither_enabled =
                                    qs.lock().unwrap_or_else(|e| e.into_inner()).dither_enabled;
                                let output_volume = current_output_volume(&vol);
                                let motor_audio_active = haptics.process(&tmp[..n], output_volume);
                                if motor_audio_active {
                                    data[..n].fill(128);
                                } else {
                                    for i in 0..n {
                                        let sample = tmp[i] * output_volume;
                                        let v = if dither_enabled {
                                            dither.apply(sample, 1.0 / 256.0)
                                        } else {
                                            sample
                                        };
                                        data[i] = ((v.clamp(-1.0, 1.0) * 0.5 + 0.5) * 255.0) as u8;
                                    }
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
                        .map_err(|e| e.to_string())
                }
                SampleFormat::F64 => {
                    let buf = buffer.clone();
                    let fp = frames_played.clone();
                    let uc = underrun_count.clone();
                    let vol = live_volume.clone();
                    let haptics = haptic_capture.clone();
                    let mut tmp = Vec::<f32>::new();
                    device
                        .build_output_stream(
                            $stream_config,
                            move |data: &mut [f64], _| {
                                let _profile_scope =
                                    profiler::scope("audio::player::output_callback");
                                tmp.resize(data.len(), 0.0);
                                let n = buf.pop(&mut tmp);
                                if n < data.len() {
                                    uc.fetch_add(1, Ordering::Relaxed);
                                }
                                let output_volume = current_output_volume(&vol);
                                let motor_audio_active = haptics.process(&tmp[..n], output_volume);
                                if motor_audio_active {
                                    data[..n].fill(0.0);
                                } else {
                                    for i in 0..n {
                                        data[i] = (tmp[i] * output_volume) as f64;
                                    }
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
                        .map_err(|e| e.to_string())
                }
                other => Err(format!("Unsupported output sample format: {:?}", other)),
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
            build_stream_for_config!(&fallback_config).map_err(|fallback_err| {
                format!(
                    "Failed to build output stream with fixed buffer ({err}) and default buffer ({fallback_err})"
                )
            })?
        }
        Err(err) => return Err(err.to_string()),
    };
    let output_info = OutputDeviceInfo {
        device_name,
        sample_rate,
        channels,
        sample_format: format!("{:?}", sample_format),
        buffer_size: buffer_size_label,
        output_latency_mode,
    };

    Ok((SendStream(stream), output_info, buffer))
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
    let haptic_enabled = state.haptic_enabled.clone();
    let haptic_queue = state.haptic_queue.clone();
    haptic_queue
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .clear();
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
        frames_played.clone(),
        underrun_count.clone(),
        volume.clone(),
        quality_settings.clone(),
        haptic_enabled,
        haptic_queue,
        output_buffer_ms,
        output_latency_mode,
    )?;
    let sample_rate = output_info.sample_rate;
    let channels = output_info.channels;
    let mut pipeline = DecodePipeline::new(&path, sample_rate, channels, processing_params)?;
    if !(pitch_val.abs() > 0.01
        && algo.lock().unwrap_or_else(|e| e.into_inner()).as_str() != "resample")
    {
        let mut prefill_rubberband_shifter: Option<RubberBandPitchShifter> = None;
        let mut prefill_vocal_only_shifter: Option<VocalOnlyPitchProcessor> = None;
        prefill_audio_buffer(
            &mut pipeline,
            &mut prefill_rubberband_shifter,
            &mut prefill_vocal_only_shifter,
            &buffer,
            &stop_flag,
            output_buffer_ms.min(160),
        )?;
    }
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
            let mut rubberband_shifter: Option<RubberBandPitchShifter> = None;
            let mut vocal_only_shifter: Option<VocalOnlyPitchProcessor> = None;
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
    state
        .haptic_queue
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .clear();
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
    state
        .haptic_queue
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .clear();
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
    state
        .haptic_queue
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .clear();
    state.queue_headroom_history.clear();
    Ok(())
}

pub fn set_volume(vol: f32) -> Result<(), String> {
    let _scope = profiler::scope("audio::player::set_volume");
    let state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    *state.volume.lock().unwrap_or_else(|e| e.into_inner()) = vol;
    Ok(())
}

pub fn set_motor_audio_enabled(enabled: bool) -> Result<(), String> {
    let state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    state.haptic_enabled.store(enabled, Ordering::SeqCst);
    state
        .haptic_queue
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .clear();
    Ok(())
}

pub fn drain_motor_audio_control_points(max_points: i32) -> Vec<f64> {
    let state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    if !state.haptic_enabled.load(Ordering::Relaxed) {
        return Vec::new();
    }

    let mut queue = state.haptic_queue.lock().unwrap_or_else(|e| e.into_inner());
    let count = (max_points.max(0) as usize).min(queue.len());
    let mut values = Vec::with_capacity(count * 2);
    for _ in 0..count {
        let Some(point) = queue.pop_front() else {
            break;
        };
        values.push(point.amplitude as f64);
        values.push(point.frequency_position as f64);
    }
    values
}

pub fn motor_audio_frame_duration_ms() -> i32 {
    HAPTIC_FRAME_DURATION_MS as i32
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

#[cfg(test)]
mod motor_audio_tests {
    use super::*;

    #[test]
    fn silence_produces_zero_amplitude_control_points() {
        let queue = Mutex::new(VecDeque::new());
        let mut analyzer = HapticAnalyzer::new(1_000, 1);
        analyzer.push(&vec![0.0; 20], 1.0, &queue);

        let points = queue.lock().unwrap();
        assert_eq!(points.len(), 2);
        assert!(points.iter().all(|point| point.amplitude == 0.0));
    }

    #[test]
    fn alternating_signal_produces_audible_motor_envelope() {
        let queue = Mutex::new(VecDeque::new());
        let mut analyzer = HapticAnalyzer::new(1_000, 1);
        let samples = (0..20)
            .map(|index| if index % 2 == 0 { -0.5 } else { 0.5 })
            .collect::<Vec<_>>();
        analyzer.push(&samples, 1.0, &queue);

        let points = queue.lock().unwrap();
        assert_eq!(points.len(), 2);
        assert!(points.iter().any(|point| point.amplitude > 0.2));
        assert!(points.iter().all(|point| point.frequency_position > 0.5));
    }

    #[test]
    fn control_point_queue_stays_bounded_to_limit_latency() {
        let queue = Mutex::new(VecDeque::new());
        let mut analyzer = HapticAnalyzer::new(1_000, 1);
        analyzer.push(&vec![0.4; 2_000], 1.0, &queue);

        assert_eq!(queue.lock().unwrap().len(), MAX_HAPTIC_QUEUE_POINTS);
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
