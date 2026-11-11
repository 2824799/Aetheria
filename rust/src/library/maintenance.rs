//! Whole-library and per-file maintenance: reset, metadata refresh, export.

use super::{paths, probe, songs, LibraryError, Result};
use crate::audio::dsp;
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
         DELETE FROM audio_files;
         DELETE FROM songs;
         DELETE FROM playlists;
         DELETE FROM tags;",
    )?;
    schema::seed_default_tags(&tx)?;
    tx.commit()?;

    // The rows are gone; files that cannot be removed right now (e.g. still
    // open in the player on Windows) are merely orphans.
    for dir in [paths::files_dir(), paths::covers_dir()] {
        let _ = fs::remove_dir_all(&dir);
    }
    paths::ensure_dirs()?;
    Ok(())
}

/// Re-reads stream properties and measures full-file loudness for a version.
pub fn refresh_metadata(version_id: &str) -> Result<()> {
    let conn = connection::open()?;
    let stored: String = conn
        .query_row(
            "SELECT filepath FROM audio_files WHERE id = ?1",
            params![version_id],
            |row| row.get(0),
        )
        .optional()?
        .ok_or_else(songs::version_not_found)?;
    let path = paths::audio_file(&stored)
        .filter(|path| path.is_file())
        .ok_or_else(missing_file)?;

    // A failed measurement keeps the previous value instead of inventing one.
    let loudness = dsp::calculate_loudness(&path.to_string_lossy(), dsp::LoudnessScan::Full).ok();
    match probe::open(&path) {
        Ok(file) => {
            let properties = probe::properties(&path, &file);
            conn.execute(
                "UPDATE audio_files SET
                     bitrate = ?1,
                     sample_rate = ?2,
                     duration = CASE WHEN ?3 > 0 THEN ?3 ELSE duration END,
                     bit_depth = ?4,
                     loudness = COALESCE(?5, loudness),
                     metadata_scanned = 1
                 WHERE id = ?6",
                params![
                    properties.bitrate,
                    properties.sample_rate,
                    properties.duration,
                    properties.bit_depth,
                    loudness,
                    version_id,
                ],
            )?;
        }
        Err(_) => {
            conn.execute(
                "UPDATE audio_files SET loudness = COALESCE(?1, loudness), metadata_scanned = 1
                 WHERE id = ?2",
                params![loudness, version_id],
            )?;
        }
    }
    Ok(())
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
        let name = Path::new(&original_name)
            .file_name()
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
