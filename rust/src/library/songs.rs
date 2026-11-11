//! Song and audio-version queries and mutations.

use super::{paths, probe, LibraryError, Result};
use crate::database::connection;
use crate::models::{AudioVersion, Song, Tag};
use rusqlite::{params, Connection, OptionalExtension, Row};
use std::collections::HashMap;
use std::fs;
use std::path::Path;

const SONG_COLUMNS: &str = "id, title, artist, album, lyrics, cover_path, rating, created_at";
const VERSION_COLUMNS: &str = "id, song_id, filepath, original_name, format, bitrate, \
     sample_rate, duration, file_size, is_enabled, is_primary, md5, bit_depth, loudness, \
     metadata_scanned";

/// The UI shows this placeholder for songs without an artist; it must never
/// be stored as a real artist name.
const UNKNOWN_ARTIST: &str = "未知歌手";

fn song_from_row(row: &Row<'_>) -> rusqlite::Result<Song> {
    Ok(Song {
        id: row.get(0)?,
        title: row.get(1)?,
        artist: row.get(2)?,
        album: row.get(3)?,
        lyrics: row.get(4)?,
        cover_path: row.get(5)?,
        rating: row.get::<_, Option<i32>>(6)?.unwrap_or(0),
        created_at: row.get::<_, Option<String>>(7)?.unwrap_or_default(),
        versions: Vec::new(),
        tags: Vec::new(),
    })
}

fn version_from_row(row: &Row<'_>) -> rusqlite::Result<AudioVersion> {
    let flag = |index: usize| {
        row.get::<_, Option<i32>>(index)
            .map(|v| v.unwrap_or(0) != 0)
    };
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
        is_enabled: flag(9)?,
        is_primary: flag(10)?,
        md5: row.get(11)?,
        bit_depth: row.get(12)?,
        loudness: row.get(13)?,
        metadata_scanned: flag(14)?,
    })
}

pub(super) fn tag_from_row(row: &Row<'_>) -> rusqlite::Result<Tag> {
    Ok(Tag {
        id: row.get(0)?,
        name: row.get(1)?,
        color: row.get(2)?,
        category: row.get(3)?,
    })
}

/// Trims an artist name; blank input and the UI placeholder mean "no artist".
pub(super) fn normalize_artist(artist: &str) -> Option<String> {
    let trimmed = artist.trim();
    (!trimmed.is_empty() && trimmed != UNKNOWN_ARTIST).then(|| trimmed.to_string())
}

/// Every song with its versions and tags, loaded in three queries.
pub fn all() -> Result<Vec<Song>> {
    let conn = connection::open()?;
    let mut songs = conn
        .prepare(&format!(
            "SELECT {SONG_COLUMNS} FROM songs ORDER BY title COLLATE NOCASE, id"
        ))?
        .query_map([], song_from_row)?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    let index_by_id: HashMap<String, usize> = songs
        .iter()
        .enumerate()
        .map(|(index, song)| (song.id.clone(), index))
        .collect();

    let mut stmt = conn.prepare(&format!(
        "SELECT {VERSION_COLUMNS} FROM audio_files ORDER BY rowid"
    ))?;
    for version in stmt.query_map([], version_from_row)? {
        let version = version?;
        if let Some(&index) = index_by_id.get(&version.song_id) {
            songs[index].versions.push(version);
        }
    }

    let mut stmt = conn.prepare(
        "SELECT t.id, t.name, t.color, t.category, st.song_id
         FROM song_tags st JOIN tags t ON t.id = st.tag_id
         ORDER BY t.id",
    )?;
    let rows = stmt.query_map([], |row| Ok((tag_from_row(row)?, row.get::<_, String>(4)?)))?;
    for row in rows {
        let (tag, song_id) = row?;
        if let Some(&index) = index_by_id.get(&song_id) {
            songs[index].tags.push(tag);
        }
    }
    Ok(songs)
}

pub(super) fn load(conn: &Connection, song_id: &str) -> Result<Song> {
    let mut song = conn
        .query_row(
            &format!("SELECT {SONG_COLUMNS} FROM songs WHERE id = ?1"),
            params![song_id],
            song_from_row,
        )
        .optional()?
        .ok_or_else(song_not_found)?;
    song.versions = conn
        .prepare(&format!(
            "SELECT {VERSION_COLUMNS} FROM audio_files WHERE song_id = ?1 ORDER BY rowid"
        ))?
        .query_map(params![song_id], version_from_row)?
        .collect::<rusqlite::Result<_>>()?;
    song.tags = conn
        .prepare(
            "SELECT t.id, t.name, t.color, t.category
             FROM song_tags st JOIN tags t ON t.id = st.tag_id
             WHERE st.song_id = ?1 ORDER BY t.id",
        )?
        .query_map(params![song_id], tag_from_row)?
        .collect::<rusqlite::Result<_>>()?;
    Ok(song)
}

pub(super) fn load_version(conn: &Connection, version_id: &str) -> Result<AudioVersion> {
    conn.query_row(
        &format!("SELECT {VERSION_COLUMNS} FROM audio_files WHERE id = ?1"),
        params![version_id],
        version_from_row,
    )
    .optional()?
    .ok_or_else(version_not_found)
}

pub(super) fn song_not_found() -> LibraryError {
    LibraryError::new("歌曲不存在。")
}

pub(super) fn version_not_found() -> LibraryError {
    LibraryError::new("音源版本不存在。")
}

pub(super) fn exists(conn: &Connection, song_id: &str) -> Result<bool> {
    Ok(conn.query_row(
        "SELECT EXISTS(SELECT 1 FROM songs WHERE id = ?1)",
        params![song_id],
        |row| row.get(0),
    )?)
}

pub fn update_metadata(song_id: &str, title: &str, artist: &str) -> Result<()> {
    let title = title.trim();
    if title.is_empty() {
        return Err(LibraryError::new("歌曲名称不能为空。"));
    }
    let conn = connection::open()?;
    let updated = conn.execute(
        "UPDATE songs SET title = ?1, artist = ?2, updated_at = CURRENT_TIMESTAMP WHERE id = ?3",
        params![title, normalize_artist(artist), song_id],
    )?;
    if updated == 0 {
        return Err(song_not_found());
    }
    Ok(())
}

/// Deletes a song with everything that hangs off it, then its files.
pub fn delete(song_id: &str) -> Result<()> {
    let mut conn = connection::open()?;
    let tx = conn.transaction()?;
    let cover_path: Option<String> = tx
        .query_row(
            "SELECT cover_path FROM songs WHERE id = ?1",
            params![song_id],
            |row| row.get(0),
        )
        .optional()?
        .flatten();
    let audio_paths = tx
        .prepare("SELECT filepath FROM audio_files WHERE song_id = ?1")?
        .query_map(params![song_id], |row| row.get::<_, String>(0))?
        .collect::<rusqlite::Result<Vec<_>>>()?;

    // Explicit deletes keep databases created before the cascades consistent.
    for table in ["lyrics", "playlist_songs", "song_tags", "audio_files"] {
        tx.execute(
            &format!("DELETE FROM {table} WHERE song_id = ?1"),
            params![song_id],
        )?;
    }
    tx.execute("DELETE FROM songs WHERE id = ?1", params![song_id])?;
    tx.commit()?;

    // Files go last: a failed transaction must not leave rows without audio.
    for stored in &audio_paths {
        remove_audio_file(stored);
    }
    if let Some(cover) = cover_path.as_deref().and_then(paths::cover_file) {
        let _ = fs::remove_file(cover);
    }
    Ok(())
}

/// Deletes one audio version; when it was the primary, the oldest remaining
/// version takes over.
pub fn delete_version(version_id: &str) -> Result<()> {
    let mut conn = connection::open()?;
    let tx = conn.transaction()?;
    let (song_id, was_primary, stored_path): (String, bool, String) = tx
        .query_row(
            "SELECT song_id, COALESCE(is_primary, 0), filepath FROM audio_files WHERE id = ?1",
            params![version_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .optional()?
        .ok_or_else(version_not_found)?;

    tx.execute(
        "DELETE FROM lyrics WHERE audio_version_id = ?1",
        params![version_id],
    )?;
    tx.execute("DELETE FROM audio_files WHERE id = ?1", params![version_id])?;
    if was_primary {
        tx.execute(
            "UPDATE audio_files SET is_primary = 1, is_enabled = 1
             WHERE id = (SELECT id FROM audio_files WHERE song_id = ?1 ORDER BY rowid LIMIT 1)",
            params![song_id],
        )?;
    }
    tx.commit()?;

    remove_audio_file(&stored_path);
    Ok(())
}

pub fn set_primary_version(version_id: &str) -> Result<()> {
    let mut conn = connection::open()?;
    let tx = conn.transaction()?;
    let song_id: String = tx
        .query_row(
            "SELECT song_id FROM audio_files WHERE id = ?1",
            params![version_id],
            |row| row.get(0),
        )
        .optional()?
        .ok_or_else(version_not_found)?;
    tx.execute(
        "UPDATE audio_files SET is_primary = (id = ?1) WHERE song_id = ?2",
        params![version_id, song_id],
    )?;
    tx.execute(
        "UPDATE audio_files SET is_enabled = 1 WHERE id = ?1",
        params![version_id],
    )?;
    tx.commit()?;
    Ok(())
}

/// Returns the song's cover path, extracting embedded art from its primary
/// audio file when no cover has been stored yet (or the stored one is gone).
pub fn ensure_cover(song_id: &str) -> Result<Option<String>> {
    ensure_cover_with(&connection::open()?, song_id)
}

pub(super) fn ensure_cover_with(conn: &Connection, song_id: &str) -> Result<Option<String>> {
    let current: Option<String> = conn
        .query_row(
            "SELECT cover_path FROM songs WHERE id = ?1",
            params![song_id],
            |row| row.get(0),
        )
        .optional()?
        .flatten();
    if let Some(stored) = current {
        if paths::cover_file(&stored).is_some_and(|path| path.is_file()) {
            return Ok(Some(stored));
        }
    }

    let audio_path: Option<String> = conn
        .query_row(
            "SELECT filepath FROM audio_files WHERE song_id = ?1
             ORDER BY is_primary DESC, rowid LIMIT 1",
            params![song_id],
            |row| row.get(0),
        )
        .optional()?;
    let Some(audio_path) = audio_path.as_deref().and_then(paths::audio_file) else {
        return Ok(None);
    };
    let Some(cover_path) = extract_cover(&audio_path, song_id) else {
        return Ok(None);
    };
    conn.execute(
        "UPDATE songs SET cover_path = ?1, updated_at = CURRENT_TIMESTAMP WHERE id = ?2",
        params![cover_path, song_id],
    )?;
    Ok(Some(cover_path))
}

fn extract_cover(audio_path: &Path, song_id: &str) -> Option<String> {
    let (data, extension) = probe::embedded_cover(audio_path)?;
    let file_name = format!("{song_id}.{extension}");
    let destination = paths::cover_file(&file_name)?;
    fs::create_dir_all(destination.parent()?).ok()?;
    fs::write(destination, data).ok()?;
    Some(paths::cover_relative_path(&file_name))
}

/// Best-effort removal of a managed audio file and its sidecar lyrics.
pub(super) fn remove_audio_file(stored: &str) {
    if let Some(path) = paths::audio_file(stored) {
        let _ = fs::remove_file(path.with_extension("lrc"));
        let _ = fs::remove_file(path);
    }
}
