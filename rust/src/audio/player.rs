use std::sync::{Arc, Mutex, atomic::{AtomicBool, Ordering}};
use std::thread;
use std::time::Duration;
use std::collections::VecDeque;
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use crate::audio::dsp::{self, AudioOutput};

// Thread-safe ring buffer/FIFO queue for audio samples
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
    
    pub fn push(&self, samples: &[f32]) {
        let mut queue = self.data.lock().unwrap();
        while queue.len() + samples.len() > self.capacity {
            std::thread::sleep(Duration::from_millis(5));
            drop(queue);
            queue = self.data.lock().unwrap();
        }
        queue.extend(samples.iter().cloned());
    }
    
    pub fn pop(&self, out: &mut [f32]) -> usize {
        let mut queue = self.data.lock().unwrap();
        let len = out.len().min(queue.len());
        for i in 0..len {
            out[i] = queue.pop_front().unwrap_or(0.0);
        }
        len
    }

    pub fn clear(&self) {
        self.data.lock().unwrap().clear();
    }

    pub fn len(&self) -> usize {
        self.data.lock().unwrap().len()
    }
}

pub struct SendStream(pub cpal::Stream);
unsafe impl Send for SendStream {}
unsafe impl Sync for SendStream {}

// CPAL implementation of the AudioOutput target
pub struct CpalAudioOutput {
    buffer: Arc<AudioBuffer>,
    stream: Option<SendStream>,
}

impl CpalAudioOutput {
    pub fn new(buffer: Arc<AudioBuffer>) -> Self {
        Self {
            buffer,
            stream: None,
        }
    }
}

impl AudioOutput for CpalAudioOutput {
    fn init(&mut self, sample_rate: u32, channels: u32) -> Result<(), String> {
        let host = cpal::default_host();
        let device = host.default_output_device()
            .ok_or_else(|| "No default audio output device found".to_string())?;
            
        let config = cpal::StreamConfig {
            channels: channels as u16,
            sample_rate: cpal::SampleRate(sample_rate),
            buffer_size: cpal::BufferSize::Default,
        };
        
        let buffer_clone = self.buffer.clone();
        let stream = device.build_output_stream(
            &config,
            move |data: &mut [f32], _: &cpal::OutputCallbackInfo| {
                let read = buffer_clone.pop(data);
                if read < data.len() {
                    for i in read..data.len() {
                        data[i] = 0.0;
                    }
                }
            },
            move |err| {
                eprintln!("Audio output stream error: {}", err);
            },
            None
        ).map_err(|e| e.to_string())?;
        
        stream.play().map_err(|e| e.to_string())?;
        self.stream = Some(SendStream(stream));
        Ok(())
    }
    
    fn write_samples(&mut self, samples: &[f32]) -> Result<(), String> {
        self.buffer.push(samples);
        Ok(())
    }
    
    fn flush(&mut self) -> Result<(), String> {
        while self.buffer.len() > 0 {
            thread::sleep(Duration::from_millis(10));
        }
        Ok(())
    }
}

// Global player controller states
struct PlayerState {
    thread_handle: Option<thread::JoinHandle<()>>,
    stop_flag: Arc<AtomicBool>,
    pause_flag: Arc<AtomicBool>,
    seek_request: Arc<Mutex<Option<f64>>>,
    position_sec: Arc<Mutex<f64>>,
    volume: Arc<Mutex<f32>>,
    pitch: Arc<Mutex<f64>>,
    algo: Arc<Mutex<String>>,
    loudness_normalization_gain: Arc<Mutex<f32>>,
}

lazy_static::lazy_static! {
    static ref GLOBAL_PLAYER: Mutex<PlayerState> = Mutex::new(PlayerState {
        thread_handle: None,
        stop_flag: Arc::new(AtomicBool::new(false)),
        pause_flag: Arc::new(AtomicBool::new(false)),
        seek_request: Arc::new(Mutex::new(None)),
        position_sec: Arc::new(Mutex::new(0.0)),
        volume: Arc::new(Mutex::new(0.8)),
        pitch: Arc::new(Mutex::new(0.0)),
        algo: Arc::new(Mutex::new("wsola".to_string())),
        loudness_normalization_gain: Arc::new(Mutex::new(1.0)),
    });
}

/// Control API: Start playing an audio file with DSP processing
pub fn start_playback(path: String, vol: f32, pitch_val: f64, pitch_algo: String, normalization_gain: f32) -> Result<(), String> {
    let mut state = GLOBAL_PLAYER.lock().unwrap();
    
    // Stop any existing playback thread
    state.stop_flag.store(true, Ordering::SeqCst);
    if let Some(handle) = state.thread_handle.take() {
        let _ = handle.join();
    }
    
    // Reset flags
    state.stop_flag.store(false, Ordering::SeqCst);
    state.pause_flag.store(false, Ordering::SeqCst);
    *state.seek_request.lock().unwrap() = None;
    *state.position_sec.lock().unwrap() = 0.0;
    *state.volume.lock().unwrap() = vol;
    *state.pitch.lock().unwrap() = pitch_val;
    *state.algo.lock().unwrap() = pitch_algo;
    *state.loudness_normalization_gain.lock().unwrap() = normalization_gain;
    
    let stop_flag = state.stop_flag.clone();
    let pause_flag = state.pause_flag.clone();
    let seek_req = state.seek_request.clone();
    let pos_sec = state.position_sec.clone();
    let volume_state = state.volume.clone();
    let pitch_state = state.pitch.clone();
    let algo_state = state.algo.clone();
    let norm_gain_state = state.loudness_normalization_gain.clone();
    
    let handle = thread::spawn(move || {
        let buffer = Arc::new(AudioBuffer::new(44100 * 4)); // 4 seconds buffer capacity
        let mut output = CpalAudioOutput::new(buffer);
        if let Err(e) = output.init(44100, 2) {
            eprintln!("Failed to initialize audio output: {}", e);
            return;
        }
        
        // Decode to F32 stereo samples at 44.1kHz
        let samples = match dsp::decode_to_pcm(&path, 44100) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("Decode error: {}", e);
                return;
            }
        };
        
        let mut sample_index = 0usize;
        let total_samples = samples.len();
        
        while sample_index < total_samples {
            if stop_flag.load(Ordering::SeqCst) {
                break;
            }
            
            if pause_flag.load(Ordering::SeqCst) {
                thread::sleep(Duration::from_millis(20));
                continue;
            }
            
            // Handle seek request
            {
                let mut req = seek_req.lock().unwrap();
                if let Some(sec) = req.take() {
                    let target_sample = (sec * 44100.0 * 2.0) as usize;
                    sample_index = target_sample.min(total_samples - (total_samples % 2));
                    *pos_sec.lock().unwrap() = sec;
                }
            }
            
            // Read a block of audio samples
            let block_size = 4096usize; // frame size of 2048 stereo samples
            let end_idx = (sample_index + block_size).min(total_samples);
            if sample_index >= end_idx {
                break;
            }
            
            let mut block = samples[sample_index..end_idx].to_vec();
            sample_index = end_idx;
            
            // Read DSP parameters
            let current_pitch = *pitch_state.lock().unwrap();
            let current_algo = algo_state.lock().unwrap().clone();
            let current_vol = *volume_state.lock().unwrap();
            let current_norm = *norm_gain_state.lock().unwrap();
            
            // 1. Apply volume adjustments (Master Volume * Normalization Gain)
            let total_gain = current_vol * current_norm;
            if (total_gain - 1.0).abs() > 0.01 {
                for sample in &mut block {
                    *sample *= total_gain;
                }
            }
            
            // 2. Apply Pitch Shift
            if current_pitch.abs() > 0.01 {
                let pitch_factor = 2.0f64.powf(current_pitch / 12.0);
                block = match current_algo.as_str() {
                    "resample" => dsp::pitch_shift_resample(&block, pitch_factor),
                    "ola" => dsp::pitch_shift_ola(&block, pitch_factor),
                    _ => dsp::pitch_shift_wsola(&block, pitch_factor),
                };
            }
            
            // 3. Write processed block to CPAL
            if let Err(e) = output.write_samples(&block) {
                eprintln!("Write samples error: {}", e);
                break;
            }
            
            // Update time position (1 sample is 1 channel, so divide by 2 for stereo)
            let frames_played = block.len() / 2;
            let secs_played = frames_played as f64 / 44100.0;
            *pos_sec.lock().unwrap() += secs_played;
        }
        
        let _ = output.flush();
    });
    
    state.thread_handle = Some(handle);
    Ok(())
}

/// Control API: Pause playback
pub fn pause_playback() -> Result<(), String> {
    let state = GLOBAL_PLAYER.lock().unwrap();
    state.pause_flag.store(true, Ordering::SeqCst);
    Ok(())
}

/// Control API: Resume playback
pub fn resume_playback() -> Result<(), String> {
    let state = GLOBAL_PLAYER.lock().unwrap();
    state.pause_flag.store(false, Ordering::SeqCst);
    Ok(())
}

/// Control API: Seek to target seconds
pub fn seek_playback(secs: f64) -> Result<(), String> {
    let state = GLOBAL_PLAYER.lock().unwrap();
    *state.seek_request.lock().unwrap() = Some(secs);
    Ok(())
}

/// Control API: Stop playback
pub fn stop_playback() -> Result<(), String> {
    let mut state = GLOBAL_PLAYER.lock().unwrap();
    state.stop_flag.store(true, Ordering::SeqCst);
    if let Some(handle) = state.thread_handle.take() {
        let _ = handle.join();
    }
    Ok(())
}

/// Control API: Set master volume dynamically
pub fn set_volume(vol: f32) -> Result<(), String> {
    let state = GLOBAL_PLAYER.lock().unwrap();
    *state.volume.lock().unwrap() = vol;
    Ok(())
}

/// Control API: Set pitch shifting parameters dynamically
pub fn set_pitch(pitch_val: f64, pitch_algo: String) -> Result<(), String> {
    let state = GLOBAL_PLAYER.lock().unwrap();
    *state.pitch.lock().unwrap() = pitch_val;
    *state.algo.lock().unwrap() = pitch_algo;
    Ok(())
}

/// Control API: Get current playback position in seconds
pub fn get_position() -> f64 {
    let state = GLOBAL_PLAYER.lock().unwrap();
    let val = *state.position_sec.lock().unwrap();
    val
}
