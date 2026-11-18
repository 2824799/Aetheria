//! Whole-library and per-file maintenance: reset, metadata refresh, export.

use super::{paths, probe, songs, LibraryError, Result};
use crate::audio::loudness;
use crate::database::{connection, schema};
use rusqlite::{params, OptionalExtension};
use std::fs;
use std::path::Path;

/// Deletes every song, tag, playlist and managed file, then restores the
/// default tags.
pub fn reset() -> Result<()> {
    let mut conn = connection::open()?;
    let tx = conn.transaction()?;
    // Children first so the foreign keys never dangle mid-transaction.
    tx.execute_batch(
        "DELETE FROM lyrics;
         DELETE FROM playlist_songs;
         DELETE FROM song_tags;
         DELETE FROM phigros_charts;
         DELETE FROM phigros_songs;
         DELETE FROM audio_files;
         DELETE FROM songs;
         DELETE FROM playlists;
         DELETE FROM tags;",
    )?;
    schema::seed_default_tags(&tx)?;
    tx.commit()?;

    // The rows are gone; files that cannot be removed right now (e.g. still
    // open in the player on Windows) are merely orphans.
    for dir in [
        paths::files_dir(),
        paths::covers_dir(),
        paths::phigros_dir(),
    ] {
        let _ = fs::remove_dir_all(&dir);
    }
    paths::ensure_dirs()?;
    Ok(())
}

/// Re-reads stream properties and measures full-file loudness for a version.
pub fn refresh_metadata(version_id: &str) -> Result<()> {
    let mut conn = connection::open()?;
    // A read snapshot ensures a concurrent package replacement cannot receive the old
    // file's measurements. SQLite rejects promotion of a stale snapshot to a writer.
    let tx = conn.transaction()?;
    let (stored, song_id, primary): (String, String, bool) = tx
        .query_row(
            "SELECT filepath, song_id, is_primary FROM audio_files WHERE id = ?1",
            [version_id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )
        .optional()?
        .ok_or_else(songs::version_not_found)?;
    let path = paths::audio_file(&stored).ok_or_else(missing_file)?;
    let profile = loudness::scan(&path);
    let mut scan_error = profile.as_ref().err().cloned();
    let properties = probe::open(&path)
        .ok()
        .map(|file| probe::properties(&path, &file));
    let mut chart_profiles = Vec::new();
    if primary {
        let mut stmt = tx.prepare(
            "SELECT DISTINCT audio_rel_path FROM phigros_charts
            WHERE song_id = ?1 AND audio_rel_path IS NOT NULL",
        )?;
        for rel in stmt.query_map([&song_id], |r| r.get::<_, String>(0))? {
            let rel = rel?;
            let measurement = match paths::audio_file(&rel) {
                Some(chart) if chart == path => profile.clone(),
                Some(chart) => loudness::scan(&chart),
                None => Err(missing_file().to_string()),
            };
            match measurement {
                Ok(profile) => chart_profiles.push((rel, profile.attenuation_db)),
                Err(message) => {
                    scan_error.get_or_insert(message);
                }
            }
        }
    }
    if let Some(p) = properties {
        tx.execute(
            "UPDATE audio_files SET bitrate = ?1, sample_rate = ?2,
            duration = CASE WHEN ?3 > 0 THEN ?3 ELSE duration END, bit_depth = ?4 WHERE id = ?5",
            params![
                p.bitrate,
                p.sample_rate,
                p.duration,
                p.bit_depth,
                version_id
            ],
        )?;
    }
    if let Ok(profile) = profile {
        tx.execute(
            "UPDATE audio_files SET integrated_lufs = ?1, balance_db = ?2, metadata_scanned = 1 WHERE id = ?3",
            params![profile.integrated, profile.attenuation_db, version_id],
        )?;
    }
    if scan_error.is_some() {
        // Keep the last valid measurement and mark this version for another attempt.
        tx.execute(
            "UPDATE audio_files SET metadata_scanned = 0 WHERE id = ?1",
            [version_id],
        )?;
    }
    for (rel, db) in chart_profiles {
        tx.execute(
            "UPDATE phigros_charts SET balance_db = ?1 WHERE song_id = ?2 AND audio_rel_path = ?3",
            params![db, song_id, rel],
        )?;
    }
    tx.commit()?;
    match scan_error {
        Some(message) => Err(LibraryError::new(message)),
        None => Ok(()),
    }
}

/// Copies a managed audio file out of the library. `destination` is either a
/// directory (the original file name is used) or the full target path.
pub fn export_version(version_id: &str, destination: &str) -> Result<String> {
    let conn = connection::open()?;
    let (stored, original_name): (String, String) = conn
        .query_row(
            "SELECT filepath, original_name FROM audio_files WHERE id = ?1",
            params![version_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()?
        .ok_or_else(songs::version_not_found)?;
    let source = paths::audio_file(&stored)
        .filter(|path| path.is_file())
        .ok_or_else(missing_file)?;

    let destination = Path::new(destination);
    let target = if destination.is_dir() {
        // `original_name` is untrusted (synced database): keep its last component only.
        let name = paths::file_name(&original_name)
            .map(std::ffi::OsStr::new)
            .or_else(|| source.file_name())
            .ok_or_else(|| LibraryError::new("文件名无效。"))?;
        destination.join(name)
    } else {
        destination.to_path_buf()
    };
    fs::copy(source, &target)?;
    Ok(target.to_string_lossy().into_owned())
}

fn missing_file() -> LibraryError {
    LibraryError::new("音乐库中找不到该音频文件。")
}
