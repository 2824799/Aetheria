//! Sample-accurate Phigros chart hit-sound synthesis & mixing engine.
//!
//! Loads decoded PCM hit sound clips (`tap`, `drag`, `flick`) resampled to the
//! active hardware output rate/channel layout and mixes scheduled note hits
//! directly into PCM output blocks inside [`super::player::DecodePipeline`].

use super::dsp::StreamDecoder;
use serde::Deserialize;
use std::fs;
use std::path::{Path, PathBuf};

/// Scales 100% UI slider volume (~-0.7 dBFS raw clip peaks) so hitsounds
/// sit naturally beside Phigros masters without drowning the music.
const DEFAULT_MIX_SCALE: f64 = 0.68;

/// Notes of the exact same sound kind within this window (e.g. multi-finger chords)
/// coalesce into one hit transient instead of linearly stacking to digital clipping.
const COINCIDENCE_WINDOW_SECS: f64 = 0.0025;

/// Cap simultaneous decaying tails so fast drag streams stay clean & bounded.
const MAX_ACTIVE_VOICES: usize = 24;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum HitNoteKind {
    Tap = 0,
    Drag = 1,
    Flick = 2,
}

impl HitNoteKind {
    /// Maps official Phigros note types (`1=Tap, 2=Drag, 3=Hold, 4=Flick`).
    /// Hold triggers the Tap hit sound at its head time in Phigros.
    pub fn from_phigros_type(raw_type: u8) -> Option<Self> {
        match raw_type {
            1 | 3 => Some(Self::Tap),
            2 => Some(Self::Drag),
            4 => Some(Self::Flick),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct HitEvent {
    pub time_secs: f64,
    pub kind: HitNoteKind,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct HitSoundConfig {
    pub enabled: bool,
    pub volume: f64,
    pub offset_ms: i32,
}

impl Default for HitSoundConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            volume: 0.75,
            offset_ms: 0,
        }
    }
}

#[derive(Deserialize)]
struct CompactChart {
    notes: Vec<(f64, u8)>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct OfficialChart {
    #[serde(default)]
    offset: f64,
    #[serde(default)]
    judge_line_list: Vec<OfficialJudgeLine>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct OfficialJudgeLine {
    bpm: f64,
    #[serde(default)]
    notes_above: Vec<OfficialNote>,
    #[serde(default)]
    notes_below: Vec<OfficialNote>,
}

#[derive(Deserialize)]
struct OfficialNote {
    #[serde(rename = "type")]
    note_type: u8,
    time: f64,
}

/// Sorted, coincidence-coalesced timeline of hit-sound trigger events.
#[derive(Clone, Debug, Default)]
pub struct HitTimeline {
    events: Vec<HitEvent>,
}

impl HitTimeline {
    pub fn from_events(mut events: Vec<HitEvent>) -> Self {
        events.retain(|e| e.time_secs.is_finite() && e.time_secs >= 0.0);
        events.sort_by(|a, b| {
            a.time_secs
                .total_cmp(&b.time_secs)
                .then_with(|| a.kind.cmp(&b.kind))
        });

        let mut last_by_kind = [f64::NEG_INFINITY; 3];
        let mut coalesced = Vec::with_capacity(events.len());
        for ev in events {
            let slot = ev.kind as usize;
            if ev.time_secs - last_by_kind[slot] >= COINCIDENCE_WINDOW_SECS {
                last_by_kind[slot] = ev.time_secs;
                coalesced.push(ev);
            }
        }
        Self { events: coalesced }
    }

    pub fn from_json_str(raw: &str) -> Result<Self, String> {
        if let Ok(compact) = serde_json::from_str::<CompactChart>(raw) {
            let events = compact
                .notes
                .into_iter()
                .filter_map(|(t, kind_raw)| {
                    HitNoteKind::from_phigros_type(kind_raw).map(|kind| HitEvent {
                        time_secs: t,
                        kind,
                    })
                })
                .collect();
            return Ok(Self::from_events(events));
        }

        let official: OfficialChart = serde_json::from_str(raw)
            .map_err(|e| format!("Invalid Phigros chart JSON: {e}"))?;
        let mut events = Vec::new();
        for line in official.judge_line_list {
            if !line.bpm.is_finite() || line.bpm <= 0.0 {
                continue;
            }
            let unit_secs = 1.875 / line.bpm;
            for note in line.notes_above.into_iter().chain(line.notes_below.into_iter()) {
                if let Some(kind) = HitNoteKind::from_phigros_type(note.note_type) {
                    events.push(HitEvent {
                        time_secs: note.time * unit_secs + official.offset,
                        kind,
                    });
                }
            }
        }
        Ok(Self::from_events(events))
    }

    pub fn load_file(path: &Path) -> Result<Self, String> {
        let raw = fs::read_to_string(path).map_err(|e| e.to_string())?;
        Self::from_json_str(&raw)
    }

    pub fn events(&self) -> &[HitEvent] {
        &self.events
    }
}

/// Decoded stereo/multichannel hit sound clips matched to output `(sample_rate, channels)`.
#[derive(Clone, Debug)]
pub struct HitSoundBank {
    sample_rate: u32,
    channels: usize,
    /// Interleaved `f64` samples indexed by [`HitNoteKind`].
    clips: [Vec<f64>; 3],
}

impl HitSoundBank {
    pub fn from_buffers(
        sample_rate: u32,
        channels: usize,
        tap: Vec<f64>,
        drag: Vec<f64>,
        flick: Vec<f64>,
    ) -> Self {
        Self {
            sample_rate: sample_rate.max(1),
            channels: channels.max(1),
            clips: [tap, drag, flick],
        }
    }

    pub fn load_from_dir(dir: &Path, sample_rate: u32, channels: u32) -> Result<Self, String> {
        let tap = load_first_clip(dir, "tap", channels, sample_rate)?;
        let drag = load_first_clip(dir, "drag", channels, sample_rate).unwrap_or_else(|_| tap.clone());
        let flick = load_first_clip(dir, "flick", channels, sample_rate).unwrap_or_else(|_| tap.clone());
        Ok(Self::from_buffers(
            sample_rate,
            channels as usize,
            tap,
            drag,
            flick,
        ))
    }

    pub fn matches(&self, sample_rate: u32, channels: u32) -> bool {
        self.sample_rate == sample_rate && self.channels == channels as usize
    }

    fn clip(&self, kind: HitNoteKind) -> &[f64] {
        &self.clips[kind as usize]
    }
}

fn load_first_clip(
    dir: &Path,
    stem: &str,
    channels: u32,
    sample_rate: u32,
) -> Result<Vec<f64>, String> {
    for ext in ["wav", "flac", "ogg", "mp3"] {
        let path: PathBuf = dir.join(format!("{stem}.{ext}"));
        if path.is_file() {
            return decode_clip(&path, channels, sample_rate);
        }
    }
    Err(format!("Missing hitsound clip for '{stem}' in {}", dir.display()))
}

fn decode_clip(path: &Path, channels: u32, sample_rate: u32) -> Result<Vec<f64>, String> {
    let mut decoder = StreamDecoder::new(&path.to_string_lossy(), channels, sample_rate, "high")?;
    let mut out = Vec::new();
    loop {
        let block = decoder.read_block(2048)?;
        if block.is_empty() {
            break;
        }
        out.extend(block);
    }
    if out.is_empty() {
        return Err(format!("Decoded hitsound clip was empty: {}", path.display()));
    }
    Ok(out)
}

#[derive(Clone, Copy, Debug)]
struct ActiveVoice {
    kind: HitNoteKind,
    frame_pos: usize,
}

/// Mixes scheduled chart hits and active decaying tails into PCM blocks.
#[derive(Default)]
pub struct HitSoundMixer {
    voices: Vec<ActiveVoice>,
}

impl HitSoundMixer {
    pub fn new() -> Self {
        Self {
            voices: Vec::with_capacity(MAX_ACTIVE_VOICES),
        }
    }

    pub fn reset(&mut self) {
        self.voices.clear();
    }

    pub fn mix_block(
        &mut self,
        block: &mut [f64],
        channels: usize,
        sample_rate: u32,
        block_start_frame: i64,
        cfg: &HitSoundConfig,
        bank: &HitSoundBank,
        timeline: &HitTimeline,
    ) {
        if block.is_empty() || channels == 0 || sample_rate == 0 {
            return;
        }
        if !cfg.enabled || cfg.volume <= 0.0001 {
            self.voices.clear();
            return;
        }
        if !bank.matches(sample_rate, channels as u32) {
            return;
        }

        let block_frames = block.len() / channels;
        if block_frames == 0 {
            return;
        }
        let block_end_frame = block_start_frame + block_frames as i64;
        let gain = DEFAULT_MIX_SCALE * cfg.volume.clamp(0.0, 1.5);

        // 1. Continue rendering active voices carried over from previous blocks.
        let mut idx = 0;
        while idx < self.voices.len() {
            let voice = &mut self.voices[idx];
            let clip = bank.clip(voice.kind);
            let clip_frames = clip.len() / channels;
            if voice.frame_pos >= clip_frames {
                self.voices.swap_remove(idx);
                continue;
            }
            let mix_frames = (clip_frames - voice.frame_pos).min(block_frames);
            mix_slice(
                block,
                0,
                clip,
                voice.frame_pos,
                mix_frames,
                channels,
                gain,
            );
            voice.frame_pos += mix_frames;
            if voice.frame_pos >= clip_frames {
                self.voices.swap_remove(idx);
            } else {
                idx += 1;
            }
        }

        // 2. Spawn new note hits whose shifted trigger frame falls inside this block.
        let events = timeline.events();
        if events.is_empty() {
            return;
        }
        let offset_secs = cfg.offset_ms as f64 / 1000.0;
        let sr = sample_rate as f64;
        let trigger_frame = |e: &HitEvent| -> i64 { ((e.time_secs + offset_secs) * sr).round() as i64 };

        let start_idx = events.partition_point(|e| trigger_frame(e) < block_start_frame);
        let end_idx = events.partition_point(|e| trigger_frame(e) < block_end_frame);

        for ev in &events[start_idx..end_idx] {
            let tf = trigger_frame(ev);
            if tf < 0 {
                continue;
            }
            let local_frame = (tf - block_start_frame) as usize;
            if local_frame >= block_frames {
                continue;
            }
            let clip = bank.clip(ev.kind);
            let clip_frames = clip.len() / channels;
            if clip_frames == 0 {
                continue;
            }
            let mix_frames = clip_frames.min(block_frames - local_frame);
            mix_slice(block, local_frame, clip, 0, mix_frames, channels, gain);
            if mix_frames < clip_frames {
                if self.voices.len() >= MAX_ACTIVE_VOICES {
                    self.voices.remove(0);
                }
                self.voices.push(ActiveVoice {
                    kind: ev.kind,
                    frame_pos: mix_frames,
                });
            }
        }
    }
}

#[inline]
fn mix_slice(
    dst: &mut [f64],
    dst_frame: usize,
    clip: &[f64],
    clip_frame: usize,
    frames: usize,
    channels: usize,
    gain: f64,
) {
    let dst_start = dst_frame * channels;
    let src_start = clip_frame * channels;
    let samples = frames * channels;
    for i in 0..samples {
        dst[dst_start + i] += clip[src_start + i] * gain;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_bank() -> HitSoundBank {
        // Mono clips at 100 Hz so frame math maps 1:1 to 10ms ticks.
        let tap = vec![1.0, 0.5, 0.25];
        let drag = vec![0.4, 0.2];
        let flick = vec![0.8, 0.6, 0.4, 0.2];
        HitSoundBank::from_buffers(100, 1, tap, drag, flick)
    }

    #[test]
    fn coalesces_same_kind_chords_within_window_but_preserves_distinct_kinds() {
        let timeline = HitTimeline::from_events(vec![
            HitEvent { time_secs: 1.000, kind: HitNoteKind::Tap },
            HitEvent { time_secs: 1.001, kind: HitNoteKind::Tap },
            HitEvent { time_secs: 1.000, kind: HitNoteKind::Flick },
            HitEvent { time_secs: 1.050, kind: HitNoteKind::Tap },
        ]);
        assert_eq!(
            timeline.events(),
            &[
                HitEvent { time_secs: 1.000, kind: HitNoteKind::Tap },
                HitEvent { time_secs: 1.000, kind: HitNoteKind::Flick },
                HitEvent { time_secs: 1.050, kind: HitNoteKind::Tap },
            ]
        );
    }

    #[test]
    fn parses_official_phigros_chart_timing_and_offset() {
        let json = r#"{
            "formatVersion": 3,
            "offset": 0.25,
            "judgeLineList": [{
                "bpm": 120.0,
                "notesAbove": [
                    {"type": 1, "time": 64},
                    {"type": 2, "time": 96}
                ],
                "notesBelow": [
                    {"type": 3, "time": 128},
                    {"type": 4, "time": 160}
                ]
            }]
        }"#;
        let timeline = HitTimeline::from_json_str(json).unwrap();
        // At 120 BPM: 1 unit = 1.875 / 120 = 0.015625 s; 64 units = 1.0s + 0.25 = 1.25s.
        assert_eq!(timeline.events().len(), 4);
        assert!((timeline.events()[0].time_secs - 1.25).abs() < 1e-6);
        assert_eq!(timeline.events()[0].kind, HitNoteKind::Tap);
        assert_eq!(timeline.events()[1].kind, HitNoteKind::Drag);
        assert_eq!(timeline.events()[2].kind, HitNoteKind::Tap); // Hold -> Tap sound
        assert_eq!(timeline.events()[3].kind, HitNoteKind::Flick);
    }

    #[test]
    fn mixes_across_block_boundaries_and_resets_on_seek() {
        let bank = test_bank();
        // Flick clip has 4 frames [0.8, 0.6, 0.4, 0.2]; trigger at t=0.08s => frame 8.
        let timeline = HitTimeline::from_events(vec![HitEvent {
            time_secs: 0.08,
            kind: HitNoteKind::Flick,
        }]);
        let cfg = HitSoundConfig {
            enabled: true,
            volume: 1.0,
            offset_ms: 0,
        };
        let mut mixer = HitSoundMixer::new();

        // Block 0: frames 0..10 -> frames 8,9 receive flick[0], flick[1].
        let mut b0 = vec![0.0; 10];
        mixer.mix_block(&mut b0, 1, 100, 0, &cfg, &bank, &timeline);
        assert!((b0[8] - 0.8 * DEFAULT_MIX_SCALE).abs() < 1e-9);
        assert!((b0[9] - 0.6 * DEFAULT_MIX_SCALE).abs() < 1e-9);

        // Block 1: frames 10..20 -> frames 0,1 receive carried tail flick[2], flick[3].
        let mut b1 = vec![0.0; 10];
        mixer.mix_block(&mut b1, 1, 100, 10, &cfg, &bank, &timeline);
        assert!((b1[0] - 0.4 * DEFAULT_MIX_SCALE).abs() < 1e-9);
        assert!((b1[1] - 0.2 * DEFAULT_MIX_SCALE).abs() < 1e-9);
        assert!((b1[2]).abs() < 1e-9);

        // Seek reset drops any active tail immediately.
        let mut b_before_seek = vec![0.0; 10];
        mixer.mix_block(&mut b_before_seek, 1, 100, 0, &cfg, &bank, &timeline);
        mixer.reset();
        let mut b_after_seek = vec![0.0; 10];
        mixer.mix_block(&mut b_after_seek, 1, 100, 50, &cfg, &bank, &timeline);
        assert!(b_after_seek.iter().all(|&s| s.abs() < 1e-9));
    }

    #[test]
    fn positive_offset_shifts_trigger_later() {
        let bank = test_bank();
        let timeline = HitTimeline::from_events(vec![HitEvent {
            time_secs: 0.02,
            kind: HitNoteKind::Drag,
        }]);
        let cfg = HitSoundConfig {
            enabled: true,
            volume: 1.0,
            offset_ms: 30, // 0.02s + 0.03s = 0.05s => frame 5
        };
        let mut mixer = HitSoundMixer::new();
        let mut block = vec![0.0; 10];
        mixer.mix_block(&mut block, 1, 100, 0, &cfg, &bank, &timeline);
        assert!(block[2].abs() < 1e-9);
        assert!((block[5] - 0.4 * DEFAULT_MIX_SCALE).abs() < 1e-9);
        assert!((block[6] - 0.2 * DEFAULT_MIX_SCALE).abs() < 1e-9);
    }
}
