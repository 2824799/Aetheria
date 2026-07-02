use std::fs::File;
use symphonia::core::codecs::DecoderOptions;
use symphonia::core::errors::Error;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;
use symphonia::core::audio::AudioBufferRef;
use symphonia::core::audio::Signal;

/// Trait representing an audio output target.
pub trait AudioOutput: Send {
    fn init(&mut self, sample_rate: u32, channels: u32) -> Result<(), String>;
    fn write_samples(&mut self, samples: &[f32]) -> Result<(), String>;
    fn flush(&mut self) -> Result<(), String>;
}

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

/// Decode the entire audio file into F32 stereo samples at the target sample rate.
pub fn decode_to_pcm(filepath: &str, target_sample_rate: u32) -> Result<Vec<f32>, String> {
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
        
    let input_sample_rate = track.codec_params.sample_rate.unwrap_or(44100);
    let mut decoded_samples = Vec::new();
    
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
        let num_frames = decoded.frames();
        let mut temp_samples = vec![0.0f32; num_frames * spec.channels.count()];
        
        match decoded {
            AudioBufferRef::F32(buf) => {
                for chan in 0..spec.channels.count() {
                    let data = buf.chan(chan);
                    for (frame, &val) in data.iter().enumerate() {
                        temp_samples[frame * spec.channels.count() + chan] = val;
                    }
                }
            }
            AudioBufferRef::S16(buf) => {
                for chan in 0..spec.channels.count() {
                    let data = buf.chan(chan);
                    for (frame, &val) in data.iter().enumerate() {
                        temp_samples[frame * spec.channels.count() + chan] = val as f32 / 32768.0;
                    }
                }
            }
            AudioBufferRef::S24(buf) => {
                for chan in 0..spec.channels.count() {
                    let data = buf.chan(chan);
                    for (frame, &val) in data.iter().enumerate() {
                        temp_samples[frame * spec.channels.count() + chan] = val.0 as f32 / 8388608.0;
                    }
                }
            }
            AudioBufferRef::S32(buf) => {
                for chan in 0..spec.channels.count() {
                    let data = buf.chan(chan);
                    for (frame, &val) in data.iter().enumerate() {
                        temp_samples[frame * spec.channels.count() + chan] = val as f32 / 2147483648.0;
                    }
                }
            }
            _ => {}
        }
        
        if spec.channels.count() == 1 {
            for &sample in &temp_samples {
                decoded_samples.push(sample);
                decoded_samples.push(sample);
            }
        } else if spec.channels.count() == 2 {
            decoded_samples.extend(temp_samples);
        } else {
            for frame in 0..num_frames {
                decoded_samples.push(temp_samples[frame * spec.channels.count()]);
                decoded_samples.push(temp_samples[frame * spec.channels.count() + 1]);
            }
        }
    }
    
    if input_sample_rate != target_sample_rate {
        let num_input_frames = decoded_samples.len() / 2;
        let factor = target_sample_rate as f64 / input_sample_rate as f64;
        let num_output_frames = (num_input_frames as f64 * factor) as usize;
        let mut resampled = Vec::with_capacity(num_output_frames * 2);
        
        for i in 0..num_output_frames {
            let src_idx = i as f64 / factor;
            let idx_floor = src_idx.floor() as usize;
            let idx_ceil = (idx_floor + 1).min(num_input_frames - 1);
            let t = src_idx - idx_floor as f64;
            
            let left = (1.0 - t) * decoded_samples[idx_floor * 2] as f64 + t * decoded_samples[idx_ceil * 2] as f64;
            let right = (1.0 - t) * decoded_samples[idx_floor * 2 + 1] as f64 + t * decoded_samples[idx_ceil * 2 + 1] as f64;
            
            resampled.push(left as f32);
            resampled.push(right as f32);
        }
        Ok(resampled)
    } else {
        Ok(decoded_samples)
    }
}

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
