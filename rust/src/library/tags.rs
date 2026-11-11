//! Tag definitions and song tagging.

use super::{songs, LibraryError, Result};
use crate::database::connection;
use crate::models::Tag;
use rusqlite::params;

pub fn all() -> Result<Vec<Tag>> {
    let conn = connection::open()?;
    let tags = conn
        .prepare("SELECT id, name, color, category FROM tags ORDER BY category, name")?
        .query_map([], songs::tag_from_row)?
        .collect::<rusqlite::Result<_>>()?;
    Ok(tags)
}

pub fn add(name: &str, color: Option<String>, category: Option<String>) -> Result<Tag> {
    let name = valid_name(name)?;
    let conn = connection::open()?;
    conn.execute(
        "INSERT INTO tags (name, color, category) VALUES (?1, ?2, ?3)",
        params![name, color, category],
    )
    .map_err(name_conflict)?;
    Ok(Tag {
        id: conn.last_insert_rowid(),
        name: name.to_string(),
        color,
        category,
    })
}

pub fn update(
    tag_id: i64,
    name: &str,
    color: Option<String>,
    category: Option<String>,
) -> Result<()> {
    let name = valid_name(name)?;
    let conn = connection::open()?;
    conn.execute(
        "UPDATE tags SET name = ?1, color = ?2, category = ?3 WHERE id = ?4",
        params![name, color, category, tag_id],
    )
    .map_err(name_conflict)?;
    Ok(())
}

pub fn delete(tag_id: i64) -> Result<()> {
    let mut conn = connection::open()?;
    let tx = conn.transaction()?;
    tx.execute("DELETE FROM song_tags WHERE tag_id = ?1", params![tag_id])?;
    tx.execute("DELETE FROM tags WHERE id = ?1", params![tag_id])?;
    tx.commit()?;
    Ok(())
}

/// Binds (`bind = true`) or unbinds a tag on a song.
pub fn tag_song(song_id: &str, tag_id: i64, bind: bool) -> Result<()> {
    let conn = connection::open()?;
    let sql = if bind {
        "INSERT OR IGNORE INTO song_tags (song_id, tag_id) VALUES (?1, ?2)"
    } else {
        "DELETE FROM song_tags WHERE song_id = ?1 AND tag_id = ?2"
    };
    conn.execute(sql, params![song_id, tag_id])?;
    Ok(())
}

fn valid_name(name: &str) -> Result<&str> {
    let name = name.trim();
    if name.is_empty() {
        return Err(LibraryError::new("标签名称不能为空。"));
    }
    Ok(name)
}

fn name_conflict(error: rusqlite::Error) -> LibraryError {
    match error.sqlite_error_code() {
        Some(rusqlite::ErrorCode::ConstraintViolation) => LibraryError::new("标签名称已存在。"),
        _ => error.into(),
    }
}
