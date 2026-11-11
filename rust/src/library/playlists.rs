//! Manually ordered playlists.

use super::{LibraryError, Result};
use crate::database::connection;
use crate::models::Playlist;
use rusqlite::{params, Row};
use uuid::Uuid;

const PLAYLIST_COLUMNS: &str = "id, name, description, created_at";

fn playlist_from_row(row: &Row<'_>) -> rusqlite::Result<Playlist> {
    Ok(Playlist {
        id: row.get(0)?,
        name: row.get(1)?,
        description: row.get(2)?,
        created_at: row.get::<_, Option<String>>(3)?.unwrap_or_default(),
    })
}

pub fn all() -> Result<Vec<Playlist>> {
    let conn = connection::open()?;
    let playlists = conn
        .prepare(&format!(
            "SELECT {PLAYLIST_COLUMNS} FROM playlists ORDER BY created_at, rowid"
        ))?
        .query_map([], playlist_from_row)?
        .collect::<rusqlite::Result<_>>()?;
    Ok(playlists)
}

pub fn create(name: &str) -> Result<Playlist> {
    let name = valid_name(name)?;
    let conn = connection::open()?;
    let id = Uuid::new_v4().to_string();
    conn.execute(
        "INSERT INTO playlists (id, name, description) VALUES (?1, ?2, '')",
        params![id, name],
    )
    .map_err(name_conflict)?;
    Ok(conn.query_row(
        &format!("SELECT {PLAYLIST_COLUMNS} FROM playlists WHERE id = ?1"),
        params![id],
        playlist_from_row,
    )?)
}

pub fn rename(id: &str, name: &str) -> Result<()> {
    let name = valid_name(name)?;
    let conn = connection::open()?;
    conn.execute(
        "UPDATE playlists SET name = ?1 WHERE id = ?2",
        params![name, id],
    )
    .map_err(name_conflict)?;
    Ok(())
}

pub fn delete(id: &str) -> Result<()> {
    let mut conn = connection::open()?;
    let tx = conn.transaction()?;
    tx.execute(
        "DELETE FROM playlist_songs WHERE playlist_id = ?1",
        params![id],
    )?;
    tx.execute("DELETE FROM playlists WHERE id = ?1", params![id])?;
    tx.commit()?;
    Ok(())
}

/// Song ids in playlist order.
pub fn song_ids(playlist_id: &str) -> Result<Vec<String>> {
    let conn = connection::open()?;
    let ids = conn
        .prepare("SELECT song_id FROM playlist_songs WHERE playlist_id = ?1 ORDER BY sort_order")?
        .query_map(params![playlist_id], |row| row.get(0))?
        .collect::<rusqlite::Result<_>>()?;
    Ok(ids)
}

/// Appends songs to the end of a playlist, skipping ones it already contains.
pub fn add_songs(playlist_id: &str, song_ids: &[String]) -> Result<()> {
    let mut conn = connection::open()?;
    let tx = conn.transaction()?;
    let mut next_order: i64 = tx.query_row(
        "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM playlist_songs WHERE playlist_id = ?1",
        params![playlist_id],
        |row| row.get(0),
    )?;
    {
        let mut insert = tx.prepare(
            "INSERT OR IGNORE INTO playlist_songs (playlist_id, song_id, sort_order)
             VALUES (?1, ?2, ?3)",
        )?;
        for song_id in song_ids {
            next_order += insert.execute(params![playlist_id, song_id, next_order])? as i64;
        }
    }
    tx.commit()?;
    Ok(())
}

pub fn remove_songs(playlist_id: &str, song_ids: &[String]) -> Result<()> {
    let mut conn = connection::open()?;
    let tx = conn.transaction()?;
    {
        let mut delete =
            tx.prepare("DELETE FROM playlist_songs WHERE playlist_id = ?1 AND song_id = ?2")?;
        for song_id in song_ids {
            delete.execute(params![playlist_id, song_id])?;
        }
    }
    tx.commit()?;
    Ok(())
}

fn valid_name(name: &str) -> Result<&str> {
    let name = name.trim();
    if name.is_empty() {
        return Err(LibraryError::new("歌单名称不能为空。"));
    }
    Ok(name)
}

fn name_conflict(error: rusqlite::Error) -> LibraryError {
    match error.sqlite_error_code() {
        Some(rusqlite::ErrorCode::ConstraintViolation) => LibraryError::new("歌单名称已存在。"),
        _ => error.into(),
    }
}
