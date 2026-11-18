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
use crate::audio::hitsound::{HitSoundBank, HitSoundConfig, HitSoundMixer, HitTimeline};
use crate::audio::profiler;
use crate::audio::rubberband::RubberBandPitchShifter;
use crate::audio::sample::{finite_sample, OutputSample, TpdfDither};
use std::path::Path;

#[derive(Clone, Copy, Debug)]
struct AudioTimelineSegment {
    remaining_out_frames: usize,
    source_frame: f64,
    source_frames_per_out_frame: f64,
}

struct BufferState {
    samples: VecDeque<f64>,
    segments: VecDeque<AudioTimelineSegment>,
}

// Thread-safe ring buffer / FIFO used to bridge the decode thread and the cpal
// hardware callback thread while tracking the source-song frame position of
// every buffered output frame.
pub struct AudioBuffer {
    data: Mutex<BufferState>,
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

#[derive(Default)]
struct HitSoundShared {
    se_dir: Mutex<Option<String>>,
    chart_path: Mutex<Option<String>>,
    config: Mutex<HitSoundConfig>,
    se_revision: AtomicU64,
    chart_revision: AtomicU64,
}

impl HitSoundShared {
    fn set_se_dir(&self, dir: Option<String>) {
        let mut guard = self.se_dir.lock().unwrap_or_else(|e| e.into_inner());
        if *guard != dir {
            *guard = dir;
            self.se_revision.fetch_add(1, Ordering::Release);
        }
    }

    fn update(&self, chart_path: Option<String>, config: HitSoundConfig) {
        {
            let mut chart_guard = self.chart_path.lock().unwrap_or_else(|e| e.into_inner());
            if *chart_guard != chart_path {
                *chart_guard = chart_path;
                self.chart_revision.fetch_add(1, Ordering::Release);
            }
        }
        *self.config.lock().unwrap_or_else(|e| e.into_inner()) = config;
    }
}

#[derive(Clone)]
struct ProcessingParams {
    pitch: Arc<Mutex<f64>>,
    algo: Arc<Mutex<String>>,
    loudness_normalization_gain: Arc<Mutex<f32>>,
    quality_settings: Arc<Mutex<AudioQualitySettings>>,
    clipped_sample_count: Arc<AtomicU64>,
    peak_bits: Arc<AtomicU64>,
    hitsound: Arc<HitSoundShared>,
}

struct ProcessedBlock {
    samples: Vec<f64>,
    source_start_frame: f64,
    source_frames: f64,
}

struct DecodePipeline {
    decoder: StreamDecoder,
    block_frames: usize,
    sample_rate: u32,
    channels: u32,
    params: ProcessingParams,
    pending_output: Option<ProcessedBlock>,
    source_position_frames: f64,
    hitsound_mixer: HitSoundMixer,
    cached_se_rev: u64,
    cached_bank: Option<HitSoundBank>,
    cached_chart_rev: u64,
    cached_timeline: Option<HitTimeline>,
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
            pending_output: None,
            source_position_frames: 0.0,
            hitsound_mixer: HitSoundMixer::new(),
            cached_se_rev: u64::MAX,
            cached_bank: None,
            cached_chart_rev: u64::MAX,
            cached_timeline: None,
        })
    }

    fn seek(&mut self, secs: f64) -> Result<(), String> {
        let _scope = profiler::scope("audio::player::DecodePipeline::seek");
        self.decoder.seek(secs)?;
        self.pending_output = None;
        self.hitsound_mixer.reset();
        self.source_position_frames = secs.max(0.0) * self.sample_rate as f64;
        Ok(())
    }

    fn mix_hitsounds(&mut self, samples: &mut [f64], source_start_frame: f64, source_frames: f64) {
        if samples.is_empty() || self.channels == 0 {
            return;
        }

        let se_rev = self.params.hitsound.se_revision.load(Ordering::Acquire);
        if se_rev != self.cached_se_rev {
            let dir_opt = self
                .params
                .hitsound
                .se_dir
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .clone();
            self.cached_bank = dir_opt.and_then(|dir| {
                HitSoundBank::load_from_dir(Path::new(&dir), self.sample_rate, self.channels).ok()
            });
            self.cached_se_rev = se_rev;
        }

        let chart_rev = self.params.hitsound.chart_revision.load(Ordering::Acquire);
        if chart_rev != self.cached_chart_rev {
            let chart_opt = self
                .params
                .hitsound
                .chart_path
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .clone();
            self.cached_timeline =
                chart_opt.and_then(|path| HitTimeline::load_file(Path::new(&path)).ok());
            self.cached_chart_rev = chart_rev;
            self.hitsound_mixer.reset();
        }

        let cfg = *self
            .params
            .hitsound
            .config
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        if let (Some(bank), Some(timeline)) = (&self.cached_bank, &self.cached_timeline) {
            self.hitsound_mixer.mix_block_scaled(
                samples,
                self.channels as usize,
                self.sample_rate,
                source_start_frame,
                source_frames,
                &cfg,
                bank,
                timeline,
            );
        }
    }

    fn finalize_block(
        &mut self,
        mut samples: Vec<f64>,
        source_frames: f64,
        peak_protection_enabled: bool,
    ) -> ProcessedBlock {
        let source_start_frame = self.source_position_frames;
        self.source_position_frames += source_frames;
        self.mix_hitsounds(&mut samples, source_start_frame, source_frames);
        let total_gain = *self
            .params
            .loudness_normalization_gain
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        if total_gain != 1.0 {
            for sample in samples.iter_mut() {
                *sample *= total_gain as f64;
            }
        }

        {
            let _protection_scope =
                profiler::scope("audio::player::DecodePipeline::post_dsp_protection");
            apply_post_dsp_protection(
                &mut samples,
                peak_protection_enabled,
                &self.params.clipped_sample_count,
                &self.params.peak_bits,
            );
        }
        ProcessedBlock {
            samples,
            source_start_frame,
            source_frames,
        }
    }

    fn next_block(
        &mut self,
        rubberband_shifter: &mut Option<RubberBandPitchShifter>,
        vocal_only_shifter: &mut Option<VocalOnlyPitchProcessor>,
    ) -> Result<Option<ProcessedBlock>, String> {
        let _scope = profiler::scope("audio::player::DecodePipeline::next_block");
        if let Some(pending) = self.pending_output.take() {
            return Ok(Some(pending));
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

        let block = self.decoder.read_block(self.block_frames)?;
        if block.is_empty() {
            let tail = if vocal_only_active {
                vocal_only_shifter.as_mut().map(VocalOnlyPitchProcessor::finish)
            } else {
                rubberband_shifter.as_mut().map(RubberBandPitchShifter::finish)
            };
            if let Some(tail) = tail.filter(|t| !t.is_empty()) {
                let tail: Vec<f64> = tail.into_iter().map(f64::from).collect();
                let frames = (tail.len() / self.channels.max(1) as usize) as f64;
                return Ok(Some(self.finalize_block(
                    tail,
                    frames,
                    current_quality.peak_protection_enabled,
                )));
            }
            return Ok(None);
        }

        let in_frames = block.len() / self.channels.max(1) as usize;
        let (processed, source_frames) = if current_pitch.abs() > 0.01 && self.channels == 2 {
            let _pitch_scope = profiler::scope("audio::player::DecodePipeline::pitch_shift");
            let pitch_factor = 2.0f64.powf(current_pitch / 12.0);
            let block_f32: Vec<f32> = block.iter().map(|&s| s as f32).collect();
            match current_algo.as_str() {
                "resample" => {
                    *rubberband_shifter = None;
                    *vocal_only_shifter = None;
                    let shifted: Vec<f64> = dsp::pitch_shift_resample(&block_f32, pitch_factor)
                        .into_iter()
                        .map(f64::from)
                        .collect();
                    (shifted, in_frames as f64)
                }
                _ => {
                    let shifted = if vocal_only_active {
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
                            shifter.process(&block_f32, pitch_factor)
                        } else {
                            block_f32
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
                            shifter.process(&block_f32, pitch_factor)
                        } else {
                            block_f32
                        }
                    };
                    let shifted_f64: Vec<f64> = shifted.into_iter().map(f64::from).collect();
                    let out_frames = (shifted_f64.len() / self.channels.max(1) as usize) as f64;
                    (shifted_f64, out_frames)
                }
            }
        } else {
            *rubberband_shifter = None;
            *vocal_only_shifter = None;
            (block, in_frames as f64)
        };

        if processed.is_empty() {
            return Ok(Some(ProcessedBlock {
                samples: processed,
                source_start_frame: self.source_position_frames,
                source_frames: 0.0,
            }));
        }

        Ok(Some(self.finalize_block(
            processed,
            source_frames,
            current_quality.peak_protection_enabled,
        )))
    }
}

impl AudioBuffer {
    pub fn new(capacity: usize) -> Self {
        let _scope = profiler::scope("audio::player::AudioBuffer::new");
        Self {
            data: Mutex::new(BufferState {
                samples: VecDeque::with_capacity(capacity),
                segments: VecDeque::new(),
            }),
            capacity,
            len_samples: AtomicUsize::new(0),
        }
    }

    /// Push samples, blocking (backpressure) until there is room. Aborts early (discarding
    /// the block) if `stop_flag` becomes set, so the decode thread can always be joined even
    /// when the output stream is paused and therefore not draining the buffer.
    pub fn push(&self, samples: &[f64], stop_flag: &AtomicBool) {
        self.push_timed(samples, 2, 0.0, 0.0, stop_flag);
    }

    pub fn push_timed(
        &self,
        samples: &[f64],
        channels: usize,
        source_start_frame: f64,
        source_frames: f64,
        stop_flag: &AtomicBool,
    ) {
        let _scope = profiler::scope("audio::player::AudioBuffer::push");
        let ch = channels.max(1);
        let max_chunk_samples = ((self.capacity / ch).max(1)) * ch;
        let total_out_frames = samples.len() / ch;
        let mut cursor_src_frame = source_start_frame;

        for chunk in samples.chunks(max_chunk_samples.max(1)) {
            let chunk_frames = chunk.len() / ch;
            let chunk_src_frames = if total_out_frames > 0 && source_frames > 0.0 {
                source_frames * (chunk_frames as f64 / total_out_frames as f64)
            } else {
                0.0
            };
            loop {
                if stop_flag.load(Ordering::SeqCst) {
                    return;
                }
                if self.try_push_timed(chunk, ch, cursor_src_frame, chunk_src_frames) {
                    break;
                }
                thread::sleep(Duration::from_millis(2));
            }
            cursor_src_frame += chunk_src_frames;
        }
    }

    pub fn try_push(&self, samples: &[f64]) -> bool {
        self.try_push_timed(samples, 2, 0.0, 0.0)
    }

    pub fn try_push_timed(
        &self,
        samples: &[f64],
        channels: usize,
        source_start_frame: f64,
        source_frames: f64,
    ) -> bool {
        let _scope = profiler::scope("audio::player::AudioBuffer::try_push");
        let mut queue = self.data.lock().unwrap_or_else(|e| e.into_inner());
        if queue.samples.len() + samples.len() > self.capacity {
            return false;
        }
        queue.samples.extend(samples.iter().cloned());
        let ch = channels.max(1);
        let out_frames = samples.len() / ch;
        if out_frames > 0 {
            let rate = if source_frames > 0.0 {
                source_frames / out_frames as f64
            } else {
                1.0
            };
            queue.segments.push_back(AudioTimelineSegment {
                remaining_out_frames: out_frames,
                source_frame: source_start_frame,
                source_frames_per_out_frame: rate,
            });
        }
        self.len_samples.fetch_add(samples.len(), Ordering::Relaxed);
        true
    }

    pub fn capacity(&self) -> usize {
        self.capacity
    }

    #[cfg(test)]
    fn pop<T: OutputSample>(
        &self,
        out: &mut [T],
        channels: usize,
        volume: f64,
        dither: &mut TpdfDither,
        enabled: bool,
    ) -> usize {
        self.pop_with_timeline(out, channels, volume, dither, enabled).0
    }

    fn pop_with_timeline<T: OutputSample>(
        &self,
        out: &mut [T],
        channels: usize,
        volume: f64,
        dither: &mut TpdfDither,
        enabled: bool,
    ) -> (usize, Option<(f64, f64)>) {
        let _scope = profiler::scope("audio::player::AudioBuffer::pop");
        let mut queue = self.data.lock().unwrap_or_else(|e| e.into_inner());
        let len = out.len().min(queue.samples.len()) / channels * channels;
        for i in 0..len {
            out[i] = T::encode(
                queue.samples.pop_front().unwrap_or(0.0) * volume,
                dither,
                enabled,
            );
        }
        let mut timeline_update = None;
        if len > 0 {
            self.len_samples.fetch_sub(len, Ordering::Relaxed);
            let mut remaining = len / channels;
            while remaining > 0 {
                let Some(mut seg) = queue.segments.pop_front() else {
                    break;
                };
                if seg.remaining_out_frames <= remaining {
                    remaining -= seg.remaining_out_frames;
                    let end_frame = seg.source_frame
                        + seg.remaining_out_frames as f64 * seg.source_frames_per_out_frame;
                    timeline_update = Some((end_frame, seg.source_frames_per_out_frame));
                } else {
                    seg.remaining_out_frames -= remaining;
                    seg.source_frame += remaining as f64 * seg.source_frames_per_out_frame;
                    timeline_update = Some((seg.source_frame, seg.source_frames_per_out_frame));
                    queue.segments.push_front(seg);
                    remaining = 0;
                }
            }
        }
        out[len..].fill(T::SILENCE);
        (len, timeline_update)
    }

    pub fn clear(&self) {
        let _scope = profiler::scope("audio::player::AudioBuffer::clear");
        let mut queue = self.data.lock().unwrap_or_else(|e| e.into_inner());
        queue.samples.clear();
        queue.segments.clear();
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

fn effective_playback_rate(pitch: f64, algo: &str, channels: u32) -> f64 {
    if channels == 2 && algo == "resample" && pitch.abs() > 0.01 {
        let factor = 2.0f64.powf(pitch / 12.0);
        if factor.is_finite() && factor > 0.0 && (factor - 1.0).abs() >= 0.001 {
            return factor;
        }
    }
    1.0
}

struct PlayerState {
    thread_handle: Option<thread::JoinHandle<()>>,
    stream: Option<SendStream>,
    buffer: Option<Arc<AudioBuffer>>,
    stop_flag: Arc<AtomicBool>,
    seek_request: Arc<Mutex<Option<f64>>>,
    source_frame_bits: Arc<AtomicU64>,
    playback_rate_bits: Arc<AtomicU64>,
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
    hitsound: Arc<HitSoundShared>,
}

lazy_static::lazy_static! {
    static ref GLOBAL_PLAYER: Mutex<PlayerState> = Mutex::new(PlayerState {
        thread_handle: None,
        stream: None,
        buffer: None,
        stop_flag: Arc::new(AtomicBool::new(false)),
        seek_request: Arc::new(Mutex::new(None)),
        source_frame_bits: Arc::new(AtomicU64::new(0.0f64.to_bits())),
        playback_rate_bits: Arc::new(AtomicU64::new(1.0f64.to_bits())),
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
        hitsound: Arc::new(HitSoundShared::default()),
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

    let ch = (pipeline.channels as usize).max(1);
    while buffer.len() < target_samples && !stop_flag.load(Ordering::SeqCst) {
        let Some(block) = pipeline.next_block(rubberband_shifter, vocal_only_shifter)? else {
            break;
        };
        if block.samples.is_empty() {
            continue;
        }
        if !buffer.try_push_timed(
            &block.samples,
            ch,
            block.source_start_frame,
            block.source_frames,
        ) {
            pipeline.pending_output = Some(block);
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
    source_frame_bits: Arc<AtomicU64>,
    playback_rate_bits: Arc<AtomicU64>,
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
                let sf = source_frame_bits.clone();
                let pr = playback_rate_bits.clone();
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
                            let (n, timeline) =
                                buf.pop_with_timeline(data, ch, volume, &mut dither, enabled);
                            if n < data.len() {
                                uc.fetch_add(1, Ordering::Relaxed);
                            }
                            if let Some((src_frame, rate)) = timeline {
                                sf.store(src_frame.to_bits(), Ordering::Relaxed);
                                pr.store(rate.to_bits(), Ordering::Relaxed);
                            }
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
    chart_path: Option<String>,
    hitsound_enabled: bool,
    hitsound_volume: f32,
    hitsound_offset_ms: i32,
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
    state.hitsound.update(
        chart_path,
        HitSoundConfig {
            enabled: hitsound_enabled,
            volume: f64::from(hitsound_volume).clamp(0.0, 1.5),
            offset_ms: hitsound_offset_ms.clamp(-500, 500),
        },
    );

    let stop_flag = Arc::new(AtomicBool::new(false));
    let seek_request = Arc::new(Mutex::new(None));
    let source_frame_bits = Arc::new(AtomicU64::new(0.0f64.to_bits()));
    let playback_rate_bits = Arc::new(AtomicU64::new(1.0f64.to_bits()));
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
        hitsound: state.hitsound.clone(),
    };

    let (stream, output_info, buffer) = build_output(
        source,
        source_frame_bits.clone(),
        playback_rate_bits.clone(),
        underrun_count.clone(),
        volume.clone(),
        quality_settings.clone(),
        output_buffer_ms,
        output_latency_mode,
    )?;
    let sample_rate = output_info.sample_rate;
    let channels = output_info.channels;
    let initial_rate = effective_playback_rate(
        *pitch.lock().unwrap_or_else(|e| e.into_inner()),
        &algo.lock().unwrap_or_else(|e| e.into_inner()),
        channels,
    );
    playback_rate_bits.store(initial_rate.to_bits(), Ordering::Relaxed);
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
    state.source_frame_bits = source_frame_bits.clone();
    state.playback_rate_bits = playback_rate_bits.clone();
    state.stream_finished = stream_finished.clone();
    state.volume = volume.clone();
    state.pitch = pitch.clone();
    state.algo = algo.clone();
    state.loudness_normalization_gain = norm_gain.clone();
    state.output_info = Arc::new(Mutex::new(output_info));
    state.underrun_count = underrun_count.clone();
    state.clipped_sample_count = clipped_sample_count.clone();
    state.peak_bits = peak_bits.clone();

    let thread_pitch = pitch.clone();
    let thread_algo = algo.clone();
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
                        buffer.clear();
                        if let Err(e) = pipeline.seek(sec) {
                            eprintln!("Seek error: {}", e);
                        }
                        if let Some(shifter) = &mut rubberband_shifter {
                            shifter.reset();
                        }
                        if let Some(shifter) = &mut vocal_only_shifter {
                            shifter.reset();
                        }
                        // A seek starts a fresh five-second headroom window.
                        stream_finished.store(false, Ordering::SeqCst);
                        source_frame_bits.store(
                            (sec.max(0.0) * sample_rate as f64).to_bits(),
                            Ordering::SeqCst,
                        );
                        let rate = effective_playback_rate(
                            *thread_pitch.lock().unwrap_or_else(|e| e.into_inner()),
                            &thread_algo.lock().unwrap_or_else(|e| e.into_inner()),
                            channels,
                        );
                        playback_rate_bits.store(rate.to_bits(), Ordering::Relaxed);
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

                if block.samples.is_empty() {
                    continue;
                }
                {
                    let _push_scope = profiler::scope("audio::player::AudioBuffer::push_wait");
                    buffer.push_timed(
                        &block.samples,
                        channels as usize,
                        block.source_start_frame,
                        block.source_frames,
                        &stop_flag,
                    );
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
    state.source_frame_bits.store(
        (secs.max(0.0) * state.sample_rate as f64).to_bits(),
        Ordering::SeqCst,
    );
    let rate = effective_playback_rate(
        *state.pitch.lock().unwrap_or_else(|e| e.into_inner()),
        &state.algo.lock().unwrap_or_else(|e| e.into_inner()),
        state.channels,
    );
    state
        .playback_rate_bits
        .store(rate.to_bits(), Ordering::Relaxed);
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
    let rate = effective_playback_rate(pitch_val, &pitch_algo, state.channels);
    *state.pitch.lock().unwrap_or_else(|e| e.into_inner()) = pitch_val;
    *state.algo.lock().unwrap_or_else(|e| e.into_inner()) = pitch_algo;
    if state.buffer.as_ref().is_none_or(|b| b.len() == 0) {
        state
            .playback_rate_bits
            .store(rate.to_bits(), Ordering::Relaxed);
    }
    Ok(())
}

pub fn configure_hitsound_bank(se_dir: Option<String>) -> Result<(), String> {
    let _scope = profiler::scope("audio::player::configure_hitsound_bank");
    let state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    state.hitsound.set_se_dir(se_dir);
    Ok(())
}

pub fn update_playback_hitsound(
    chart_path: Option<String>,
    enabled: bool,
    volume: f32,
    offset_ms: i32,
) -> Result<(), String> {
    let _scope = profiler::scope("audio::player::update_playback_hitsound");
    let state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    state.hitsound.update(
        chart_path,
        HitSoundConfig {
            enabled,
            volume: f64::from(volume).clamp(0.0, 1.5),
            offset_ms: offset_ms.clamp(-500, 500),
        },
    );
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
/// Snapshot polled by the UI progress timer.
#[derive(Clone, Copy, Debug)]
pub struct PlaybackProgress {
    pub position_secs: f64,
    /// Effective source-timeline speed (`1.0` normally; scales under `resample` pitch shift).
    pub playback_rate: f64,
    /// The stream reached its end and every queued sample has been played.
    pub finished: bool,
}

pub fn get_progress() -> PlaybackProgress {
    let _scope = profiler::scope("audio::player::get_progress");
    let state = GLOBAL_PLAYER.lock().unwrap_or_else(|e| e.into_inner());
    let source_frames = f64::from_bits(state.source_frame_bits.load(Ordering::Relaxed));
    let raw_rate = f64::from_bits(state.playback_rate_bits.load(Ordering::Relaxed));
    let playback_rate = if raw_rate.is_finite() && raw_rate > 0.0 {
        raw_rate
    } else {
        1.0
    };
    PlaybackProgress {
        position_secs: if state.sample_rate == 0 || !source_frames.is_finite() {
            0.0
        } else {
            (source_frames / state.sample_rate as f64).max(0.0)
        },
        playback_rate,
        finished: state.stream_finished.load(Ordering::Relaxed),
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
            hitsound: Arc::new(HitSoundShared::default()),
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
            pipeline.pending_output.is_some(),
            "test must fill beyond queue capacity"
        );
        let mut output = vec![0i32; buffer.len()];
        let mut dither = TpdfDither::new(123);
        let len = output.len();
        assert_eq!(buffer.pop(&mut output, 2, 1.0, &mut dither, true), len);
        while let Some(block) = pipeline.next_block(&mut rubberband, &mut vocal).unwrap() {
            output.extend(
                block
                    .samples
                    .into_iter()
                    .map(|s| i32::encode(s, &mut dither, true)),
            );
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
            Arc::new(AtomicU64::new(1.0f64.to_bits())),
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

    #[test]
    fn decode_pipeline_mixes_hitsounds_with_live_toggle_and_seek_reset() {
        struct TempDir(std::path::PathBuf);
        impl Drop for TempDir {
            fn drop(&mut self) {
                let _ = std::fs::remove_dir_all(&self.0);
            }
        }

        let dir = TempDir(std::env::temp_dir().join(format!(
            "aetheria-pipeline-hs-{}",
            std::process::id()
        )));
        let se_dir = dir.0.join("se");
        std::fs::create_dir_all(&se_dir).unwrap();

        let silence = vec![0.0f64; 48000 * 2];
        let track = TestWav::float(48000, 2, &silence);
        let tap_clip = vec![0.5f64; 200 * 2];
        let tap_wav = TestWav::float(48000, 2, &tap_clip);
        std::fs::copy(tap_wav.path(), se_dir.join("tap.wav")).unwrap();

        let chart_path = dir.0.join("chart.json");
        std::fs::write(&chart_path, r#"{"notes":[[0.10,1],[0.80,1]]}"#).unwrap();
        let chart_str = chart_path.to_string_lossy().into_owned();

        let shared_params = params();
        let hitsound = shared_params.hitsound.clone();
        hitsound.set_se_dir(Some(se_dir.to_string_lossy().into_owned()));
        hitsound.update(
            Some(chart_str.clone()),
            HitSoundConfig {
                enabled: true,
                volume: 1.0,
                offset_ms: 0,
            },
        );

        let mut pipeline = DecodePipeline::new(track.path(), 48000, 2, shared_params).unwrap();
        let mut rubberband = None;
        let mut vocal = None;

        let mut out1 = Vec::new();
        while out1.len() < 12000 * 2 {
            let block = pipeline
                .next_block(&mut rubberband, &mut vocal)
                .unwrap()
                .expect("expected initial audio blocks");
            out1.extend(block.samples);
        }
        assert!(
            out1.len() < 36000 * 2,
            "initial read exceeded safe pre-second-note window"
        );
        assert!(
            out1[..4800 * 2].iter().all(|s| s.abs() < 1e-6),
            "frames before first hit note must stay silent"
        );
        let first_hit_peak = out1[4800 * 2..5000 * 2]
            .iter()
            .fold(0.0f64, |acc, s| acc.max(s.abs()));
        assert!(
            first_hit_peak > 0.25,
            "expected audible tap hit at 0.10s, got peak {first_hit_peak}"
        );

        hitsound.update(
            Some(chart_str.clone()),
            HitSoundConfig {
                enabled: false,
                volume: 1.0,
                offset_ms: 0,
            },
        );
        let mut out2 = Vec::new();
        while let Some(block) = pipeline.next_block(&mut rubberband, &mut vocal).unwrap() {
            out2.extend(block.samples);
        }
        assert!(
            out2.iter().all(|s| s.abs() < 1e-6),
            "live disabling hitsounds must silence upcoming 0.80s hit"
        );

        hitsound.update(
            Some(chart_str),
            HitSoundConfig {
                enabled: true,
                volume: 1.0,
                offset_ms: 0,
            },
        );
        *pipeline.params.loudness_normalization_gain.lock().unwrap() = 0.5;
        pipeline.seek(0.05).unwrap();
        let mut out3 = Vec::new();
        while let Some(block) = pipeline.next_block(&mut rubberband, &mut vocal).unwrap() {
            out3.extend(block.samples);
        }
        let post_seek_first = out3[..8000 * 2]
            .iter()
            .fold(0.0f64, |acc, s| acc.max(s.abs()));
        let post_seek_second = out3[30000 * 2..]
            .iter()
            .fold(0.0f64, |acc, s| acc.max(s.abs()));
        assert!(
            (post_seek_first - 0.5 * first_hit_peak).abs() < 1e-6
                && (post_seek_second - post_seek_first).abs() < 1e-6,
            "seek reset must allow 0.10s and 0.80s hitsounds to trigger again: {post_seek_first}, {post_seek_second}"
        );
    }

    #[test]
    fn decode_pipeline_resample_tracks_source_timeline_across_speed_and_seek() {
        struct TempDir(std::path::PathBuf);
        impl Drop for TempDir {
            fn drop(&mut self) {
                let _ = std::fs::remove_dir_all(&self.0);
            }
        }

        let dir = TempDir(std::env::temp_dir().join(format!(
            "aetheria-resample-tl-{}",
            std::process::id()
        )));
        let se_dir = dir.0.join("se");
        std::fs::create_dir_all(&se_dir).unwrap();

        let total_src_frames = 48000usize;
        let silence = vec![0.0f64; total_src_frames * 2];
        let track = TestWav::float(48000, 2, &silence);
        let tap_clip = vec![0.5f64; 100 * 2];
        let tap_wav = TestWav::float(48000, 2, &tap_clip);
        std::fs::copy(tap_wav.path(), se_dir.join("tap.wav")).unwrap();

        let chart_path = dir.0.join("chart.json");
        std::fs::write(&chart_path, r#"{"notes":[[0.40,1]]}"#).unwrap();

        let shared_params = params();
        *shared_params.pitch.lock().unwrap() = 12.0; // +12 st = 2.0x speed
        *shared_params.algo.lock().unwrap() = "resample".to_string();
        shared_params
            .hitsound
            .set_se_dir(Some(se_dir.to_string_lossy().into_owned()));
        shared_params.hitsound.update(
            Some(chart_path.to_string_lossy().into_owned()),
            HitSoundConfig {
                enabled: true,
                volume: 1.0,
                offset_ms: 0,
            },
        );

        let mut pipeline =
            DecodePipeline::new(track.path(), 48000, 2, shared_params.clone()).unwrap();
        let buffer = AudioBuffer::new(48000 * 2);
        let mut rubberband = None;
        let mut vocal = None;

        // Play first half in 2.0x resample, then switch live back to 1.0x bypass.
        let mut played_out_samples = Vec::new();
        let mut last_timeline = (0.0f64, 1.0f64);
        let mut dither = TpdfDither::new(7);
        let mut out_chunk = [0.0f64; 1024];

        let b1 = pipeline
            .next_block(&mut rubberband, &mut vocal)
            .unwrap()
            .unwrap();
        assert!((b1.source_frames / (b1.samples.len() / 2) as f64 - 2.0).abs() < 0.01);
        assert!(buffer.try_push_timed(&b1.samples, 2, b1.source_start_frame, b1.source_frames));

        // Switch pitch off while remainder decodes.
        *shared_params.pitch.lock().unwrap() = 0.0;
        while let Some(block) = pipeline.next_block(&mut rubberband, &mut vocal).unwrap() {
            assert!(buffer.try_push_timed(
                &block.samples,
                2,
                block.source_start_frame,
                block.source_frames
            ));
        }

        let mut observed_rates = Vec::new();
        loop {
            let (n, tl) = buffer.pop_with_timeline(&mut out_chunk, 2, 1.0, &mut dither, false);
            if n == 0 {
                break;
            }
            played_out_samples.extend_from_slice(&out_chunk[..n]);
            if let Some((sf, rate)) = tl {
                assert!(
                    sf >= last_timeline.0,
                    "source timeline regressed across live speed switch: {} -> {sf}",
                    last_timeline.0
                );
                last_timeline = (sf, rate);
                observed_rates.push(rate);
            }
        }
        assert!((last_timeline.0 - total_src_frames as f64).abs() < 4.0);
        assert!(observed_rates.first().is_some_and(|&r| (r - 2.0).abs() < 0.01));
        assert!(observed_rates.last().is_some_and(|&r| (r - 1.0).abs() < 0.01));

        // Seek back to 0.20s at 2.0x resample: note at 0.40s chart time must trigger ~0.10s (4800 frames) after seek!
        *shared_params.pitch.lock().unwrap() = 12.0;
        buffer.clear();
        pipeline.seek(0.20).unwrap();
        let mut after_seek = Vec::new();
        while let Some(block) = pipeline.next_block(&mut rubberband, &mut vocal).unwrap() {
            assert!(buffer.try_push_timed(
                &block.samples,
                2,
                block.source_start_frame,
                block.source_frames
            ));
            loop {
                let (n, _) = buffer.pop_with_timeline(&mut out_chunk, 2, 1.0, &mut dither, false);
                if n == 0 {
                    break;
                }
                after_seek.extend_from_slice(&out_chunk[..n]);
            }
        }
        let early_peak = after_seek[..4600 * 2]
            .iter()
            .fold(0.0f64, |acc, s| acc.max(s.abs()));
        let accelerated_hit_peak = after_seek[4700 * 2..5000 * 2]
            .iter()
            .fold(0.0f64, |acc, s| acc.max(s.abs()));
        assert!(early_peak < 1e-6);
        assert!(accelerated_hit_peak > 0.25);
    }
}
