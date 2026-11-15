//! Phigros zone playlist, chart metadata, and extracted asset package import.

use super::{paths, playlists, probe, songs, LibraryError, Result};
use crate::database::connection;
use crate::models::{PhigrosChartMeta, PhigrosImportResult, PhigrosSongMeta, Playlist};
use rusqlite::{params, Connection, OptionalExtension};
use serde::Deserialize;
use std::collections::HashMap;
use std::fs;
use std::path::Path;
use uuid::Uuid;

pub const PHIGROS_PLAYLIST_KIND: &str = "phigros";
pub const DEFAULT_PHIGROS_PLAYLIST_NAME: &str = "Phigros";

#[derive(Deserialize)]
struct Manifest {
    #[serde(default)]
    se: HashMap<String, String>,
    songs: Vec<ManifestSong>,
}

#[derive(Deserialize)]
struct ManifestSong {
    phigros_id: String,
    title: String,
    composer: String,
    #[serde(default)]
    illustrator: String,
    chapter: String,
    audio_file: String,
    #[serde(default)]
    cover_file: Option<String>,
    #[serde(default)]
    default_difficulty: Option<String>,
    #[serde(default)]
    duration: Option<f64>,
    #[serde(default)]
    sample_rate: Option<i32>,
    charts: Vec<ManifestChart>,
}

#[derive(Deserialize)]
struct ManifestChart {
    difficulty: String,
    sort_rank: i32,
    rating: f64,
    #[serde(default)]
    charter: String,
    #[serde(default)]
    bpm_min: f64,
    #[serde(default)]
    bpm_max: f64,
    #[serde(default)]
    chart_offset_ms: i32,
    note_count: i32,
    tap_count: i32,
    drag_count: i32,
    hold_count: i32,
    flick_count: i32,
    chart_file: String,
    #[serde(default)]
    audio_file: Option<String>,
    #[serde(default)]
    cover_file: Option<String>,
}

/// Ensures there is a dedicated playlist row with `kind = 'phigros'`.
pub fn ensure_phigros_playlist(conn: &Connection) -> Result<Playlist> {
    if let Some(existing) = conn
        .query_row(
            "SELECT id, name, description, created_at, kind
             FROM playlists WHERE kind = ?1 ORDER BY created_at, rowid LIMIT 1",
            params![PHIGROS_PLAYLIST_KIND],
            playlists::playlist_from_row_pub,
        )
        .optional()?
    {
        return Ok(existing);
    }

    if let Some(named_id) = conn
        .query_row(
            "SELECT id FROM playlists WHERE name = ?1 LIMIT 1",
            params![DEFAULT_PHIGROS_PLAYLIST_NAME],
            |row| row.get::<_, String>(0),
        )
        .optional()?
    {
        conn.execute(
            "UPDATE playlists SET kind = ?1 WHERE id = ?2",
            params![PHIGROS_PLAYLIST_KIND, named_id],
        )?;
        return Ok(conn.query_row(
            "SELECT id, name, description, created_at, kind FROM playlists WHERE id = ?1",
            params![named_id],
            playlists::playlist_from_row_pub,
        )?);
    }

    let id = Uuid::new_v4().to_string();
    conn.execute(
        "INSERT INTO playlists (id, name, description, kind)
         VALUES (?1, ?2, ?3, ?4)",
        params![
            id,
            DEFAULT_PHIGROS_PLAYLIST_NAME,
            "Phigros 曲库、全难度谱面与打击音效专区",
            PHIGROS_PLAYLIST_KIND
        ],
    )?;
    Ok(conn.query_row(
        "SELECT id, name, description, created_at, kind FROM playlists WHERE id = ?1",
        params![id],
        playlists::playlist_from_row_pub,
    )?)
}

/// Batch-loads Phigros metadata and charts keyed by `song_id`.
pub fn load_all_meta(conn: &Connection) -> Result<HashMap<String, PhigrosSongMeta>> {
    let mut map: HashMap<String, PhigrosSongMeta> = HashMap::new();
    let mut song_stmt = conn.prepare(
        "SELECT song_id, phigros_id, chapter, composer, illustrator,
                selected_difficulty, hitsound_mode, hitsound_volume, hitsound_offset_ms
         FROM phigros_songs",
    )?;
    let rows = song_stmt.query_map([], |row| {
        Ok((
            row.get::<_, String>(0)?,
            PhigrosSongMeta {
                phigros_id: row.get(1)?,
                chapter: row.get(2)?,
                composer: row.get(3)?,
                illustrator: row.get(4)?,
                selected_difficulty: row.get(5)?,
                hitsound_mode: row.get(6)?,
                hitsound_volume: row.get(7)?,
                hitsound_offset_ms: row.get(8)?,
                charts: Vec::new(),
            },
        ))
    })?;
    for row in rows {
        let (song_id, meta) = row?;
        map.insert(song_id, meta);
    }
    if map.is_empty() {
        return Ok(map);
    }

    let mut chart_stmt = conn.prepare(
        "SELECT song_id, difficulty, sort_rank, rating, charter, bpm_min, bpm_max,
                chart_offset_ms, note_count, tap_count, drag_count, hold_count,
                flick_count, audio_rel_path, cover_rel_path, chart_rel_path
         FROM phigros_charts
         ORDER BY sort_rank, difficulty",
    )?;
    let chart_rows = chart_stmt.query_map([], |row| {
        Ok((
            row.get::<_, String>(0)?,
            PhigrosChartMeta {
                difficulty: row.get(1)?,
                sort_rank: row.get(2)?,
                rating: row.get(3)?,
                charter: row.get(4)?,
                bpm_min: row.get(5)?,
                bpm_max: row.get(6)?,
                chart_offset_ms: row.get(7)?,
                note_count: row.get(8)?,
                tap_count: row.get(9)?,
                drag_count: row.get(10)?,
                hold_count: row.get(11)?,
                flick_count: row.get(12)?,
                audio_rel_path: row.get(13)?,
                cover_rel_path: row.get(14)?,
                chart_rel_path: row.get(15)?,
            },
        ))
    })?;
    for row in chart_rows {
        let (song_id, chart) = row?;
        if let Some(meta) = map.get_mut(&song_id) {
            meta.charts.push(chart);
        }
    }
    Ok(map)
}

pub fn load_meta(conn: &Connection, song_id: &str) -> Result<Option<PhigrosSongMeta>> {
    let meta = conn
        .query_row(
            "SELECT phigros_id, chapter, composer, illustrator,
                    selected_difficulty, hitsound_mode, hitsound_volume, hitsound_offset_ms
             FROM phigros_songs WHERE song_id = ?1",
            params![song_id],
            |row| {
                Ok(PhigrosSongMeta {
                    phigros_id: row.get(0)?,
                    chapter: row.get(1)?,
                    composer: row.get(2)?,
                    illustrator: row.get(3)?,
                    selected_difficulty: row.get(4)?,
                    hitsound_mode: row.get(5)?,
                    hitsound_volume: row.get(6)?,
                    hitsound_offset_ms: row.get(7)?,
                    charts: Vec::new(),
                })
            },
        )
        .optional()?;
    let Some(mut meta) = meta else {
        return Ok(None);
    };
    meta.charts = conn
        .prepare(
            "SELECT difficulty, sort_rank, rating, charter, bpm_min, bpm_max,
                    chart_offset_ms, note_count, tap_count, drag_count, hold_count,
                    flick_count, audio_rel_path, cover_rel_path, chart_rel_path
             FROM phigros_charts
             WHERE song_id = ?1
             ORDER BY sort_rank, difficulty",
        )?
        .query_map(params![song_id], |row| {
            Ok(PhigrosChartMeta {
                difficulty: row.get(0)?,
                sort_rank: row.get(1)?,
                rating: row.get(2)?,
                charter: row.get(3)?,
                bpm_min: row.get(4)?,
                bpm_max: row.get(5)?,
                chart_offset_ms: row.get(6)?,
                note_count: row.get(7)?,
                tap_count: row.get(8)?,
                drag_count: row.get(9)?,
                hold_count: row.get(10)?,
                flick_count: row.get(11)?,
                audio_rel_path: row.get(12)?,
                cover_rel_path: row.get(13)?,
                chart_rel_path: row.get(14)?,
            })
        })?
        .collect::<rusqlite::Result<_>>()?;
    Ok(Some(meta))
}

pub fn set_difficulty(song_id: &str, difficulty: &str) -> Result<()> {
    let conn = connection::open()?;
    let exists: bool = conn.query_row(
        "SELECT EXISTS(SELECT 1 FROM phigros_charts WHERE song_id = ?1 AND difficulty = ?2)",
        params![song_id, difficulty],
        |row| row.get(0),
    )?;
    if !exists {
        return Err(LibraryError::new("该歌曲没有对应的 Phigros 难度谱面。"));
    }
    let updated = conn.execute(
        "UPDATE phigros_songs SET selected_difficulty = ?1 WHERE song_id = ?2",
        params![difficulty, song_id],
    )?;
    if updated == 0 {
        return Err(songs::song_not_found());
    }
    Ok(())
}

pub fn set_hitsound(
    song_id: &str,
    mode: &str,
    volume: Option<f64>,
    offset_ms: Option<i32>,
) -> Result<()> {
    if !matches!(mode, "global" | "on" | "off") {
        return Err(LibraryError::new("无效的打击音效模式。"));
    }
    let clamped_vol = volume.map(|v| v.clamp(0.0, 1.5));
    let clamped_offset = offset_ms.map(|o| o.clamp(-500, 500));
    let conn = connection::open()?;
    let updated = conn.execute(
        "UPDATE phigros_songs
         SET hitsound_mode = ?1, hitsound_volume = ?2, hitsound_offset_ms = ?3
         WHERE song_id = ?4",
        params![mode, clamped_vol, clamped_offset, song_id],
    )?;
    if updated == 0 {
        return Err(songs::song_not_found());
    }
    Ok(())
}

/// Imports an extracted Phigros bundle directory (`phigros_manifest.json` + media/charts/se).
pub fn import_package(package_dir: &Path) -> Result<PhigrosImportResult> {
    if !package_dir.is_dir() {
        return Err(LibraryError::new("Phigros 资源目录不存在。"));
    }
    let manifest_path = package_dir.join("phigros_manifest.json");
    if !manifest_path.is_file() {
        return Err(LibraryError::new("目录中缺少 phigros_manifest.json。"));
    }
    let raw_manifest = fs::read_to_string(&manifest_path)?;
    let manifest: Manifest = serde_json::from_str(&raw_manifest)
        .map_err(|e| LibraryError::new(format!("解析 phigros_manifest.json 失败: {e}")))?;

    paths::ensure_dirs()?;

    // Copy official SE samples (`tap.wav`, `drag.wav`, `flick.wav`) into `<library>/phigros/se/`.
    let se_dest_dir = paths::phigros_se_dir();
    fs::create_dir_all(&se_dest_dir)?;
    for (kind, rel_src) in &manifest.se {
        let src = safe_join(package_dir, rel_src)?;
        if src.is_file() {
            let ext = src
                .extension()
                .and_then(|e| e.to_str())
                .unwrap_or("wav");
            let dst_name = format!("{kind}.{ext}");
            fs::copy(&src, se_dest_dir.join(dst_name))?;
        }
    }

    let mut conn = connection::open()?;
    let tx = conn.transaction()?;
    let playlist = ensure_phigros_playlist(&tx)?;
    let mut next_order: i64 = tx.query_row(
        "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM playlist_songs WHERE playlist_id = ?1",
        params![playlist.id],
        |row| row.get(0),
    )?;

    let mut imported_count = 0i32;
    let mut updated_count = 0i32;
    let mut total_charts = 0i32;

    for item in &manifest.songs {
        if item.charts.is_empty() {
            continue;
        }
        let main_audio_src = safe_join(package_dir, &item.audio_file)?;
        if !main_audio_src.is_file() {
            continue;
        }

        let safe_id = sanitize_id(&item.phigros_id);
        let main_rel_audio = copy_managed_audio(&main_audio_src, &format!("phi_{safe_id}"))?;
        let main_cover_rel = match item.cover_file.as_deref() {
            Some(rel) => copy_managed_cover(
                &safe_join(package_dir, rel)?,
                &format!("phi_{safe_id}"),
            )?,
            None => None,
        };

        let existing_song_id: Option<String> = tx
            .query_row(
                "SELECT song_id FROM phigros_songs WHERE phigros_id = ?1",
                params![item.phigros_id],
                |row| row.get(0),
            )
            .optional()?;

        let song_id = if let Some(existing_id) = existing_song_id {
            updated_count += 1;
            tx.execute(
                "UPDATE songs
                 SET title = ?1, artist = ?2, album = ?3, cover_path = COALESCE(?4, cover_path),
                     updated_at = CURRENT_TIMESTAMP
                 WHERE id = ?5",
                params![
                    item.title,
                    item.composer,
                    item.chapter,
                    main_cover_rel,
                    existing_id
                ],
            )?;
            // Refresh primary audio metadata if file updated.
            upsert_primary_audio(&tx, &existing_id, &main_rel_audio, &main_audio_src, item)?;
            existing_id
        } else {
            imported_count += 1;
            let new_id = Uuid::new_v4().to_string();
            tx.execute(
                "INSERT INTO songs (id, title, artist, album, cover_path, rating)
                 VALUES (?1, ?2, ?3, ?4, ?5, 0)",
                params![new_id, item.title, item.composer, item.chapter, main_cover_rel],
            )?;
            upsert_primary_audio(&tx, &new_id, &main_rel_audio, &main_audio_src, item)?;
            new_id
        };

        let existing_selection: Option<String> = tx
            .query_row(
                "SELECT selected_difficulty FROM phigros_songs WHERE song_id = ?1",
                params![song_id],
                |row| row.get(0),
            )
            .optional()?;
        let selected_diff = existing_selection
            .filter(|d| item.charts.iter().any(|c| c.difficulty == *d))
            .or_else(|| {
                item.default_difficulty
                    .clone()
                    .filter(|d| item.charts.iter().any(|c| c.difficulty == *d))
            })
            .or_else(|| {
                ["IN", "AT", "HD", "EZ", "SP", "Legacy"]
                    .into_iter()
                    .find(|d| item.charts.iter().any(|c| c.difficulty == *d))
                    .map(str::to_string)
            })
            .unwrap_or_else(|| item.charts[0].difficulty.clone());

        tx.execute(
            "INSERT INTO phigros_songs
                (song_id, phigros_id, chapter, composer, illustrator, selected_difficulty)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)
             ON CONFLICT(song_id) DO UPDATE SET
                chapter = excluded.chapter,
                composer = excluded.composer,
                illustrator = excluded.illustrator,
                selected_difficulty = ?6",
            params![
                song_id,
                item.phigros_id,
                item.chapter,
                item.composer,
                item.illustrator,
                selected_diff
            ],
        )?;

        tx.execute(
            "DELETE FROM phigros_charts WHERE song_id = ?1",
            params![song_id],
        )?;

        for chart in &item.charts {
            let chart_src = safe_join(package_dir, &chart.chart_file)?;
            if !chart_src.is_file() {
                continue;
            }
            let chart_dest_name = format!("{safe_id}_{}.json", sanitize_id(&chart.difficulty));
            let chart_dest = paths::phigros_charts_dir().join(&chart_dest_name);
            fs::create_dir_all(paths::phigros_charts_dir())?;
            fs::copy(&chart_src, &chart_dest)?;
            let chart_rel = paths::phigros_chart_relative_path(&chart_dest_name);

            let diff_audio_rel = match chart.audio_file.as_deref() {
                Some(rel) => {
                    let src = safe_join(package_dir, rel)?;
                    if src.is_file() {
                        Some(copy_managed_audio(
                            &src,
                            &format!("phi_{safe_id}_{}", sanitize_id(&chart.difficulty)),
                        )?)
                    } else {
                        None
                    }
                }
                None => None,
            };

            let diff_cover_rel = match chart.cover_file.as_deref() {
                Some(rel) => {
                    let src = safe_join(package_dir, rel)?;
                    if src.is_file() {
                        copy_managed_cover(
                            &src,
                            &format!("phi_{safe_id}_{}", sanitize_id(&chart.difficulty)),
                        )?
                    } else {
                        None
                    }
                }
                None => None,
            };

            tx.execute(
                "INSERT INTO phigros_charts (
                    song_id, difficulty, sort_rank, rating, charter, bpm_min, bpm_max,
                    chart_offset_ms, note_count, tap_count, drag_count, hold_count,
                    flick_count, audio_rel_path, cover_rel_path, chart_rel_path
                 ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)",
                params![
                    song_id,
                    chart.difficulty,
                    chart.sort_rank,
                    chart.rating,
                    chart.charter,
                    chart.bpm_min,
                    chart.bpm_max,
                    chart.chart_offset_ms,
                    chart.note_count,
                    chart.tap_count,
                    chart.drag_count,
                    chart.hold_count,
                    chart.flick_count,
                    diff_audio_rel,
                    diff_cover_rel,
                    chart_rel,
                ],
            )?;
            total_charts += 1;
        }

        let inserted = tx.execute(
            "INSERT OR IGNORE INTO playlist_songs (playlist_id, song_id, sort_order)
             VALUES (?1, ?2, ?3)",
            params![playlist.id, song_id, next_order],
        )?;
        if inserted > 0 {
            next_order += 1;
        }
    }
    tx.commit()?;

    Ok(PhigrosImportResult {
        playlist_id: playlist.id,
        imported_count,
        updated_count,
        chart_count: total_charts,
    })
}

fn upsert_primary_audio(
    tx: &rusqlite::Transaction<'_>,
    song_id: &str,
    rel_audio: &str,
    src_path: &Path,
    item: &ManifestSong,
) -> Result<()> {
    let dest_path = paths::audio_file(rel_audio)
        .ok_or_else(|| LibraryError::new("目标音频路径无效。"))?;
    let file_size = dest_path.metadata()?.len() as i64;
    let md5 = probe::file_md5(&dest_path)?;
    let format = dest_path
        .extension()
        .and_then(|e| e.to_str())
        .map(|s| s.to_uppercase());
    let (bitrate, sample_rate, duration, bit_depth) = match probe::open(&dest_path) {
        Ok(file) => {
            let p = probe::properties(&dest_path, &file);
            (
                p.bitrate,
                p.sample_rate.or(item.sample_rate),
                if p.duration > 0.0 {
                    p.duration
                } else {
                    item.duration.unwrap_or(0.0)
                },
                p.bit_depth,
            )
        }
        Err(_) => (None, item.sample_rate, item.duration.unwrap_or(0.0), Some(16)),
    };
    let orig_name = src_path
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| format!("{}.flac", item.title));

    let existing_ver: Option<String> = tx
        .query_row(
            "SELECT id FROM audio_files WHERE song_id = ?1 AND is_primary = 1 LIMIT 1",
            params![song_id],
            |row| row.get(0),
        )
        .optional()?;
    if let Some(ver_id) = existing_ver {
        tx.execute(
            "UPDATE audio_files
             SET filepath = ?1, original_name = ?2, format = ?3, bitrate = ?4,
                 sample_rate = ?5, duration = ?6, file_size = ?7, md5 = ?8,
                 bit_depth = ?9, metadata_scanned = 1
             WHERE id = ?10",
            params![
                rel_audio,
                orig_name,
                format,
                bitrate,
                sample_rate,
                duration,
                file_size,
                md5,
                bit_depth,
                ver_id,
            ],
        )?;
    } else {
        tx.execute(
            "INSERT INTO audio_files (
                id, song_id, filepath, original_name, format, bitrate,
                sample_rate, duration, file_size, is_enabled, is_primary,
                md5, bit_depth, loudness, metadata_scanned
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 1, 1, ?10, ?11, NULL, 1)",
            params![
                Uuid::new_v4().to_string(),
                song_id,
                rel_audio,
                orig_name,
                format,
                bitrate,
                sample_rate,
                duration,
                file_size,
                md5,
                bit_depth,
            ],
        )?;
    }
    Ok(())
}

fn copy_managed_audio(src: &Path, stem: &str) -> Result<String> {
    let ext = src
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("flac");
    let file_name = format!("{stem}.{ext}");
    let dest = paths::files_dir().join(&file_name);
    fs::create_dir_all(paths::files_dir())?;
    let need_copy = match (src.metadata(), dest.metadata()) {
        (Ok(sm), Ok(dm)) => sm.len() != dm.len() || probe::file_md5(src).ok() != probe::file_md5(&dest).ok(),
        _ => true,
    };
    if need_copy {
        fs::copy(src, &dest)?;
    }
    Ok(paths::audio_relative_path(&file_name))
}

fn copy_managed_cover(src: &Path, stem: &str) -> Result<Option<String>> {
    if !src.is_file() {
        return Ok(None);
    }
    let ext = src
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("jpg");
    let file_name = format!("{stem}.{ext}");
    let dest = paths::covers_dir().join(&file_name);
    fs::create_dir_all(paths::covers_dir())?;
    let need_copy = match (src.metadata(), dest.metadata()) {
        (Ok(sm), Ok(dm)) => sm.len() != dm.len(),
        _ => true,
    };
    if need_copy {
        fs::copy(src, &dest)?;
    }
    Ok(Some(paths::cover_relative_path(&file_name)))
}

fn safe_join(root: &Path, rel: &str) -> Result<std::path::PathBuf> {
    let clean = rel.replace('\\', "/");
    if clean.starts_with('/') || clean.contains("..") || clean.contains('\0') {
        return Err(LibraryError::new(format!("非法资源路径: {rel}")));
    }
    let mut out = root.to_path_buf();
    for part in clean.split('/').filter(|p| !p.is_empty()) {
        out.push(part);
    }
    Ok(out)
}

fn fnv1a64(bytes: &[u8]) -> u64 {
    let mut hash = 0xcbf29ce484222325u64;
    for &b in bytes {
        hash ^= u64::from(b);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

fn sanitize_id(raw: &str) -> String {
    let cleaned: String = raw
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | '.') {
                c
            } else {
                '_'
            }
        })
        .collect();
    if cleaned == raw {
        cleaned
    } else {
        format!("{cleaned}_{:08x}", fnv1a64(raw.as_bytes()) as u32)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::audio::test_support::TestWav;
    use crate::library::{maintenance, test_support::TestLibrary};

    fn write_test_package(dir: &Path) {
        let wav = TestWav::pcm(44100, 2, 16, &vec![0i32; 4410]);
        fs::create_dir_all(dir.join("audio")).unwrap();
        fs::create_dir_all(dir.join("charts")).unwrap();
        fs::create_dir_all(dir.join("se")).unwrap();
        fs::copy(wav.path(), dir.join("audio/glaciaxion.wav")).unwrap();
        fs::copy(wav.path(), dir.join("se/tap.wav")).unwrap();
        fs::write(
            dir.join("charts/glac_ez.json"),
            r#"{"notes":[[0.5,1],[1.0,2]]}"#,
        )
        .unwrap();
        fs::write(
            dir.join("charts/glac_in.json"),
            r#"{"notes":[[0.25,1],[0.5,2],[0.75,3],[1.0,4]]}"#,
        )
        .unwrap();
        fs::write(
            dir.join("phigros_manifest.json"),
            r#"{
                "se": {"tap": "se/tap.wav"},
                "songs": [{
                    "phigros_id": "Glaciaxion.SunsetRay.0",
                    "title": "Glaciaxion",
                    "composer": "SunsetRay",
                    "illustrator": "Tester",
                    "chapter": "过去的章节",
                    "audio_file": "audio/glaciaxion.wav",
                    "duration": 0.1,
                    "sample_rate": 44100,
                    "charts": [
                        {
                            "difficulty": "EZ",
                            "sort_rank": 0,
                            "rating": 2.0,
                            "charter": "ChartA",
                            "bpm_min": 140.0,
                            "bpm_max": 140.0,
                            "chart_offset_ms": 0,
                            "note_count": 2,
                            "tap_count": 1,
                            "drag_count": 1,
                            "hold_count": 0,
                            "flick_count": 0,
                            "chart_file": "charts/glac_ez.json"
                        },
                        {
                            "difficulty": "IN",
                            "sort_rank": 2,
                            "rating": 13.5,
                            "charter": "ChartB",
                            "bpm_min": 140.0,
                            "bpm_max": 140.0,
                            "chart_offset_ms": 0,
                            "note_count": 4,
                            "tap_count": 1,
                            "drag_count": 1,
                            "hold_count": 1,
                            "flick_count": 1,
                            "chart_file": "charts/glac_in.json"
                        }
                    ]
                }]
            }"#,
        )
        .unwrap();
    }

    #[test]
    fn imports_phigros_package_and_preserves_user_difficulty_and_hitsound_on_reimport() {
        let lib = TestLibrary::new();
        let pkg = lib.scratch_dir().join("pkg");
        write_test_package(&pkg);

        let first = import_package(&pkg).unwrap();
        assert_eq!(first.imported_count, 1);
        assert_eq!(first.updated_count, 0);
        assert_eq!(first.chart_count, 2);

        let pls = playlists::all().unwrap();
        assert_eq!(pls.len(), 1);
        assert_eq!(pls[0].kind.as_deref(), Some(PHIGROS_PLAYLIST_KIND));

        let loaded = songs::all().unwrap();
        assert_eq!(loaded.len(), 1);
        let song_id = loaded[0].id.clone();
        assert_eq!(
            loaded[0].phigros.as_ref().unwrap().selected_difficulty,
            "IN"
        );

        set_difficulty(&song_id, "EZ").unwrap();
        set_hitsound(&song_id, "off", Some(0.4), Some(-15)).unwrap();

        let second = import_package(&pkg).unwrap();
        assert_eq!(second.imported_count, 0);
        assert_eq!(second.updated_count, 1);

        let reloaded = songs::all().unwrap();
        let phi = reloaded[0].phigros.as_ref().unwrap();
        assert_eq!(phi.selected_difficulty, "EZ");
        assert_eq!(phi.hitsound_mode, "off");
        assert_eq!(phi.hitsound_volume, Some(0.4));
        assert_eq!(phi.hitsound_offset_ms, Some(-15));

        maintenance::reset().unwrap();
        assert!(songs::all().unwrap().is_empty());
        assert!(paths::phigros_se_dir().is_dir());
    }

    #[test]
    fn non_ascii_phigros_ids_do_not_collide_on_managed_paths() {
        let lib = TestLibrary::new();
        let pkg = lib.scratch_dir().join("pkg_cjk");
        let wav = TestWav::pcm(44100, 2, 16, &vec![0i32; 4410]);
        fs::create_dir_all(pkg.join("audio")).unwrap();
        fs::create_dir_all(pkg.join("charts")).unwrap();
        fs::create_dir_all(pkg.join("se")).unwrap();
        fs::copy(wav.path(), pkg.join("audio/a.wav")).unwrap();
        fs::copy(wav.path(), pkg.join("audio/b.wav")).unwrap();
        fs::copy(wav.path(), pkg.join("se/tap.wav")).unwrap();
        fs::write(pkg.join("charts/a.json"), r#"{"notes":[[0.5,1]]}"#).unwrap();
        fs::write(pkg.join("charts/b.json"), r#"{"notes":[[0.8,2]]}"#).unwrap();
        fs::write(
            pkg.join("phigros_manifest.json"),
            r#"{
                "se": {"tap": "se/tap.wav"},
                "songs": [
                    {
                        "phigros_id": "聖夜讃歌.A39.0",
                        "title": "聖夜讃歌",
                        "composer": "A39",
                        "chapter": "单曲精选集",
                        "audio_file": "audio/a.wav",
                        "charts": [{
                            "difficulty": "IN",
                            "sort_rank": 2,
                            "rating": 13.0,
                            "note_count": 1,
                            "tap_count": 1,
                            "drag_count": 0,
                            "hold_count": 0,
                            "flick_count": 0,
                            "chart_file": "charts/a.json"
                        }]
                    },
                    {
                        "phigros_id": "心の記憶.A39.0",
                        "title": "心の記憶",
                        "composer": "A39",
                        "chapter": "单曲精选集",
                        "audio_file": "audio/b.wav",
                        "charts": [{
                            "difficulty": "IN",
                            "sort_rank": 2,
                            "rating": 14.0,
                            "note_count": 1,
                            "tap_count": 0,
                            "drag_count": 1,
                            "hold_count": 0,
                            "flick_count": 0,
                            "chart_file": "charts/b.json"
                        }]
                    }
                ]
            }"#,
        )
        .unwrap();

        let res = import_package(&pkg).unwrap();
        assert_eq!(res.imported_count, 2);
        let all = songs::all().unwrap();
        assert_eq!(all.len(), 2);
        let conn = connection::open().unwrap();
        let file0: String = conn
            .query_row(
                "SELECT filepath FROM audio_files WHERE song_id = ?1",
                params![all[0].id],
                |r| r.get(0),
            )
            .unwrap();
        let file1: String = conn
            .query_row(
                "SELECT filepath FROM audio_files WHERE song_id = ?1",
                params![all[1].id],
                |r| r.get(0),
            )
            .unwrap();
        assert_ne!(file0, file1);
        assert_ne!(
            all[0].phigros.as_ref().unwrap().charts[0].chart_rel_path,
            all[1].phigros.as_ref().unwrap().charts[0].chart_rel_path
        );
    }
}
