use std::collections::VecDeque;
use std::ffi::c_void;

use crate::audio::profiler;

type RubberBandLiveState = *mut c_void;

const RUBBERBAND_LIVE_OPTION_WINDOW_SHORT: i32 = 0x0000_0000;
const RUBBERBAND_LIVE_OPTION_WINDOW_MEDIUM: i32 = 0x0010_0000;
const RUBBERBAND_LIVE_OPTION_FORMANT_SHIFTED: i32 = 0x0000_0000;
const RUBBERBAND_LIVE_OPTION_FORMANT_PRESERVED: i32 = 0x0100_0000;
const RUBBERBAND_LIVE_OPTION_CHANNELS_TOGETHER: i32 = 0x1000_0000;

unsafe extern "C" {
    fn rubberband_live_new(sample_rate: u32, channels: u32, options: i32) -> RubberBandLiveState;
    fn rubberband_live_delete(state: RubberBandLiveState);
    fn rubberband_live_reset(state: RubberBandLiveState);
    fn rubberband_live_set_pitch_scale(state: RubberBandLiveState, scale: f64);
    fn rubberband_live_set_formant_option(state: RubberBandLiveState, options: i32);
    fn rubberband_live_get_start_delay(state: RubberBandLiveState) -> u32;
    fn rubberband_live_get_block_size(state: RubberBandLiveState) -> u32;
    fn rubberband_live_shift(
        state: RubberBandLiveState,
        input: *const *const f32,
        output: *mut *mut f32,
    );
}

pub struct RubberBandPitchShifter {
    state: RubberBandLiveState,
    channels: usize,
    block_size: usize,
    pitch_scale: f64,
    delay_remaining: usize,
    input_frames: usize,
    output_frames: usize,
    input_fifo: Vec<VecDeque<f32>>,
    output_fifo: Vec<VecDeque<f32>>,
    input_block: Vec<Vec<f32>>,
    output_block: Vec<Vec<f32>>,
}

// SAFETY: This wrapper uniquely owns the native state, exposes it through no
// aliases, and requires &mut self for processing/configuration. The vendored
// RubberBandLiveShifter.h thread-safety contract prohibits concurrent calls on
// one instance, not transferring sole ownership between threads. Do not add Sync.
unsafe impl Send for RubberBandPitchShifter {}

impl RubberBandPitchShifter {
    pub fn new(
        sample_rate: u32,
        channels: u32,
        pitch_scale: f64,
        window: &str,
        preserve_formant: bool,
    ) -> Result<Self, String> {
        let _scope = profiler::scope("audio::rubberband::RubberBandPitchShifter::new");
        if sample_rate == 0 || channels == 0 {
            return Err("Invalid Rubber Band output format".to_string());
        }

        let options = RUBBERBAND_LIVE_OPTION_CHANNELS_TOGETHER
            | window_option(window)
            | formant_option(preserve_formant);
        let state = unsafe { rubberband_live_new(sample_rate, channels, options) };
        if state.is_null() {
            return Err("Rubber Band LiveShifter initialization failed".to_string());
        }

        let block_size = unsafe { rubberband_live_get_block_size(state) } as usize;
        if block_size == 0 {
            unsafe { rubberband_live_delete(state) };
            return Err("Rubber Band reported an invalid block size".to_string());
        }

        let pitch_scale = sanitize_pitch_scale(pitch_scale);
        unsafe {
            rubberband_live_set_pitch_scale(state, pitch_scale);
        }

        let channels = channels as usize;
        Ok(Self {
            state,
            channels,
            block_size,
            pitch_scale,
            delay_remaining: unsafe { rubberband_live_get_start_delay(state) } as usize,
            input_frames: 0,
            output_frames: 0,
            input_fifo: (0..channels).map(|_| VecDeque::new()).collect(),
            output_fifo: (0..channels).map(|_| VecDeque::new()).collect(),
            input_block: (0..channels).map(|_| vec![0.0; block_size]).collect(),
            output_block: (0..channels).map(|_| vec![0.0; block_size]).collect(),
        })
    }

    pub fn reset(&mut self) {
        let _scope = profiler::scope("audio::rubberband::RubberBandPitchShifter::reset");
        unsafe {
            rubberband_live_reset(self.state);
            rubberband_live_set_pitch_scale(self.state, self.pitch_scale);
        }
        self.delay_remaining = unsafe { rubberband_live_get_start_delay(self.state) } as usize;
        self.input_frames = 0;
        self.output_frames = 0;
        for fifo in &mut self.input_fifo {
            fifo.clear();
        }
        for fifo in &mut self.output_fifo {
            fifo.clear();
        }
    }

    pub fn process(&mut self, input: &[f32], pitch_scale: f64) -> Vec<f32> {
        let _scope = profiler::scope("audio::rubberband::RubberBandPitchShifter::process");
        if input.is_empty() {
            return Vec::new();
        }
        if input.len() % self.channels != 0 {
            return input.to_vec();
        }

        let pitch_scale = sanitize_pitch_scale(pitch_scale);
        if (pitch_scale - self.pitch_scale).abs() > 0.000_001 {
            unsafe { rubberband_live_set_pitch_scale(self.state, pitch_scale) };
            self.pitch_scale = pitch_scale;
        }

        let frames = input.len() / self.channels;
        self.input_frames += frames;
        self.push_interleaved(input);
        self.shift_ready_blocks();
        self.pop_interleaved(frames)
    }

    pub fn set_formant_preserved(&mut self, preserve_formant: bool) {
        let _scope =
            profiler::scope("audio::rubberband::RubberBandPitchShifter::set_formant_preserved");
        unsafe {
            rubberband_live_set_formant_option(self.state, formant_option(preserve_formant));
        }
    }

    pub fn finish(&mut self) -> Vec<f32> {
        let _scope = profiler::scope("audio::rubberband::RubberBandPitchShifter::finish");
        let remaining = self.input_frames.saturating_sub(self.output_frames);
        // LiveShifter has fixed processing latency. Feed zero padding until every
        // real input frame has a corresponding output; never expose the padding.
        while self.output_fifo.first().map_or(0, VecDeque::len) < remaining {
            for channel_fifo in &mut self.input_fifo {
                channel_fifo.resize(self.block_size, 0.0);
            }
            self.shift_ready_blocks();
        }
        self.pop_interleaved(remaining)
    }

    fn push_interleaved(&mut self, input: &[f32]) {
        let _scope = profiler::scope("audio::rubberband::RubberBandPitchShifter::push_interleaved");
        for frame in input.chunks_exact(self.channels) {
            for (channel, &sample) in frame.iter().enumerate() {
                self.input_fifo[channel].push_back(sample);
            }
        }
    }

    fn shift_ready_blocks(&mut self) {
        let _scope =
            profiler::scope("audio::rubberband::RubberBandPitchShifter::shift_ready_blocks");
        while self
            .input_fifo
            .first()
            .is_some_and(|fifo| fifo.len() >= self.block_size)
        {
            for channel in 0..self.channels {
                for sample in 0..self.block_size {
                    self.input_block[channel][sample] =
                        self.input_fifo[channel].pop_front().unwrap_or(0.0);
                    self.output_block[channel][sample] = 0.0;
                }
            }

            let input_ptrs: Vec<*const f32> = self
                .input_block
                .iter()
                .map(|block| block.as_ptr())
                .collect();
            let mut output_ptrs: Vec<*mut f32> = self
                .output_block
                .iter_mut()
                .map(|block| block.as_mut_ptr())
                .collect();

            unsafe {
                rubberband_live_shift(self.state, input_ptrs.as_ptr(), output_ptrs.as_mut_ptr());
            }

            let skip = self.delay_remaining.min(self.block_size);
            self.delay_remaining -= skip;
            for channel in 0..self.channels {
                self.output_fifo[channel].extend(&self.output_block[channel][skip..]);
            }
        }
    }

    fn pop_interleaved(&mut self, requested_frames: usize) -> Vec<f32> {
        let _scope = profiler::scope("audio::rubberband::RubberBandPitchShifter::pop_interleaved");
        let available = self.output_fifo.first().map_or(0, VecDeque::len);
        let frames = requested_frames
            .min(available)
            .min(self.input_frames.saturating_sub(self.output_frames));
        self.output_frames += frames;
        let mut output = Vec::with_capacity(frames * self.channels);

        for _ in 0..frames {
            for channel in 0..self.channels {
                output.push(self.output_fifo[channel].pop_front().unwrap_or(0.0));
            }
        }

        output
    }
}

impl Drop for RubberBandPitchShifter {
    fn drop(&mut self) {
        if !self.state.is_null() {
            unsafe { rubberband_live_delete(self.state) };
            self.state = std::ptr::null_mut();
        }
    }
}

fn sanitize_pitch_scale(scale: f64) -> f64 {
    if !scale.is_finite() || scale <= 0.0 {
        1.0
    } else {
        scale.clamp(0.25, 4.0)
    }
}

fn window_option(window: &str) -> i32 {
    if window == "quality" {
        RUBBERBAND_LIVE_OPTION_WINDOW_MEDIUM
    } else {
        RUBBERBAND_LIVE_OPTION_WINDOW_SHORT
    }
}

fn formant_option(preserve_formant: bool) -> i32 {
    if preserve_formant {
        RUBBERBAND_LIVE_OPTION_FORMANT_PRESERVED
    } else {
        RUBBERBAND_LIVE_OPTION_FORMANT_SHIFTED
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pitch_delay_is_trimmed_and_tail_keeps_exact_duration() {
        for frames in [1, 129, 2048, 12001] {
            for window in ["latency", "quality"] {
                let mut shifter =
                    RubberBandPitchShifter::new(48000, 2, 1.12246, window, false).unwrap();
                let input: Vec<f32> = (0..frames * 2)
                    .map(|n| (n as f32 / 2.0 * 0.13).sin() * 0.1)
                    .collect();
                let mut output = Vec::new();
                for block in input.chunks(258) {
                    output.extend(shifter.process(block, 1.12246));
                }
                output.extend(shifter.finish());
                assert_eq!(output.len(), input.len(), "{frames} frames/{window}");
                assert!(output.iter().all(|s| s.is_finite()));
                assert!(shifter.finish().is_empty());
                shifter.reset();
                assert!(shifter.finish().is_empty());
            }
        }
    }

    #[test]
    fn prefilled_processor_can_move_without_losing_state() {
        let input = vec![0.1; 16000];
        let mut shifter = RubberBandPitchShifter::new(48000, 2, 1.0, "latency", false).unwrap();
        let mut output = shifter.process(&input[..8000], 1.0);
        let tail = std::thread::spawn(move || {
            let mut tail = shifter.process(&input[8000..], 1.0);
            tail.extend(shifter.finish());
            tail
        })
        .join()
        .unwrap();
        output.extend(tail);
        assert_eq!(output.len(), 16000);
        // At unity pitch the sustained signal must be present at both ends of
        // the compensated stream, not replaced with the processor's startup delay.
        assert!(output[256..1024].iter().any(|s| s.abs() > 0.01));
        assert!(output[15000..].iter().any(|s| s.abs() > 0.01));
    }
}
