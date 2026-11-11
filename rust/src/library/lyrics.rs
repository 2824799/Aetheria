//! Saved lyrics and local lyric discovery.
//!
//! A song keeps at most one lyric per scope, where a scope is either one
//! audio version or the song as a whole (`audio_version_id IS NULL`).

use super::{paths, probe, songs, LibraryError, Result};
use crate::database::connection;
use crate::models::{LocalLyricCandidate, SavedLyric};
use rusqlite::{params, Connection, OptionalExtension, Row};
use std::fs;
use uuid::Uuid;

const LYRIC_COLUMNS: &str = "id, song_id, audio_version_id, source, source_id, title, artist, \
     content, translation, romanized, offset_ms, is_selected, updated_at";

/// Metadata lines some lyric providers embed (often huge base64 payloads).
const JUNK_LINE_PREFIXES: [&str; 5] = ["[awlrc:", "[kana:", "[encoding:", "[re:", "[ve:"];

/// A single unbroken token longer than this is a payload, not a lyric line.
const MAX_UNBROKEN_LINE_LEN: usize = 500;

/// A lyric about to be saved for one scope of a song.
pub struct NewLyric {
    pub song_id: String,
    pub audio_version_id: Option<String>,
    pub source: String,
    pub source_id: Option<String>,
    pub title: String,
    pub artist: Option<String>,
    pub content: String,
    pub translation: Option<String>,
    pub romanized: Option<String>,
    pub offset_ms: i32,
}

fn lyric_from_row(row: &Row<'_>) -> rusqlite::Result<SavedLyric> {
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
        offset_ms: row.get::<_, Option<i32>>(10)?.unwrap_or(0),
        is_selected: row.get::<_, Option<i32>>(11)?.unwrap_or(0) != 0,
        updated_at: row.get::<_, Option<String>>(12)?.unwrap_or_default(),
    })
}

/// Normalizes line endings and drops blank lines and provider junk.
pub fn sanitize_content(content: &str) -> String {
    content
        .lines()
        .flat_map(|line| line.split('\r'))
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .filter(|line| {
            let lower = line.to_ascii_lowercase();
            !JUNK_LINE_PREFIXES
                .iter()
                .any(|prefix| lower.starts_with(prefix))
        })
        .filter(|line| line.len() <= MAX_UNBROKEN_LINE_LEN || line.contains(' '))
        .collect::<Vec<_>>()
        .join("\n")
}

/// Rewrites lyrics saved by early builds that still contain provider junk.
pub(super) fn scrub_legacy_tags(conn: &Connection) -> Result<()> {
    let dirty = conn
        .prepare(
            "SELECT id, content FROM lyrics
             WHERE content LIKE '%[awlrc:%' OR content LIKE '%[kana:%'",
        )?
        .query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    for (id, content) in dirty {
        conn.execute(
            "UPDATE lyrics SET content = ?1 WHERE id = ?2",
            params![sanitize_content(&content), id],
        )?;
    }
    Ok(())
}

fn ensure_version_belongs_to_song(
    conn: &Connection,
    song_id: &str,
    version_id: &str,
) -> Result<()> {
    let belongs: bool = conn.query_row(
        "SELECT EXISTS(SELECT 1 FROM audio_files WHERE id = ?1 AND song_id = ?2)",
        params![version_id, song_id],
        |row| row.get(0),
    )?;
    if !belongs {
        return Err(LibraryError::new("歌词绑定的音源版本不属于当前歌曲。"));
    }
    Ok(())
}

fn load(conn: &Connection, lyric_id: &str) -> Result<SavedLyric> {
    conn.query_row(
        &format!("SELECT {LYRIC_COLUMNS} FROM lyrics WHERE id = ?1"),
        params![lyric_id],
        lyric_from_row,
    )
    .optional()?
    .ok_or_else(|| LibraryError::new("歌词不存在。"))
}

/// The lyric to show for a song: the one bound to `audio_version_id` when it
/// exists, otherwise the song-wide one.
pub fn selected(song_id: &str, audio_version_id: Option<&str>) -> Result<Option<SavedLyric>> {
    let conn = connection::open()?;
    if let Some(version_id) = audio_version_id {
        ensure_version_belongs_to_song(&conn, song_id, version_id)?;
    }
    // `IS ?2` matches the requested version; NULL-version rows sort last.
    Ok(conn
        .query_row(
            &format!(
                "SELECT {LYRIC_COLUMNS} FROM lyrics
                 WHERE song_id = ?1 AND is_selected = 1
                   AND (audio_version_id IS ?2 OR audio_version_id IS NULL)
                 ORDER BY audio_version_id IS NULL, updated_at DESC, rowid DESC
                 LIMIT 1"
            ),
            params![song_id, audio_version_id],
            lyric_from_row,
        )
        .optional()?)
}

/// Ids of every song that has at least one non-empty saved lyric.
pub fn song_ids_with_lyrics() -> Result<Vec<String>> {
    let conn = connection::open()?;
    let ids = conn
        .prepare("SELECT DISTINCT song_id FROM lyrics WHERE TRIM(content) <> ''")?
        .query_map([], |row| row.get(0))?
        .collect::<rusqlite::Result<_>>()?;
    Ok(ids)
}

/// Saves `lyric` as the lyric of its scope, replacing the previous one.
pub fn save(lyric: NewLyric) -> Result<SavedLyric> {
    let content = sanitize_content(&lyric.content);
    if content.is_empty() {
        return Err(LibraryError::new("歌词内容不能为空。"));
    }
    let non_blank = |value: Option<String>| {
        value
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
    };

    let mut conn = connection::open()?;
    let tx = conn.transaction()?;
    if !songs::exists(&tx, &lyric.song_id)? {
        return Err(songs::song_not_found());
    }
    if let Some(version_id) = lyric.audio_version_id.as_deref() {
        ensure_version_belongs_to_song(&tx, &lyric.song_id, version_id)?;
    }
    tx.execute(
        "DELETE FROM lyrics WHERE song_id = ?1 AND audio_version_id IS ?2",
        params![lyric.song_id, lyric.audio_version_id],
    )?;
    let id = Uuid::new_v4().to_string();
    tx.execute(
        &format!(
            "INSERT INTO lyrics ({LYRIC_COLUMNS})
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, 1, CURRENT_TIMESTAMP)"
        ),
        params![
            id,
            lyric.song_id,
            lyric.audio_version_id,
            lyric.source,
            lyric.source_id,
            lyric.title.trim(),
            non_blank(lyric.artist),
            content,
            non_blank(lyric.translation),
            non_blank(lyric.romanized),
            lyric.offset_ms,
        ],
    )?;
    let saved = load(&tx, &id)?;
    tx.commit()?;
    Ok(saved)
}

pub fn update_offset(lyric_id: &str, offset_ms: i32) -> Result<SavedLyric> {
    let conn = connection::open()?;
    conn.execute(
        "UPDATE lyrics SET offset_ms = ?1, updated_at = CURRENT_TIMESTAMP WHERE id = ?2",
        params![offset_ms, lyric_id],
    )?;
    load(&conn, lyric_id)
}

/// Removes the lyrics visible from one scope: the given version's lyric plus
/// the song-wide one, or every lyric of the song when no version is given.
///
/// Returns whether the song still has lyrics (bound to other versions).
pub fn clear(song_id: &str, audio_version_id: Option<&str>) -> Result<bool> {
    let mut conn = connection::open()?;
    let tx = conn.transaction()?;
    match audio_version_id {
        Some(version_id) => tx.execute(
            "DELETE FROM lyrics
             WHERE song_id = ?1 AND (audio_version_id = ?2 OR audio_version_id IS NULL)",
            params![song_id, version_id],
        )?,
        None => tx.execute("DELETE FROM lyrics WHERE song_id = ?1", params![song_id])?,
    };
    let has_lyrics: bool = tx.query_row(
        "SELECT EXISTS(SELECT 1 FROM lyrics WHERE song_id = ?1 AND TRIM(content) <> '')",
        params![song_id],
        |row| row.get(0),
    )?;
    if !has_lyrics {
        // The pre-`lyrics`-table column would otherwise keep flagging the song.
        tx.execute(
            "UPDATE songs SET lyrics = NULL WHERE id = ?1",
            params![song_id],
        )?;
    }
    tx.commit()?;
    Ok(has_lyrics)
}

/// Lyrics found on disk for a song: embedded tags, `.lrc` sidecars and the
/// legacy `songs.lyrics` column, de-duplicated by content.
pub fn local_candidates(
    song_id: &str,
    audio_version_id: Option<&str>,
) -> Result<Vec<LocalLyricCandidate>> {
    let conn = connection::open()?;
    let (title, artist, legacy_lyrics): (String, Option<String>, Option<String>) = conn
        .query_row(
            "SELECT title, artist, lyrics FROM songs WHERE id = ?1",
            params![song_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .optional()?
        .ok_or_else(songs::song_not_found)?;

    if let Some(version_id) = audio_version_id {
        ensure_version_belongs_to_song(&conn, song_id, version_id)?;
    }
    let version: Option<(String, String, String)> = conn
        .query_row(
            "SELECT id, filepath, original_name FROM audio_files
             WHERE song_id = ?1 AND (?2 IS NULL OR id = ?2)
             ORDER BY is_primary DESC, rowid LIMIT 1",
            params![song_id, audio_version_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .optional()?;

    let mut candidates = Vec::<LocalLyricCandidate>::new();
    let mut push = |source: &str, source_id: String, content: &str| {
        let content = sanitize_content(content);
        if content.is_empty() || candidates.iter().any(|known| known.content == content) {
            return;
        }
        candidates.push(LocalLyricCandidate {
            source: source.to_string(),
            source_id: Some(source_id),
            title: title.clone(),
            artist: artist.clone(),
            content,
        });
    };

    if let Some((version_id, stored_path, original_name)) = version {
        if let Some(audio_path) = paths::audio_file(&stored_path) {
            if let Some(content) = probe::embedded_lyrics(&audio_path) {
                push("local_embedded", version_id, &content);
            }
            // Sidecar copied at import time, then one dropped in by hand
            // under the file's original name.
            let mut sidecars = vec![audio_path.with_extension("lrc")];
            if let Some(name) = paths::file_name(&original_name) {
                sidecars.push(paths::files_dir().join(name).with_extension("lrc"));
            }
            for sidecar in sidecars {
                if let Ok(content) = fs::read_to_string(&sidecar) {
                    push(
                        "local_lrc",
                        sidecar.to_string_lossy().into_owned(),
                        &content,
                    );
                }
            }
        }
    }
    if let Some(content) = legacy_lyrics {
        push("legacy_song", song_id.to_string(), &content);
    }
    Ok(candidates)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitize_drops_provider_junk_and_blank_lines() {
        let dirty = "[offset:0]\r\n[00:01.00]Hello world\n[awlrc:lrc:W29mZnNld...]\n\n[KANA:11111]\r[00:05.00]Second line\n";
        assert_eq!(
            sanitize_content(dirty),
            "[offset:0]\n[00:01.00]Hello world\n[00:05.00]Second line"
        );
    }

    #[test]
    fn sanitize_drops_oversized_unbroken_tokens() {
        let payload = format!("[00:02.00]{}", "A".repeat(600));
        assert!(sanitize_content(&payload).is_empty());
        let prose = format!("[00:02.00]{}", "word ".repeat(150));
        assert!(!sanitize_content(&prose).is_empty());
    }
}
