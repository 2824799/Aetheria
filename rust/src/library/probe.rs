//! Reads technical properties, tags, embedded art and lyrics from audio files.

use super::{LibraryError, Result};
use lofty::file::{AudioFile, TaggedFile, TaggedFileExt};
use lofty::picture::{MimeType, Picture, PictureType};
use lofty::probe::Probe;
use lofty::tag::{Accessor, ItemKey, Tag};
use std::fs::File;
use std::io::Read;
use std::path::Path;
use symphonia::core::errors::Error as SymphoniaError;

const SECONDS_PER_DAY: f64 = 86_400.0;

/// Stream properties as stored in `audio_files`.
pub struct AudioProperties {
    pub duration: f64,
    /// Bits per second.
    pub bitrate: Option<i32>,
    pub sample_rate: Option<i32>,
    pub bit_depth: Option<i32>,
}

#[derive(Default)]
pub struct AudioTags {
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
}

pub fn open(path: &Path) -> Result<TaggedFile> {
    Probe::open(path)
        .map_err(|e| LibraryError::new(format!("无法打开音频文件: {e}")))?
        .read()
        .map_err(|e| LibraryError::new(format!("无法读取音频元数据: {e}")))
}

pub fn properties(path: &Path, file: &TaggedFile) -> AudioProperties {
    let properties = file.properties();
    let bitrate = properties
        .audio_bitrate()
        .map(|kbps| kbps.saturating_mul(1000));
    AudioProperties {
        duration: reliable_duration(path, properties.duration().as_secs_f64(), bitrate),
        bitrate: bitrate.map(|bps| bps.min(i32::MAX as u32) as i32),
        sample_rate: properties.sample_rate().map(|rate| rate as i32),
        bit_depth: properties.bit_depth().map(i32::from),
    }
}

/// Title/artist/album, preferring the primary tag and falling back per field
/// to any other tag block in the file. Blank values count as missing.
pub fn tags(file: &TaggedFile) -> AudioTags {
    let first = |read: fn(&Tag) -> Option<String>| ordered_tags(file).find_map(read);
    AudioTags {
        title: first(|tag| non_blank(tag.title().as_deref())),
        artist: first(|tag| non_blank(tag.artist().as_deref())),
        album: first(|tag| non_blank(tag.album().as_deref())),
    }
}

pub fn embedded_lyrics(path: &Path) -> Option<String> {
    let file = Probe::open(path).ok()?.read().ok()?;
    let lyrics = ordered_tags(&file).find_map(|tag| non_blank(tag.get_string(&ItemKey::Lyrics)));
    lyrics
}

/// The front cover (or, failing that, any picture) and its file extension.
pub fn embedded_cover(path: &Path) -> Option<(Vec<u8>, &'static str)> {
    let file = Probe::open(path).ok()?.read().ok()?;
    let usable = |picture: &&Picture| !picture.data().is_empty();
    let picture = ordered_tags(&file)
        .find_map(|tag| tag.get_picture_type(PictureType::CoverFront).filter(usable))
        .or_else(|| ordered_tags(&file).find_map(|tag| tag.pictures().iter().find(usable)))?;
    let extension = match picture.mime_type() {
        Some(MimeType::Png) => "png",
        Some(MimeType::Gif) => "gif",
        Some(MimeType::Bmp) => "bmp",
        Some(MimeType::Tiff) => "tiff",
        _ => "jpg",
    };
    Some((picture.data().to_vec(), extension))
}

/// MD5 of the file contents, streamed so large lossless files are never held
/// in memory.
pub fn file_md5(path: &Path) -> std::io::Result<String> {
    let mut file = File::open(path)?;
    let mut context = md5::Context::new();
    let mut buffer = vec![0u8; 1 << 16];
    loop {
        let read = file.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        context.consume(&buffer[..read]);
    }
    Ok(format!("{:x}", context.compute()))
}

fn ordered_tags(file: &TaggedFile) -> impl Iterator<Item = &Tag> {
    let primary = file.primary_tag();
    primary.into_iter().chain(
        file.tags()
            .iter()
            .filter(move |tag| !primary.is_some_and(|primary| std::ptr::eq(primary, *tag))),
    )
}

fn non_blank(value: Option<&str>) -> Option<String> {
    let trimmed = value?.trim();
    (!trimmed.is_empty()).then(|| trimmed.to_string())
}

fn plausible(duration: f64) -> Option<f64> {
    (duration.is_finite() && duration > 0.0).then_some(duration)
}

fn is_raw_aac(path: &Path) -> bool {
    path.extension()
        .and_then(|ext| ext.to_str())
        .is_some_and(|ext| ext.eq_ignore_ascii_case("aac"))
}

/// Raw ADTS streams carry no duration header, so tag readers guess from the
/// bitrate; counting packets is the only trustworthy source for them.
fn reliable_duration(path: &Path, tagged_duration: f64, bitrate_bps: Option<u32>) -> f64 {
    let tagged = plausible(tagged_duration);
    let duration = if is_raw_aac(path) {
        decoded_duration(path, true).or(tagged)
    } else {
        tagged.or_else(|| decoded_duration(path, false))
    };
    duration
        .or_else(|| bitrate_duration(path, bitrate_bps))
        .unwrap_or(0.0)
}

/// Duration from the container header, or from walking every packet when the
/// header is absent or (`count_packets`) known to be unreliable.
fn decoded_duration(path: &Path, count_packets: bool) -> Option<f64> {
    let mut format = crate::audio::dsp::open_format(&path.to_string_lossy()).ok()?;
    let track = crate::audio::dsp::default_track(format.as_ref()).ok()?;
    let track_id = track.id;
    let n_frames = track.codec_params.n_frames;
    let sample_rate = track.codec_params.sample_rate.filter(|rate| *rate > 0);
    let time_base = track.codec_params.time_base;
    let seconds_at = |timestamp: u64| {
        time_base
            .map(|base| {
                let time = base.calc_time(timestamp);
                time.seconds as f64 + time.frac
            })
            .and_then(plausible)
    };
    let frames_to_seconds =
        |frames: u64| sample_rate.and_then(|rate| plausible(frames as f64 / f64::from(rate)));

    if !count_packets {
        let from_header =
            n_frames.and_then(|frames| frames_to_seconds(frames).or_else(|| seconds_at(frames)));
        if from_header.is_some() {
            return from_header;
        }
    }

    let mut packet_duration_sum = 0u64;
    let mut last_packet_end = None;
    loop {
        match format.next_packet() {
            Ok(packet) if packet.track_id() == track_id => {
                packet_duration_sum = packet_duration_sum.saturating_add(packet.dur());
                last_packet_end = Some(packet.ts().saturating_add(packet.dur()));
            }
            Ok(_) | Err(SymphoniaError::ResetRequired) => continue,
            Err(_) => break,
        }
    }

    let from_packet_sum = if count_packets && packet_duration_sum > 0 {
        frames_to_seconds(packet_duration_sum)
    } else {
        None
    };
    from_packet_sum.or_else(|| {
        let end = last_packet_end?;
        seconds_at(end).or_else(|| frames_to_seconds(end))
    })
}

fn bitrate_duration(path: &Path, bitrate_bps: Option<u32>) -> Option<f64> {
    let bitrate = bitrate_bps.filter(|bitrate| *bitrate > 0)?;
    let file_size = path.metadata().ok()?.len() as f64;
    plausible(file_size * 8.0 / f64::from(bitrate)).filter(|duration| *duration < SECONDS_PER_DAY)
}
