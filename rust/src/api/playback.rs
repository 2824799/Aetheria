//! Playback engine and audio profiler API exposed to Dart.

use crate::audio::player::{self, AudioOutputInfo, PlaybackProgress};
use crate::audio::profiler;
use flutter_rust_bridge::frb;

/// Starts streaming `path`, replacing whatever is currently playing.
pub fn start_playback(
    path: String,
    volume: f32,
    pitch: f64,
    algo: String,
    normalization_gain: f32,
) -> Result<(), String> {
    player::start_playback(path, volume, pitch, algo, normalization_gain)
}

pub fn pause_playback() -> Result<(), String> {
    player::pause_playback()
}

pub fn resume_playback() -> Result<(), String> {
    player::resume_playback()
}

pub fn seek_playback(secs: f64) -> Result<(), String> {
    player::seek_playback(secs)
}

pub fn stop_playback() -> Result<(), String> {
    player::stop_playback()
}

/// Position and end-of-stream flag, read together for the UI progress timer.
pub fn get_playback_progress() -> PlaybackProgress {
    player::get_progress()
}

pub fn set_volume(volume: f32) -> Result<(), String> {
    player::set_volume(volume)
}

/// `pitch` is in semitones; `algo` is `"resample"` or `"rubberband"`.
pub fn set_pitch(pitch: f64, algo: String) -> Result<(), String> {
    player::set_pitch(pitch, algo)
}

pub fn set_output_buffer_ms(ms: i32) -> Result<(), String> {
    player::set_output_buffer_ms(ms)
}

pub fn set_output_latency_mode(mode: String) -> Result<(), String> {
    player::set_output_latency_mode(mode)
}

pub fn set_audio_quality_settings(
    peak_protection_enabled: bool,
    dither_enabled: bool,
    rubberband_window: String,
    rubberband_formant_preserved: bool,
    rubberband_vocal_only_pitch: bool,
    resampler_quality: String,
) -> Result<(), String> {
    player::set_quality_settings(
        peak_protection_enabled,
        dither_enabled,
        rubberband_window,
        rubberband_formant_preserved,
        rubberband_vocal_only_pitch,
        resampler_quality,
    )
}

pub fn get_audio_output_info() -> AudioOutputInfo {
    player::get_output_info()
}

pub fn get_default_output_device_name() -> Result<String, String> {
    player::default_output_device_name()
}

// ---- Profiler ----

#[frb(sync)]
pub fn set_audio_performance_profiling_enabled(enabled: bool) {
    profiler::set_enabled(enabled);
}

#[frb(sync)]
pub fn reset_audio_performance_stats() {
    profiler::reset();
}

#[frb(sync)]
pub fn get_audio_performance_report_json() -> String {
    profiler::report_json()
}

#[frb(sync)]
pub fn export_audio_performance_report_markdown() -> String {
    profiler::report_markdown()
}
