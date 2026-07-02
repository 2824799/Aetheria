use std::fs::File;
use symphonia::core::codecs::{Decoder, DecoderOptions};
use symphonia::core::errors::Error;
use symphonia::core::formats::{FormatOptions, FormatReader, SeekMode, SeekTo};
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;
use symphonia::core::audio::{AudioBufferRef, Signal};
use symphonia::core::units::Time;

/// Calculate the loudness metric of an audio file in dBFS (decibels relative to full scale).
/// This is computed by analyzing the average RMS level of the first 300 packets (approx. 5-10 seconds) for speed.
pub fn calculate_loudness(filepath: &str) -> Result<f64, String> {
    let file = File::open(filepath).map_err(|e| e.to_string())?;
    let mss = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();

    if let Some(ext) = std::path::Path::new(filepath).extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }

    let meta_opts = MetadataOptions::default();
    let fmt_opts = FormatOptions::default();

    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &fmt_opts, &meta_opts)
        .map_err(|e| e.to_string())?;

    let mut format = probed.format;

    let track = format.tracks().iter()
        .find(|t| t.codec_params.codec != symphonia::core::codecs::CODEC_TYPE_NULL)
        .ok_or_else(|| "No audio track found".to_string())?;

    let track_id = track.id;
    let mut decoder = symphonia::default::get_codecs()
        .make(&track.codec_params, &DecoderOptions::default())
        .map_err(|e| e.to_string())?;

    let mut total_samples = 0u64;
    let mut sum_squares = 0.0f64;
    let mut packet_count = 0;

    loop {
        let packet = match format.next_packet() {
            Ok(p) => p,
            Err(Error::IoError(ref e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
            Err(e) => return Err(e.to_string()),
        };

        if packet.track_id() != track_id {
            continue;
        }

        let decoded = match decoder.decode(&packet) {
            Ok(buf) => buf,
            Err(Error::DecodeError(_)) => continue,
            Err(e) => return Err(e.to_string()),
        };

        let spec = *decoded.spec();

        match decoded {
            AudioBufferRef::F32(buf) => {
                for chan in 0..spec.channels.count() {
                    for &sample in buf.chan(chan) {
                        sum_squares += (sample as f64) * (sample as f64);
                        total_samples += 1;
                    }
                }
            }
            AudioBufferRef::S16(buf) => {
                for chan in 0..spec.channels.count() {
                    for &sample in buf.chan(chan) {
                        let s = sample as f64 / 32768.0;
                        sum_squares += s * s;
                        total_samples += 1;
                    }
                }
            }
            AudioBufferRef::S24(buf) => {
                for chan in 0..spec.channels.count() {
                    for sample in buf.chan(chan) {
                        let s = sample.0 as f64 / 8388608.0;
                        sum_squares += s * s;
                        total_samples += 1;
                    }
                }
            }
            AudioBufferRef::S32(buf) => {
                for chan in 0..spec.channels.count() {
                    for &sample in buf.chan(chan) {
                        let s = sample as f64 / 2147483648.0;
                        sum_squares += s * s;
                        total_samples += 1;
                    }
                }
            }
            _ => {}
        }

        packet_count += 1;
        if packet_count > 300 {
            break;
        }
    }

    if total_samples == 0 {
        return Ok(-15.0);
    }

    let mean_square = sum_squares / (total_samples as f64);
    let rms = mean_square.sqrt();
    let db = 20.0 * rms.log10();

    Ok(db.clamp(-60.0, 0.0))
}

/// Calculate the loudness metric of the ENTIRE audio file in dBFS (decibels relative to full scale).
/// This is used during manual database refresh for high-fidelity volume normalization.
pub fn calculate_loudness_full(filepath: &str) -> Result<f64, String> {
    let file = File::open(filepath).map_err(|e| e.to_string())?;
    let mss = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();

    if let Some(ext) = std::path::Path::new(filepath).extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }

    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &Default::default(), &Default::default())
        .map_err(|e| e.to_string())?;

    let mut format = probed.format;

    let track = format.tracks().iter()
        .find(|t| t.codec_params.codec != symphonia::core::codecs::CODEC_TYPE_NULL)
        .ok_or_else(|| "No audio track found".to_string())?;

    let track_id = track.id;
    let mut decoder = symphonia::default::get_codecs()
        .make(&track.codec_params, &Default::default())
        .map_err(|e| e.to_string())?;

    let mut total_samples = 0u64;
    let mut sum_squares = 0.0f64;

    loop {
        let packet = match format.next_packet() {
            Ok(p) => p,
            Err(Error::IoError(ref e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
            Err(e) => return Err(e.to_string()),
        };

        if packet.track_id() != track_id {
            continue;
        }

        let decoded = match decoder.decode(&packet) {
            Ok(buf) => buf,
            Err(Error::DecodeError(_)) => continue,
            Err(e) => return Err(e.to_string()),
        };

        let spec = *decoded.spec();

        match decoded {
            AudioBufferRef::F32(buf) => {
                for chan in 0..spec.channels.count() {
                    for &sample in buf.chan(chan) {
                        sum_squares += (sample as f64) * (sample as f64);
                        total_samples += 1;
                    }
                }
            }
            AudioBufferRef::S16(buf) => {
                for chan in 0..spec.channels.count() {
                    for &sample in buf.chan(chan) {
                        let s = sample as f64 / 32768.0;
                        sum_squares += s * s;
                        total_samples += 1;
                    }
                }
            }
            AudioBufferRef::S24(buf) => {
                for chan in 0..spec.channels.count() {
                    for sample in buf.chan(chan) {
                        let s = sample.0 as f64 / 8388608.0;
                        sum_squares += s * s;
                        total_samples += 1;
                    }
                }
            }
            AudioBufferRef::S32(buf) => {
                for chan in 0..spec.channels.count() {
                    for &sample in buf.chan(chan) {
                        let s = sample as f64 / 2147483648.0;
                        sum_squares += s * s;
                        total_samples += 1;
                    }
                }
            }
            _ => {}
        }
    }

    if total_samples == 0 {
        return Ok(-15.0);
    }

    let mean_square = sum_squares / (total_samples as f64);
    let rms = mean_square.sqrt();
    let db = 20.0 * rms.log10();

    Ok(db.clamp(-60.0, 0.0))
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
    target_channels: usize,
    /// output frames produced per input frame (target_sr / source_sr)
    resample_ratio: f64,
    /// decoded f32 samples, already channel-converted to target_channels, at the source sample rate
    src_buffer: Vec<f32>,
    /// fractional read position (in frames) into src_buffer
    read_pos: f64,
    eof: bool,
}

impl StreamDecoder {
    pub fn new(path: &str, target_channels: u32, target_sample_rate: u32) -> Result<Self, String> {
        let file = File::open(path).map_err(|e| e.to_string())?;
        let mss = MediaSourceStream::new(Box::new(file), Default::default());
        let mut hint = Hint::new();
        if let Some(ext) = std::path::Path::new(path).extension().and_then(|e| e.to_str()) {
            hint.with_extension(ext);
        }

        let probed = symphonia::default::get_probe()
            .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
            .map_err(|e| e.to_string())?;
        let mut format = probed.format;

        let track = format.tracks().iter()
            .find(|t| t.codec_params.codec != symphonia::core::codecs::CODEC_TYPE_NULL)
            .ok_or_else(|| "No audio track found".to_string())?;
        let track_id = track.id;
        let source_sample_rate = track.codec_params.sample_rate.unwrap_or(target_sample_rate);
        let decoder = symphonia::default::get_codecs()
            .make(&track.codec_params, &DecoderOptions::default())
            .map_err(|e| e.to_string())?;

        let resample_ratio = target_sample_rate as f64 / source_sample_rate as f64;

        Ok(Self {
            format,
            decoder,
            track_id,
            source_sample_rate,
            target_channels: target_channels as usize,
            resample_ratio,
            src_buffer: Vec::new(),
            read_pos: 0.0,
            eof: false,
        })
    }

    /// Decode the next packet from the source and append channel-converted f32 frames to src_buffer.
    /// Returns Ok(false) at end of stream.
    fn decode_next_packet(&mut self) -> Result<bool, String> {
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
            let decoded = match self.decoder.decode(&packet) {
                Ok(b) => b,
                Err(Error::DecodeError(_)) => continue,
                Err(e) => return Err(e.to_string()),
            };
            let (inter, chans) = packet_to_interleaved_f32(&decoded);
            let frames = if chans > 0 { inter.len() / chans } else { 0 };
            let tc = self.target_channels;
            for f in 0..frames {
                let base = f * chans;
                let l = if chans >= 1 { inter[base] } else { 0.0 };
                let r = if chans >= 2 { inter[base + 1] } else { l };
                match tc {
                    1 => self.src_buffer.push((l + r) * 0.5),
                    2 => {
                        self.src_buffer.push(l);
                        self.src_buffer.push(r);
                    }
                    n => {
                        self.src_buffer.push(l);
                        self.src_buffer.push(r);
                        for _ in 2..n {
                            self.src_buffer.push(0.0);
                        }
                    }
                }
            }
            return Ok(true);
        }
    }

    /// Read up to `out_frames` resampled frames (interleaved at target_channels).
    /// Returns fewer frames near end of stream; an empty result signals EOF.
    pub fn read_block(&mut self, out_frames: usize) -> Result<Vec<f32>, String> {
        let tc = self.target_channels;
        let mut out: Vec<f32> = Vec::with_capacity(out_frames * tc);
        while out.len() / tc < out_frames {
            // Ensure we have at least read_pos.floor()+2 source frames available.
            let need = (self.read_pos.floor() as usize) + 2;
            while self.src_buffer.len() / tc < need {
                if !self.decode_next_packet()? {
                    break;
                }
            }
            let avail = self.src_buffer.len() / tc;
            if avail == 0 {
                break;
            }
            if self.eof && (self.read_pos.floor() as usize) >= avail {
                break;
            }
            let i0 = (self.read_pos.floor() as usize).min(avail - 1);
            let i1 = (i0 + 1).min(avail - 1);
            let frac = (self.read_pos - self.read_pos.floor()) as f32;
            for c in 0..tc {
                let s0 = self.src_buffer[i0 * tc + c];
                let s1 = self.src_buffer[i1 * tc + c];
                out.push(s0 * (1.0 - frac) + s1 * frac);
            }
            self.read_pos += 1.0 / self.resample_ratio;

            // Drop fully consumed source frames to keep src_buffer bounded.
            let whole = self.read_pos.floor() as usize;
            if whole > 0 {
                let drop_n = (whole * tc).min(self.src_buffer.len());
                self.src_buffer.drain(0..drop_n);
                self.read_pos -= whole as f64;
            }
        }
        Ok(out)
    }

    /// Seek the source to `secs` seconds and reset internal buffers/resampler state.
    pub fn seek(&mut self, secs: f64) -> Result<(), String> {
        let time = Time {
            seconds: secs.floor() as u64,
            frac: secs - secs.floor(),
        };
        let _ = self
            .format
            .seek(
                SeekMode::Accurate,
                SeekTo::Time {
                    time,
                    track_id: Some(self.track_id),
                },
            )
            .map_err(|e| e.to_string())?;
        self.src_buffer.clear();
        self.read_pos = 0.0;
        self.eof = false;
        Ok(())
    }

    #[allow(dead_code)]
    pub fn source_sample_rate(&self) -> u32 {
        self.source_sample_rate
    }
}

/// Convert a decoded symphonia packet into interleaved f32 samples at the source channel count.
fn packet_to_interleaved_f32(decoded: &AudioBufferRef) -> (Vec<f32>, usize) {
    let spec = decoded.spec();
    let chans = spec.channels.count();
    let frames = decoded.frames();
    let mut out = vec![0.0f32; frames * chans];
    match decoded {
        AudioBufferRef::F32(buf) => {
            for chan in 0..chans {
                for (f, &v) in buf.chan(chan).iter().enumerate() {
                    out[f * chans + chan] = v;
                }
            }
        }
        AudioBufferRef::S16(buf) => {
            for chan in 0..chans {
                for (f, &v) in buf.chan(chan).iter().enumerate() {
                    out[f * chans + chan] = v as f32 / 32768.0;
                }
            }
        }
        AudioBufferRef::S24(buf) => {
            for chan in 0..chans {
                for (f, &v) in buf.chan(chan).iter().enumerate() {
                    out[f * chans + chan] = v.0 as f32 / 8388608.0;
                }
            }
        }
        AudioBufferRef::S32(buf) => {
            for chan in 0..chans {
                for (f, &v) in buf.chan(chan).iter().enumerate() {
                    out[f * chans + chan] = v as f32 / 2147483648.0;
                }
            }
        }
        AudioBufferRef::U8(buf) => {
            for chan in 0..chans {
                for (f, &v) in buf.chan(chan).iter().enumerate() {
                    out[f * chans + chan] = (v as f32 - 128.0) / 128.0;
                }
            }
        }
        AudioBufferRef::F64(buf) => {
            for chan in 0..chans {
                for (f, &v) in buf.chan(chan).iter().enumerate() {
                    out[f * chans + chan] = v as f32;
                }
            }
        }
        _ => {}
    }
    (out, chans)
}

// ===================== Pitch shifting =====================

/// Simple Resampling pitch shifting: changes pitch and speed together (high quality, no speed preservation).
pub fn pitch_shift_resample(input: &[f32], pitch_factor: f64) -> Vec<f32> {
    if (pitch_factor - 1.0).abs() < 0.001 {
        return input.to_vec();
    }
    let num_samples = input.len() / 2;
    let target_num_samples = (num_samples as f64 / pitch_factor) as usize;
    let mut output = Vec::with_capacity(target_num_samples * 2);

    for i in 0..target_num_samples {
        let src_idx = i as f64 * pitch_factor;
        let idx_floor = src_idx.floor() as usize;
        let idx_ceil = (idx_floor + 1).min(num_samples - 1);
        let t = src_idx - idx_floor as f64;

        let left = (1.0 - t) * input[idx_floor * 2] as f64 + t * input[idx_ceil * 2] as f64;
        let right = (1.0 - t) * input[idx_floor * 2 + 1] as f64 + t * input[idx_ceil * 2 + 1] as f64;

        output.push(left as f32);
        output.push(right as f32);
    }
    output
}

/// Time domain OLA (Overlap Add) time-stretches the signal.
pub fn time_stretch_ola(input: &[f32], stretch_factor: f64) -> Vec<f32> {
    if (stretch_factor - 1.0).abs() < 0.005 {
        return input.to_vec();
    }
    let num_samples = input.len() / 2;
    let window_size = 1024;
    let hop_s = 256;
    let hop_a = (hop_s as f64 * stretch_factor) as usize;

    let target_num_samples = (num_samples as f64 / stretch_factor) as usize + window_size;
    let mut out_data = vec![0.0f32; target_num_samples * 2];
    let mut out_weight = vec![0.0f32; target_num_samples];

    let hanning: Vec<f32> = (0..window_size)
        .map(|n| 0.5 * (1.0 - ((2.0 * std::f64::consts::PI * n as f64) / (window_size - 1) as f64).cos()) as f32)
        .collect();

    let mut out_pos = 0;
    let mut in_pos = 0;

    while in_pos + window_size < num_samples && out_pos + window_size < target_num_samples {
        for n in 0..window_size {
            let win = hanning[n];
            let in_idx = (in_pos + n) * 2;
            let out_idx = (out_pos + n) * 2;

            out_data[out_idx] += input[in_idx] * win;
            out_data[out_idx + 1] += input[in_idx + 1] * win;
            out_weight[out_pos + n] += win * win;
        }
        out_pos += hop_s;
        in_pos += hop_a;
    }

    let mut final_output = Vec::with_capacity(out_pos * 2);
    for i in 0..out_pos {
        let weight = out_weight[i];
        let gain = if weight > 0.1 { 1.0 / weight } else { 0.0 };
        final_output.push(out_data[i * 2] * gain);
        final_output.push(out_data[i * 2 + 1] * gain);
    }

    final_output
}

/// Pitch shift using OLA (Overlap Add): stretches speed first then resamples back (tempo preserved).
pub fn pitch_shift_ola(input: &[f32], pitch_factor: f64) -> Vec<f32> {
    let stretch_factor = 1.0 / pitch_factor;
    let stretched = time_stretch_ola(input, stretch_factor);
    pitch_shift_resample(&stretched, pitch_factor)
}

/// WSOLA (Waveform Similarity Overlap Add) time stretching for enhanced tempo preservation.
pub fn time_stretch_wsola(input: &[f32], stretch_factor: f64) -> Vec<f32> {
    if (stretch_factor - 1.0).abs() < 0.005 {
        return input.to_vec();
    }
    let num_samples = input.len() / 2;
    let window_size = 1024;
    let hop_s = 256;
    let hop_a = (hop_s as f64 * stretch_factor) as usize;
    let tolerance = 128;

    let target_num_samples = (num_samples as f64 / stretch_factor) as usize + window_size;
    let mut out_data = vec![0.0f32; target_num_samples * 2];
    let mut out_weight = vec![0.0f32; target_num_samples];

    let hanning: Vec<f32> = (0..window_size)
        .map(|n| 0.5 * (1.0 - ((2.0 * std::f64::consts::PI * n as f64) / (window_size - 1) as f64).cos()) as f32)
        .collect();

    let mut out_pos = 0;
    let mut in_pos = 0;
    let mut last_delta = 0isize;

    if num_samples > window_size {
        for n in 0..window_size {
            let win = hanning[n];
            out_data[n * 2] += input[n * 2] * win;
            out_data[n * 2 + 1] += input[n * 2 + 1] * win;
            out_weight[n] += win * win;
        }
        out_pos += hop_s;
        in_pos += hop_a;
    }

    while in_pos + window_size + tolerance < num_samples && out_pos + window_size < target_num_samples {
        let natural_pos = (in_pos as isize - hop_a as isize + last_delta + hop_s as isize) as usize;
        let mut best_offset = 0isize;
        let mut min_diff = f32::MAX;

        for delta in -(tolerance as isize)..=(tolerance as isize) {
            let candidate_pos = (in_pos as isize + delta) as usize;
            let mut diff = 0.0f32;
            for n in 0..hop_s {
                let natural_idx = (natural_pos + n) * 2;
                let candidate_idx = (candidate_pos + n) * 2;
                diff += (input[natural_idx] - input[candidate_idx]).abs() +
                        (input[natural_idx + 1] - input[candidate_idx + 1]).abs();
            }
            if diff < min_diff {
                min_diff = diff;
                best_offset = delta;
            }
        }

        last_delta = best_offset;
        let actual_in_pos = (in_pos as isize + best_offset) as usize;

        for n in 0..window_size {
            let win = hanning[n];
            let in_idx = (actual_in_pos + n) * 2;
            let out_idx = (out_pos + n) * 2;

            out_data[out_idx] += input[in_idx] * win;
            out_data[out_idx + 1] += input[in_idx + 1] * win;
            out_weight[out_pos + n] += win * win;
        }

        out_pos += hop_s;
        in_pos += hop_a;
    }

    let mut final_output = Vec::with_capacity(out_pos * 2);
    for i in 0..out_pos {
        let weight = out_weight[i];
        let gain = if weight > 0.1 { 1.0 / weight } else { 0.0 };
        final_output.push(out_data[i * 2] * gain);
        final_output.push(out_data[i * 2 + 1] * gain);
    }

    final_output
}

/// Pitch shift using WSOLA (Waveform Similarity Overlap Add) for high quality tempo preservation.
pub fn pitch_shift_wsola(input: &[f32], pitch_factor: f64) -> Vec<f32> {
    let stretch_factor = 1.0 / pitch_factor;
    let stretched = time_stretch_wsola(input, stretch_factor);
    pitch_shift_resample(&stretched, pitch_factor)
}
