use crate::database::connection::{
    establish_connection, get_files_dir, get_library_dir, set_library_dir,
};
use crate::database::schema::init_db;
use crate::models::{
    AudioVersion, LocalLyricCandidate, Playlist, PreviewInfo, SavedLyric, Song, Tag,
};
use flutter_rust_bridge::frb;
use lofty::file::{AudioFile, TaggedFileExt};
use lofty::picture::{MimeType, PictureType};
use lofty::probe::Probe;
use lofty::tag::{Accessor, ItemKey};
use rusqlite::params;
use rusqlite::OptionalExtension;
use std::cmp::Ordering;
use std::fs;
use std::path::{Path, PathBuf};
use symphonia::core::errors::Error;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;
use uuid::Uuid;

fn is_raw_aac_path(path: &Path) -> bool {
    path.extension()
        .and_then(|ext| ext.to_str())
        .map(|ext| ext.eq_ignore_ascii_case("aac"))
        .unwrap_or(false)
}

#[cfg(windows)]
#[link(name = "Shlwapi")]
extern "system" {
    fn StrCmpLogicalW(psz1: *const u16, psz2: *const u16) -> i32;
}

#[cfg(windows)]
fn explorer_style_compare(a: &str, b: &str) -> Ordering {
    let a_wide: Vec<u16> = a.encode_utf16().chain(std::iter::once(0)).collect();
    let b_wide: Vec<u16> = b.encode_utf16().chain(std::iter::once(0)).collect();
    unsafe { StrCmpLogicalW(a_wide.as_ptr(), b_wide.as_ptr()).cmp(&0) }
}

#[cfg(not(windows))]
fn explorer_style_compare(a: &str, b: &str) -> Ordering {
    a.to_lowercase()
        .cmp(&b.to_lowercase())
        .then_with(|| a.cmp(b))
}

fn sort_songs_like_explorer(songs: &mut [Song]) {
    songs.sort_by(|a, b| {
        explorer_style_compare(&a.title, &b.title)
            .then_with(|| {
                explorer_style_compare(
                    a.artist.as_deref().unwrap_or(""),
                    b.artist.as_deref().unwrap_or(""),
                )
            })
            .then_with(|| a.id.cmp(&b.id))
    });
}

fn get_covers_dir() -> PathBuf {
    get_library_dir().join("covers")
}

fn picture_extension(mime_type: Option<&MimeType>) -> &'static str {
    match mime_type {
        Some(MimeType::Png) => "png",
        Some(MimeType::Jpeg) => "jpg",
        Some(MimeType::Gif) => "gif",
        Some(MimeType::Bmp) => "bmp",
        Some(MimeType::Tiff) => "tiff",
        _ => "jpg",
    }
}

fn extract_embedded_cover(src_path: &Path, song_id: &str) -> Option<String> {
    let tagged_file = Probe::open(src_path).ok()?.read().ok()?;
    let picture = tagged_file
        .primary_tag()
        .and_then(|tag| {
            tag.get_picture_type(PictureType::CoverFront)
                .or_else(|| tag.pictures().first())
        })
        .or_else(|| {
            tagged_file.tags().iter().find_map(|tag| {
                tag.get_picture_type(PictureType::CoverFront)
                    .or_else(|| tag.pictures().first())
            })
        })?;

    let data = picture.data();
    if data.is_empty() {
        return None;
    }

    let covers_dir = get_covers_dir();
    if fs::create_dir_all(&covers_dir).is_err() {
        return None;
    }
    let ext = picture_extension(picture.mime_type());
    let filename = format!("{}.{}", song_id, ext);
    let absolute_path = covers_dir.join(&filename);
    if fs::write(&absolute_path, data).is_err() {
        return None;
    }
    Some(format!("covers/{}", filename))
}

fn ensure_song_cover_path(
    conn: &rusqlite::Connection,
    song_id: &str,
) -> Result<Option<String>, String> {
    let current: Option<String> = conn
        .query_row(
            "SELECT cover_path FROM songs WHERE id = ?1",
            params![song_id],
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| e.to_string())?
        .flatten();

    if let Some(path) = current {
        if get_library_dir().join(&path).exists() {
            return Ok(Some(path));
        }
    }

    let audio_path: Option<String> = conn
        .query_row(
            "SELECT filepath FROM audio_files WHERE song_id = ?1 ORDER BY is_primary DESC, created_at ASC LIMIT 1",
            params![song_id],
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| e.to_string())?;

    let Some(filepath) = audio_path else {
        return Ok(None);
    };
    let absolute_audio_path = get_library_dir().join(filepath);
    let cover_path = extract_embedded_cover(&absolute_audio_path, song_id);
    if let Some(path) = &cover_path {
        conn.execute(
            "UPDATE songs SET cover_path = ?1, updated_at = CURRENT_TIMESTAMP WHERE id = ?2",
            params![path, song_id],
        )
        .map_err(|e| e.to_string())?;
    }
    Ok(cover_path)
}

fn saved_lyric_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<SavedLyric> {
    let is_selected: i32 = row.get(11)?;
    Ok(SavedLyric {
        id: row.get(0)?,
        song_id: row.get(1)?,
        audio_version_id: row.get(2)?,
        source: row.get(3)?,
        source_id: row.get(4)?,
        title: row.get(5)?,
        artist: row.get(6)?,
        content: row.get(7)?,
        translation: row.get(8)?,
        romanized: row.get(9)?,
        offset_ms: row.get(10)?,
        is_selected: is_selected != 0,
        updated_at: row.get(12)?,
    })
}

fn selected_lyric_query() -> &'static str {
    "SELECT id, song_id, audio_version_id, source, source_id, title, artist, content, translation, romanized, offset_ms, is_selected, updated_at
     FROM lyrics"
}

fn ensure_version_belongs_to_song(
    conn: &rusqlite::Connection,
    song_id: &str,
    audio_version_id: &str,
) -> Result<(), String> {
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM audio_files WHERE id = ?1 AND song_id = ?2",
            params![audio_version_id, song_id],
            |row| row.get(0),
        )
        .map_err(|e| e.to_string())?;
    if count == 0 {
        return Err("歌词绑定的音源版本不属于当前歌曲。".to_string());
    }
    Ok(())
}

fn absolute_audio_path_from_relative(relative_path: &str) -> PathBuf {
    let filename = relative_path.split('/').last().unwrap_or(relative_path);
    get_files_dir().join(filename)
}

fn read_text_file_if_exists(path: &Path) -> Option<String> {
    if !path.exists() {
        return None;
    }
    let content = fs::read_to_string(path).ok()?;
    let trimmed = content.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn embedded_lyrics_from_audio(path: &Path) -> Option<String> {
    let tagged_file = Probe::open(path).ok()?.read().ok()?;
    let primary = tagged_file
        .primary_tag()
        .and_then(|tag| tag.get_string(&ItemKey::Lyrics))
        .map(str::trim)
        .filter(|text| !text.is_empty())
        .map(ToOwned::to_owned);
    if primary.is_some() {
        return primary;
    }
    tagged_file
        .first_tag()
        .and_then(|tag| tag.get_string(&ItemKey::Lyrics))
        .map(str::trim)
        .filter(|text| !text.is_empty())
        .map(ToOwned::to_owned)
}

fn copy_sidecar_lyrics(src_path: &Path, dest_audio_path: &Path) {
    let source_lrc = src_path.with_extension("lrc");
    if !source_lrc.exists() {
        return;
    }
    let dest_lrc = dest_audio_path.with_extension("lrc");
    let _ = fs::copy(source_lrc, dest_lrc);
}

fn remove_sidecar_lyrics(audio_path: &Path) {
    let sidecar = audio_path.with_extension("lrc");
    if sidecar.exists() {
        let _ = fs::remove_file(sidecar);
    }
}

#[frb(sync)]
pub fn is_library_initialized() -> bool {
    let lib_dir = get_library_dir();
    lib_dir.exists() && lib_dir.join("database.db").exists()
}

pub fn initialize_library_path(path: String) -> Result<(), String> {
    let p = std::path::PathBuf::from(path);
    set_library_dir(p);
    init_db().map_err(|e| e.to_string())?;
    Ok(())
}

/// Flush committed WAL pages before sync transfers database.db by itself.
pub fn checkpoint_library_database() -> Result<(), String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    conn.execute_batch("PRAGMA wal_checkpoint(TRUNCATE);")
        .map_err(|e| e.to_string())
}

pub fn get_songs() -> Result<Vec<Song>, String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;

    let mut stmt = conn
        .prepare(
            "SELECT id, title, artist, album, lyrics, cover_path, rating, created_at FROM songs",
        )
        .map_err(|e| e.to_string())?;

    let song_rows = stmt
        .query_map([], |row| {
            Ok(Song {
                id: row.get(0)?,
                title: row.get(1)?,
                artist: row.get(2)?,
                album: row.get(3)?,
                lyrics: row.get(4)?,
                cover_path: row.get(5)?,
                rating: row.get(6)?,
                created_at: row.get(7)?,
                versions: Vec::new(),
                tags: Vec::new(),
            })
        })
        .map_err(|e| e.to_string())?;

    let mut songs = Vec::new();
    for song_res in song_rows {
        let mut song = song_res.map_err(|e| e.to_string())?;

        let mut v_stmt = conn.prepare(
            "SELECT id, song_id, filepath, original_name, format, bitrate, sample_rate, duration, file_size, is_enabled, is_primary, md5, bit_depth, loudness, metadata_scanned FROM audio_files WHERE song_id = ?1"
        ).map_err(|e| e.to_string())?;

        let v_rows = v_stmt
            .query_map(params![song.id], |row| {
                let is_enabled_int: i32 = row.get(9)?;
                let is_primary_int: i32 = row.get(10)?;
                Ok(AudioVersion {
                    id: row.get(0)?,
                    song_id: row.get(1)?,
                    filepath: row.get(2)?,
                    original_name: row.get(3)?,
                    format: row.get(4)?,
                    bitrate: row.get(5)?,
                    sample_rate: row.get(6)?,
                    duration: row.get(7)?,
                    file_size: row.get(8)?,
                    is_enabled: is_enabled_int != 0,
                    is_primary: is_primary_int != 0,
                    md5: row.get(11)?,
                    bit_depth: row.get(12)?,
                    loudness: row.get(13)?,
                    metadata_scanned: row.get::<_, i32>(14)? != 0,
                })
            })
            .map_err(|e| e.to_string())?;

        for v in v_rows {
            song.versions.push(v.map_err(|e| e.to_string())?);
        }

        let mut t_stmt = conn
            .prepare(
                "SELECT t.id, t.name, t.color, t.category FROM tags t 
             JOIN song_tags st ON t.id = st.tag_id 
             WHERE st.song_id = ?1",
            )
            .map_err(|e| e.to_string())?;

        let t_rows = t_stmt
            .query_map(params![song.id], |row| {
                Ok(Tag {
                    id: row.get(0)?,
                    name: row.get(1)?,
                    color: row.get(2)?,
                    category: row.get(3)?,
                })
            })
            .map_err(|e| e.to_string())?;

        for t in t_rows {
            song.tags.push(t.map_err(|e| e.to_string())?);
        }

        songs.push(song);
    }

    sort_songs_like_explorer(&mut songs);

    Ok(songs)
}

pub fn get_tags() -> Result<Vec<Tag>, String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    let mut stmt = conn
        .prepare("SELECT id, name, color, category FROM tags ORDER BY category, name")
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |row| {
            Ok(Tag {
                id: row.get(0)?,
                name: row.get(1)?,
                color: row.get(2)?,
                category: row.get(3)?,
            })
        })
        .map_err(|e| e.to_string())?;

    let mut tags = Vec::new();
    for r in rows {
        tags.push(r.map_err(|e| e.to_string())?);
    }
    Ok(tags)
}

pub fn get_playlists() -> Result<Vec<Playlist>, String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    let mut stmt = conn
        .prepare("SELECT id, name, description, created_at FROM playlists ORDER BY created_at ASC")
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |row| {
            Ok(Playlist {
                id: row.get(0)?,
                name: row.get(1)?,
                description: row.get(2)?,
                created_at: row.get(3)?,
            })
        })
        .map_err(|e| e.to_string())?;
    let mut playlists = Vec::new();
    for r in rows {
        playlists.push(r.map_err(|e| e.to_string())?);
    }
    Ok(playlists)
}

pub fn start_audio_server() -> u16 {
    crate::audio::server::start();
    std::thread::sleep(std::time::Duration::from_millis(50));
    crate::audio::server::get_port()
}

fn estimate_duration_with_symphonia(path: &Path) -> Option<f64> {
    let file = fs::File::open(path).ok()?;
    let mss = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }

    let probed = symphonia::default::get_probe()
        .format(
            &hint,
            mss,
            &FormatOptions::default(),
            &MetadataOptions::default(),
        )
        .ok()?;
    let mut format = probed.format;
    let (track_id, n_frames, sample_rate, time_base) = {
        let track = format
            .tracks()
            .iter()
            .find(|t| t.codec_params.codec != symphonia::core::codecs::CODEC_TYPE_NULL)?;
        (
            track.id,
            track.codec_params.n_frames,
            track.codec_params.sample_rate,
            track.codec_params.time_base,
        )
    };
    let raw_aac = is_raw_aac_path(path);

    if !raw_aac {
        if let (Some(n_frames), Some(sample_rate)) = (n_frames, sample_rate) {
            if sample_rate > 0 {
                let duration = n_frames as f64 / sample_rate as f64;
                if duration.is_finite() && duration > 0.0 {
                    return Some(duration);
                }
            }
        }

        if let (Some(time_base), Some(n_frames)) = (time_base, n_frames) {
            let time = time_base.calc_time(n_frames);
            let duration = time.seconds as f64 + time.frac;
            if duration.is_finite() && duration > 0.0 {
                return Some(duration);
            }
        }
    }

    let mut packet_duration_sum = 0u64;
    let mut last_packet_end = None;
    loop {
        match format.next_packet() {
            Ok(packet) => {
                if packet.track_id() != track_id {
                    continue;
                }
                packet_duration_sum = packet_duration_sum.saturating_add(packet.dur());
                last_packet_end = Some(packet.ts().saturating_add(packet.dur()));
            }
            Err(Error::IoError(ref err)) if err.kind() == std::io::ErrorKind::UnexpectedEof => {
                break;
            }
            Err(Error::ResetRequired) => continue,
            Err(_) => break,
        }
    }

    if raw_aac && packet_duration_sum > 0 {
        if let Some(sample_rate) = sample_rate {
            let duration = packet_duration_sum as f64 / sample_rate as f64;
            if duration.is_finite() && duration > 0.0 {
                return Some(duration);
            }
        }
    }

    if let Some(packet_end) = last_packet_end {
        if let Some(time_base) = time_base {
            let time = time_base.calc_time(packet_end);
            let duration = time.seconds as f64 + time.frac;
            if duration.is_finite() && duration > 0.0 {
                return Some(duration);
            }
        }
        if let Some(sample_rate) = sample_rate {
            let duration = packet_end as f64 / sample_rate as f64;
            if duration.is_finite() && duration > 0.0 {
                return Some(duration);
            }
        }
    }

    None
}

fn estimate_duration_from_bitrate(path: &Path, bitrate_bps: Option<u32>) -> Option<f64> {
    let bitrate = bitrate_bps?;
    if bitrate == 0 {
        return None;
    }
    let file_size = path.metadata().ok()?.len() as f64;
    let duration = (file_size * 8.0) / (bitrate as f64);
    if duration.is_finite() && duration > 0.0 && duration < 86400.0 {
        Some(duration)
    } else {
        None
    }
}

fn reliable_duration(path: &Path, lofty_duration: f64, lofty_bitrate: Option<u32>) -> f64 {
    if is_raw_aac_path(path) {
        if let Some(d) = estimate_duration_with_symphonia(path) {
            return d;
        }
    }

    if lofty_duration.is_finite() && lofty_duration > 0.0 {
        return lofty_duration;
    }
    if let Some(d) = estimate_duration_with_symphonia(path) {
        return d;
    }
    if let Some(d) = estimate_duration_from_bitrate(path, lofty_bitrate) {
        return d;
    }
    0.0
}

pub fn get_library_path() -> Result<String, String> {
    Ok(get_library_dir().to_string_lossy().to_string())
}

pub fn import_song(filepath: String) -> Result<Song, String> {
    let src_path = Path::new(&filepath);
    if !src_path.exists() {
        return Err("File does not exist".to_string());
    }

    let original_name = src_path
        .file_name()
        .ok_or_else(|| "Invalid file name".to_string())?
        .to_string_lossy()
        .to_string();

    let ext = src_path
        .extension()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();

    let file_size = src_path.metadata().map_err(|e| e.to_string())?.len() as i64;

    let tagged_file = Probe::open(src_path)
        .map_err(|e| format!("Failed to open file probe: {}", e))?
        .read()
        .map_err(|e| format!("Failed to read metadata: {}", e))?;

    let properties = tagged_file.properties();
    let duration = reliable_duration(
        src_path,
        properties.duration().as_secs_f64(),
        properties.audio_bitrate().map(|b| b as u32),
    );
    let bitrate = properties.audio_bitrate().map(|b| (b * 1000) as i32);
    let sample_rate = properties.sample_rate().map(|s| s as i32);
    let bit_depth = properties.bit_depth().map(|d| d as i32);
    let loudness = crate::audio::dsp::calculate_loudness(&src_path.to_string_lossy()).ok();

    let mut title = src_path
        .file_stem()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();
    let mut artist = None;
    let mut album = None;

    if let Some(primary_tag) = tagged_file.primary_tag() {
        if let Some(t) = primary_tag.title() {
            title = t.to_string();
        }
        if let Some(a) = primary_tag.artist() {
            artist = Some(a.to_string());
        }
        if let Some(al) = primary_tag.album() {
            album = Some(al.to_string());
        }
    } else if let Some(first_tag) = tagged_file.first_tag() {
        if let Some(t) = first_tag.title() {
            title = t.to_string();
        }
        if let Some(a) = first_tag.artist() {
            artist = Some(a.to_string());
        }
        if let Some(al) = first_tag.album() {
            album = Some(al.to_string());
        }
    }

    let file_data = fs::read(src_path).map_err(|e| e.to_string())?;
    let file_md5 = format!("{:x}", md5::compute(file_data));

    let conn = establish_connection().map_err(|e| e.to_string())?;

    let md5_exists: bool = conn
        .query_row(
            "SELECT COUNT(*) FROM audio_files WHERE md5 = ?1",
            params![file_md5],
            |row| row.get::<_, i64>(0).map(|count| count > 0),
        )
        .map_err(|e| e.to_string())?;

    if md5_exists {
        return Err(format!(
            "音频文件 [{}] 已存在于音乐库中，请勿重复导入！",
            original_name
        ));
    }

    let uuid = Uuid::new_v4().to_string();
    let dest_filename = format!("{}.{}", uuid, ext);
    let dest_relative_path = format!("files/{}", dest_filename);
    let dest_absolute_path = get_files_dir().join(&dest_filename);

    fs::copy(src_path, &dest_absolute_path).map_err(|e| e.to_string())?;
    copy_sidecar_lyrics(src_path, &dest_absolute_path);

    let song_id: String = match artist {
        Some(ref art_name) => conn
            .query_row(
                "SELECT id FROM songs WHERE title = ?1 AND artist = ?2",
                params![title, art_name],
                |row| row.get(0),
            )
            .optional(),
        None => conn
            .query_row(
                "SELECT id FROM songs WHERE title = ?1 AND artist IS NULL",
                params![title],
                |row| row.get(0),
            )
            .optional(),
    }
    .map_err(|e| e.to_string())?
    .unwrap_or_else(|| {
        let new_id = Uuid::new_v4().to_string();
        conn.execute(
            "INSERT INTO songs (id, title, artist, album) VALUES (?1, ?2, ?3, ?4)",
            params![new_id, title, artist, album],
        )
        .unwrap();
        new_id
    });

    let version_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM audio_files WHERE song_id = ?1",
            params![song_id],
            |row| row.get(0),
        )
        .map_err(|e| e.to_string())?;
    let is_primary = if version_count == 0 { 1 } else { 0 };

    let version_id = Uuid::new_v4().to_string();
    conn.execute(
        "INSERT INTO audio_files (id, song_id, filepath, original_name, format, bitrate, sample_rate, duration, file_size, is_enabled, is_primary, md5, bit_depth, loudness) 
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 1, ?10, ?11, ?12, ?13)",
        params![
            version_id,
            song_id,
            dest_relative_path,
            original_name,
            ext,
            bitrate,
            sample_rate,
            duration,
            file_size,
            is_primary,
            file_md5,
            bit_depth,
            loudness
        ]
    ).map_err(|e| e.to_string())?;

    let _ = ensure_song_cover_path(&conn, &song_id);

    let mut stmt = conn.prepare(
        "SELECT id, title, artist, album, lyrics, cover_path, rating, created_at FROM songs WHERE id = ?1"
    ).map_err(|e| e.to_string())?;

    let mut song = stmt
        .query_row(params![song_id], |row| {
            Ok(Song {
                id: row.get(0)?,
                title: row.get(1)?,
                artist: row.get(2)?,
                album: row.get(3)?,
                lyrics: row.get(4)?,
                cover_path: row.get(5)?,
                rating: row.get(6)?,
                created_at: row.get(7)?,
                versions: Vec::new(),
                tags: Vec::new(),
            })
        })
        .map_err(|e| e.to_string())?;

    let mut v_stmt = conn.prepare(
        "SELECT id, song_id, filepath, original_name, format, bitrate, sample_rate, duration, file_size, is_enabled, is_primary, md5, bit_depth, loudness, metadata_scanned FROM audio_files WHERE song_id = ?1"
    ).map_err(|e| e.to_string())?;
    let v_rows = v_stmt
        .query_map(params![song.id], |row| {
            let is_enabled_int: i32 = row.get(9)?;
            let is_primary_int: i32 = row.get(10)?;
            Ok(AudioVersion {
                id: row.get(0)?,
                song_id: row.get(1)?,
                filepath: row.get(2)?,
                original_name: row.get(3)?,
                format: row.get(4)?,
                bitrate: row.get(5)?,
                sample_rate: row.get(6)?,
                duration: row.get(7)?,
                file_size: row.get(8)?,
                is_enabled: is_enabled_int != 0,
                is_primary: is_primary_int != 0,
                md5: row.get(11)?,
                bit_depth: row.get(12)?,
                loudness: row.get(13)?,
                metadata_scanned: row.get::<_, i32>(14)? != 0,
            })
        })
        .map_err(|e| e.to_string())?;
    for v in v_rows {
        song.versions.push(v.map_err(|e| e.to_string())?);
    }

    let mut t_stmt = conn
        .prepare(
            "SELECT t.id, t.name, t.color, t.category FROM tags t 
         JOIN song_tags st ON t.id = st.tag_id 
         WHERE st.song_id = ?1",
        )
        .map_err(|e| e.to_string())?;
    let t_rows = t_stmt
        .query_map(params![song.id], |row| {
            Ok(Tag {
                id: row.get(0)?,
                name: row.get(1)?,
                color: row.get(2)?,
                category: row.get(3)?,
            })
        })
        .map_err(|e| e.to_string())?;
    for t in t_rows {
        song.tags.push(t.map_err(|e| e.to_string())?);
    }

    Ok(song)
}

pub fn import_song_with_metadata(
    filepath: String,
    title: String,
    artist: String,
) -> Result<(), String> {
    let src_path = Path::new(&filepath);
    if !src_path.exists() {
        return Err("File does not exist".to_string());
    }

    let original_name = src_path
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();

    let ext = src_path
        .extension()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();

    let file_size = src_path.metadata().map_err(|e| e.to_string())?.len() as i64;

    let tagged_file = Probe::open(src_path)
        .map_err(|e| format!("Failed to open file probe: {}", e))?
        .read()
        .map_err(|e| format!("Failed to read metadata: {}", e))?;

    let properties = tagged_file.properties();
    let duration = reliable_duration(
        src_path,
        properties.duration().as_secs_f64(),
        properties.audio_bitrate().map(|b| b as u32),
    );
    let bitrate = properties.audio_bitrate().map(|b| (b * 1000) as i32);
    let sample_rate = properties.sample_rate().map(|s| s as i32);
    let bit_depth = properties.bit_depth().map(|d| d as i32);
    let loudness = crate::audio::dsp::calculate_loudness(&src_path.to_string_lossy()).ok();

    let file_data = fs::read(src_path).map_err(|e| e.to_string())?;
    let file_md5 = format!("{:x}", md5::compute(file_data));

    let conn = establish_connection().map_err(|e| e.to_string())?;

    let md5_exists: bool = conn
        .query_row(
            "SELECT COUNT(*) FROM audio_files WHERE md5 = ?1",
            params![file_md5],
            |row| row.get::<_, i64>(0).map(|count| count > 0),
        )
        .map_err(|e| e.to_string())?;

    if md5_exists {
        return Err(format!(
            "音频文件 [{}] 已存在于库中，请勿重复导入！",
            original_name
        ));
    }

    let uuid = Uuid::new_v4().to_string();
    let dest_filename = format!("{}.{}", uuid, ext);
    let dest_relative_path = format!("files/{}", dest_filename);
    let dest_absolute_path = get_files_dir().join(&dest_filename);

    fs::copy(src_path, &dest_absolute_path).map_err(|e| e.to_string())?;
    copy_sidecar_lyrics(src_path, &dest_absolute_path);

    let artist_opt = if artist.trim().is_empty() || artist == "未知歌手" {
        None
    } else {
        Some(artist.trim().to_string())
    };
    let song_id: String = match &artist_opt {
        None => {
            let id_opt: Option<String> = conn
                .query_row(
                    "SELECT id FROM songs WHERE title = ?1 AND artist IS NULL",
                    params![title.trim()],
                    |row| row.get(0),
                )
                .optional()
                .map_err(|e| e.to_string())?;
            id_opt
        }
        Some(art) => {
            let id_opt: Option<String> = conn
                .query_row(
                    "SELECT id FROM songs WHERE title = ?1 AND artist = ?2",
                    params![title.trim(), art],
                    |row| row.get(0),
                )
                .optional()
                .map_err(|e| e.to_string())?;
            id_opt
        }
    }
    .unwrap_or_else(|| {
        let new_id = Uuid::new_v4().to_string();
        conn.execute(
            "INSERT INTO songs (id, title, artist) VALUES (?1, ?2, ?3)",
            params![new_id, title.trim(), artist_opt],
        )
        .unwrap();
        new_id
    });

    let version_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM audio_files WHERE song_id = ?1",
            params![song_id],
            |row| row.get(0),
        )
        .map_err(|e| e.to_string())?;
    let is_primary = if version_count == 0 { 1 } else { 0 };

    let version_id = Uuid::new_v4().to_string();
    conn.execute(
        "INSERT INTO audio_files (id, song_id, filepath, original_name, format, bitrate, sample_rate, duration, file_size, is_enabled, is_primary, md5, bit_depth, loudness) 
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 1, ?10, ?11, ?12, ?13)",
        params![
            version_id,
            song_id,
            dest_relative_path,
            original_name,
            ext,
            bitrate,
            sample_rate,
            duration,
            file_size,
            is_primary,
            file_md5,
            bit_depth,
            loudness
        ]
    ).map_err(|e| e.to_string())?;

    let _ = ensure_song_cover_path(&conn, &song_id);

    Ok(())
}

pub fn import_audio_version_for_song(
    song_id: String,
    filepath: String,
) -> Result<AudioVersion, String> {
    let src_path = Path::new(&filepath);
    if !src_path.exists() {
        return Err("File does not exist".to_string());
    }

    let original_name = src_path
        .file_name()
        .ok_or_else(|| "Invalid file name".to_string())?
        .to_string_lossy()
        .to_string();

    let ext = src_path
        .extension()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();

    let file_size = src_path.metadata().map_err(|e| e.to_string())?.len() as i64;

    let tagged_file = Probe::open(src_path)
        .map_err(|e| format!("Failed to open file probe: {}", e))?
        .read()
        .map_err(|e| format!("Failed to read metadata: {}", e))?;

    let properties = tagged_file.properties();
    let duration = reliable_duration(
        src_path,
        properties.duration().as_secs_f64(),
        properties.audio_bitrate().map(|b| b as u32),
    );
    let bitrate = properties.audio_bitrate().map(|b| (b * 1000) as i32);
    let sample_rate = properties.sample_rate().map(|s| s as i32);
    let bit_depth = properties.bit_depth().map(|d| d as i32);

    let loudness = crate::audio::dsp::calculate_loudness(&src_path.to_string_lossy()).ok();

    let file_data = fs::read(src_path).map_err(|e| e.to_string())?;
    let file_md5 = format!("{:x}", md5::compute(file_data));

    let conn = establish_connection().map_err(|e| e.to_string())?;

    let md5_exists: bool = conn
        .query_row(
            "SELECT COUNT(*) FROM audio_files WHERE md5 = ?1",
            params![file_md5],
            |row| row.get::<_, i64>(0).map(|count| count > 0),
        )
        .map_err(|e| e.to_string())?;

    if md5_exists {
        return Err(format!("该音频文件已存在于库中，请勿重复导入！"));
    }

    let uuid = Uuid::new_v4().to_string();
    let dest_filename = format!("{}.{}", uuid, ext);
    let dest_relative_path = format!("files/{}", dest_filename);
    let dest_absolute_path = get_files_dir().join(&dest_filename);

    fs::copy(src_path, &dest_absolute_path).map_err(|e| e.to_string())?;
    copy_sidecar_lyrics(src_path, &dest_absolute_path);

    let version_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM audio_files WHERE song_id = ?1",
            params![song_id],
            |row| row.get(0),
        )
        .map_err(|e| e.to_string())?;
    let is_primary = if version_count == 0 { 1 } else { 0 };

    let version_id = Uuid::new_v4().to_string();
    conn.execute(
        "INSERT INTO audio_files (id, song_id, filepath, original_name, format, bitrate, sample_rate, duration, file_size, is_enabled, is_primary, md5, bit_depth, loudness) 
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 1, ?10, ?11, ?12, ?13)",
        params![
            version_id,
            song_id,
            dest_relative_path,
            original_name,
            ext,
            bitrate,
            sample_rate,
            duration,
            file_size,
            is_primary,
            file_md5,
            bit_depth,
            loudness
        ]
    ).map_err(|e| e.to_string())?;

    let _ = ensure_song_cover_path(&conn, &song_id);

    Ok(AudioVersion {
        id: version_id,
        song_id,
        filepath: dest_relative_path,
        original_name,
        format: Some(ext),
        bitrate,
        sample_rate,
        duration,
        file_size,
        is_enabled: true,
        is_primary: is_primary != 0,
        md5: Some(file_md5),
        bit_depth,
        loudness,
        metadata_scanned: false,
    })
}

pub fn ensure_song_cover(song_id: String) -> Result<Option<String>, String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    ensure_song_cover_path(&conn, &song_id)
}

pub fn update_version_status(
    version_id: String,
    _is_enabled: bool,
    is_primary: bool,
) -> Result<(), String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;

    if is_primary {
        let song_id: String = conn
            .query_row(
                "SELECT song_id FROM audio_files WHERE id = ?1",
                params![version_id],
                |row| row.get(0),
            )
            .map_err(|e| e.to_string())?;

        conn.execute(
            "UPDATE audio_files SET is_primary = 0 WHERE song_id = ?1",
            params![song_id],
        )
        .map_err(|e| e.to_string())?;

        conn.execute(
            "UPDATE audio_files SET is_primary = 1, is_enabled = 1 WHERE id = ?1",
            params![version_id],
        )
        .map_err(|e| e.to_string())?;
    }

    Ok(())
}

pub fn update_song_metadata(song_id: String, title: String, artist: String) -> Result<(), String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    let artist_val = if artist.trim().is_empty() || artist.trim() == "未知歌手" {
        None
    } else {
        Some(artist.trim().to_string())
    };
    conn.execute(
        "UPDATE songs SET title = ?1, artist = ?2 WHERE id = ?3",
        params![title.trim(), artist_val, song_id],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn get_selected_lyric(
    song_id: String,
    audio_version_id: Option<String>,
) -> Result<Option<SavedLyric>, String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;

    if let Some(version_id) = audio_version_id {
        ensure_version_belongs_to_song(&conn, &song_id, &version_id)?;
        let sql = format!(
            "{} WHERE song_id = ?1 AND audio_version_id = ?2 AND is_selected = 1 ORDER BY updated_at DESC LIMIT 1",
            selected_lyric_query()
        );
        let version_lyric = conn
            .query_row(&sql, params![song_id, version_id], saved_lyric_from_row)
            .optional()
            .map_err(|e| e.to_string())?;
        if version_lyric.is_some() {
            return Ok(version_lyric);
        }
    }

    let sql = format!(
        "{} WHERE song_id = ?1 AND audio_version_id IS NULL AND is_selected = 1 ORDER BY updated_at DESC LIMIT 1",
        selected_lyric_query()
    );
    conn.query_row(&sql, params![song_id], saved_lyric_from_row)
        .optional()
        .map_err(|e| e.to_string())
}

pub fn get_lyrics_for_song(song_id: String) -> Result<Vec<SavedLyric>, String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    let sql = format!(
        "{} WHERE song_id = ?1 ORDER BY audio_version_id IS NULL, is_selected DESC, updated_at DESC",
        selected_lyric_query()
    );
    let mut stmt = conn.prepare(&sql).map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map(params![song_id], saved_lyric_from_row)
        .map_err(|e| e.to_string())?;

    let mut lyrics = Vec::new();
    for row in rows {
        lyrics.push(row.map_err(|e| e.to_string())?);
    }
    Ok(lyrics)
}

pub fn get_local_lyric_candidates(
    song_id: String,
    audio_version_id: Option<String>,
) -> Result<Vec<LocalLyricCandidate>, String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;

    let (title, artist, legacy_lyrics): (String, Option<String>, Option<String>) = conn
        .query_row(
            "SELECT title, artist, lyrics FROM songs WHERE id = ?1",
            params![song_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .map_err(|e| e.to_string())?;

    let version = match audio_version_id {
        Some(version_id) => {
            ensure_version_belongs_to_song(&conn, &song_id, &version_id)?;
            conn.query_row(
                "SELECT id, filepath, original_name FROM audio_files WHERE id = ?1",
                params![version_id],
                |row| {
                    Ok((
                        row.get::<_, String>(0)?,
                        row.get::<_, String>(1)?,
                        row.get::<_, String>(2)?,
                    ))
                },
            )
            .optional()
            .map_err(|e| e.to_string())?
        }
        None => conn
            .query_row(
                "SELECT id, filepath, original_name FROM audio_files WHERE song_id = ?1 ORDER BY is_primary DESC LIMIT 1",
                params![song_id],
                |row| {
                    Ok((
                        row.get::<_, String>(0)?,
                        row.get::<_, String>(1)?,
                        row.get::<_, String>(2)?,
                    ))
                },
            )
            .optional()
            .map_err(|e| e.to_string())?,
    };

    let mut candidates = Vec::<LocalLyricCandidate>::new();
    let mut seen_contents = Vec::<String>::new();
    let mut push_candidate = |source: &str,
                              source_id: Option<String>,
                              content: String,
                              candidate_title: String,
                              candidate_artist: Option<String>| {
        let normalized = content.trim().replace("\r\n", "\n").replace('\r', "\n");
        if normalized.is_empty() || seen_contents.iter().any(|item| item == &normalized) {
            return;
        }
        seen_contents.push(normalized.clone());
        candidates.push(LocalLyricCandidate {
            source: source.to_string(),
            source_id,
            title: candidate_title,
            artist: candidate_artist,
            content: normalized,
        });
    };

    if let Some((version_id, filepath, original_name)) = version {
        let abs_path = absolute_audio_path_from_relative(&filepath);
        if let Some(content) = embedded_lyrics_from_audio(&abs_path) {
            push_candidate(
                "local_embedded",
                Some(version_id.clone()),
                content,
                title.clone(),
                artist.clone(),
            );
        }

        let sidecar_path = abs_path.with_extension("lrc");
        if let Some(content) = read_text_file_if_exists(&sidecar_path) {
            push_candidate(
                "local_lrc",
                Some(sidecar_path.to_string_lossy().to_string()),
                content,
                title.clone(),
                artist.clone(),
            );
        }

        let original_stem_lrc = get_files_dir().join(
            Path::new(&original_name)
                .file_stem()
                .unwrap_or_default()
                .to_string_lossy()
                .to_string()
                + ".lrc",
        );
        if let Some(content) = read_text_file_if_exists(&original_stem_lrc) {
            push_candidate(
                "local_lrc",
                Some(original_stem_lrc.to_string_lossy().to_string()),
                content,
                title.clone(),
                artist.clone(),
            );
        }
    }

    if let Some(content) = legacy_lyrics {
        push_candidate("legacy_song", Some(song_id), content, title, artist);
    }

    Ok(candidates)
}

pub fn save_lyric(
    song_id: String,
    audio_version_id: Option<String>,
    source: String,
    source_id: Option<String>,
    title: String,
    artist: Option<String>,
    content: String,
    translation: Option<String>,
    romanized: Option<String>,
    offset_ms: i32,
) -> Result<SavedLyric, String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    let trimmed_content = content.trim().replace("\r\n", "\n").replace('\r', "\n");
    if trimmed_content.is_empty() {
        return Err("歌词内容不能为空。".to_string());
    }

    let song_exists: bool = conn
        .query_row(
            "SELECT COUNT(*) FROM songs WHERE id = ?1",
            params![song_id],
            |row| row.get::<_, i64>(0).map(|count| count > 0),
        )
        .map_err(|e| e.to_string())?;
    if !song_exists {
        return Err("歌曲不存在。".to_string());
    }

    if let Some(version_id) = audio_version_id.as_deref() {
        ensure_version_belongs_to_song(&conn, &song_id, version_id)?;
        conn.execute(
            "UPDATE lyrics SET is_selected = 0 WHERE song_id = ?1 AND audio_version_id = ?2",
            params![song_id, version_id],
        )
        .map_err(|e| e.to_string())?;
    } else {
        conn.execute(
            "UPDATE lyrics SET is_selected = 0 WHERE song_id = ?1 AND audio_version_id IS NULL",
            params![song_id],
        )
        .map_err(|e| e.to_string())?;
    }

    let id = Uuid::new_v4().to_string();
    conn.execute(
        "INSERT INTO lyrics (id, song_id, audio_version_id, source, source_id, title, artist, content, translation, romanized, offset_ms, is_selected, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, 1, CURRENT_TIMESTAMP)",
        params![
            id,
            song_id,
            audio_version_id,
            source,
            source_id,
            title.trim(),
            artist.map(|value| value.trim().to_string()).filter(|value| !value.is_empty()),
            trimmed_content,
            translation.map(|value| value.trim().to_string()).filter(|value| !value.is_empty()),
            romanized.map(|value| value.trim().to_string()).filter(|value| !value.is_empty()),
            offset_ms,
        ],
    )
    .map_err(|e| e.to_string())?;

    let sql = format!("{} WHERE id = ?1", selected_lyric_query());
    conn.query_row(&sql, params![id], saved_lyric_from_row)
        .map_err(|e| e.to_string())
}

pub fn select_lyric(lyric_id: String) -> Result<SavedLyric, String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    let (song_id, audio_version_id): (String, Option<String>) = conn
        .query_row(
            "SELECT song_id, audio_version_id FROM lyrics WHERE id = ?1",
            params![lyric_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .map_err(|e| e.to_string())?;

    if let Some(version_id) = audio_version_id.as_deref() {
        conn.execute(
            "UPDATE lyrics SET is_selected = 0 WHERE song_id = ?1 AND audio_version_id = ?2",
            params![song_id, version_id],
        )
        .map_err(|e| e.to_string())?;
    } else {
        conn.execute(
            "UPDATE lyrics SET is_selected = 0 WHERE song_id = ?1 AND audio_version_id IS NULL",
            params![song_id],
        )
        .map_err(|e| e.to_string())?;
    }

    conn.execute(
        "UPDATE lyrics SET is_selected = 1, updated_at = CURRENT_TIMESTAMP WHERE id = ?1",
        params![lyric_id],
    )
    .map_err(|e| e.to_string())?;

    let sql = format!("{} WHERE id = ?1", selected_lyric_query());
    conn.query_row(&sql, params![lyric_id], saved_lyric_from_row)
        .map_err(|e| e.to_string())
}

pub fn update_lyric_offset(lyric_id: String, offset_ms: i32) -> Result<SavedLyric, String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    conn.execute(
        "UPDATE lyrics SET offset_ms = ?1, updated_at = CURRENT_TIMESTAMP WHERE id = ?2",
        params![offset_ms, lyric_id],
    )
    .map_err(|e| e.to_string())?;

    let sql = format!("{} WHERE id = ?1", selected_lyric_query());
    conn.query_row(&sql, params![lyric_id], saved_lyric_from_row)
        .map_err(|e| e.to_string())
}

pub fn delete_lyric(lyric_id: String) -> Result<(), String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    conn.execute("DELETE FROM lyrics WHERE id = ?1", params![lyric_id])
        .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn delete_song(song_id: String) -> Result<(), String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;

    let cover_path: Option<String> = conn
        .query_row(
            "SELECT cover_path FROM songs WHERE id = ?1",
            params![song_id],
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| e.to_string())?
        .flatten();

    let mut stmt = conn
        .prepare("SELECT filepath FROM audio_files WHERE song_id = ?1")
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map(params![song_id], |row| row.get::<_, String>(0))
        .map_err(|e| e.to_string())?;
    let files_dir = get_library_dir();
    for filepath_res in rows {
        if let Ok(filepath) = filepath_res {
            let absolute_path = files_dir.join(filepath);
            if absolute_path.exists() {
                remove_sidecar_lyrics(&absolute_path);
                let _ = fs::remove_file(absolute_path);
            }
        }
    }

    let _ = conn.execute("DELETE FROM lyrics WHERE song_id = ?1", params![song_id]);
    conn.execute("DELETE FROM songs WHERE id = ?1", params![song_id])
        .map_err(|e| e.to_string())?;

    if let Some(path) = cover_path {
        let absolute_path = get_library_dir().join(path);
        if absolute_path.exists() {
            let _ = fs::remove_file(absolute_path);
        }
    }
    Ok(())
}

pub fn delete_audio_version(version_id: String) -> Result<(), String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;

    let (song_id, is_primary): (String, i32) = conn
        .query_row(
            "SELECT song_id, is_primary FROM audio_files WHERE id = ?1",
            params![version_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .map_err(|e| e.to_string())?;

    let filepath: String = conn
        .query_row(
            "SELECT filepath FROM audio_files WHERE id = ?1",
            params![version_id],
            |row| row.get(0),
        )
        .map_err(|e| e.to_string())?;

    let absolute_path = get_library_dir().join(filepath);
    if absolute_path.exists() {
        remove_sidecar_lyrics(&absolute_path);
        let _ = fs::remove_file(absolute_path);
    }

    let _ = conn.execute(
        "DELETE FROM lyrics WHERE audio_version_id = ?1",
        params![version_id],
    );
    conn.execute("DELETE FROM audio_files WHERE id = ?1", params![version_id])
        .map_err(|e| e.to_string())?;

    if is_primary != 0 {
        let next_primary_id: Option<String> = conn
            .query_row(
                "SELECT id FROM audio_files WHERE song_id = ?1 LIMIT 1",
                params![song_id],
                |row| row.get(0),
            )
            .optional()
            .map_err(|e| e.to_string())?;

        if let Some(tid) = next_primary_id {
            conn.execute(
                "UPDATE audio_files SET is_primary = 1, is_enabled = 1 WHERE id = ?1",
                params![tid],
            )
            .map_err(|e| e.to_string())?;
        }
    }

    Ok(())
}

pub fn verify_audio_file(filepath: String) -> bool {
    let lib_dir = get_library_dir();
    let file_path = lib_dir.join(&filepath);
    file_path.exists() && file_path.is_file()
}

pub fn add_tag(
    name: String,
    color: Option<String>,
    category: Option<String>,
) -> Result<Tag, String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    conn.execute(
        "INSERT INTO tags (name, color, category) VALUES (?1, ?2, ?3)",
        params![name, color, category],
    )
    .map_err(|e| e.to_string())?;

    let last_id = conn.last_insert_rowid();
    Ok(Tag {
        id: last_id,
        name,
        color,
        category,
    })
}

pub fn update_tag(
    tag_id: i64,
    name: String,
    color: Option<String>,
    category: Option<String>,
) -> Result<(), String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    conn.execute(
        "UPDATE tags SET name = ?1, color = ?2, category = ?3 WHERE id = ?4",
        params![name.trim(), color, category, tag_id],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn delete_tag(tag_id: i64) -> Result<(), String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    conn.execute("DELETE FROM tags WHERE id = ?1", params![tag_id])
        .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn tag_song(song_id: String, tag_id: i64, bind: bool) -> Result<(), String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    if bind {
        conn.execute(
            "INSERT OR IGNORE INTO song_tags (song_id, tag_id) VALUES (?1, ?2)",
            params![song_id, tag_id],
        )
        .map_err(|e| e.to_string())?;
    } else {
        conn.execute(
            "DELETE FROM song_tags WHERE song_id = ?1 AND tag_id = ?2",
            params![song_id, tag_id],
        )
        .map_err(|e| e.to_string())?;
    }
    Ok(())
}

pub fn create_playlist(name: String) -> Result<Playlist, String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    let id = Uuid::new_v4().to_string();
    conn.execute(
        "INSERT INTO playlists (id, name, description) VALUES (?1, ?2, '')",
        params![id, name],
    )
    .map_err(|e| e.to_string())?;

    let mut stmt = conn
        .prepare("SELECT id, name, description, created_at FROM playlists WHERE id = ?1")
        .map_err(|e| e.to_string())?;
    let playlist = stmt
        .query_row(params![id], |row| {
            Ok(Playlist {
                id: row.get(0)?,
                name: row.get(1)?,
                description: row.get(2)?,
                created_at: row.get(3)?,
            })
        })
        .map_err(|e| e.to_string())?;
    Ok(playlist)
}

pub fn delete_playlist(id: String) -> Result<(), String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    conn.execute("DELETE FROM playlists WHERE id = ?1", params![id])
        .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn rename_playlist(id: String, name: String) -> Result<(), String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    conn.execute(
        "UPDATE playlists SET name = ?1 WHERE id = ?2",
        params![name, id],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn add_songs_to_playlist(playlist_id: String, song_ids: Vec<String>) -> Result<(), String> {
    let mut conn = establish_connection().map_err(|e| e.to_string())?;
    let tx = conn.transaction().map_err(|e| e.to_string())?;

    let max_sort_order: i32 = tx
        .query_row(
            "SELECT COALESCE(MAX(sort_order), -1) FROM playlist_songs WHERE playlist_id = ?1",
            params![playlist_id],
            |row| row.get(0),
        )
        .map_err(|e| e.to_string())?;

    let mut current_order = max_sort_order + 1;
    for song_id in song_ids {
        let exists: i64 = tx
            .query_row(
                "SELECT COUNT(*) FROM playlist_songs WHERE playlist_id = ?1 AND song_id = ?2",
                params![playlist_id, song_id],
                |row| row.get(0),
            )
            .map_err(|e| e.to_string())?;
        if exists == 0 {
            tx.execute(
                "INSERT INTO playlist_songs (playlist_id, song_id, sort_order) VALUES (?1, ?2, ?3)",
                params![playlist_id, song_id, current_order],
            )
            .map_err(|e| e.to_string())?;
            current_order += 1;
        }
    }
    tx.commit().map_err(|e| e.to_string())?;
    Ok(())
}

pub fn remove_songs_from_playlist(
    playlist_id: String,
    song_ids: Vec<String>,
) -> Result<(), String> {
    let mut conn = establish_connection().map_err(|e| e.to_string())?;
    let tx = conn.transaction().map_err(|e| e.to_string())?;
    for song_id in song_ids {
        tx.execute(
            "DELETE FROM playlist_songs WHERE playlist_id = ?1 AND song_id = ?2",
            params![playlist_id, song_id],
        )
        .map_err(|e| e.to_string())?;
    }
    tx.commit().map_err(|e| e.to_string())?;
    Ok(())
}

pub fn get_playlist_songs(playlist_id: String) -> Result<Vec<String>, String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    let mut stmt = conn
        .prepare(
            "SELECT song_id FROM playlist_songs WHERE playlist_id = ?1 ORDER BY sort_order ASC",
        )
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map(params![playlist_id], |row| row.get::<_, String>(0))
        .map_err(|e| e.to_string())?;
    let mut song_ids = Vec::new();
    for r in rows {
        song_ids.push(r.map_err(|e| e.to_string())?);
    }
    Ok(song_ids)
}

fn scan_directory(dir: &Path, files: &mut Vec<std::path::PathBuf>) {
    if dir.is_dir() {
        if let Ok(entries) = fs::read_dir(dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    scan_directory(&path, files);
                } else if path.is_file() {
                    if let Some(ext) = path.extension() {
                        let ext_str = ext.to_string_lossy().to_lowercase();
                        if ["mp3", "wav", "flac", "m4a", "ogg", "aac"].contains(&ext_str.as_str()) {
                            files.push(path);
                        }
                    }
                }
            }
        }
    }
}

pub fn scan_directory_for_preview(dir_path: String) -> Result<Vec<String>, String> {
    let path = Path::new(&dir_path);
    if !path.is_dir() {
        return Err("Not a directory".to_string());
    }
    let mut files = Vec::new();
    scan_directory(path, &mut files);
    let list = files
        .into_iter()
        .map(|f| f.to_string_lossy().to_string())
        .collect();
    Ok(list)
}

pub fn preview_audio_metadata(filepaths: Vec<String>) -> Result<Vec<PreviewInfo>, String> {
    let mut list = Vec::new();
    for fp in filepaths {
        let path = Path::new(&fp);
        let filename = path
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string();

        let mut title = path
            .file_stem()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string();
        let mut artist = "未知歌手".to_string();

        if let Ok(tagged_file) = Probe::open(path).and_then(|p| p.read()) {
            if let Some(primary_tag) = tagged_file.primary_tag() {
                if let Some(t) = primary_tag.title() {
                    title = t.to_string();
                }
                if let Some(a) = primary_tag.artist() {
                    artist = a.to_string();
                }
            }
        }

        list.push(PreviewInfo {
            filepath: fp,
            filename,
            title,
            artist,
        });
    }
    Ok(list)
}

pub fn reset_library() -> Result<(), String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;

    let files_dir = get_files_dir();
    if files_dir.exists() {
        let _ = fs::remove_dir_all(&files_dir);
        let _ = fs::create_dir_all(&files_dir);
    }

    let tables = [
        "lyrics",
        "songs",
        "audio_files",
        "tags",
        "song_tags",
        "playlists",
        "playlist_songs",
    ];
    for table in tables {
        let _ = conn.execute(&format!("DELETE FROM {}", table), []);
    }

    let default_tags = vec![
        ("中文", "#ef4444", "语言"),
        ("英文", "#3b82f6", "语言"),
        ("日韩", "#f43f5e", "语言"),
        ("纯音乐", "#10b981", "流派"),
        ("摇滚", "#f59e0b", "流派"),
        ("流行", "#ec4899", "流派"),
        ("民谣", "#84cc16", "流派"),
        ("古典", "#64748b", "流派"),
        ("伤感", "#8b5cf6", "情绪"),
        ("治愈", "#06b6d4", "情绪"),
        ("欢快", "#eab308", "情绪"),
    ];

    for (name, color, category) in default_tags {
        let _ = conn.execute(
            "INSERT INTO tags (name, color, category) VALUES (?1, ?2, ?3)",
            params![name, color, category],
        );
    }

    Ok(())
}

pub fn export_audio_file(version_id: String, dest_path: String) -> Result<String, String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;

    let (filepath, original_name): (String, String) = conn
        .query_row(
            "SELECT filepath, original_name FROM audio_files WHERE id = ?1",
            params![version_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .map_err(|e| e.to_string())?;

    let src_absolute = get_library_dir().join(&filepath);
    if !src_absolute.exists() {
        return Err("Source file not found in library".to_string());
    }

    let dest_path_obj = Path::new(&dest_path);
    let dest_absolute = if dest_path_obj.is_dir() {
        dest_path_obj.join(&original_name)
    } else {
        dest_path_obj.to_path_buf()
    };

    fs::copy(src_absolute, &dest_absolute).map_err(|e| e.to_string())?;

    Ok(dest_absolute.to_string_lossy().to_string())
}

pub fn update_version_duration(version_id: String, duration: f64) -> Result<(), String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    conn.execute(
        "UPDATE audio_files SET duration = ?1 WHERE id = ?2",
        params![duration, version_id],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn start_rust_playback(
    path: String,
    volume: f32,
    pitch: f64,
    algo: String,
    normalization_gain: f32,
) -> Result<(), String> {
    crate::audio::player::start_playback(path, volume, pitch, algo, normalization_gain)
}

pub fn pause_rust_playback() -> Result<(), String> {
    crate::audio::player::pause_playback()
}

pub fn resume_rust_playback() -> Result<(), String> {
    crate::audio::player::resume_playback()
}

pub fn seek_rust_playback(secs: f64) -> Result<(), String> {
    crate::audio::player::seek_playback(secs)
}

pub fn stop_rust_playback() -> Result<(), String> {
    crate::audio::player::stop_playback()
}

pub fn set_rust_volume(vol: f32) -> Result<(), String> {
    crate::audio::player::set_volume(vol)
}

pub fn set_rust_pitch(pitch: f64, algo: String) -> Result<(), String> {
    crate::audio::player::set_pitch(pitch, algo)
}

pub fn set_rust_output_buffer_ms(ms: i32) -> Result<(), String> {
    crate::audio::player::set_output_buffer_ms(ms)
}

pub fn set_rust_output_latency_mode(mode: String) -> Result<(), String> {
    crate::audio::player::set_output_latency_mode(mode)
}

pub fn set_rust_audio_quality_settings(
    peak_protection_enabled: bool,
    dither_enabled: bool,
    rubberband_window: String,
    rubberband_formant_preserved: bool,
    resampler_quality: String,
) -> Result<(), String> {
    crate::audio::player::set_quality_settings(
        peak_protection_enabled,
        dither_enabled,
        rubberband_window,
        rubberband_formant_preserved,
        resampler_quality,
    )
}

pub fn get_rust_audio_output_info() -> crate::audio::player::AudioOutputInfo {
    crate::audio::player::get_output_info()
}

pub fn get_rust_default_output_device_name() -> Result<String, String> {
    crate::audio::player::default_output_device_name()
}

pub fn get_rust_playback_position() -> f64 {
    crate::audio::player::get_position()
}

pub fn is_rust_playback_finished() -> bool {
    crate::audio::player::is_finished()
}

fn refresh_audio_file_metadata_impl(
    conn: &rusqlite::Connection,
    id: &str,
    abs_path: &Path,
) -> Result<(), String> {
    if !abs_path.exists() {
        return Err("Audio file does not exist".to_string());
    }

    let loudness =
        crate::audio::dsp::calculate_loudness_full(&abs_path.to_string_lossy()).unwrap_or(-15.0);

    if let Ok(tagged_file) = Probe::open(abs_path)
        .map_err(|e| e.to_string())
        .and_then(|p| p.read().map_err(|e| e.to_string()))
    {
        let properties = tagged_file.properties();
        let duration = reliable_duration(
            abs_path,
            properties.duration().as_secs_f64(),
            properties.audio_bitrate().map(|b| b as u32),
        );
        let bitrate = properties.audio_bitrate().map(|b| (b * 1000) as i32);
        let sample_rate = properties.sample_rate().map(|s| s as i32);
        let bit_depth = properties.bit_depth().map(|d| d as i32);

        conn.execute(
            "UPDATE audio_files SET bitrate = ?1, sample_rate = ?2, duration = ?3, bit_depth = ?4, loudness = ?5, metadata_scanned = 1 WHERE id = ?6",
            params![bitrate, sample_rate, duration, bit_depth, loudness, id],
        )
        .map_err(|e| e.to_string())?;
    } else {
        conn.execute(
            "UPDATE audio_files SET loudness = ?1, metadata_scanned = 1 WHERE id = ?2",
            params![loudness, id],
        )
        .map_err(|e| e.to_string())?;
    }

    Ok(())
}

pub fn refresh_audio_file_metadata(version_id: String) -> Result<(), String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    let filepath: String = conn
        .query_row(
            "SELECT filepath FROM audio_files WHERE id = ?1",
            params![version_id],
            |row| row.get(0),
        )
        .map_err(|e| e.to_string())?;

    let filename = filepath.split('/').last().unwrap_or(&filepath);
    let abs_path = get_files_dir().join(filename);
    refresh_audio_file_metadata_impl(&conn, &version_id, &abs_path)
}

pub fn refresh_song_database() -> Result<(), String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    let files_dir = get_files_dir();

    let mut stmt = conn
        .prepare("SELECT id, filepath FROM audio_files")
        .map_err(|e| e.to_string())?;
    let mut entries = Vec::new();
    let rows = stmt
        .query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })
        .map_err(|e| e.to_string())?;

    for r in rows {
        if let Ok((id, filepath)) = r {
            let filename = filepath.split('/').last().unwrap_or(&filepath);
            let abs_path = files_dir.join(filename);
            entries.push((id, abs_path));
        }
    }

    for (id, abs_path) in entries {
        let _ = refresh_audio_file_metadata_impl(&conn, &id, &abs_path);
    }

    Ok(())
}
