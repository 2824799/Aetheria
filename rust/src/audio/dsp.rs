use crate::audio::profiler;
use std::fs::File;
use std::path::Path;
use symphonia::core::audio::{AudioBufferRef, Channels, SampleBuffer};
use symphonia::core::codecs::{Decoder, DecoderOptions, CODEC_TYPE_NULL};
use symphonia::core::errors::Error;
use symphonia::core::formats::{FormatOptions, FormatReader, SeekMode, SeekTo, Track};
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;
use symphonia::core::units::{Time, TimeBase};

const RESAMPLE_EPSILON: f64 = 0.000_001;
const STANDARD_SINC_HALF_TAPS: usize = 32;
const HIGH_QUALITY_SINC_HALF_TAPS: usize = 96;

/// Opens `path` and probes its container format.
pub fn open_format(path: &str) -> Result<Box<dyn FormatReader>, String> {
    let file = File::open(path).map_err(|e| e.to_string())?;
    let stream = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();
    if let Some(extension) = Path::new(path).extension().and_then(|e| e.to_str()) {
        hint.with_extension(extension);
    }
    symphonia::default::get_probe()
        .format(
            &hint,
            stream,
            &FormatOptions::default(),
            &MetadataOptions::default(),
        )
        .map(|probed| probed.format)
        .map_err(|e| e.to_string())
}

/// The first track that carries decodable audio.
pub fn default_track(format: &dyn FormatReader) -> Result<&Track, String> {
    format
        .tracks()
        .iter()
        .find(|track| track.codec_params.codec != CODEC_TYPE_NULL)
        .ok_or_else(|| "No audio track found".to_string())
}

fn make_decoder(track: &Track) -> Result<Box<dyn Decoder>, String> {
    symphonia::default::get_codecs()
        .make(&track.codec_params, &DecoderOptions::default())
        .map_err(|e| e.to_string())
}

/// How much of a file a loudness measurement decodes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LoudnessScan {
    /// Roughly the first 5-10 seconds; fast enough to run during import.
    Quick,
    /// The whole file; used when the user asks for a metadata refresh.
    Full,
}

const QUICK_LOUDNESS_PACKETS: usize = 300;

/// Average RMS level of an audio file in dBFS, clamped to `-60.0..=0.0`.
///
/// Fails when the file yields no decodable samples, so callers never store a
/// made-up level.
pub fn calculate_loudness(path: &str, scan: LoudnessScan) -> Result<f64, String> {
    let _scope = profiler::scope(match scan {
        LoudnessScan::Quick => "audio::dsp::calculate_loudness",
        LoudnessScan::Full => "audio::dsp::calculate_loudness_full",
    });
    let mut format = open_format(path)?;
    let track = default_track(format.as_ref())?;
    let track_id = track.id;
    let mut decoder = make_decoder(track)?;

    let mut sample_count = 0u64;
    let mut sum_squares = 0.0f64;
    let mut packet_count = 0usize;
    loop {
        let packet = match format.next_packet() {
            Ok(packet) => packet,
            Err(Error::IoError(ref e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
            Err(e) => return Err(e.to_string()),
        };
        if packet.track_id() != track_id {
            continue;
        }
        let decoded = match decoder.decode(&packet) {
            Ok(buffer) => buffer,
            Err(Error::DecodeError(_)) => continue,
            Err(e) => return Err(e.to_string()),
        };
        let (samples, _) = packet_to_interleaved_f64(&decoded);
        for sample in samples.into_iter().filter(|sample| sample.is_finite()) {
            sum_squares += sample * sample;
            sample_count += 1;
        }
        packet_count += 1;
        if scan == LoudnessScan::Quick && packet_count > QUICK_LOUDNESS_PACKETS {
            break;
        }
    }

    if sample_count == 0 {
        return Err("No decodable audio samples".to_string());
    }
    let rms = (sum_squares / sample_count as f64).sqrt();
    Ok((20.0 * rms.log10()).clamp(-60.0, 0.0))
}

#[derive(Clone, Copy, Debug)]
pub(crate) struct SourceFormat {
    pub sample_rate: u32,
    pub channels: u16,
    pub precision_bits: u32,
}

pub(crate) fn probe_source_format(path: &str) -> Result<SourceFormat, String> {
    let format = open_format(path)?;
    let params = &default_track(format.as_ref())?.codec_params;
    Ok(SourceFormat {
        sample_rate: params.sample_rate.unwrap_or(0),
        channels: params.channels.map_or(2, |c| c.count() as u16),
        precision_bits: params.bits_per_sample.unwrap_or(24),
    })
}

// ===================== Streaming decoder =====================

/// Streaming audio decoder that decodes a file packet-by-packet and resamples in real time
/// to the target sample rate / channel layout used by the hardware output. This avoids the
/// memory blow-up and startup latency of decoding an entire file into RAM.
pub struct StreamDecoder {
    format: Box<dyn FormatReader>,
    decoder: Box<dyn Decoder>,
    track_id: u32,
    source_sample_rate: u32,
    time_base: TimeBase,
    seek_target_ts: Option<u64>,
    target_channels: usize,
    target_sample_rate: u32,
    output_frames: u64,
    source_offset: u64,
    passthrough_resample: bool,
    /// decoded f64 samples, already channel-converted to target_channels, at the source sample rate
    src_buffer: Vec<f64>,
    kernel: Option<SincKernel>,
    eof: bool,
}

impl StreamDecoder {
    pub fn new(
        path: &str,
        target_channels: u32,
        target_sample_rate: u32,
        resampler_quality: &str,
    ) -> Result<Self, String> {
        let _scope = profiler::scope("audio::dsp::StreamDecoder::new");
        if target_channels == 0
            || target_channels > 32
            || !(8000..=768000).contains(&target_sample_rate)
        {
            return Err("Unsupported output rate/channel count".to_string());
        }
        let format = open_format(path)?;
        let track = default_track(format.as_ref())?;
        let track_id = track.id;
        let source_sample_rate = track.codec_params.sample_rate.unwrap_or(target_sample_rate);
        let time_base = track
            .codec_params
            .time_base
            .unwrap_or(TimeBase::new(1, source_sample_rate.max(1)));
        let decoder = make_decoder(track)?;

        if source_sample_rate == 0 {
            return Err("Invalid source sample rate".to_string());
        }
        let resample_ratio = target_sample_rate as f64 / source_sample_rate as f64;
        let passthrough_resample = (resample_ratio - 1.0).abs() < RESAMPLE_EPSILON;

        Ok(Self {
            format,
            decoder,
            track_id,
            source_sample_rate,
            time_base,
            seek_target_ts: None,
            target_channels: target_channels as usize,
            target_sample_rate,
            output_frames: 0,
            source_offset: 0,
            passthrough_resample,
            src_buffer: Vec::new(),
            kernel: if passthrough_resample {
                None
            } else {
                Some(SincKernel::new(
                    source_sample_rate,
                    target_sample_rate,
                    resampler_quality,
                )?)
            },
            eof: false,
        })
    }

    /// Decode the next packet from the source and append channel-converted f64 frames to src_buffer.
    /// Returns Ok(false) at end of stream.
    fn decode_next_packet(&mut self) -> Result<bool, String> {
        let _scope = profiler::scope("audio::dsp::StreamDecoder::decode_next_packet");
        if self.eof {
            return Ok(false);
        }
        loop {
            let packet = match self.format.next_packet() {
                Ok(p) => p,
                Err(Error::IoError(ref e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => {
                    self.eof = true;
                    return Ok(false);
                }
                Err(Error::ResetRequired) => continue,
                Err(e) => return Err(e.to_string()),
            };
            if packet.track_id() != self.track_id {
                continue;
            }
            let decoded = {
                let _scope = profiler::scope("audio::dsp::StreamDecoder::decode_packet");
                match self.decoder.decode(&packet) {
                    Ok(b) => b,
                    Err(Error::DecodeError(_)) => continue,
                    Err(e) => return Err(e.to_string()),
                }
            };
            if decoded.spec().rate != self.source_sample_rate {
                return Err("Source sample rate changed during playback".to_string());
            }
            let (inter, source_channels) = packet_to_interleaved_f64(&decoded);
            let mut skip_frames = 0;
            if let Some(target) = self.seek_target_ts {
                let ticks = target.saturating_sub(packet.ts());
                skip_frames = ((ticks as u128
                    * self.time_base.numer as u128
                    * self.source_sample_rate as u128)
                    / self.time_base.denom as u128) as usize;
                if skip_frames >= inter.len() / source_channels {
                    continue;
                }
                self.seek_target_ts = None;
            }
            append_channels(
                &inter[skip_frames * source_channels..],
                decoded.spec().channels,
                self.target_channels,
                &mut self.src_buffer,
            );
            return Ok(true);
        }
    }

    /// Read up to `out_frames` resampled frames (interleaved at target_channels).
    /// Returns fewer frames near end of stream; an empty result signals EOF.
    pub fn read_block(&mut self, out_frames: usize) -> Result<Vec<f64>, String> {
        let _block_scope = profiler::scope("audio::dsp::StreamDecoder::read_block");
        let tc = self.target_channels;
        let mut out: Vec<f64> = Vec::with_capacity(out_frames * tc);

        if self.passthrough_resample {
            while self.src_buffer.len() / tc < out_frames {
                if !self.decode_next_packet()? {
                    break;
                }
            }
            let take_samples = (out_frames * tc).min(self.src_buffer.len());
            out.extend(self.src_buffer.drain(0..take_samples));
            return Ok(out);
        }

        let _sinc_scope = profiler::scope("audio::dsp::StreamDecoder::sinc_resampler");
        let mut frame = vec![0.0f64; tc];
        while out.len() / tc < out_frames {
            // Derive phase from integer frame counts, never accumulated floating point:
            // buffer compaction and read block size must not change the signal.
            let position = self.output_frames as u128 * self.source_sample_rate as u128;
            let whole = (position / self.target_sample_rate as u128) as u64;
            let frac = (position % self.target_sample_rate as u128) as f64
                / self.target_sample_rate as f64;
            let center = (whole - self.source_offset) as isize;
            let sinc_half_taps = self.kernel.as_ref().unwrap().half_taps as isize;
            let need = (center + sinc_half_taps + 2).max(0) as usize;
            while self.src_buffer.len() / tc < need {
                if !self.decode_next_packet()? {
                    break;
                }
            }
            let avail = self.src_buffer.len() / tc;
            if avail == 0 {
                break;
            }
            if self.eof && center as usize >= avail {
                break;
            }

            let kernel = self.kernel.as_ref().unwrap();
            let phase = frac * kernel.phases as f64;
            let phase_index = (phase.floor() as usize).min(kernel.phases - 1);
            let blend = phase - phase_index as f64;
            let first = &kernel.coefficients[phase_index];
            let second = &kernel.coefficients[phase_index + 1];
            let mut weight_sum = 0.0;
            frame.fill(0.0);
            for (i, (&a, &b)) in first.iter().zip(second).enumerate() {
                let idx = center + i as isize - sinc_half_taps;
                if idx < 0 || idx as usize >= avail {
                    continue;
                }
                let weight = a + (b - a) * blend;
                weight_sum += weight;
                let base = idx as usize * tc;
                for c in 0..tc {
                    frame[c] += self.src_buffer[base + c] * weight;
                }
            }

            if weight_sum.abs() > 1e-12 {
                for c in 0..tc {
                    out.push(frame[c] / weight_sum);
                }
            } else {
                let i0 = center.max(0) as usize;
                let base = i0.min(avail - 1) * tc;
                for c in 0..tc {
                    out.push(self.src_buffer[base + c]);
                }
            }

            self.output_frames += 1;
        }
        // Compact once per block, preserving filter history even at EOF.
        let history = self.kernel.as_ref().unwrap().half_taps;
        let next_frame = ((self.output_frames as u128 * self.source_sample_rate as u128)
            / self.target_sample_rate as u128) as u64;
        let drop_frames = next_frame
            .saturating_sub(self.source_offset)
            .saturating_sub(history as u64)
            .min((self.src_buffer.len() / tc) as u64) as usize;
        if drop_frames > 0 {
            self.src_buffer.drain(..drop_frames * tc);
            self.source_offset += drop_frames as u64;
        }
        Ok(out)
    }

    /// Seek the source to `secs` seconds and reset internal buffers/resampler state.
    pub fn seek(&mut self, secs: f64) -> Result<(), String> {
        let _scope = profiler::scope("audio::dsp::StreamDecoder::seek");
        if !secs.is_finite() || secs < 0.0 {
            return Err("Invalid seek position".to_string());
        }
        let time = Time {
            seconds: secs.floor() as u64,
            frac: secs - secs.floor(),
        };
        let seeked = self
            .format
            .seek(
                SeekMode::Accurate,
                SeekTo::Time {
                    time,
                    track_id: Some(self.track_id),
                },
            )
            .map_err(|e| e.to_string())?;
        self.decoder.reset();
        self.seek_target_ts = Some(seeked.required_ts);
        self.src_buffer.clear();
        self.output_frames = 0;
        self.source_offset = 0;
        self.eof = false;
        Ok(())
    }

    #[allow(dead_code)]
    pub fn source_sample_rate(&self) -> u32 {
        self.source_sample_rate
    }
}

fn sinc(x: f64) -> f64 {
    if x.abs() < 1e-8 {
        1.0
    } else {
        let pix = std::f64::consts::PI * x;
        pix.sin() / pix
    }
}

struct SincKernel {
    half_taps: usize,
    phases: usize,
    coefficients: Vec<Vec<f64>>,
}

impl SincKernel {
    fn new(source: u32, target: u32, quality: &str) -> Result<Self, String> {
        let high = quality != "standard";
        let ratio = target as f64 / source as f64;
        // Downsampling must cut off BELOW the destination Nyquist.
        let cutoff = ratio.min(1.0) * if high { 0.95 } else { 0.90 };
        let taps = if high {
            HIGH_QUALITY_SINC_HALF_TAPS
        } else {
            STANDARD_SINC_HALF_TAPS
        };
        let half_taps = (taps as f64 / cutoff).ceil() as usize;
        if half_taps > 4096 {
            return Err("Sample-rate ratio exceeds supported filter range".to_string());
        }
        let (mut a, mut b) = (source, target);
        while b != 0 {
            (a, b) = (b, a % b);
        }
        let phases = (target / a).clamp(1, 1024) as usize;
        let coefficients = (0..=phases)
            .map(|phase| {
                let fraction = phase as f64 / phases as f64;
                (-(half_taps as isize)..=half_taps as isize)
                    .map(|tap| {
                        let x = tap as f64 - fraction;
                        let distance = x.abs() / half_taps as f64;
                        if distance > 1.0 {
                            return 0.0;
                        }
                        let angle = std::f64::consts::PI * distance;
                        let window = 0.35875
                            + 0.48829 * angle.cos()
                            + 0.14128 * (2.0 * angle).cos()
                            + 0.01168 * (3.0 * angle).cos();
                        cutoff * sinc(cutoff * x) * window
                    })
                    .collect()
            })
            .collect();
        Ok(Self {
            half_taps,
            phases,
            coefficients,
        })
    }
}

/// Preserve every supported PCM format, including all 32 integer bits.
fn packet_to_interleaved_f64(decoded: &AudioBufferRef) -> (Vec<f64>, usize) {
    let mut samples = SampleBuffer::<f64>::new(decoded.capacity() as u64, *decoded.spec());
    samples.copy_interleaved_ref(decoded.clone());
    (samples.samples().to_vec(), decoded.spec().channels.count())
}

/// Stereo fold-down includes centre/surround/LFE channels instead of discarding
/// them. Normalize the matrix once by its row sum to avoid per-block gain pumping.
/// CPAL exposes only a channel count, not a speaker map: fill front L/R and leave
/// extra output channels silent rather than guessing their speaker assignments.
fn append_channels(input: &[f64], layout: Channels, target: usize, output: &mut Vec<f64>) {
    let channels = layout.count();
    if channels == 0 || target == 0 {
        return;
    }
    if channels <= 2 && channels == target {
        output.extend_from_slice(input);
        return;
    }
    if channels == 1 {
        for &sample in input {
            output.push(sample);
            if target > 1 {
                output.push(sample);
            }
            output.extend(std::iter::repeat(0.0).take(target.saturating_sub(2)));
        }
        return;
    }
    let weights: Vec<(f64, f64)> = layout
        .iter()
        .map(|channel| {
            use std::f64::consts::FRAC_1_SQRT_2 as K;
            if channel == Channels::FRONT_LEFT {
                (1.0, 0.0)
            } else if channel == Channels::FRONT_RIGHT {
                (0.0, 1.0)
            } else if (Channels::REAR_LEFT
                | Channels::SIDE_LEFT
                | Channels::FRONT_LEFT_CENTRE
                | Channels::TOP_FRONT_LEFT
                | Channels::TOP_REAR_LEFT
                | Channels::REAR_LEFT_CENTRE
                | Channels::FRONT_LEFT_WIDE
                | Channels::FRONT_LEFT_HIGH)
                .contains(channel)
            {
                (K, 0.0)
            } else if (Channels::REAR_RIGHT
                | Channels::SIDE_RIGHT
                | Channels::FRONT_RIGHT_CENTRE
                | Channels::TOP_FRONT_RIGHT
                | Channels::TOP_REAR_RIGHT
                | Channels::REAR_RIGHT_CENTRE
                | Channels::FRONT_RIGHT_WIDE
                | Channels::FRONT_RIGHT_HIGH)
                .contains(channel)
            {
                (0.0, K)
            } else if (Channels::LFE1 | Channels::LFE2).contains(channel) {
                (0.5, 0.5)
            } else {
                (K, K)
            }
        })
        .collect();
    let gain = weights
        .iter()
        .map(|w| w.0)
        .sum::<f64>()
        .max(weights.iter().map(|w| w.1).sum::<f64>())
        .max(1.0);
    for frame in input.chunks_exact(channels) {
        let left = frame
            .iter()
            .zip(&weights)
            .map(|(s, w)| s * w.0)
            .sum::<f64>()
            / gain;
        let right = frame
            .iter()
            .zip(&weights)
            .map(|(s, w)| s * w.1)
            .sum::<f64>()
            / gain;
        if target == 1 {
            output.push((left + right) * 0.5);
        } else {
            output.extend_from_slice(&[left, right]);
            output.extend(std::iter::repeat(0.0).take(target - 2));
        }
    }
}

// ===================== Pitch shifting =====================

/// Resampling pitch shift: pitch and speed change together (tempo is not preserved).
pub fn pitch_shift_resample(input: &[f32], pitch_factor: f64) -> Vec<f32> {
    let _scope = profiler::scope("audio::dsp::pitch_shift_resample");
    if input.len() < 4 || pitch_factor <= 0.0 || !pitch_factor.is_finite() {
        return input.to_vec();
    }
    if (pitch_factor - 1.0).abs() < 0.001 {
        return input.to_vec();
    }

    let num_samples = input.len() / 2;
    let target_num_samples = ((num_samples as f64) / pitch_factor).round().max(1.0) as usize;
    let mut output = Vec::with_capacity(target_num_samples * 2);

    for i in 0..target_num_samples {
        let src_idx = i as f64 * pitch_factor;
        output.push(cubic_stereo(input, num_samples, src_idx, 0));
        output.push(cubic_stereo(input, num_samples, src_idx, 1));
    }
    output
}

fn cubic_stereo(input: &[f32], frames: usize, pos: f64, channel: usize) -> f32 {
    let i1 = pos.floor() as isize;
    let t = (pos - pos.floor()) as f32;
    let sample = |idx: isize| -> f32 {
        let frame = idx.clamp(0, frames.saturating_sub(1) as isize) as usize;
        input[frame * 2 + channel]
    };

    let y0 = sample(i1 - 1);
    let y1 = sample(i1);
    let y2 = sample(i1 + 1);
    let y3 = sample(i1 + 2);

    let a0 = -0.5 * y0 + 1.5 * y1 - 1.5 * y2 + 0.5 * y3;
    let a1 = y0 - 2.5 * y1 + 2.0 * y2 - 0.5 * y3;
    let a2 = -0.5 * y0 + 0.5 * y2;
    let a3 = y1;
    ((a0 * t + a1) * t + a2) * t + a3
}

#[cfg(test)]
mod fidelity_tests {
    use super::*;
    use crate::audio::test_support::TestWav;

    fn read_all(path: &str, rate: u32, channels: u32, block: usize, quality: &str) -> Vec<f64> {
        let mut decoder = StreamDecoder::new(path, channels, rate, quality).unwrap();
        let mut result = Vec::new();
        loop {
            let samples = decoder.read_block(block).unwrap();
            if samples.is_empty() {
                break;
            }
            result.extend(samples);
            // A zero-length read must not consume samples or filter history.
            assert!(decoder.read_block(0).unwrap().is_empty());
            assert!(result.len() < 1_000_000, "decoder failed to reach EOF");
        }
        result
    }
    #[test]
    fn pcm_16_24_32_is_exact_at_matching_rate_across_packets() {
        for bits in [16, 24, 32] {
            let scale = (1u64 << (bits - 1)) as f64;
            let min = -(1i64 << (bits - 1));
            let max = (1i64 << (bits - 1)) - 1;
            let samples: Vec<i32> = (0..20001)
                .map(|n| [min, min + 1, -1, 0, 1, max - 1, max][n % 7] as i32)
                .collect();
            let file = TestWav::pcm(48000, 1, bits, &samples);
            for block in [7, 2048] {
                let output = read_all(file.path(), 48000, 1, block, "high");
                assert_eq!(output.len(), samples.len());
                for (&got, &expected) in output.iter().zip(&samples) {
                    assert_eq!(got, expected as f64 / scale, "{bits}-bit PCM");
                }
            }
        }
    }
    #[test]
    fn float64_and_channel_identity_survive_without_downcasting() {
        let input = [0.123456789012345, -0.98765432109876, 1e-14, -1e-14];
        let file = TestWav::float(44100, 2, &input);
        assert_eq!(read_all(file.path(), 44100, 2, 3, "high"), input);
    }
    #[test]
    fn every_surround_channel_reaches_stereo_without_clipping() {
        let layout = Channels::FRONT_LEFT
            | Channels::FRONT_RIGHT
            | Channels::FRONT_CENTRE
            | Channels::LFE1
            | Channels::REAR_LEFT
            | Channels::REAR_RIGHT;
        for channel in 0..6 {
            let mut input = [0.0; 6];
            input[channel] = 1.0;
            let mut output = Vec::new();
            append_channels(&input, layout, 2, &mut output);
            assert!(output.iter().any(|&s| s > 0.0), "lost channel {channel}");
        }
        let mut output = Vec::new();
        append_channels(&[1.0; 6], layout, 2, &mut output);
        assert!(output.iter().all(|&s| s <= 1.0));
    }
    fn tone(rate: u32, frequency: f64) -> Vec<f64> {
        (0..rate / 4)
            .map(|n| 0.5 * (2.0 * std::f64::consts::PI * frequency * n as f64 / rate as f64).sin())
            .collect()
    }
    fn db_gain(samples: &[f64]) -> f64 {
        let samples = &samples[512..samples.len() - 512];
        let rms = (samples.iter().map(|s| s * s).sum::<f64>() / samples.len() as f64).sqrt();
        20.0 * (rms / (0.5 / 2.0f64.sqrt())).log10()
    }
    #[test]
    fn downsampling_rejects_ultrasonic_aliases() {
        for (source, target, frequency) in [
            (96000, 48000, 30000.0),
            (192000, 48000, 30000.0),
            (96000, 44100, 26000.0),
        ] {
            for quality in ["standard", "high"] {
                let file = TestWav::float(source, 1, &tone(source, frequency));
                let output = read_all(file.path(), target, 1, 2048, quality);
                let db = db_gain(&output);
                eprintln!("SRC {source}->{target} {frequency}Hz {quality}: {db:.2} dB alias");
                assert!(db < -85.0, "alias rejection too low: {db}dB");
            }
        }
    }
    #[test]
    fn high_quality_preserves_audible_passband() {
        for (source, target) in [
            (44100, 48000),
            (48000, 44100),
            (96000, 48000),
            (192000, 48000),
        ] {
            for frequency in [1000.0, 10000.0, 20000.0] {
                let file = TestWav::float(source, 1, &tone(source, frequency));
                let db = db_gain(&read_all(file.path(), target, 1, 2048, "high"));
                assert!(
                    db.abs() < 0.1,
                    "{source}->{target} {frequency}Hz gain {db}dB"
                );
            }
        }
    }
    #[test]
    fn resampler_is_independent_of_read_block_size_and_keeps_duration() {
        let input = tone(44100, 997.0);
        let file = TestWav::float(44100, 1, &input);
        let a = read_all(file.path(), 48000, 1, 17, "high");
        let b = read_all(file.path(), 48000, 1, 2048, "high");
        assert!((a.len() as isize - 12000).abs() <= 1);
        assert!((a.len() as isize - b.len() as isize).abs() <= 1);
        let error = a
            .iter()
            .zip(&b)
            .map(|(a, b)| (a - b).abs())
            .fold(0.0f64, f64::max);
        assert!(error < 1e-9, "block boundary error {error}");
    }
    #[test]
    fn seek_clears_decoder_and_old_audio() {
        let samples: Vec<i32> = (0..48000).map(|n| n % 32768).collect();
        let file = TestWav::pcm(48000, 1, 16, &samples);
        let mut decoder = StreamDecoder::new(file.path(), 1, 48000, "high").unwrap();
        decoder.read_block(4000).unwrap();
        decoder.seek(0.0).unwrap();
        let output = decoder.read_block(128).unwrap();
        assert_eq!(
            output,
            samples[..128]
                .iter()
                .map(|&s| s as f64 / 32768.0)
                .collect::<Vec<_>>()
        );
    }
    #[test]
    fn reference_flac_decodes_exactly_and_seeks_inside_codec_packets() {
        let path = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tests/fixtures/pcm24-stereo.flac"
        );
        let expected: Vec<f64> = (0..20000i64)
            .map(|n| ((n * 104729) % (1 << 24) - (1 << 23)) as f64 / 8388608.0)
            .collect();
        assert_eq!(read_all(path, 48000, 2, 2048, "high"), expected);
        let mut decoder = StreamDecoder::new(path, 2, 48000, "high").unwrap();
        decoder.read_block(2000).unwrap();
        decoder.seek(0.137).unwrap();
        assert_eq!(
            decoder.read_block(128).unwrap(),
            expected[6576 * 2..(6576 + 128) * 2]
        );
        decoder.seek(0.0).unwrap();
        assert_eq!(decoder.read_block(128).unwrap(), expected[..256]);
    }
    #[test]
    fn every_symphonia_sample_format_converts_without_silencing_channels() {
        use std::borrow::Cow;
        use symphonia::core::audio::{AudioBuffer, Signal, SignalSpec};
        use symphonia::core::sample::{i24, u24};
        macro_rules! check {
            ($kind:ident, $ty:ty, $input:expr, $expected:expr) => {{
                let mut buffer =
                    AudioBuffer::<$ty>::new(3, SignalSpec::new(48000, Channels::FRONT_LEFT));
                buffer.render_reserved(Some(3));
                buffer.chan_mut(0).copy_from_slice(&$input);
                let (output, channels) =
                    packet_to_interleaved_f64(&AudioBufferRef::$kind(Cow::Borrowed(&buffer)));
                assert_eq!(channels, 1);
                assert_eq!(output, $expected, stringify!($kind));
            }};
        }
        check!(U8, u8, [0, 128, 192], [-1.0, 0.0, 0.5]);
        check!(U16, u16, [0, 32768, 49152], [-1.0, 0.0, 0.5]);
        check!(
            U24,
            u24,
            [u24(0), u24(8388608), u24(12582912)],
            [-1.0, 0.0, 0.5]
        );
        check!(U32, u32, [0, 2147483648, 3221225472], [-1.0, 0.0, 0.5]);
        check!(S8, i8, [-128, 0, 64], [-1.0, 0.0, 0.5]);
        check!(S16, i16, [-32768, 0, 16384], [-1.0, 0.0, 0.5]);
        check!(
            S24,
            i24,
            [i24(-8388608), i24(0), i24(4194304)],
            [-1.0, 0.0, 0.5]
        );
        check!(S32, i32, [-2147483648, 0, 1073741824], [-1.0, 0.0, 0.5]);
        check!(F32, f32, [-1.0, 0.0, 0.5], [-1.0, 0.0, 0.5]);
        check!(F64, f64, [-1.0, 0.0, 0.5], [-1.0, 0.0, 0.5]);
    }
}
