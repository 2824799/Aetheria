//! Full-track BS.1770 measurement and Aetheria's short-term listening preference.
use super::{dsp, profiler};
use ebur128::{Channel, EbuR128, Mode};
use std::path::Path;
use symphonia::core::audio::{Channels, SampleBuffer, SignalSpec};
use symphonia::core::errors::Error;

const TARGET_LUFS: f64 = -16.0;

#[derive(Clone, Copy, Debug)]
pub(crate) struct Profile {
    // Silence and clips shorter than the 400 ms integration window have no integrated level.
    pub integrated: Option<f64>,
    pub attenuation_db: f64,
}

fn speaker(channel: Channels) -> Channel {
    match channel {
        Channels::LFE1 | Channels::LFE2 => Channel::Unused,
        Channels::FRONT_LEFT => Channel::Left,
        Channels::FRONT_RIGHT => Channel::Right,
        Channels::SIDE_LEFT => Channel::Mp090,
        Channels::SIDE_RIGHT => Channel::Mm090,
        Channels::REAR_LEFT => Channel::LeftSurround,
        Channels::REAR_RIGHT => Channel::RightSurround,
        Channels::REAR_LEFT_CENTRE => Channel::Mp135,
        Channels::REAR_RIGHT_CENTRE => Channel::Mm135,
        Channels::REAR_CENTRE => Channel::Mp180,
        Channels::FRONT_LEFT_WIDE => Channel::Mp060,
        Channels::FRONT_RIGHT_WIDE => Channel::Mm060,
        Channels::FRONT_LEFT_CENTRE => Channel::MpSC,
        Channels::FRONT_RIGHT_CENTRE => Channel::MmSC,
        Channels::TOP_CENTRE => Channel::Tp000,
        Channels::TOP_FRONT_LEFT | Channels::FRONT_LEFT_HIGH => Channel::Up030,
        Channels::TOP_FRONT_RIGHT | Channels::FRONT_RIGHT_HIGH => Channel::Um030,
        Channels::TOP_FRONT_CENTRE | Channels::FRONT_CENTRE_HIGH => Channel::Up000,
        Channels::TOP_REAR_LEFT => Channel::Up135,
        Channels::TOP_REAR_RIGHT => Channel::Um135,
        Channels::TOP_REAR_CENTRE => Channel::Up180,
        _ => Channel::Center,
    }
}

struct Analyzer {
    spec: SignalSpec,
    meter: EbuR128,
    frames: u64,
    windows: u64,
    loud_weight: f64,
}

impl Analyzer {
    fn new(spec: SignalSpec) -> Result<Self, String> {
        let map: Vec<_> = spec.channels.iter().map(speaker).collect();
        if map.is_empty() || !(8000..=768000).contains(&spec.rate) {
            return Err("Unsupported loudness scan format".into());
        }
        let mut meter = EbuR128::new(
            map.len() as u32,
            spec.rate,
            Mode::I | Mode::S | Mode::HISTOGRAM,
        )
        .map_err(|e| e.to_string())?;
        meter.set_channel_map(&map).map_err(|e| e.to_string())?;
        Ok(Self {
            spec,
            meter,
            frames: 0,
            windows: 0,
            loud_weight: 0.0,
        })
    }

    fn add(&mut self, mut samples: &[f32]) -> Result<(), String> {
        let rate = self.spec.rate as usize;
        let channels = self.spec.channels.count();
        while !samples.is_empty() {
            // Observe a complete three-second window every second, independent of packet size.
            let until_tick = rate - (self.frames % rate as u64) as usize;
            let count = samples.len().min(until_tick * channels);
            let (chunk, rest) = samples.split_at(count);
            self.meter
                .add_frames_f32(chunk)
                .map_err(|e| e.to_string())?;
            samples = rest;
            self.frames += (count / channels) as u64;
            if self.frames >= 3 * rate as u64 && self.frames % rate as u64 == 0 {
                let short = self.meter.loudness_shortterm().map_err(|e| e.to_string())?;
                // A window from -14 to -8 LUFS contributes smoothly from zero to one.
                // Include quiet windows in the denominator so a brief climax carries little weight.
                self.loud_weight += ((short + 14.0) / 6.0).clamp(0.0, 1.0);
                self.windows += 1;
            }
        }
        Ok(())
    }

    fn finish(self) -> Result<Profile, String> {
        let level = self.meter.loudness_global().map_err(|e| e.to_string())?;
        let integrated = level.is_finite().then_some(level);
        let base = integrated.map_or(0.0, |l| (l - TARGET_LUFS).max(0.0));
        // Start adding comfort attenuation once loud passages occupy over a quarter
        // of the track. Reach the 3 dB ceiling at three quarters.
        let density = self.loud_weight / self.windows.max(1) as f64;
        let extra = 3.0 * ((density - 0.25) / 0.5).clamp(0.0, 1.0);
        Ok(Profile {
            integrated,
            attenuation_db: base + extra.min(base),
        })
    }
}

pub(crate) fn scan(path: &Path) -> Result<Profile, String> {
    let _scope = profiler::scope("audio::loudness::scan");
    let mut format = dsp::open_format(&path.to_string_lossy())?;
    let track = dsp::default_track(format.as_ref())?;
    let track_id = track.id;
    let mut decoder = dsp::make_decoder(track)?;
    let mut analyzer: Option<Analyzer> = None;
    let mut buffer: Option<SampleBuffer<f32>> = None;
    loop {
        let packet = match format.next_packet() {
            Ok(packet) => packet,
            Err(Error::IoError(e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
            Err(e) => return Err(e.to_string()),
        };
        if packet.track_id() != track_id {
            continue;
        }
        let pcm = decoder.decode(&packet).map_err(|e| e.to_string())?;
        let spec = *pcm.spec();
        if pcm.frames() == 0 {
            continue;
        }
        let meter = match &mut analyzer {
            Some(meter) => meter,
            slot @ None => slot.insert(Analyzer::new(spec)?),
        };
        if meter.spec != spec {
            return Err("Audio layout changed during loudness scan".into());
        }
        if buffer
            .as_ref()
            .is_some_and(|b| b.capacity() < pcm.frames() * spec.channels.count())
        {
            buffer = None;
        }
        let buf = buffer.get_or_insert_with(|| SampleBuffer::new(pcm.capacity() as u64, spec));
        buf.copy_interleaved_ref(pcm);
        if !buf.samples().iter().all(|v| v.is_finite()) {
            return Err("Non-finite PCM".into());
        }
        meter.add(buf.samples())?;
    }
    analyzer
        .ok_or_else(|| "No decodable audio samples".to_string())?
        .finish()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::audio::test_support::TestWav;

    fn measure(intro: usize, music: usize, amplitude: f64, hz: f64) -> Profile {
        const RATE: u32 = 48_000;
        let mut pcm = vec![0.0; intro * RATE as usize];
        pcm.extend(
            (0..music * RATE as usize)
                .map(|n| amplitude * (std::f64::consts::TAU * hz * n as f64 / RATE as f64).sin()),
        );
        let wav = TestWav::float(RATE, 1, &pcm);
        scan(&wav.path).unwrap()
    }

    #[test]
    fn full_file_gate_ignores_silent_intro_and_short_peak_gets_no_comfort_penalty() {
        let continuous = measure(0, 5, 0.8, 997.0);
        let brief = measure(20, 5, 0.8, 997.0);
        // BS.1770's full-scale 997 Hz single-channel reference is -3.01 LKFS.
        let reference = -3.01 + 20.0 * 0.8_f64.log10();
        assert!((continuous.integrated.unwrap() - reference).abs() < 0.1);
        assert!((continuous.integrated.unwrap() - brief.integrated.unwrap()).abs() < 0.3);
        let extra = |p: Profile| p.attenuation_db - (p.integrated.unwrap() - TARGET_LUFS);
        assert!((extra(continuous) - 3.0).abs() < 1e-6);
        assert!(extra(brief).abs() < 1e-6);
    }

    #[test]
    fn k_weighting_and_quiet_or_undefined_programmes() {
        let bass = measure(0, 2, 0.08, 35.0);
        let voice = measure(0, 2, 0.08, 3000.0);
        assert!(voice.integrated.unwrap() - bass.integrated.unwrap() > 6.0);
        assert_eq!(voice.attenuation_db, 0.0);
        let silence = measure(2, 0, 0.0, 0.0);
        assert_eq!(silence.integrated, None);
        assert_eq!(silence.attenuation_db, 0.0);
        let clip = TestWav::float(48_000, 1, &[0.5; 4800]);
        assert_eq!(scan(&clip.path).unwrap().integrated, None);
    }

    #[test]
    fn lfe_is_excluded_from_integrated_loudness() {
        let layout = Channels::FRONT_LEFT | Channels::FRONT_RIGHT | Channels::LFE1;
        let mut meter = Analyzer::new(SignalSpec::new(48000, layout)).unwrap();
        let pcm: Vec<_> = (0..48000)
            .flat_map(|n| [0.0, 0.0, (n as f32 / 20.0).sin()])
            .collect();
        meter.add(&pcm).unwrap();
        assert_eq!(meter.finish().unwrap().integrated, None);
    }
}
